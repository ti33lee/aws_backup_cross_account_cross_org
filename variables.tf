variable "backup_iam_role" {
    default = ""
}


variable "regions" {
    default = "eu-west-1"
}

variable "retention_period" {
    description = "in days"
    default     = "1"
}

variable "recovery_tag" {
    default = "rds_name"
}

variable "recovery_tag_value" {
    default = "test"
}

variable "orgAdmin_role" {
    default = ""
}

variable "organization_id" {
    default = ""
}

variable "central_bucket_name" {
    default = "rds-snapshots-bucket-xxx"
}

# should resource be created?
variable "enabled" { 
    type = bool
    default = false
}