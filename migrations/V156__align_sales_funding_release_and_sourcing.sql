ALTER TABLE crm.sales_request
    ADD COLUMN sourcing_required BOOLEAN;

ALTER TABLE crm.sales_request_audit DROP CONSTRAINT sales_request_audit_event_type_check;
ALTER TABLE crm.sales_request_audit ADD CONSTRAINT sales_request_audit_event_type_check
    CHECK (event_type IN ('CREATED','REVIEW_STARTED','MANAGER_CHANGED','TERMS_AGREED','CANCELLED',
        'PAYMENT_RECORDED','PAYMENT_ALLOCATED','PAYMENT_REFUNDED','PREPAYMENT_CONFIRMED','STOCK_RESERVED','STOCK_RELEASED',
        'SOURCING_ASSIGNED','SOURCING_CHANGED','ORDERS_CREATED'));

ALTER TABLE crm.settlement_sales_order_funding
    ADD COLUMN released_by_subject VARCHAR(255),
    DROP CONSTRAINT uq_settlement_sales_funding_currency,
    DROP CONSTRAINT settlement_sales_order_funding_check,
    ADD CONSTRAINT settlement_sales_order_funding_check
        CHECK ((released_at IS NULL AND release_reason IS NULL AND released_by_subject IS NULL) OR (released_at IS NOT NULL AND length(btrim(release_reason)) > 0 AND length(btrim(released_by_subject)) > 0));

CREATE OR REPLACE VIEW crm.sales_fulfillment_progress AS
SELECT request.id AS sales_request_id,
    (SELECT COALESCE(SUM(line.quantity),0) FROM crm.sales_request_line line WHERE line.sales_request_id=request.id) AS requested_quantity,
    COUNT(unit.id) FILTER (WHERE unit.released_at IS NULL AND (unit.customer_order_line_id IS NULL OR order_line.status_code<>'REMOVED')) AS committed_quantity,
    COUNT(unit.id) FILTER (WHERE unit.released_at IS NULL AND order_line.status_code='DELIVERED') AS delivered_quantity,
    COUNT(unit.id) FILTER (WHERE unit.released_at IS NULL AND unit.customer_order_line_id IS NOT NULL AND order_line.status_code NOT IN ('REMOVED','DELIVERED')) AS ordered_quantity,
    COUNT(unit.id) FILTER (WHERE unit.released_at IS NULL AND unit.customer_order_line_id IS NULL
        AND item.status_code='AVAILABLE' AND item.accepted_at IS NOT NULL AND item.current_warehouse_id IS NOT NULL
        AND item.sales_request_line_id=unit.sales_request_line_id
        AND NOT EXISTS (SELECT 1 FROM crm.sales_sourcing_assignment assignment WHERE assignment.id=unit.sourcing_assignment_id AND assignment.warehouse_id<>item.current_warehouse_id)
        AND NOT EXISTS (SELECT 1 FROM crm.inbound_delivery delivery WHERE delivery.id=item.inbound_delivery_id AND delivery.status_code NOT IN ('COMPLETED','CANCELLED'))
        AND NOT EXISTS (SELECT 1 FROM crm.mini_supplier_intake_item link JOIN crm.mini_supplier_intake intake ON intake.id=link.intake_id
            WHERE link.cargo_item_id=item.id AND intake.completed_at IS NULL)) AS ready_quantity
FROM crm.sales_request request
LEFT JOIN crm.cargo_sales_unit unit ON unit.sales_request_id=request.id
LEFT JOIN crm.cargo_item item ON item.id=unit.cargo_item_id
LEFT JOIN crm.customer_order_line order_line ON order_line.id=unit.customer_order_line_id
GROUP BY request.id;

CREATE OR REPLACE FUNCTION crm.sales_request_stage(request_id UUID) RETURNS TEXT LANGUAGE sql STABLE AS $$
SELECT CASE WHEN request.status_code<>'PAID' THEN request.status_code
    WHEN progress.delivered_quantity=progress.requested_quantity THEN 'COMPLETED'
    WHEN progress.ready_quantity+progress.ordered_quantity+progress.delivered_quantity=progress.requested_quantity
        THEN CASE WHEN progress.ready_quantity=0 THEN 'HANDING_OVER' ELSE 'READY_FOR_HANDOVER' END
    WHEN progress.committed_quantity>progress.ready_quantity+progress.ordered_quantity+progress.delivered_quantity OR EXISTS (SELECT 1 FROM crm.sales_sourcing_assignment assignment
        WHERE assignment.sales_request_id=request.id AND assignment.status_code IN ('ACCEPTED','PURCHASING','SHIPPED','RECEIVED')) THEN 'SOURCING'
    ELSE 'ORGANIZING_SOURCING' END
FROM crm.sales_request request JOIN crm.sales_fulfillment_progress progress ON progress.sales_request_id=request.id
WHERE request.id=request_id
$$;

CREATE INDEX ix_settlement_sales_funding_order ON crm.settlement_sales_order_funding(customer_order_id,currency_code) WHERE released_at IS NULL;

CREATE VIEW crm.sales_prepayment_commitment AS
SELECT line.project_id,line.sales_request_id,line.currency_code,
    SUM(line.required_prepayment-COALESCE((
        SELECT SUM(unit.prepayment_amount) FROM crm.cargo_sales_unit unit
        JOIN crm.customer_order_line order_line ON order_line.id=unit.customer_order_line_id
        WHERE unit.sales_request_line_id=line.id AND unit.released_at IS NULL AND order_line.status_code<>'REMOVED'
    ),0)) AS reserved_amount
FROM crm.sales_request_line line JOIN crm.sales_request request ON request.id=line.sales_request_id
WHERE request.status_code='PAID'
GROUP BY line.project_id,line.sales_request_id,line.currency_code;
