# One image repository per service — the same immutable digest promoted
# dev → prod within a service (PRD §5.3). deploy-dev and deploy-prod both
# already scope ecr:* to each service's exact repo ARN in iam.tf, so the
# name must stay each service's name (local.services key).
resource "aws_ecr_repository" "service" {
  for_each             = local.services
  name                 = each.key
  image_tag_mutability = "IMMUTABLE" # §5.3: immutable tags, reference by digest
  force_delete         = true        # decommissioning a service must not get stuck on "repository not empty" — found live

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = "paved-road" }
}

# Storage stays in budget: drop untagged layers a build superseded.
resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = local.services
  repository = aws_ecr_repository.service[each.key].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "expire untagged after 3 days"
      selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 3 }
      action       = { type = "expire" }
    }]
  })
}

output "ecr_repository_url" {
  value = { for k, v in aws_ecr_repository.service : k => v.repository_url }
}

# Converting the pre-existing singleton hello-world-svc resources to
# for_each changes their resource address — without these, tofu plans a
# destroy of the live repo/policy instead of a state move (verified live).
moved {
  from = aws_ecr_repository.service
  to   = aws_ecr_repository.service["hello-world-svc"]
}

moved {
  from = aws_ecr_lifecycle_policy.service
  to   = aws_ecr_lifecycle_policy.service["hello-world-svc"]
}
