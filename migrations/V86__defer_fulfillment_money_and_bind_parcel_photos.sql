ALTER TABLE crm.fulfillment_shipment
    DROP CONSTRAINT ck_fulfillment_shipment_money,
    ALTER COLUMN customer_amount DROP NOT NULL,
    ALTER COLUMN service_fee_amount DROP NOT NULL,
    ALTER COLUMN currency_code DROP NOT NULL,
    ADD CONSTRAINT ck_fulfillment_shipment_money CHECK (
        (
            customer_amount IS NULL
            AND service_fee_amount IS NULL
            AND currency_code IS NULL
            AND partner_entitlement_amount IS NULL
        )
        OR (
            customer_amount > 0
            AND service_fee_amount >= 0
            AND service_fee_amount < customer_amount
            AND partner_entitlement_amount > 0
            AND currency_code IS NOT NULL
        )
    ),
    ADD CONSTRAINT ck_fulfillment_shipment_settlement_money CHECK (
        status_code <> 'SETTLED'
        OR (
            customer_amount IS NOT NULL
            AND service_fee_amount IS NOT NULL
            AND currency_code IS NOT NULL
            AND partner_entitlement_amount IS NOT NULL
        )
    );

ALTER TABLE crm.fulfillment_parcel
    ADD COLUMN photo_evidence_message_id UUID,
    ADD CONSTRAINT fk_fulfillment_parcel_photo_evidence
        FOREIGN KEY (photo_evidence_message_id)
            REFERENCES crm.chat_message (id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX uq_fulfillment_parcel_photo_evidence
    ON crm.fulfillment_parcel (photo_evidence_message_id)
    WHERE photo_evidence_message_id IS NOT NULL;

COMMENT ON COLUMN crm.fulfillment_shipment.customer_amount IS
    'Actual amount received from the fulfillment customer; absent until financial settlement is recorded.';

COMMENT ON COLUMN crm.fulfillment_shipment.service_fee_amount IS
    'Box EU service fee fixed together with actual customer receipt at settlement.';

COMMENT ON COLUMN crm.fulfillment_parcel.photo_evidence_message_id IS
    'Task-chat message containing ready photo attachments explicitly bound to this parcel.';
