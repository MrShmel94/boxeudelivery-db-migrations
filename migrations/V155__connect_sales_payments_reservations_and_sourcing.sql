ALTER TABLE crm.sales_request
    ADD COLUMN payment_confirmed_at TIMESTAMPTZ,
    DROP CONSTRAINT sales_request_status_code_check,
    ADD CONSTRAINT sales_request_status_code_check
        CHECK (status_code IN ('NEW','REVIEWING','AWAITING_PREPAYMENT','PAID','CANCELLED')),
    ADD CONSTRAINT ck_sales_request_paid CHECK (status_code <> 'PAID' OR payment_confirmed_at IS NOT NULL);

ALTER TABLE crm.sales_request_audit DROP CONSTRAINT sales_request_audit_event_type_check;
ALTER TABLE crm.sales_request_audit ADD CONSTRAINT sales_request_audit_event_type_check
    CHECK (event_type IN ('CREATED','REVIEW_STARTED','MANAGER_CHANGED','TERMS_AGREED','CANCELLED',
        'PAYMENT_RECORDED','PAYMENT_REFUNDED','PREPAYMENT_CONFIRMED','STOCK_RESERVED','STOCK_RELEASED',
        'SOURCING_ASSIGNED','SOURCING_CHANGED','ORDERS_CREATED'));

ALTER TABLE crm.sales_request_line ADD CONSTRAINT uq_sales_request_line_scope UNIQUE (id, sales_request_id, project_id);

CREATE TABLE crm.sales_command (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES crm.project(id),
    sales_request_id UUID NOT NULL,
    command_key UUID NOT NULL,
    actor_subject VARCHAR(255) NOT NULL,
    fingerprint VARCHAR(64) NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT uq_sales_command_key UNIQUE (project_id, command_key),
    FOREIGN KEY (sales_request_id, project_id) REFERENCES crm.sales_request(id, project_id)
);

CREATE TABLE crm.sales_sourcing_assignment (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    sales_request_id UUID NOT NULL,
    sales_request_line_id UUID NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 1000),
    supplier_id UUID,
    employee_account_id UUID REFERENCES crm.account(id),
    warehouse_id UUID NOT NULL REFERENCES crm.warehouse(id),
    supplier_unit_amount NUMERIC(19,4) CHECK(supplier_unit_amount >= 0),
    supplier_currency_code VARCHAR(3) REFERENCES crm.currency_definition(code),
    supplier_terms VARCHAR(2000) NOT NULL CHECK (length(btrim(supplier_terms)) > 0),
    deadline_at TIMESTAMPTZ NOT NULL,
    status_code VARCHAR(24) NOT NULL CHECK (status_code IN ('OFFERED','ACCEPTED','PURCHASING','SHIPPED','RECEIVED','DECLINED','CANCELLED')),
    progress_comment VARCHAR(1000),
    created_by_subject VARCHAR(255) NOT NULL,
    updated_by_subject VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    version BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT uq_sales_sourcing_scope UNIQUE (id, sales_request_id, sales_request_line_id, project_id),
    FOREIGN KEY (sales_request_line_id, sales_request_id, project_id)
        REFERENCES crm.sales_request_line(id, sales_request_id, project_id),
    FOREIGN KEY (project_id, supplier_id) REFERENCES crm.project_supplier(project_id, supplier_id),
    CHECK (num_nonnulls(supplier_id, employee_account_id) = 1),
    CHECK ((supplier_unit_amount IS NULL) = (supplier_currency_code IS NULL)),
    CHECK (supplier_id IS NULL OR supplier_unit_amount IS NOT NULL)
);
CREATE INDEX ix_sales_sourcing_supplier ON crm.sales_sourcing_assignment(project_id,supplier_id,created_at DESC,id DESC);
CREATE INDEX ix_sales_sourcing_request ON crm.sales_sourcing_assignment(sales_request_id,created_at,id);

