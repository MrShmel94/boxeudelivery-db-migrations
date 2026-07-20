ALTER TABLE crm.inbound_delivery
    DROP CONSTRAINT ck_inbound_delivery_status,
    DROP CONSTRAINT ck_inbound_delivery_transport_lifecycle,
    ADD CONSTRAINT ck_inbound_delivery_status
        CHECK (status_code IN (
            'DRAFT',
            'IN_TRANSIT_TO_PICKUP_POINT',
            'PRICE_MODERATION',
            'READY_FOR_COURIER_PICKUP',
            'COURIER_ASSIGNED',
            'IN_TRANSIT_TO_WAREHOUSE',
            'PARTIALLY_RECEIVED',
            'COMPLETED',
            'CANCELLED'
        )),
    ADD CONSTRAINT ck_inbound_delivery_transport_lifecycle
        CHECK (
            (
                status_code IN ('DRAFT', 'CANCELLED')
                AND dispatched_at IS NULL
                AND ready_for_courier_at IS NULL
                AND courier_picked_up_at IS NULL
            )
            OR (
                status_code IN ('IN_TRANSIT_TO_PICKUP_POINT', 'PRICE_MODERATION')
                AND transport_mode = 'COURIER_VIA_PICKUP_POINT'
                AND dispatched_at IS NOT NULL
                AND ready_for_courier_at IS NULL
                AND courier_picked_up_at IS NULL
            )
            OR (
                status_code IN ('READY_FOR_COURIER_PICKUP', 'COURIER_ASSIGNED')
                AND transport_mode = 'COURIER_VIA_PICKUP_POINT'
                AND dispatched_at IS NOT NULL
                AND ready_for_courier_at IS NOT NULL
                AND courier_picked_up_at IS NULL
            )
            OR (
                status_code IN ('IN_TRANSIT_TO_WAREHOUSE', 'PARTIALLY_RECEIVED', 'COMPLETED')
                AND dispatched_at IS NOT NULL
                AND (
                    (
                        transport_mode = 'DIRECT_TO_WAREHOUSE'
                        AND ready_for_courier_at IS NULL
                        AND courier_picked_up_at IS NULL
                    )
                    OR (
                        transport_mode = 'COURIER_VIA_PICKUP_POINT'
                        AND ready_for_courier_at IS NOT NULL
                        AND courier_picked_up_at IS NOT NULL
                    )
                )
            )
        );

ALTER TABLE crm.cargo_item
    DROP CONSTRAINT ck_cargo_item_status,
    DROP CONSTRAINT ck_cargo_item_delivery_assignment,
    ADD CONSTRAINT ck_cargo_item_status CHECK (status_code IN (
        'EXPECTED_AT_SUPPLIER', 'AT_SUPPLIER', 'RESERVED_FOR_DELIVERY',
        'IN_TRANSIT_TO_PICKUP_POINT', 'PRICE_MODERATION',
        'READY_FOR_COURIER_PICKUP', 'IN_TRANSIT_TO_WAREHOUSE',
        'AVAILABLE', 'IN_RELOCATION', 'PICKED_FOR_ORDER', 'PACKED_FOR_CUSTOMER',
        'DELIVERED_TO_CUSTOMER', 'MISSING', 'DAMAGED', 'REJECTED', 'CANCELLED'
    )),
    ADD CONSTRAINT ck_cargo_item_delivery_assignment CHECK (
        (
            status_code IN ('EXPECTED_AT_SUPPLIER', 'AT_SUPPLIER', 'CANCELLED')
            AND inbound_delivery_id IS NULL
            AND inbound_delivery_line_id IS NULL
        )
        OR (
            status_code IN (
                'RESERVED_FOR_DELIVERY', 'IN_TRANSIT_TO_PICKUP_POINT',
                'PRICE_MODERATION', 'READY_FOR_COURIER_PICKUP',
                'IN_TRANSIT_TO_WAREHOUSE', 'AVAILABLE', 'IN_RELOCATION',
                'PICKED_FOR_ORDER', 'PACKED_FOR_CUSTOMER', 'DELIVERED_TO_CUSTOMER',
                'MISSING', 'DAMAGED', 'REJECTED'
            )
            AND inbound_delivery_id IS NOT NULL
            AND inbound_delivery_line_id IS NOT NULL
        )
    );

CREATE INDEX ix_inbound_delivery_price_moderation
    ON crm.inbound_delivery (project_id, updated_at DESC, id)
    WHERE status_code = 'PRICE_MODERATION';

COMMENT ON INDEX crm.ix_inbound_delivery_price_moderation IS
    'Operational queue of pickup-point deliveries blocked until every exact item has both transport prices.';
