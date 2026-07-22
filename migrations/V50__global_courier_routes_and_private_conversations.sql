-- Country identities remain uppercase catalogue keys, but operational catalogues may use
-- two to five letters instead of being limited to ISO alpha-2.
ALTER TABLE crm.warehouse DROP CONSTRAINT fk_warehouse_country;
ALTER TABLE crm.pickup_point DROP CONSTRAINT fk_pickup_point_country;
ALTER TABLE crm.outbound_delivery DROP CONSTRAINT fk_outbound_delivery_country;
ALTER TABLE crm.account_courier_route
    DROP CONSTRAINT fk_account_courier_route_origin_country,
    DROP CONSTRAINT fk_account_courier_route_destination_country;
ALTER TABLE crm.project_supplier_country DROP CONSTRAINT fk_project_supplier_country_country;
ALTER TABLE crm.project_country DROP CONSTRAINT fk_project_country_country;
ALTER TABLE crm.task_category DROP CONSTRAINT fk_task_category_country;
ALTER TABLE crm.task_subcategory DROP CONSTRAINT fk_task_subcategory_category_country;
ALTER TABLE crm.task_system_classification_default DROP CONSTRAINT fk_task_system_default_subcategory_country;

ALTER TABLE crm.country DROP CONSTRAINT ck_country_code;
ALTER TABLE crm.warehouse DROP CONSTRAINT ck_warehouse_country_code;
ALTER TABLE crm.pickup_point DROP CONSTRAINT ck_pickup_point_country_code;
ALTER TABLE crm.outbound_delivery DROP CONSTRAINT ck_outbound_delivery_country;
ALTER TABLE crm.project_supplier_country DROP CONSTRAINT ck_project_supplier_country_code;
ALTER TABLE crm.country_audit_event DROP CONSTRAINT ck_country_audit_event_country_code;

ALTER TABLE crm.country ALTER COLUMN code TYPE VARCHAR(5);
ALTER TABLE crm.country_audit_event ALTER COLUMN country_code TYPE VARCHAR(5);
ALTER TABLE crm.warehouse ALTER COLUMN country_code TYPE VARCHAR(5);
ALTER TABLE crm.pickup_point ALTER COLUMN country_code TYPE VARCHAR(5);
ALTER TABLE crm.outbound_delivery ALTER COLUMN country_code TYPE VARCHAR(5);
ALTER TABLE crm.account_courier_route
    ALTER COLUMN origin_country_code TYPE VARCHAR(5),
    ALTER COLUMN destination_country_code TYPE VARCHAR(5);
ALTER TABLE crm.project_supplier_country ALTER COLUMN country_code TYPE VARCHAR(5);
ALTER TABLE crm.project_country ALTER COLUMN country_code TYPE VARCHAR(5);
ALTER TABLE crm.task_category ALTER COLUMN country_code TYPE VARCHAR(5);
ALTER TABLE crm.task_subcategory ALTER COLUMN country_code TYPE VARCHAR(5);
ALTER TABLE crm.task_system_classification_default ALTER COLUMN country_code TYPE VARCHAR(5);

ALTER TABLE crm.country
    ADD CONSTRAINT ck_country_code CHECK (code ~ '^[A-Z]{2,5}$');
ALTER TABLE crm.warehouse
    ADD CONSTRAINT ck_warehouse_country_code
        CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2,5}$');
ALTER TABLE crm.pickup_point
    ADD CONSTRAINT ck_pickup_point_country_code CHECK (country_code ~ '^[A-Z]{2,5}$');
ALTER TABLE crm.outbound_delivery
    ADD CONSTRAINT ck_outbound_delivery_country
        CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2,5}$');
ALTER TABLE crm.project_supplier_country
    ADD CONSTRAINT ck_project_supplier_country_code CHECK (country_code ~ '^[A-Z]{2,5}$');
ALTER TABLE crm.country_audit_event
    ADD CONSTRAINT ck_country_audit_event_country_code CHECK (country_code ~ '^[A-Z]{2,5}$');

ALTER TABLE crm.warehouse
    ADD CONSTRAINT fk_warehouse_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT;
ALTER TABLE crm.pickup_point
    ADD CONSTRAINT fk_pickup_point_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT;
ALTER TABLE crm.outbound_delivery
    ADD CONSTRAINT fk_outbound_delivery_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT;
ALTER TABLE crm.account_courier_route
    ADD CONSTRAINT fk_account_courier_route_origin_country
        FOREIGN KEY (origin_country_code) REFERENCES crm.country (code) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_account_courier_route_destination_country
        FOREIGN KEY (destination_country_code) REFERENCES crm.country (code) ON DELETE RESTRICT;
ALTER TABLE crm.project_supplier_country
    ADD CONSTRAINT fk_project_supplier_country_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT;
ALTER TABLE crm.project_country
    ADD CONSTRAINT fk_project_country_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT;
ALTER TABLE crm.task_category
    ADD CONSTRAINT fk_task_category_country
        FOREIGN KEY (country_code) REFERENCES crm.country (code) ON DELETE RESTRICT;
