CREATE TABLE crm.supplier_goods_attention_state
(
    supplier_goods_entry_id UUID        NOT NULL,
    revision                BIGINT      NOT NULL,
    changed_at              TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (supplier_goods_entry_id),

    CONSTRAINT fk_supplier_goods_attention_state_entry
        FOREIGN KEY (supplier_goods_entry_id) REFERENCES crm.supplier_goods_entry (id) ON DELETE RESTRICT,
    CONSTRAINT ck_supplier_goods_attention_state_revision
        CHECK (revision > 0)
);

CREATE TABLE crm.supplier_goods_viewed_receipt
(
    supplier_goods_entry_id UUID        NOT NULL,
    account_id              UUID        NOT NULL,
    viewed_revision         BIGINT      NOT NULL,
    viewed_at               TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (supplier_goods_entry_id, account_id),

    CONSTRAINT fk_supplier_goods_viewed_receipt_state
        FOREIGN KEY (supplier_goods_entry_id)
            REFERENCES crm.supplier_goods_attention_state (supplier_goods_entry_id) ON DELETE RESTRICT,
    CONSTRAINT fk_supplier_goods_viewed_receipt_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_supplier_goods_viewed_receipt_revision
        CHECK (viewed_revision > 0)
);

CREATE INDEX ix_supplier_goods_viewed_receipt_account_entry_revision
    ON crm.supplier_goods_viewed_receipt (account_id, supplier_goods_entry_id, viewed_revision);

INSERT INTO crm.supplier_goods_attention_state (supplier_goods_entry_id, revision, changed_at)
SELECT entry.id, 1, entry.created_at
FROM crm.supplier_goods_entry entry;

INSERT INTO crm.supplier_goods_viewed_receipt (
    supplier_goods_entry_id,
    account_id,
    viewed_revision,
    viewed_at
)
SELECT state.supplier_goods_entry_id, administrator.account_id, state.revision, NOW()
FROM crm.supplier_goods_attention_state state
CROSS JOIN (
    SELECT DISTINCT global_role.account_id
    FROM crm.account_global_role global_role
    JOIN crm.account account ON account.id = global_role.account_id
    WHERE global_role.role_scope = 'GLOBAL'
      AND global_role.role_code IN ('OWNER', 'CRM_ADMIN')
      AND account.status = 'ACTIVE'
) administrator
ON CONFLICT (supplier_goods_entry_id, account_id) DO NOTHING;

INSERT INTO crm.supplier_goods_viewed_receipt (
    supplier_goods_entry_id,
    account_id,
    viewed_revision,
    viewed_at
)
SELECT DISTINCT entry.id, member.account_id, state.revision, NOW()
FROM crm.supplier_goods_entry entry
JOIN crm.supplier_goods_attention_state state ON state.supplier_goods_entry_id = entry.id
JOIN crm.project_member member ON member.project_id = entry.project_id
JOIN crm.project_member_role role ON role.project_member_id = member.id
JOIN crm.account account ON account.id = member.account_id
WHERE role.role_code IN (
    'OPERATIONS_MANAGER',
    'CUSTOMER_MANAGER',
    'BUYER',
    'LOGISTICS_SPECIALIST',
    'WAREHOUSE_OPERATOR',
    'CASHIER',
    'ACCOUNTANT',
    'FINANCIAL_CONTROLLER'
)
  AND account.status = 'ACTIVE'
ON CONFLICT (supplier_goods_entry_id, account_id) DO NOTHING;

INSERT INTO crm.supplier_goods_viewed_receipt (
    supplier_goods_entry_id,
    account_id,
    viewed_revision,
    viewed_at
)
SELECT DISTINCT entry.id, supplier_member.account_id, state.revision, NOW()
FROM crm.supplier_goods_entry entry
JOIN crm.supplier_goods_attention_state state ON state.supplier_goods_entry_id = entry.id
JOIN crm.project_supplier_member supplier_member
  ON supplier_member.project_id = entry.project_id
 AND supplier_member.supplier_id = entry.supplier_id
JOIN crm.project_supplier assignment
  ON assignment.project_id = supplier_member.project_id
 AND assignment.supplier_id = supplier_member.supplier_id
JOIN crm.supplier supplier ON supplier.id = supplier_member.supplier_id
JOIN crm.project_member member
  ON member.project_id = supplier_member.project_id
 AND member.account_id = supplier_member.account_id
JOIN crm.project_member_role role
  ON role.project_member_id = member.id
 AND role.role_code = 'SUPPLIER'
JOIN crm.account account ON account.id = supplier_member.account_id
WHERE supplier_member.status_code = 'ACTIVE'
  AND assignment.status_code = 'ACTIVE'
  AND supplier.status_code = 'ACTIVE'
  AND account.status = 'ACTIVE'
ON CONFLICT (supplier_goods_entry_id, account_id) DO NOTHING;

COMMENT ON TABLE crm.supplier_goods_attention_state IS
    'Monotonic attention revision for one reusable goods card. Initial creation and each later exact-item materialization advance the card attention state.';

COMMENT ON TABLE crm.supplier_goods_viewed_receipt IS
    'Per-account supplier-goods card revision explicitly viewed by the user. This is personal read state, not cargo audit or lifecycle state.';
