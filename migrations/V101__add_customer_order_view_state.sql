CREATE TABLE crm.customer_order_viewed_receipt
(
    customer_order_id UUID        NOT NULL,
    account_id         UUID        NOT NULL,
    viewed_at          TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (customer_order_id, account_id),

    CONSTRAINT fk_customer_order_viewed_receipt_order
        FOREIGN KEY (customer_order_id) REFERENCES crm.customer_order (id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_order_viewed_receipt_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT
);

CREATE INDEX ix_customer_order_viewed_receipt_account_order
    ON crm.customer_order_viewed_receipt (account_id, customer_order_id);

INSERT INTO crm.customer_order_viewed_receipt (customer_order_id, account_id, viewed_at)
SELECT customer_order.id, administrator.account_id, NOW()
FROM crm.customer_order customer_order
CROSS JOIN (
    SELECT DISTINCT global_role.account_id
    FROM crm.account_global_role global_role
    JOIN crm.account account ON account.id = global_role.account_id
    WHERE global_role.role_scope = 'GLOBAL'
      AND global_role.role_code IN ('OWNER', 'CRM_ADMIN')
      AND account.status = 'ACTIVE'
) administrator
ON CONFLICT (customer_order_id, account_id) DO NOTHING;

INSERT INTO crm.customer_order_viewed_receipt (customer_order_id, account_id, viewed_at)
SELECT DISTINCT customer_order.id, member.account_id, NOW()
FROM crm.customer_order customer_order
JOIN crm.project_member member ON member.project_id = customer_order.project_id
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
ON CONFLICT (customer_order_id, account_id) DO NOTHING;

INSERT INTO crm.customer_order_viewed_receipt (customer_order_id, account_id, viewed_at)
SELECT DISTINCT customer_order.id, supplier_member.account_id, NOW()
FROM crm.customer_order customer_order
JOIN crm.project_supplier_member supplier_member
  ON supplier_member.project_id = customer_order.project_id
 AND supplier_member.supplier_id = customer_order.supplier_id
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
ON CONFLICT (customer_order_id, account_id) DO NOTHING;

INSERT INTO crm.customer_order_viewed_receipt (customer_order_id, account_id, viewed_at)
SELECT DISTINCT customer_order.id, member.account_id, NOW()
FROM crm.customer_order customer_order
JOIN crm.project_member member
  ON member.project_id = customer_order.project_id
 AND member.account_id = customer_order.customer_account_id
JOIN crm.project_member_role role
  ON role.project_member_id = member.id
 AND role.role_code = 'CUSTOMER'
JOIN crm.account account ON account.id = member.account_id
WHERE customer_order.customer_account_id IS NOT NULL
  AND account.status = 'ACTIVE'
ON CONFLICT (customer_order_id, account_id) DO NOTHING;

COMMENT ON TABLE crm.customer_order_viewed_receipt IS
    'First durable authorized customer-order card view per account. Absence means the order is new for that account; this is personal read state, not order lifecycle or audit.';
