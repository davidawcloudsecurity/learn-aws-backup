Let’s add a `backup_plan: low` for monthly backups with a retention period of 3 months (90 days) to your Terraform setup. I’ll explain the approach without rewriting the full script, then provide the modified Terraform code with comments to integrate it alongside your existing `high` (daily) and `medium` (weekly) plans. This will target EC2 instances tagged `backup_plan: low`.

---

### Approach for `backup_plan: low`

#### 1. Backup Frequency
- **Monthly Backups**: We’ll schedule backups to run once a month, on the 1st day at midnight UTC, using a cron expression like `cron(0 0 1 * ? *)`. This ensures a consistent monthly snapshot for instances tagged `backup_plan: low`.

#### 2. Retention Period
- **3 Months (90 Days)**: Set retention to 90 days (`delete_after = 90`). 
  - **Why 90 Days?**: 
    - Monthly backups occur every ~30 days, so 90 days retains 3 backups (e.g., Month 1, Month 2, Month 3).
    - After 90 days, the oldest backup expires, and a new one is added, maintaining a rolling window of 3 monthly backups.
  - **RTO/RPO Context**: 
    - **RPO**: This gives an RPO of ~30 days (720 hours), as backups capture data monthly.
    - **RTO**: Assuming your 72-hour RTO applies, 90 days ensures backups are available far beyond the 72-hour recovery window.

#### 3. Vault and Selection
- **Backup Vault**: Create a new vault (e.g., `low-<random-id>`) to store monthly backups, keeping them separate from `high` and `medium`.
- **Resource Selection**: Use `backup_plan: low` to target specific EC2 instances, allowing flexibility to apply this plan to different or overlapping resources.

#### 4. Retention Strategy
- **Rolling Retention**: With `delete_after = 90`:
  - Day 1 (1st of Month 1): Backup 1 created, expires Day 91.
  - Day 31 (1st of Month 2): Backup 2 created, expires Day 121.
  - Day 61 (1st of Month 3): Backup 3 created, expires Day 151.
  - Day 91 (1st of Month 4): Backup 1 expires, Backup 4 created, expires Day 181.
- **Result**: After Day 61, you have 3 monthly backups (e.g., from the last 3 months), covering 90 days of history.

---

### Modified Terraform Script
Here’s the updated script adding `backup_plan: low` to your existing setup:

```hcl
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
```

---

### Key Additions and Explanations

1. **Monthly Schedule in Locals**:
   - Added `monthly_schedule_expression_map` with `cron(0 0 1 * ? *)` for the 1st of each month at midnight UTC.
   - Used `lookup` to set `monthly_schedule_expression`.
   - **Why**: Ensures monthly backups for `low` occur on a predictable schedule.

2. **Retention for Low**:
   - Added `monthly_delete_after = 90` in `locals`.
   - **Why**: Retains monthly backups for 90 days (3 months), providing 3 rolling backups.

3. **Low Backup Vault**:
   - Added `aws_backup_vault.low` with a name like `low-<random-id>`.
   - Tagged with `Purpose = "Monthly EC2 Backups"`.
   - **Why**: Separates monthly backups for clarity.

4. **Monthly Backup Plan**:
   - Added `aws_backup_plan.monthly_backup_plan` with:
     - `schedule = local.monthly_schedule_expression` (monthly on the 1st).
     - `delete_after = local.monthly_delete_after` (90 days).
     - Targets the `low` vault.
   - **Why**: Defines the monthly backup schedule and retention.

5. **Low Backup Selection**:
   - Added `aws_backup_selection.low_backup_selection`.
   - Targets `backup_plan: low` instances using the same IAM role.
   - **Why**: Links the plan to tagged instances.

6. **Outputs Updated**:
   - Included `low` vault ARN and monthly plan ID.

---

### How It Fits
- **Daily (`high`)**: Daily backups, 7-day retention, RPO 24 hours, RTO 72 hours.
- **Weekly (`medium`)**: Weekly backups, 28-day retention, RPO 7 days, RTO 72 hours.
- **Monthly (`low`)**: Monthly backups, 90-day retention, RPO ~30 days, RTO 72 hours.

---

### Next Steps
- **Tag Instances**: Add `backup_plan: low` to relevant EC2 instances.
- **Deploy**: Run `terraform apply` to create the resources.
- **Test**: Verify backups occur on the 1st of each month and expire after 90 days.
