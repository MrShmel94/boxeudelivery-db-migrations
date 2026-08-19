ALTER TABLE crm.supplier_goods_entry
    ADD COLUMN deleted_by_subject varchar(255),
    ADD COLUMN deleted_at timestamptz,
    ADD COLUMN deletion_reason varchar(500),
    ADD CONSTRAINT supplier_goods_entry_deletion_metadata_check CHECK (
        (deleted_at IS NULL AND deleted_by_subject IS NULL AND deletion_reason IS NULL)
        OR (
            deleted_at IS NOT NULL
            AND deleted_by_subject IS NOT NULL
            AND btrim(deleted_by_subject) <> ''
            AND deletion_reason IS NOT NULL
            AND btrim(deletion_reason) <> ''
        )
    );

CREATE INDEX supplier_goods_entry_active_project_updated_idx
    ON crm.supplier_goods_entry (project_id, updated_at DESC, id)
    WHERE deleted_at IS NULL;
