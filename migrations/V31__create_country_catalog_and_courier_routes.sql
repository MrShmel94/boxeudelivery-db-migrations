CREATE TABLE crm.country
(
    code               VARCHAR(2)   NOT NULL,
    name               VARCHAR(100) NOT NULL,
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version            BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_country
        PRIMARY KEY (code),
    CONSTRAINT ck_country_code
        CHECK (code ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_country_name_not_blank
        CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_country_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_country_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_country_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_country_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_country_name_case_insensitive
    ON crm.country (LOWER(BTRIM(name)));

CREATE INDEX ix_country_name_code
    ON crm.country (name, code);

INSERT INTO crm.country (
    code,
    name,
    created_by_subject,
    updated_by_subject
)
SELECT existing.code,
       CASE existing.code
           WHEN 'PL' THEN 'Польша'
           WHEN 'BY' THEN 'Беларусь'
           WHEN 'RU' THEN 'Россия'
           ELSE existing.code
       END,
       'migration:V31',
       'migration:V31'
FROM (
    SELECT DISTINCT UPPER(BTRIM(country_code)) AS code
    FROM crm.pickup_point
    WHERE country_code IS NOT NULL
    UNION
    SELECT DISTINCT UPPER(BTRIM(country_code)) AS code
    FROM crm.outbound_delivery
    WHERE country_code IS NOT NULL
) existing
WHERE existing.code ~ '^[A-Z]{2}$'
ON CONFLICT (code) DO NOTHING;

ALTER TABLE crm.warehouse
    ADD COLUMN country_code VARCHAR(2),
    ADD CONSTRAINT fk_warehouse_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_warehouse_country_code
        CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$');

CREATE INDEX ix_warehouse_country_name
    ON crm.warehouse (country_code, name, id);

ALTER TABLE crm.pickup_point
    ADD CONSTRAINT fk_pickup_point_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT;

ALTER TABLE crm.outbound_delivery
    ADD CONSTRAINT fk_outbound_delivery_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT;

CREATE TABLE crm.account_courier_route
(
    account_id               UUID         NOT NULL,
    origin_country_code      VARCHAR(2)   NOT NULL,
    destination_country_code VARCHAR(2)   NOT NULL,
    assigned_by_subject      VARCHAR(255) NOT NULL,
    assigned_at              TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_account_courier_route
        PRIMARY KEY (account_id, origin_country_code, destination_country_code),
    CONSTRAINT fk_account_courier_route_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_account_courier_route_origin_country
        FOREIGN KEY (origin_country_code) REFERENCES crm.country (code) ON DELETE RESTRICT,
    CONSTRAINT fk_account_courier_route_destination_country
        FOREIGN KEY (destination_country_code) REFERENCES crm.country (code) ON DELETE RESTRICT,
    CONSTRAINT ck_account_courier_route_direction
        CHECK (origin_country_code <> destination_country_code),
    CONSTRAINT ck_account_courier_route_assigned_by_not_blank
        CHECK (BTRIM(assigned_by_subject) <> '')
);

CREATE INDEX ix_account_courier_route_direction_account
    ON crm.account_courier_route (origin_country_code, destination_country_code, account_id);

CREATE TABLE crm.country_audit_event
(
    id            UUID         NOT NULL,
    country_code  VARCHAR(2)   NOT NULL,
    event_type    VARCHAR(32)  NOT NULL,
    actor_subject VARCHAR(255) NOT NULL,
    details       JSONB        NOT NULL DEFAULT '{}'::JSONB,
    occurred_at   TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_country_audit_event
        PRIMARY KEY (id),
    CONSTRAINT ck_country_audit_event_country_code
        CHECK (country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_country_audit_event_type
        CHECK (event_type IN ('CREATED', 'UPDATED', 'DELETED')),
    CONSTRAINT ck_country_audit_event_actor_not_blank
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_country_audit_event_details_object
        CHECK (jsonb_typeof(details) = 'object')
);

CREATE INDEX ix_country_audit_event_country_occurred
    ON crm.country_audit_event (country_code, occurred_at DESC, id);

COMMENT ON TABLE crm.country IS
    'Administrator-managed country catalogue identified by immutable ISO-style alpha-2 codes.';
COMMENT ON COLUMN crm.warehouse.country_code IS
    'Country of the warehouse. Nullable only for warehouses that predate the managed country catalogue.';
COMMENT ON TABLE crm.account_courier_route IS
    'Directed country pairs configured for a courier account; authorization remains role-based.';
COMMENT ON TABLE crm.country_audit_event IS
    'Append-only country catalogue audit retained after an unused country is deleted.';
