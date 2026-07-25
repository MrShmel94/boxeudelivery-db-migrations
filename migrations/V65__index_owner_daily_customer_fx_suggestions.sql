CREATE INDEX ix_customer_fx_quote_personal_daily_suggestion
    ON crm.cargo_item_customer_fx_quote_snapshot (
        owner_account_id,
        purchase_date,
        base_currency_code,
        quote_currency_code,
        created_at DESC,
        id DESC
    )
    WHERE active AND owner_account_id IS NOT NULL;

CREATE INDEX ix_customer_fx_quote_supplier_daily_suggestion
    ON crm.cargo_item_customer_fx_quote_snapshot (
        project_id,
        owner_supplier_id,
        purchase_date,
        base_currency_code,
        quote_currency_code,
        created_at DESC,
        id DESC
    )
    WHERE active AND owner_supplier_id IS NOT NULL;

COMMENT ON INDEX crm.ix_customer_fx_quote_personal_daily_suggestion IS
    'Supports the latest same-day, same-pair customer FX suggestion for an exact personal owner.';

COMMENT ON INDEX crm.ix_customer_fx_quote_supplier_daily_suggestion IS
    'Supports the latest same-day, same-pair customer FX suggestion for the current project supplier group.';
