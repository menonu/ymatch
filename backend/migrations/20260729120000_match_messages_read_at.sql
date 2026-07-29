-- #535: per-match chat read watermarks for each participant.
-- Unread = peer TEXT/LOCATION messages with created_at after the caller's
-- watermark (NULL means never read → all peer messages count as unread).
-- Opening a match's message list sets that participant's watermark to NOW().

ALTER TABLE matches
  ADD COLUMN IF NOT EXISTS user1_messages_read_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS user2_messages_read_at TIMESTAMPTZ;