ALTER TABLE crm.cargo_item ADD COLUMN sales_request_line_id UUID REFERENCES crm.sales_request_line(id);
CREATE INDEX ix_cargo_item_sales_line ON crm.cargo_item(sales_request_line_id,id) WHERE sales_request_line_id IS NOT NULL;
ALTER TABLE crm.customer_order ADD COLUMN sales_request_id UUID;
ALTER TABLE crm.customer_order ADD CONSTRAINT fk_customer_order_sales_request
    FOREIGN KEY (sales_request_id,project_id) REFERENCES crm.sales_request(id,project_id);
ALTER TABLE crm.customer_order ADD CONSTRAINT uq_customer_order_sales_scope UNIQUE(id,sales_request_id,project_id);
CREATE INDEX ix_customer_order_sales ON crm.customer_order(sales_request_id,id) WHERE sales_request_id IS NOT NULL;

CREATE TABLE crm.cargo_sales_unit (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    sales_request_id UUID NOT NULL,
    sales_request_line_id UUID NOT NULL,
    cargo_item_id UUID NOT NULL REFERENCES crm.cargo_item(id),
    unit_number INTEGER NOT NULL CHECK (unit_number BETWEEN 1 AND 1000),
    sourcing_assignment_id UUID,
    unit_price NUMERIC(19,4) NOT NULL CHECK(unit_price > 0),
    currency_code VARCHAR(3) NOT NULL REFERENCES crm.currency_definition(code),
    prepayment_amount NUMERIC(19,4) NOT NULL CHECK(prepayment_amount >= 0 AND prepayment_amount <= unit_price),
    supplier_amount NUMERIC(19,4) CHECK(supplier_amount >= 0),
    supplier_currency_code VARCHAR(3) REFERENCES crm.currency_definition(code),
    product_confirmation VARCHAR(500) NOT NULL CHECK(length(btrim(product_confirmation)) > 0),
    customer_order_id UUID,
    customer_order_line_id UUID REFERENCES crm.customer_order_line(id),
    reserved_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ,
    received_warehouse_id UUID REFERENCES crm.warehouse(id),
    released_at TIMESTAMPTZ,
    release_reason VARCHAR(500),
    FOREIGN KEY (sales_request_line_id,sales_request_id,project_id)
        REFERENCES crm.sales_request_line(id,sales_request_id,project_id),
    FOREIGN KEY (sourcing_assignment_id,sales_request_id,sales_request_line_id,project_id)
        REFERENCES crm.sales_sourcing_assignment(id,sales_request_id,sales_request_line_id,project_id),
    FOREIGN KEY (customer_order_id,sales_request_id,project_id)
        REFERENCES crm.customer_order(id,sales_request_id,project_id),
    CHECK ((customer_order_id IS NULL) = (customer_order_line_id IS NULL)),
    CHECK ((supplier_amount IS NULL) = (supplier_currency_code IS NULL)),
    CHECK (customer_order_id IS NULL OR supplier_amount IS NOT NULL),
    CHECK ((released_at IS NULL AND release_reason IS NULL) OR (released_at IS NOT NULL AND length(btrim(release_reason)) > 0))
);
CREATE UNIQUE INDEX uq_cargo_sales_unit_active_item ON crm.cargo_sales_unit(cargo_item_id) WHERE released_at IS NULL;
CREATE UNIQUE INDEX uq_cargo_sales_unit_position ON crm.cargo_sales_unit(sales_request_line_id,unit_number) WHERE released_at IS NULL;
CREATE INDEX ix_cargo_sales_unit_request ON crm.cargo_sales_unit(sales_request_id,id);
CREATE INDEX ix_cargo_sales_unit_order ON crm.cargo_sales_unit(customer_order_id,id) WHERE customer_order_id IS NOT NULL;

ALTER TABLE crm.settlement_money_operation ADD COLUMN sales_request_id UUID;
ALTER TABLE crm.settlement_money_operation ADD CONSTRAINT fk_settlement_money_operation_sales
    FOREIGN KEY (sales_request_id,project_id) REFERENCES crm.sales_request(id,project_id);
