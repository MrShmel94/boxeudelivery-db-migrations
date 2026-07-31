ALTER TABLE crm.outbound_delivery
    ALTER COLUMN recipient_name DROP NOT NULL,
    ADD COLUMN supplier_charge_amount NUMERIC(19, 4),
    ADD COLUMN supplier_charge_currency VARCHAR(3),
    DROP CONSTRAINT ck_outbound_delivery_recipient_name,
    ADD CONSTRAINT ck_outbound_delivery_recipient_name
        CHECK (recipient_name IS NULL OR BTRIM(recipient_name) <> ''),
    ADD CONSTRAINT fk_outbound_delivery_supplier_charge_currency
        FOREIGN KEY (supplier_charge_currency)
            REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_outbound_delivery_supplier_charge
        CHECK (
            (supplier_charge_amount IS NULL AND supplier_charge_currency IS NULL)
            OR (supplier_charge_amount >= 0 AND supplier_charge_currency IS NOT NULL)
        );

ALTER TABLE crm.outbound_delivery_financial_revision
    ADD COLUMN supplier_charge_amount NUMERIC(19, 4),
    ADD COLUMN supplier_charge_currency VARCHAR(3),
    ADD CONSTRAINT fk_outbound_delivery_financial_revision_supplier_currency
        FOREIGN KEY (supplier_charge_currency)
            REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_outbound_delivery_financial_revision_supplier_charge
        CHECK (
            (supplier_charge_amount IS NULL AND supplier_charge_currency IS NULL)
            OR (supplier_charge_amount >= 0 AND supplier_charge_currency IS NOT NULL)
        );

COMMENT ON COLUMN crm.outbound_delivery.supplier_charge_amount IS
    'Optional delivery charge deducted from the supplier future settlement; it is not a cash movement by itself.';

COMMENT ON COLUMN crm.outbound_delivery.supplier_charge_currency IS
    'Currency of the optional supplier delivery charge.';
