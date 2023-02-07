data "aws_caller_identity" "current" {}

data "aws_caller_identity" "source_account" {
    provider = aws.sandbox
}

data "aws_caller_identity" "backup_account" {
    provider = aws.backup
}