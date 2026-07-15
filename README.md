# Box EU Delivery Database Migrations

Independent Flyway deployment unit for the Box EU Delivery CRM database. It is kept in the product's root Git repository so migrations, backend mappings, API contracts, and knowledge can change atomically.

## Boundaries

- Flyway SQL is the only schema-evolution mechanism.
- Versioned migrations in `migrations/` are immutable after application.
- Every correction is a new migration version.
- Controlled reference data belongs only in repeatable SQL under `fixtures/`.
- Plaintext passwords, real accounts, personal data, and environment secrets never belong in migrations or fixtures.
- Account foreign keys do not cascade physical deletion; account deletion/archival requires an explicit future business rule.
- Flyway runs before the backend; Hibernate only validates the resulting schema.

## Current Schema

`V1__create_accounts_schema.sql` creates:

- `accounts.account` for account profile and lifecycle data;
- `accounts.password_credential` for password hashes and mandatory-password-change state;
- `accounts.account_category` for the optional `EMPLOYEE`, `SUPPLIER`, or `CLIENT` classification;
- `accounts.access_role` and `accounts.account_access_role` so authorization remains separate from business category.

The repeatable fixture provides the three confirmed category codes and the confirmed `ADMIN` access role. No account is seeded. The existing secret-configured bootstrap administrator remains the controlled entry point for the first real administrator.

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

- account HTTP endpoints and JPA mappings;
- the detailed permission matrix beyond `ADMIN`;
- temporary-password lifetime and delivery channel;
- email-based password recovery and notifications;
- project, task, participant, subtask, and chat schemas.

Those contracts will be added as small coordinated slices instead of being guessed in the first migration.
