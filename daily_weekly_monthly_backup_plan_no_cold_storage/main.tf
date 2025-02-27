# Define input variables
variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Local variables for schedules and retention
locals {
  # Schedule expression maps for different environments
  daily_schedule_expression_map = {
    dev     = "cron(0 0 * * ? *)"  # Midnight UTC daily
    staging = "cron(0 0 * * ? *)"  # Midnight UTC daily
    prod    = "cron(0 0 * * ? *)"  # Midnight UTC daily
  }

  weekly_schedule_expression_map = {
    dev     = "cron(0 0 ? * SUN *)"  # Midnight UTC every Sunday
    staging = "cron(0 0 ? * SUN *)"  # Midnight UTC every Sunday
    prod    = "cron(0 0 ? * SUN *)"  # Midnight UTC every Sunday
  }

  # New schedule expression map for monthly backups
  monthly_schedule_expression_map = {
    dev     = "cron(0 0 1 * ? *)"  # Midnight UTC on the 1st of every month
    staging = "cron(0 0 1 * ? *)"  # Midnight UTC on the 1st of every month
    prod    = "cron(0 0 1 * ? *)"  # Midnight UTC on the 1st of every month
  }

  # Use lookup to set schedules based on environment
  daily_schedule_expression   = lookup(local.daily_schedule_expression_map, var.environment, "cron(0 0 * * ? *)")
  weekly_schedule_expression  = lookup(local.weekly_schedule_expression_map, var.environment, "cron(0 0 ? * SUN *)")
  monthly_schedule_expression = lookup(local.monthly_schedule_expression_map, var.environment, "cron(0 0 1 * ? *)")

  # Retention periods
  daily_delete_after   = 7   # Retain daily backups for 7 days (high priority)
  weekly_delete_after  = 28  # Retain weekly backups for 28 days (medium priority)
  monthly_delete_after = 90  # Retain monthly backups for 90 days (low priority, 3 months)
}

# Generate a random string for unique resource naming
resource "random_string" "id" {
  length  = 6
  special = false
  upper   = false
}

# Backup vault for daily backups (high priority)
resource "aws_backup_vault" "high" {
  name          = "high-${random_string.id.result}"
  force_destroy = true
  tags = merge(
    var.tags,
    {
      Environment = var.environment
      Purpose     = "Daily EC2 Backups"
    }
  )
}

# Backup vault for weekly backups (medium priority)
resource "aws_backup_vault" "medium" {
  name          = "medium-${random_string.id.result}"
  force_destroy = true
  tags = merge(
    var.tags,
    {
      Environment = var.environment
      Purpose     = "Weekly EC2 Backups"
    }
  )
}

# New backup vault for monthly backups (low priority)
resource "aws_backup_vault" "low" {
  name          = "low-${random_string.id.result}"  # Unique name with random suffix
  force_destroy = true                              # Allows deletion even if backups exist
  tags = merge(
    var.tags,
    {
      Environment = var.environment             # Tag vault with environment
      Purpose     = "Monthly EC2 Backups"       # Descriptive tag
    }
  )
}

# Daily backup plan (high priority)
resource "aws_backup_plan" "daily_backup_plan" {
  name = "daily_backup_plan-${random_string.id.result}"
  tags = merge(
    var.tags,
    {
      Environment = var.environment
      AWS_Backup  = "terraform"
    }
  )
  rule {
    rule_name         = "daily_backup_rule"
    target_vault_name = aws_backup_vault.high.name
    schedule          = local.daily_schedule_expression
    lifecycle {
      delete_after = local.daily_delete_after
    }
  }
}

# Weekly backup plan (medium priority)
resource "aws_backup_plan" "weekly_backup_plan" {
  name = "weekly_backup_plan-${random_string.id.result}"
  tags = merge(
    var.tags,
    {
      Environment = var.environment
      AWS_Backup  = "terraform"
    }
  )
  rule {
    rule_name         = "weekly_backup_rule"
    target_vault_name = aws_backup_vault.medium.name
    schedule          = local.weekly_schedule_expression
    lifecycle {
      delete_after = local.weekly_delete_after
    }
  }
}

# New monthly backup plan (low priority)
resource "aws_backup_plan" "monthly_backup_plan" {
  name = "monthly_backup_plan-${random_string.id.result}"  # Unique plan name
  tags = merge(
    var.tags,
    {
      Environment = var.environment              # Tag plan with environment
      AWS_Backup  = "terraform"                  # Indicate Terraform management
    }
  )
  rule {
    rule_name         = "monthly_backup_rule"         # Name of the rule
    target_vault_name = aws_backup_vault.low.name     # Store in 'low' vault
    schedule          = local.monthly_schedule_expression  # Monthly on the 1st at midnight UTC
    lifecycle {
      delete_after = local.monthly_delete_after       # Retain for 90 days (3 months)
    }
  }
}

# IAM role for AWS Backup
resource "aws_iam_role" "role_backup" {
  name = "aws-backup-service-role-${random_string.id.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })
}

# Attach Backup policy
resource "aws_iam_role_policy_attachment" "backup_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.role_backup.name
}

# Attach Restore policy
resource "aws_iam_role_policy_attachment" "restore_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
  role       = aws_iam_role.role_backup.name
}

# Backup selection for daily backups (high priority)
resource "aws_backup_selection" "high_backup_selection" {
  iam_role_arn = aws_iam_role.role_backup.arn
  name         = "high_backup_selection-${random_string.id.result}"
  plan_id      = aws_backup_plan.daily_backup_plan.id
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup_plan"
    value = "high"
  }
}

# Backup selection for weekly backups (medium priority)
resource "aws_backup_selection" "medium_backup_selection" {
  iam_role_arn = aws_iam_role.role_backup.arn
  name         = "medium_backup_selection-${random_string.id.result}"
  plan_id      = aws_backup_plan.weekly_backup_plan.id
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup_plan"
    value = "medium"
  }
}

# New backup selection for monthly backups (low priority)
resource "aws_backup_selection" "low_backup_selection" {
  iam_role_arn = aws_iam_role.role_backup.arn          # Reuse same IAM role
  name         = "low_backup_selection-${random_string.id.result}"  # Unique selection name
  plan_id      = aws_backup_plan.monthly_backup_plan.id  # Link to monthly plan
  selection_tag {
    type  = "STRINGEQUALS"    # Match exact tag value
    key   = "backup_plan"     # Tag key
    value = "low"             # Tag value for low priority
  }
}

# Outputs
output "backup_vault_arns" {
  description = "ARNs of the created backup vaults"
  value = {
    high   = aws_backup_vault.high.arn
    medium = aws_backup_vault.medium.arn
    low    = aws_backup_vault.low.arn
  }
}

output "backup_plan_ids" {
  description = "IDs of the created backup plans"
  value = {
    daily   = aws_backup_plan.daily_backup_plan.id
    weekly  = aws_backup_plan.weekly_backup_plan.id
    monthly = aws_backup_plan.monthly_backup_plan.id
  }
}

output "backup_role_arn" {
  description = "ARN of the IAM role for AWS Backup"
  value       = aws_iam_role.role_backup.arn
}
