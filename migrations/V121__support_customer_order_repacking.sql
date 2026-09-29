ALTER TABLE crm.inventory_movement
    DROP CONSTRAINT ck_inventory_movement_type,
    DROP CONSTRAINT ck_inventory_movement_warehouses,
    ADD CONSTRAINT ck_inventory_movement_type CHECK (movement_type IN (
        'RECEIVED', 'PICKED_FOR_ORDER', 'DELIVERED_TO_CUSTOMER', 'RETURNED_TO_STOCK',
        'RELOCATION_DISPATCHED', 'RELOCATION_RECEIVED'
    )),
    ADD CONSTRAINT ck_inventory_movement_warehouses CHECK (
        (movement_type IN ('RECEIVED', 'RETURNED_TO_STOCK')
            AND from_warehouse_id IS NULL AND to_warehouse_id IS NOT NULL AND relocation_id IS NULL)
        OR (movement_type IN ('PICKED_FOR_ORDER', 'DELIVERED_TO_CUSTOMER')
            AND from_warehouse_id IS NOT NULL AND to_warehouse_id IS NULL AND relocation_id IS NULL)
        OR (movement_type IN ('RELOCATION_DISPATCHED', 'RELOCATION_RECEIVED')
            AND from_warehouse_id IS NOT NULL AND to_warehouse_id IS NOT NULL
            AND from_warehouse_id <> to_warehouse_id AND relocation_id IS NOT NULL)
    );

COMMENT ON COLUMN crm.inventory_movement.movement_type IS
    'Immutable inventory transition: receipt, order pick, customer handover, in-place order release, or relocation.';

ALTER TABLE crm.outbound_package
    DROP CONSTRAINT ck_outbound_package_lifecycle,
    ADD CONSTRAINT ck_outbound_package_lifecycle CHECK (
        (
            status_code = 'DRAFT'
            AND sealed_by_account_id IS NULL
            AND sealed_by_subject IS NULL
            AND sealed_at IS NULL
            AND cancelled_by_account_id IS NULL
            AND cancelled_by_subject IS NULL
            AND cancelled_at IS NULL
            AND cancellation_reason IS NULL
        )
        OR (
            status_code = 'SEALED'
            AND sealed_by_account_id IS NOT NULL
            AND sealed_by_subject IS NOT NULL
            AND BTRIM(sealed_by_subject) <> ''
            AND sealed_at IS NOT NULL
            AND cancelled_by_account_id IS NULL
            AND cancelled_by_subject IS NULL
            AND cancelled_at IS NULL
            AND cancellation_reason IS NULL
        )
        OR (
            status_code = 'CANCELLED'
            AND (
                (
                    sealed_by_account_id IS NULL
                    AND sealed_by_subject IS NULL
                    AND sealed_at IS NULL
                )
                OR (
                    sealed_by_account_id IS NOT NULL
                    AND sealed_by_subject IS NOT NULL
                    AND BTRIM(sealed_by_subject) <> ''
                    AND sealed_at IS NOT NULL
                )
            )
            AND cancelled_by_account_id IS NOT NULL
            AND cancelled_by_subject IS NOT NULL
            AND BTRIM(cancelled_by_subject) <> ''
            AND cancelled_at IS NOT NULL
            AND cancellation_reason IS NOT NULL
            AND BTRIM(cancellation_reason) <> ''
        )
    );

COMMENT ON COLUMN crm.outbound_package.sealed_at IS
    'Original seal time retained when a sealed package is cancelled for an attributable pre-handover repack.';