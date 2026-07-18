-- V22 matched legacy actor subjects as a bare UUID, while persistent account
-- subjects use the canonical account:<uuid> form. Reconcile only unambiguous
-- active legacy groups and never replace a daily value created after V22.
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
      AND rate.user_daily_rate_snapshot_id IS NULL
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
               || legacy.account_id::TEXT || '|'
               || legacy.effective_on::TEXT || '|'
               || legacy.base_currency_code || '|'
               || legacy.quote_currency_code
           )::UUID,
           legacy.account_id,
           legacy.base_currency_code,
           legacy.quote_currency_code,
           legacy.quote_per_base,
           legacy.effective_on,
           'USER_MANUAL',
           NULL,
           NULL,
           TRUE,
           'account:' || legacy.account_id::TEXT,
           legacy.created_at
    FROM consistent_legacy_rate legacy
    WHERE NOT EXISTS (
        SELECT 1
        FROM crm.cargo_user_daily_purchase_rate_snapshot daily_rate
        WHERE daily_rate.account_id = legacy.account_id
          AND daily_rate.effective_on = legacy.effective_on
          AND daily_rate.base_currency_code = legacy.base_currency_code
          AND daily_rate.quote_currency_code = legacy.quote_currency_code
          AND daily_rate.active
    )
    ON CONFLICT DO NOTHING
    RETURNING id
), resolved_daily_rate AS (
    SELECT daily_rate.id,
           daily_rate.account_id,
           daily_rate.effective_on,
           daily_rate.base_currency_code,
           daily_rate.quote_currency_code,
           daily_rate.quote_per_base
    FROM crm.cargo_user_daily_purchase_rate_snapshot daily_rate
    JOIN consistent_legacy_rate legacy
      ON legacy.account_id = daily_rate.account_id
     AND legacy.effective_on = daily_rate.effective_on
     AND legacy.base_currency_code = daily_rate.base_currency_code
     AND legacy.quote_currency_code = daily_rate.quote_currency_code
     AND legacy.quote_per_base = daily_rate.quote_per_base
    WHERE daily_rate.active
      AND (
          EXISTS (SELECT 1 FROM inserted_daily_rate inserted WHERE inserted.id = daily_rate.id)
          OR daily_rate.created_by_subject = 'account:' || daily_rate.account_id::TEXT
      )
)
UPDATE crm.cargo_item_purchase_rate_snapshot item_rate
SET user_daily_rate_snapshot_id = daily_rate.id
FROM resolved_daily_rate daily_rate
WHERE item_rate.user_daily_rate_snapshot_id IS NULL
  AND item_rate.created_by_subject = 'account:' || daily_rate.account_id::TEXT
  AND item_rate.effective_on = daily_rate.effective_on
  AND item_rate.base_currency_code = daily_rate.base_currency_code
  AND item_rate.quote_currency_code = daily_rate.quote_currency_code
  AND item_rate.quote_per_base = daily_rate.quote_per_base;
