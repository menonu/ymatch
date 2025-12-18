DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'inventory_user_id_merch_id_key') THEN
        ALTER TABLE inventory DROP CONSTRAINT inventory_user_id_merch_id_key;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'inventory_user_id_merch_id_status_key') THEN
        ALTER TABLE inventory ADD CONSTRAINT inventory_user_id_merch_id_status_key UNIQUE (user_id, merch_id, status);
    END IF;
END $$;
