CREATE TABLE crm.cargo_user_daily_purchase_rate_snapshot
(
    id                       UUID            NOT NULL,
    account_id               UUID            NOT NULL,
    base_currency_code       VARCHAR(3)      NOT NULL,
    quote_currency_code      VARCHAR(3)      NOT NULL,
    quote_per_base           NUMERIC(24, 10) NOT NULL,
    effective_on             DATE            NOT NULL,
    source_code              VARCHAR(32)     NOT NULL,
    supersedes_id            UUID,
    correction_reason        VARCHAR(500),
    active                   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_by_subject       VARCHAR(255)    NOT NULL,
    created_at               TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_cargo_user_daily_purchase_rate
        PRIMARY KEY (id),
    CONSTRAINT uq_cargo_user_daily_rate_supersedes
        UNIQUE (supersedes_id),
    CONSTRAINT fk_cargo_user_daily_rate_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_user_daily_rate_base_currency
        FOREIGN KEY (base_currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_user_daily_rate_quote_currency
        FOREIGN KEY (quote_currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_user_daily_rate_supersedes
        FOREIGN KEY (supersedes_id)
            REFERENCES crm.cargo_user_daily_purchase_rate_snapshot (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_user_daily_rate_pair
        CHECK (base_currency_code <> quote_currency_code),
    CONSTRAINT ck_cargo_user_daily_rate_value
        CHECK (quote_per_base > 0),
    CONSTRAINT ck_cargo_user_daily_rate_source
        CHECK (source_code IN ('USER_MANUAL')),
    CONSTRAINT ck_cargo_user_daily_rate_actor
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_cargo_user_daily_rate_correction
        CHECK (
            (supersedes_id IS NULL AND correction_reason IS NULL)
            OR (
                supersedes_id IS NOT NULL
                AND correction_reason IS NOT NULL
                AND BTRIM(correction_reason) <> ''
            )
        )
);

CREATE UNIQUE INDEX uq_cargo_user_daily_rate_active_pair
    ON crm.cargo_user_daily_purchase_rate_snapshot (
        account_id,
        effective_on,
        base_currency_code,
        quote_currency_code
    )
    WHERE active;

CREATE INDEX ix_cargo_user_daily_rate_account_date
    ON crm.cargo_user_daily_purchase_rate_snapshot (
        account_id,
        effective_on DESC,
        quote_currency_code,
        active,
        base_currency_code,
        created_at DESC,
        id
    );

ALTER TABLE crm.cargo_item_purchase_rate_snapshot
    ADD COLUMN user_daily_rate_snapshot_id UUID,
    ADD CONSTRAINT fk_item_purchase_rate_user_daily
        FOREIGN KEY (user_daily_rate_snapshot_id)
            REFERENCES crm.cargo_user_daily_purchase_rate_snapshot (id) ON DELETE RESTRICT;

-- Reuse pre-V23 history only when one account used exactly one value for the
-- same date and directed pair. Conflicting legacy values remain unlinked
-- instead of silently selecting an arbitrary canonical rate.
WITH consistent_legacy_rate AS (
    SELECT account.id AS account_id,
           rate.effective_on,
           rate.base_currency_code,
           rate.quote_currency_code,
           MIN(rate.quote_per_base) AS quote_per_base,
           MIN(rate.created_at) AS created_at
    FROM crm.cargo_item_purchase_rate_snapshot rate
    JOIN crm.account account
      ON 'account:' || account.id::TEXT = rate.created_by_subject
    WHERE rate.active
    GROUP BY account.id,
             rate.effective_on,
             rate.base_currency_code,
             rate.quote_currency_code
    HAVING COUNT(DISTINCT rate.quote_per_base) = 1
), inserted_daily_rate AS (
    INSERT INTO crm.cargo_user_daily_purchase_rate_snapshot (
        id,
        account_id,
        base_currency_code,
        quote_currency_code,
        quote_per_base,
        effective_on,
        source_code,
        supersedes_id,
        correction_reason,
        active,
        created_by_subject,
        created_at
    )
    SELECT MD5(
               'cargo-user-daily-rate|'
               || account_id::TEXT || '|'
               || effective_on::TEXT || '|'
               || base_currency_code || '|'
               || quote_currency_code
           )::UUID,
           account_id,
           base_currency_code,
           quote_currency_code,
           quote_per_base,
           effective_on,
           'USER_MANUAL',
           NULL,
           NULL,
           TRUE,
           'account:' || account_id::TEXT,
           created_at
    FROM consistent_legacy_rate
    RETURNING id,
              account_id,
              effective_on,
              base_currency_code,
              quote_currency_code,
              quote_per_base
)
UPDATE crm.cargo_item_purchase_rate_snapshot item_rate
SET user_daily_rate_snapshot_id = daily_rate.id
FROM inserted_daily_rate daily_rate
WHERE item_rate.created_by_subject = 'account:' || daily_rate.account_id::TEXT
  AND item_rate.effective_on = daily_rate.effective_on
  AND item_rate.base_currency_code = daily_rate.base_currency_code
  AND item_rate.quote_currency_code = daily_rate.quote_currency_code
  AND item_rate.quote_per_base = daily_rate.quote_per_base;

CREATE INDEX ix_item_purchase_rate_user_daily
    ON crm.cargo_item_purchase_rate_snapshot (user_daily_rate_snapshot_id)
    WHERE user_daily_rate_snapshot_id IS NOT NULL;

ALTER TABLE crm.cargo_audit_event
    DROP CONSTRAINT ck_cargo_audit_event_aggregate_type,
    ADD CONSTRAINT ck_cargo_audit_event_aggregate_type
        CHECK (aggregate_type IN (
            'SUPPLIER_GOODS',
            'INBOUND_DELIVERY',
            'INBOUND_PACKAGE',
            'COURIER_ASSIGNMENT',
            'CARGO_ITEM',
            'CARGO_PHOTO',
            'CARGO_FINANCIAL_ENTRY',
            'CARGO_PURCHASE_RATE',
            'CARGO_USER_DAILY_RATE',
            'CUSTOMER_ORDER',
            'CUSTOMER_ORDER_LINE',
            'PICKING_SESSION',
            'OUTBOUND_PACKAGE',
            'OUTBOUND_DELIVERY'
        ));

COMMENT ON TABLE crm.cargo_user_daily_purchase_rate_snapshot IS
    'Immutable user-scoped daily directed rate preferences. One active value exists per account, date, and currency pair.';

COMMENT ON COLUMN crm.cargo_item_purchase_rate_snapshot.user_daily_rate_snapshot_id IS
    'Exact user daily-rate revision reused by this immutable item purchase-rate snapshot. Null is retained only for pre-V23 history.';