ALTER TABLE crm.task_subcategory
    ADD CONSTRAINT fk_task_subcategory_category_country
        FOREIGN KEY (category_id, country_code)
            REFERENCES crm.task_category (id, country_code) ON DELETE RESTRICT;
ALTER TABLE crm.task_system_classification_default
    ADD CONSTRAINT fk_task_system_default_subcategory_country
        FOREIGN KEY (subcategory_id, country_code)
            REFERENCES crm.task_subcategory (id, country_code) ON DELETE RESTRICT;

COMMENT ON TABLE crm.country IS
    'Administrator-managed country catalogue identified by immutable uppercase codes of two to five letters.';
COMMENT ON TABLE crm.account_courier_route IS
    'Directed country pairs that authoritatively filter global courier job eligibility.';

-- COURIER is a global account identity and authorization role. Existing project-scoped
-- courier access is removed, including direct task and supplier-group visibility.
CREATE TEMPORARY TABLE v50_changed_courier_account
(
    account_id UUID PRIMARY KEY
) ON COMMIT DROP;

INSERT INTO v50_changed_courier_account (account_id)
SELECT account.id
FROM crm.account account
WHERE account.category_code = 'COURIER'
ON CONFLICT DO NOTHING;

WITH inserted AS (
    INSERT INTO crm.account_global_role (
        account_id,
        role_scope,
        role_code,
        assigned_by_subject,
        assigned_at
    )
    SELECT account.id,
           'GLOBAL',
           'COURIER',
           'migration:v50',
           CURRENT_TIMESTAMP
    FROM crm.account account
    WHERE account.category_code = 'COURIER'
    ON CONFLICT (account_id, role_code) DO NOTHING
    RETURNING account_id
)
INSERT INTO v50_changed_courier_account (account_id)
SELECT account_id FROM inserted
ON CONFLICT DO NOTHING;

WITH removed AS (
    DELETE FROM crm.account_global_role role
    USING crm.account account
    WHERE role.account_id = account.id
      AND role.role_code = 'COURIER'
      AND account.category_code IS DISTINCT FROM 'COURIER'
    RETURNING role.account_id
)
INSERT INTO v50_changed_courier_account (account_id)
SELECT account_id FROM removed
ON CONFLICT DO NOTHING;

INSERT INTO crm.project_audit_event (
    id,
    project_id,
    event_type,
    actor_subject,
    details,
    occurred_at
)
SELECT MD5('v50-global-courier-project-removal:' || member.project_id::TEXT || ':' || member.account_id::TEXT)::UUID,
       member.project_id,
       'MEMBER_REMOVED',
       'migration:v50',
       JSONB_BUILD_OBJECT(
           'accountId', member.account_id,
           'reason', 'COURIER_GLOBAL_ONLY'
       ),
       CURRENT_TIMESTAMP
FROM crm.project_member member
JOIN crm.account account ON account.id = member.account_id
WHERE account.category_code = 'COURIER'
ON CONFLICT (id) DO NOTHING;

DELETE FROM crm.task_participant participant
USING crm.project_member member, crm.account account
WHERE participant.project_member_id = member.id
  AND member.account_id = account.id
  AND account.category_code = 'COURIER';

DELETE FROM crm.project_supplier_member supplier_member
USING crm.account account
WHERE supplier_member.account_id = account.id
  AND account.category_code = 'COURIER';

DELETE FROM crm.project_member_role
WHERE role_code = 'COURIER';

DELETE FROM crm.project_member_role role
USING crm.project_member member, crm.account account
WHERE role.project_member_id = member.id
  AND member.account_id = account.id
  AND account.category_code = 'COURIER';

DELETE FROM crm.project_member member
USING crm.account account
WHERE member.account_id = account.id
  AND account.category_code = 'COURIER';

DELETE FROM crm.access_role
WHERE scope_type = 'PROJECT'
  AND code = 'COURIER';

ALTER TABLE crm.access_role
    DROP CONSTRAINT ck_access_role_project_scope,
    ADD CONSTRAINT ck_access_role_project_scope
        CHECK (scope_type <> 'PROJECT' OR code NOT IN ('OWNER', 'CRM_ADMIN', 'COURIER'));

UPDATE crm.password_credential credential
SET security_version = security_version + 1,
    updated_at = CURRENT_TIMESTAMP
WHERE credential.account_id IN (
    SELECT changed.account_id FROM v50_changed_courier_account changed
);

-- A supplier/employee conversation and an employee/courier conversation are distinct
-- security boundaries. Historical main-chat messages are not copied into the new channel.
ALTER TABLE crm.conversation
    DROP CONSTRAINT ck_conversation_kind,
    ADD CONSTRAINT ck_conversation_kind
        CHECK (kind_code IN ('TASK', 'INBOUND_DELIVERY', 'COURIER_TRIP', 'COURIER_INTERNAL'));

ALTER TABLE crm.inbound_delivery
    ADD COLUMN courier_conversation_id UUID;

