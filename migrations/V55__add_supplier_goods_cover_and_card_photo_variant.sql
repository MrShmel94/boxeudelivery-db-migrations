ALTER TABLE crm.cargo_item_photo_object
    DROP CONSTRAINT ck_cargo_item_photo_object_variant,
    ADD CONSTRAINT ck_cargo_item_photo_object_variant
        CHECK (variant_code IN ('ORIGINAL', 'PREVIEW', 'CARD'));

ALTER TABLE crm.cargo_item_photo
    ADD CONSTRAINT uq_cargo_item_photo_id_goods
        UNIQUE (id, supplier_goods_entry_id);

ALTER TABLE crm.supplier_goods_entry
    ADD COLUMN cover_photo_id UUID,
    ADD CONSTRAINT fk_supplier_goods_entry_cover_photo
        FOREIGN KEY (cover_photo_id, id)
            REFERENCES crm.cargo_item_photo (id, supplier_goods_entry_id) ON DELETE RESTRICT;

CREATE INDEX ix_supplier_goods_entry_cover_photo
    ON crm.supplier_goods_entry (cover_photo_id)
    WHERE cover_photo_id IS NOT NULL;

COMMENT ON COLUMN crm.supplier_goods_entry.cover_photo_id IS
    'Explicit READY gallery photo selected as the goods-card cover; NULL preserves the first-ready-photo fallback.';

COMMENT ON TABLE crm.cargo_item_photo_object IS
    'Verified original plus backend-generated PREVIEW and compact CARD JPEG variants stored in private S3-compatible storage.';

UPDATE crm.cargo_photo_processing_job job
SET status_code = 'PENDING',
    attempt_count = 0,
    not_before = CURRENT_TIMESTAMP,
    locked_at = NULL,
    locked_by = NULL,
    last_error_code = NULL,
    updated_at = CURRENT_TIMESTAMP
FROM crm.cargo_item_photo photo
WHERE photo.id = job.photo_id
  AND photo.status_code = 'READY'
  AND job.status_code = 'DONE'
  AND EXISTS (
      SELECT 1
      FROM crm.cargo_item_photo_object original_object
      WHERE original_object.photo_id = photo.id
        AND original_object.variant_code = 'ORIGINAL'
  )
  AND NOT EXISTS (
      SELECT 1
      FROM crm.cargo_item_photo_object card_object
      WHERE card_object.photo_id = photo.id
        AND card_object.variant_code = 'CARD'
  );
