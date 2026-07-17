CREATE TABLE crm.inbound_delivery_number_counter
(
    calendar_year SMALLINT NOT NULL,
    last_value    BIGINT   NOT NULL,
    CONSTRAINT pk_inbound_delivery_number_counter
        PRIMARY KEY (calendar_year),
    CONSTRAINT ck_inbound_delivery_number_counter_year
        CHECK (calendar_year BETWEEN 2000 AND 9999),
    CONSTRAINT ck_inbound_delivery_number_counter_value
        CHECK (last_value > 0)
);

ALTER TABLE crm.inbound_delivery
    ADD COLUMN delivery_number VARCHAR(32);

WITH numbered AS (
    SELECT delivery.id,
           EXTRACT(YEAR FROM delivery.created_at AT TIME ZONE 'UTC')::SMALLINT AS calendar_year,
           ROW_NUMBER() OVER (
               PARTITION BY EXTRACT(YEAR FROM delivery.created_at AT TIME ZONE 'UTC')
               ORDER BY delivery.created_at, delivery.id
           ) AS sequence_number
    FROM crm.inbound_delivery delivery
)
UPDATE crm.inbound_delivery delivery
SET delivery_number = 'IN-' || numbered.calendar_year || '-' || LPAD(numbered.sequence_number::TEXT, 6, '0')
FROM numbered
WHERE numbered.id = delivery.id;

INSERT INTO crm.inbound_delivery_number_counter (calendar_year, last_value)
SELECT EXTRACT(YEAR FROM delivery.created_at AT TIME ZONE 'UTC')::SMALLINT,
       COUNT(*)
FROM crm.inbound_delivery delivery
GROUP BY EXTRACT(YEAR FROM delivery.created_at AT TIME ZONE 'UTC')::SMALLINT;

ALTER TABLE crm.inbound_delivery
    ALTER COLUMN delivery_number SET NOT NULL,
    ADD CONSTRAINT ck_inbound_delivery_number_format
        CHECK (delivery_number ~ '^IN-[0-9]{4}-[0-9]{6,}$');

CREATE UNIQUE INDEX uq_inbound_delivery_number
    ON crm.inbound_delivery (delivery_number);

CREATE INDEX ix_inbound_delivery_project_status_created
    ON crm.inbound_delivery (project_id, status_code, created_at DESC, id);

CREATE INDEX ix_inbound_delivery_project_supplier_created
    ON crm.inbound_delivery (project_id, supplier_account_id, created_at DESC, id);

CREATE INDEX ix_inbound_delivery_project_warehouse_created
    ON crm.inbound_delivery (project_id, target_warehouse_id, created_at DESC, id);

CREATE INDEX ix_inbound_delivery_line_manufacturer_article
    ON crm.inbound_delivery_line (manufacturer_article)
    WHERE manufacturer_article IS NOT NULL;

COMMENT ON COLUMN crm.inbound_delivery.delivery_number IS
    'Immutable human-readable inbound delivery number allocated by a race-safe yearly counter.';

COMMENT ON TABLE crm.inbound_delivery_number_counter IS
    'Race-safe yearly allocator for immutable human-readable inbound delivery numbers.';
