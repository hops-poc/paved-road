# GitHub's OIDC issuer. Thumbprint fetched live from the cert chain rather than
# hardcoded — AWS's IdP no longer actually validates it against GitHub's cert
# (GitHub is in AWS's trusted CA list), but the Terraform resource schema
# still requires the argument.
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]

  tags = {
    Project = "paved-road"
  }
}
