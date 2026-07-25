CREATE TABLE crm.supplier_goods_photo_draft_session
(
    id                       UUID        NOT NULL,
    project_id               UUID        NOT NULL,
    supplier_id              UUID        NOT NULL,
    created_by_account_id    UUID        NOT NULL,
    photo_limit              SMALLINT    NOT NULL,
    status_code              VARCHAR(16) NOT NULL,
    activated_at             TIMESTAMPTZ,
    completed_at             TIMESTAMPTZ,
    adopted_at               TIMESTAMPTZ,
    cancelled_at             TIMESTAMPTZ,
    supplier_goods_entry_id  UUID,
    expires_at               TIMESTAMPTZ NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                  BIGINT      NOT NULL DEFAULT 0,
    CONSTRAINT pk_supplier_goods_photo_draft_session
        PRIMARY KEY (id),
    CONSTRAINT fk_supplier_goods_photo_draft_session_supplier
        FOREIGN KEY (project_id, supplier_id)
            REFERENCES crm.project_supplier (project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_supplier_goods_photo_draft_session_creator
        FOREIGN KEY (created_by_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_supplier_goods_photo_draft_session_goods
        FOREIGN KEY (supplier_goods_entry_id, project_id, supplier_id)
            REFERENCES crm.supplier_goods_entry (id, project_id, supplier_id) ON DELETE RESTRICT,
    CONSTRAINT ck_supplier_goods_photo_draft_session_status
        CHECK (status_code IN ('WAITING', 'ACTIVE', 'COMPLETED', 'ADOPTED', 'CANCELLED')),
    CONSTRAINT ck_supplier_goods_photo_draft_session_lifecycle
        CHECK (
            (
                status_code = 'WAITING'
                AND activated_at IS NULL
                AND completed_at IS NULL
                AND adopted_at IS NULL
                AND cancelled_at IS NULL
                AND supplier_goods_entry_id IS NULL
            )
            OR (
                status_code = 'ACTIVE'
                AND activated_at IS NOT NULL
                AND completed_at IS NULL
                AND adopted_at IS NULL
                AND cancelled_at IS NULL
                AND supplier_goods_entry_id IS NULL
            )
            OR (
                status_code = 'COMPLETED'
                AND activated_at IS NOT NULL
                AND completed_at IS NOT NULL
                AND adopted_at IS NULL
                AND cancelled_at IS NULL
                AND supplier_goods_entry_id IS NULL
            )
            OR (
                status_code = 'ADOPTED'
                AND activated_at IS NOT NULL
                AND completed_at IS NOT NULL
                AND adopted_at IS NOT NULL
                AND cancelled_at IS NULL
                AND supplier_goods_entry_id IS NOT NULL
            )
            OR (
                status_code = 'CANCELLED'
                AND completed_at IS NULL
                AND adopted_at IS NULL
                AND cancelled_at IS NOT NULL
                AND supplier_goods_entry_id IS NULL
            )
        ),
    CONSTRAINT ck_supplier_goods_photo_draft_session_expiry
        CHECK (expires_at > created_at),
    CONSTRAINT ck_supplier_goods_photo_draft_session_photo_limit
        CHECK (photo_limit BETWEEN 1 AND 10),
    CONSTRAINT ck_supplier_goods_photo_draft_session_timestamps
        CHECK (
            updated_at >= created_at
            AND (activated_at IS NULL OR activated_at >= created_at)
            AND (completed_at IS NULL OR completed_at >= activated_at)
            AND (adopted_at IS NULL OR adopted_at >= completed_at)
            AND (cancelled_at IS NULL OR cancelled_at >= created_at)
        ),
    CONSTRAINT ck_supplier_goods_photo_draft_session_version
        CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_supplier_goods_photo_draft_session_open_creator_supplier
    ON crm.supplier_goods_photo_draft_session (
        project_id,
        supplier_id,
        created_by_account_id
    )
    WHERE status_code IN ('WAITING', 'ACTIVE');

CREATE INDEX ix_supplier_goods_photo_draft_session_creator_status_expiry
    ON crm.supplier_goods_photo_draft_session (
        created_by_account_id,
        status_code,
        expires_at,
        id
    );

CREATE TABLE crm.supplier_goods_photo_draft_file
(
    id                       UUID          NOT NULL,
    session_id               UUID          NOT NULL,
    uploader_account_id      UUID          NOT NULL,
    status_code              VARCHAR(16)   NOT NULL,
    position                 SMALLINT      NOT NULL,
    original_filename        VARCHAR(255)  NOT NULL,
    declared_content_type    VARCHAR(255)  NOT NULL,
    declared_size_bytes      BIGINT        NOT NULL,
    declared_checksum_sha256 VARCHAR(44)   NOT NULL,
    object_key               VARCHAR(1024) NOT NULL,
    upload_expires_at        TIMESTAMPTZ   NOT NULL,
    verified_at              TIMESTAMPTZ,
    adopted_photo_id         UUID,
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version                  BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_supplier_goods_photo_draft_file
        PRIMARY KEY (id),
    CONSTRAINT uq_supplier_goods_photo_draft_file_position
        UNIQUE (session_id, position),
    CONSTRAINT uq_supplier_goods_photo_draft_file_object_key
        UNIQUE (object_key),
    CONSTRAINT uq_supplier_goods_photo_draft_file_adopted_photo
        UNIQUE (adopted_photo_id),
    CONSTRAINT fk_supplier_goods_photo_draft_file_session
        FOREIGN KEY (session_id)
            REFERENCES crm.supplier_goods_photo_draft_session (id) ON DELETE RESTRICT,
    CONSTRAINT fk_supplier_goods_photo_draft_file_uploader
        FOREIGN KEY (uploader_account_id) REFERENCES crm.account (id) ON DELETE RESTRICT,
    CONSTRAINT fk_supplier_goods_photo_draft_file_adopted_photo
        FOREIGN KEY (adopted_photo_id) REFERENCES crm.cargo_item_photo (id) ON DELETE RESTRICT,
    CONSTRAINT ck_supplier_goods_photo_draft_file_status
        CHECK (status_code IN ('PENDING_UPLOAD', 'VERIFIED', 'ADOPTED')),
    CONSTRAINT ck_supplier_goods_photo_draft_file_lifecycle
        CHECK (
            (
                status_code = 'PENDING_UPLOAD'
                AND verified_at IS NULL
                AND adopted_photo_id IS NULL
            )
            OR (
                status_code = 'VERIFIED'
                AND verified_at IS NOT NULL
                AND adopted_photo_id IS NULL
            )
            OR (
                status_code = 'ADOPTED'
                AND verified_at IS NOT NULL
                AND adopted_photo_id IS NOT NULL
            )
        ),
    CONSTRAINT ck_supplier_goods_photo_draft_file_position
        CHECK (position BETWEEN 0 AND 9),
    CONSTRAINT ck_supplier_goods_photo_draft_file_filename_not_blank
        CHECK (BTRIM(original_filename) <> ''),
    CONSTRAINT ck_supplier_goods_photo_draft_file_content_type
        CHECK (declared_content_type IN ('image/jpeg', 'image/png')),
    CONSTRAINT ck_supplier_goods_photo_draft_file_size
        CHECK (declared_size_bytes BETWEEN 1 AND 15728640),
    CONSTRAINT ck_supplier_goods_photo_draft_file_checksum
        CHECK (LENGTH(declared_checksum_sha256) = 44),
    CONSTRAINT ck_supplier_goods_photo_draft_file_object_key_not_blank
        CHECK (BTRIM(object_key) <> ''),
    CONSTRAINT ck_supplier_goods_photo_draft_file_upload_expiry
        CHECK (upload_expires_at > created_at),
    CONSTRAINT ck_supplier_goods_photo_draft_file_verified_at
        CHECK (verified_at IS NULL OR verified_at >= created_at),
    CONSTRAINT ck_supplier_goods_photo_draft_file_version
        CHECK (version >= 0)
);

CREATE INDEX ix_supplier_goods_photo_draft_file_session_position
    ON crm.supplier_goods_photo_draft_file (session_id, position, id);

COMMENT ON TABLE crm.supplier_goods_photo_draft_session IS
    'Short-lived authenticated phone-camera draft whose verified photos are adopted atomically when supplier goods are created.';

COMMENT ON COLUMN crm.supplier_goods_photo_draft_session.id IS
    'Random routing identifier only. Possession never grants authentication, supplier access, or upload authority.';

COMMENT ON COLUMN crm.supplier_goods_photo_draft_file.object_key IS
    'Private temporary or verified storage key. It is never exposed as a durable public URL.';
