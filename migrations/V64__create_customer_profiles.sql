CREATE TABLE crm.customer_profile
(
    id                  UUID         NOT NULL,
    project_id          UUID         NOT NULL,
    supplier_id         UUID         NOT NULL,
    display_name        VARCHAR(200) NOT NULL,
    phone               VARCHAR(32),
    email               VARCHAR(254),
    email_normalized    VARCHAR(254) GENERATED ALWAYS AS (LOWER(BTRIM(email))) STORED,
    linked_account_id   UUID,
    status_code         VARCHAR(16)  NOT NULL DEFAULT 'ACTIVE',
    created_by_subject  VARCHAR(255) NOT NULL,
    updated_by_subject  VARCHAR(255) NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version             BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_customer_profile
        PRIMARY KEY (id),
    CONSTRAINT uq_customer_profile_scope
        UNIQUE (id, project_id, supplier_id),
    CONSTRAINT fk_customer_profile_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_profile_linked_account
        FOREIGN KEY (linked_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_customer_profile_display_name_not_blank
        CHECK (BTRIM(display_name) <> ''),
    CONSTRAINT ck_customer_profile_phone_not_blank
        CHECK (phone IS NULL OR BTRIM(phone) <> ''),
    CONSTRAINT ck_customer_profile_email_not_blank
        CHECK (email IS NULL OR BTRIM(email) <> ''),
    CONSTRAINT ck_customer_profile_email_shape
        CHECK (email IS NULL OR email_normalized ~ '^[^[:space:]@]+@[^[:space:]@]+$'),
    CONSTRAINT ck_customer_profile_status
        CHECK (status_code IN ('ACTIVE', 'ARCHIVED')),
    CONSTRAINT ck_customer_profile_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_customer_profile_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_customer_profile_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_customer_profile_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_customer_profile_linked_account_scope
    ON crm.customer_profile (project_id, supplier_id, linked_account_id)
    WHERE linked_account_id IS NOT NULL;

CREATE INDEX ix_customer_profile_scope_updated
    ON crm.customer_profile (project_id, supplier_id, status_code, updated_at DESC, id);

CREATE INDEX ix_customer_profile_display_name_trgm
    ON crm.customer_profile USING GIN (LOWER(display_name) gin_trgm_ops);

CREATE INDEX ix_customer_profile_email_trgm
    ON crm.customer_profile USING GIN (email_normalized gin_trgm_ops)
    WHERE email_normalized IS NOT NULL;

CREATE INDEX ix_customer_profile_phone_trgm
    ON crm.customer_profile USING GIN (LOWER(phone) gin_trgm_ops)
    WHERE phone IS NOT NULL;

CREATE TABLE crm.customer_profile_external_link
(
    id                  UUID          NOT NULL,
    customer_profile_id UUID          NOT NULL,
    project_id          UUID          NOT NULL,
    supplier_id         UUID          NOT NULL,
    platform_code       VARCHAR(16)   NOT NULL,
    label               VARCHAR(100),
    url                 VARCHAR(1000) NOT NULL,
    sort_order          INTEGER       NOT NULL DEFAULT 0,
    created_by_subject  VARCHAR(255)  NOT NULL,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_customer_profile_external_link
        PRIMARY KEY (id),
    CONSTRAINT uq_customer_profile_external_link_value
        UNIQUE (customer_profile_id, url),
    CONSTRAINT fk_customer_profile_external_link_profile
        FOREIGN KEY (customer_profile_id, project_id, supplier_id)
            REFERENCES crm.customer_profile (id, project_id, supplier_id) ON DELETE CASCADE,
    CONSTRAINT ck_customer_profile_external_link_platform
        CHECK (platform_code IN ('TELEGRAM', 'OLX', 'AVITO', 'OTHER')),
    CONSTRAINT ck_customer_profile_external_link_label_not_blank
        CHECK (label IS NULL OR BTRIM(label) <> ''),
    CONSTRAINT ck_customer_profile_external_link_url
        CHECK (BTRIM(url) <> '' AND url ~* '^https://[^[:space:]]+$'),
    CONSTRAINT ck_customer_profile_external_link_sort_order
        CHECK (sort_order >= 0),
    CONSTRAINT ck_customer_profile_external_link_created_by_not_blank
        CHECK (BTRIM(created_by_subject) <> '')
);

CREATE INDEX ix_customer_profile_external_link_profile
    ON crm.customer_profile_external_link (customer_profile_id, sort_order, id);

CREATE TABLE crm.customer_profile_audit_event
(
    id                  UUID         NOT NULL,
    customer_profile_id UUID         NOT NULL,
    project_id          UUID         NOT NULL,
    supplier_id         UUID         NOT NULL,
    event_type          VARCHAR(32)  NOT NULL,
    actor_subject       VARCHAR(255) NOT NULL,
    details             JSONB        NOT NULL DEFAULT '{}'::JSONB,
    occurred_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_customer_profile_audit_event
        PRIMARY KEY (id),
    CONSTRAINT fk_customer_profile_audit_event_profile
        FOREIGN KEY (customer_profile_id, project_id, supplier_id)
            REFERENCES crm.customer_profile (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT ck_customer_profile_audit_event_type
        CHECK (event_type IN ('CREATED', 'ACCOUNT_LINKED')),
    CONSTRAINT ck_customer_profile_audit_event_actor_not_blank
        CHECK (BTRIM(actor_subject) <> '')
);

CREATE INDEX ix_customer_profile_audit_event_profile_occurred
    ON crm.customer_profile_audit_event (customer_profile_id, occurred_at DESC, id);

INSERT INTO crm.customer_profile (
    id,
    project_id,
    supplier_id,
    display_name,
    phone,
    email,
    linked_account_id,
    status_code,
    created_by_subject,
    updated_by_subject,
    created_at,
    updated_at,
    version
)
SELECT MD5(
           'boxeudelivery:customer-profile:'
           || customer_order.project_id::TEXT
           || ':'
           || customer_order.supplier_id::TEXT
           || ':'
           || customer_order.customer_account_id::TEXT
       )::UUID,
       customer_order.project_id,
       customer_order.supplier_id,
       BTRIM(account.first_name || ' ' || account.last_name),
       account.phone,
       account.email,
       customer_order.customer_account_id,
       'ACTIVE',
       'migration:v64',
       'migration:v64',
       MIN(customer_order.created_at),
       MAX(customer_order.updated_at),
       0
FROM crm.customer_order customer_order
JOIN crm.account account ON account.id = customer_order.customer_account_id
GROUP BY customer_order.project_id,
         customer_order.supplier_id,
         customer_order.customer_account_id,
         account.first_name,
         account.last_name,
         account.phone,
         account.email;

INSERT INTO crm.customer_profile_audit_event (
    id,
    customer_profile_id,
    project_id,
    supplier_id,
    event_type,
    actor_subject,
    details,
    occurred_at
)
SELECT MD5('boxeudelivery:customer-profile-audit:' || profile.id::TEXT)::UUID,
       profile.id,
       profile.project_id,
       profile.supplier_id,
       'CREATED',
       'migration:v64',
       JSONB_BUILD_OBJECT('linkedAccountId', profile.linked_account_id::TEXT),
       profile.created_at
FROM crm.customer_profile profile;

ALTER TABLE crm.customer_order
    ADD COLUMN customer_profile_id UUID,
    ADD COLUMN customer_display_name VARCHAR(200),
    ADD COLUMN customer_phone VARCHAR(32),
    ADD COLUMN customer_email VARCHAR(254);

UPDATE crm.customer_order customer_order
SET customer_profile_id = customer_profile.id,
    customer_display_name = customer_profile.display_name,
    customer_phone = customer_profile.phone,
    customer_email = customer_profile.email
FROM crm.customer_profile customer_profile
WHERE customer_profile.project_id = customer_order.project_id
  AND customer_profile.supplier_id = customer_order.supplier_id
  AND customer_profile.linked_account_id = customer_order.customer_account_id;

ALTER TABLE crm.customer_order
    ALTER COLUMN customer_profile_id SET NOT NULL,
    ALTER COLUMN customer_display_name SET NOT NULL,
    ALTER COLUMN customer_account_id DROP NOT NULL,
    ADD CONSTRAINT fk_customer_order_customer_profile
        FOREIGN KEY (customer_profile_id, project_id, supplier_id)
            REFERENCES crm.customer_profile (id, project_id, supplier_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_customer_order_customer_display_name_not_blank
        CHECK (BTRIM(customer_display_name) <> ''),
    ADD CONSTRAINT ck_customer_order_customer_phone_not_blank
        CHECK (customer_phone IS NULL OR BTRIM(customer_phone) <> ''),
    ADD CONSTRAINT ck_customer_order_customer_email_not_blank
        CHECK (customer_email IS NULL OR BTRIM(customer_email) <> '');

CREATE INDEX ix_customer_order_customer_profile
    ON crm.customer_order (customer_profile_id, created_at DESC, id);

COMMENT ON TABLE crm.customer_profile IS
    'Reusable supplier-scoped customer card. A linked account is optional and is the only source of CRM access.';

COMMENT ON TABLE crm.customer_profile_external_link IS
    'Operator-entered HTTPS contact links. The backend stores and validates the URL but never fetches it.';

COMMENT ON COLUMN crm.customer_order.customer_profile_id IS
    'Immutable customer card selected when the order is created.';

COMMENT ON COLUMN crm.customer_order.customer_display_name IS
    'Immutable customer name snapshot captured when the order is created.';

COMMENT ON COLUMN crm.customer_order.customer_account_id IS
    'Optional linked CRM account snapshot. NULL means the customer has no CRM access to this order.';
