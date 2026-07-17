# Box EU Delivery Database Migrations

Independent Flyway deployment unit and Git repository for the Box EU Delivery CRM database. Backend mappings and migration contracts evolve in separate repositories, so compatible revisions and deployment order must be coordinated explicitly.

## Boundaries

- Flyway SQL is the only schema-evolution mechanism.
- Versioned migrations in `migrations/` are immutable after application.
- Every correction is a new migration version.
- Controlled reference data belongs only in repeatable SQL under `fixtures/`.
- Plaintext passwords, real accounts, personal data, and environment secrets never belong in migrations or fixtures.
- Account foreign keys do not cascade physical deletion; the current lifecycle exposes disable/reactivate rather than physical deletion.
- Project, membership, warehouse, project-warehouse, cargo, receipt, movement, and photo foreign keys use restrictive deletion. Relationships are removed explicitly, and referenced resources cannot be deleted.
- Application tables currently share one `crm` schema. A new PostgreSQL schema requires a concrete isolation, ownership, permissions, or lifecycle reason; schemas are not created per entity.
- Flyway's technical history table remains in `public`; no business tables are stored there.
- Flyway runs before the backend; Hibernate only validates the resulting schema.

## Current Schema

`V1__create_crm_schema_and_account_foundation.sql` creates the initial tables in the shared `crm` application schema:

- `crm.account` for account profile and lifecycle data;
- `crm.password_credential` for password hashes and mandatory-password-change state;
- `crm.account_category` for the optional `EMPLOYEE`, `SUPPLIER`, or `CLIENT` classification;
- `crm.access_role` for predefined role definitions whose identity includes `GLOBAL` or `PROJECT` scope;
- `crm.account_global_role` for platform-wide role assignments only.

`V2__complete_account_lifecycle.sql` adds account disable metadata, credential security versions, email-delivery metadata, hashed single-use password-reset tokens, durable audit events, and database constraints for the fixed role catalogue. `V3__align_password_reset_token_hash_type.sql` is the immutable follow-up that aligns the token hash mapping without editing an already-applied migration.

`V4__create_project_membership_and_outbox.sql` adds:

- `crm.project` with one preserved display name and case-insensitive uniqueness enforced by a functional `LOWER(BTRIM(name))` index, plus optional description, audit metadata, and optimistic version;
- `crm.project_member` and `crm.project_member_role` with restrictive foreign keys and strong project/account/role ownership;
- `crm.project_audit_event`, whose project UUID intentionally has no foreign key so deletion evidence survives;
- `crm.outbox_event` for retryable at-least-once business-event publication.

`V5__add_project_task_settings.sql` adds the globally unique task prefix and `Europe/Moscow` project time-zone default. `V6__create_task_foundation.sql` adds the race-safe per-project counter, task hierarchy, one conversation per root tree, exact participants, deadlines, statuses, priorities, and durable audit events. `V7__create_task_chat.sql` adds immutable context-scoped messages, closed reactions, and first-viewed receipts. `V8__create_chat_attachments.sql` adds the verified upload lifecycle, original/preview/playback variants, message linkage, and PostgreSQL-backed media-processing jobs. `V9__align_chat_attachment_duration_type.sql` aligns the attachment duration column with its Java mapping without editing an applied migration.

`V10__create_warehouse_catalog.sql` adds the global `crm.warehouse` catalogue, the explicit many-to-many `crm.project_warehouse` assignment with restrictive foreign keys, and append-only `crm.warehouse_audit_event` evidence that survives warehouse deletion. Warehouse display names remain stored once while a functional index enforces global case-insensitive uniqueness.

`V11__create_inbound_cargo_receipt_and_photos.sql` adds supplier inbound deliveries, shared line snapshots, one `crm.cargo_item` row per physical unit, immutable per-item warehouse receipt outcomes, and the append-only initial inventory movement ledger. Accepted items alone receive an opaque unique label and become available in an assigned project warehouse. Optional serials are globally unique case-insensitively when present. Cargo-owned photo metadata limits each item to ten ordered JPEG/PNG uploads of at most 15 MB, preserves verified original and preview variants, and uses a durable PostgreSQL processing queue plus cargo audit events. All operational links use restrictive and scope-consistent foreign keys.

