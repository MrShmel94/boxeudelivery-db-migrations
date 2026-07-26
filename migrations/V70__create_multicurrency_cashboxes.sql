CREATE TABLE crm.settlement_cashbox
(
    id                 UUID         NOT NULL,
    display_name       VARCHAR(150) NOT NULL,
    masked_reference   VARCHAR(100),
    status_code        VARCHAR(16)  NOT NULL DEFAULT 'ACTIVE',
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version            BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_settlement_cashbox
        PRIMARY KEY (id),
    CONSTRAINT ck_settlement_cashbox_display_name
        CHECK (BTRIM(display_name) <> ''),
    CONSTRAINT ck_settlement_cashbox_masked_reference
        CHECK (masked_reference IS NULL OR BTRIM(masked_reference) <> ''),
    CONSTRAINT ck_settlement_cashbox_status
        CHECK (status_code IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT ck_settlement_cashbox_created_by
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_settlement_cashbox_updated_by
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_settlement_cashbox_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_settlement_cashbox_version
        CHECK (version >= 0)
);

ALTER TABLE crm.settlement_financial_account
    ADD COLUMN cashbox_id UUID;

INSERT INTO crm.settlement_cashbox (
    id,
    display_name,
    masked_reference,
    status_code,
    created_by_subject,
    updated_by_subject,
    created_at,
    updated_at,
    version
)
SELECT account.id,
       account.display_name,
       account.masked_reference,
       account.status_code,
       account.created_by_subject,
       account.updated_by_subject,
       account.created_at,
       account.updated_at,
       account.version
FROM crm.settlement_financial_account account
WHERE account.account_type = 'COMPANY_CASHBOX';

UPDATE crm.settlement_financial_account
SET cashbox_id = id
WHERE account_type = 'COMPANY_CASHBOX';

ALTER TABLE crm.settlement_financial_account
    ADD CONSTRAINT fk_settlement_financial_account_cashbox
        FOREIGN KEY (cashbox_id) REFERENCES crm.settlement_cashbox (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_settlement_financial_account_cashbox
        CHECK (
            (account_type = 'COMPANY_CASHBOX' AND cashbox_id IS NOT NULL)
            OR
            (account_type <> 'COMPANY_CASHBOX' AND cashbox_id IS NULL)
        );

CREATE UNIQUE INDEX uq_settlement_financial_account_cashbox_currency
    ON crm.settlement_financial_account (cashbox_id, currency_code)
    WHERE account_type = 'COMPANY_CASHBOX';

CREATE INDEX ix_settlement_financial_account_cashbox
    ON crm.settlement_financial_account (cashbox_id, status_code, currency_code, id)
    WHERE cashbox_id IS NOT NULL;

CREATE TABLE crm.settlement_cash_denomination
(
    id                 UUID           NOT NULL,
    currency_code      VARCHAR(3)     NOT NULL,
    kind_code          VARCHAR(8)     NOT NULL,
    denomination_value NUMERIC(19, 4) NOT NULL,
    active             BOOLEAN        NOT NULL DEFAULT TRUE,
    display_order      SMALLINT       NOT NULL,
    created_at         TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_settlement_cash_denomination
        PRIMARY KEY (id),
    CONSTRAINT uq_settlement_cash_denomination_value
        UNIQUE (currency_code, kind_code, denomination_value),
    CONSTRAINT fk_settlement_cash_denomination_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_cash_denomination_kind
        CHECK (kind_code IN ('NOTE', 'COIN')),
    CONSTRAINT ck_settlement_cash_denomination_value
        CHECK (denomination_value > 0),
    CONSTRAINT ck_settlement_cash_denomination_display_order
        CHECK (display_order >= 0),
    CONSTRAINT ck_settlement_cash_denomination_timestamps
        CHECK (updated_at >= created_at)
);

CREATE INDEX ix_settlement_cash_denomination_active_currency
    ON crm.settlement_cash_denomination (
        currency_code,
        active,
        kind_code,
        display_order,
        denomination_value
    );

COMMENT ON TABLE crm.settlement_cashbox IS
    'Physical company cash storage. Currency-specific immutable-ledger accounts remain its child sections.';

COMMENT ON COLUMN crm.settlement_financial_account.cashbox_id IS
    'Physical cashbox grouping for a single currency-specific COMPANY_CASHBOX ledger account.';

COMMENT ON TABLE crm.settlement_cash_denomination IS
    'System-managed cash denomination catalogue. It does not represent counted inventory by itself.';