ALTER TABLE crm.settlement_money_operation DROP CONSTRAINT ck_settlement_money_operation_type,
    DROP CONSTRAINT ck_settlement_money_operation_scope,
    DROP CONSTRAINT ck_settlement_money_operation_shape;
ALTER TABLE crm.settlement_money_operation ADD CONSTRAINT ck_settlement_money_operation_type
    CHECK (operation_type IN ('CUSTOMER_ADVANCE','CUSTOMER_ORDER_CHARGE','CUSTOMER_ORDER_RECEIPT',
        'CUSTOMER_ORDER_DELIVERY_EXPENSE','CUSTOMER_REFUND','COUNTERPARTY_ADJUSTMENT','INTERNAL_TRANSFER',
        'INTERNAL_CONVERSION','COMPANY_MONEY_IN','COMPANY_MONEY_OUT','SUPPLIER_ACCRUAL',
        'SUPPLIER_ENTITLEMENT_ADJUSTMENT','SUPPLIER_DEDUCTION','SUPPLIER_PAYOUT','SALES_ADVANCE','SALES_REFUND')),
    ADD CONSTRAINT ck_settlement_money_operation_scope CHECK (
        (sales_request_id IS NULL AND ((project_id IS NULL AND supplier_id IS NULL) OR (project_id IS NOT NULL AND supplier_id IS NOT NULL)))
        OR (sales_request_id IS NOT NULL AND project_id IS NOT NULL AND supplier_id IS NULL)
    ),
    ADD CONSTRAINT ck_settlement_money_operation_shape CHECK (
        (sales_request_id IS NULL AND (

        (
            operation_type = 'CUSTOMER_ADVANCE' AND project_id IS NOT NULL
            AND counterparty_type = 'CUSTOMER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND counterparty_delta = amount AND reason IS NULL
        ) OR (
            operation_type = 'CUSTOMER_ORDER_CHARGE' AND project_id IS NOT NULL
            AND counterparty_type = 'CUSTOMER' AND customer_order_id IS NOT NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta = -amount AND reason IS NULL
        ) OR (
            operation_type = 'CUSTOMER_ORDER_RECEIPT' AND project_id IS NOT NULL
            AND customer_order_id IS NOT NULL AND fulfillment_shipment_id IS NULL
            AND outbound_delivery_id IS NULL AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL
            AND payment_method IS NOT NULL AND counterparty_delta IS NULL AND reason IS NULL
            AND ((counterparty_type IS NULL AND customer_profile_id IS NULL)
                OR (counterparty_type = 'CUSTOMER' AND customer_profile_id IS NOT NULL))
        ) OR (
            operation_type = 'CUSTOMER_ORDER_DELIVERY_EXPENSE'
            AND project_id IS NOT NULL AND supplier_id IS NOT NULL
            AND counterparty_type IS NULL AND customer_profile_id IS NULL
            AND customer_order_id IS NOT NULL AND fulfillment_shipment_id IS NULL
            AND outbound_delivery_id IS NOT NULL AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta IS NULL AND reason IS NULL
        ) OR (
            operation_type = 'CUSTOMER_REFUND' AND project_id IS NOT NULL
            AND counterparty_type = 'CUSTOMER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND counterparty_delta = -amount AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'COUNTERPARTY_ADJUSTMENT' AND project_id IS NOT NULL
            AND counterparty_type IS NOT NULL AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta IS NOT NULL AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type IN ('INTERNAL_TRANSFER', 'INTERNAL_CONVERSION')
            AND project_id IS NULL AND supplier_id IS NULL AND counterparty_type IS NULL
            AND customer_profile_id IS NULL AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NOT NULL
            AND financial_account_id <> destination_financial_account_id
            AND payment_method IS NULL AND counterparty_delta IS NULL
            AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_ACCRUAL' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER'
            AND NUM_NONNULLS(customer_order_id, fulfillment_shipment_id) = 1
            AND outbound_delivery_id IS NULL AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL
            AND payment_method IS NULL AND counterparty_delta = amount
            AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_ENTITLEMENT_ADJUSTMENT' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER'
            AND NUM_NONNULLS(customer_order_id, fulfillment_shipment_id) = 1
            AND outbound_delivery_id IS NULL AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL
            AND payment_method IS NULL AND counterparty_delta IS NOT NULL AND counterparty_delta <> 0
            AND amount = ABS(counterparty_delta) AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_DEDUCTION' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NULL
            AND counterparty_delta = -amount AND reason IS NOT NULL AND BTRIM(reason) <> ''
        ) OR (
            operation_type = 'SUPPLIER_PAYOUT' AND project_id IS NOT NULL
            AND counterparty_type = 'SUPPLIER' AND customer_order_id IS NULL
            AND fulfillment_shipment_id IS NULL AND outbound_delivery_id IS NULL
            AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND (counterparty_delta IS NULL OR counterparty_delta = -amount) AND reason IS NULL
        )
        OR (
            operation_type IN ('COMPANY_MONEY_IN', 'COMPANY_MONEY_OUT')
            AND project_id IS NULL AND supplier_id IS NULL
            AND counterparty_type IS NULL AND customer_profile_id IS NULL
            AND customer_order_id IS NULL AND fulfillment_shipment_id IS NULL
            AND outbound_delivery_id IS NULL
            AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL
            AND payment_method IS NULL AND counterparty_delta IS NULL
            AND reason IS NOT NULL AND BTRIM(reason) <> ''
        )
            )) OR (
            operation_type IN ('SALES_ADVANCE','SALES_REFUND') AND sales_request_id IS NOT NULL
            AND project_id IS NOT NULL AND supplier_id IS NULL AND customer_profile_id IS NULL
            AND counterparty_type IS NULL AND customer_order_id IS NULL AND fulfillment_shipment_id IS NULL
            AND outbound_delivery_id IS NULL AND financial_account_id IS NOT NULL
            AND destination_financial_account_id IS NULL AND payment_method IS NOT NULL
            AND counterparty_delta IS NULL
            AND (operation_type <> 'SALES_REFUND' OR (reason IS NOT NULL AND length(btrim(reason)) > 0))
        )
    );
