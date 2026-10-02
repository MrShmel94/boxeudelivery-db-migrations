ALTER TABLE crm.settlement_financial_account
    DROP CONSTRAINT ck_settlement_financial_account_type,
    DROP CONSTRAINT ck_settlement_financial_account_custodian,
    ADD CONSTRAINT ck_settlement_financial_account_type
        CHECK (account_type IN (
            'COMPANY_BANK', 'COMPANY_CARD', 'COMPANY_CASHBOX', 'COMPANY_WALLET',
            'EMPLOYEE_CARD', 'EMPLOYEE_CASH'
        )),
    ADD CONSTRAINT ck_settlement_financial_account_custodian
        CHECK (
            (account_type IN ('EMPLOYEE_CARD', 'EMPLOYEE_CASH')
                AND custodian_account_id IS NOT NULL)
            OR
            (account_type IN ('COMPANY_BANK', 'COMPANY_CARD', 'COMPANY_CASHBOX', 'COMPANY_WALLET')
                AND custodian_account_id IS NULL)
        );

ALTER TABLE crm.settlement_money_operation
    DROP CONSTRAINT ck_settlement_money_operation_payment_method,
    ADD CONSTRAINT ck_settlement_money_operation_payment_method
        CHECK (payment_method IS NULL OR payment_method IN (
            'CASH', 'BANK_TRANSFER', 'CARD_TRANSFER', 'WALLET_TRANSFER'
        ));
