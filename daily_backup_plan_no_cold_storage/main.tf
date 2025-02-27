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

  # Use lookup to set the daily schedule based on environment, defaulting to midnight UTC
  daily_schedule_expression = lookup(local.daily_schedule_expression_map, var.environment, "cron(0 0 * * ? *)")

  # Retention period for daily backups
  daily_delete_after = 7  # Retain daily backups for 7 days to support RTO of 72 hours
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
  force_destroy = true                              # Allows deletion even if backups exist (useful for testing)
  tags = merge(
    var.tags,
    {
      Environment = var.environment             # Tag vault with environment
      Purpose     = "Daily EC2 Backups"         # Descriptive tag
    }
  )
}

# Define the daily backup plan for EC2 instances
resource "aws_backup_plan" "daily_backup_plan" {
  name = "daily_backup_plan-${random_string.id.result}"  # Unique plan name
  tags = merge(
    var.tags,
    {
      Environment = var.environment              # Tag plan with environment
      AWS_Backup  = "terraform"                  # Indicate Terraform management
    }
  )

  # Define the backup rule
  rule {
    rule_name         = "daily_backup_rule"          # Name of the rule
    target_vault_name = aws_backup_vault.high.name   # Store backups in the 'high' vault
    schedule          = local.daily_schedule_expression  # Daily at midnight UTC (adjustable via environment)
    lifecycle {
      delete_after = local.daily_delete_after        # Retain for 7 days to ensure RTO of 72 hours
      # No cold storage transition for simplicity; backups stay in warm storage
    }
  }
}

# IAM role for AWS Backup to access resources
resource "aws_iam_role" "role_backup" {
  name = "aws-backup-service-role-${random_string.id.result}"  # Unique role name

  # Allow AWS Backup service to assume this role
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
  role       = aws_iam_role.role_backup.name  # Attach to the Backup role
}

# Attach Restore policy for restoring backups
resource "aws_iam_role_policy_attachment" "restore_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
  role       = aws_iam_role.role_backup.name  # Attach to the Backup role
}

# Define the backup selection for EC2 instances tagged with 'backup_plan: high'
resource "aws_backup_selection" "high_backup_selection" {
  iam_role_arn = aws_iam_role.role_backup.arn          # Role ARN for permissions
  name         = "high_backup_selection-${random_string.id.result}"  # Unique selection name
  plan_id      = aws_backup_plan.daily_backup_plan.id  # Link to the daily backup plan

  # Target EC2 instances with the tag 'backup_plan: high'
  selection_tag {
    type  = "STRINGEQUALS"    # Match exact tag value
    key   = "backup_plan"     # Tag key from your requirement
    value = "high"            # Tag value from your requirement
  }
}

# Outputs for reference
output "backup_vault_arn" {
  description = "ARN of the high-priority backup vault"
  value       = aws_backup_vault.high.arn
}

output "backup_plan_id" {
  description = "ID of the daily backup plan"
  value       = aws_backup_plan.daily_backup_plan.id
}

output "backup_role_arn" {
  description = "ARN of the IAM role for AWS Backup"
  value       = aws_iam_role.role_backup.arn
}
