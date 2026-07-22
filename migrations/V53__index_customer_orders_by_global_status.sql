CREATE INDEX ix_customer_order_status_created
    ON crm.customer_order (status_code, created_at DESC, id DESC);

COMMENT ON INDEX crm.ix_customer_order_status_created IS
    'Supports lifecycle filtering across all visible projects in the customer-order register.';
