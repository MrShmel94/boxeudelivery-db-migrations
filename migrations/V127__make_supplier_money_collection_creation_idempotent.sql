ALTER TABLE crm.settlement_supplier_money_collection
    ADD COLUMN client_request_id UUID NOT NULL,
    ADD COLUMN request_fingerprint VARCHAR(64) NOT NULL,
    ADD CONSTRAINT uq_settlement_supplier_money_collection_request UNIQUE (client_request_id),
    ADD CONSTRAINT ck_settlement_supplier_money_collection_fingerprint
        CHECK (request_fingerprint ~ '^[0-9a-f]{64}$');
