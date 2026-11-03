ALTER TABLE crm.sales_request ADD COLUMN website_context JSONB
    CHECK (website_context IS NULL OR jsonb_typeof(website_context)='object');
ALTER TABLE crm.sales_request_line ALTER COLUMN characteristics TYPE VARCHAR(2000);
