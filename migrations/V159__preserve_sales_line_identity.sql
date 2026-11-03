CREATE OR REPLACE FUNCTION crm.guard_paid_sales_composition() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE request_id UUID;
BEGIN
    IF TG_OP='UPDATE' AND (OLD.id IS DISTINCT FROM NEW.id
        OR OLD.sales_request_id IS DISTINCT FROM NEW.sales_request_id
        OR OLD.project_id IS DISTINCT FROM NEW.project_id) THEN
        RAISE EXCEPTION 'Sales line identity cannot move between requests'
            USING ERRCODE='23514',CONSTRAINT='ck_sales_paid_composition';
    END IF;
    IF TG_OP='DELETE' THEN request_id=OLD.sales_request_id; ELSE request_id=NEW.sales_request_id; END IF;
    PERFORM 1 FROM crm.sales_request WHERE id=request_id FOR UPDATE;
    IF EXISTS (SELECT 1 FROM crm.sales_request request WHERE request.id=request_id AND request.status_code='PAID')
        OR EXISTS (SELECT 1 FROM crm.settlement_money_operation operation
        WHERE operation.sales_request_id=request_id AND operation.operation_type IN ('SALES_ADVANCE','SALES_REFUND')) THEN
        RAISE EXCEPTION 'Paid sales composition requires its dedicated revision workflow'
            USING ERRCODE='23514',CONSTRAINT='ck_sales_paid_composition';
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
