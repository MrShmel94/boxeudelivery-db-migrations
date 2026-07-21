CREATE TABLE crm.task_viewed_receipt
(
    task_id    UUID        NOT NULL,
    account_id UUID        NOT NULL,
    viewed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (task_id, account_id),

    CONSTRAINT fk_task_viewed_receipt_task
        FOREIGN KEY (task_id) REFERENCES crm.task (id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_viewed_receipt_account
        FOREIGN KEY (account_id) REFERENCES crm.account (id) ON DELETE RESTRICT
);

CREATE INDEX ix_task_viewed_receipt_account_task
    ON crm.task_viewed_receipt (account_id, task_id);

INSERT INTO crm.task_viewed_receipt (task_id, account_id, viewed_at)
SELECT DISTINCT target.id, member.account_id, NOW()
FROM crm.task target
JOIN crm.task participant_task
  ON participant_task.conversation_id = target.conversation_id
JOIN crm.task_participant participant
  ON participant.task_id = participant_task.id
JOIN crm.project_member member
  ON member.id = participant.project_member_id
JOIN crm.account account
  ON account.id = member.account_id
WHERE account.status = 'ACTIVE'
  AND (
      participant_task.id = target.id
      OR participant_task.parent_task_id IS NULL
  )
ON CONFLICT (task_id, account_id) DO NOTHING;

INSERT INTO crm.task_viewed_receipt (task_id, account_id, viewed_at)
SELECT task.id, administrator.account_id, NOW()
FROM crm.task task
CROSS JOIN (
    SELECT DISTINCT role.account_id
    FROM crm.account_global_role role
    JOIN crm.account account ON account.id = role.account_id
    WHERE role.role_scope = 'GLOBAL'
      AND role.role_code IN ('OWNER', 'CRM_ADMIN')
      AND account.status = 'ACTIVE'
) administrator
ON CONFLICT (task_id, account_id) DO NOTHING;

COMMENT ON TABLE crm.task_viewed_receipt IS
    'First durable authorized task-card view per account. Absence means the task is new for that account; this is read state, not task audit.';
