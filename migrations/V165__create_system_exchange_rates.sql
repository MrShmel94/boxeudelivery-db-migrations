CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;

CREATE TABLE crm.exchange_rate_pair
(
    id UUID PRIMARY KEY,
    base_currency VARCHAR(3) NOT NULL REFERENCES crm.currency_definition(code),
    quote_currency VARCHAR(3) NOT NULL REFERENCES crm.currency_definition(code),
    version BIGINT NOT NULL DEFAULT 0 CHECK (version >= 0),
    CONSTRAINT uq_exchange_rate_pair UNIQUE (base_currency, quote_currency),
    CONSTRAINT ck_exchange_rate_pair_distinct CHECK (base_currency <> quote_currency)
);

CREATE TABLE crm.exchange_rate_period
(
    id UUID PRIMARY KEY,
    pair_id UUID NOT NULL REFERENCES crm.exchange_rate_pair(id),
    quote_per_base NUMERIC(24,12) NOT NULL,
    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ,
    requested_valid_from TIMESTAMPTZ,
    requested_valid_to TIMESTAMPTZ,
    note VARCHAR(1000) NOT NULL DEFAULT '',
    created_by_subject VARCHAR(160) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT ck_exchange_rate_positive CHECK (quote_per_base > 0 AND quote_per_base <> 'NaN'::numeric),
    CONSTRAINT ck_exchange_rate_period CHECK (
        isfinite(valid_from) AND (valid_to IS NULL OR (isfinite(valid_to) AND valid_to > valid_from))
    ),
    CONSTRAINT ex_exchange_rate_period_overlap EXCLUDE USING gist
        (pair_id WITH =, tstzrange(valid_from, valid_to, '[)') WITH &&)
);

CREATE INDEX ix_exchange_rate_period_history ON crm.exchange_rate_period(pair_id, valid_from DESC);

CREATE TABLE crm.exchange_rate_audit_event
(
    id UUID PRIMARY KEY,
    pair_id UUID NOT NULL REFERENCES crm.exchange_rate_pair(id),
    new_rate_id UUID NOT NULL UNIQUE REFERENCES crm.exchange_rate_period(id),
    previous_rate_id UUID REFERENCES crm.exchange_rate_period(id),
    previous_valid_to TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    new_valid_from TIMESTAMPTZ NOT NULL,
    new_valid_to TIMESTAMPTZ,
    actor_subject VARCHAR(160) NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX ix_exchange_rate_audit_pair ON crm.exchange_rate_audit_event(pair_id, occurred_at DESC);
