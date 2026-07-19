INSERT INTO crm.country (
    code,
    name,
    created_by_subject,
    updated_by_subject
)
VALUES ('PL', 'Польша', 'fixture:country-reference', 'fixture:country-reference'),
       ('BY', 'Беларусь', 'fixture:country-reference', 'fixture:country-reference'),
       ('RU', 'Россия', 'fixture:country-reference', 'fixture:country-reference')
ON CONFLICT (code) DO NOTHING;
