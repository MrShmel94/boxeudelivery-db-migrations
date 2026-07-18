ALTER TABLE crm.cargo_item_financial_entry
    ALTER COLUMN currency_code TYPE VARCHAR(3)
        USING BTRIM(currency_code)::VARCHAR(3);

ALTER TABLE crm.cargo_item_financial_revision
    ALTER COLUMN currency_code TYPE VARCHAR(3)
        USING BTRIM(currency_code)::VARCHAR(3);
