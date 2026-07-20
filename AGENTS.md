# Flyway Repository Rules

- Route through `../boxeudelivery-knowledge/ROUTING.md` and read `engineering/database-migrations.md` plus the affected capability.
- Flyway SQL is the exact schema authority.
- Never modify an already-applied versioned migration; add a later version.
- Keep schema evolution in versioned migrations and controlled business/reference convergence in repeatable fixtures.
- Never place accounts, credentials, personal data, secrets, or production payloads in fixtures.
- Validate the complete ordered chain, clean and relevant existing histories, backend mappings/queries, and repository `git diff --check`.
- Coordinate compatible backend, frontend, contract, and knowledge changes without inventing schema detail in prose.
