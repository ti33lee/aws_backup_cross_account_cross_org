# create s3 bucket in Central account for snapshots storage

resource "aws_s3_bucket" "snapshots_bucket" {
    provider = aws.backup
    bucket = "rds-snapshots-bucket-${data.aws_caller_identity.backup_account.account_id}"
}
 
# create access point for boto3 s3 copy operations 
resource "aws_s3_access_point" "example" {
  bucket = aws_s3_bucket.snapshots_bucket.id
  name   = "snapshot-bucket-access-point"
}

# create s3 bucket in DR account for storing copied snapshots for recovery

resource "aws_s3_bucket" "dr_snapshots_bucket" {
    provider = aws.dr   # dr aws provider for provisioning backup bucket in DR
    bucket = "rds-snapshots-bucket-${data.aws_caller_identity.dr_account.account_id}"
}

# create iam_role for lambda

resource "aws_iam_role" "lambda_copy_s3_role" {
    provider = aws.backup
    name = "iam_role_copy_snapshot2s3"
    path = "/"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
    managed_policy_arns = [aws_iam_policy.lambda_execution_role_policy.arn]
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    sid    = "copySnapshotToS3"
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
  statement {
    sid    = "AllowRDSAssume"
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      type        = "Service"
      identifiers = ["export.rds.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_execution_role_policy" {
  statement {
    sid    = "AllowBucketAccess"
    effect = "Allow"
    actions = [
        "s3:PutObject*",
        "s3:ListBucket",
        "s3:GetObject*",
        "s3:DeleteObject*",
        "s3:GetBucketLocation"
    ]
    resources = ["${aws_s3_bucket.snapshots_bucket.arn}", "${aws_s3_bucket.snapshots_bucket.arn}/*"]
  }

  statement {
    sid    = "allowDecryptKMSkey"
    effect = "Allow"
    actions = [
      "kms:*"
    ]
    resources = [aws_kms_key.aws_kms_key.arn]
  }

  statement {
    sid    = "AllowLoggin"
    effect = "Allow"
    actions = [
      "logs:*"
    ]
    resources = ["*"]
  }
  statement {
    sid    = "OtherAccess"
    effect = "Allow"
    actions = [
      "backup:StartCopyJob", "backup:DescribeRecoveryPoint", "iam:PassRole", "rds:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda_execution_role_policy" {
    provider = aws.backup
    name = "lambda_copy2s3_role_policy"
    policy = data.aws_iam_policy_document.lambda_execution_role_policy.json
    depends_on = [aws_s3_bucket.snapshots_bucket] 
}


# lambda function to copy to s3 based on copy completion event

data "archive_file" "lambda_snapshpotCopy_zip" {
  type = "zip"
  source_file = "${path.module}/src/lambda_snapshot_s3.py"
  output_path = "${path.module}/lambda_snapshot_s3.zip"

}

resource "aws_lambda_function" "lambda_copy2s3" {
    provider = aws.backup
    function_name = "lambda_copySnapshot_s3"
    filename              = data.archive_file.lambda_snapshpotCopy_zip.output_path
    source_code_hash      = data.archive_file.lambda_snapshpotCopy_zip.output_base64sha256
    role = aws_iam_role.lambda_copy_s3_role.arn
    handler               = "lambda_snapshot_s3.handler"
    memory_size           = 256
    runtime               = "python3.9"
    timeout               = 300
    description           = "runs snapshot copy from aws backup vault to local s3 bucket"
    publish               = "true"
    environment {
        variables = {
            S3BucketName = "${aws_s3_bucket.snapshots_bucket.id}",
            IamRoleArn = "${aws_iam_role.lambda_copy_s3_role.arn}",
            KmsKeyId = "${aws_kms_key.aws_kms_key.arn}"
        }
    }
}

# allow lambda eventrule triggers
resource "aws_lambda_permission" "allow_eventbus" {
    provider = aws.backup
    statement_id  = "allowLambdaExecutionfromEventRule"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_copy2s3.function_name
    principal     = "events.amazonaws.com"
    source_arn    = aws_cloudwatch_event_rule.central_eventbridge_rule.arn
}





 # archive file second function to do cross-organization copy
data "archive_file" "lambda_copytodr_zip" {
  type = "zip"
  source_file = "${path.module}/src/lambda_copytodr.py"
  output_path = "${path.module}/lambda_copytodr.zip"

}
#lambda function to copy manual snapshot to S3 bucket in DR account 
resource "aws_lambda_function" "lambda_copy2s3" {
    count = var.enabled ? 1 : 0   # should only be enabled when we set dr destination
    provider = aws.backup   
    function_name = "lambda_copytodr"
    filename              = data.archive_file.lambda_copytodr_zip.output_path
    source_code_hash      = data.archive_file.lambda_copytodr_zip.output_base64sha256
    role = aws_iam_role.lambda_copy_s3_role.arn
    handler               = "lambda_copytodr.handler"
    memory_size           = 256
    runtime               = "python3.9"
    timeout               = 300
    description           = "runs cross org manual snapshot copy from central s3 bucket to DR s3 bucket"
    publish               = "true"
    environment {
        variables = {
            backup_s3_bucket = "${aws_s3_bucket.snapshots_bucket.id}",
            dr_s3_bucket     =  "${aws_s3_bucket.dr_snapshots_bucket.name}",
            IamRoleArn = "${aws_iam_role.lambda_copy_s3_role.arn}",
            KmsKeyId = ""  # kms key ID for encryption of snapshot in DR bucket
        }
    }
}



# allow lambda s3 triggers
resource "aws_lambda_permission" "allow_bucket_triggers" {
    count = var.enabled ? 1 : 0   # should only be enabled when we set dr destination
    provider = aws.backup  
    statement_id  = "AllowExecutionFromS3Bucket"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_copy2s3.arn
    principal     = "s3.amazonaws.com"
    source_arn    = aws_s3_bucket.bucket.arn
}