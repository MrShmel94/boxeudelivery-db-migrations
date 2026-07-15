INSERT INTO crm.access_role (scope_type, code, active, sort_order)
SELECT scope_type, 'CRM_ADMIN', active, sort_order
FROM crm.access_role
WHERE code = 'ADMIN'
ON CONFLICT (scope_type, code) DO UPDATE
    SET active = EXCLUDED.active,
        sort_order = EXCLUDED.sort_order,
        updated_at = NOW();

UPDATE crm.account_global_role
SET role_code = 'CRM_ADMIN'
WHERE role_code = 'ADMIN';

DELETE FROM crm.access_role
WHERE code IN ('ADMIN', 'USER');

ALTER TABLE crm.access_role
    ADD CONSTRAINT ck_access_role_code_catalog
        CHECK (code IN (
            'OWNER',
            'CRM_ADMIN',
            'OPERATIONS_MANAGER',
            'CUSTOMER_MANAGER',
            'BUYER',
            'LOGISTICS_SPECIALIST',
            'WAREHOUSE_OPERATOR',
            'CASHIER',
            'COURIER',
            'ACCOUNTANT',
            'FINANCIAL_CONTROLLER',
            'SUPPLIER',
            'CUSTOMER'
        )),
    ADD CONSTRAINT ck_access_role_project_scope
        CHECK (scope_type <> 'PROJECT' OR code NOT IN ('OWNER', 'CRM_ADMIN'));

ALTER TABLE crm.account
    ADD COLUMN disabled_at TIMESTAMPTZ,
    ADD COLUMN disabled_by_subject VARCHAR(255),
    ADD CONSTRAINT ck_account_disabled_state
        CHECK (
            (status = 'ACTIVE' AND disabled_at IS NULL AND disabled_by_subject IS NULL)
            OR
            (status = 'DISABLED' AND disabled_at IS NOT NULL AND disabled_by_subject IS NOT NULL)
        ),
    ADD CONSTRAINT ck_account_disabled_by_subject_not_blank
        CHECK (disabled_by_subject IS NULL OR BTRIM(disabled_by_subject) <> '');

ALTER TABLE crm.password_credential
    ADD COLUMN security_version BIGINT NOT NULL DEFAULT 0,
    ADD CONSTRAINT ck_password_credential_security_version
        CHECK (security_version >= 0);

CREATE TABLE crm.email_delivery
(
    id                  UUID         PRIMARY KEY,
    account_id          UUID         NOT NULL,
    message_type        VARCHAR(32)  NOT NULL,
    recipient_email     VARCHAR(254) NOT NULL,
    provider            VARCHAR(64),
    status              VARCHAR(32)  NOT NULL DEFAULT 'PENDING',
    provider_message_id VARCHAR(255),
    failure_code        VARCHAR(128),
    created_by_subject  VARCHAR(255) NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    attempted_at        TIMESTAMPTZ,

    CONSTRAINT fk_email_delivery_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id),
    CONSTRAINT ck_email_delivery_message_type
        CHECK (message_type IN ('INITIAL_PASSWORD', 'PASSWORD_RESET')),
    CONSTRAINT ck_email_delivery_status
        CHECK (status IN ('PENDING', 'SENT', 'FAILED')),
    CONSTRAINT ck_email_delivery_recipient_not_blank
        CHECK (BTRIM(recipient_email) <> ''),
    CONSTRAINT ck_email_delivery_created_by_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_email_delivery_provider_state
        CHECK (
            (status = 'PENDING' AND provider IS NULL AND provider_message_id IS NULL
                AND failure_code IS NULL AND attempted_at IS NULL)
            OR
            (status = 'SENT' AND provider IS NOT NULL AND provider_message_id IS NOT NULL
                AND failure_code IS NULL AND attempted_at IS NOT NULL)
            OR
            (status = 'FAILED' AND provider IS NOT NULL AND provider_message_id IS NULL
                AND failure_code IS NOT NULL AND attempted_at IS NOT NULL)
        ),
    CONSTRAINT ck_email_delivery_attempted_at
        CHECK (attempted_at IS NULL OR attempted_at >= created_at)
);

CREATE INDEX ix_email_delivery_account_created_at
    ON crm.email_delivery (account_id, created_at DESC);

CREATE TABLE crm.password_reset_token
(
    id                   UUID         PRIMARY KEY,
    account_id           UUID         NOT NULL,
    token_hash           CHAR(64)     NOT NULL,
    email_delivery_id    UUID         NOT NULL,
    requested_by_subject VARCHAR(255) NOT NULL,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at           TIMESTAMPTZ  NOT NULL,
    consumed_at          TIMESTAMPTZ,

    CONSTRAINT uq_password_reset_token_hash
        UNIQUE (token_hash),
    CONSTRAINT uq_password_reset_token_delivery
        UNIQUE (email_delivery_id),
    CONSTRAINT fk_password_reset_token_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id),
    CONSTRAINT fk_password_reset_token_delivery
        FOREIGN KEY (email_delivery_id) REFERENCES crm.email_delivery (id),
    CONSTRAINT ck_password_reset_token_requester_not_blank
        CHECK (BTRIM(requested_by_subject) <> ''),
    CONSTRAINT ck_password_reset_token_expiry
        CHECK (expires_at > created_at),
    CONSTRAINT ck_password_reset_token_consumed_at
        CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);

CREATE UNIQUE INDEX ux_password_reset_token_active_account
    ON crm.password_reset_token (account_id)
    WHERE consumed_at IS NULL;

CREATE INDEX ix_password_reset_token_expiry
    ON crm.password_reset_token (expires_at)
    WHERE consumed_at IS NULL;

CREATE TABLE crm.account_audit_event
(
    id            UUID         PRIMARY KEY,
    account_id    UUID         NOT NULL,
    event_type    VARCHAR(64)  NOT NULL,
    actor_subject VARCHAR(255) NOT NULL,
    details       JSONB        NOT NULL DEFAULT '{}'::JSONB,
    occurred_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_account_audit_event_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id),
    CONSTRAINT ck_account_audit_event_type
        CHECK (event_type IN (
            'CREATED',
            'PROFILE_UPDATED',
            'ADMIN_UPDATED',
            'DISABLED',
            'REACTIVATED',
            'ROLES_UPDATED',
            'TEMPORARY_PASSWORD_CONSUMED',
            'PASSWORD_CHANGED',
            'PASSWORD_RESET_REQUESTED'
        )),
    CONSTRAINT ck_account_audit_event_actor_not_blank
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_account_audit_event_details_object
        CHECK (JSONB_TYPEOF(details) = 'object')
);

CREATE INDEX ix_account_audit_event_account_occurred_at
    ON crm.account_audit_event (account_id, occurred_at DESC);

COMMENT ON COLUMN crm.password_credential.security_version IS
    'Incremented on credential replacement so previously issued JWTs can be rejected.';
COMMENT ON TABLE crm.email_delivery IS
    'Delivery metadata only. Email bodies, temporary passwords, and reset tokens are never persisted.';
COMMENT ON COLUMN crm.password_reset_token.token_hash IS
    'Lowercase SHA-256 hash of a cryptographically random single-use token.';
COMMENT ON TABLE crm.account_audit_event IS
    'Security and lifecycle audit trail without passwords, tokens, or email bodies.';
