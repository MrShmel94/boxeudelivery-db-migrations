# Box EU Delivery Database Migrations

Independent Flyway deployment unit and Git repository for the Box EU Delivery CRM database. Backend mappings and migration contracts evolve in separate repositories, so compatible revisions and deployment order must be coordinated explicitly.

## Boundaries

- Flyway SQL is the only schema-evolution mechanism.
- Versioned migrations in `migrations/` are immutable after application.
- Every correction is a new migration version.
- Controlled reference data belongs only in repeatable SQL under `fixtures/`.
- Plaintext passwords, real accounts, personal data, and environment secrets never belong in migrations or fixtures.
- Account foreign keys do not cascade physical deletion; the current lifecycle exposes disable/reactivate rather than physical deletion.
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

The repeatable fixture reconciles the three category codes and the exact role definitions. Global scope contains all thirteen roles: `OWNER`, `CRM_ADMIN`, `OPERATIONS_MANAGER`, `CUSTOMER_MANAGER`, `BUYER`, `LOGISTICS_SPECIALIST`, `WAREHOUSE_OPERATOR`, `CASHIER`, `COURIER`, `ACCOUNTANT`, `FINANCIAL_CONTROLLER`, `SUPPLIER`, and `CUSTOMER`. Project scope contains the eleven operational roles and excludes `OWNER` and `CRM_ADMIN`. No account is seeded. The secret-configured bootstrap owner remains the controlled entry point for the first persistent owner.

Project membership and project-role assignment will be introduced together with the project aggregate. The intended relational shape is `project_member` plus `project_member_role`, with a composite foreign key back to the membership and a project-scoped role definition. A generic nullable `scope_id` assignment is intentionally avoided because it cannot enforce ownership with strong foreign keys.

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

- project-operation permission mapping and role-combination rules;
- durable email retry/dead-letter and provider feedback processing;
- project, task, participant, subtask, and chat schemas.

Those contracts will be added as small coordinated slices instead of being guessed in the first migration.
