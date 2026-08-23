data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  # Everything the pipeline creates for the service is named with this
  # prefix + env, so IAM can scope by resource name instead of needing
  # separate AWS accounts per environment (DECISIONS.md §2: single account +
  # per-purpose IAM roles is sufficient isolation at this scale).
  svc_name_prefix = "hello-world-svc"
}

# ---------------------------------------------------------------------------
# Trust policies
# ---------------------------------------------------------------------------
# Every trust condition requires aud=sts.amazonaws.com AND a sub match. See
# bootstrap/README.md's fork-isolation note before editing the `pull_request`
# arms — sub alone does not distinguish a fork PR from a same-repo one.

data "aws_iam_policy_document" "trust_plan_readonly" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.gh_owner_repo}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "trust_deploy_dev" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # pull_request → preview deploys; ref:refs/heads/main → dev deploy on merge.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.gh_owner_repo}:pull_request",
        "repo:${local.gh_owner_repo}:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "trust_deploy_prod" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # environment:prod — unassumable until the GitHub Environment reviewer
    # approves. This is the approval gate enforced by IAM, not just Actions
    # config (PRD §6.3).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.gh_owner_repo}:environment:prod"]
    }
  }
}

data "aws_iam_policy_document" "trust_agents_inference" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.gh_owner_repo}:pull_request",        # ReviewBot, Triage
        "repo:${local.gh_owner_repo}:ref:refs/heads/main", # Release (dev)
        "repo:${local.gh_owner_repo}:environment:dev",
        "repo:${local.gh_owner_repo}:environment:prod", # Release, Incident
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# plan-readonly — terraform plan on same-repo PRs. Read/describe only.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "plan_readonly" {
  name               = "paved-road-plan-readonly"
  assume_role_policy = data.aws_iam_policy_document.trust_plan_readonly.json
  tags               = { Project = "paved-road", Role = "plan-readonly" }
}

data "aws_iam_policy_document" "plan_readonly_perms" {
  statement {
    sid    = "ReadServiceResources"
    effect = "Allow"
    actions = [
      "lambda:Get*", "lambda:List*",
      "dynamodb:Describe*", "dynamodb:List*",
      "cloudfront:Get*", "cloudfront:List*",
      "ecr:Describe*", "ecr:List*", "ecr:GetRepositoryPolicy",
      "iam:Get*", "iam:List*",
      "logs:Describe*", "logs:List*", "logs:Get*",
      "cloudwatch:Describe*", "cloudwatch:Get*", "cloudwatch:List*",
      "budgets:View*", "budgets:Describe*",
      "tag:Get*",
      "s3:GetObject", "s3:ListBucket", # read the state file being planned against
    ]
    resources = ["*"] # plan is read-only; a *:Get/List/Describe policy has no mutation blast radius
  }
}

resource "aws_iam_role_policy" "plan_readonly" {
  name   = "read-only"
  role   = aws_iam_role.plan_readonly.id
  policy = data.aws_iam_policy_document.plan_readonly_perms.json
}

# ---------------------------------------------------------------------------
# deploy-dev — writes dev + preview (pr-*) named resources only.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "deploy_dev" {
  name               = "paved-road-deploy-dev"
  assume_role_policy = data.aws_iam_policy_document.trust_deploy_dev.json
  tags               = { Project = "paved-road", Role = "deploy-dev" }
}

data "aws_iam_policy_document" "deploy_dev_perms" {
  statement {
    sid    = "WriteDevAndPreviewResources"
    effect = "Allow"
    actions = [
      "lambda:*",
      "dynamodb:*",
      "cloudfront:*",
      "ecr:*",
      "logs:*",
      "cloudwatch:*",
    ]
    resources = [
      "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.svc_name_prefix}-dev*",
      "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.svc_name_prefix}-pr-*",
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${local.svc_name_prefix}-dev*",
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${local.svc_name_prefix}-pr-*",
      "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.svc_name_prefix}",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.svc_name_prefix}-dev*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.svc_name_prefix}-pr-*",
      "*", # CloudFront/CloudWatch alarms have no path-style resource scoping usable here; tightened in session 2 once modules/ fixes the exact shapes (see bootstrap/README.md)
    ]
  }
  statement {
    sid     = "PassAndManageLambdaExecRole"
    effect  = "Allow"
    actions = ["iam:CreateRole", "iam:DeleteRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:PassRole", "iam:GetRole", "iam:TagRole"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${local.svc_name_prefix}-dev-exec",
      "arn:aws:iam::${local.account_id}:role/${local.svc_name_prefix}-pr-*-exec",
    ]
  }
  statement {
    sid       = "StateBackend"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*", aws_dynamodb_table.tfstate_lock.arn]
  }
}

resource "aws_iam_role_policy" "deploy_dev" {
  name   = "write-dev-and-preview"
  role   = aws_iam_role.deploy_dev.id
  policy = data.aws_iam_policy_document.deploy_dev_perms.json
}

# ---------------------------------------------------------------------------
# deploy-prod — writes prod-named resources only. Unassumable pre-approval.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "deploy_prod" {
  name               = "paved-road-deploy-prod"
  assume_role_policy = data.aws_iam_policy_document.trust_deploy_prod.json
  tags               = { Project = "paved-road", Role = "deploy-prod" }
}

data "aws_iam_policy_document" "deploy_prod_perms" {
  statement {
    sid    = "WriteProdResources"
    effect = "Allow"
    actions = [
      "lambda:*",
      "dynamodb:*",
      "cloudfront:*",
      "ecr:*",
      "logs:*",
      "cloudwatch:*",
    ]
    resources = [
      "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.svc_name_prefix}-prod*",
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${local.svc_name_prefix}-prod*",
      "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.svc_name_prefix}",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.svc_name_prefix}-prod*",
      "*", # see deploy-dev's note — CloudFront/CloudWatch alarms tightened in session 2
    ]
  }
  statement {
    sid       = "PassAndManageLambdaExecRole"
    effect    = "Allow"
    actions   = ["iam:CreateRole", "iam:DeleteRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:PassRole", "iam:GetRole", "iam:TagRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.svc_name_prefix}-prod-exec"]
  }
  statement {
    sid       = "StateBackend"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*", aws_dynamodb_table.tfstate_lock.arn]
  }
}

resource "aws_iam_role_policy" "deploy_prod" {
  name   = "write-prod"
  role   = aws_iam_role.deploy_prod.id
  policy = data.aws_iam_policy_document.deploy_prod_perms.json
}

# ---------------------------------------------------------------------------
# agents-inference — bedrock:InvokeModel on one model + ledger writes. Never
# anything cloud-mutating (PRD §8.1, DECISIONS.md §1: an agent is a credential
# like any other).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "agents_inference" {
  name               = "paved-road-agents-inference"
  assume_role_policy = data.aws_iam_policy_document.trust_agents_inference.json
  tags               = { Project = "paved-road", Role = "agents-inference" }
}

data "aws_iam_policy_document" "agents_inference_perms" {
  statement {
    sid       = "InvokeAllowlistedModelOnly"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["arn:aws:bedrock:${local.region}::foundation-model/${var.bedrock_model_id}"]
  }
  statement {
    sid       = "WriteLedgerOnly"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = ["arn:aws:dynamodb:${local.region}:${local.account_id}:table/${local.svc_name_prefix}-agent-ledger"]
  }
}

resource "aws_iam_role_policy" "agents_inference" {
  name   = "invoke-and-log-only"
  role   = aws_iam_role.agents_inference.id
  policy = data.aws_iam_policy_document.agents_inference_perms.json
}
