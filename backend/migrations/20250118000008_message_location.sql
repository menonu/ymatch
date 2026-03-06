-- Add location support to messages
ALTER TABLE messages ADD COLUMN message_type TEXT DEFAULT 'TEXT';
ALTER TABLE messages ADD COLUMN latitude DOUBLE PRECISION;
ALTER TABLE messages ADD COLUMN longitude DOUBLE PRECISION;
