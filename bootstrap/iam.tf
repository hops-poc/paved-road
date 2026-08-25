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
# arms — sub alone does not distinguish a fork PR from a same-repo one; that
# isolation is enforced at the workflow layer (never request id-token: write
# on a fork-triggered job), not here.
#
# sub alone also doesn't separate plan-readonly from deploy-dev: both would
# otherwise trust the identical `repo:<org>/<repo>:pull_request` subject,
# which would let a job that only needs to plan instead assume the
# write-capable role. The second discriminator is `job_workflow_ref`, which
# names the actual reusable-workflow file a job runs — this pins that
# convention now so session 3 has to build to it, not invent it under
# pressure:
#   paved-road/.github/workflows/plan.yml     -> plan-readonly
#   paved-road/.github/workflows/deploy.yml   -> deploy-dev, deploy-prod
#   paved-road/.github/workflows/agents.yml   -> agents-inference
# If session 3 lands the pipeline as one big service.yml instead of these
# three files, this scoping silently stops discriminating — split the files,
# don't just merge the conditions back to sub-only.

locals {
  job_workflow_ref_plan   = "${local.gh_owner_paved_road}/.github/workflows/plan.yml@*"
  job_workflow_ref_deploy = "${local.gh_owner_paved_road}/.github/workflows/deploy.yml@*"
  job_workflow_ref_agents = "${local.gh_owner_paved_road}/.github/workflows/agents.yml@*"
}

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
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = [local.job_workflow_ref_plan]
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
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = [local.job_workflow_ref_deploy]
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
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = [local.job_workflow_ref_deploy]
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
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = [local.job_workflow_ref_agents]
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

  # tofu plan still acquires the state lock (not just apply) — found live:
  # plan-readonly could assume the role fine but AccessDenied'd on
  # dynamodb:GetItem/PutItem against the lock table, because this role was
  # scoped assuming "read-only" meant "no lock-table access needed." Same
  # lock actions deploy-dev/deploy-prod already have, scoped to the lock
  # table only — the S3 state object read above stays on the wildcard
  # Get/List statement since it's genuinely read-only.
  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.tfstate_lock.arn]
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
  # Scopable-by-ARN services — named-resource restricted. Never combine this
  # action list with a "*" resource in the same or another statement; that
  # would grant lambda:*/dynamodb:*/ecr:*/logs:* account-wide, including
  # prod, and defeat the whole point of a per-env role (caught in review —
  # an earlier draft of this file did exactly that).
  statement {
    sid    = "WriteDevAndPreviewNamedResources"
    effect = "Allow"
    actions = [
      "lambda:*",
      "dynamodb:*",
      "ecr:*",
      "logs:*",
    ]
    resources = [
      "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.svc_name_prefix}-dev*",
      "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.svc_name_prefix}-pr-*",
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${local.svc_name_prefix}-dev*",
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${local.svc_name_prefix}-pr-*",
      "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.svc_name_prefix}",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.svc_name_prefix}-dev*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.svc_name_prefix}-pr-*",
    ]
  }
  # CloudWatch alarms ARE ARN-addressable — scope by name, same as everything else.
  statement {
    sid    = "ManageDevAndPreviewAlarms"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms", "cloudwatch:SetAlarmState", "cloudwatch:TagResource",
    ]
    resources = [
      "arn:aws:cloudwatch:${local.region}:${local.account_id}:alarm:${local.svc_name_prefix}-dev*",
      "arn:aws:cloudwatch:${local.region}:${local.account_id}:alarm:${local.svc_name_prefix}-pr-*",
    ]
  }
  # ecr:GetAuthorizationToken is an account/region-level action (the docker
  # login token isn't per-repository) — AWS requires Resource "*" for it,
  # the same class of constraint as CreateDistribution below. Putting it in
  # the repository-scoped ecr:* statement above silently grants nothing —
  # found live: deploy-dev's first real run got AccessDenied on it, `docker
  # login` never even reached the repository-scoped actions.
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  # CloudFront has no per-distribution ARN scoping until the distribution
  # exists (CreateDistribution requires resource "*" — an AWS API
  # constraint, not a policy choice). The action list is the actual scoping
  # control here: it can create/manage a distribution, nothing else.
  # OriginAccessControl actions were missing outright (not just unscopable)
  # — found live: aws_cloudfront_origin_access_control's refresh AccessDenied
  # on GetOriginAccessControl, an omission from the original design, not an
  # AWS scoping constraint like the distribution actions above.
  statement {
    sid    = "ManageCloudFrontDistributions"
    effect = "Allow"
    actions = [
      "cloudfront:CreateDistribution", "cloudfront:GetDistribution", "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution", "cloudfront:ListDistributions", "cloudfront:TagResource",
      "cloudfront:ListTagsForResource", "cloudfront:CreateInvalidation",
      "cloudfront:CreateOriginAccessControl", "cloudfront:GetOriginAccessControl",
      "cloudfront:UpdateOriginAccessControl", "cloudfront:DeleteOriginAccessControl",
    ]
    resources = ["*"]
  }
  # logs:DescribeLogGroups is a list/search action — AWS requires it use the
  # fixed pseudo-resource arn:...:log-group::log-stream: (visible verbatim
  # in the AccessDenied error), not a real log-group ARN, so it can't live
  # in the log-group-scoped logs:* statement above. Same constraint class as
  # ecr:GetAuthorizationToken/CloudFront CreateDistribution.
  statement {
    sid       = "LogsDescribe"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
  statement {
    sid    = "PassAndManageLambdaExecRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:PassRole", "iam:GetRole", "iam:TagRole",
      # Refresh-phase reads on the inline policy — missing originally, found
      # live via AccessDenied on ListRolePolicies during tofu apply's refresh.
      "iam:GetRolePolicy", "iam:ListRolePolicies",
    ]
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
  # Same shape as deploy-dev's perms — see its comments for why the
  # scopable and unscopable services are split across statements instead of
  # sharing one action list with a "*" resource.
  statement {
    sid    = "WriteProdNamedResources"
    effect = "Allow"
    actions = [
      "lambda:*",
      "dynamodb:*",
      "ecr:*",
      "logs:*",
    ]
    resources = [
      "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.svc_name_prefix}-prod*",
      "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${local.svc_name_prefix}-prod*",
      "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.svc_name_prefix}",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.svc_name_prefix}-prod*",
    ]
  }
  statement {
    sid    = "ManageProdAlarms"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms", "cloudwatch:SetAlarmState", "cloudwatch:TagResource",
    ]
    resources = ["arn:aws:cloudwatch:${local.region}:${local.account_id}:alarm:${local.svc_name_prefix}-prod*"]
  }
  statement {
    sid    = "ManageCloudFrontDistributions"
    effect = "Allow"
    actions = [
      "cloudfront:CreateDistribution", "cloudfront:GetDistribution", "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution", "cloudfront:ListDistributions", "cloudfront:TagResource",
      "cloudfront:ListTagsForResource", "cloudfront:CreateInvalidation",
    ]
    resources = ["*"]
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
