-- #404: optional single image on merchandise group description.
ALTER TABLE merchandise_groups
    ADD COLUMN IF NOT EXISTS photo_url TEXT;
