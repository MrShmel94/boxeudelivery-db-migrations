ALTER TABLE crm.cargo_item_photo
    DROP CONSTRAINT ck_cargo_item_photo_content_type;

ALTER TABLE crm.cargo_item_photo
    ADD CONSTRAINT ck_cargo_item_photo_content_type
        CHECK (declared_content_type IN ('image/jpeg', 'image/png', 'image/webp'));

ALTER TABLE crm.supplier_goods_photo_draft_file
    DROP CONSTRAINT ck_supplier_goods_photo_draft_file_content_type;

ALTER TABLE crm.supplier_goods_photo_draft_file
    ADD CONSTRAINT ck_supplier_goods_photo_draft_file_content_type
        CHECK (declared_content_type IN ('image/jpeg', 'image/png', 'image/webp'));

ALTER TABLE crm.supplier_goods_photo_draft_file
    ADD COLUMN verified_content_type VARCHAR(255);

UPDATE crm.supplier_goods_photo_draft_file
SET verified_content_type = declared_content_type
WHERE status_code IN ('VERIFIED', 'ADOPTED');

ALTER TABLE crm.supplier_goods_photo_draft_file
    ADD CONSTRAINT ck_supplier_goods_photo_draft_file_verified_content_type
        CHECK (
            verified_content_type IS NULL
            OR verified_content_type IN ('image/jpeg', 'image/png', 'image/webp')
        );

COMMENT ON COLUMN crm.supplier_goods_photo_draft_file.verified_content_type IS
    'Content type detected from decodable image bytes after upload verification; declared browser metadata is not authoritative.';
