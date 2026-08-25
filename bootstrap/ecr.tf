# Shared image repository — one repo, the same immutable digest promoted
# dev → prod (PRD §5.3). deploy-dev and deploy-prod both already scope ecr:*
# to this exact repo ARN in iam.tf, so the name must stay svc_name_prefix.
resource "aws_ecr_repository" "service" {
  name                 = local.svc_name_prefix
  image_tag_mutability = "IMMUTABLE" # §5.3: immutable tags, reference by digest

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = "paved-road" }
}

# Storage stays in budget: drop untagged layers a build superseded.
resource "aws_ecr_lifecycle_policy" "service" {
  repository = aws_ecr_repository.service.name
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
  value = aws_ecr_repository.service.repository_url
}
