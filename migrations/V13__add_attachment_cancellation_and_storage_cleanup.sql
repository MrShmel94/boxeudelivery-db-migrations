ALTER TABLE crm.chat_attachment
    ADD COLUMN cancelled_at TIMESTAMPTZ;

ALTER TABLE crm.chat_attachment
    DROP CONSTRAINT ck_chat_attachment_status,
    DROP CONSTRAINT ck_chat_attachment_completed_at,
    DROP CONSTRAINT ck_chat_attachment_ready_at,
    DROP CONSTRAINT ck_chat_attachment_failure;

ALTER TABLE crm.chat_attachment
    ADD CONSTRAINT ck_chat_attachment_status
        CHECK (status_code IN ('PENDING_UPLOAD', 'PROCESSING', 'READY', 'FAILED', 'CANCELLED')),
    ADD CONSTRAINT ck_chat_attachment_completed_at
        CHECK (
            (status_code = 'PENDING_UPLOAD' AND upload_completed_at IS NULL)
            OR (status_code IN ('PROCESSING', 'READY', 'FAILED') AND upload_completed_at IS NOT NULL)
            OR status_code = 'CANCELLED'
        ),
    ADD CONSTRAINT ck_chat_attachment_ready_at
        CHECK (
            (status_code = 'READY' AND ready_at IS NOT NULL)
            OR (status_code <> 'READY' AND ready_at IS NULL)
        ),
    ADD CONSTRAINT ck_chat_attachment_failure
        CHECK (
            (status_code = 'FAILED' AND failure_code IS NOT NULL)
            OR (status_code <> 'FAILED' AND failure_code IS NULL)
        ),
    ADD CONSTRAINT ck_chat_attachment_cancelled_at
        CHECK (
            (status_code = 'CANCELLED' AND cancelled_at IS NOT NULL)
            OR (status_code <> 'CANCELLED' AND cancelled_at IS NULL)
        );

CREATE INDEX ix_chat_attachment_unattached_cleanup
    ON crm.chat_attachment (created_at, id)
    WHERE message_id IS NULL AND status_code <> 'CANCELLED';

ALTER TABLE crm.task_audit_event
    DROP CONSTRAINT ck_task_audit_event_type;

ALTER TABLE crm.task_audit_event
    ADD CONSTRAINT ck_task_audit_event_type
        CHECK (event_type IN (
            'CREATED',
            'UPDATED',
            'DEADLINE_CHANGED',
            'STATUS_CHANGED',
            'DELETED',
            'PARTICIPANT_ADDED',
            'PARTICIPANT_REMOVED',
            'ATTACHMENT_CANCELLED'
        ));

CREATE TABLE crm.storage_object_deletion_job
(
    id              UUID          PRIMARY KEY,
    object_key      VARCHAR(1024) NOT NULL,
    source_type     VARCHAR(64)   NOT NULL,
    source_id       UUID          NOT NULL,
    status_code     VARCHAR(16)   NOT NULL DEFAULT 'PENDING',
    attempt_count   INTEGER       NOT NULL DEFAULT 0,
    not_before      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    locked_at       TIMESTAMPTZ,
    locked_by       VARCHAR(128),
    last_error_code VARCHAR(64),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_storage_object_deletion_job_key
        UNIQUE (object_key),
    CONSTRAINT ck_storage_object_deletion_job_key
        CHECK (BTRIM(object_key) <> ''),
    CONSTRAINT ck_storage_object_deletion_job_source
        CHECK (BTRIM(source_type) <> ''),
    CONSTRAINT ck_storage_object_deletion_job_status
        CHECK (status_code IN ('PENDING', 'RUNNING')),
    CONSTRAINT ck_storage_object_deletion_job_attempts
        CHECK (attempt_count >= 0),
    CONSTRAINT ck_storage_object_deletion_job_lock
        CHECK (
            (status_code = 'RUNNING' AND locked_at IS NOT NULL AND locked_by IS NOT NULL)
            OR (status_code = 'PENDING' AND locked_at IS NULL AND locked_by IS NULL)
        ),
    CONSTRAINT ck_storage_object_deletion_job_timestamps
        CHECK (updated_at >= created_at)
);

CREATE INDEX ix_storage_object_deletion_job_ready
    ON crm.storage_object_deletion_job (not_before, created_at, id)
    WHERE status_code = 'PENDING';

COMMENT ON TABLE crm.storage_object_deletion_job IS
    'Durable, retryable deletion of private object-storage keys. Business transactions enqueue exact keys; a bounded worker performs idempotent provider deletion.';
