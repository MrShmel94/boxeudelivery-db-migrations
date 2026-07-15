CREATE SCHEMA crm;

CREATE TABLE crm.account_category
(
    code       VARCHAR(32) PRIMARY KEY,
    active     BOOLEAN      NOT NULL DEFAULT TRUE,
    sort_order SMALLINT     NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_account_category_code
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_account_category_sort_order
        CHECK (sort_order >= 0),
    CONSTRAINT ck_account_category_timestamps
        CHECK (updated_at >= created_at)
);

CREATE TABLE crm.access_role
(
    scope_type VARCHAR(32) NOT NULL,
    code       VARCHAR(64) NOT NULL,
    active     BOOLEAN      NOT NULL DEFAULT TRUE,
    sort_order SMALLINT     NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    PRIMARY KEY (scope_type, code),

    CONSTRAINT ck_access_role_scope_type
        CHECK (scope_type IN ('GLOBAL', 'PROJECT')),
    CONSTRAINT ck_access_role_code
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_access_role_sort_order
        CHECK (sort_order >= 0),
    CONSTRAINT ck_access_role_timestamps
        CHECK (updated_at >= created_at)
);

CREATE TABLE crm.account
(
    id                 UUID         PRIMARY KEY,
    first_name         VARCHAR(100) NOT NULL,
    last_name          VARCHAR(100) NOT NULL,
    email              VARCHAR(254) NOT NULL,
    email_normalized   VARCHAR(254) GENERATED ALWAYS AS (LOWER(BTRIM(email))) STORED,
    phone              VARCHAR(16),
    category_code      VARCHAR(32),
    status             VARCHAR(32)  NOT NULL DEFAULT 'ACTIVE',
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    version            BIGINT       NOT NULL DEFAULT 0,

    CONSTRAINT uq_account_email_normalized
        UNIQUE (email_normalized),
    CONSTRAINT fk_account_category
        FOREIGN KEY (category_code) REFERENCES crm.account_category (code),
    CONSTRAINT ck_account_first_name_not_blank
        CHECK (BTRIM(first_name) <> ''),
    CONSTRAINT ck_account_last_name_not_blank
        CHECK (BTRIM(last_name) <> ''),
    CONSTRAINT ck_account_email_not_blank
        CHECK (BTRIM(email) <> ''),
    CONSTRAINT ck_account_email_shape
        CHECK (email_normalized ~ '^[^[:space:]@]+@[^[:space:]@]+$'),
    CONSTRAINT ck_account_phone_e164
        CHECK (phone IS NULL OR phone ~ '^\+[1-9][0-9]{6,14}$'),
    CONSTRAINT ck_account_status
        CHECK (status IN ('ACTIVE', 'DISABLED')),
    CONSTRAINT ck_account_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_account_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_account_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_account_version
        CHECK (version >= 0)
);

CREATE INDEX ix_account_category_code
    ON crm.account (category_code)
    WHERE category_code IS NOT NULL;

CREATE INDEX ix_account_status
    ON crm.account (status);

CREATE TABLE crm.account_global_role
(
    account_id          UUID         NOT NULL,
    role_scope          VARCHAR(32)  NOT NULL DEFAULT 'GLOBAL',
    role_code           VARCHAR(64)  NOT NULL,
    assigned_by_subject VARCHAR(255) NOT NULL,
    assigned_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    PRIMARY KEY (account_id, role_code),

    CONSTRAINT fk_account_global_role_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id),
    CONSTRAINT fk_account_global_role_role
        FOREIGN KEY (role_scope, role_code) REFERENCES crm.access_role (scope_type, code),
    CONSTRAINT ck_account_global_role_scope
        CHECK (role_scope = 'GLOBAL'),
    CONSTRAINT ck_account_global_role_assigned_by_not_blank
        CHECK (BTRIM(assigned_by_subject) <> '')
);

CREATE INDEX ix_account_global_role_role_code
    ON crm.account_global_role (role_code, account_id);

CREATE TABLE crm.password_credential
(
    account_id                     UUID         PRIMARY KEY,
    password_hash                  VARCHAR(255) NOT NULL,
    password_change_required       BOOLEAN      NOT NULL DEFAULT TRUE,
    temporary_password_consumed_at TIMESTAMPTZ,
    password_changed_at            TIMESTAMPTZ,
    created_at                     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at                     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    version                        BIGINT       NOT NULL DEFAULT 0,

    CONSTRAINT fk_password_credential_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id),
    CONSTRAINT ck_password_credential_hash_not_blank
        CHECK (BTRIM(password_hash) <> ''),
    CONSTRAINT ck_password_credential_consumed_at
        CHECK (temporary_password_consumed_at IS NULL OR temporary_password_consumed_at >= created_at),
    CONSTRAINT ck_password_credential_changed_at
        CHECK (password_changed_at IS NULL OR password_changed_at >= created_at),
    CONSTRAINT ck_password_credential_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_password_credential_version
        CHECK (version >= 0)
);

COMMENT ON SCHEMA crm IS
    'Application-owned tables for the Box EU Delivery CRM modular monolith.';
COMMENT ON TABLE crm.access_role IS
    'Predefined role definitions. Scope is part of role identity.';
COMMENT ON TABLE crm.account_global_role IS
    'Global platform roles only. Project roles are assigned through project membership.';
COMMENT ON COLUMN crm.account.category_code IS
    'Optional business classification; it is not an authorization role.';
COMMENT ON COLUMN crm.account.email_normalized IS
    'Database-generated canonical email used to enforce case-insensitive uniqueness.';
COMMENT ON COLUMN crm.password_credential.password_hash IS
    'One-way password hash only. Plaintext and temporary passwords must never be persisted.';
COMMENT ON COLUMN crm.password_credential.temporary_password_consumed_at IS
    'First successful use of the one-time temporary password.';
