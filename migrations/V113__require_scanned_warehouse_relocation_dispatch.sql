ALTER TABLE crm.warehouse_relocation_item
    ADD COLUMN dispatch_scanned_by_account_id UUID,
    ADD COLUMN dispatch_scanned_by_subject VARCHAR(255),
    ADD COLUMN dispatch_scanned_at TIMESTAMPTZ,
    ADD CONSTRAINT fk_warehouse_relocation_item_dispatch_scanner
        FOREIGN KEY (dispatch_scanned_by_account_id)
            REFERENCES crm.account (id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_warehouse_relocation_item_dispatch_scan CHECK (
        (
            dispatch_scanned_by_account_id IS NULL
            AND dispatch_scanned_by_subject IS NULL
            AND dispatch_scanned_at IS NULL
        )
        OR (
            dispatch_scanned_by_account_id IS NOT NULL
            AND dispatch_scanned_by_subject IS NOT NULL
            AND BTRIM(dispatch_scanned_by_subject) <> ''
            AND dispatch_scanned_at IS NOT NULL
        )
    );

CREATE INDEX ix_warehouse_relocation_item_dispatch_progress
    ON crm.warehouse_relocation_item (relocation_id, dispatch_scanned_at);

COMMENT ON COLUMN crm.warehouse_relocation_item.dispatch_scanned_at IS
    'Mobile source-warehouse scan proving that this exact labelled unit was physically prepared before relocation dispatch.';
