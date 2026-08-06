ALTER TABLE crm.supplier
    ADD COLUMN home_country_code VARCHAR(5);

ALTER TABLE crm.supplier
    ADD CONSTRAINT fk_supplier_home_country
        FOREIGN KEY (home_country_code)
            REFERENCES crm.country(code)
            ON DELETE RESTRICT;

CREATE INDEX ix_supplier_home_country
    ON crm.supplier(home_country_code, display_name, id);
