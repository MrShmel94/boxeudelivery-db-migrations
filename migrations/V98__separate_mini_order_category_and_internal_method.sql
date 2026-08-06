ALTER TABLE crm.task_subcategory
    ADD CONSTRAINT uq_task_subcategory_id_category UNIQUE (id, category_id);

ALTER TABLE crm.task
    ADD COLUMN task_category_id UUID;

UPDATE crm.task task
SET task_category_id = subcategory.category_id
FROM crm.task_subcategory subcategory
WHERE subcategory.id = task.task_subcategory_id;

ALTER TABLE crm.task
    ADD CONSTRAINT fk_task_category
        FOREIGN KEY (task_category_id) REFERENCES crm.task_category (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_task_classification_pair
        FOREIGN KEY (task_subcategory_id, task_category_id)
            REFERENCES crm.task_subcategory (id, category_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_task_classification_category
        CHECK (task_subcategory_id IS NULL OR task_category_id IS NOT NULL);

CREATE INDEX ix_task_category
    ON crm.task (task_category_id)
    WHERE task_category_id IS NOT NULL;

ALTER TABLE crm.customer_order
    ADD COLUMN mini_task_category_id UUID;

UPDATE crm.customer_order customer_order
SET mini_task_category_id = subcategory.category_id
FROM crm.task_subcategory subcategory
WHERE subcategory.id = customer_order.mini_task_subcategory_id;

ALTER TABLE crm.customer_order
    DROP CONSTRAINT ck_customer_order_mini_task_subcategory,
    ADD CONSTRAINT fk_customer_order_mini_task_category
        FOREIGN KEY (mini_task_category_id) REFERENCES crm.task_category (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_customer_order_mini_task_classification_pair
        FOREIGN KEY (mini_task_subcategory_id, mini_task_category_id)
            REFERENCES crm.task_subcategory (id, category_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_customer_order_mini_task_classification
        CHECK (
            (
                order_kind_code = 'MINI'
                AND mini_task_category_id IS NOT NULL
            )
            OR (
                order_kind_code = 'STANDARD'
                AND mini_task_category_id IS NULL
                AND mini_task_subcategory_id IS NULL
            )
        );

CREATE INDEX ix_customer_order_mini_task_category
    ON crm.customer_order (mini_task_category_id, created_at DESC, id)
    WHERE mini_task_category_id IS NOT NULL;

COMMENT ON COLUMN crm.task.task_category_id IS
    'Stable task category. A managed task may temporarily have no narrower subcategory until an internal participant selects the execution method.';

COMMENT ON COLUMN crm.customer_order.mini_task_category_id IS
    'Supplier-visible MINI order category. The optional subcategory is an internal execution method and may be selected later.';

COMMENT ON COLUMN crm.customer_order.mini_task_subcategory_id IS
    'Optional internal MINI execution method within mini_task_category_id; never part of the supplier-facing projection.';
