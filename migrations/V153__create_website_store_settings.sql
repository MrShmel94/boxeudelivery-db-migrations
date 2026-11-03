CREATE TABLE crm.website_store_settings (
    project_id UUID PRIMARY KEY REFERENCES crm.project(id),
    version BIGINT NOT NULL CHECK (version > 0),
    pickup_enabled BOOLEAN NOT NULL,
    city VARCHAR(120),
    address VARCHAR(500),
    opening_hours VARCHAR(200),
    pickup_fee NUMERIC(11,2) CHECK (pickup_fee >= 0),
    updated_at TIMESTAMPTZ NOT NULL,
    CHECK (NOT pickup_enabled OR (
        length(trim(city)) > 0 AND city IS NOT NULL AND
        length(trim(address)) > 0 AND address IS NOT NULL AND
        length(trim(opening_hours)) > 0 AND opening_hours IS NOT NULL AND pickup_fee IS NOT NULL
    ))
);
CREATE TABLE crm.website_store_settings_audit (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES crm.project(id),
    version BIGINT NOT NULL,
    actor_id UUID NOT NULL,
    pickup_enabled BOOLEAN NOT NULL,
    city VARCHAR(120),
    address VARCHAR(500),
    opening_hours VARCHAR(200),
    pickup_fee NUMERIC(11,2),
    occurred_at TIMESTAMPTZ NOT NULL,
    UNIQUE(project_id, version)
);
CREATE FUNCTION crm.touch_website_store_settings_revision() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO crm.website_catalog_revision(project_id, transaction_id)
        VALUES (NEW.project_id, txid_current()) ON CONFLICT DO NOTHING;
    RETURN NULL;
END;
$$;
CREATE TRIGGER website_store_settings_changed
AFTER INSERT OR UPDATE ON crm.website_store_settings
FOR EACH ROW EXECUTE FUNCTION crm.touch_website_store_settings_revision();
