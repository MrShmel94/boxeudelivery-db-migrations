CREATE TABLE crm.chat_message_unread
(
    message_id UUID        NOT NULL,
    account_id UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (message_id, account_id),

    CONSTRAINT fk_chat_message_unread_message
        FOREIGN KEY (message_id) REFERENCES crm.chat_message (id) ON DELETE RESTRICT,
    CONSTRAINT fk_chat_message_unread_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT
);

CREATE INDEX ix_chat_message_unread_account_created
    ON crm.chat_message_unread (account_id, created_at DESC, message_id);

COMMENT ON TABLE crm.chat_message_unread IS
    'Current per-account unread chat inbox. Existing history is deliberately not backfilled; durable viewed receipts remain the immutable read evidence.';