CREATE INDEX ix_settlement_money_operation_sales ON crm.settlement_money_operation(sales_request_id,currency_code,id)
    WHERE sales_request_id IS NOT NULL;

CREATE TABLE crm.settlement_sales_order_funding (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    sales_request_id UUID NOT NULL,
    customer_order_id UUID NOT NULL,
    currency_code VARCHAR(3) NOT NULL REFERENCES crm.currency_definition(code),
    amount NUMERIC(19,4) NOT NULL CHECK(amount > 0),
    created_at TIMESTAMPTZ NOT NULL,
    created_by_subject VARCHAR(255) NOT NULL,
    released_at TIMESTAMPTZ,
    release_reason VARCHAR(500),
    CONSTRAINT uq_settlement_sales_funding_currency UNIQUE(customer_order_id,currency_code),
    FOREIGN KEY(customer_order_id,sales_request_id,project_id) REFERENCES crm.customer_order(id,sales_request_id,project_id),
    CHECK ((released_at IS NULL AND release_reason IS NULL) OR (released_at IS NOT NULL AND length(btrim(release_reason)) > 0))
);
CREATE INDEX ix_settlement_sales_funding_request ON crm.settlement_sales_order_funding(sales_request_id,id);

CREATE FUNCTION crm.enforce_sales_stock_exclusivity() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE held_line UUID; candidate_id UUID;
BEGIN
    IF TG_TABLE_NAME = 'cargo_item' THEN
        IF NEW.sales_request_line_id IS NULL THEN RETURN NEW; END IF;
        IF NOT EXISTS (SELECT 1 FROM crm.sales_request_line line JOIN crm.sales_request request ON request.id=line.sales_request_id
            WHERE line.id=NEW.sales_request_line_id AND line.project_id=NEW.project_id AND request.payment_confirmed_at IS NOT NULL
                AND request.status_code='PAID') THEN
            RAISE EXCEPTION 'Confirmed paid sales request required' USING ERRCODE='23514',CONSTRAINT='ck_cargo_sales_reservation_exclusive';
        END IF;
        IF TG_OP='UPDATE' AND OLD.sales_request_line_id IS NOT NULL AND (
            OLD.sales_request_line_id IS DISTINCT FROM NEW.sales_request_line_id
            OR OLD.supplier_id IS DISTINCT FROM NEW.supplier_id
            OR OLD.supplier_goods_variant_id IS DISTINCT FROM NEW.supplier_goods_variant_id
            OR OLD.customer_profile_id IS DISTINCT FROM NEW.customer_profile_id
            OR OLD.customer_account_id IS DISTINCT FROM NEW.customer_account_id) THEN
            RAISE EXCEPTION 'Release the sales commitment before changing ownership' USING ERRCODE='23514',CONSTRAINT='ck_cargo_sales_reservation_exclusive';
        END IF;
        IF NEW.status_code IN ('IN_RELOCATION','PICKED_FOR_ORDER','PACKED_FOR_CUSTOMER','DELIVERED_TO_CUSTOMER')
            OR EXISTS (SELECT 1 FROM crm.customer_order_line line WHERE line.cargo_item_id=NEW.id AND line.status_code<>'REMOVED')
            OR EXISTS (SELECT 1 FROM crm.warehouse_relocation_item link JOIN crm.warehouse_relocation relocation ON relocation.id=link.relocation_id
                WHERE link.cargo_item_id=NEW.id AND relocation.status_code NOT IN ('COMPLETED','CANCELLED')) THEN
            RAISE EXCEPTION 'Physical unit already belongs to another operation' USING ERRCODE='23514',CONSTRAINT='ck_cargo_sales_reservation_exclusive';
        END IF;
        IF NEW.status_code='AVAILABLE' AND NEW.accepted_at IS NOT NULL THEN
            UPDATE crm.cargo_sales_unit SET received_at=NEW.accepted_at,received_warehouse_id=NEW.current_warehouse_id
                WHERE cargo_item_id=NEW.id AND released_at IS NULL AND customer_order_id IS NULL AND received_at IS NULL;
        END IF;
    ELSE
        candidate_id := NEW.cargo_item_id;
        SELECT sales_request_line_id INTO held_line FROM crm.cargo_item WHERE id=candidate_id FOR UPDATE;
        IF held_line IS NOT NULL THEN
            IF TG_TABLE_NAME='customer_order_line' THEN
                IF NEW.status_code='REMOVED' THEN RETURN NEW; END IF;
            END IF;
            RAISE EXCEPTION 'Physical unit is reserved by sales' USING ERRCODE='23514',CONSTRAINT='ck_cargo_sales_reservation_exclusive';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER sales_stock_exclusive BEFORE INSERT OR UPDATE ON crm.cargo_item
    FOR EACH ROW EXECUTE FUNCTION crm.enforce_sales_stock_exclusivity();
