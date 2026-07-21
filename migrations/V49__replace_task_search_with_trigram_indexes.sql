DROP INDEX crm.ix_task_search_key_prefix;
DROP INDEX crm.ix_task_search_title;
DROP INDEX crm.ix_inbound_delivery_search_number_prefix;
DROP INDEX crm.ix_inbound_delivery_search_tracking_prefix;
DROP INDEX crm.ix_inbound_package_search_number_prefix;
DROP INDEX crm.ix_courier_trip_search_number_prefix;
DROP INDEX crm.ix_customer_order_search_number_prefix;
DROP INDEX crm.ix_outbound_package_search_number_prefix;
DROP INDEX crm.ix_outbound_delivery_search_number_prefix;
DROP INDEX crm.ix_outbound_delivery_search_tracking_prefix;
DROP INDEX crm.ix_warehouse_relocation_search_number_prefix;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX ix_task_search_key_trigram
    ON crm.task USING GIN (
        (translate(lower(task_key), 'ё', 'е')) gin_trgm_ops
    );

CREATE INDEX ix_task_search_title_trigram
    ON crm.task USING GIN (
        (translate(lower(title), 'ё', 'е')) gin_trgm_ops
    );

COMMENT ON INDEX crm.ix_task_search_title_trigram IS
    'Case-insensitive fragment search over task titles with Russian е/ё normalization; conversation data is excluded.';
