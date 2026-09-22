-- A physical item can be picked again after a cancelled order has been returned
-- to warehouse stock. Pick rows are immutable history, while active order-line
-- uniqueness and the item/line locks still prevent concurrent active allocation.
SET LOCAL lock_timeout = '5s';

ALTER TABLE crm.customer_order_pick
    DROP CONSTRAINT uq_customer_order_pick_item;
