ALTER TABLE crm.project
    DROP CONSTRAINT uq_project_name_normalized,
    DROP COLUMN name_normalized;

CREATE UNIQUE INDEX uq_project_name_case_insensitive
    ON crm.project (LOWER(BTRIM(name)));

ALTER TABLE crm.project
    ADD COLUMN task_prefix VARCHAR(8),
    ADD COLUMN time_zone_id VARCHAR(64) NOT NULL DEFAULT 'Europe/Moscow';

WITH existing_project AS
(
    SELECT id,
           ROW_NUMBER() OVER (ORDER BY id) AS sequence_number
    FROM crm.project
)
UPDATE crm.project project
SET task_prefix = 'P' || LPAD(existing_project.sequence_number::TEXT, 7, '0')
FROM existing_project
WHERE existing_project.id = project.id;

ALTER TABLE crm.project
    ALTER COLUMN task_prefix SET NOT NULL,
    ADD CONSTRAINT ck_project_task_prefix
        CHECK (task_prefix ~ '^[A-Z][A-Z0-9]{1,7}$'),
    ADD CONSTRAINT ck_project_time_zone_not_blank
        CHECK (BTRIM(time_zone_id) <> '');

CREATE UNIQUE INDEX uq_project_task_prefix
    ON crm.project (task_prefix);

COMMENT ON COLUMN crm.project.task_prefix IS
    'Globally unique immutable prefix used to build human task keys such as ST-1. Existing projects receive a safe placeholder that an administrator may replace before the first task.';
COMMENT ON COLUMN crm.project.time_zone_id IS
    'IANA business time zone used as the default when interpreting new project task deadlines.';
