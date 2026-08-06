ALTER TABLE crm.task_category
    ADD COLUMN managed_task_source_code VARCHAR(32),
    ADD CONSTRAINT ck_task_category_managed_task_source
        CHECK (
            managed_task_source_code IS NULL
            OR managed_task_source_code IN (
                'INBOUND_DELIVERY',
                'COURIER_TRIP',
                'CUSTOMER_ORDER',
                'CUSTOMER_ORDER_SHIPMENT',
                'CUSTOMER_ORDER_HANDOVER',
                'CUSTOMER_ORDER_DELIVERY',
                'WAREHOUSE_RELOCATION',
                'FULFILLMENT_SHIPMENT',
                'FULFILLMENT_RETURN'
            )
        ),
    ADD CONSTRAINT ck_task_category_managed_task_source_scope
        CHECK (
            managed_task_source_code IS NULL
            OR (country_code IS NOT NULL AND system_code IS NULL)
        );

CREATE UNIQUE INDEX uq_task_category_country_managed_task_source
    ON crm.task_category (country_code, managed_task_source_code)
    WHERE managed_task_source_code IS NOT NULL;

CREATE TABLE crm.task_subcategory_usage
(
    subcategory_id UUID        NOT NULL,
    task_id        UUID        NOT NULL,
    first_used_at  TIMESTAMPTZ NOT NULL,
    CONSTRAINT pk_task_subcategory_usage PRIMARY KEY (subcategory_id, task_id),
    CONSTRAINT fk_task_subcategory_usage_subcategory
        FOREIGN KEY (subcategory_id) REFERENCES crm.task_subcategory (id) ON DELETE RESTRICT
);

INSERT INTO crm.task_subcategory_usage (subcategory_id, task_id, first_used_at)
SELECT usage.subcategory_id,
       usage.task_id,
       MIN(usage.used_at)
FROM (
    SELECT task.task_subcategory_id AS subcategory_id,
           task.id                  AS task_id,
           task.created_at          AS used_at
    FROM crm.task task
    WHERE task.task_subcategory_id IS NOT NULL

    UNION ALL

    SELECT subcategory.id  AS subcategory_id,
           audit.task_id   AS task_id,
           audit.occurred_at AS used_at
    FROM crm.task_audit_event audit
    JOIN crm.task_subcategory subcategory
      ON subcategory.id::TEXT = LOWER(audit.details ->> 'subcategoryId')
    WHERE audit.details ? 'subcategoryId'
) usage
GROUP BY usage.subcategory_id, usage.task_id
ON CONFLICT (subcategory_id, task_id) DO NOTHING;

CREATE OR REPLACE FUNCTION crm.record_task_subcategory_usage()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.task_subcategory_id IS NOT NULL THEN
        INSERT INTO crm.task_subcategory_usage (subcategory_id, task_id, first_used_at)
        VALUES (NEW.task_subcategory_id, NEW.id, CURRENT_TIMESTAMP)
        ON CONFLICT (subcategory_id, task_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_task_subcategory_usage
    AFTER INSERT OR UPDATE OF task_subcategory_id
    ON crm.task
    FOR EACH ROW
EXECUTE FUNCTION crm.record_task_subcategory_usage();

COMMENT ON COLUMN crm.task_category.managed_task_source_code IS
    'Optional stable managed-process binding for an administrator-managed country category. Display names remain editable and are never used as identity.';

COMMENT ON TABLE crm.task_subcategory_usage IS
    'Immutable evidence that a task used a subcategory. Task identifiers intentionally have no foreign key so deletion history survives task removal.';
