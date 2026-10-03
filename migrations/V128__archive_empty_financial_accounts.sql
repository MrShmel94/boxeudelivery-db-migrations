ALTER TABLE crm.settlement_financial_account
    ADD COLUMN archived_reason VARCHAR(500),
    ADD COLUMN archived_at TIMESTAMPTZ,
    ADD CONSTRAINT ck_settlement_financial_account_archive CHECK (
        (archived_reason IS NULL AND archived_at IS NULL)
        OR
        (status_code = 'INACTIVE' AND archived_reason IS NOT NULL
            AND BTRIM(archived_reason) <> '' AND archived_at IS NOT NULL)
    );
