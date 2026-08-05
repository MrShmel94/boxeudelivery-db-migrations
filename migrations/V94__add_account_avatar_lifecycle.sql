CREATE TABLE crm.account_avatar_upload
(
    id                       UUID          PRIMARY KEY,
    account_id               UUID          NOT NULL,
    status_code              VARCHAR(24)   NOT NULL DEFAULT 'PENDING_UPLOAD',
    declared_filename        VARCHAR(255)  NOT NULL,
    declared_content_type    VARCHAR(255)  NOT NULL,
    declared_size_bytes      BIGINT        NOT NULL,
    declared_checksum_sha256 VARCHAR(44)   NOT NULL,
    upload_object_key        VARCHAR(1024) NOT NULL,
    upload_expires_at        TIMESTAMPTZ   NOT NULL,
    completed_at             TIMESTAMPTZ,
    cancelled_at             TIMESTAMPTZ,
    accepted_revision        UUID,
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    version                  BIGINT        NOT NULL DEFAULT 0,

    CONSTRAINT fk_account_avatar_upload_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id),
    CONSTRAINT uq_account_avatar_upload_object_key
        UNIQUE (upload_object_key),
    CONSTRAINT ck_account_avatar_upload_status
        CHECK (status_code IN ('PENDING_UPLOAD', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT ck_account_avatar_upload_filename_not_blank
        CHECK (BTRIM(declared_filename) <> ''),
    CONSTRAINT ck_account_avatar_upload_content_type
        CHECK (LOWER(declared_content_type) = 'image/jpeg'),
    CONSTRAINT ck_account_avatar_upload_size
        CHECK (declared_size_bytes BETWEEN 1 AND 2097152),
    CONSTRAINT ck_account_avatar_upload_checksum
        CHECK (declared_checksum_sha256 ~ '^[A-Za-z0-9+/]{43}=$'),
    CONSTRAINT ck_account_avatar_upload_key_not_blank
        CHECK (BTRIM(upload_object_key) <> ''),
    CONSTRAINT ck_account_avatar_upload_expiry
        CHECK (upload_expires_at > created_at),
    CONSTRAINT ck_account_avatar_upload_state
        CHECK (
            (status_code = 'PENDING_UPLOAD'
                AND completed_at IS NULL
                AND cancelled_at IS NULL
                AND accepted_revision IS NULL)
            OR
            (status_code = 'COMPLETED'
                AND completed_at IS NOT NULL
                AND cancelled_at IS NULL
                AND accepted_revision IS NOT NULL)
            OR
            (status_code = 'CANCELLED'
                AND completed_at IS NULL
                AND cancelled_at IS NOT NULL
                AND accepted_revision IS NULL)
        ),
    CONSTRAINT ck_account_avatar_upload_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_account_avatar_upload_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX ux_account_avatar_upload_pending_account
    ON crm.account_avatar_upload (account_id)
    WHERE status_code = 'PENDING_UPLOAD';

CREATE INDEX ix_account_avatar_upload_expired
    ON crm.account_avatar_upload (upload_expires_at, id)
    WHERE status_code = 'PENDING_UPLOAD';

ALTER TABLE crm.account
    ADD COLUMN avatar_revision UUID,
    ADD COLUMN avatar_object_key VARCHAR(1024),
    ADD COLUMN avatar_content_type VARCHAR(255),
    ADD COLUMN avatar_size_bytes BIGINT,
    ADD COLUMN avatar_checksum_sha256 VARCHAR(44),
    ADD COLUMN avatar_updated_at TIMESTAMPTZ,
    ADD CONSTRAINT ck_account_avatar_state
        CHECK (
            (avatar_revision IS NULL
                AND avatar_object_key IS NULL
                AND avatar_content_type IS NULL
                AND avatar_size_bytes IS NULL
                AND avatar_checksum_sha256 IS NULL
                AND avatar_updated_at IS NULL)
            OR
            (avatar_revision IS NOT NULL
                AND BTRIM(avatar_object_key) <> ''
                AND LOWER(avatar_content_type) = 'image/jpeg'
                AND avatar_size_bytes BETWEEN 1 AND 1048576
                AND avatar_checksum_sha256 ~ '^[A-Za-z0-9+/]{43}=$'
                AND avatar_updated_at IS NOT NULL)
        );

ALTER TABLE crm.account_audit_event
    DROP CONSTRAINT ck_account_audit_event_type,
    ADD CONSTRAINT ck_account_audit_event_type
        CHECK (event_type IN (
            'CREATED',
            'PROFILE_UPDATED',
            'AVATAR_UPDATED',
            'AVATAR_REMOVED',
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

COMMENT ON TABLE crm.account_avatar_upload IS
    'Short-lived, checksum-bound direct uploads used to replace the current account avatar.';
COMMENT ON COLUMN crm.account.avatar_object_key IS
    'Private object key for the normalized 256x256 JPEG avatar. The user-selected source is not retained.';
COMMENT ON COLUMN crm.account.avatar_revision IS
    'Immutable cache revision for the current avatar representation exposed through account DTOs.';
