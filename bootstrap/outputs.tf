output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.id
}

output "tfstate_lock_table" {
  value = aws_dynamodb_table.tfstate_lock.name
}

output "role_arns" {
  value = {
    plan_readonly    = aws_iam_role.plan_readonly.arn
    deploy_dev       = aws_iam_role.deploy_dev.arn
    deploy_prod      = aws_iam_role.deploy_prod.arn
    agents_inference = aws_iam_role.agents_inference.arn
  }
  description = "Paste into hello-world-svc's CI workflow (role-to-assume per job) and into AI-GOVERNANCE.md §1 once real."
}
