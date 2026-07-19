DROP INDEX IF EXISTS crm.ix_cargo_item_financial_entry_item_status;

ALTER TABLE crm.cargo_item_financial_entry
    DROP CONSTRAINT ck_cargo_item_financial_entry_status,
    DROP CONSTRAINT ck_cargo_item_financial_entry_confirmation,
    DROP CONSTRAINT ck_cargo_item_financial_entry_timestamps,
    DROP COLUMN status_code,
    DROP COLUMN confirmed_by_subject,
    DROP COLUMN confirmed_at,
    ADD CONSTRAINT ck_cargo_item_financial_entry_timestamps
        CHECK (updated_at >= created_at);

ALTER TABLE crm.cargo_item_financial_revision
    DROP CONSTRAINT ck_cargo_item_financial_revision_status,
    DROP COLUMN status_code;

COMMENT ON TABLE crm.cargo_item_financial_entry IS
    'Current effective typed monetary values for one exact physical cargo item. Visibility is derived from entry_type.';

COMMENT ON TABLE crm.cargo_item_financial_revision IS
    'Immutable financial snapshots retained for every creation and reasoned correction, including legacy lifecycle evidence.';

COMMENT ON COLUMN crm.cargo_item_financial_revision.financial_entry_id IS
    'Stable logical identity of the current financial entry across all immutable revisions.';
