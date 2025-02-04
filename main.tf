variable "environment" {
  description = "The deployment environment"
  type        = string
}

# Add tags variable for resource tagging
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

locals {

  # Schedule expression maps for different environments
  daily_schedule_expression_map = {
    dev       = "cron(0 0 * * ? *)"      # Midnight every day
    staging   = "cron(0 0 * * ? *)"      # Midnight every day
    prod      = "cron(0 0 * * ? *)"      # Midnight every day
  }

  monthly_schedule_expression_map = {
    dev       = "cron(0 0 1 * ? *)"      # Midnight on the 1st of every month
    staging   = "cron(0 0 1 * ? *)"      # Midnight on the 1st of every month
    prod      = "cron(0 0 1 * ? *)"      # Midnight on the 1st of every month
  }

  yearly_schedule_expression_map = {
    dev       = "cron(0 0 1 1 ? *)"      # Midnight on January 1st
    staging   = "cron(0 0 1 1 ? *)"      # Midnight on January 1st
    prod      = "cron(0 0 1 1 ? *)"      # Midnight on January 1st
  }

  # Define the schedule for daily backups (High Priority)
  daily_schedule_expression   = lookup(local.daily_schedule_expression_map, var.environment, "cron(0 0 * * ? *)")
  
  # Define the schedule for monthly backups (Medium Priority)
  monthly_schedule_expression = lookup(local.monthly_schedule_expression_map, var.environment, "cron(0 0 1 * ? *)")
  
  # Define the schedule for yearly backups (Low Priority)
  yearly_schedule_expression  = lookup(local.yearly_schedule_expression_map, var.environment, "cron(0 0 1 1 ? *)")
  
  # Retention periods for each type of backup
  daily_delete_after   = 120     # Retain daily backups for 7 days (High Priority)
  monthly_delete_after = 365    # Retain monthly backups for 30 days (Medium Priority)
  yearly_delete_after  = 1825   # Retain yearly backups for 365 days (Low Priority)

  # Cold storage settings (example values, you can adjust as needed)
  high_cold_storage_after = 90
  mid_cold_storage_after  = 60
  low_cold_storage_after  = 30
}

# Add random string resource for unique naming
resource "random_string" "id" {
    length  = 6
    special = false
    upper   = false
}

# Define a backup vault for high-priority backups (Daily)
resource "aws_backup_vault" "high" {
  name          = "high-${random_string.id.result}"
  force_destroy = true
}

# Define a backup vault for medium-priority backups (Monthly)
resource "aws_backup_vault" "medium" {
  name          = "medium-${random_string.id.result}"
  force_destroy = true
}

# Define a backup vault for low-priority backups (Yearly)
resource "aws_backup_vault" "low" {
  name          = "low-${random_string.id.result}"
  force_destroy = true
}

# Define policies to prevent deletion of backup vaults
resource "aws_backup_vault_policy" "high" {
  count             = var.environment == "staging" ? 1 : 0
  backup_vault_name = aws_backup_vault.high.name
  policy            = length(data.aws_iam_policy_document.deny_vault_deletion) > 0 ? data.aws_iam_policy_document.deny_vault_deletion[0].json : ""
}

resource "aws_backup_vault_policy" "medium" {
  count             = var.environment == "staging" ? 1 : 0
  backup_vault_name = aws_backup_vault.medium.name
  policy            = length(data.aws_iam_policy_document.deny_vault_deletion) > 0 ? data.aws_iam_policy_document.deny_vault_deletion[0].json : ""
}

resource "aws_backup_vault_policy" "low" {
  count             = var.environment == "staging" ? 1 : 0
  backup_vault_name = aws_backup_vault.low.name
  policy            = length(data.aws_iam_policy_document.deny_vault_deletion) > 0 ? data.aws_iam_policy_document.deny_vault_deletion[0].json : ""
}

# Define the daily backup plan (High Priority)
resource "aws_backup_plan" "daily_backup_plan" {
  name = "daily_backup_plan-${random_string.id.result}"
  rule {
    rule_name         = "daily_backup_rule"
    target_vault_name = aws_backup_vault.high.name
    schedule          = local.daily_schedule_expression
    lifecycle {
      delete_after = local.daily_delete_after
      cold_storage_after = var.environment != "staging" ? null : local.high_cold_storage_after
    }
  }
}

# Define the monthly backup plan (Medium Priority)
resource "aws_backup_plan" "monthly_backup_plan" {
  name = "monthly_backup_plan-${random_string.id.result}"
  rule {
    rule_name         = "monthly_backup_rule"
    target_vault_name = aws_backup_vault.medium.name
    schedule          = local.monthly_schedule_expression
    lifecycle {
      delete_after = local.monthly_delete_after
      cold_storage_after = var.environment != "staging" ? null : local.mid_cold_storage_after
    }
  }
}

# Define the yearly backup plan (Low Priority)
resource "aws_backup_plan" "yearly_backup_plan" {
  name = "yearly_backup_plan-${random_string.id.result}"
  rule {
    rule_name         = "yearly_backup_rule"
    target_vault_name = aws_backup_vault.low.name
    schedule          = local.yearly_schedule_expression
    lifecycle {
      delete_after = local.yearly_delete_after
      cold_storage_after = var.environment != "staging" ? null : local.low_cold_storage_after
    }
  }
}

# Define the selection for high priority backups (Daily)
resource "aws_backup_selection" "high_backup_selection" {
  iam_role_arn = aws_iam_role.role_backup.arn
  name         = "high_backup_selection-${random_string.id.result}"
  plan_id      = aws_backup_plan.daily_backup_plan.id

  # Select resources with the tag 'backup_plan' = 'High'
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup_plan"
    value = "High"
  }
}

# Define the selection for medium priority backups (Monthly)
resource "aws_backup_selection" "medium_backup_selection" {
  iam_role_arn = aws_iam_role.role_backup.arn
  name         = "medium_backup_selection-${random_string.id.result}"
  plan_id      = aws_backup_plan.monthly_backup_plan.id

  # Select resources with the tag 'backup_plan' = 'Medium'
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup_plan"
    value = "Medium"
  }
}

# Define the selection for low priority backups (Yearly)
resource "aws_backup_selection" "low_backup_selection" {
  iam_role_arn = aws_iam_role.role_backup.arn
  name         = "low_backup_selection-${random_string.id.result}"
  plan_id      = aws_backup_plan.yearly_backup_plan.id

  # Select resources with the tag 'backup_plan' = 'Low'
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup_plan"
    value = "Low"
  }
}

data "aws_iam_policy_document" "deny_vault_deletion" {
  count = var.environment == "staging" ? 1 : 0
  statement {
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "backup:DeleteBackupVault",
      "backup:DeleteRecoveryPoint"
    ]

    resources = ["*"]
  }
}

# Add IAM role for AWS Backup
resource "aws_iam_role" "role_backup" {
  name = "aws-backup-service-role-${random_string.id.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS Backup service role policy
resource "aws_iam_role_policy_attachment" "backup_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.role_backup.name
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
  role       = aws_iam_role.role_backup.name
}

# Add outputs for the created resources
output "backup_vault_arns" {
  description = "ARNs of the created backup vaults"
  value = {
    high   = aws_backup_vault.high.arn
    medium = aws_backup_vault.medium.arn
    low    = aws_backup_vault.low.arn
  }
}

output "backup_role_arn" {
  description = "ARN of the IAM role created for AWS Backup"
  value       = aws_iam_role.role_backup.arn
}
