-- Every account is a guest account identified by its uuid; password signup
-- and login no longer exist.
--
-- Fill any missing uuid first so the NOT NULL constraint cannot fail at
-- startup. Such accounts become unreachable (the generated key is never
-- issued); none are expected in deployed environments.
UPDATE users SET uuid = gen_random_uuid()::text WHERE uuid IS NULL;
ALTER TABLE users ALTER COLUMN uuid SET NOT NULL;

ALTER TABLE users DROP COLUMN password_hash;
