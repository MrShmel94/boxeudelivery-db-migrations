CREATE TABLE crm.sales_material_preview_job (
    material_id UUID PRIMARY KEY REFERENCES crm.sales_material(id) ON DELETE RESTRICT,
    status_code VARCHAR(16) NOT NULL CHECK (status_code IN ('PENDING','RUNNING')),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    not_before TIMESTAMPTZ NOT NULL,
    locked_at TIMESTAMPTZ,
    locked_by VARCHAR(80),
    last_error_code VARCHAR(80),
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CHECK ((status_code='PENDING' AND locked_at IS NULL AND locked_by IS NULL)
        OR (status_code='RUNNING' AND locked_at IS NOT NULL AND locked_by IS NOT NULL))
);
CREATE INDEX ix_sales_material_preview_due ON crm.sales_material_preview_job(not_before,material_id);
INSERT INTO crm.sales_material_preview_job(material_id,status_code,not_before,created_at,updated_at)
    SELECT id,'PENDING',now(),now(),now() FROM crm.sales_material
    WHERE kind='PHOTO' AND status='READY' AND preview_key IS NULL;
