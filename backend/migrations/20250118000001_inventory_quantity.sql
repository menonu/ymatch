-- Add quantity column to inventory table
ALTER TABLE inventory ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1;
