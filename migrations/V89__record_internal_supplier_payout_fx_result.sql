ALTER TABLE crm.settlement_supplier_payout_leg
    ADD COLUMN actual_settlement_cost_amount NUMERIC(19, 4);

UPDATE crm.settlement_supplier_payout_leg
SET actual_settlement_cost_amount = settlement_amount
WHERE settlement_currency_code = payout_currency_code;

ALTER TABLE crm.settlement_supplier_payout_leg
    ADD CONSTRAINT ck_supplier_payout_leg_actual_cost_positive
        CHECK (
            actual_settlement_cost_amount IS NULL
            OR actual_settlement_cost_amount > 0
        ),
    ADD CONSTRAINT ck_supplier_payout_leg_same_currency_actual_cost
        CHECK (
            settlement_currency_code <> payout_currency_code
            OR actual_settlement_cost_amount = settlement_amount
        );

COMMENT ON COLUMN crm.settlement_supplier_payout_leg.actual_settlement_cost_amount IS
    'Confidential actual company cost in settlement currency for the payout amount; null only for historical cross-currency payouts whose execution cost was not recorded.';
