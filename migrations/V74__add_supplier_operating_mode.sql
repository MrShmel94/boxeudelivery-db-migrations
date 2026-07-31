ALTER TABLE crm.project_supplier
    ADD COLUMN operating_mode varchar(16);

UPDATE crm.project_supplier
SET operating_mode = 'FULL';

ALTER TABLE crm.project_supplier
    ALTER COLUMN operating_mode SET NOT NULL,
    ADD CONSTRAINT ck_project_supplier_operating_mode
        CHECK (operating_mode IN ('FULL', 'MINI'));

COMMENT ON COLUMN crm.project_supplier.operating_mode IS
    'Project-scoped supplier workflow: FULL uses the complete logistics flow, MINI uses direct warehouse goods flow.';

ALTER TABLE crm.cargo_item
    DROP CONSTRAINT ck_cargo_item_delivery_assignment,
    ADD CONSTRAINT ck_cargo_item_delivery_assignment CHECK (
        (
            inbound_delivery_id IS NULL
            AND inbound_delivery_line_id IS NULL
            AND supplier_goods_entry_id IS NOT NULL
            AND status_code IN (
                'EXPECTED_AT_SUPPLIER', 'AT_SUPPLIER',
                'IN_TRANSIT_TO_WAREHOUSE', 'AVAILABLE', 'IN_RELOCATION',
                'PICKED_FOR_ORDER', 'PACKED_FOR_CUSTOMER', 'DELIVERED_TO_CUSTOMER',
                'MISSING', 'DAMAGED', 'REJECTED', 'CANCELLED'
            )
        )
        OR (
            inbound_delivery_id IS NOT NULL
            AND inbound_delivery_line_id IS NOT NULL
            AND status_code IN (
                'RESERVED_FOR_DELIVERY', 'IN_TRANSIT_TO_PICKUP_POINT',
                'PRICE_MODERATION', 'READY_FOR_COURIER_PICKUP',
                'IN_TRANSIT_TO_WAREHOUSE', 'AVAILABLE', 'IN_RELOCATION',
                'PICKED_FOR_ORDER', 'PACKED_FOR_CUSTOMER', 'DELIVERED_TO_CUSTOMER',
                'MISSING', 'DAMAGED', 'REJECTED'
            )
        )
    );

COMMENT ON CONSTRAINT ck_cargo_item_delivery_assignment ON crm.cargo_item IS
    'Allows supplier-goods lifecycle without a delivery for direct MINI flow, while delivery-backed items retain both delivery references.';
