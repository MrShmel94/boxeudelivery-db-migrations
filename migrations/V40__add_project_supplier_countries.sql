CREATE TABLE crm.project_supplier_country
(
    project_id          UUID         NOT NULL,
    supplier_id         UUID         NOT NULL,
    country_code        VARCHAR(2)   NOT NULL,
    assigned_by_subject VARCHAR(255) NOT NULL,
    assigned_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_project_supplier_country
        PRIMARY KEY (project_id, supplier_id, country_code),
    CONSTRAINT fk_project_supplier_country_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_project_supplier_country_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT,
    CONSTRAINT ck_project_supplier_country_code
        CHECK (country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_project_supplier_country_actor_not_blank
        CHECK (BTRIM(assigned_by_subject) <> '')
);

CREATE INDEX ix_project_supplier_country_lookup
    ON crm.project_supplier_country (project_id, country_code, supplier_id);

CREATE INDEX ix_project_supplier_country_usage
    ON crm.project_supplier_country (country_code, project_id, supplier_id);

INSERT INTO crm.project_supplier_country (
    project_id,
    supplier_id,
    country_code,
    assigned_by_subject,
    assigned_at
)
SELECT assignment.project_id,
       assignment.supplier_id,
       country.code,
       'migration:v40',
       CURRENT_TIMESTAMP
FROM crm.project_supplier assignment
CROSS JOIN crm.country country;

ALTER TABLE crm.supplier_audit_event
    DROP CONSTRAINT ck_supplier_audit_event_type,
    ADD CONSTRAINT ck_supplier_audit_event_type
        CHECK (event_type IN (
            'LEGACY_BACKFILLED',
            'CREATED',
            'UPDATED',
            'ACTIVATED',
            'DEACTIVATED',
            'MEMBER_ADDED',
            'MEMBER_REACTIVATED',
            'MEMBER_REMOVED',
            'CAPABILITIES_UPDATED',
            'COUNTRIES_UPDATED'
        ));

COMMENT ON TABLE crm.project_supplier_country IS
    'Project-scoped countries where a supplier group may create new inbound deliveries. Absence denies new use of that country.';
