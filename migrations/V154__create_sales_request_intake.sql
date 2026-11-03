CREATE TABLE crm.sales_request_number_counter (
    calendar_year INTEGER PRIMARY KEY CHECK (calendar_year > 0),
    last_value BIGINT NOT NULL CHECK (last_value > 0)
);

CREATE TABLE crm.sales_request (
    id UUID PRIMARY KEY,
    request_number VARCHAR(24) NOT NULL UNIQUE,
    project_id UUID NOT NULL REFERENCES crm.project(id) ON DELETE RESTRICT,
    client_request_id UUID NOT NULL,
    intake_fingerprint VARCHAR(64) NOT NULL CHECK (intake_fingerprint ~ '^[0-9a-f]{64}$'),
    source_reference VARCHAR(200) CHECK (source_reference IS NULL OR length(btrim(source_reference)) > 0),
    customer_name VARCHAR(200) NOT NULL CHECK (length(btrim(customer_name)) > 0),
    customer_phone VARCHAR(32),
    customer_email VARCHAR(254),
    receipt_preference VARCHAR(16) NOT NULL CHECK (receipt_preference IN ('TOGETHER', 'SEPARATELY')),
    status_code VARCHAR(32) NOT NULL CHECK (status_code IN ('NEW', 'REVIEWING', 'AWAITING_PREPAYMENT', 'CANCELLED')),
    manager_account_id UUID REFERENCES crm.account(id) ON DELETE RESTRICT,
    customer_comment VARCHAR(2000),
    agreed_terms VARCHAR(2000),
    cancellation_reason VARCHAR(500),
    terms_agreed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    version BIGINT NOT NULL DEFAULT 0 CHECK (version >= 0),
    CONSTRAINT uq_sales_request_scope UNIQUE (id, project_id),
    CONSTRAINT uq_sales_request_intake UNIQUE (project_id, client_request_id),
    CONSTRAINT ck_sales_request_contact CHECK (
        nullif(btrim(customer_phone), '') IS NOT NULL OR nullif(btrim(customer_email), '') IS NOT NULL
    ),
    CONSTRAINT ck_sales_request_review CHECK (
        status_code NOT IN ('REVIEWING', 'AWAITING_PREPAYMENT') OR manager_account_id IS NOT NULL
    ),
    CONSTRAINT ck_sales_request_terms_pair CHECK (
        (agreed_terms IS NULL AND terms_agreed_at IS NULL)
        OR (agreed_terms IS NOT NULL AND length(btrim(agreed_terms)) > 0 AND terms_agreed_at IS NOT NULL)
    ),
    CONSTRAINT ck_sales_request_agreed CHECK (
        status_code <> 'AWAITING_PREPAYMENT' OR terms_agreed_at IS NOT NULL
    ),
    CONSTRAINT ck_sales_request_cancelled CHECK (
        (status_code = 'CANCELLED' AND cancelled_at IS NOT NULL
            AND cancellation_reason IS NOT NULL AND length(btrim(cancellation_reason)) > 0)
        OR (status_code <> 'CANCELLED' AND cancelled_at IS NULL AND cancellation_reason IS NULL)
    )
);

CREATE UNIQUE INDEX uq_sales_request_source ON crm.sales_request(project_id, source_reference)
    WHERE source_reference IS NOT NULL;
CREATE INDEX ix_sales_request_project_created ON crm.sales_request(project_id, created_at DESC, id DESC);
CREATE INDEX ix_sales_request_project_status_created ON crm.sales_request(project_id, status_code, created_at DESC, id DESC);
CREATE INDEX ix_sales_request_project_manager_created ON crm.sales_request(project_id, manager_account_id, created_at DESC, id DESC);

ALTER TABLE crm.supplier_goods_variant
    ADD CONSTRAINT uq_supplier_goods_variant_project UNIQUE (id, project_id);

CREATE TABLE crm.sales_request_line (
    id UUID PRIMARY KEY,
    sales_request_id UUID NOT NULL,
    project_id UUID NOT NULL,
    sequence_number INTEGER NOT NULL CHECK (sequence_number BETWEEN 1 AND 100),
    supplier_goods_variant_id UUID,
    product_name VARCHAR(250) NOT NULL CHECK (length(btrim(product_name)) > 0),
    characteristics VARCHAR(500),
    attributes JSONB NOT NULL CHECK (jsonb_typeof(attributes) = 'array'),
    quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 1000),
    unit_price NUMERIC(19,4),
    currency_code VARCHAR(3) REFERENCES crm.currency_definition(code) ON DELETE RESTRICT,
    required_prepayment NUMERIC(19,4),
    expected_arrival_date DATE,
    CONSTRAINT fk_sales_request_line_request FOREIGN KEY (sales_request_id, project_id)
        REFERENCES crm.sales_request(id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sales_request_line_variant FOREIGN KEY (supplier_goods_variant_id, project_id)
        REFERENCES crm.supplier_goods_variant(id, project_id) ON DELETE RESTRICT,
    CONSTRAINT uq_sales_request_line_sequence UNIQUE (sales_request_id, sequence_number),
    CONSTRAINT ck_sales_request_line_terms CHECK (
        (unit_price IS NULL AND currency_code IS NULL AND required_prepayment IS NULL AND expected_arrival_date IS NULL)
        OR (unit_price IS NOT NULL AND unit_price > 0 AND currency_code IS NOT NULL
            AND required_prepayment IS NOT NULL AND required_prepayment > 0
            AND required_prepayment <= unit_price * quantity)
    )
);

CREATE TABLE crm.sales_request_audit (
    id UUID PRIMARY KEY,
    sales_request_id UUID NOT NULL,
    project_id UUID NOT NULL,
    event_type VARCHAR(32) NOT NULL CHECK (event_type IN ('CREATED', 'REVIEW_STARTED', 'MANAGER_CHANGED', 'TERMS_AGREED', 'CANCELLED')),
    actor_subject VARCHAR(255) NOT NULL,
    reason VARCHAR(500),
    details JSONB NOT NULL CHECK (jsonb_typeof(details) = 'object'),
    occurred_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_sales_request_audit_request FOREIGN KEY (sales_request_id, project_id)
        REFERENCES crm.sales_request(id, project_id) ON DELETE RESTRICT,
    CONSTRAINT ck_sales_request_audit_reason CHECK (
        event_type NOT IN ('MANAGER_CHANGED', 'TERMS_AGREED', 'CANCELLED') OR (reason IS NOT NULL AND length(btrim(reason)) > 0)
    )
);

CREATE INDEX ix_sales_request_audit_history
    ON crm.sales_request_audit(project_id, sales_request_id, occurred_at DESC, id DESC);
