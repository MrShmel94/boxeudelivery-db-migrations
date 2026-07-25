DO
$$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM crm.cargo_item_customer_fx_quote_snapshot quote
        LEFT JOIN crm.cargo_item_financial_revision purchase_revision
            ON purchase_revision.financial_entry_id = quote.purchase_entry_id
           AND purchase_revision.revision_number = quote.purchase_revision
           AND purchase_revision.cargo_item_id = quote.cargo_item_id
           AND purchase_revision.project_id = quote.project_id
           AND purchase_revision.entry_type = 'SUPPLIER_PURCHASE_COST'
        WHERE purchase_revision.effective_on IS NULL
    ) THEN
        RAISE EXCEPTION
            'Customer FX quote snapshots require a purchase date on the exact supplier purchase-cost revision';
    END IF;
END
$$;

UPDATE crm.cargo_item_customer_fx_quote_snapshot quote
SET quoted_on = purchase_revision.effective_on
FROM crm.cargo_item_financial_revision purchase_revision
WHERE purchase_revision.financial_entry_id = quote.purchase_entry_id
  AND purchase_revision.revision_number = quote.purchase_revision
  AND purchase_revision.cargo_item_id = quote.cargo_item_id
  AND purchase_revision.project_id = quote.project_id
  AND purchase_revision.entry_type = 'SUPPLIER_PURCHASE_COST';

ALTER TABLE crm.cargo_item_customer_fx_quote_snapshot
    RENAME COLUMN quoted_on TO purchase_date;

COMMENT ON COLUMN crm.cargo_item_customer_fx_quote_snapshot.purchase_date IS
    'Purchase date copied from the exact supplier purchase-cost revision; callers cannot provide or change it through the customer FX quote API.';

COMMENT ON COLUMN crm.cargo_item_customer_fx_quote_snapshot.visibility_scope_code IS
    'PERSONAL is visible only to the owning account and global OWNER; SUPPLIER_GROUP follows current active group membership and is also visible to global OWNER.';
