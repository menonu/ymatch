-- Drop the sort_order column from merchandise.
--
-- The column was added in 20250118000005_merch_sort_order.sql to support
-- a manual-reorder UI in the Flutter app. That feature interfered with
-- the inventory steppers (#203), so the UI was removed and the backend
-- endpoint/handler/repository method were also deleted.
--
-- This migration finishes the cleanup by removing the now-unused column.
-- Sort order is now an entirely UI-side concern (alphabetical by name
-- within each group, then groups alphabetical — see
-- frontend/lib/screens/event_detail_screen.dart).
--
-- The merch list query (`backend/src/repositories/merch.rs::list_for_event`)
-- used to `ORDER BY m.sort_order ASC, m.id ASC`; it now uses only
-- `ORDER BY m.id ASC`. All existing rows have `sort_order = 0` (default)
-- so the column is functionally a no-op; dropping is safe.

ALTER TABLE merchandise DROP COLUMN sort_order;
