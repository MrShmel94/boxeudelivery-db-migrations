ALTER TABLE crm.password_reset_token
    ALTER COLUMN token_hash TYPE VARCHAR(64);
