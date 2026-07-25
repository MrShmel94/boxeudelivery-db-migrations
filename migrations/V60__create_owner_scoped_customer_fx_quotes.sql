CREATE TABLE crm.cargo_item_customer_fx_quote_snapshot
(
    id                         UUID            NOT NULL,
    cargo_item_id              UUID            NOT NULL,
    project_id                 UUID            NOT NULL,
    purchase_entry_id          UUID            NOT NULL,
    purchase_revision          INTEGER         NOT NULL,
    customer_price_entry_id    UUID            NOT NULL,
    customer_price_revision    INTEGER         NOT NULL,
    base_currency_code         VARCHAR(3)      NOT NULL,
    quote_currency_code        VARCHAR(3)      NOT NULL,
    market_quote_per_base      NUMERIC(24, 10) NOT NULL,
    customer_quote_per_base    NUMERIC(24, 10) NOT NULL,
    quoted_on                  DATE            NOT NULL,
    visibility_scope_code      VARCHAR(24)     NOT NULL,
    owner_account_id           UUID,
    owner_supplier_id          UUID,
    supersedes_id              UUID,
    correction_reason          VARCHAR(500),
    active                     BOOLEAN         NOT NULL DEFAULT TRUE,
    created_by_account_id      UUID            NOT NULL,
    created_by_subject         VARCHAR(255)    NOT NULL,
    created_at                 TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_cargo_item_customer_fx_quote_snapshot
        PRIMARY KEY (id),
    CONSTRAINT uq_cargo_item_customer_fx_quote_supersedes
        UNIQUE (supersedes_id),
    CONSTRAINT fk_cargo_item_customer_fx_quote_item_scope
        FOREIGN KEY (cargo_item_id, project_id)
            REFERENCES crm.cargo_item (id, project_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_customer_fx_quote_purchase_revision
        FOREIGN KEY (purchase_entry_id, purchase_revision, cargo_item_id, project_id)
            REFERENCES crm.cargo_item_financial_revision (
                financial_entry_id,
                revision_number,
                cargo_item_id,
                project_id
            ) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_customer_fx_quote_customer_price_revision
        FOREIGN KEY (customer_price_entry_id, customer_price_revision, cargo_item_id, project_id)
            REFERENCES crm.cargo_item_financial_revision (
                financial_entry_id,
                revision_number,
                cargo_item_id,
                project_id
            ) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_customer_fx_quote_base_currency
        FOREIGN KEY (base_currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_customer_fx_quote_quote_currency
        FOREIGN KEY (quote_currency_code) REFERENCES crm.currency_definition (code) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_customer_fx_quote_owner_account
        FOREIGN KEY (owner_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_customer_fx_quote_owner_supplier
        FOREIGN KEY (project_id, owner_supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_customer_fx_quote_creator
        FOREIGN KEY (created_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_cargo_item_customer_fx_quote_supersedes
        FOREIGN KEY (supersedes_id)
            REFERENCES crm.cargo_item_customer_fx_quote_snapshot (id) ON DELETE RESTRICT,
    CONSTRAINT ck_cargo_item_customer_fx_quote_revisions
        CHECK (purchase_revision >= 1 AND customer_price_revision >= 1),
    CONSTRAINT ck_cargo_item_customer_fx_quote_pair
        CHECK (base_currency_code <> quote_currency_code),
    CONSTRAINT ck_cargo_item_customer_fx_quote_rates
        CHECK (market_quote_per_base > 0 AND customer_quote_per_base > 0),
    CONSTRAINT ck_cargo_item_customer_fx_quote_scope
        CHECK (visibility_scope_code IN ('PERSONAL', 'SUPPLIER_GROUP')),
    CONSTRAINT ck_cargo_item_customer_fx_quote_owner
        CHECK (
            (
                visibility_scope_code = 'PERSONAL'
                AND owner_account_id IS NOT NULL
                AND owner_supplier_id IS NULL
            )
            OR (
                visibility_scope_code = 'SUPPLIER_GROUP'
                AND owner_account_id IS NULL
                AND owner_supplier_id IS NOT NULL
            )
        ),
    CONSTRAINT ck_cargo_item_customer_fx_quote_actor_not_blank
        CHECK (BTRIM(created_by_subject) <> ''),
    CONSTRAINT ck_cargo_item_customer_fx_quote_correction
        CHECK (
            (supersedes_id IS NULL AND correction_reason IS NULL)
            OR (
                supersedes_id IS NOT NULL
                AND correction_reason IS NOT NULL
                AND BTRIM(correction_reason) <> ''
            )
        )
);

CREATE UNIQUE INDEX uq_cargo_item_customer_fx_quote_active_personal
    ON crm.cargo_item_customer_fx_quote_snapshot (
        cargo_item_id,
        purchase_entry_id,
        purchase_revision,
        customer_price_entry_id,
        customer_price_revision,
        owner_account_id
    )
    WHERE active AND visibility_scope_code = 'PERSONAL';

CREATE UNIQUE INDEX uq_cargo_item_customer_fx_quote_active_supplier
    ON crm.cargo_item_customer_fx_quote_snapshot (
        cargo_item_id,
        purchase_entry_id,
        purchase_revision,
        customer_price_entry_id,
        customer_price_revision,
        owner_supplier_id
    )
    WHERE active AND visibility_scope_code = 'SUPPLIER_GROUP';

CREATE INDEX ix_cargo_item_customer_fx_quote_item_current
    ON crm.cargo_item_customer_fx_quote_snapshot (
        cargo_item_id,
        purchase_entry_id,
        purchase_revision,
        customer_price_entry_id,
        customer_price_revision,
        active,
        created_at DESC,
        id
    );

CREATE INDEX ix_cargo_item_customer_fx_quote_personal_owner
    ON crm.cargo_item_customer_fx_quote_snapshot (owner_account_id, active, created_at DESC, id)
    WHERE owner_account_id IS NOT NULL;

CREATE INDEX ix_cargo_item_customer_fx_quote_supplier_owner
    ON crm.cargo_item_customer_fx_quote_snapshot (
        project_id,
        owner_supplier_id,
        active,
        created_at DESC,
        id
    )
    WHERE owner_supplier_id IS NOT NULL;

ALTER TABLE crm.cargo_audit_event
    DROP CONSTRAINT ck_cargo_audit_event_aggregate_type,
    ADD CONSTRAINT ck_cargo_audit_event_aggregate_type
        CHECK (aggregate_type IN (
            'SUPPLIER_GOODS',
            'INBOUND_DELIVERY',
            'INBOUND_PACKAGE',
            'COURIER_TRIP',
            'COURIER_ASSIGNMENT',
            'CARGO_ITEM',
            'CARGO_PHOTO',
            'CARGO_PHOTO_CAPTURE_SESSION',
            'CARGO_FINANCIAL_ENTRY',
            'CARGO_PURCHASE_RATE',
            'CARGO_CUSTOMER_FX_QUOTE',
            'CARGO_USER_DAILY_RATE',
            'CUSTOMER_ORDER',
            'CUSTOMER_ORDER_LINE',
            'PICKING_SESSION',
            'OUTBOUND_PACKAGE',
            'OUTBOUND_DELIVERY',
            'WAREHOUSE_RELOCATION'
        ));

COMMENT ON TABLE crm.cargo_item_customer_fx_quote_snapshot IS
    'Owner-scoped customer FX quote facts. Values are immutable, corrected by successor, and excluded from generic cargo and customer projections.';

COMMENT ON COLUMN crm.cargo_item_customer_fx_quote_snapshot.market_quote_per_base IS
    'Market quote-currency units for one base-currency unit at the moment the customer quote was recorded.';

COMMENT ON COLUMN crm.cargo_item_customer_fx_quote_snapshot.customer_quote_per_base IS
    'Confidential quote-currency units for one base-currency unit communicated to the customer.';

COMMENT ON COLUMN crm.cargo_item_customer_fx_quote_snapshot.visibility_scope_code IS
    'PERSONAL is visible only to the owning account and global administrators; SUPPLIER_GROUP follows current active group membership.';
