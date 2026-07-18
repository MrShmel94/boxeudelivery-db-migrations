INSERT INTO crm.currency_definition (
    code,
    display_name,
    symbol,
    fraction_digits,
    active,
    display_order
)
VALUES ('USD', 'US Dollar', '$', 2, TRUE, 10),
       ('EUR', 'Euro', '€', 2, TRUE, 20),
       ('PLN', 'Polish Zloty', 'zł', 2, TRUE, 30),
       ('RUB', 'Russian Ruble', '₽', 2, TRUE, 40),
       ('CNY', 'Chinese Yuan', '¥', 2, TRUE, 50)
ON CONFLICT (code) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        symbol = EXCLUDED.symbol,
        fraction_digits = EXCLUDED.fraction_digits,
        active = EXCLUDED.active,
        display_order = EXCLUDED.display_order,
        updated_at = CURRENT_TIMESTAMP;
