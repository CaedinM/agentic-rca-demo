-- sql/000_agent_logging_tables.sql
-- Requires pgcrypto for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
  CREATE TYPE agent_run_status AS ENUM ('running', 'needs_user', 'completed', 'failed');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE agent_finding_type AS ENUM ('headline', 'contributor', 'hypothesis', 'evidence_table', 'note');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS agent_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  status agent_run_status NOT NULL DEFAULT 'running',

  -- User request / app context
  inputs_json JSONB NOT NULL,

  -- Final outputs
  result_json JSONB,
  memo_md TEXT,

  confidence DOUBLE PRECISION CHECK (confidence >= 0 AND confidence <= 1),

  -- Observability rollups
  duration_ms INT CHECK (duration_ms IS NULL OR duration_ms >= 0),
  total_tokens_in INT CHECK (total_tokens_in IS NULL OR total_tokens_in >= 0),
  total_tokens_out INT CHECK (total_tokens_out IS NULL OR total_tokens_out >= 0),

  error TEXT
);

CREATE INDEX IF NOT EXISTS idx_agent_runs_created_at ON agent_runs(created_at);
CREATE INDEX IF NOT EXISTS idx_agent_runs_status ON agent_runs(status);

CREATE TABLE IF NOT EXISTS agent_tool_calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES agent_runs(id) ON DELETE CASCADE,

  ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  tool_name TEXT NOT NULL,

  -- request/response payloads for trace view
  input_json JSONB,
  output_json JSONB,

  success BOOLEAN NOT NULL DEFAULT TRUE,
  error TEXT,

  duration_ms INT CHECK (duration_ms IS NULL OR duration_ms >= 0),
  tokens_in INT CHECK (tokens_in IS NULL OR tokens_in >= 0),
  tokens_out INT CHECK (tokens_out IS NULL OR tokens_out >= 0)
);

CREATE INDEX IF NOT EXISTS idx_agent_tool_calls_run_id ON agent_tool_calls(run_id);
CREATE INDEX IF NOT EXISTS idx_agent_tool_calls_ts ON agent_tool_calls(ts);
CREATE INDEX IF NOT EXISTS idx_agent_tool_calls_tool_name ON agent_tool_calls(tool_name);

CREATE TABLE IF NOT EXISTS agent_findings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES agent_runs(id) ON DELETE CASCADE,

  finding_type agent_finding_type NOT NULL,
  title TEXT NOT NULL,
  data_json JSONB NOT NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agent_findings_run_id ON agent_findings(run_id);
CREATE INDEX IF NOT EXISTS idx_agent_findings_type ON agent_findings(finding_type);
CREATE INDEX IF NOT EXISTS idx_agent_findings_created_at ON agent_findings(created_at);
