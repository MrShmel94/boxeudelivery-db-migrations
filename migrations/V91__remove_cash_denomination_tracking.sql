DROP TABLE crm.settlement_cash_denomination_posting;

DROP TABLE crm.settlement_cash_denomination;

ALTER TABLE crm.settlement_money_account_posting
    DROP CONSTRAINT uq_settlement_money_account_posting_currency;
