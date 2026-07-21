CREATE TABLE crm.project_country
(
    project_id          UUID         NOT NULL,
    country_code        VARCHAR(2)   NOT NULL,
    assigned_by_subject VARCHAR(255) NOT NULL,
    assigned_at         TIMESTAMPTZ  NOT NULL,
    CONSTRAINT pk_project_country PRIMARY KEY (project_id, country_code),
    CONSTRAINT fk_project_country_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE CASCADE,
    CONSTRAINT fk_project_country_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT,
    CONSTRAINT ck_project_country_actor CHECK (BTRIM(assigned_by_subject) <> '')
);

CREATE INDEX ix_project_country_country
    ON crm.project_country (country_code, project_id);

CREATE TABLE crm.task_category
(
    id                 UUID         NOT NULL,
    country_code       VARCHAR(2)   NOT NULL,
    name               VARCHAR(150) NOT NULL,
    active             BOOLEAN      NOT NULL DEFAULT TRUE,
    sort_order         INTEGER      NOT NULL DEFAULT 0,
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL,
    updated_at         TIMESTAMPTZ  NOT NULL,
    version            BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_task_category PRIMARY KEY (id),
    CONSTRAINT uq_task_category_id_country UNIQUE (id, country_code),
    CONSTRAINT fk_task_category_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT,
    CONSTRAINT ck_task_category_name_not_blank CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_task_category_sort_order CHECK (sort_order >= 0),
    CONSTRAINT ck_task_category_created_actor CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_task_category_updated_actor CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_task_category_timestamps CHECK (updated_at >= created_at),
    CONSTRAINT ck_task_category_version CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_task_category_country_name
    ON crm.task_category (country_code, LOWER(BTRIM(name)));

CREATE INDEX ix_task_category_country_active_sort
    ON crm.task_category (country_code, active, sort_order, name, id);

CREATE TABLE crm.task_subcategory
(
    id                 UUID         NOT NULL,
    category_id        UUID         NOT NULL,
    country_code       VARCHAR(2)   NOT NULL,
    name               VARCHAR(150) NOT NULL,
    active             BOOLEAN      NOT NULL DEFAULT TRUE,
    sort_order         INTEGER      NOT NULL DEFAULT 0,
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL,
    updated_at         TIMESTAMPTZ  NOT NULL,
    version            BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_task_subcategory PRIMARY KEY (id),
    CONSTRAINT uq_task_subcategory_id_country UNIQUE (id, country_code),
    CONSTRAINT fk_task_subcategory_category_country
        FOREIGN KEY (category_id, country_code)
            REFERENCES crm.task_category (id, country_code) ON DELETE RESTRICT,
    CONSTRAINT ck_task_subcategory_name_not_blank CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_task_subcategory_sort_order CHECK (sort_order >= 0),
    CONSTRAINT ck_task_subcategory_created_actor CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_task_subcategory_updated_actor CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_task_subcategory_timestamps CHECK (updated_at >= created_at),
    CONSTRAINT ck_task_subcategory_version CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_task_subcategory_category_name
    ON crm.task_subcategory (category_id, LOWER(BTRIM(name)));

CREATE INDEX ix_task_subcategory_category_active_sort
    ON crm.task_subcategory (category_id, active, sort_order, name, id);

CREATE TABLE crm.task_system_classification_default
(
    country_code       VARCHAR(2)   NOT NULL,
    source_code        VARCHAR(32)  NOT NULL,
    subcategory_id     UUID         NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    updated_at         TIMESTAMPTZ  NOT NULL,
    version            BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_task_system_classification_default PRIMARY KEY (country_code, source_code),
    CONSTRAINT fk_task_system_default_subcategory_country
        FOREIGN KEY (subcategory_id, country_code)
            REFERENCES crm.task_subcategory (id, country_code) ON DELETE RESTRICT,
    CONSTRAINT ck_task_system_default_source
        CHECK (source_code IN ('INBOUND_DELIVERY', 'COURIER_TRIP')),
    CONSTRAINT ck_task_system_default_actor CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_task_system_default_version CHECK (version >= 0)
);

ALTER TABLE crm.task
    ADD COLUMN task_subcategory_id UUID,
    ADD CONSTRAINT fk_task_subcategory
        FOREIGN KEY (task_subcategory_id) REFERENCES crm.task_subcategory (id) ON DELETE RESTRICT;

CREATE INDEX ix_task_subcategory
    ON crm.task (task_subcategory_id)
    WHERE task_subcategory_id IS NOT NULL;

COMMENT ON TABLE crm.project_country IS
    'Explicit countries enabled for a project. This is not derived from warehouses, pickup points, or suppliers.';

COMMENT ON COLUMN crm.task.task_subcategory_id IS
    'Required by the application for every new task. Nullable only for legacy tasks until classification backfill is complete.';
