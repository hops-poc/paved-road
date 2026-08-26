# One bucket, one state file per stack inside it (PRD §5.4): bootstrap/,
# dev/, prod/. Versioned so a bad apply's state is
# recoverable; not public, ever — this is exactly the kind of bucket
# scenario 6 (public S3 via a bad plan) tests policy against.

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.gh_org}-paved-road-tfstate"

  tags = {
    Project = "paved-road"
    Purpose = "terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Terraform 1.5.7 predates S3 native locking (1.10+) — DynamoDB lock table is
# the real mechanism here, not a fallback held in reserve (bootstrap/README.md).
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "paved-road-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST" # on-demand — no idle cost
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project = "paved-road"
    Purpose = "terraform-state-lock"
  }
}
