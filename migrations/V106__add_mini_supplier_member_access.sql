ALTER TABLE crm.project_supplier_member
    ADD COLUMN member_role_code VARCHAR(16) NOT NULL DEFAULT 'MEMBER',
    ADD CONSTRAINT ck_project_supplier_member_role
        CHECK (member_role_code IN ('LEADER', 'MEMBER'));

WITH ranked_mini_members AS (
    SELECT member.project_id,
           member.supplier_id,
           member.account_id,
           ROW_NUMBER() OVER (
               PARTITION BY member.project_id, member.supplier_id
               ORDER BY
                   CASE WHEN member.status_code = 'ACTIVE' THEN 0 ELSE 1 END,
                   member.created_at,
                   member.account_id
           ) AS member_rank
    FROM crm.project_supplier_member member
    JOIN crm.project_supplier assignment
      ON assignment.project_id = member.project_id
     AND assignment.supplier_id = member.supplier_id
    WHERE assignment.operating_mode = 'MINI'
)
UPDATE crm.project_supplier_member member
SET member_role_code = 'LEADER',
    updated_by_subject = 'migration:v106',
    updated_at = CURRENT_TIMESTAMP
FROM ranked_mini_members ranked
WHERE ranked.member_rank = 1
  AND member.project_id = ranked.project_id
  AND member.supplier_id = ranked.supplier_id
  AND member.account_id = ranked.account_id;

ALTER TABLE crm.project_supplier_member
    ALTER COLUMN member_role_code DROP DEFAULT;

CREATE UNIQUE INDEX uq_project_supplier_member_leader
    ON crm.project_supplier_member (project_id, supplier_id)
    WHERE member_role_code = 'LEADER';

CREATE TABLE crm.project_supplier_member_permission
(
    project_id         UUID         NOT NULL,
    supplier_id        UUID         NOT NULL,
    account_id         UUID         NOT NULL,
    permission_code    VARCHAR(16)  NOT NULL,
    granted_by_subject VARCHAR(255) NOT NULL,
    granted_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_project_supplier_member_permission
        PRIMARY KEY (project_id, supplier_id, account_id, permission_code),
    CONSTRAINT fk_project_supplier_member_permission_member
        FOREIGN KEY (project_id, supplier_id, account_id)
            REFERENCES crm.project_supplier_member (project_id, supplier_id, account_id) ON DELETE RESTRICT,
    CONSTRAINT ck_project_supplier_member_permission_code
        CHECK (permission_code IN ('GOODS', 'ORDERS', 'FINANCE')),
    CONSTRAINT ck_project_supplier_member_permission_actor_not_blank
        CHECK (BTRIM(granted_by_subject) <> '')
);

CREATE INDEX ix_project_supplier_member_permission_lookup
    ON crm.project_supplier_member_permission (project_id, supplier_id, permission_code, account_id);

INSERT INTO crm.project_supplier_member_permission (
    project_id,
    supplier_id,
    account_id,
    permission_code,
    granted_by_subject,
    granted_at
)
SELECT member.project_id,
       member.supplier_id,
       member.account_id,
       permission.permission_code,
       'migration:v106',
       CURRENT_TIMESTAMP
FROM crm.project_supplier_member member
JOIN crm.project_supplier assignment
  ON assignment.project_id = member.project_id
 AND assignment.supplier_id = member.supplier_id
CROSS JOIN (VALUES ('GOODS'), ('ORDERS'), ('FINANCE')) permission(permission_code)
WHERE assignment.operating_mode = 'MINI'
  AND member.member_role_code = 'MEMBER';

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
            'COUNTRIES_UPDATED',
            'MEMBER_PERMISSIONS_UPDATED',
            'LEADER_CHANGED'
        ));

COMMENT ON COLUMN crm.project_supplier_member.member_role_code IS
    'MINI project-supplier role. Exactly one member is LEADER; other members use explicit page permissions.';

COMMENT ON TABLE crm.project_supplier_member_permission IS
    'Explicit MINI supplier member page permissions. A MINI leader has all permissions implicitly.';
