ALTER TABLE crm.cargo_item
    ADD COLUMN customer_profile_id UUID;

UPDATE crm.cargo_item item
SET customer_profile_id = profile.id
FROM crm.customer_profile profile
WHERE item.customer_account_id IS NOT NULL
  AND profile.project_id = item.project_id
  AND profile.supplier_id = item.supplier_id
  AND profile.linked_account_id = item.customer_account_id;

ALTER TABLE crm.cargo_item
    ADD CONSTRAINT fk_cargo_item_customer_profile
        FOREIGN KEY (customer_profile_id, project_id, supplier_id)
            REFERENCES crm.customer_profile (id, project_id, supplier_id) ON DELETE RESTRICT;

CREATE INDEX ix_cargo_item_customer_profile_status
    ON crm.cargo_item (project_id, supplier_id, customer_profile_id, status_code, created_at DESC, id)
    WHERE customer_profile_id IS NOT NULL;

COMMENT ON COLUMN crm.cargo_item.customer_profile_id IS
    'Optional durable customer identity. The separately stored linked account controls CRM access only.';
