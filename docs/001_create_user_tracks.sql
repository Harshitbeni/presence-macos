-- Migration: Replace Supabase Presence with a database table + Realtime
-- Run this in Supabase Dashboard → SQL Editor → New query → Run
--
-- Each user gets ONE row. When they change songs, they UPDATE that row.
-- Other users subscribe to changes via Supabase Realtime (postgres_changes).

CREATE TABLE IF NOT EXISTS user_tracks (
  id               uuid PRIMARY KEY DEFAULT auth.uid(),
  display_name     text NOT NULL DEFAULT '',
  imessage_contact text NOT NULL DEFAULT '',
  title            text NOT NULL DEFAULT '—',
  artist           text NOT NULL DEFAULT '—',
  artwork_url      text NOT NULL DEFAULT '',
  track_id         text NOT NULL DEFAULT '',
  is_paused        boolean NOT NULL DEFAULT false,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  last_seen_at     timestamptz NOT NULL DEFAULT now()
);

-- Security: users can read everyone, but only write their own row
ALTER TABLE user_tracks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read all rows"
  ON user_tracks FOR SELECT
  USING (true);

CREATE POLICY "Users can insert their own row"
  ON user_tracks FOR INSERT
  WITH CHECK (id = auth.uid());

CREATE POLICY "Users can update their own row"
  ON user_tracks FOR UPDATE
  USING (id = auth.uid());

CREATE POLICY "Users can delete their own row"
  ON user_tracks FOR DELETE
  USING (id = auth.uid());

-- Enable Realtime so other clients get live INSERT/UPDATE/DELETE events
ALTER PUBLICATION supabase_realtime ADD TABLE user_tracks;
