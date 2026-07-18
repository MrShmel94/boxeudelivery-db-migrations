CREATE TABLE crm.currency_definition
(
    code            VARCHAR(3)  NOT NULL,
    display_name    VARCHAR(64) NOT NULL,
    symbol          VARCHAR(8)  NOT NULL,
    fraction_digits SMALLINT    NOT NULL,
    active          BOOLEAN     NOT NULL DEFAULT TRUE,
    display_order   SMALLINT    NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_currency_definition
        PRIMARY KEY (code),
    CONSTRAINT ck_currency_definition_code
        CHECK (code ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_currency_definition_name_not_blank
        CHECK (BTRIM(display_name) <> ''),
    CONSTRAINT ck_currency_definition_symbol_not_blank
        CHECK (BTRIM(symbol) <> ''),
    CONSTRAINT ck_currency_definition_fraction_digits
        CHECK (fraction_digits BETWEEN 0 AND 4),
    CONSTRAINT ck_currency_definition_display_order
        CHECK (display_order >= 0),
    CONSTRAINT ck_currency_definition_timestamps
        CHECK (updated_at >= created_at)
);

-- These rows are required before historical finance rows can receive foreign keys.
-- R__02_currency_reference_data.sql remains the authoritative repeatable catalogue.
INSERT INTO crm.currency_definition (
    code,
    display_name,
    symbol,
    fraction_digits,
    active,
    display_order
)
VALUES ('USD', 'US Dollar', '$', 2, TRUE, 10),
       ('EUR', 'Euro', '€', 2, TRUE, 20),
       ('PLN', 'Polish Zloty', 'zł', 2, TRUE, 30),
       ('RUB', 'Russian Ruble', '₽', 2, TRUE, 40),
       ('CNY', 'Chinese Yuan', '¥', 2, TRUE, 50);

ALTER TABLE crm.cargo_item_financial_entry
    ADD COLUMN effective_on DATE,
    DROP CONSTRAINT ck_cargo_item_financial_entry_currency,
    ADD CONSTRAINT fk_cargo_item_financial_entry_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_cargo_item_financial_entry_effective_on
        CHECK (entry_type = 'SUPPLIER_PURCHASE_COST' OR effective_on IS NULL);

ALTER TABLE crm.cargo_item_financial_revision
    ADD COLUMN effective_on DATE,
    DROP CONSTRAINT ck_cargo_item_financial_revision_currency,
    ADD CONSTRAINT fk_cargo_item_financial_revision_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_cargo_item_financial_revision_effective_on
        CHECK (entry_type = 'SUPPLIER_PURCHASE_COST' OR effective_on IS NULL);

ALTER TABLE crm.cargo_item_financial_revision
    ADD CONSTRAINT uq_cargo_item_financial_revision_purchase_scope
        UNIQUE (financial_entry_id, revision_number, cargo_item_id, project_id);

CREATE TABLE crm.cargo_item_purchase_rate_snapshot
(
    id                    UUID            NOT NULL,
    cargo_item_id         UUID            NOT NULL,
    project_id            UUID            NOT NULL,
    purchase_entry_id     UUID            NOT NULL,
    purchase_revision     INTEGER         NOT NULL,
    base_currency_code    VARCHAR(3)      NOT NULL,
    quote_currency_code   VARCHAR(3)      NOT NULL,
    quote_per_base        NUMERIC(24, 10) NOT NULL,
    effective_on          DATE            NOT NULL,
    source_code           VARCHAR(32)     NOT NULL,
    supersedes_id         UUID,
    correction_reason     VARCHAR(500),
    active                BOOLEAN         NOT NULL DEFAULT TRUE,
    created_by_subject    VARCHAR(255)    NOT NULL,
    created_at            TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_cargo_item_purchase_rate_snapshot
        PRIMARY KEY (id),
    CONSTRAINT uq_cargo_item_purchase_rate_snapshot_supersedes
        UNIQUE (supersedes_id),
    CONSTRAINT uq_cargo_item_purchase_rate_snapshot_scope
        UNIQUE (id, cargo_item_id, project_id),
    CONSTRAINT fk_cargo_item_purchase_rate_snapshot_item_scope
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_purchase_rate_snapshot_purchase_revision
        FOREIGN KEY (purchase_entry_id, purchase_revision, cargo_item_id, project_id)
            REFERENCES crm.cargo_item_financial_revision (
                financial_entry_id,
                revision_number,
                cargo_item_id,
                project_id
            ) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_purchase_rate_snapshot_base_currency
        FOREIGN KEY (base_currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_purchase_rate_snapshot_quote_currency
        FOREIGN KEY (quote_currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_purchase_rate_snapshot_supersedes
        FOREIGN KEY (supersedes_id) REFERENCES crm.cargo_item_purchase_rate_snapshot (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_item_purchase_rate_snapshot_pair
        CHECK (base_currency_code <> quote_currency_code),
    CONSTRAINT ck_cargo_item_purchase_rate_snapshot_purchase_revision
        CHECK (purchase_revision >= 1),
    CONSTRAINT ck_cargo_item_purchase_rate_snapshot_rate
        CHECK (quote_per_base > 0),
    CONSTRAINT ck_cargo_item_purchase_rate_snapshot_source
        CHECK (source_code IN ('SUPPLIER_MANUAL')),
    CONSTRAINT ck_cargo_item_purchase_rate_snapshot_actor_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_cargo_item_purchase_rate_snapshot_correction
        CHECK (
            (supersedes_id IS NULL AND correction_reason IS NULL)
            OR (
                supersedes_id IS NOT NULL
                AND correction_reason IS NOT NULL
                AND BTRIM(correction_reason) <> ''
            )
        )
);

CREATE UNIQUE INDEX uq_cargo_item_purchase_rate_snapshot_active_pair_date
    ON crm.cargo_item_purchase_rate_snapshot (
        cargo_item_id,
        purchase_entry_id,
        purchase_revision,
        base_currency_code,
        quote_currency_code,
        effective_on
    )
    WHERE active;

CREATE INDEX ix_cargo_item_purchase_rate_snapshot_item_active
    ON crm.cargo_item_purchase_rate_snapshot (cargo_item_id, active, effective_on DESC, created_at DESC, id);

CREATE INDEX ix_cargo_item_purchase_rate_snapshot_project_created
    ON crm.cargo_item_purchase_rate_snapshot (project_id, created_at DESC, id);

ALTER TABLE crm.cargo_audit_event
    DROP CONSTRAINT ck_cargo_audit_event_aggregate_type,
    ADD CONSTRAINT ck_cargo_audit_event_aggregate_type
        CHECK (aggregate_type IN (
            'SUPPLIER_GOODS',
            'INBOUND_DELIVERY',
            'INBOUND_PACKAGE',
            'COURIER_ASSIGNMENT',
            'CARGO_ITEM',
            'CARGO_PHOTO',
            'CARGO_FINANCIAL_ENTRY',
            'CARGO_PURCHASE_RATE'
        ));

COMMENT ON TABLE crm.currency_definition IS
    'System-managed ISO currency catalogue used by monetary facts. Inactive currencies remain valid historically.';

COMMENT ON COLUMN crm.cargo_item_financial_entry.effective_on IS
    'Business-effective date. It is used as the purchase date for SUPPLIER_PURCHASE_COST and is absent for other current entry types.';

COMMENT ON TABLE crm.cargo_item_purchase_rate_snapshot IS
    'Directed supplier-declared purchase reference rates. Financial fields are immutable; correction appends a successor and deactivates the prior snapshot.';

COMMENT ON COLUMN crm.cargo_item_purchase_rate_snapshot.quote_per_base IS
    'Positive quote-currency units for one base-currency unit, for example 4.0000000000 means 1 USD = 4 PLN.';
