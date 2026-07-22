CREATE INDEX ix_customer_order_global_created
    ON crm.customer_order (created_at DESC, id DESC);

CREATE INDEX ix_customer_order_project_status_created
    ON crm.customer_order (project_id, status_code, created_at DESC, id DESC);

CREATE INDEX ix_customer_order_search_number_trigram
    ON crm.customer_order USING GIN (
        (upper(order_number)) gin_trgm_ops
    );

COMMENT ON INDEX crm.ix_customer_order_global_created IS
    'Supports stable cross-project order pagination by newest order first.';

COMMENT ON INDEX crm.ix_customer_order_project_status_created IS
    'Supports project and lifecycle filtering in the global customer-order register.';

COMMENT ON INDEX crm.ix_customer_order_search_number_trigram IS
    'Supports case-insensitive fragment search by immutable human-readable order number.';
