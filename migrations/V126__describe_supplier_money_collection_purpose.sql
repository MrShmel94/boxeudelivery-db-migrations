ALTER TABLE crm.settlement_supplier_money_collection
    ADD COLUMN purpose VARCHAR(300) NOT NULL DEFAULT 'Получение денег для поставщика',
    ADD CONSTRAINT ck_settlement_supplier_money_collection_purpose CHECK (BTRIM(purpose) <> '');

ALTER TABLE crm.settlement_supplier_money_collection
    ALTER COLUMN purpose DROP DEFAULT;
