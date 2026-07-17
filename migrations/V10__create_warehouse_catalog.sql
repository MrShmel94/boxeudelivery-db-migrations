CREATE TABLE crm.warehouse
(
    id                    UUID         NOT NULL,
    name                  VARCHAR(150) NOT NULL,
    location_description VARCHAR(1000) NOT NULL,
    created_by_subject    VARCHAR(255) NOT NULL,
    updated_by_subject    VARCHAR(255) NOT NULL,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version               BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_warehouse
        PRIMARY KEY (id),
    CONSTRAINT ck_warehouse_name_not_blank
        CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_warehouse_location_description_not_blank
        CHECK (BTRIM(location_description) <> ''),
    CONSTRAINT ck_warehouse_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_warehouse_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_warehouse_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_warehouse_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_warehouse_name_case_insensitive
    ON crm.warehouse (LOWER(BTRIM(name)));

CREATE INDEX ix_warehouse_updated_at
    ON crm.warehouse (updated_at DESC, id);

CREATE TABLE crm.project_warehouse
(
    project_id          UUID         NOT NULL,
    warehouse_id        UUID         NOT NULL,
    assigned_by_subject VARCHAR(255) NOT NULL,
    assigned_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_project_warehouse
        PRIMARY KEY (project_id, warehouse_id),
    CONSTRAINT fk_project_warehouse_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_project_warehouse_warehouse
        FOREIGN KEY (warehouse_id) REFERENCES crm.warehouse (id) ON DELETE RESTRICT,
    CONSTRAINT ck_project_warehouse_assigned_by_subject_not_blank
        CHECK (BTRIM(assigned_by_subject) <> '')
);

CREATE INDEX ix_project_warehouse_warehouse_project
    ON crm.project_warehouse (warehouse_id, project_id);

CREATE TABLE crm.warehouse_audit_event
(
    id            UUID         NOT NULL,
    warehouse_id  UUID         NOT NULL,
    event_type    VARCHAR(64)  NOT NULL,
    actor_subject VARCHAR(255) NOT NULL,
    details       JSONB        NOT NULL DEFAULT '{}'::JSONB,
    occurred_at   TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_warehouse_audit_event
        PRIMARY KEY (id),
    CONSTRAINT ck_warehouse_audit_event_type
        CHECK (event_type IN (
            'CREATED',
            'UPDATED',
            'DELETED',
            'PROJECT_ASSIGNED',
            'PROJECT_REMOVED'
        )),
    CONSTRAINT ck_warehouse_audit_event_actor_not_blank
        CHECK (BTRIM(actor_subject) <> ''),
    CONSTRAINT ck_warehouse_audit_event_details_object
        CHECK (jsonb_typeof(details) = 'object')
);

CREATE INDEX ix_warehouse_audit_event_warehouse_occurred_at
    ON crm.warehouse_audit_event (warehouse_id, occurred_at DESC);

COMMENT ON TABLE crm.warehouse IS
    'Global warehouse catalogue. A warehouse may be assigned to multiple projects.';
COMMENT ON COLUMN crm.warehouse.location_description IS
    'Required human-readable location description; not a structured postal address.';
COMMENT ON TABLE crm.project_warehouse IS
    'Explicit many-to-many assignment between projects and warehouses.';
COMMENT ON TABLE crm.warehouse_audit_event IS
    'Append-only warehouse lifecycle and project-assignment audit retained after warehouse deletion.';
