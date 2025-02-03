variable "deployment_environment" {
  description = "The deployment environment"
  type        = string
}

locals {
  # Define the schedule for daily backups (High Priority)
  daily_schedule_expression   = lookup(local.daily_schedule_expression_map, var.deployment_environment, "cron(0 0 * * ? *)")
  
  # Define the schedule for monthly backups (Medium Priority)
  monthly_schedule_expression = lookup(local.monthly_schedule_expression_map, var.deployment_environment, "cron(0 0 1 * ? *)")
  
  # Define the schedule for yearly backups (Low Priority)
  yearly_schedule_expression  = lookup(local.yearly_schedule_expression_map, var.deployment_environment, "cron(0 0 1 1 ? *)")
  
  # Retention periods for each type of backup
  daily_delete_after   = 7     # Retain daily backups for 7 days (High Priority)
  monthly_delete_after = 30    # Retain monthly backups for 30 days (Medium Priority)
  yearly_delete_after  = 365   # Retain yearly backups for 365 days (Low Priority)

  # Cold storage settings (example values, you can adjust as needed)
  high_cold_storage_after = 120
  mid_cold_storage_after  = 120
  low_cold_storage_after  = 120
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
  count             = var.environment == "platform" ? 1 : 0
  backup_vault_name = aws_backup_vault.high.name
  policy            = data.aws_iam_policy_document.deny_vault_deletion[0].json
}

resource "aws_backup_vault_policy" "medium" {
  count             = var.environment == "platform" ? 1 : 0
  backup_vault_name = aws_backup_vault.medium.name
  policy            = data.aws_iam_policy_document.deny_vault_deletion[0].json
}

resource "aws_backup_vault_policy" "low" {
  count             = var.environment == "platform" ? 1 : 0
  backup_vault_name = aws_backup_vault.low.name
  policy            = data.aws_iam_policy_document.deny_vault_deletion[0].json
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
      cold_storage_after = var.deployment_environment != "gcc-prod" ? null : local.high_cold_storage_after
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
      cold_storage_after = var.deployment_environment != "gcc-prod" ? null : local.mid_cold_storage_after
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
      cold_storage_after = var.deployment_environment != "gcc-prod" ? null : local.low_cold_storage_after
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
