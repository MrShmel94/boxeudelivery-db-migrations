ALTER TABLE crm.sales_request
    ADD COLUMN source_channel VARCHAR(24) NOT NULL DEFAULT 'MANUAL'
        CHECK (source_channel IN ('MANUAL','WEBSITE','TELEGRAM','INSTAGRAM','WHATSAPP','VK','PHONE','EMAIL','OTHER')),
    ADD COLUMN source_label VARCHAR(80),
    ADD COLUMN social_handle VARCHAR(200),
    ADD COLUMN profile_url VARCHAR(2000),
    ADD COLUMN conversation_url VARCHAR(2000),
    DROP CONSTRAINT ck_sales_request_contact;
UPDATE crm.sales_request SET source_channel='WEBSITE' WHERE website_context IS NOT NULL;
ALTER TABLE crm.sales_request ADD CONSTRAINT ck_sales_request_contact CHECK (
    nullif(btrim(customer_phone),'') IS NOT NULL OR nullif(btrim(customer_email),'') IS NOT NULL
    OR nullif(btrim(social_handle),'') IS NOT NULL OR nullif(btrim(profile_url),'') IS NOT NULL
    OR nullif(btrim(conversation_url),'') IS NOT NULL
);

ALTER TABLE crm.sales_request_audit DROP CONSTRAINT sales_request_audit_event_type_check;
ALTER TABLE crm.sales_request_audit ADD CONSTRAINT sales_request_audit_event_type_check CHECK (event_type IN (
    'CREATED','REVIEW_STARTED','MANAGER_CHANGED','TERMS_AGREED','CANCELLED','PAYMENT_RECORDED','PAYMENT_ALLOCATED',
    'PAYMENT_REFUNDED','PREPAYMENT_CONFIRMED','STOCK_RESERVED','STOCK_RELEASED','SOURCING_ASSIGNED','SOURCING_CHANGED',
    'ORDERS_CREATED','CONTACT_CHANGED','COMPOSITION_CHANGED','ACTION_PLANNED','ACTION_COMPLETED','ACTION_CANCELLED',
    'ACTION_RESCHEDULED','MATERIAL_ADDED','MATERIAL_UPLOAD_STARTED','MATERIAL_UPLOADED','MATERIAL_ARCHIVED'
));

CREATE TABLE crm.sales_action (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    sales_request_id UUID NOT NULL,
    kind VARCHAR(24) NOT NULL CHECK (kind IN ('PREPARE_QUOTE','SEND_OFFER','CONTACT_CUSTOMER','OTHER')),
    title VARCHAR(200) NOT NULL CHECK (length(btrim(title))>0),
    description VARCHAR(2000),
    assignee_account_id UUID NOT NULL REFERENCES crm.account(id) ON DELETE RESTRICT,
    due_at TIMESTAMPTZ NOT NULL,
    time_zone_id VARCHAR(80) NOT NULL,
    status VARCHAR(16) NOT NULL CHECK (status IN ('PLANNED','COMPLETED','CANCELLED')),
    result VARCHAR(1000),
    completed_at TIMESTAMPTZ,
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (sales_request_id,project_id) REFERENCES crm.sales_request(id,project_id) ON DELETE RESTRICT,
    CHECK ((status='PLANNED' AND completed_at IS NULL AND result IS NULL)
        OR (status<>'PLANNED' AND completed_at IS NOT NULL AND length(btrim(result))>0 AND result IS NOT NULL))
);
CREATE INDEX ix_sales_action_request ON crm.sales_action(project_id,sales_request_id,status,due_at,id);
CREATE INDEX ix_sales_action_due ON crm.sales_action(project_id,due_at,assignee_account_id,sales_request_id)
    WHERE status='PLANNED';

CREATE TABLE crm.sales_material (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    sales_request_id UUID NOT NULL,
    kind VARCHAR(16) NOT NULL CHECK (kind IN ('LINK','FILE','PHOTO')),
    title VARCHAR(200) NOT NULL CHECK (length(btrim(title))>0),
    url VARCHAR(2000),
    status VARCHAR(24) NOT NULL CHECK (status IN ('PENDING_UPLOAD','READY')),
    filename VARCHAR(255),
    content_type VARCHAR(150),
    size_bytes BIGINT CHECK (size_bytes BETWEEN 1 AND 20971520),
    checksum_sha256 VARCHAR(44),
    upload_key VARCHAR(512),
    upload_expires_at TIMESTAMPTZ,
    accepted_key VARCHAR(512),
    preview_key VARCHAR(512),
    uploader_account_id UUID NOT NULL REFERENCES crm.account(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL,
    uploaded_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ,
    archived_by_subject VARCHAR(255),
    FOREIGN KEY (sales_request_id,project_id) REFERENCES crm.sales_request(id,project_id) ON DELETE RESTRICT,
    CHECK ((kind='LINK' AND url IS NOT NULL AND status='READY' AND filename IS NULL AND upload_key IS NULL
            AND accepted_key IS NULL AND preview_key IS NULL AND upload_expires_at IS NULL)
        OR (kind IN ('FILE','PHOTO') AND url IS NULL AND filename IS NOT NULL AND content_type IS NOT NULL
            AND size_bytes IS NOT NULL AND checksum_sha256 IS NOT NULL AND upload_key IS NOT NULL
            AND upload_expires_at IS NOT NULL
            AND ((status='PENDING_UPLOAD' AND accepted_key IS NULL AND uploaded_at IS NULL)
                OR (status='READY' AND accepted_key IS NOT NULL AND uploaded_at IS NOT NULL)))),
    CHECK ((archived_at IS NULL AND archived_by_subject IS NULL)
        OR (archived_at IS NOT NULL AND archived_by_subject IS NOT NULL))
);
CREATE INDEX ix_sales_material_request ON crm.sales_material(project_id,sales_request_id,created_at DESC,id);

CREATE FUNCTION crm.guard_paid_sales_composition() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE request_id UUID;
BEGIN
    IF TG_OP='DELETE' THEN request_id=OLD.sales_request_id; ELSE request_id=NEW.sales_request_id; END IF;
    PERFORM 1 FROM crm.sales_request WHERE id=request_id FOR UPDATE;
    IF EXISTS (SELECT 1 FROM crm.sales_request request WHERE request.id=request_id AND request.status_code='PAID')
        OR EXISTS (SELECT 1 FROM crm.settlement_money_operation operation
        WHERE operation.sales_request_id=request_id AND operation.operation_type IN ('SALES_ADVANCE','SALES_REFUND')) THEN
        RAISE EXCEPTION 'Paid sales composition requires its dedicated revision workflow'
            USING ERRCODE='23514',CONSTRAINT='ck_sales_paid_composition';
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER sales_paid_composition_guard BEFORE INSERT OR UPDATE OR DELETE ON crm.sales_request_line
    FOR EACH ROW EXECUTE FUNCTION crm.guard_paid_sales_composition();
