CREATE TABLE crm.supplier
(
    id                 UUID         NOT NULL,
    display_name       VARCHAR(150) NOT NULL,
    status_code        VARCHAR(16)  NOT NULL,
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version            BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_supplier
        PRIMARY KEY (id),
    CONSTRAINT ck_supplier_display_name_not_blank
        CHECK (BTRIM(display_name) <> ''),
    CONSTRAINT ck_supplier_status
        CHECK (status_code IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT ck_supplier_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_supplier_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_supplier_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_supplier_version
        CHECK (version >= 0)
);

CREATE INDEX ix_supplier_status_name
    ON crm.supplier (status_code, display_name, id);

CREATE TABLE crm.project_supplier
(
    project_id         UUID         NOT NULL,
    supplier_id        UUID         NOT NULL,
    status_code        VARCHAR(16)  NOT NULL,
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version            BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_project_supplier
        PRIMARY KEY (project_id, supplier_id),
    CONSTRAINT fk_project_supplier_project
        FOREIGN KEY (project_id) REFERENCES crm.project (id) ON DELETE RESTRICT,
    CONSTRAINT fk_project_supplier_supplier
        FOREIGN KEY (supplier_id) REFERENCES crm.supplier (id) ON DELETE RESTRICT,
    CONSTRAINT ck_project_supplier_status
        CHECK (status_code IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT ck_project_supplier_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_project_supplier_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_project_supplier_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_project_supplier_version
        CHECK (version >= 0)
);

CREATE INDEX ix_project_supplier_supplier_project
    ON crm.project_supplier (supplier_id, project_id);

CREATE TABLE crm.project_supplier_member
(
    project_id         UUID         NOT NULL,
    supplier_id        UUID         NOT NULL,
    account_id         UUID         NOT NULL,
    status_code        VARCHAR(16)  NOT NULL,
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version            BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_project_supplier_member
        PRIMARY KEY (project_id, supplier_id, account_id),
    CONSTRAINT fk_project_supplier_member_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_project_supplier_member_project_member
        FOREIGN KEY (project_id, account_id)
            REFERENCES crm.project_member (project_id, account_id) ON DELETE RESTRICT,
    CONSTRAINT ck_project_supplier_member_status
        CHECK (status_code IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT ck_project_supplier_member_created_by_subject_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_project_supplier_member_updated_by_subject_not_blank
        CHECK (BTRIM(updated_by_subject) <> ''),
    CONSTRAINT ck_project_supplier_member_timestamps
        CHECK (updated_at >= created_at),
    CONSTRAINT ck_project_supplier_member_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_project_supplier_member_active_account
    ON crm.project_supplier_member (project_id, account_id)
    WHERE status_code = 'ACTIVE';

CREATE INDEX ix_project_supplier_member_supplier_status
    ON crm.project_supplier_member (project_id, supplier_id, status_code, account_id);

CREATE INDEX ix_project_supplier_member_account_status
    ON crm.project_supplier_member (account_id, status_code, project_id, supplier_id);

CREATE TABLE crm.supplier_audit_event
(
    id            UUID         NOT NULL,
    project_id    UUID         NOT NULL,
    supplier_id   UUID         NOT NULL,
    event_type    VARCHAR(32)  NOT NULL,
    actor_subject VARCHAR(255) NOT NULL,
    details       JSONB        NOT NULL DEFAULT '{}'::JSONB,
    occurred_at   TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_supplier_audit_event
        PRIMARY KEY (id),
    CONSTRAINT fk_supplier_audit_event_project_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT ck_supplier_audit_event_type
        CHECK (event_type IN (
            'LEGACY_BACKFILLED',
            'CREATED',
            'UPDATED',
            'ACTIVATED',
            'DEACTIVATED',
            'MEMBER_ADDED',
            'MEMBER_REACTIVATED',
            'MEMBER_REMOVED'
        )),
    CONSTRAINT ck_supplier_audit_event_actor_not_blank
        CHECK (BTRIM(actor_subject) <> '')
);

CREATE INDEX ix_supplier_audit_event_supplier_occurred
    ON crm.supplier_audit_event (project_id, supplier_id, occurred_at DESC, id);

CREATE TEMPORARY TABLE legacy_supplier_scope ON COMMIT DROP AS
WITH scope AS (
    SELECT member.project_id, member.account_id
    FROM crm.project_member member
    JOIN crm.project_member_role role
      ON role.project_member_id = member.id
     AND role.role_code = 'SUPPLIER'
    UNION
    SELECT delivery.project_id, delivery.supplier_account_id
    FROM crm.inbound_delivery delivery
    UNION
    SELECT entry.project_id, entry.supplier_account_id
    FROM crm.supplier_goods_entry entry
    UNION
    SELECT item.project_id, item.supplier_account_id
    FROM crm.cargo_item item
    UNION
    SELECT customer_order.project_id, customer_order.supplier_account_id
    FROM crm.customer_order customer_order
)
SELECT scope.project_id,
       scope.account_id,
       CASE
           WHEN account.status = 'ACTIVE'
               AND EXISTS (
                   SELECT 1
                   FROM crm.project_member member
                   JOIN crm.project_member_role role
                     ON role.project_member_id = member.id
                    AND role.role_code = 'SUPPLIER'
                   WHERE member.project_id = scope.project_id
                     AND member.account_id = scope.account_id
               )
               THEN 'ACTIVE'
           ELSE 'INACTIVE'
       END AS status_code
FROM scope
JOIN crm.account account ON account.id = scope.account_id;

INSERT INTO crm.supplier (
    id,
    display_name,
    status_code,
    created_by_subject,
    updated_by_subject,
    created_at,
    updated_at
)
SELECT MD5('boxeudelivery:supplier:' || account.id::TEXT)::UUID,
       BTRIM(account.first_name || ' ' || account.last_name),
       CASE WHEN account.status = 'ACTIVE' THEN 'ACTIVE' ELSE 'INACTIVE' END,
       'migration:v32',
       'migration:v32',
       CURRENT_TIMESTAMP,
       CURRENT_TIMESTAMP
FROM crm.account account
WHERE EXISTS (
    SELECT 1
    FROM legacy_supplier_scope scope
    WHERE scope.account_id = account.id
);

INSERT INTO crm.project_supplier (
    project_id,
    supplier_id,
    status_code,
    created_by_subject,
    updated_by_subject,
    created_at,
    updated_at
)
SELECT scope.project_id,
       MD5('boxeudelivery:supplier:' || scope.account_id::TEXT)::UUID,
       scope.status_code,
       'migration:v32',
       'migration:v32',
       CURRENT_TIMESTAMP,
       CURRENT_TIMESTAMP
FROM legacy_supplier_scope scope;

INSERT INTO crm.project_supplier_member (
    project_id,
    supplier_id,
    account_id,
    status_code,
    created_by_subject,
    updated_by_subject,
    created_at,
    updated_at
)
SELECT scope.project_id,
       MD5('boxeudelivery:supplier:' || scope.account_id::TEXT)::UUID,
       scope.account_id,
       scope.status_code,
       'migration:v32',
       'migration:v32',
       CURRENT_TIMESTAMP,
       CURRENT_TIMESTAMP
FROM legacy_supplier_scope scope
WHERE EXISTS (
    SELECT 1
    FROM crm.project_member member
    WHERE member.project_id = scope.project_id
      AND member.account_id = scope.account_id
);

INSERT INTO crm.supplier_audit_event (
    id,
    project_id,
    supplier_id,
    event_type,
    actor_subject,
    details,
    occurred_at
)
SELECT MD5(
           'boxeudelivery:supplier-audit:'
           || scope.project_id::TEXT
           || ':'
           || scope.account_id::TEXT
       )::UUID,
       scope.project_id,
       MD5('boxeudelivery:supplier:' || scope.account_id::TEXT)::UUID,
       'LEGACY_BACKFILLED',
       'migration:v32',
       JSONB_BUILD_OBJECT('legacySupplierAccountId', scope.account_id),
       CURRENT_TIMESTAMP
FROM legacy_supplier_scope scope;

COMMENT ON TABLE crm.supplier IS
    'Global supplier-group identity. Accounts remain real people and receive project-scoped access through membership.';

COMMENT ON TABLE crm.project_supplier IS
    'Explicit activation of one supplier group inside one project.';

COMMENT ON TABLE crm.project_supplier_member IS
    'Project-scoped supplier data access for real accounts. Only active members with the SUPPLIER project role are authorized.';
