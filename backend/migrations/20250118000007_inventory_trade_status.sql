-- PostgreSQL requires dropping and recreating the CHECK constraint to alter it.
ALTER TABLE inventory DROP CONSTRAINT inventory_status_check;
ALTER TABLE inventory ADD CONSTRAINT inventory_status_check CHECK (status IN ('HAVE', 'WANT', 'TRADE'));