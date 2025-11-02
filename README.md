# Azure Backup Management Scripts

This repository contains PowerShell scripts to automate Azure VM backup management and reporting. The scripts help you create test infrastructure with backup policies and generate comprehensive backup reports.

## 📋 Overview

The project consists of two main scripts:
- **`Create.ps1`** - Creates Azure infrastructure with backup protection (for testing/demo purposes)
- **`Report.ps1`** - Generates detailed backup reports from existing Azure backup vaults

## 🚀 Quick Start

### If you already have VMs with backups configured:
```powershell
.\Report.ps1
```
**This is the most common use case** - just run the report script to analyze your existing backup infrastructure.

### If you need to create test infrastructure:
```powershell
.\Create.ps1
```
**Only use this if you want to create new VMs and backup policies for testing purposes.**

## 📁 Files Structure

```
📦 AzureBackupScript/
├── 📄 config.json          # Configuration file
├── 📄 Create.ps1           # Infrastructure creation script
├── 📄 Report.ps1           # Backup reporting script
├── 📄 BackupReport.csv     # Generated report output
└── 📄 README.md           # This file
```

## ⚙️ Configuration

Edit `config.json` to match your environment:

```json
{
  "subscriptionId": "your-subscription-id",
  "resourceGroup": "your-resource-group",
  "location": "your-azure-region",
  "vaultName": "your-backup-vault-name",
  "reportPath": ".\\BackupReport.csv"
}
```

### Key Configuration Properties:
- **`subscriptionId`** - Your Azure subscription ID
- **`resourceGroup`** - Resource group containing your backup vault
- **`vaultName`** - Name of your Recovery Services Vault
- **`reportPath`** - Output path for the backup report CSV file

## 🔧 Script Details

### Create.ps1 - Infrastructure Creation

**Purpose**: Creates Azure VMs and configures backup protection for testing/demo scenarios.

**What it does**:
- ✅ Creates Azure VMs based on configuration
- ✅ Sets up Recovery Services Vault
- ✅ Configures backup policies
- ✅ Enables backup protection on VMs
- ✅ Triggers initial backup jobs

**Usage**:
```powershell
# Create infrastructure as defined in config.json
.\Create.ps1

# Force recreation of existing resources
.\Create.ps1 -Force
```

**⚠️ Important**: This script creates billable Azure resources. Only use for testing/demo purposes.

### Report.ps1 - Backup Reporting

**Purpose**: Generates comprehensive backup reports from existing Azure backup infrastructure.

**What it does**:
- 📊 Analyzes all protected VMs in the specified vault
- 📅 Retrieves last backup status and timestamps
- ⏱️ Shows backup duration and data size
- 🚨 Identifies failed backups with detailed error messages
- 📈 Provides backup health overview
- 💾 Exports detailed CSV report

**Usage**:
```powershell
# Generate backup report
.\Report.ps1
```

**Output**: Creates `BackupReport.csv` with detailed backup information for all protected VMs.

**📊 Excel Integration**: The generated CSV file can be directly imported into Microsoft Excel for advanced analysis, filtering, and visualization of your backup data.

## 📊 Report Contents

The generated CSV report includes comprehensive backup information that can be **imported directly into Microsoft Excel** for analysis:

| Column | Description |
|--------|-------------|
| **ServerName** | VM friendly name |
| **VirtualMachineId** | Full Azure resource ID |
| **ProtectionStatus** | Current protection status |
| **ProtectionState** | Detailed protection state |
| **LastBackupStatus** | Status of most recent backup |
| **LastBackupTime** | Timestamp of last backup (dd-MM-yyyy - HH:mm:ss) |
| **BackupStartTime** | Start time of backup job |
| **BackupEndTime** | End time of backup job |
| **BackupDuration** | Duration of backup job (hh:mm:ss) |
| **BackupSize** | Size of backup data |
| **FailureReason** | Detailed error information for failed backups |
| **PolicyName** | Applied backup policy |
| **HealthStatus** | Current health status |

## 🔐 Prerequisites

1. **Azure CLI** installed and configured
2. **PowerShell 5.1** or later
3. **Azure subscription** with appropriate permissions
4. **Recovery Services Vault** (for Report.ps1)

### Required Azure Permissions:
- Reader access to subscription/resource group
- Backup Reader role on Recovery Services Vault
- Virtual Machine Contributor (for Create.ps1 only)

## 🚀 Getting Started

1. **Clone or download** this repository
2. **Configure Azure CLI**:
   ```powershell
   az login
   az account set --subscription "your-subscription-id"
   ```
3. **Update `config.json`** with your environment details
4. **Run the appropriate script**:
   - For existing backups: `.\Report.ps1`
   - For new test infrastructure: `.\Create.ps1`

## 💡 Common Use Cases

### Scenario 1: Monitor Existing Backups
*You already have VMs with backup configured and want to monitor their status.*

```powershell
# Just run the report
.\Report.ps1
```

### Scenario 2: Create Test Environment
*You want to create a test environment with VMs and backup policies.*

```powershell
# Create infrastructure first
.\Create.ps1

# Then generate reports
.\Report.ps1
```

### Scenario 3: Regular Monitoring
*Set up automated reporting for ongoing backup monitoring.*

```powershell
# Schedule this to run daily/weekly
.\Report.ps1

# Check the generated BackupReport.csv for any issues
```

## 🔍 Troubleshooting

### Common Issues:

**Authentication Errors**:
```powershell
az login
az account set --subscription "your-subscription-id"
```

**No Backup Items Found**:
- Verify vault name and resource group in config.json
- Ensure VMs have backup protection enabled
- Check Azure permissions

**Script Execution Policy**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## 📝 Notes

- **Create.ps1** is primarily for **testing/demo purposes** - it creates billable Azure resources
- **Report.ps1** is for **production monitoring** - it only reads existing backup data
- The scripts use Azure CLI for authentication and API calls
- Reports are generated in **CSV format for easy import into Microsoft Excel** or other spreadsheet applications
- All timestamps are formatted as dd-MM-yyyy - HH:mm:ss for consistency

## 🤝 Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## 📄 License

This project is provided as-is for educational and testing purposes.

## ⚠️ Disclaimer

**IMPORTANT**: Although these scripts have been tested, they are **NOT recommended for use in production environments** without thorough testing and validation in your specific environment.

**No Warranty**: This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement.

**No Responsibility**: The authors and contributors of this project take **no responsibility** for any damage, data loss, service interruptions, or other issues that may arise from the use of these scripts. Use at your own risk.

**Production Use**: Before using these scripts in any production environment:
- Thoroughly test in a non-production environment
- Review and understand all code before execution
- Ensure proper backup and recovery procedures are in place
- Validate compatibility with your specific Azure environment and policies
- Consider having the scripts reviewed by your IT security and operations teams

**Your Responsibility**: It is your responsibility to ensure these scripts are suitable for your environment and comply with your organization's policies and procedures.