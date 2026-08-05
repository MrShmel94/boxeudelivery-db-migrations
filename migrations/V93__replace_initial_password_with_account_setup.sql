ALTER TABLE crm.password_credential
    ALTER COLUMN password_hash DROP NOT NULL,
    ADD COLUMN credential_setup_required BOOLEAN NOT NULL DEFAULT FALSE,
    ADD CONSTRAINT ck_password_credential_setup_state
        CHECK (
            (
                credential_setup_required
                AND password_hash IS NULL
                AND password_change_required = FALSE
                AND temporary_password_consumed_at IS NULL
                AND password_changed_at IS NULL
            )
            OR
            (
                credential_setup_required = FALSE
                AND password_hash IS NOT NULL
            )
        );

ALTER TABLE crm.email_delivery
    DROP CONSTRAINT ck_email_delivery_message_type,
    ADD CONSTRAINT ck_email_delivery_message_type
        CHECK (message_type IN ('INITIAL_PASSWORD', 'ACCOUNT_SETUP', 'PASSWORD_RESET'));

ALTER TABLE crm.account_audit_event
    DROP CONSTRAINT ck_account_audit_event_type,
    ADD CONSTRAINT ck_account_audit_event_type
        CHECK (event_type IN (
            'CREATED',
            'PROFILE_UPDATED',
            'ADMIN_UPDATED',
            'DISABLED',
            'REACTIVATED',
            'ROLES_UPDATED',
            'TEMPORARY_PASSWORD_CONSUMED',
            'ACCOUNT_SETUP_REQUESTED',
            'ACCOUNT_SETUP_COMPLETED',
            'PASSWORD_CHANGED',
            'PASSWORD_RESET_REQUESTED'
        ));

CREATE TABLE crm.account_setup_token
(
    id                   UUID         PRIMARY KEY,
    account_id           UUID         NOT NULL,
    token_hash           VARCHAR(64)  NOT NULL,
    email_delivery_id    UUID         NOT NULL,
    requested_by_subject VARCHAR(255) NOT NULL,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at           TIMESTAMPTZ  NOT NULL,
    consumed_at          TIMESTAMPTZ,

    CONSTRAINT uq_account_setup_token_hash
        UNIQUE (token_hash),
    CONSTRAINT uq_account_setup_token_delivery
        UNIQUE (email_delivery_id),
    CONSTRAINT fk_account_setup_token_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id),
    CONSTRAINT fk_account_setup_token_delivery
        FOREIGN KEY (email_delivery_id) REFERENCES crm.email_delivery (id),
    CONSTRAINT ck_account_setup_token_requester_not_blank
        CHECK (BTRIM(requested_by_subject) <> ''),
    CONSTRAINT ck_account_setup_token_expiry
        CHECK (expires_at > created_at),
    CONSTRAINT ck_account_setup_token_consumed_at
        CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);

CREATE UNIQUE INDEX ux_account_setup_token_active_account
    ON crm.account_setup_token (account_id)
    WHERE consumed_at IS NULL;

CREATE INDEX ix_account_setup_token_expiry
    ON crm.account_setup_token (expires_at)
    WHERE consumed_at IS NULL;

COMMENT ON COLUMN crm.password_credential.credential_setup_required IS
    'True only while an administrator-provisioned account has no user-selected password.';
COMMENT ON TABLE crm.account_setup_token IS
    'Hashed, expiring, single-use tokens for initial account credential setup.';
COMMENT ON COLUMN crm.account_setup_token.token_hash IS
    'Lowercase SHA-256 hash of a cryptographically random single-use token.';
