resource "aws_s3_bucket" "tiered_storage" {
  count  = var.tiered_storage_enabled ? 1 : 0
  bucket = local.tiered_storage_bucket_name
  tags   = local.instance_tags
}

resource "aws_s3_bucket_acl" "tiered_storage" {
  count  = var.tiered_storage_enabled ? 1 : 0
  bucket = aws_s3_bucket.tiered_storage[count.index].id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "tiered_storage" {
  count  = var.tiered_storage_enabled ? 1 : 0
  bucket = aws_s3_bucket.tiered_storage[count.index].id
  versioning_configuration {
    status = "Disabled"
  }
}