CREATE TRIGGER sales_stock_exclusive BEFORE INSERT OR UPDATE OF cargo_item_id,status_code ON crm.customer_order_line
    FOR EACH ROW EXECUTE FUNCTION crm.enforce_sales_stock_exclusivity();
CREATE TRIGGER sales_stock_exclusive BEFORE INSERT OR UPDATE OF cargo_item_id ON crm.warehouse_relocation_item
    FOR EACH ROW EXECUTE FUNCTION crm.enforce_sales_stock_exclusivity();
CREATE OR REPLACE FUNCTION crm.touch_website_stock_eligibility_revision() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    previous_project UUID;
    current_project UUID;
    relevant_columns TEXT[];
BEGIN
    IF TG_OP='UPDATE' THEN
        relevant_columns := CASE TG_TABLE_NAME
            WHEN 'cargo_item' THEN ARRAY['current_warehouse_id','accepted_at','inbound_delivery_id','project_id','sales_request_line_id']
            WHEN 'inbound_delivery' THEN ARRAY['status_code','project_id']
            WHEN 'mini_supplier_intake' THEN ARRAY['completed_at','project_id']
            WHEN 'mini_supplier_intake_item' THEN ARRAY['intake_id','cargo_item_id','project_id']
            WHEN 'warehouse_relocation' THEN ARRAY['status_code','project_id']
            WHEN 'warehouse_relocation_item' THEN ARRAY['relocation_id','cargo_item_id','project_id']
        END;
        IF (SELECT bool_and(to_jsonb(NEW)->column_name IS NOT DISTINCT FROM to_jsonb(OLD)->column_name)
            FROM unnest(relevant_columns) column_name) THEN
            RETURN NULL;
        END IF;
    END IF;
    IF TG_OP<>'INSERT' THEN previous_project := (to_jsonb(OLD)->>'project_id')::UUID; END IF;
    IF TG_OP<>'DELETE' THEN current_project := (to_jsonb(NEW)->>'project_id')::UUID; END IF;
    INSERT INTO crm.website_catalog_revision(project_id,transaction_id)
        SELECT id,txid_current() FROM crm.project WHERE id IN (previous_project,current_project)
        ON CONFLICT(project_id,transaction_id) DO NOTHING;
    RETURN NULL;
