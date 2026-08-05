CREATE TABLE crm.mini_supplier_intake
(
    id                      UUID         NOT NULL,
    project_id              UUID         NOT NULL,
    supplier_id             UUID         NOT NULL,
    supplier_goods_entry_id UUID         NOT NULL,
    created_by_account_id   UUID         NOT NULL,
    created_by_subject      VARCHAR(255) NOT NULL,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_by_account_id UUID,
    completed_by_subject    VARCHAR(255),
    completed_at            TIMESTAMPTZ,
    version                 BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_mini_supplier_intake PRIMARY KEY (id),
    CONSTRAINT uq_mini_supplier_intake_project UNIQUE (id, project_id),
    CONSTRAINT uq_mini_supplier_intake_scope UNIQUE (id, project_id, supplier_id),
    CONSTRAINT fk_mini_supplier_intake_entry
        FOREIGN KEY (supplier_goods_entry_id, project_id, supplier_id)
            REFERENCES crm.supplier_goods_entry (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mini_supplier_intake_created_by
        FOREIGN KEY (created_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_mini_supplier_intake_completed_by
        FOREIGN KEY (completed_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_mini_supplier_intake_creator_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_mini_supplier_intake_completion_shape
        CHECK (
            (completed_at IS NULL AND completed_by_account_id IS NULL AND completed_by_subject IS NULL)
            OR (
                completed_at IS NOT NULL
                AND completed_at >= created_at
                AND completed_by_account_id IS NOT NULL
                AND completed_by_subject IS NOT NULL
                AND BTRIM(completed_by_subject) <> ''
            )
        )
);

CREATE INDEX ix_mini_supplier_intake_entry_created
    ON crm.mini_supplier_intake (supplier_goods_entry_id, created_at DESC, id DESC);

CREATE TABLE crm.mini_supplier_intake_item
(
    intake_id     UUID       NOT NULL,
    cargo_item_id UUID       NOT NULL,
    project_id    UUID       NOT NULL,
    supplier_id   UUID       NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_mini_supplier_intake_item PRIMARY KEY (intake_id, cargo_item_id),
    CONSTRAINT uq_mini_supplier_intake_item_cargo UNIQUE (cargo_item_id),
    CONSTRAINT fk_mini_supplier_intake_item_intake
        FOREIGN KEY (intake_id, project_id, supplier_id)
            REFERENCES crm.mini_supplier_intake (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mini_supplier_intake_item_cargo
        FOREIGN KEY (cargo_item_id, project_id, supplier_id)
            REFERENCES crm.cargo_item (id, project_id, supplier_id) ON DELETE RESTRICT
);

CREATE INDEX ix_mini_supplier_intake_item_intake
    ON crm.mini_supplier_intake_item (intake_id, cargo_item_id);

ALTER TABLE crm.task
    DROP CONSTRAINT ck_task_standalone_managed_shape,
    DROP CONSTRAINT ck_task_deadline_required_shape,
    ADD COLUMN mini_supplier_intake_id UUID,
    ADD CONSTRAINT uq_task_mini_supplier_intake UNIQUE (mini_supplier_intake_id),
    ADD CONSTRAINT fk_task_mini_supplier_intake
        FOREIGN KEY (mini_supplier_intake_id, project_id)
            REFERENCES crm.mini_supplier_intake (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_task_standalone_managed_shape CHECK (
        NUM_NONNULLS(
            customer_order_id,
            warehouse_relocation_id,
            fulfillment_shipment_id,
            fulfillment_return_id,
            mini_supplier_intake_id
        ) = 0
        OR (
            NUM_NONNULLS(
                customer_order_id,
                warehouse_relocation_id,
                fulfillment_shipment_id,
                fulfillment_return_id,
                mini_supplier_intake_id
            ) = 1
            AND inbound_delivery_id IS NULL
            AND courier_trip_id IS NULL
            AND parent_task_id IS NULL
        )
    ),
    ADD CONSTRAINT ck_task_deadline_required_shape CHECK (
        deadline_at IS NOT NULL
        OR customer_order_id IS NOT NULL
        OR warehouse_relocation_id IS NOT NULL
        OR fulfillment_shipment_id IS NOT NULL
        OR fulfillment_return_id IS NOT NULL
        OR mini_supplier_intake_id IS NOT NULL
    );

CREATE INDEX ix_task_mini_supplier_intake
    ON crm.task (mini_supplier_intake_id)
    WHERE mini_supplier_intake_id IS NOT NULL;

COMMENT ON TABLE crm.mini_supplier_intake IS
    'One immutable MINI goods materialization batch travelling directly to a warehouse. Its task completes only after every linked item leaves transit.';
COMMENT ON TABLE crm.mini_supplier_intake_item IS
    'Exact physical units belonging to one MINI intake batch; a reusable goods card may have many independent batches.';
COMMENT ON COLUMN crm.task.mini_supplier_intake_id IS
    'One-to-one MINI intake binding. The intake lifecycle is the only terminal-state authority.';
