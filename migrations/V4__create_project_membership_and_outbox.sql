CREATE TABLE crm.project
(
    id                 UUID         PRIMARY KEY,
    name               VARCHAR(150) NOT NULL,
    name_normalized    VARCHAR(150) GENERATED ALWAYS AS (LOWER(BTRIM(name))) STORED,
    description        VARCHAR(2000),
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    version            BIGINT       NOT NULL DEFAULT 0,

    CONSTRAINT uq_project_name_normalized
        UNIQUE (name_normalized),
    CONSTRAINT ck_project_name_not_blank
        CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_project_description_not_blank
        CHECK (description IS NULL OR BTRIM(description) <> ''),
    CONSTRAINT ck_project_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_project_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_project_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_project_version
        CHECK (version >= 0)
);

CREATE INDEX ix_project_updated_at
    ON crm.project (updated_at DESC, id);

CREATE TABLE crm.project_member
(
    id                  UUID         PRIMARY KEY,
    project_id          UUID         NOT NULL,
    account_id          UUID         NOT NULL,
    assigned_by_subject VARCHAR(255) NOT NULL,
    assigned_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_by_subject  VARCHAR(255) NOT NULL,
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    version             BIGINT       NOT NULL DEFAULT 0,

    CONSTRAINT uq_project_member_project_account
        UNIQUE (project_id, account_id),
    CONSTRAINT fk_project_member_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_project_member_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_project_member_assigned_by_subject_not_blank
        CHECK (BTRIM(assigned_by_subject) <> ''),
    CONSTRAINT ck_project_member_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_project_member_timestamps
        CHECK (updated_at >= assigned_at),
    CONSTRAINT ck_project_member_version
        CHECK (version >= 0)
);

CREATE INDEX ix_project_member_account_project
    ON crm.project_member (account_id, project_id);

CREATE TABLE crm.project_member_role
(
    project_member_id   UUID         NOT NULL,
    role_scope          VARCHAR(32)  NOT NULL DEFAULT 'PROJECT',
    role_code           VARCHAR(64)  NOT NULL,
    assigned_by_subject VARCHAR(255) NOT NULL,
    assigned_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    PRIMARY KEY (project_member_id, role_code),

    CONSTRAINT fk_project_member_role_member
        FOREIGN KEY (project_member_id) REFERENCES crm.project_member (id) ON DELETE RESTRICT,
    CONSTRAINT fk_project_member_role_definition
        FOREIGN KEY (role_scope, role_code) REFERENCES crm.access_role (scope_type, code) ON DELETE RESTRICT,
    CONSTRAINT ck_project_member_role_scope
        CHECK (role_scope = 'PROJECT'),
    CONSTRAINT ck_project_member_role_assigned_by_subject_not_blank
        CHECK (BTRIM(assigned_by_subject) <> '')
);

CREATE INDEX ix_project_member_role_code
    ON crm.project_member_role (role_code, project_member_id);

CREATE TABLE crm.project_audit_event
(
    id            UUID         PRIMARY KEY,
    project_id    UUID         NOT NULL,
    event_type    VARCHAR(64)  NOT NULL,
    actor_subject VARCHAR(255) NOT NULL,
    details       JSONB        NOT NULL DEFAULT '{}'::JSONB,
    occurred_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_project_audit_event_type
        CHECK (event_type IN (
            'CREATED',
            'UPDATED',
            'DELETED',
            'MEMBER_ADDED',
            'MEMBER_ROLES_UPDATED',
            'MEMBER_REMOVED'
        )),
    CONSTRAINT ck_project_audit_event_actor_not_blank
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_project_audit_event_details_object
        CHECK (JSONB_TYPEOF(details) = 'object')
);

CREATE INDEX ix_project_audit_event_project_occurred_at
    ON crm.project_audit_event (project_id, occurred_at DESC);

CREATE TABLE crm.outbox_event
(
    id              UUID         PRIMARY KEY,
    aggregate_type  VARCHAR(64)  NOT NULL,
    aggregate_id    UUID         NOT NULL,
    event_type      VARCHAR(128) NOT NULL,
    event_version   INTEGER      NOT NULL,
    target_subject  VARCHAR(255) NOT NULL,
    resource_scope  VARCHAR(255) NOT NULL,
    payload         JSONB        NOT NULL DEFAULT '{}'::JSONB,
    occurred_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_at    TIMESTAMPTZ,
    attempt_count   INTEGER      NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    last_error      VARCHAR(1000),

    CONSTRAINT ck_outbox_event_aggregate_type_not_blank
        CHECK (BTRIM(aggregate_type) <> ''),
    CONSTRAINT ck_outbox_event_type_not_blank
        CHECK (BTRIM(event_type) <> ''),
    CONSTRAINT ck_outbox_event_version
        CHECK (event_version > 0),
    CONSTRAINT ck_outbox_event_target_subject_not_blank
        CHECK (BTRIM(target_subject) <> ''),
    CONSTRAINT ck_outbox_event_resource_scope_not_blank
        CHECK (BTRIM(resource_scope) <> ''),
    CONSTRAINT ck_outbox_event_payload_object
        CHECK (JSONB_TYPEOF(payload) = 'object'),
    CONSTRAINT ck_outbox_event_attempt_count
        CHECK (attempt_count >= 0),
    CONSTRAINT ck_outbox_event_published_at
        CHECK (published_at IS NULL OR published_at >= occurred_at),
    CONSTRAINT ck_outbox_event_retry_at
        CHECK (next_attempt_at >= occurred_at)
);

CREATE INDEX ix_outbox_event_pending
    ON crm.outbox_event (next_attempt_at, occurred_at, id)
    WHERE published_at IS NULL;

CREATE INDEX ix_outbox_event_published_at
    ON crm.outbox_event (published_at)
    WHERE published_at IS NOT NULL;

COMMENT ON TABLE crm.project IS
    'Top-level business work containers. Physical deletion is allowed only while no dependent rows exist.';
COMMENT ON TABLE crm.project_member IS
    'Explicit account membership in one project. Membership is separate from global account roles.';
COMMENT ON TABLE crm.project_member_role IS
    'Predefined PROJECT-scoped roles assigned to one concrete project membership.';
COMMENT ON TABLE crm.project_audit_event IS
    'Durable project audit trail. project_id intentionally has no foreign key so deletion evidence survives project deletion.';
COMMENT ON TABLE crm.outbox_event IS
    'Transactional outbox for at-least-once post-commit business-event publication.';
