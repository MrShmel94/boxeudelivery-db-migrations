CREATE TABLE crm.chat_message
(
    id                UUID         PRIMARY KEY,
    conversation_id   UUID         NOT NULL,
    context_task_id   UUID         NOT NULL,
    author_account_id UUID         NOT NULL,
    sequence_number   BIGINT       NOT NULL,
    client_message_id UUID         NOT NULL,
    body              VARCHAR(10000),
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_chat_message_conversation_sequence
        UNIQUE (conversation_id, sequence_number),
    CONSTRAINT uq_chat_message_client_idempotency
        UNIQUE (conversation_id, author_account_id, client_message_id),
    CONSTRAINT uq_chat_message_id_conversation
        UNIQUE (id, conversation_id),
    CONSTRAINT fk_chat_message_conversation
        FOREIGN KEY (conversation_id) REFERENCES crm.task_conversation (id) ON DELETE RESTRICT,
    CONSTRAINT fk_chat_message_context_task
        FOREIGN KEY (context_task_id, conversation_id)
            REFERENCES crm.task (id, conversation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_chat_message_author_account
        FOREIGN KEY (author_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_chat_message_sequence
        CHECK (sequence_number > 0),
    CONSTRAINT ck_chat_message_body
        CHECK (body IS NULL OR (BTRIM(body) <> '' AND CHAR_LENGTH(body) <= 10000))
);

CREATE INDEX ix_chat_message_conversation_sequence_desc
    ON crm.chat_message (conversation_id, sequence_number DESC, id);

CREATE INDEX ix_chat_message_context_sequence_desc
    ON crm.chat_message (context_task_id, sequence_number DESC, id);

CREATE TABLE crm.chat_message_reaction
(
    message_id    UUID        NOT NULL,
    account_id    UUID        NOT NULL,
    reaction_code VARCHAR(32) NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (message_id, account_id),

    CONSTRAINT fk_chat_message_reaction_message
        FOREIGN KEY (message_id) REFERENCES crm.chat_message (id) ON DELETE RESTRICT,
    CONSTRAINT fk_chat_message_reaction_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT ck_chat_message_reaction_code
        CHECK (reaction_code IN ('THUMBS_UP', 'HEART', 'CHECK', 'LAUGH', 'SURPRISED', 'SAD')),
    CONSTRAINT ck_chat_message_reaction_timestamps
        CHECK (updated_at >= created_at)
);

CREATE INDEX ix_chat_message_reaction_message_code
    ON crm.chat_message_reaction (message_id, reaction_code, account_id);

CREATE TABLE crm.chat_message_viewed_receipt
(
    message_id UUID        NOT NULL,
    account_id UUID        NOT NULL,
    viewed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (message_id, account_id),

    CONSTRAINT fk_chat_message_viewed_receipt_message
        FOREIGN KEY (message_id) REFERENCES crm.chat_message (id) ON DELETE RESTRICT,
    CONSTRAINT fk_chat_message_viewed_receipt_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT
);

CREATE INDEX ix_chat_message_viewed_receipt_message_time
    ON crm.chat_message_viewed_receipt (message_id, viewed_at, account_id);

COMMENT ON TABLE crm.chat_message IS
    'Immutable user messages in a root task conversation, each attributed to one exact task context.';
COMMENT ON TABLE crm.chat_message_reaction IS
    'One current closed-code reaction per account and visible message.';
COMMENT ON TABLE crm.chat_message_viewed_receipt IS
    'First durable authorized visible time for an account and message; not proof of human comprehension.';
