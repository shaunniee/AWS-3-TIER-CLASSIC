-- Enable extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table
CREATE TABLE IF NOT EXISTS users (
  id         uuid PRIMARY KEY,
  email      text NOT NULL,
  name       text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Todos table
CREATE TABLE IF NOT EXISTS todos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id),
  title       text NOT NULL,
  description text,
  is_done     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  due_at      timestamptz
);
