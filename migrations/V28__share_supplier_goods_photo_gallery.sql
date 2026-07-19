ALTER TABLE crm.cargo_item_photo
    ADD COLUMN supplier_goods_entry_id UUID;

UPDATE crm.cargo_item_photo photo
SET supplier_goods_entry_id = item.supplier_goods_entry_id
FROM crm.cargo_item item
WHERE item.id = photo.cargo_item_id;

ALTER TABLE crm.cargo_item_photo
    ALTER COLUMN supplier_goods_entry_id SET NOT NULL,
    DROP CONSTRAINT uq_cargo_item_photo_position,
    DROP CONSTRAINT ck_cargo_item_photo_position,
    DROP CONSTRAINT fk_cargo_item_photo_item;

DROP INDEX crm.ix_cargo_item_photo_item_position;

WITH ordered_photos AS (
    SELECT photo.id,
           ROW_NUMBER() OVER (
               PARTITION BY photo.supplier_goods_entry_id
               ORDER BY photo.position, photo.created_at, photo.id
           ) - 1 AS shared_position
    FROM crm.cargo_item_photo photo
)
UPDATE crm.cargo_item_photo photo
SET position = ordered_photos.shared_position::SMALLINT
FROM ordered_photos
WHERE ordered_photos.id = photo.id;

ALTER TABLE crm.cargo_item
    ADD CONSTRAINT uq_cargo_item_id_supplier_goods_entry
        UNIQUE (id, supplier_goods_entry_id);

ALTER TABLE crm.cargo_item_photo
    ADD CONSTRAINT uq_cargo_item_photo_goods_position
        UNIQUE (supplier_goods_entry_id, position),
    ADD CONSTRAINT fk_cargo_item_photo_source_item_goods
        FOREIGN KEY (cargo_item_id, supplier_goods_entry_id)
            REFERENCES crm.cargo_item (id, supplier_goods_entry_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_cargo_item_photo_shared_position
        CHECK (position BETWEEN 0 AND 32767);

CREATE INDEX ix_cargo_item_photo_goods_position
    ON crm.cargo_item_photo (supplier_goods_entry_id, position, id);

COMMENT ON TABLE crm.cargo_item_photo IS
    'Private shared product gallery for a supplier goods entry. cargo_item_id records the physical unit used to upload the photo.';

COMMENT ON COLUMN crm.cargo_item_photo.supplier_goods_entry_id IS
    'Stable owner of the shared product gallery across all physical units of the same supplier goods entry.';

COMMENT ON COLUMN crm.cargo_item_photo.cargo_item_id IS
    'Source physical unit through which the shared gallery photo was uploaded; retained for audit.';
