-- ADR 0008 / #423: add CANCELLED terminal match status.
-- System-driven only (item deleted); not reachable via user change_status.
-- Extends the domain from 20250405000000_trade_lifecycle.sql.

ALTER TABLE matches DROP CONSTRAINT IF EXISTS matches_status_check;
ALTER TABLE matches ADD CONSTRAINT matches_status_check
  CHECK (status IN (
    'PENDING', 'OFFERED', 'ACCEPTED', 'COMPLETED', 'REJECTED', 'CANCELLED'
  ));
