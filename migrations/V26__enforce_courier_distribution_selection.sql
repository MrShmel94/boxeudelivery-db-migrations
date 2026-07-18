ALTER TABLE crm.inbound_delivery
    DROP CONSTRAINT ck_inbound_delivery_courier_configuration,
    ADD CONSTRAINT ck_inbound_delivery_courier_configuration
        CHECK (
            (
                transport_mode = 'DIRECT_TO_WAREHOUSE'
                AND courier_distribution_mode = 'OPEN_POOL'
                AND designated_courier_account_id IS NULL
                AND pickup_deadline_at IS NULL
                AND pickup_deadline_zone_id IS NULL
            )
            OR (
                transport_mode = 'COURIER_VIA_PICKUP_POINT'
                AND pickup_deadline_at IS NOT NULL
                AND pickup_deadline_zone_id IS NOT NULL
                AND (
                    (
                        courier_distribution_mode = 'OPEN_POOL'
                        AND designated_courier_account_id IS NULL
                    )
                    OR (
                        courier_distribution_mode = 'DIRECT_ASSIGNMENT'
                        AND (
                            designated_courier_account_id IS NOT NULL
                            OR status_code = 'READY_FOR_COURIER_PICKUP'
                        )
                    )
                )
            )
        );

COMMENT ON CONSTRAINT ck_inbound_delivery_courier_configuration ON crm.inbound_delivery IS
    'Courier routes require an exact deadline. OPEN_POOL has no selected courier; DIRECT_ASSIGNMENT requires one except while a ready job privately awaits reassignment after decline or emergency release.';
