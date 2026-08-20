ALTER TABLE crm.customer_order
    ADD CONSTRAINT ck_customer_order_lifecycle_v2
        CHECK (
            (
                status_code = 'DRAFT'
                AND confirmed_by_subject IS NULL
                AND confirmed_at IS NULL
                AND cancelled_by_subject IS NULL
                AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code IN ('CONFIRMED', 'PICKING', 'PACKED', 'PAYMENT_PENDING', 'FULFILLED')
                AND confirmed_by_subject IS NOT NULL
                AND BTRIM(confirmed_by_subject) <> ''
                AND confirmed_at IS NOT NULL
                AND cancelled_by_subject IS NULL
                AND cancelled_at IS NULL
                AND cancellation_reason IS NULL
            )
            OR (
                status_code = 'CANCELLED'
                AND (
                    (
                        confirmed_by_subject IS NULL
                        AND confirmed_at IS NULL
                    )
                    OR (
                        confirmed_by_subject IS NOT NULL
                        AND BTRIM(confirmed_by_subject) <> ''
                        AND confirmed_at IS NOT NULL
                    )
                )
                AND cancelled_by_subject IS NOT NULL
                AND BTRIM(cancelled_by_subject) <> ''
                AND cancelled_at IS NOT NULL
                AND cancellation_reason IS NOT NULL
                AND BTRIM(cancellation_reason) <> ''
            )
        ) NOT VALID;

ALTER TABLE crm.customer_order
    VALIDATE CONSTRAINT ck_customer_order_lifecycle_v2;

ALTER TABLE crm.customer_order
    DROP CONSTRAINT ck_customer_order_lifecycle;

ALTER TABLE crm.customer_order
    RENAME CONSTRAINT ck_customer_order_lifecycle_v2 TO ck_customer_order_lifecycle;
