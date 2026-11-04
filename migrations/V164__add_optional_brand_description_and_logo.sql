ALTER TABLE crm.product_brand
    ADD COLUMN description VARCHAR(2000),
    ADD COLUMN logo_revision UUID,
    ADD COLUMN logo_object_key VARCHAR(500),
    ADD CONSTRAINT product_brand_description_valid
        CHECK (description IS NULL OR (description = btrim(description) AND length(description) > 0)),
    ADD CONSTRAINT product_brand_logo_complete
        CHECK ((logo_revision IS NULL AND logo_object_key IS NULL)
            OR (logo_revision IS NOT NULL AND logo_object_key IS NOT NULL AND length(logo_object_key) > 0));

ALTER TABLE crm.product_brand_audit_event
    ADD COLUMN previous_details JSONB,
    ADD COLUMN details JSONB;

CREATE TABLE crm.product_brand_logo_upload (
    id UUID PRIMARY KEY,
    actor_subject VARCHAR(255) NOT NULL,
    object_key VARCHAR(500) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT product_brand_logo_upload_expiry CHECK (expires_at > created_at)
);
CREATE INDEX ix_product_brand_logo_upload_expiry ON crm.product_brand_logo_upload(expires_at, id);
