ALTER TABLE crm.chat_message
    ADD CONSTRAINT uq_chat_message_id_context_conversation
        UNIQUE (id, context_task_id, conversation_id);

CREATE TABLE crm.chat_attachment
(
    id                       UUID         PRIMARY KEY,
    conversation_id          UUID         NOT NULL,
    context_task_id          UUID         NOT NULL,
    message_id               UUID,
    uploader_account_id      UUID         NOT NULL,
    kind_code                VARCHAR(32)  NOT NULL,
    status_code              VARCHAR(32)  NOT NULL DEFAULT 'PENDING_UPLOAD',
    original_filename        VARCHAR(255) NOT NULL,
    declared_content_type    VARCHAR(255) NOT NULL,
    declared_size_bytes      BIGINT       NOT NULL,
    declared_checksum_sha256 VARCHAR(44)  NOT NULL,
    duration_seconds         SMALLINT,
    original_object_key      VARCHAR(1024) NOT NULL,
    failure_code             VARCHAR(64),
    created_at               TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    upload_expires_at        TIMESTAMPTZ  NOT NULL,
    upload_completed_at      TIMESTAMPTZ,
    ready_at                 TIMESTAMPTZ,
    version                  BIGINT       NOT NULL DEFAULT 0,

    CONSTRAINT uq_chat_attachment_original_object_key
        UNIQUE (original_object_key),
    CONSTRAINT fk_chat_attachment_context_task
        FOREIGN KEY (context_task_id, conversation_id)
            REFERENCES crm.task (id, conversation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_chat_attachment_message
        FOREIGN KEY (message_id, context_task_id, conversation_id)
            REFERENCES crm.chat_message (id, context_task_id, conversation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_chat_attachment_uploader
        FOREIGN KEY (uploader_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_chat_attachment_kind
        CHECK (kind_code IN ('PHOTO', 'FILE', 'VOICE')),
    CONSTRAINT ck_chat_attachment_status
        CHECK (status_code IN ('PENDING_UPLOAD', 'PROCESSING', 'READY', 'FAILED')),
    CONSTRAINT ck_chat_attachment_filename
        CHECK (BTRIM(original_filename) <> ''),
    CONSTRAINT ck_chat_attachment_content_type
        CHECK (BTRIM(declared_content_type) <> ''),
    CONSTRAINT ck_chat_attachment_size
        CHECK (declared_size_bytes > 0 AND declared_size_bytes <= 52428800),
    CONSTRAINT ck_chat_attachment_checksum
        CHECK (declared_checksum_sha256 ~ '^[A-Za-z0-9+/]{43}=$'),
    CONSTRAINT ck_chat_attachment_voice_duration
        CHECK (
            (kind_code = 'VOICE' AND duration_seconds BETWEEN 1 AND 60)
            OR (kind_code <> 'VOICE' AND duration_seconds IS NULL)
        ),
    CONSTRAINT ck_chat_attachment_object_key
        CHECK (BTRIM(original_object_key) <> ''),
    CONSTRAINT ck_chat_attachment_upload_expiry
        CHECK (upload_expires_at > created_at),
    CONSTRAINT ck_chat_attachment_completed_at
        CHECK (
            (status_code = 'PENDING_UPLOAD' AND upload_completed_at IS NULL)
            OR (status_code <> 'PENDING_UPLOAD' AND upload_completed_at IS NOT NULL)
        ),
    CONSTRAINT ck_chat_attachment_ready_at
        CHECK (
            (status_code = 'READY' AND ready_at IS NOT NULL)
            OR (status_code <> 'READY' AND ready_at IS NULL)
        ),
    CONSTRAINT ck_chat_attachment_failure
        CHECK (
            (status_code = 'FAILED' AND failure_code IS NOT NULL)
            OR (status_code <> 'FAILED' AND failure_code IS NULL)
        ),
    CONSTRAINT ck_chat_attachment_version
        CHECK (version >= 0)
);

CREATE INDEX ix_chat_attachment_context_created
    ON crm.chat_attachment (context_task_id, created_at DESC, id);

CREATE INDEX ix_chat_attachment_message
    ON crm.chat_attachment (message_id, id)
    WHERE message_id IS NOT NULL;

CREATE INDEX ix_chat_attachment_pending_expiry
    ON crm.chat_attachment (upload_expires_at, id)
    WHERE status_code = 'PENDING_UPLOAD';

CREATE TABLE crm.chat_attachment_object
(
    attachment_id  UUID         NOT NULL,
    variant_code   VARCHAR(32)  NOT NULL,
    object_key     VARCHAR(1024) NOT NULL,
    content_type   VARCHAR(255) NOT NULL,
    size_bytes     BIGINT       NOT NULL,
    checksum_sha256 VARCHAR(44),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    PRIMARY KEY (attachment_id, variant_code),

    CONSTRAINT uq_chat_attachment_object_key
        UNIQUE (object_key),
    CONSTRAINT fk_chat_attachment_object_attachment
        FOREIGN KEY (attachment_id) REFERENCES crm.chat_attachment (id) ON DELETE RESTRICT,
    CONSTRAINT ck_chat_attachment_object_variant
        CHECK (variant_code IN ('ORIGINAL', 'PREVIEW', 'PLAYBACK')),
    CONSTRAINT ck_chat_attachment_object_key
        CHECK (BTRIM(object_key) <> ''),
    CONSTRAINT ck_chat_attachment_object_content_type
        CHECK (BTRIM(content_type) <> ''),
    CONSTRAINT ck_chat_attachment_object_size
        CHECK (size_bytes > 0 AND size_bytes <= 52428800),
    CONSTRAINT ck_chat_attachment_object_checksum
        CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[A-Za-z0-9+/]{43}=$')
);

CREATE TABLE crm.attachment_processing_job
(
    id              UUID        PRIMARY KEY,
    attachment_id   UUID        NOT NULL,
    job_type        VARCHAR(32) NOT NULL,
    status_code     VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    attempt_count   INTEGER     NOT NULL DEFAULT 0,
    not_before      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_at       TIMESTAMPTZ,
    locked_by       VARCHAR(128),
    last_error_code VARCHAR(64),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_attachment_processing_job
        UNIQUE (attachment_id, job_type),
    CONSTRAINT fk_attachment_processing_job_attachment
        FOREIGN KEY (attachment_id) REFERENCES crm.chat_attachment (id) ON DELETE RESTRICT,
    CONSTRAINT ck_attachment_processing_job_type
        CHECK (job_type IN ('IMAGE_PREVIEW', 'AUDIO_PLAYBACK')),
    CONSTRAINT ck_attachment_processing_job_status
        CHECK (status_code IN ('PENDING', 'RUNNING', 'DONE', 'FAILED')),
    CONSTRAINT ck_attachment_processing_job_attempts
        CHECK (attempt_count >= 0),
    CONSTRAINT ck_attachment_processing_job_lock
        CHECK (
            (status_code = 'RUNNING' AND locked_at IS NOT NULL AND locked_by IS NOT NULL)
            OR (status_code <> 'RUNNING')
        ),
    CONSTRAINT ck_attachment_processing_job_timestamps
        CHECK (updated_at >= created_at)
);

CREATE INDEX ix_attachment_processing_job_ready
    ON crm.attachment_processing_job (not_before, created_at, id)
    WHERE status_code = 'PENDING';

COMMENT ON TABLE crm.chat_attachment IS
    'Authorized upload lifecycle and message binding. The database owns metadata and state; S3 owns bytes.';
COMMENT ON TABLE crm.chat_attachment_object IS
    'Verified S3 objects for original, image preview, or normalized audio playback variants.';
COMMENT ON TABLE crm.attachment_processing_job IS
    'PostgreSQL-backed durable media processing jobs. Redis is never the source of truth for job delivery.';
