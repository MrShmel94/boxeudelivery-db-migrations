ALTER TABLE crm.project_member
    ADD CONSTRAINT uq_project_member_id_project
        UNIQUE (id, project_id);

CREATE TABLE crm.project_task_counter
(
    project_id UUID   PRIMARY KEY,
    last_value BIGINT NOT NULL DEFAULT 0,

    CONSTRAINT fk_project_task_counter_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT ck_project_task_counter_last_value
        CHECK (last_value >= 0)
);

CREATE TABLE crm.task_conversation
(
    id                    UUID        PRIMARY KEY,
    project_id            UUID        NOT NULL,
    last_message_sequence BIGINT      NOT NULL DEFAULT 0,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    version               BIGINT      NOT NULL DEFAULT 0,

    CONSTRAINT uq_task_conversation_id_project
        UNIQUE (id, project_id),
    CONSTRAINT fk_task_conversation_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT ck_task_conversation_last_message_sequence
        CHECK (last_message_sequence >= 0),
    CONSTRAINT ck_task_conversation_version
        CHECK (version >= 0)
);

CREATE INDEX ix_task_conversation_project
    ON crm.task_conversation (project_id, created_at DESC, id);

CREATE TABLE crm.task
(
    id                    UUID          PRIMARY KEY,
    project_id            UUID          NOT NULL,
    conversation_id       UUID          NOT NULL,
    parent_task_id        UUID,
    task_key              VARCHAR(32)   NOT NULL,
    sequence_number       BIGINT        NOT NULL,
    title                 VARCHAR(200)  NOT NULL,
    description           VARCHAR(10000),
    status_code           VARCHAR(32)   NOT NULL DEFAULT 'PLANNED',
    priority_code         VARCHAR(32)   NOT NULL DEFAULT 'NORMAL',
    deadline_at           TIMESTAMPTZ   NOT NULL,
    deadline_zone_id      VARCHAR(64)   NOT NULL,
    completed_at          TIMESTAMPTZ,
    created_by_account_id UUID          NOT NULL,
    updated_by_account_id UUID          NOT NULL,
    created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    version               BIGINT        NOT NULL DEFAULT 0,

    CONSTRAINT uq_task_project_sequence
        UNIQUE (project_id, sequence_number),
    CONSTRAINT uq_task_key
        UNIQUE (task_key),
    CONSTRAINT uq_task_id_project
        UNIQUE (id, project_id),
    CONSTRAINT uq_task_id_conversation
        UNIQUE (id, conversation_id),
    CONSTRAINT uq_task_id_project_conversation
        UNIQUE (id, project_id, conversation_id),
    CONSTRAINT fk_task_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_conversation
        FOREIGN KEY (conversation_id, project_id)
            REFERENCES crm.task_conversation (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_parent
        FOREIGN KEY (parent_task_id, project_id, conversation_id)
            REFERENCES crm.task (id, project_id, conversation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_created_by_account
        FOREIGN KEY (created_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_updated_by_account
        FOREIGN KEY (updated_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_task_not_own_parent
        CHECK (parent_task_id IS NULL OR parent_task_id <> id),
    CONSTRAINT ck_task_key_not_blank
        CHECK (BTRIM(task_key) <> ''),
    CONSTRAINT ck_task_sequence_number
        CHECK (sequence_number > 0),
    CONSTRAINT ck_task_title_not_blank
        CHECK (BTRIM(title) <> ''),
    CONSTRAINT ck_task_description_not_blank
        CHECK (description IS NULL OR BTRIM(description) <> ''),
    CONSTRAINT ck_task_status
        CHECK (status_code IN ('PLANNED', 'IN_PROGRESS', 'BLOCKED', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT ck_task_priority
        CHECK (priority_code IN ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
    CONSTRAINT ck_task_deadline_zone_not_blank
        CHECK (BTRIM(deadline_zone_id) <> ''),
    CONSTRAINT ck_task_completed_at
        CHECK (
            (status_code = 'COMPLETED' AND completed_at IS NOT NULL)
            OR (status_code <> 'COMPLETED' AND completed_at IS NULL)
        ),
    CONSTRAINT ck_task_completed_after_creation
        CHECK (completed_at IS NULL OR completed_at >= created_at),
    CONSTRAINT ck_task_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_task_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_task_root_per_conversation
    ON crm.task (conversation_id)
    WHERE parent_task_id IS NULL;

CREATE INDEX ix_task_project_updated
    ON crm.task (project_id, updated_at DESC, id);

CREATE INDEX ix_task_project_status_deadline
    ON crm.task (project_id, status_code, deadline_at, id);

CREATE INDEX ix_task_parent
    ON crm.task (parent_task_id, id)
    WHERE parent_task_id IS NOT NULL;

CREATE TABLE crm.task_participant
(
    id                     UUID        PRIMARY KEY,
    project_id             UUID        NOT NULL,
    task_id                UUID        NOT NULL,
    project_member_id      UUID        NOT NULL,
    assigned_by_account_id UUID        NOT NULL,
    assigned_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    version                BIGINT      NOT NULL DEFAULT 0,

    CONSTRAINT uq_task_participant_task_member
        UNIQUE (task_id, project_member_id),
    CONSTRAINT fk_task_participant_task
        FOREIGN KEY (task_id, project_id) REFERENCES crm.task (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_participant_project_member
        FOREIGN KEY (project_member_id, project_id)
            REFERENCES crm.project_member (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_participant_assigned_by_account
        FOREIGN KEY (assigned_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_task_participant_version
        CHECK (version >= 0)
);

CREATE INDEX ix_task_participant_member_task
    ON crm.task_participant (project_member_id, task_id);

CREATE INDEX ix_task_participant_project_task
    ON crm.task_participant (project_id, task_id);

CREATE TABLE crm.task_audit_event
(
    id            UUID        PRIMARY KEY,
    project_id    UUID        NOT NULL,
    task_id       UUID        NOT NULL,
    event_type    VARCHAR(64) NOT NULL,
    actor_subject VARCHAR(255) NOT NULL,
    details       JSONB       NOT NULL DEFAULT '{}'::JSONB,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_task_audit_event_type
        CHECK (event_type IN (
            'CREATED',
            'UPDATED',
            'DEADLINE_CHANGED',
            'STATUS_CHANGED',
            'DELETED',
            'PARTICIPANT_ADDED',
            'PARTICIPANT_REMOVED'
        )),
    CONSTRAINT ck_task_audit_actor_not_blank
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_task_audit_details_object
        CHECK (JSONB_TYPEOF(details) = 'object')
);

CREATE INDEX ix_task_audit_task_occurred
    ON crm.task_audit_event (task_id, occurred_at DESC, id);

CREATE INDEX ix_task_audit_project_occurred
    ON crm.task_audit_event (project_id, occurred_at DESC, id);

COMMENT ON TABLE crm.project_task_counter IS
    'Race-safe project-local task sequence allocator. Values are never derived with MAX and committed keys are never reused.';
COMMENT ON TABLE crm.task_conversation IS
    'One durable conversation for one root task tree.';
COMMENT ON TABLE crm.task IS
    'Project task or subtask. Parent, project, and conversation are immutable after creation.';
COMMENT ON TABLE crm.task_participant IS
    'Exact-task participation backed by an authoritative membership in the same project.';
COMMENT ON TABLE crm.task_audit_event IS
    'Durable task audit trail. Task and project identifiers intentionally have no foreign keys so evidence survives controlled physical deletion.';
