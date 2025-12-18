-- Add UUID column for Guest Login
ALTER TABLE users ADD COLUMN IF NOT EXISTS uuid TEXT UNIQUE;

-- Make password_hash nullable for Guest Users
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;
