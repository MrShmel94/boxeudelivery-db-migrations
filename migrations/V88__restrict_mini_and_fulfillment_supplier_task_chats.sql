-- Supplier accounts operating in MINI or FULFILLMENT remain participants in
-- their business workflows, but they must not become members of the managed
-- task conversation. FULL customer-order supplier participation is unchanged.

CREATE TEMPORARY TABLE restricted_supplier_task_participant ON COMMIT DROP AS
SELECT participant.task_id,
       participant.project_member_id
FROM crm.task_participant participant
JOIN crm.task participant_task
  ON participant_task.id = participant.task_id
JOIN crm.task conversation_root
  ON conversation_root.conversation_id = participant_task.conversation_id
 AND conversation_root.parent_task_id IS NULL
JOIN crm.project_member member
  ON member.id = participant.project_member_id
 AND member.project_id = participant.project_id
LEFT JOIN crm.customer_order customer_order
  ON customer_order.id = conversation_root.customer_order_id
LEFT JOIN crm.fulfillment_shipment shipment
  ON shipment.id = conversation_root.fulfillment_shipment_id
LEFT JOIN crm.fulfillment_return fulfillment_return
  ON fulfillment_return.id = conversation_root.fulfillment_return_id
WHERE (
    customer_order.order_kind_code = 'MINI'
    AND (
        participant.source_code = 'CUSTOMER_ORDER_SUPPLIER'
        OR EXISTS (
            SELECT 1
            FROM crm.project_supplier_member supplier_member
            WHERE supplier_member.project_id = customer_order.project_id
              AND supplier_member.supplier_id = customer_order.supplier_id
              AND supplier_member.account_id = member.account_id
              AND supplier_member.status_code = 'ACTIVE'
        )
    )
) OR (
    shipment.id IS NOT NULL
    AND (
        participant.source_code = 'FULFILLMENT_SUPPLIER'
        OR EXISTS (
            SELECT 1
            FROM crm.project_supplier_member supplier_member
            WHERE supplier_member.project_id = shipment.project_id
              AND supplier_member.supplier_id = shipment.supplier_id
              AND supplier_member.account_id = member.account_id
              AND supplier_member.status_code = 'ACTIVE'
        )
    )
) OR (
    fulfillment_return.id IS NOT NULL
    AND (
        participant.source_code = 'FULFILLMENT_SUPPLIER'
        OR EXISTS (
            SELECT 1
            FROM crm.project_supplier_member supplier_member
            WHERE supplier_member.project_id = fulfillment_return.project_id
              AND supplier_member.supplier_id = fulfillment_return.supplier_id
              AND supplier_member.account_id = member.account_id
              AND supplier_member.status_code = 'ACTIVE'
        )
    )
);

DELETE FROM crm.task_assignee assignee
USING restricted_supplier_task_participant restricted
WHERE assignee.task_id = restricted.task_id
  AND assignee.project_member_id = restricted.project_member_id;

DELETE FROM crm.task_participant participant
USING restricted_supplier_task_participant restricted
WHERE participant.task_id = restricted.task_id
  AND participant.project_member_id = restricted.project_member_id;

COMMENT ON TABLE crm.task_participant IS
    'Exact task and conversation membership. MINI and FULFILLMENT supplier accounts are excluded; FULL supplier task participation remains supported.';
