ALTER TABLE crm.cargo_item_financial_entry
    ADD COLUMN active BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE crm.cargo_item_financial_revision
    DROP CONSTRAINT ck_cargo_item_financial_revision_reason,
    ADD CONSTRAINT ck_cargo_item_financial_revision_reason
        CHECK (
            (
                action_code IN ('CORRECTED', 'DELETED')
                AND reason IS NOT NULL
                AND BTRIM(reason) <> ''
            )
            OR (
                action_code NOT IN ('CORRECTED', 'DELETED')
                AND reason IS NULL
            )
        );

CREATE INDEX ix_cargo_item_financial_entry_item_active_type
    ON crm.cargo_item_financial_entry (cargo_item_id, active, entry_type);

COMMENT ON COLUMN crm.cargo_item_financial_entry.active IS
    'Whether this typed value is currently effective. Inactive rows remain for immutable revision and audit history.';
