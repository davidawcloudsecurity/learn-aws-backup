Here’s the updated Terraform script with changes tailored to your needs:

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
```

---

### Key Changes and Explanations

1. **Simplified to Daily Backup Only**:
   - **Why**: Your requirement is an RPO of 24 hours (daily backups) and RTO of 72 hours. I removed the monthly and yearly plans/vaults from your original script to focus solely on the daily backup plan that meets your needs.
   - **Change**: Kept only `aws_backup_vault.high`, `aws_backup_plan.daily_backup_plan`, and `aws_backup_selection.high_backup_selection`.

2. **Retention Adjusted**:
   - **Original**: `daily_delete_after = 120` (120 days).
   - **New**: `daily_delete_after = 7` (7 days).
   - **Why**: Your RTO of 72 hours (3 days) means you need backups available for at least 3 days to recover. A 7-day retention ensures you have a week’s worth of backups, giving you a buffer beyond the 72-hour recovery window. You can increase this (e.g., 14 or 30 days) if you want more history, but 7 days is sufficient and cost-effective.

3. **Schedule**:
   - **Kept**: `cron(0 0 * * ? *)` (midnight UTC daily).
   - **Why**: This meets your RPO of 24 hours by taking a backup every 24 hours. The `daily_schedule_expression_map` allows flexibility across environments (dev, staging, prod), defaulting to midnight UTC if unspecified.

4. **Tagging**:
   - **Kept**: `backup_plan: high` in `aws_backup_selection`.
   - **Why**: Matches your earlier confirmation to tag EC2 instances with `backup_plan: high`. This ensures only those instances (and all their EBS volumes) are backed up.

5. **Removed Unused Features**:
   - **Cold Storage**: Removed `cold_storage_after` settings since your RTO of 72 hours implies quick access to backups, and warm storage (default) is faster for restores.
   - **Vault Policies**: Removed `aws_backup_vault_policy` resources as they’re only applied in staging and not critical for your basic setup.
   - **Other Plans**: Dropped monthly and yearly plans/vaults to streamline the script.

6. **IAM Role**:
   - **Kept**: `aws_iam_role.role_backup` with both Backup and Restore policies.
   - **Why**: AWS Backup needs permissions to create snapshots (Backup policy) and restore them (Restore policy) for your EC2 EBS volumes.

7. **Outputs**:
   - **Simplified**: Reduced to key resources (vault ARN, plan ID, role ARN) for easy reference after deployment.

---

### How This Meets Your Requirements
- **RPO of 24 hours**: The `daily_schedule_expression` (`cron(0 0 * * ? *)`) triggers a backup every 24 hours, ensuring no more than 24 hours of data loss.
- **RTO of 72 hours**: The `delete_after = 7` days keeps backups for a week, giving you well beyond 72 hours to initiate and complete a restore. Restoring an EBS snapshot typically takes minutes to hours, fitting comfortably within your 72-hour window.
- **EC2 Instances**: The `selection_tag` targets all EBS volumes of instances tagged `backup_plan: high`, covering your RHEL and Windows instances.

---

### How to Use This Script
1. **Save the Script**: Save it as `main.tf` in a Terraform directory.
2. **Initialize Terraform**:
   ```bash
   terraform init
   ```
3. **Set Variables**: Create a `terraform.tfvars` file or pass variables inline:
   ```hcl
   environment = "prod"  # Adjust to dev, staging, or prod
   tags = {
     Owner = "YourName"
   }
   ```
4. **Apply**:
   ```bash
   terraform apply
   ```
   - Review the plan and confirm to deploy.

5. **Tag Your EC2 Instances**:
   - Manually via AWS Console: Add `backup_plan: high` to your RHEL and Windows instances (as done in Step 1).
   - Or with Terraform: Add an `aws_ec2_tag` resource if you want to manage tags here (let me know if you need this).

---

### Validation
- This uses AWS Backup’s Terraform resources as documented in the Terraform AWS Provider (e.g., `aws_backup_plan`, `aws_backup_selection`).
- Cron expressions and retention settings align with AWS Backup’s capabilities (per AWS documentation as of February 26, 2025).
