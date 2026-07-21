CREATE INDEX ix_task_search_key_prefix
    ON crm.task (UPPER(task_key) text_pattern_ops);

CREATE INDEX ix_task_search_title
    ON crm.task USING GIN (to_tsvector('simple', title));

CREATE INDEX ix_inbound_delivery_search_number_prefix
    ON crm.inbound_delivery (UPPER(delivery_number) text_pattern_ops);

CREATE INDEX ix_inbound_delivery_search_tracking_prefix
    ON crm.inbound_delivery (UPPER(tracking_number) text_pattern_ops)
    WHERE tracking_number IS NOT NULL;

CREATE INDEX ix_inbound_package_search_number_prefix
    ON crm.inbound_package (UPPER(package_number) text_pattern_ops);

CREATE INDEX ix_courier_trip_search_number_prefix
    ON crm.courier_trip (UPPER(trip_number) text_pattern_ops);

CREATE INDEX ix_customer_order_search_number_prefix
    ON crm.customer_order (UPPER(order_number) text_pattern_ops);

CREATE INDEX ix_outbound_package_search_number_prefix
    ON crm.outbound_package (UPPER(package_number) text_pattern_ops);

CREATE INDEX ix_outbound_delivery_search_number_prefix
    ON crm.outbound_delivery (UPPER(delivery_number) text_pattern_ops);

CREATE INDEX ix_outbound_delivery_search_tracking_prefix
    ON crm.outbound_delivery (UPPER(tracking_number) text_pattern_ops)
    WHERE tracking_number IS NOT NULL;

CREATE INDEX ix_warehouse_relocation_search_number_prefix
    ON crm.warehouse_relocation (UPPER(relocation_number) text_pattern_ops);

COMMENT ON INDEX crm.ix_task_search_title IS
    'Task-title full-text index. Conversation message bodies are deliberately excluded from task search.';
