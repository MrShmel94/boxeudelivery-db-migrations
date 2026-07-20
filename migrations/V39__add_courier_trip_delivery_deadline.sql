ALTER TABLE crm.courier_trip
    ADD COLUMN delivery_deadline_at TIMESTAMPTZ,
    ADD COLUMN delivery_deadline_zone_id VARCHAR(64);

WITH earliest_delivery_deadline AS (
    SELECT DISTINCT ON (link.courier_trip_id)
        link.courier_trip_id,
        delivery.delivery_deadline_at,
        delivery.delivery_deadline_zone_id
    FROM crm.courier_trip_delivery link
    JOIN crm.inbound_delivery delivery ON delivery.id = link.inbound_delivery_id
    ORDER BY
        link.courier_trip_id,
        delivery.delivery_deadline_at,
        link.sequence_number
)
UPDATE crm.courier_trip trip
SET delivery_deadline_at = earliest.delivery_deadline_at,
    delivery_deadline_zone_id = earliest.delivery_deadline_zone_id
FROM earliest_delivery_deadline earliest
WHERE earliest.courier_trip_id = trip.id;

ALTER TABLE crm.courier_trip
    ALTER COLUMN delivery_deadline_at SET NOT NULL,
    ALTER COLUMN delivery_deadline_zone_id SET NOT NULL,
    ADD CONSTRAINT ck_courier_trip_delivery_deadline_zone_not_blank
        CHECK (BTRIM(delivery_deadline_zone_id) <> ''),
    ADD CONSTRAINT ck_courier_trip_deadline_order
        CHECK (pickup_deadline_at <= delivery_deadline_at);

COMMENT ON COLUMN crm.courier_trip.delivery_deadline_at IS
    'Earliest warehouse-arrival deadline among member deliveries when the trip was created.';

COMMENT ON COLUMN crm.courier_trip.delivery_deadline_zone_id IS
    'Display-zone snapshot belonging to the earliest warehouse-arrival deadline.';
