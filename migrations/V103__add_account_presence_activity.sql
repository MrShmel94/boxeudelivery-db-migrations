CREATE TABLE crm.account_presence
(
    account_id   UUID        NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (account_id),

    CONSTRAINT fk_account_presence_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT
);

COMMENT ON TABLE crm.account_presence IS
    'Durable, low-frequency account activity marker. Live online state remains ephemeral in Redis and is not persisted here.';

COMMENT ON COLUMN crm.account_presence.last_seen_at IS
    'Latest observed authenticated CRM WebSocket activity, refreshed periodically and on disconnect.';
