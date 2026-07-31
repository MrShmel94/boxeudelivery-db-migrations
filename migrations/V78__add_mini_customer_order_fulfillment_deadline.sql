-- A MINI order owns its operational completion deadline. Existing orders are
-- intentionally left without a fabricated date; the application requires a
-- real future deadline before a legacy MINI draft can be updated or confirmed.

ALTER TABLE crm.customer_order
    ADD COLUMN fulfillment_deadline_at TIMESTAMPTZ,
    ADD COLUMN fulfillment_deadline_zone_id VARCHAR(64),
    ADD CONSTRAINT ck_customer_order_fulfillment_deadline_kind
        CHECK (
            order_kind_code = 'MINI'
            OR (fulfillment_deadline_at IS NULL AND fulfillment_deadline_zone_id IS NULL)
        ),
    ADD CONSTRAINT ck_customer_order_fulfillment_deadline_pair
        CHECK (
            (fulfillment_deadline_at IS NULL AND fulfillment_deadline_zone_id IS NULL)
            OR (
                fulfillment_deadline_at IS NOT NULL
                AND fulfillment_deadline_zone_id IS NOT NULL
                AND BTRIM(fulfillment_deadline_zone_id) <> ''
            )
        );

COMMENT ON COLUMN crm.customer_order.fulfillment_deadline_at IS
    'Operational completion deadline owned by a MINI order and projected to its managed task.';

COMMENT ON COLUMN crm.customer_order.fulfillment_deadline_zone_id IS
    'Project time-zone snapshot used to present the MINI order fulfillment deadline.';
