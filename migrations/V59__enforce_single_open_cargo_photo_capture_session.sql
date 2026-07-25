WITH ranked_open_sessions AS (
    SELECT session.id,
           ROW_NUMBER() OVER (
               PARTITION BY session.project_id,
                            session.cargo_item_id,
                            session.created_by_account_id
               ORDER BY session.created_at DESC, session.id DESC
           ) AS row_number
    FROM crm.cargo_photo_capture_session session
    WHERE session.status_code IN ('WAITING', 'ACTIVE')
)
UPDATE crm.cargo_photo_capture_session session
SET status_code = 'CANCELLED',
    cancelled_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP,
    version = session.version + 1
FROM ranked_open_sessions ranked
WHERE session.id = ranked.id
  AND ranked.row_number > 1;

CREATE UNIQUE INDEX uq_cargo_photo_capture_session_open_creator_item
    ON crm.cargo_photo_capture_session (
        project_id,
        cargo_item_id,
        created_by_account_id
    )
    WHERE status_code IN ('WAITING', 'ACTIVE');

COMMENT ON INDEX crm.uq_cargo_photo_capture_session_open_creator_item IS
    'A user may have only one open phone-camera handoff for an exact cargo item.';
