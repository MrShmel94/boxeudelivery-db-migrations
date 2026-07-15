FROM flyway/flyway:12.10.0-alpine

COPY migrations /flyway/migrations
COPY fixtures /flyway/fixtures

ENV FLYWAY_LOCATIONS=filesystem:/flyway/migrations,filesystem:/flyway/fixtures \
    FLYWAY_CONNECT_RETRIES=30 \
    FLYWAY_CLEAN_DISABLED=true \
    FLYWAY_OUT_OF_ORDER=false \
    FLYWAY_VALIDATE_MIGRATION_NAMING=true \
    FLYWAY_ENCODING=UTF-8

CMD ["migrate"]
