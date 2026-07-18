CREATE TABLE crm.customer_order_number_counter
(
    calendar_year INTEGER NOT NULL,
    last_value    BIGINT  NOT NULL,
    CONSTRAINT pk_customer_order_number_counter
        PRIMARY KEY (calendar_year),
    CONSTRAINT ck_customer_order_number_counter_year
        CHECK (calendar_year BETWEEN 2000 AND 9999),
    CONSTRAINT ck_customer_order_number_counter_value
        CHECK (last_value >= 1)
);

CREATE TABLE crm.customer_order
(
    id                    UUID         NOT NULL,
    order_number          VARCHAR(20)  NOT NULL,
    project_id            UUID         NOT NULL,
    supplier_account_id   UUID         NOT NULL,
    customer_account_id   UUID         NOT NULL,
    status_code           VARCHAR(16)  NOT NULL,
    confirmed_by_subject  VARCHAR(255),
    confirmed_at          TIMESTAMPTZ,
    cancelled_by_subject  VARCHAR(255),
    cancelled_at          TIMESTAMPTZ,
    cancellation_reason   VARCHAR(500),
    created_by_subject    VARCHAR(255) NOT NULL,
    updated_by_subject    VARCHAR(255) NOT NULL,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version               BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_customer_order
        PRIMARY KEY (id),
    CONSTRAINT uq_customer_order_number
        UNIQUE (order_number),
    CONSTRAINT uq_customer_order_id_project
        UNIQUE (id, project_id),
    CONSTRAINT fk_customer_order_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_supplier
        FOREIGN KEY (supplier_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_customer
        FOREIGN KEY (customer_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_customer_order_distinct_parties
        CHECK (supplier_account_id <> customer_account_id),
    CONSTRAINT ck_customer_order_status
        CHECK (status_code IN ('DRAFT', 'CONFIRMED', 'CANCELLED')),
    CONSTRAINT ck_customer_order_lifecycle
        CHECK (
            (
                status_code = 'DRAFT'
                AND confirmed_by_subject IS NULL
                AND confirmed_at IS NULL
                AND cancelled_by_subject IS NULL
                AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code = 'CONFIRMED'
                AND confirmed_by_subject IS NOT NULL
                AND BTRIM(confirmed_by_subject) <> ''
                AND confirmed_at IS NOT NULL
                AND cancelled_by_subject IS NULL
                AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code = 'CANCELLED'
                AND confirmed_by_subject IS NULL
                AND confirmed_at IS NULL
                AND cancelled_by_subject IS NOT NULL
                AND BTRIM(cancelled_by_subject) <> ''
                AND cancelled_at IS NOT NULL
                AND cancellation_reason IS NOT NULL
                AND BTRIM(cancellation_reason) <> ''
            )
        ),
    CONSTRAINT ck_customer_order_created_by_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_customer_order_updated_by_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_customer_order_timestamps
        CHECK (
            updated_at >= created_at
            AND (confirmed_at IS NULL OR confirmed_at >= created_at)
            AND (cancelled_at IS NULL OR cancelled_at >= created_at)
        ),
    CONSTRAINT ck_customer_order_version
        CHECK (version >= 0)
);

CREATE INDEX ix_customer_order_project_created
    ON crm.customer_order (project_id, created_at DESC, id);

CREATE INDEX ix_customer_order_supplier_status
    ON crm.customer_order (supplier_account_id, status_code, created_at DESC, id);

CREATE INDEX ix_customer_order_customer_status
    ON crm.customer_order (customer_account_id, status_code, created_at DESC, id);

ALTER TABLE crm.cargo_item_financial_revision
    ADD CONSTRAINT uq_cargo_item_financial_revision_order_source
        UNIQUE (financial_entry_id, revision_number, cargo_item_id, project_id, entry_type);

CREATE TABLE crm.customer_order_line
(
    id                          UUID           NOT NULL,
    customer_order_id           UUID           NOT NULL,
    project_id                  UUID           NOT NULL,
    cargo_item_id               UUID           NOT NULL,
    sequence_number             INTEGER        NOT NULL,
    status_code                 VARCHAR(16)    NOT NULL,
    unit_price                  NUMERIC(19, 4) NOT NULL,
    currency_code               VARCHAR(3)     NOT NULL,
    source_financial_entry_id   UUID           NOT NULL,
    source_financial_revision   INTEGER        NOT NULL,
    source_financial_entry_type VARCHAR(48)    NOT NULL,
    customer_assigned_by_order  BOOLEAN        NOT NULL DEFAULT FALSE,
    removed_by_subject          VARCHAR(255),
    removed_at                  TIMESTAMPTZ,
    removal_reason              VARCHAR(500),
    created_by_subject          VARCHAR(255)   NOT NULL,
    updated_by_subject          VARCHAR(255)   NOT NULL,
    created_at                  TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                  TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revision_number             INTEGER        NOT NULL DEFAULT 1,
    version                     BIGINT         NOT NULL DEFAULT 0,
    CONSTRAINT pk_customer_order_line
        PRIMARY KEY (id),
    CONSTRAINT uq_customer_order_line_id_order
        UNIQUE (id, customer_order_id),
    CONSTRAINT uq_customer_order_line_id_scope
        UNIQUE (id, customer_order_id, project_id),
    CONSTRAINT uq_customer_order_line_order_sequence
        UNIQUE (customer_order_id, sequence_number),
    CONSTRAINT fk_customer_order_line_order_scope
        FOREIGN KEY (customer_order_id, project_id)
            REFERENCES crm.customer_order (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_line_item_scope
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_line_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_line_price_source
        FOREIGN KEY (
            source_financial_entry_id,
            source_financial_revision,
            cargo_item_id,
            project_id,
            source_financial_entry_type
        ) REFERENCES crm.cargo_item_financial_revision (
            financial_entry_id,
            revision_number,
            cargo_item_id,
            project_id,
            entry_type
        ) ON DELETE RESTRICT,
    CONSTRAINT ck_customer_order_line_sequence
        CHECK (sequence_number >= 1),
    CONSTRAINT ck_customer_order_line_status
        CHECK (status_code IN ('DRAFT', 'CONFIRMED', 'REMOVED')),
    CONSTRAINT ck_customer_order_line_price
        CHECK (unit_price >= 0),
    CONSTRAINT ck_customer_order_line_price_source_type
        CHECK (source_financial_entry_type = 'CUSTOMER_ITEM_PRICE'),
    CONSTRAINT ck_customer_order_line_source_revision
        CHECK (source_financial_revision >= 1),
    CONSTRAINT ck_customer_order_line_removal
        CHECK (
            (
                status_code <> 'REMOVED'
                AND removed_by_subject IS NULL
                AND removed_at IS NULL
                AND removal_reason IS NULL
            )
            OR (
                status_code = 'REMOVED'
                AND removed_by_subject IS NOT NULL
                AND BTRIM(removed_by_subject) <> ''
                AND removed_at IS NOT NULL
                AND removal_reason IS NOT NULL
                AND BTRIM(removal_reason) <> ''
            )
        ),
    CONSTRAINT ck_customer_order_line_created_by_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_customer_order_line_updated_by_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_customer_order_line_timestamps
        CHECK (updated_at >= created_at AND (removed_at IS NULL OR removed_at >= created_at)),
    CONSTRAINT ck_customer_order_line_revision
        CHECK (revision_number >= 1),
    CONSTRAINT ck_customer_order_line_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_customer_order_line_active_order_item
    ON crm.customer_order_line (customer_order_id, cargo_item_id)
    WHERE status_code <> 'REMOVED';

CREATE UNIQUE INDEX uq_customer_order_line_active_item
    ON crm.customer_order_line (cargo_item_id)
    WHERE status_code <> 'REMOVED';

CREATE INDEX ix_customer_order_line_order_status_sequence
    ON crm.customer_order_line (customer_order_id, status_code, sequence_number, id);

CREATE INDEX ix_customer_order_line_project_item
    ON crm.customer_order_line (project_id, cargo_item_id, status_code);

CREATE TABLE crm.customer_order_line_revision
(
    id                          UUID           NOT NULL,
    customer_order_line_id      UUID           NOT NULL,
    customer_order_id           UUID           NOT NULL,
    project_id                  UUID           NOT NULL,
    cargo_item_id               UUID           NOT NULL,
    revision_number             INTEGER        NOT NULL,
    action_code                 VARCHAR(16)    NOT NULL,
    status_code                 VARCHAR(16)    NOT NULL,
    unit_price                  NUMERIC(19, 4) NOT NULL,
    currency_code               VARCHAR(3)     NOT NULL,
    source_financial_entry_id   UUID           NOT NULL,
    source_financial_revision   INTEGER        NOT NULL,
    source_financial_entry_type VARCHAR(48)    NOT NULL,
    actor_subject               VARCHAR(255)   NOT NULL,
    reason                      VARCHAR(500),
    occurred_at                 TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_customer_order_line_revision
        PRIMARY KEY (id),
    CONSTRAINT uq_customer_order_line_revision_number
        UNIQUE (customer_order_line_id, revision_number),
    CONSTRAINT fk_customer_order_line_revision_line_scope
        FOREIGN KEY (customer_order_line_id, customer_order_id, project_id)
            REFERENCES crm.customer_order_line (id, customer_order_id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_line_revision_item_scope
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_line_revision_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_line_revision_price_source
        FOREIGN KEY (
            source_financial_entry_id,
            source_financial_revision,
            cargo_item_id,
            project_id,
            source_financial_entry_type
        ) REFERENCES crm.cargo_item_financial_revision (
            financial_entry_id,
            revision_number,
            cargo_item_id,
            project_id,
            entry_type
        ) ON DELETE RESTRICT,
    CONSTRAINT ck_customer_order_line_revision_number
        CHECK (revision_number >= 1),
    CONSTRAINT ck_customer_order_line_revision_action
        CHECK (action_code IN ('ADDED', 'REPRICED', 'REMOVED', 'CONFIRMED')),
    CONSTRAINT ck_customer_order_line_revision_status
        CHECK (status_code IN ('DRAFT', 'CONFIRMED', 'REMOVED')),
    CONSTRAINT ck_customer_order_line_revision_price
        CHECK (unit_price >= 0),
    CONSTRAINT ck_customer_order_line_revision_source_type
        CHECK (source_financial_entry_type = 'CUSTOMER_ITEM_PRICE'),
    CONSTRAINT ck_customer_order_line_revision_source_revision
        CHECK (source_financial_revision >= 1),
    CONSTRAINT ck_customer_order_line_revision_actor_not_blank
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_customer_order_line_revision_reason
        CHECK (
            (action_code IN ('REPRICED', 'REMOVED') AND reason IS NOT NULL AND BTRIM(reason) <> '')
            OR (action_code IN ('ADDED', 'CONFIRMED') AND reason IS NULL)
        )
);

CREATE INDEX ix_customer_order_line_revision_order_occurred
    ON crm.customer_order_line_revision (customer_order_id, occurred_at DESC, id);

CREATE INDEX ix_customer_order_line_revision_line_occurred
    ON crm.customer_order_line_revision (customer_order_line_id, occurred_at, revision_number);

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
            'CARGO_PURCHASE_RATE',
            'CUSTOMER_ORDER',
            'CUSTOMER_ORDER_LINE'
        ));

COMMENT ON TABLE crm.customer_order IS
    'Commercial customer order for one project, one supplier, and one customer. Physical execution is modeled separately.';

COMMENT ON TABLE crm.customer_order_line IS
    'Current allocation and negotiated price snapshot for one exact physical cargo item.';

COMMENT ON TABLE crm.customer_order_line_revision IS
    'Immutable attributable history of draft negotiation, removal, and final confirmation.';