END;
$$;


DROP TRIGGER website_stock_eligibility_changed ON crm.cargo_item;
CREATE TRIGGER website_stock_eligibility_changed
    AFTER UPDATE OF current_warehouse_id,accepted_at,inbound_delivery_id,project_id,sales_request_line_id ON crm.cargo_item
    FOR EACH ROW EXECUTE FUNCTION crm.touch_website_stock_eligibility_revision();

CREATE VIEW crm.sales_fulfillment_progress AS
SELECT request.id AS sales_request_id,
    (SELECT COALESCE(SUM(line.quantity),0) FROM crm.sales_request_line line WHERE line.sales_request_id=request.id) AS requested_quantity,
    COUNT(unit.id) FILTER (WHERE unit.released_at IS NULL AND (unit.customer_order_line_id IS NULL OR order_line.status_code<>'REMOVED')) AS committed_quantity,
    COUNT(unit.id) FILTER (WHERE unit.released_at IS NULL AND order_line.status_code='DELIVERED') AS delivered_quantity,
    COUNT(unit.id) FILTER (WHERE unit.released_at IS NULL AND unit.customer_order_line_id IS NOT NULL AND order_line.status_code NOT IN ('REMOVED','DELIVERED')) AS ordered_quantity,
    COUNT(unit.id) FILTER (WHERE unit.released_at IS NULL AND unit.customer_order_line_id IS NULL
        AND item.status_code='AVAILABLE' AND item.accepted_at IS NOT NULL AND item.current_warehouse_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM crm.inbound_delivery delivery WHERE delivery.id=item.inbound_delivery_id AND delivery.status_code NOT IN ('COMPLETED','CANCELLED'))
        AND NOT EXISTS (SELECT 1 FROM crm.mini_supplier_intake_item link JOIN crm.mini_supplier_intake intake ON intake.id=link.intake_id
            WHERE link.cargo_item_id=item.id AND intake.completed_at IS NULL)) AS ready_quantity
FROM crm.sales_request request
LEFT JOIN crm.cargo_sales_unit unit ON unit.sales_request_id=request.id
LEFT JOIN crm.cargo_item item ON item.id=unit.cargo_item_id
LEFT JOIN crm.customer_order_line order_line ON order_line.id=unit.customer_order_line_id
GROUP BY request.id;

CREATE FUNCTION crm.sales_request_stage(request_id UUID) RETURNS TEXT LANGUAGE sql STABLE AS $$
SELECT CASE WHEN request.status_code<>'PAID' THEN request.status_code
    WHEN progress.delivered_quantity=progress.requested_quantity THEN 'COMPLETED'
    WHEN progress.ready_quantity+progress.ordered_quantity+progress.delivered_quantity=progress.requested_quantity
        THEN CASE WHEN progress.ready_quantity=0 THEN 'HANDING_OVER' ELSE 'READY_FOR_HANDOVER' END
    WHEN progress.committed_quantity>0 OR EXISTS (SELECT 1 FROM crm.sales_sourcing_assignment assignment
        WHERE assignment.sales_request_id=request.id AND assignment.status_code NOT IN ('CANCELLED','DECLINED')) THEN 'SOURCING'
    ELSE 'ORGANIZING_SOURCING' END
