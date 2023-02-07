###### central backup account resources ######

resource "aws_kms_key" "aws_kms_key" {
  provider = aws.backup
  description = "KMS Key for Backup"
  depends_on = [aws_iam_role.aws_backup_role]
  policy      = <<POLICY
{
    "Id": "key-consolepolicy-3",
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${data.aws_caller_identity.backup_account.account_id}:role/${var.orgAdmin_role}"
            },
            "Action": "kms:*",
            "Resource": "*"
        },
        {
            "Sid": "Allow use of the key",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "*"
                ]
            },
            "Action": [
                "kms:CreateGrant",
                "kms:Decrypt",
                "kms:GenerateDataKey*",
                "kms:DescribeKey",
                "kms:ReEncrypt*",
                "kms:RetireGrant"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:PrincipalOrgID": "${var.organization_id}"
                }
            }
        }
    ]
}
POLICY
}

resource "aws_kms_alias" "aws_kms_alias" {
  provider      = aws.backup
  name          = "alias/backup-kms"
  target_key_id = aws_kms_key.aws_kms_key.key_id
}

# backup vault in backup account

resource "aws_backup_vault" "central_backup_vault" {
  provider      = aws.backup
  name        = "central_backup_vault"
  kms_key_arn = aws_kms_key.aws_kms_key.arn
}

# vault policy to allow cross account copying - allowing copies from all accounts in the org

resource "aws_backup_vault_policy" "central_backup_vault_policy" {
  provider          = aws.backup
  backup_vault_name = aws_backup_vault.central_backup_vault.name
  depends_on = [aws_iam_role.aws_backup_role]
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "default",
  "Statement": [
    {
        "Effect": "Allow",
        "Action": "backup:CopyIntoBackupVault",
        "Resource": "*",
        "Principal": {
                    "AWS": "*"
                    },
        "Condition": {
            "StringEquals": {
                "aws:PrincipalOrgID": "${var.organization_id}"
            }
        }
    }
    ]
}
POLICY
}







###### resources to be created on source/workload account (deployed on all accounts with rds instances to be included for backups) ######

resource "aws_kms_key" "sandbox_kms" {
  provider = aws.sandbox
  description = "KMS Key for Backup"
  policy      = <<POLICY
{
    "Id": "key-consolepolicy-3",
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Allow access for Key Administrators",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.orgAdmin_role}"
            },
            "Action": "kms:*",
            "Resource": "*"
        },
        {
            "Sid": "Allow use of the key",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": [
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:DescribeKey"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "kms:CallerAccount": "${data.aws_caller_identity.backup_account.account_id}"
                }
            }
        }
    ]
}
POLICY
}

resource "aws_kms_alias" "source_kms_alias" {
  provider      = aws.sandbox
  name          = "alias/backcup-kms"
  target_key_id = aws_kms_key.sandbox_kms.key_id
}


resource "aws_backup_vault" "source_backup_vault" {
  provider      = aws.sandbox
  name        = "source_backup_vault"
  kms_key_arn = aws_kms_key.sandbox_kms.arn
}

resource "aws_backup_vault_policy" "source_backup_vault_policy" {
  provider          = aws.sandbox
  backup_vault_name = aws_backup_vault.source_backup_vault.name
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "default",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "backup:CopyIntoBackupVault",
      "Resource": "*",
      "Principal": {
                   "AWS": "${aws_iam_role.aws_backup_role.arn}"
                    }
            }
    ]
}
POLICY
}