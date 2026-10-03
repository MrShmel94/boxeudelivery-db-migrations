FROM flyway/flyway:12.10.0-alpine@sha256:2e9890a54428c4f11697ea38ce01d96901fb55af6efe47029bfc9c64d3e60b64

COPY migrations /flyway/migrations
COPY fixtures /flyway/fixtures

ENV FLYWAY_LOCATIONS=filesystem:/flyway/migrations,filesystem:/flyway/fixtures \
    FLYWAY_CONNECT_RETRIES=30 \
    FLYWAY_CLEAN_DISABLED=true \
    FLYWAY_OUT_OF_ORDER=false \
    FLYWAY_VALIDATE_MIGRATION_NAMING=true \
    FLYWAY_ENCODING=UTF-8

CMD ["migrate"]

# One-shot migration job; successful exit is its deployment readiness gate.
HEALTHCHECK NONE