FROM crm.sales_request request JOIN crm.sales_fulfillment_progress progress ON progress.sales_request_id=request.id
WHERE request.id=request_id
$$;

CREATE VIEW crm.supplier_order_financial_line AS
SELECT line.id,line.customer_order_id,line.project_id,line.cargo_item_id,line.status_code,
    CASE WHEN customer_order.sales_request_id IS NOT NULL THEN unit.supplier_amount ELSE line.unit_price END AS unit_price,
    CASE WHEN customer_order.sales_request_id IS NOT NULL THEN unit.supplier_currency_code ELSE line.currency_code END AS currency_code
FROM crm.customer_order_line line JOIN crm.customer_order ON customer_order.id=line.customer_order_id
LEFT JOIN crm.cargo_sales_unit unit ON unit.customer_order_line_id=line.id;
CREATE OR REPLACE FUNCTION crm.customer_order_lifecycle(order_id uuid) RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN customer_order.status_code = 'CANCELLED' THEN 'COMPLETED'
        WHEN customer_order.status_code <> 'FULFILLED' THEN 'ACTIVE'
        WHEN EXISTS (
            SELECT 1
            FROM crm.customer_order_line line
            WHERE line.customer_order_id = customer_order.id
              AND line.status_code <> 'REMOVED'
              AND (customer_order.order_kind_code <> 'MINI' OR line.unit_price > 0)
              AND NOT EXISTS (SELECT 1 FROM crm.cargo_sales_unit unit WHERE unit.customer_order_line_id=line.id AND unit.supplier_amount=0)
              AND NOT EXISTS (
                  SELECT 1
                  FROM crm.settlement_supplier_entitlement entitlement
                  WHERE entitlement.customer_order_line_id = line.id
              )
        ) OR EXISTS (
            SELECT 1
            FROM crm.settlement_supplier_entitlement entitlement
            LEFT JOIN crm.settlement_supplier_statement_entitlement statement_entitlement
              ON statement_entitlement.entitlement_id = entitlement.id
            WHERE entitlement.customer_order_id = customer_order.id
              AND entitlement.amount > COALESCE(statement_entitlement.deduction_amount, 0) + COALESCE((
                  SELECT SUM(allocation.amount)
                  FROM crm.settlement_supplier_payout_allocation allocation
                  LEFT JOIN crm.settlement_supplier_payout_leg leg
                    ON leg.payout_operation_id = allocation.payout_operation_id
                  LEFT JOIN crm.settlement_supplier_payout_document_acknowledgement document_acknowledgement
                    ON document_acknowledgement.payout_document_id = leg.payout_document_id
                  LEFT JOIN crm.settlement_supplier_payout_acknowledgement legacy_acknowledgement
                    ON legacy_acknowledgement.payout_operation_id = allocation.payout_operation_id
                  WHERE allocation.entitlement_id = entitlement.id
                    AND (
                        document_acknowledgement.decision_code = 'RECEIVED'
                        OR (
                            document_acknowledgement.payout_document_id IS NULL
                            AND legacy_acknowledgement.decision_code = 'RECEIVED'
                            AND NOT EXISTS (
                                SELECT 1
                                FROM crm.settlement_supplier_payout_leg other_leg
                                WHERE other_leg.payout_document_id = leg.payout_document_id
                                  AND other_leg.id <> leg.id
                            )
                        )
                    )
              ), 0)
        ) THEN 'SETTLEMENT_PENDING'
        ELSE 'COMPLETED'
    END
    FROM crm.customer_order
    WHERE customer_order.id = order_id
$$;
