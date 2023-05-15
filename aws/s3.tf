## NOTE: We do not support AWS ACLs, and AWS recommends not using ACLs with IAM. See link for more details: https://docs.aws.amazon.com/AmazonS3/latest/userguide/acl-overview.html
## ACLs removed in PR 173

resource "aws_s3_bucket" "tiered_storage" {
  count         = var.tiered_storage_enabled ? 1 : 0
  bucket        = local.tiered_storage_bucket_name
  tags          = local.instance_tags
  force_destroy = var.allow_force_destroy
}

resource "aws_s3_bucket_versioning" "tiered_storage" {
  count  = var.tiered_storage_enabled ? 1 : 0
  bucket = aws_s3_bucket.tiered_storage[count.index].id
  versioning_configuration {
    status = "Disabled"
  }
}
