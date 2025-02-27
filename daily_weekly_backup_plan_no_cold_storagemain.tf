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

  # New schedule expression map for weekly backups
  weekly_schedule_expression_map = {
    dev     = "cron(0 0 ? * SUN *)"  # Midnight UTC every Sunday
    staging = "cron(0 0 ? * SUN *)"  # Midnight UTC every Sunday
    prod    = "cron(0 0 ? * SUN *)"  # Midnight UTC every Sunday
  }

  # Use lookup to set schedules based on environment
  daily_schedule_expression  = lookup(local.daily_schedule_expression_map, var.environment, "cron(0 0 * * ? *)")
  weekly_schedule_expression = lookup(local.weekly_schedule_expression_map, var.environment, "cron(0 0 ? * SUN *)")

  # Retention periods
  daily_delete_after  = 7   # Retain daily backups for 7 days (high priority)
  weekly_delete_after = 28  # Retain weekly backups for 28 days (medium priority, 4 weeks)
}

# Generate a random string for unique resource naming
resource "random_string" "id" {
  length  = 6
  special = false
  upper   = false
}

# Create a backup vault for daily backups (high priority)
resource "aws_backup_vault" "high" {
  name          = "high-${random_string.id.result}"  # Unique name with random suffix
  force_destroy = true                              # Allows deletion even if backups exist
  tags = merge(
    var.tags,
    {
      Environment = var.environment             # Tag vault with environment
      Purpose     = "Daily EC2 Backups"         # Descriptive tag
    }
  )
}

# New backup vault for weekly backups (medium priority)
resource "aws_backup_vault" "medium" {
  name          = "medium-${random_string.id.result}"  # Unique name with random suffix
  force_destroy = true                                # Allows deletion even if backups exist
  tags = merge(
    var.tags,
    {
      Environment = var.environment             # Tag vault with environment
      Purpose     = "Weekly EC2 Backups"        # Descriptive tag
    }
  )
}

# Define the daily backup plan (high priority)
resource "aws_backup_plan" "daily_backup_plan" {
  name = "daily_backup_plan-${random_string.id.result}"  # Unique plan name
  tags = merge(
    var.tags,
    {
      Environment = var.environment              # Tag plan with environment
      AWS_Backup  = "terraform"                  # Indicate Terraform management
    }
  )

  rule {
    rule_name         = "daily_backup_rule"          # Name of the rule
    target_vault_name = aws_backup_vault.high.name   # Store in 'high' vault
    schedule          = local.daily_schedule_expression  # Daily at midnight UTC
    lifecycle {
      delete_after = local.daily_delete_after        # Retain for 7 days
    }
  }
}

# New weekly backup plan (medium priority)
resource "aws_backup_plan" "weekly_backup_plan" {
  name = "weekly_backup_plan-${random_string.id.result}"  # Unique plan name
  tags = merge(
    var.tags,
    {
      Environment = var.environment              # Tag plan with environment
      AWS_Backup  = "terraform"                  # Indicate Terraform management
    }
  )

  rule {
    rule_name         = "weekly_backup_rule"         # Name of the rule
    target_vault_name = aws_backup_vault.medium.name  # Store in 'medium' vault
    schedule          = local.weekly_schedule_expression  # Weekly on Sundays at midnight UTC
    lifecycle {
      delete_after = local.weekly_delete_after       # Retain for 28 days (4 weeks)
    }
  }
}

# IAM role for AWS Backup to access resources
resource "aws_iam_role" "role_backup" {
  name = "aws-backup-service-role-${random_string.id.result}"  # Unique role name

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

# Attach Backup policy for creating backups
resource "aws_iam_role_policy_attachment" "backup_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.role_backup.name
}

# Attach Restore policy for restoring backups
resource "aws_iam_role_policy_attachment" "restore_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
  role       = aws_iam_role.role_backup.name
}

# Backup selection for daily backups (high priority)
resource "aws_backup_selection" "high_backup_selection" {
  iam_role_arn = aws_iam_role.role_backup.arn          # Role ARN for permissions
  name         = "high_backup_selection-${random_string.id.result}"  # Unique selection name
  plan_id      = aws_backup_plan.daily_backup_plan.id  # Link to daily plan

  selection_tag {
    type  = "STRINGEQUALS"    # Match exact tag value
    key   = "backup_plan"     # Tag key
    value = "high"            # Tag value for high priority
  }
}

# New backup selection for weekly backups (medium priority)
resource "aws_backup_selection" "medium_backup_selection" {
  iam_role_arn = aws_iam_role.role_backup.arn          # Role ARN for permissions
  name         = "medium_backup_selection-${random_string.id.result}"  # Unique selection name
  plan_id      = aws_backup_plan.weekly_backup_plan.id  # Link to weekly plan

  selection_tag {
    type  = "STRINGEQUALS"    # Match exact tag value
    key   = "backup_plan"     # Tag key
    value = "medium"          # Tag value for medium priority
  }
}

# Outputs for reference
output "backup_vault_arns" {
  description = "ARNs of the created backup vaults"
  value = {
    high   = aws_backup_vault.high.arn
    medium = aws_backup_vault.medium.arn
  }
}

output "backup_plan_ids" {
  description = "IDs of the created backup plans"
  value = {
    daily  = aws_backup_plan.daily_backup_plan.id
    weekly = aws_backup_plan.weekly_backup_plan.id
  }
}

output "backup_role_arn" {
  description = "ARN of the IAM role for AWS Backup"
  value       = aws_iam_role.role_backup.arn
}
