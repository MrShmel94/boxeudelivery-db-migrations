CREATE TABLE crm.settlement_receipt_preference
(
    preference_code   VARCHAR(32)  NOT NULL,
    cashbox_id        UUID,
    updated_by_subject VARCHAR(255),
    updated_at        TIMESTAMPTZ,
    version           BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_settlement_receipt_preference
        PRIMARY KEY (preference_code),
    CONSTRAINT fk_settlement_receipt_preference_cashbox
        FOREIGN KEY (cashbox_id) REFERENCES crm.settlement_cashbox (id) ON DELETE RESTRICT,
    CONSTRAINT ck_settlement_receipt_preference_code
        CHECK (preference_code = 'CUSTOMER_ORDER_RECEIPT'),
    CONSTRAINT ck_settlement_receipt_preference_shape
        CHECK (
            (cashbox_id IS NULL AND updated_by_subject IS NULL AND updated_at IS NULL)
            OR
            (cashbox_id IS NOT NULL
                AND updated_by_subject IS NOT NULL
                AND BTRIM(updated_by_subject) <> ''
                AND updated_at IS NOT NULL)
        ),
    CONSTRAINT ck_settlement_receipt_preference_version
        CHECK (version >= 0)
);

INSERT INTO crm.settlement_receipt_preference (
    preference_code,
    cashbox_id,
    updated_by_subject,
    updated_at,
    version
)
VALUES ('CUSTOMER_ORDER_RECEIPT', NULL, NULL, NULL, 0);

COMMENT ON TABLE crm.settlement_receipt_preference IS
    'Singleton company preference for the physical cashbox used by automatic customer-order receipts.';

COMMENT ON COLUMN crm.settlement_receipt_preference.cashbox_id IS
    'Preferred physical cashbox; its active currency child is selected for each automatic order receipt.';
