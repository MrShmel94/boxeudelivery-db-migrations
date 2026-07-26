ALTER TABLE crm.border_tariff_policy_minimum
    ADD COLUMN actual_cost_usd NUMERIC(19, 4);

ALTER TABLE crm.border_tariff_policy_minimum
    ADD CONSTRAINT ck_border_tariff_policy_actual_cost
        CHECK (actual_cost_usd IS NULL OR actual_cost_usd >= 0);

ALTER TABLE crm.cargo_item_border_tariff_calculation
    ADD COLUMN policy_actual_cost_usd NUMERIC(19, 4),
    ADD COLUMN generated_actual_cost_entry_id UUID;

ALTER TABLE crm.cargo_item_border_tariff_calculation
    ADD CONSTRAINT fk_cargo_item_border_tariff_calculation_actual_cost_entry
        FOREIGN KEY (generated_actual_cost_entry_id)
            REFERENCES crm.cargo_item_financial_entry (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_cargo_item_border_tariff_calculation_actual_cost
        CHECK (
            (policy_actual_cost_usd IS NULL AND generated_actual_cost_entry_id IS NULL)
            OR (policy_actual_cost_usd >= 0 AND generated_actual_cost_entry_id IS NOT NULL)
        );

COMMENT ON COLUMN crm.border_tariff_policy_minimum.actual_cost_usd IS
    'Versioned internal transport cost for one physical item in this tariff subcategory. Null is allowed only for historical or incomplete drafts.';

COMMENT ON COLUMN crm.cargo_item_border_tariff_calculation.policy_actual_cost_usd IS
    'Immutable internal transport-cost value copied from the governing tariff policy.';

COMMENT ON COLUMN crm.cargo_item_border_tariff_calculation.generated_actual_cost_entry_id IS
    'The exact-item BORDER_TRANSPORT_ACTUAL_COST entry initialized from the governing tariff policy.';
