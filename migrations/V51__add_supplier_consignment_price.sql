ALTER TABLE crm.cargo_item_financial_entry
    DROP CONSTRAINT ck_cargo_item_financial_entry_type,
    ADD CONSTRAINT ck_cargo_item_financial_entry_type
        CHECK (entry_type IN (
            'SUPPLIER_PURCHASE_COST',
            'SUPPLIER_CONSIGNMENT_PRICE',
            'CUSTOMER_ITEM_PRICE',
            'BORDER_TRANSPORT_PRICE',
            'BORDER_TRANSPORT_ACTUAL_COST',
            'COMPANY_SERVICE_FEE'
        ));

ALTER TABLE crm.cargo_item_financial_revision
    DROP CONSTRAINT ck_cargo_item_financial_revision_type,
    ADD CONSTRAINT ck_cargo_item_financial_revision_type
        CHECK (entry_type IN (
            'SUPPLIER_PURCHASE_COST',
            'SUPPLIER_CONSIGNMENT_PRICE',
            'CUSTOMER_ITEM_PRICE',
            'BORDER_TRANSPORT_PRICE',
            'BORDER_TRANSPORT_ACTUAL_COST',
            'COMPANY_SERVICE_FEE'
        ));

COMMENT ON CONSTRAINT ck_cargo_item_financial_entry_type
    ON crm.cargo_item_financial_entry IS
    'Allowed exact-item financial facts, including the optional supplier consignment price.';

COMMENT ON CONSTRAINT ck_cargo_item_financial_revision_type
    ON crm.cargo_item_financial_revision IS
    'Allowed immutable financial revision types, including the optional supplier consignment price.';
