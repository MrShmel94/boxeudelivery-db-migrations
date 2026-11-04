LOCK TABLE crm.supplier_goods_entry IN ACCESS EXCLUSIVE MODE;

DROP TRIGGER supplier_goods_article_number ON crm.supplier_goods_entry;

ALTER TABLE crm.supplier_goods_article_number
    ALTER COLUMN article_number TYPE VARCHAR(17),
    DROP CONSTRAINT supplier_goods_article_number_format,
    ADD CONSTRAINT supplier_goods_article_number_format
        CHECK (article_number ~ '^[A-Z][A-Z0-9]{1,7}-([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{7}|[1-9][0-9]{5}|[1-9][0-9]{7})$'),
    ADD COLUMN replacement_article_number VARCHAR(17),
    ADD CONSTRAINT fk_supplier_goods_article_replacement
        FOREIGN KEY (replacement_article_number)
        REFERENCES crm.supplier_goods_article_number(article_number) ON DELETE RESTRICT,
    ADD CONSTRAINT uq_supplier_goods_article_replacement UNIQUE (replacement_article_number);

ALTER TABLE crm.supplier_goods_entry
    ALTER COLUMN article_number TYPE VARCHAR(17);

CREATE TABLE crm.supplier_goods_article_namespace (
    prefix VARCHAR(8) PRIMARY KEY,
    digits SMALLINT NOT NULL DEFAULT 6,
    CONSTRAINT supplier_goods_article_namespace_prefix
        CHECK (prefix ~ '^[A-Z][A-Z0-9]{1,7}$'),
    CONSTRAINT supplier_goods_article_namespace_digits CHECK (digits IN (6, 8))
);

CREATE OR REPLACE FUNCTION crm.issue_supplier_goods_article_number(prefix TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    digit_count INTEGER;
    minimum_value BIGINT;
    maximum_value BIGINT;
    available_value BIGINT;
    candidate TEXT;
    issued TEXT;
BEGIN
    IF prefix IS NULL OR prefix !~ '^[A-Z][A-Z0-9]{1,7}$' THEN
        RAISE EXCEPTION 'A valid project prefix is required' USING ERRCODE = '23514';
    END IF;

    INSERT INTO crm.supplier_goods_article_namespace AS namespace (prefix)
        VALUES (prefix) ON CONFLICT ON CONSTRAINT supplier_goods_article_namespace_pkey DO NOTHING;
    SELECT namespace.digits INTO STRICT digit_count
        FROM crm.supplier_goods_article_namespace namespace
        WHERE namespace.prefix = issue_supplier_goods_article_number.prefix
        FOR UPDATE;

    LOOP
        minimum_value := power(10::NUMERIC, digit_count - 1)::BIGINT;
        maximum_value := power(10::NUMERIC, digit_count)::BIGINT - 1;

        FOR attempt IN 1..32 LOOP
            candidate := prefix || '-' || (minimum_value
                + floor(random() * (maximum_value - minimum_value + 1))::BIGINT)::TEXT;
            INSERT INTO crm.supplier_goods_article_number (article_number) VALUES (candidate)
                ON CONFLICT DO NOTHING RETURNING article_number INTO issued;
            IF issued IS NOT NULL THEN
                RETURN issued;
            END IF;
        END LOOP;

        WITH occupied AS (
            SELECT minimum_value - 1 AS value
            UNION ALL
            SELECT right(number.article_number, digit_count)::BIGINT
            FROM crm.supplier_goods_article_number number
            WHERE number.article_number ~ ('^' || prefix || '-[1-9][0-9]{' || (digit_count - 1) || '}$')
        ), gaps AS (
            SELECT value + 1 AS candidate_value,
                   lead(value, 1, maximum_value + 1) OVER (ORDER BY value) AS next_value
            FROM occupied
        )
        SELECT candidate_value INTO available_value FROM gaps
            WHERE candidate_value < next_value AND candidate_value <= maximum_value
            ORDER BY candidate_value LIMIT 1;

        IF available_value IS NOT NULL THEN
            candidate := prefix || '-' || available_value::TEXT;
            INSERT INTO crm.supplier_goods_article_number (article_number) VALUES (candidate);
            RETURN candidate;
        END IF;

        IF digit_count = 8 THEN
            RAISE EXCEPTION 'No goods article numbers remain for this project prefix' USING ERRCODE = '54000';
        END IF;

        digit_count := 8;
        UPDATE crm.supplier_goods_article_namespace namespace SET digits = digit_count
            WHERE namespace.prefix = issue_supplier_goods_article_number.prefix;
    END LOOP;
END;
$$;

DO $$
DECLARE
    goods RECORD;
    replacement TEXT;
BEGIN
    FOR goods IN
        SELECT entry.id, entry.article_number, project.task_prefix
        FROM crm.supplier_goods_entry entry
        JOIN crm.project project ON project.id = entry.project_id
        ORDER BY project.task_prefix, entry.id
    LOOP
        replacement := crm.issue_supplier_goods_article_number(goods.task_prefix);
        UPDATE crm.supplier_goods_article_number SET replacement_article_number = replacement
            WHERE article_number = goods.article_number;
        UPDATE crm.supplier_goods_entry SET article_number = replacement WHERE id = goods.id;
    END LOOP;
END;
$$;

CREATE TRIGGER supplier_goods_article_number
BEFORE INSERT OR UPDATE OF article_number ON crm.supplier_goods_entry
FOR EACH ROW EXECUTE FUNCTION crm.assign_supplier_goods_article_number();

ALTER TABLE crm.supplier_goods_entry
    ADD CONSTRAINT supplier_goods_entry_article_number_format
        CHECK (article_number ~ '^[A-Z][A-Z0-9]{1,7}-([1-9][0-9]{5}|[1-9][0-9]{7})$');

INSERT INTO crm.website_catalog_revision (project_id, transaction_id)
    SELECT DISTINCT project_id, txid_current() FROM crm.supplier_goods_entry
    ON CONFLICT (project_id, transaction_id) DO NOTHING;

COMMENT ON COLUMN crm.supplier_goods_entry.article_number IS
    'Immutable goods article using the project task prefix at issue time and six random digits. Eight digits are used only after the six-digit namespace is exhausted. Shared by variants. Independent of supplier SKU, manufacturer article and physical labels.';
