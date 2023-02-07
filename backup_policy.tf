#IAM roles for taking backups

# back IAM resources in workload account
resource "aws_iam_role" "aws_backup_role" {
  provider = aws.sandbox
  name               = "iam_role_backup"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["sts:AssumeRole"],
      "Effect": "allow",
      "Principal": {
        "Service": ["backup.amazonaws.com"]
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "aws_backup_role" {
  provider = aws.sandbox
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.aws_backup_role.name
}



# Backup IAM resources in central backup account

resource "aws_iam_role" "central_backup_role" {
  provider = aws.backup
  name               = "iam_role_backup"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["sts:AssumeRole"],
      "Effect": "allow",
      "Principal": {
        "Service": ["backup.amazonaws.com"]
      }
    }
  ]
}
POLICY
  managed_policy_arns = [aws_iam_policy.service_role_policy.arn]
}



resource "aws_iam_role_policy_attachment" "central_backup_role" {
  provider = aws.backup
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.central_backup_role.name
}


# service-linked policy for rds in backup account
data "aws_iam_policy_document" "service_linked_policy" {
  statement {
    actions = ["iam:CreateServiceLinkedRole"]
    effect = "Allow"
    resources = ["arn:aws:iam::${data.aws_caller_identity.backup_account.account_id}:role/aws-service-role/backup.amazonaws.com/AWSServiceRoleForBackup"]
  }
  
}

 resource "aws_iam_policy" "service_role_policy" {
    provider          = aws.backup
    name = "service-role-backup"
    policy = data.aws_iam_policy_document.service_linked_policy.json
 }






# Backup Policy configured at org level

resource "aws_organizations_policy" "backup_rds_policy" {
  provider    = aws.central
  name        = "rds_backup_policy"
  type        = "BACKUP_POLICY"
  content     = <<POLICY
    {
    	"plans": {
    		"rds": {
    			"regions": {
    				"@@assign": [
    					"${var.regions}"
    				]
    			},
    			"rules": {
    				"hourly": {
              "schedule_expression": {"@@assign": "cron(0 7,15 ? * * *)"},
    					"target_backup_vault_name": {
    						"@@assign": "${aws_backup_vault.source_backup_vault.name}"
    					},
    					"lifecycle": {
    						"delete_after_days": {
    							"@@assign": "1"
    						}
    					},
    					"copy_actions": {
    						"${aws_backup_vault.central_backup_vault.arn}": {
    							"target_backup_vault_arn": {
    								"@@assign": "${aws_backup_vault.central_backup_vault.arn}"
    							},
    							"lifecycle": {
    								"delete_after_days": {
    									"@@assign": "2"
    								}
    							}
    						}
    					}
    				}
    			},
    			"selections": {
    				"tags": {
    					"awsbackup": {
    						"iam_role_arn": {
    							"@@assign": "arn:aws:iam::$account:role/${aws_iam_role.aws_backup_role.name}"
    						},
    						"tag_key": {
    							"@@assign": "awsBackup"
    						},
    						"tag_value": {
    							"@@assign": [
    								"true"
    							]
    						}
    					}
    				}
    			}
    		}
    	}
    }
POLICY
}


resource "aws_organizations_policy_attachment" "backup_policy_attachment" {
  provider    = aws.central
  policy_id = aws_organizations_policy.backup_rds_policy.id
  target_id = data.aws_caller_identity.current.account_id
}