CREATE TABLE crm.task_assignee
(
    id                     UUID        PRIMARY KEY,
    project_id             UUID        NOT NULL,
    task_id                UUID        NOT NULL,
    project_member_id      UUID        NOT NULL,
    assigned_by_account_id UUID        NOT NULL,
    assigned_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    version                BIGINT      NOT NULL DEFAULT 0,

    CONSTRAINT uq_task_assignee_task_member
        UNIQUE (task_id, project_member_id),
    CONSTRAINT fk_task_assignee_task
        FOREIGN KEY (task_id, project_id)
            REFERENCES crm.task (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_assignee_project_member
        FOREIGN KEY (project_member_id, project_id)
            REFERENCES crm.project_member (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_assignee_participant
        FOREIGN KEY (task_id, project_member_id)
            REFERENCES crm.task_participant (task_id, project_member_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_assignee_assigned_by_account
        FOREIGN KEY (assigned_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_task_assignee_version
        CHECK (version >= 0)
);

CREATE INDEX ix_task_assignee_member_task
    ON crm.task_assignee (project_member_id, task_id);

CREATE INDEX ix_task_assignee_project_task
    ON crm.task_assignee (project_id, task_id);

ALTER TABLE crm.task_audit_event
    DROP CONSTRAINT ck_task_audit_event_type,
    ADD CONSTRAINT ck_task_audit_event_type
        CHECK (event_type IN (
            'CREATED',
            'UPDATED',
            'DEADLINE_CHANGED',
            'STATUS_CHANGED',
            'DELETED',
            'PARTICIPANT_ADDED',
            'PARTICIPANT_REMOVED',
            'ASSIGNEE_ADDED',
            'ASSIGNEE_REMOVED',
            'ATTACHMENT_CANCELLED'
        ));

COMMENT ON TABLE crm.task_assignee IS
    'Accounts responsible for executing an exact task. Every assignee is also an exact task participant.';
