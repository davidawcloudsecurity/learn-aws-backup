# learn-aws-backup
how to deploy backup for aws resources

In the provided Terraform script, the terms "low," "medium," and "high" appear to be used to categorize backup vaults and plans based on their priority or importance. This categorization can be mapped to different backup frequencies like daily, monthly, and yearly, but the exact mapping is not explicitly defined in the script.

### Mapping Low, Medium, and High to Daily, Monthly, and Yearly

Here's a possible interpretation:

- **High Priority**: Daily Backups
  - Frequent backups to ensure minimal data loss.
  - Shorter retention period (e.g., 7 days).
  - Example: Critical data that changes frequently.

- **Medium Priority**: Monthly Backups
  - Regular backups with a moderate retention period.
  - Example: Important but less frequently changing data.

- **Low Priority**: Yearly Backups
  - Infrequent backups with a long retention period.
  - Example: Archived data or data required for long-term compliance.

### Explanation:
- **Variables and Locals:** Define the deployment environment and local variables for schedules and retention periods.
- **Backup Vaults:** Create vaults to store backups, categorized as high, medium, and low priority.
- **Policies:** Set up policies to prevent accidental deletion of vaults.
- **Backup Plans:** Create plans to schedule daily (high priority), monthly (medium priority), and yearly (low priority) backups.
- **Selections:** Use tags to specify which resources (e.g., EC2 instances, RDS databases) should be backed up according to the defined plans.

### Specifying Resources for Backup with Tags
To specify which EC2 instances or RDS databases to back up, you need to tag them appropriately. For example:

#### EC2 Instance:
```hcl
resource "aws_instance" "example" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  
  tags = {
    Name        = "example-instance"
    backup_plan = "High"  # Tag for high priority backup
  }
}
```

#### RDS Database:
```hcl
resource "aws_db_instance" "example" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = "exampledb"
  username             = "foo"
  password             = "bar"
  parameter_group_name = "default.mysql5.7"
  
  tags = {
    Name        = "example-database"
    backup_plan = "Medium"  # Tag for medium priority backup
  }
}
```

By tagging your resources and using the `aws_backup_selection` resource, you can specify which EC2 instances and RDS databases to back up according to your backup plans.
