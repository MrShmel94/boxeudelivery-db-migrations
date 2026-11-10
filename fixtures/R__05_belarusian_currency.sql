INSERT INTO crm.currency_definition (
    code,
    display_name,
    symbol,
    fraction_digits,
    active,
    display_order
)
VALUES ('BYN', 'Belarusian Ruble', 'Br', 2, TRUE, 60)
ON CONFLICT (code) DO NOTHING;