INSERT INTO crm.conversation (
    id,
    project_id,
    last_message_sequence,
    created_at,
    version,
    kind_code
)
SELECT MD5('courier-internal-delivery-conversation:' || delivery.id::TEXT)::UUID,
       delivery.project_id,
       0,
       delivery.created_at,
       0,
       'COURIER_INTERNAL'
FROM crm.inbound_delivery delivery
WHERE delivery.transport_mode = 'COURIER_VIA_PICKUP_POINT';

UPDATE crm.inbound_delivery delivery
SET courier_conversation_id = MD5('courier-internal-delivery-conversation:' || delivery.id::TEXT)::UUID
WHERE delivery.transport_mode = 'COURIER_VIA_PICKUP_POINT';

ALTER TABLE crm.inbound_delivery
    ADD CONSTRAINT uq_inbound_delivery_courier_conversation UNIQUE (courier_conversation_id),
    ADD CONSTRAINT fk_inbound_delivery_courier_conversation
        FOREIGN KEY (courier_conversation_id, project_id)
            REFERENCES crm.conversation (id, project_id) ON DELETE RESTRICT,
    ADD CONSTRAINT ck_inbound_delivery_courier_conversation
        CHECK (
            (transport_mode = 'DIRECT_TO_WAREHOUSE' AND courier_conversation_id IS NULL)
            OR
            (transport_mode = 'COURIER_VIA_PICKUP_POINT' AND courier_conversation_id IS NOT NULL)
        );

ALTER TABLE crm.courier_trip
    ADD COLUMN courier_conversation_id UUID;

INSERT INTO crm.conversation (
    id,
    project_id,
    last_message_sequence,
    created_at,
    version,
    kind_code
)
SELECT MD5('courier-internal-trip-conversation:' || trip.id::TEXT)::UUID,
       trip.project_id,
       0,
       trip.created_at,
       0,
       'COURIER_INTERNAL'
FROM crm.courier_trip trip;

UPDATE crm.courier_trip trip
SET courier_conversation_id = MD5('courier-internal-trip-conversation:' || trip.id::TEXT)::UUID;

ALTER TABLE crm.courier_trip
    ALTER COLUMN courier_conversation_id SET NOT NULL,
    ADD CONSTRAINT uq_courier_trip_courier_conversation UNIQUE (courier_conversation_id),
    ADD CONSTRAINT fk_courier_trip_courier_conversation
        FOREIGN KEY (courier_conversation_id, project_id)
            REFERENCES crm.conversation (id, project_id) ON DELETE RESTRICT;

INSERT INTO crm.conversation_participant (
    conversation_id,
    account_id,
    source_code,
    joined_at,
    revoked_at,
    created_at,
    updated_at
)
SELECT delivery.courier_conversation_id,
       participant.account_id,
       'COURIER',
       participant.joined_at,
       participant.revoked_at,
       participant.created_at,
       participant.updated_at
FROM crm.inbound_delivery delivery
JOIN crm.conversation_participant participant
  ON participant.conversation_id = delivery.conversation_id
 AND participant.source_code = 'COURIER'
WHERE delivery.courier_conversation_id IS NOT NULL
ON CONFLICT (conversation_id, account_id) DO NOTHING;

INSERT INTO crm.conversation_participant (
    conversation_id,
    account_id,
    source_code,
    joined_at,
    revoked_at,
    created_at,
    updated_at
)
SELECT trip.courier_conversation_id,
       participant.account_id,
       'COURIER',
       participant.joined_at,
       participant.revoked_at,
       participant.created_at,
       participant.updated_at
FROM crm.courier_trip trip
JOIN crm.conversation_participant participant
  ON participant.conversation_id = trip.conversation_id
 AND participant.source_code = 'COURIER'
ON CONFLICT (conversation_id, account_id) DO NOTHING;

DELETE FROM crm.chat_message_unread unread
USING crm.chat_message message, crm.conversation_participant participant
WHERE unread.message_id = message.id
  AND participant.conversation_id = message.conversation_id
  AND participant.account_id = unread.account_id
  AND participant.source_code = 'COURIER';

UPDATE crm.conversation_participant participant
SET revoked_at = COALESCE(participant.revoked_at, CURRENT_TIMESTAMP),
    updated_at = GREATEST(participant.updated_at, CURRENT_TIMESTAMP)
WHERE participant.source_code = 'COURIER'
  AND EXISTS (
      SELECT 1
      FROM crm.inbound_delivery delivery
      WHERE delivery.conversation_id = participant.conversation_id
      UNION ALL
      SELECT 1
      FROM crm.courier_trip trip
      WHERE trip.conversation_id = participant.conversation_id
  );

COMMENT ON COLUMN crm.inbound_delivery.courier_conversation_id IS
    'Separate employee-courier conversation; absent for direct-to-warehouse deliveries.';
COMMENT ON COLUMN crm.courier_trip.courier_conversation_id IS
    'Separate employee-courier conversation for the grouped custody unit.';
