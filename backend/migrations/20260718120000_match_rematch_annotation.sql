-- ADR 0012 / #477: rematch after REJECTED or CANCELLED reopens the same
-- pair+group row. Annotation columns let the Match tab show prior history
-- ("rejected before" / "cancelled before") without losing chat continuity.

ALTER TABLE matches
  ADD COLUMN IF NOT EXISTS rematch_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE matches
  ADD COLUMN IF NOT EXISTS last_terminal_status TEXT;

ALTER TABLE matches
  ADD COLUMN IF NOT EXISTS last_terminal_at TIMESTAMPTZ;

-- Drop then re-add so re-running is idempotent when the check already exists.
ALTER TABLE matches
  DROP CONSTRAINT IF EXISTS matches_last_terminal_status_check;

ALTER TABLE matches
  ADD CONSTRAINT matches_last_terminal_status_check
  CHECK (
    last_terminal_status IS NULL
    OR last_terminal_status IN ('REJECTED', 'CANCELLED')
  );
