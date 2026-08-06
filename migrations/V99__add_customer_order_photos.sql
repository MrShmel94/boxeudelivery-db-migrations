CREATE TABLE crm.customer_order_photo (
    attachment_id UUID PRIMARY KEY,
    customer_order_id UUID NOT NULL,
    project_id UUID NOT NULL,
    position INTEGER NOT NULL,
    caption VARCHAR(300),
    created_by_subject VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_customer_order_photo_attachment
        FOREIGN KEY (attachment_id) REFERENCES crm.chat_attachment(id),
    CONSTRAINT fk_customer_order_photo_order
        FOREIGN KEY (customer_order_id) REFERENCES crm.customer_order(id),
    CONSTRAINT uq_customer_order_photo_position UNIQUE (customer_order_id, position),
    CONSTRAINT ck_customer_order_photo_position CHECK (position >= 0 AND position < 10)
);

CREATE INDEX idx_customer_order_photo_order
    ON crm.customer_order_photo(customer_order_id, position, attachment_id);