`V12__harden_inbound_cargo_for_ui.sql` adds the immutable `IN-YYYY-NNNNNN` employee-facing delivery number, a race-safe yearly counter, and the indexes required by status, supplier, warehouse, and item-metadata filters. UUID remains the durable relation and API identity; the number is a display/search contract and is never allocated with `MAX + 1`.

`V13__add_attachment_cancellation_and_storage_cleanup.sql` adds the auditable `CANCELLED` lifecycle for unattached chat media and the shared durable `crm.storage_object_deletion_job` queue. Expired or abandoned drafts, replaced temporary uploads, chat variants, and cancelled cargo-photo objects are deleted from private storage by an idempotent retrying worker rather than best-effort calls or provider lifecycle assumptions.

`V14__add_supplier_goods_pre_shipment_flow.sql` separates supplier-held goods from inbound delivery. It adds reusable supplier-owned descriptions, immutable supplier ownership on every physical unit, optional exact-customer assignment, pre-shipment item states, draft reservation, explicit dispatch, and controlled cancellation. Existing declared deliveries are backfilled as already `IN_TRANSIT`; restrictive composite foreign keys prevent cross-project or cross-supplier assignment.

The repeatable fixture reconciles the three category codes and the exact role definitions. Global scope contains all thirteen roles: `OWNER`, `CRM_ADMIN`, `OPERATIONS_MANAGER`, `CUSTOMER_MANAGER`, `BUYER`, `LOGISTICS_SPECIALIST`, `WAREHOUSE_OPERATOR`, `CASHIER`, `COURIER`, `ACCOUNTANT`, `FINANCIAL_CONTROLLER`, `SUPPLIER`, and `CUSTOMER`. Project scope contains the eleven operational roles and excludes `OWNER` and `CRM_ADMIN`. No account is seeded. The secret-configured bootstrap owner remains the controlled entry point for the first persistent owner.

Project membership and project-role assignment use `project_member` plus `project_member_role`. A generic nullable `scope_id` assignment is intentionally avoided because it cannot enforce ownership with strong foreign keys. No project, account, membership, role, task, warehouse, project-warehouse assignment, audit, or outbox foreign key performs cascade deletion.

## Local Migration

Start PostgreSQL from the backend directory:

```bash
docker compose -f ../boxeudelivery-backend/compose.yaml up -d postgres
```

Optionally create local overrides:

```bash
cp .env.example .env
```

Inspect, migrate, and validate:

```bash
./scripts/flyway.sh info
./scripts/flyway.sh migrate
./scripts/flyway.sh validate
```

The defaults target the backend's local PostgreSQL port. Production and shared environments must provide the connection values through runtime secrets.

## Clean-Database Validation

Run the migration chain against an isolated disposable PostgreSQL database:

```bash
./scripts/validate.sh
```

The script runs `migrate` twice, followed by `validate` and `info`, then removes its temporary containers and database storage. The second migrate verifies that an unchanged migration set is a no-op.
It defaults to the same PostgreSQL image as the backend local stack. A compatible image can be selected explicitly for an offline/local check with `POSTGRES_IMAGE=postgres:16-alpine ./scripts/validate.sh`.

## Deployment Image

Build an immutable migration image:

```bash
docker build -t boxeudelivery-db-migrations .
```

At deployment time, provide `FLYWAY_URL`, `FLYWAY_USER`, and `FLYWAY_PASSWORD`. The image executes `flyway migrate` by default.

## Intentionally Deferred

- task reminder, escalation, archive, and retention rules;
- malware-scanner integration;
- durable email retry/dead-letter and provider feedback processing;

Those contracts will be added as small coordinated slices instead of being guessed.
