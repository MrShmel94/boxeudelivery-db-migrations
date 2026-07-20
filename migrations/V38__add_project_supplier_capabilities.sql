CREATE TABLE crm.project_supplier_capability
(
    project_id         UUID         NOT NULL,
    supplier_id        UUID         NOT NULL,
    capability_code    VARCHAR(64)  NOT NULL,
    granted_by_subject VARCHAR(255) NOT NULL,
    granted_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_project_supplier_capability
        PRIMARY KEY (project_id, supplier_id, capability_code),
    CONSTRAINT fk_project_supplier_capability_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT ck_project_supplier_capability_code
        CHECK (capability_code IN (
            'INBOUND_DIRECT_TO_WAREHOUSE',
            'INBOUND_VIA_PICKUP_POINT'
        )),
    CONSTRAINT ck_project_supplier_capability_actor_not_blank
        CHECK (BTRIM(granted_by_subject) <> '')
);

CREATE INDEX ix_project_supplier_capability_lookup
    ON crm.project_supplier_capability (project_id, capability_code, supplier_id);

INSERT INTO crm.project_supplier_capability (
    project_id,
    supplier_id,
    capability_code,
    granted_by_subject,
    granted_at
)
SELECT assignment.project_id,
       assignment.supplier_id,
       capability.capability_code,
       'migration:v38',
       CURRENT_TIMESTAMP
FROM crm.project_supplier assignment
CROSS JOIN (VALUES
    ('INBOUND_DIRECT_TO_WAREHOUSE'),
    ('INBOUND_VIA_PICKUP_POINT')
) capability(capability_code);

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
            'CAPABILITIES_UPDATED'
        ));

COMMENT ON TABLE crm.project_supplier_capability IS
    'Explicit project-scoped business operations enabled for one supplier group. Absence denies new use of that capability.';
