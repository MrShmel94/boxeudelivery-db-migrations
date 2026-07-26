CREATE TABLE crm.settlement_financial_account
(
    id                   UUID          NOT NULL,
    account_type         VARCHAR(32)   NOT NULL,
    display_name         VARCHAR(150)  NOT NULL,
    currency_code        VARCHAR(3)    NOT NULL,
    custodian_account_id UUID,
    masked_reference     VARCHAR(100),
    status_code          VARCHAR(16)   NOT NULL DEFAULT 'ACTIVE',
    created_by_subject   VARCHAR(255)  NOT NULL,
    updated_by_subject   VARCHAR(255)  NOT NULL,
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version              BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_settlement_financial_account
        PRIMARY KEY (id),
    CONSTRAINT uq_settlement_financial_account_currency
        UNIQUE (id, currency_code),
    CONSTRAINT fk_settlement_financial_account_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_financial_account_custodian
        FOREIGN KEY (custodian_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_financial_account_type
        CHECK (account_type IN (
            'COMPANY_BANK',
            'COMPANY_CARD',
            'COMPANY_CASHBOX',
            'EMPLOYEE_CARD',
            'EMPLOYEE_CASH'
        )),
    CONSTRAINT ck_settlement_financial_account_custodian
        CHECK (
            (account_type IN ('EMPLOYEE_CARD', 'EMPLOYEE_CASH') AND custodian_account_id IS NOT NULL)
            OR
            (account_type IN ('COMPANY_BANK', 'COMPANY_CARD', 'COMPANY_CASHBOX')
                AND custodian_account_id IS NULL)
        ),
    CONSTRAINT ck_settlement_financial_account_display_name
        CHECK (BTRIM(display_name) <> ''),
    CONSTRAINT ck_settlement_financial_account_masked_reference
        CHECK (masked_reference IS NULL OR BTRIM(masked_reference) <> ''),
    CONSTRAINT ck_settlement_financial_account_status
        CHECK (status_code IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT ck_settlement_financial_account_created_by
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_settlement_financial_account_updated_by
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_settlement_financial_account_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_settlement_financial_account_version
        CHECK (version >= 0)
);

CREATE INDEX ix_settlement_financial_account_status_type
    ON crm.settlement_financial_account (status_code, account_type, currency_code, display_name, id);

CREATE INDEX ix_settlement_financial_account_custodian
    ON crm.settlement_financial_account (custodian_account_id, status_code, currency_code)
    WHERE custodian_account_id IS NOT NULL;

CREATE TABLE crm.settlement_money_operation
(
    id                    UUID           NOT NULL,
    client_operation_id   UUID           NOT NULL,
    operation_type        VARCHAR(40)    NOT NULL,
    status_code           VARCHAR(16)    NOT NULL DEFAULT 'CONFIRMED',
    project_id            UUID           NOT NULL,
    supplier_id           UUID           NOT NULL,
    counterparty_type     VARCHAR(16)    NOT NULL,
    customer_profile_id   UUID,
    financial_account_id  UUID,
    payment_method        VARCHAR(24),
    amount                NUMERIC(19, 4) NOT NULL,
    currency_code         VARCHAR(3)     NOT NULL,
    counterparty_delta    NUMERIC(19, 4) NOT NULL,
    note                  VARCHAR(500),
    reason                VARCHAR(500),
    occurred_at           TIMESTAMPTZ    NOT NULL,
    confirmed_at          TIMESTAMPTZ    NOT NULL,
    created_by_subject    VARCHAR(255)   NOT NULL,
    confirmed_by_subject  VARCHAR(255)   NOT NULL,
    created_at            TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_settlement_money_operation
        PRIMARY KEY (id),
    CONSTRAINT uq_settlement_money_operation_client
        UNIQUE (client_operation_id),
    CONSTRAINT fk_settlement_money_operation_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_money_operation_customer
        FOREIGN KEY (customer_profile_id, project_id, supplier_id)
            REFERENCES crm.customer_profile (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_money_operation_account_currency
        FOREIGN KEY (financial_account_id, currency_code)
            REFERENCES crm.settlement_financial_account (id, currency_code) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_money_operation_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_money_operation_type
        CHECK (operation_type IN ('CUSTOMER_ADVANCE', 'COUNTERPARTY_ADJUSTMENT')),
    CONSTRAINT ck_settlement_money_operation_status
        CHECK (status_code = 'CONFIRMED'),
    CONSTRAINT ck_settlement_money_operation_counterparty
        CHECK (
            (counterparty_type = 'CUSTOMER' AND customer_profile_id IS NOT NULL)
            OR
            (counterparty_type = 'SUPPLIER' AND customer_profile_id IS NULL)
        ),
    CONSTRAINT ck_settlement_money_operation_payment_method
        CHECK (payment_method IS NULL OR payment_method IN ('CASH', 'BANK_TRANSFER', 'CARD_TRANSFER')),
    CONSTRAINT ck_settlement_money_operation_amount
        CHECK (amount > 0),
    CONSTRAINT ck_settlement_money_operation_delta
        CHECK (counterparty_delta <> 0 AND ABS(counterparty_delta) = amount),
    CONSTRAINT ck_settlement_money_operation_customer_advance
        CHECK (
            operation_type <> 'CUSTOMER_ADVANCE'
            OR (
                counterparty_type = 'CUSTOMER'
                AND financial_account_id IS NOT NULL
                AND payment_method IS NOT NULL
                AND counterparty_delta = amount
                AND reason IS NULL
            )
        ),
    CONSTRAINT ck_settlement_money_operation_adjustment
        CHECK (
            operation_type <> 'COUNTERPARTY_ADJUSTMENT'
            OR (
                financial_account_id IS NULL
                AND payment_method IS NULL
                AND reason IS NOT NULL
                AND BTRIM(reason) <> ''
            )
        ),
    CONSTRAINT ck_settlement_money_operation_note
        CHECK (note IS NULL OR BTRIM(note) <> ''),
    CONSTRAINT ck_settlement_money_operation_reason
        CHECK (reason IS NULL OR BTRIM(reason) <> ''),
    CONSTRAINT ck_settlement_money_operation_times
        CHECK (confirmed_at >= occurred_at AND created_at >= occurred_at),
    CONSTRAINT ck_settlement_money_operation_created_by
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_settlement_money_operation_confirmed_by
        CHECK (BTRIM(confirmed_by_subject) <> '')
);

CREATE INDEX ix_settlement_money_operation_scope_occurred
    ON crm.settlement_money_operation (
        project_id,
        supplier_id,
        occurred_at DESC,
        id DESC
    );

CREATE INDEX ix_settlement_money_operation_customer_occurred
    ON crm.settlement_money_operation (
        customer_profile_id,
        occurred_at DESC,
        id DESC
    )
    WHERE customer_profile_id IS NOT NULL;

CREATE INDEX ix_settlement_money_operation_account_occurred
    ON crm.settlement_money_operation (
        financial_account_id,
        occurred_at DESC,
        id DESC
    )
    WHERE financial_account_id IS NOT NULL;

CREATE TABLE crm.settlement_money_account_posting
(
    operation_id        UUID           NOT NULL,
    financial_account_id UUID          NOT NULL,
    currency_code       VARCHAR(3)     NOT NULL,
    amount_delta        NUMERIC(19, 4) NOT NULL,
    occurred_at         TIMESTAMPTZ    NOT NULL,
    CONSTRAINT pk_settlement_money_account_posting
        PRIMARY KEY (operation_id, financial_account_id),
    CONSTRAINT fk_settlement_money_account_posting_operation
        FOREIGN KEY (operation_id) REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_money_account_posting_account
        FOREIGN KEY (financial_account_id, currency_code)
            REFERENCES crm.settlement_financial_account (id, currency_code) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_money_account_posting_amount
        CHECK (amount_delta <> 0)
);

CREATE INDEX ix_settlement_money_account_posting_balance
    ON crm.settlement_money_account_posting (financial_account_id, currency_code, occurred_at, operation_id);

CREATE TABLE crm.settlement_counterparty_posting
(
    operation_id       UUID           NOT NULL,
    counterparty_type  VARCHAR(16)    NOT NULL,
    project_id         UUID           NOT NULL,
    supplier_id        UUID           NOT NULL,
    customer_profile_id UUID,
    currency_code      VARCHAR(3)     NOT NULL,
    amount_delta       NUMERIC(19, 4) NOT NULL,
    occurred_at        TIMESTAMPTZ    NOT NULL,
    CONSTRAINT pk_settlement_counterparty_posting
        PRIMARY KEY (operation_id),
    CONSTRAINT fk_settlement_counterparty_posting_operation
        FOREIGN KEY (operation_id) REFERENCES crm.settlement_money_operation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_counterparty_posting_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_counterparty_posting_customer
        FOREIGN KEY (customer_profile_id, project_id, supplier_id)
            REFERENCES crm.customer_profile (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_settlement_counterparty_posting_currency
        FOREIGN KEY (currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_counterparty_posting_counterparty
        CHECK (
            (counterparty_type = 'CUSTOMER' AND customer_profile_id IS NOT NULL)
            OR
            (counterparty_type = 'SUPPLIER' AND customer_profile_id IS NULL)
        ),
    CONSTRAINT ck_settlement_counterparty_posting_amount
        CHECK (amount_delta <> 0)
);

CREATE INDEX ix_settlement_counterparty_posting_customer_balance
    ON crm.settlement_counterparty_posting (
        customer_profile_id,
        currency_code,
        occurred_at,
        operation_id
    )
    WHERE counterparty_type = 'CUSTOMER';

CREATE INDEX ix_settlement_counterparty_posting_supplier_balance
    ON crm.settlement_counterparty_posting (
        project_id,
        supplier_id,
        currency_code,
        occurred_at,
        operation_id
    )
    WHERE counterparty_type = 'SUPPLIER';

COMMENT ON TABLE crm.settlement_financial_account IS
    'Operational locations of company money or funds held under an accountable employee. This is not a bank-balance integration.';

COMMENT ON TABLE crm.settlement_money_operation IS
    'Immutable confirmed business documents that create settlement postings. Price rows and order states are not money operations.';

COMMENT ON TABLE crm.settlement_money_account_posting IS
    'Immutable movements affecting one operational money-location balance.';

COMMENT ON TABLE crm.settlement_counterparty_posting IS
    'Immutable signed counterparty balance movements. Positive means value in the counterparty favour; negative means debt to the company.';
