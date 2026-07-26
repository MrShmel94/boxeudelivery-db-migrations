ALTER TABLE crm.settlement_money_account_posting
    ADD CONSTRAINT uq_settlement_money_account_posting_currency
        UNIQUE (operation_id, financial_account_id, currency_code);

ALTER TABLE crm.settlement_cash_denomination
    ADD CONSTRAINT uq_settlement_cash_denomination_currency
        UNIQUE (id, currency_code);

CREATE TABLE crm.settlement_cash_denomination_posting
(
    id                   UUID        NOT NULL,
    operation_id         UUID        NOT NULL,
    financial_account_id UUID        NOT NULL,
    currency_code        VARCHAR(3)  NOT NULL,
    denomination_id      UUID        NOT NULL,
    quantity_delta       INTEGER     NOT NULL,
    occurred_at          TIMESTAMPTZ NOT NULL,
    CONSTRAINT pk_settlement_cash_denomination_posting
        PRIMARY KEY (id),
    CONSTRAINT uq_settlement_cash_denomination_posting_operation
        UNIQUE (operation_id, financial_account_id, denomination_id),
    CONSTRAINT fk_settlement_cash_denomination_posting_money
        FOREIGN KEY (operation_id, financial_account_id, currency_code)
            REFERENCES crm.settlement_money_account_posting (
                operation_id,
                financial_account_id,
                currency_code
            ) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_cash_denomination_posting_denomination
        FOREIGN KEY (denomination_id, currency_code)
            REFERENCES crm.settlement_cash_denomination (id, currency_code) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_cash_denomination_posting_quantity
        CHECK (quantity_delta <> 0)
);

CREATE INDEX ix_settlement_cash_denomination_posting_inventory
    ON crm.settlement_cash_denomination_posting (
        financial_account_id,
        currency_code,
        denomination_id,
        occurred_at,
        operation_id
    );

CREATE INDEX ix_settlement_cash_denomination_posting_operation
    ON crm.settlement_cash_denomination_posting (operation_id, financial_account_id, denomination_id);

COMMENT ON TABLE crm.settlement_cash_denomination_posting IS
    'Immutable signed movements of exact banknote and coin quantities for cash ledger postings.';
