# Agent action ledger (PRD §8, AI-GOVERNANCE.md §3) — one shared table, not
# per-env, matching the single agents-inference role's WriteLedgerOnly ARN in
# iam.tf. Append-only audit trail: agents only ever PutItem here, never
# update/delete (enforced by IAM — the role has no UpdateItem/DeleteItem).
resource "aws_dynamodb_table" "agent_ledger" {
  name         = "hello-world-svc-agent-ledger"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "agent"
  range_key    = "ts"

  attribute {
    name = "agent"
    type = "S"
  }
  attribute {
    name = "ts"
    type = "S"
  }

  tags = { Project = "paved-road" }
}

output "agent_ledger_table" {
  value       = aws_dynamodb_table.agent_ledger.name
  description = "Paste into paved-road/.github/workflows/agents.yml as the ledger table env var."
}
