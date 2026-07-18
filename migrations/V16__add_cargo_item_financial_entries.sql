CREATE TABLE crm.cargo_item_financial_entry
(
    id                   UUID           NOT NULL,
    cargo_item_id        UUID           NOT NULL,
    project_id           UUID           NOT NULL,
    entry_type           VARCHAR(48)    NOT NULL,
    amount               NUMERIC(19, 4) NOT NULL,
    currency_code        CHAR(3)        NOT NULL,
    charged_party        VARCHAR(16),
    charged_account_id   UUID,
    status_code          VARCHAR(16)    NOT NULL,
    confirmed_by_subject VARCHAR(255),
    confirmed_at         TIMESTAMPTZ,
    created_by_subject   VARCHAR(255)   NOT NULL,
    updated_by_subject   VARCHAR(255)   NOT NULL,
    created_at           TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revision_number      INTEGER        NOT NULL DEFAULT 1,
    version              BIGINT         NOT NULL DEFAULT 0,
    CONSTRAINT pk_cargo_item_financial_entry
        PRIMARY KEY (id),
    CONSTRAINT uq_cargo_item_financial_entry_item_type
        UNIQUE (cargo_item_id, entry_type),
    CONSTRAINT uq_cargo_item_financial_entry_scope
        UNIQUE (id, cargo_item_id, project_id),
    CONSTRAINT fk_cargo_item_financial_entry_item_scope
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_financial_entry_charged_account
        FOREIGN KEY (charged_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_item_financial_entry_type
        CHECK (entry_type IN (
            'SUPPLIER_PURCHASE_COST',
            'CUSTOMER_ITEM_PRICE',
            'BORDER_TRANSPORT_PRICE',
            'BORDER_TRANSPORT_ACTUAL_COST',
            'COMPANY_SERVICE_FEE'
        )),
    CONSTRAINT ck_cargo_item_financial_entry_amount
        CHECK (amount >= 0),
    CONSTRAINT ck_cargo_item_financial_entry_currency
        CHECK (currency_code IN ('RUB', 'USD', 'EUR', 'CNY')),
    CONSTRAINT ck_cargo_item_financial_entry_charge
        CHECK (
            (
                entry_type = 'COMPANY_SERVICE_FEE'
                AND charged_party IN ('CUSTOMER', 'SUPPLIER')
                AND charged_account_id IS NOT NULL
            )
            OR (
                entry_type <> 'COMPANY_SERVICE_FEE'
                AND charged_party IS NULL
                AND charged_account_id IS NULL
            )
        ),
    CONSTRAINT ck_cargo_item_financial_entry_status
        CHECK (status_code IN ('DRAFT', 'CONFIRMED')),
    CONSTRAINT ck_cargo_item_financial_entry_confirmation
        CHECK (
            (
                status_code = 'DRAFT'
                AND confirmed_by_subject IS NULL
                AND confirmed_at IS NULL
            )
            OR (
                status_code = 'CONFIRMED'
                AND confirmed_by_subject IS NOT NULL
                AND BTRIM(confirmed_by_subject) <> ''
                AND confirmed_at IS NOT NULL
            )
        ),
    CONSTRAINT ck_cargo_item_financial_entry_created_by_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_cargo_item_financial_entry_updated_by_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_cargo_item_financial_entry_timestamps
        CHECK (
            updated_at >= created_at
            AND (confirmed_at IS NULL OR confirmed_at >= created_at)
        ),
    CONSTRAINT ck_cargo_item_financial_entry_revision
        CHECK (revision_number >= 1),
    CONSTRAINT ck_cargo_item_financial_entry_version
        CHECK (version >= 0)
);

CREATE INDEX ix_cargo_item_financial_entry_item_status
    ON crm.cargo_item_financial_entry (cargo_item_id, status_code, entry_type);

CREATE INDEX ix_cargo_item_financial_entry_project_type
    ON crm.cargo_item_financial_entry (project_id, entry_type, updated_at DESC, id);

CREATE INDEX ix_cargo_item_financial_entry_charged_account
    ON crm.cargo_item_financial_entry (charged_account_id, updated_at DESC, id)
    WHERE charged_account_id IS NOT NULL;

CREATE TABLE crm.cargo_item_financial_revision
(
    id                 UUID           NOT NULL,
    financial_entry_id UUID           NOT NULL,
    cargo_item_id      UUID           NOT NULL,
    project_id         UUID           NOT NULL,
    revision_number    INTEGER        NOT NULL,
    action_code        VARCHAR(16)    NOT NULL,
    entry_type         VARCHAR(48)    NOT NULL,
    amount             NUMERIC(19, 4) NOT NULL,
    currency_code      CHAR(3)        NOT NULL,
    charged_party      VARCHAR(16),
    charged_account_id UUID,
    status_code        VARCHAR(16)    NOT NULL,
    actor_subject      VARCHAR(255)   NOT NULL,
    reason             VARCHAR(500),
    occurred_at        TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_cargo_item_financial_revision
        PRIMARY KEY (id),
    CONSTRAINT uq_cargo_item_financial_revision_number
        UNIQUE (financial_entry_id, revision_number),
    CONSTRAINT fk_cargo_item_financial_revision_item_scope
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_financial_revision_charged_account
        FOREIGN KEY (charged_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_item_financial_revision_number
        CHECK (revision_number >= 1),
    CONSTRAINT ck_cargo_item_financial_revision_action
        CHECK (action_code IN ('CREATED', 'UPDATED', 'CONFIRMED', 'CORRECTED', 'DELETED')),
    CONSTRAINT ck_cargo_item_financial_revision_type
        CHECK (entry_type IN (
            'SUPPLIER_PURCHASE_COST',
            'CUSTOMER_ITEM_PRICE',
            'BORDER_TRANSPORT_PRICE',
            'BORDER_TRANSPORT_ACTUAL_COST',
            'COMPANY_SERVICE_FEE'
        )),
    CONSTRAINT ck_cargo_item_financial_revision_amount
        CHECK (amount >= 0),
    CONSTRAINT ck_cargo_item_financial_revision_currency
        CHECK (currency_code IN ('RUB', 'USD', 'EUR', 'CNY')),
    CONSTRAINT ck_cargo_item_financial_revision_charge
        CHECK (
            (
                entry_type = 'COMPANY_SERVICE_FEE'
                AND charged_party IN ('CUSTOMER', 'SUPPLIER')
                AND charged_account_id IS NOT NULL
            )
            OR (
                entry_type <> 'COMPANY_SERVICE_FEE'
                AND charged_party IS NULL
                AND charged_account_id IS NULL
            )
        ),
    CONSTRAINT ck_cargo_item_financial_revision_status
        CHECK (status_code IN ('DRAFT', 'CONFIRMED')),
    CONSTRAINT ck_cargo_item_financial_revision_actor_not_blank
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_cargo_item_financial_revision_reason
        CHECK (
            (action_code = 'CORRECTED' AND reason IS NOT NULL AND BTRIM(reason) <> '')
            OR (action_code <> 'CORRECTED' AND reason IS NULL)
        )
);

CREATE INDEX ix_cargo_item_financial_revision_entry_occurred
    ON crm.cargo_item_financial_revision (financial_entry_id, occurred_at DESC, revision_number DESC);

CREATE INDEX ix_cargo_item_financial_revision_item_occurred
    ON crm.cargo_item_financial_revision (cargo_item_id, occurred_at DESC, id);

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
            'CARGO_FINANCIAL_ENTRY'
        ));

COMMENT ON TABLE crm.cargo_item_financial_entry IS
    'Current typed monetary values for one exact physical cargo item. Visibility is derived from entry_type.';

COMMENT ON COLUMN crm.cargo_item_financial_entry.charged_account_id IS
    'Exact payer snapshot for COMPANY_SERVICE_FEE, resolved by the backend from the selected party.';

COMMENT ON TABLE crm.cargo_item_financial_revision IS
    'Immutable financial snapshots retained across confirmation, correction, and draft deletion.';

COMMENT ON COLUMN crm.cargo_item_financial_revision.financial_entry_id IS
    'Logical entry identity without a foreign key so deletion of a draft cannot erase its revision evidence.';
