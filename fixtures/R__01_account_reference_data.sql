INSERT INTO accounts.account_category (code, active, sort_order)
VALUES ('EMPLOYEE', TRUE, 10),
       ('SUPPLIER', TRUE, 20),
       ('CLIENT', TRUE, 30)
ON CONFLICT (code) DO UPDATE
    SET active = EXCLUDED.active,
        sort_order = EXCLUDED.sort_order,
        updated_at = NOW();

INSERT INTO accounts.access_role (code, active, sort_order)
VALUES ('ADMIN', TRUE, 10)
ON CONFLICT (code) DO UPDATE
    SET active = EXCLUDED.active,
        sort_order = EXCLUDED.sort_order,
        updated_at = NOW();
