UPDATE crm.sales_calculation_policy
SET settings = settings || jsonb_build_object('flow', jsonb_build_object(
    'valueLimitEur', 500,
    'weightLimitKg', 25,
    'dutyPercent', 30,
    'minimumPerKgEur', 4,
    'clearanceAmount', 10,
    'clearanceCurrency', 'BYN',
    'requireClientDutyConsent', true,
    'restrictionValidityDays', 1,
    'offerValidityDays', 7,
    'defaultPrepaymentPercent', NULL
)), version = version + 1
WHERE status_code = 'DRAFT' AND NOT settings ? 'flow';

ALTER TABLE crm.sales_calculation_revision ADD CONSTRAINT uq_sales_calculation_revision_scope
    UNIQUE(id,sales_request_id,project_id);

CREATE TABLE crm.sales_calculation_offer (
    id UUID PRIMARY KEY,
    offer_number BIGSERIAL NOT NULL UNIQUE,
    sales_request_id UUID NOT NULL,
    project_id UUID NOT NULL,
    revision_id UUID NOT NULL,
    status_code VARCHAR(20) NOT NULL CHECK (status_code IN ('PREPARED','PRESENTED','ACCEPTED','DECLINED','WITHDRAWN')),
    terms_snapshot JSONB NOT NULL CHECK (jsonb_typeof(terms_snapshot) = 'object'),
    customer_snapshot JSONB NOT NULL CHECK (jsonb_typeof(customer_snapshot) = 'object'),
    valid_until DATE NOT NULL,
    created_by VARCHAR(150) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_sales_offer_request FOREIGN KEY(sales_request_id,project_id) REFERENCES crm.sales_request(id,project_id),
    CONSTRAINT fk_sales_offer_calculation FOREIGN KEY(revision_id,sales_request_id,project_id)
        REFERENCES crm.sales_calculation_revision(id,sales_request_id,project_id)
);
CREATE UNIQUE INDEX uq_sales_offer_current ON crm.sales_calculation_offer(sales_request_id)
    WHERE status_code IN ('PREPARED','PRESENTED');
CREATE INDEX ix_sales_offer_request ON crm.sales_calculation_offer(sales_request_id,offer_number DESC);

CREATE TABLE crm.sales_calculation_offer_event (
    command_id UUID PRIMARY KEY,
    offer_id UUID NOT NULL REFERENCES crm.sales_calculation_offer(id),
    action_code VARCHAR(20) NOT NULL CHECK (action_code IN ('PREPARED','PRESENTED','ACCEPTED','DECLINED','WITHDRAWN')),
    reference VARCHAR(500) NOT NULL CHECK (length(btrim(reference))>0),
    customs_accepted BOOLEAN NOT NULL DEFAULT false,
    actor_subject VARCHAR(150) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX ix_sales_offer_event ON crm.sales_calculation_offer_event(offer_id,created_at);

ALTER TABLE crm.sales_request_audit DROP CONSTRAINT sales_request_audit_event_type_check;
ALTER TABLE crm.sales_request_audit ADD CONSTRAINT sales_request_audit_event_type_check CHECK (event_type IN (
    'CREATED', 'REVIEW_STARTED', 'MANAGER_CHANGED', 'TERMS_AGREED', 'CANCELLED',
    'PAYMENT_RECORDED', 'PAYMENT_ALLOCATED', 'PAYMENT_REFUNDED', 'PREPAYMENT_CONFIRMED',
    'STOCK_RESERVED', 'STOCK_RELEASED', 'SOURCING_ASSIGNED', 'SOURCING_CHANGED', 'ORDERS_CREATED',
    'CONTACT_CHANGED', 'COMPOSITION_CHANGED', 'ACTION_PLANNED', 'ACTION_COMPLETED',
    'ACTION_CANCELLED', 'ACTION_RESCHEDULED', 'MATERIAL_ADDED', 'MATERIAL_UPLOAD_STARTED',
    'MATERIAL_UPLOADED', 'MATERIAL_ARCHIVED', 'CALCULATION_SAVED',
    'CALCULATION_SELF_APPROVED', 'CALCULATION_APPLIED', 'OFFER_PREPARED',
    'OFFER_PRESENTED', 'OFFER_ACCEPTED', 'OFFER_DECLINED', 'OFFER_WITHDRAWN'
));
ALTER TABLE crm.sales_request_audit ADD CONSTRAINT ck_sales_offer_audit_reason CHECK (
    event_type NOT IN ('OFFER_PREPARED','OFFER_PRESENTED','OFFER_ACCEPTED','OFFER_DECLINED','OFFER_WITHDRAWN')
    OR (reason IS NOT NULL AND length(btrim(reason))>0)
);
