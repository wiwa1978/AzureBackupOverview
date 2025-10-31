# Load JSON config
$config = Get-Content -Path "C:\Users\wimwauters\OneDrive - Microsoft\CUSTOMERS\EUROFINS\AzureBackupScript\config.json" | ConvertFrom-Json

Write-Host "=== Azure Backup Report Generator ===" -ForegroundColor Green
Write-Host "Vault: $($config.vaultName)" -ForegroundColor Cyan
Write-Host "Resource Group: $($config.resourceGroup)" -ForegroundColor Cyan
Write-Host ""

# Login with Azure CLI
Write-Host "Connecting to Azure..."
az login

# Set subscription context
Write-Host "Setting subscription context..."
az account set --subscription $config.subscriptionId

# Get Backup Items
Write-Host "Retrieving backup items from vault '$($config.vaultName)'..."
$backupItemsJson = az backup item list --resource-group $config.resourceGroup --vault-name $config.vaultName --output json

if (-not $backupItemsJson -or $backupItemsJson -eq "[]") {
    Write-Host "Warning: No backup items found in vault '$($config.vaultName)'" -ForegroundColor Yellow
    Write-Host "Make sure you have VMs protected in this vault." -ForegroundColor Yellow
    exit
}

try {
    $backupItems = $backupItemsJson | ConvertFrom-Json
    Write-Host "Found $($backupItems.Count) backup item(s)" -ForegroundColor Green
} catch {
    Write-Host "Error parsing backup items data" -ForegroundColor Red
    exit 1
}

# Prepare Report Data
Write-Host "Generating backup report..."
$report = @()

foreach ($item in $backupItems) {
    # Get detailed backup job information for each item
    Write-Host "Processing: $($item.properties.friendlyName)..." -ForegroundColor Gray
    
    # Get recent backup jobs for this item
    $jobsJson = az backup job list --resource-group $config.resourceGroup --vault-name $config.vaultName --output json 2>$null
    $lastBackupStatus = "Unknown"
    $lastBackupTime = "Never"
    $backupStartTime = "Never"
    $backupEndTime = "Never"
    $backupDuration = "N/A"
    $backupSize = "N/A"
    $failureReason = ""
    
    if ($jobsJson -and $jobsJson -ne "[]") {
        try {
            $jobs = $jobsJson | ConvertFrom-Json
            
            # Find the most recent backup job for this VM
            $vmJobs = $jobs | Where-Object { 
                $_.properties.entityFriendlyName -eq $item.properties.friendlyName -and
                $_.properties.operation -eq "Backup" 
            } | Sort-Object { [DateTime]$_.properties.startTime } -Descending
            
            # Handle PowerShell array/single object behavior
            $jobCount = 0
            if ($vmJobs -ne $null) {
                if ($vmJobs -is [array]) {
                    $jobCount = $vmJobs.Count
                } else {
                    $jobCount = 1
                }
            }
            
            # If no exact match, try partial matching
            if ($jobCount -eq 0) {
                $vmJobs = $jobs | Where-Object { 
                    ($_.properties.entityFriendlyName -like "*$($item.properties.friendlyName)*" -or
                     $item.properties.friendlyName -like "*$($_.properties.entityFriendlyName)*") -and
                    $_.properties.operation -eq "Backup" 
                } | Sort-Object { [DateTime]$_.properties.startTime } -Descending
                
                # Recalculate job count for partial matches
                if ($vmJobs -ne $null) {
                    if ($vmJobs -is [array]) {
                        $jobCount = $vmJobs.Count
                    } else {
                        $jobCount = 1
                    }
                }
            }
            
            if ($vmJobs -and $jobCount -gt 0) {
                $latestJob = $vmJobs[0]
                $lastBackupStatus = $latestJob.properties.status
                
                # Format the main backup time to dd-mm-yyyy - hh:mm:ss
                try {
                    $backupDateTime = [DateTime]::Parse($latestJob.properties.startTime)
                    $lastBackupTime = $backupDateTime.ToString("dd-MM-yyyy - HH:mm:ss")
                } catch {
                    $lastBackupTime = $latestJob.properties.startTime
                }
                
                # Extract additional backup details
                $detailedJob = $null
                try {
                    # Start time
                    if ($latestJob.properties.startTime) {
                        $startDateTime = [DateTime]::Parse($latestJob.properties.startTime)
                        $backupStartTime = $startDateTime.ToString("dd-MM-yyyy - HH:mm:ss")
                    }
                    
                    # End time
                    if ($latestJob.properties.endTime) {
                        $endDateTime = [DateTime]::Parse($latestJob.properties.endTime)
                        $backupEndTime = $endDateTime.ToString("dd-MM-yyyy - HH:mm:ss")
                        
                        # Calculate duration
                        $duration = $endDateTime - $startDateTime
                        $backupDuration = "{0:hh\:mm\:ss}" -f $duration
                    }
                    
                    # Backup size - first try basic job info
                    if ($latestJob.properties.extendedInfo -and $latestJob.properties.extendedInfo.propertyBag) {
                        $propertyBag = $latestJob.properties.extendedInfo.propertyBag
                        if ($propertyBag.'Backup Size') {
                            $backupSize = $propertyBag.'Backup Size'
                        } elseif ($propertyBag.'Transfer Size') {
                            $backupSize = $propertyBag.'Transfer Size'
                        }
                    }
                    
                    # If backup size not found in basic info, fetch detailed job information
                    if ($backupSize -eq "N/A") {
                        try {
                            $jobId = $latestJob.name
                            Write-Host "  Fetching detailed job info: $jobId" -ForegroundColor Gray
                            $detailedJobJson = az backup job show --resource-group $config.resourceGroup --vault-name $config.vaultName --name $jobId --output json 2>$null
                            
                            if ($detailedJobJson) {
                                $detailedJob = $detailedJobJson | ConvertFrom-Json
                                if ($detailedJob.properties.extendedInfo -and $detailedJob.properties.extendedInfo.propertyBag) {
                                    $detailedPropertyBag = $detailedJob.properties.extendedInfo.propertyBag
                                    if ($detailedPropertyBag.'Backup Size') {
                                        $backupSize = $detailedPropertyBag.'Backup Size'
                                    } elseif ($detailedPropertyBag.'Transfer Size') {
                                        $backupSize = $detailedPropertyBag.'Transfer Size'
                                    }
                                }
                            }
                        } catch {
                            Write-Host "  Warning: Could not fetch detailed job info for backup size" -ForegroundColor Yellow
                        }
                    }
                } catch {
                    Write-Host "Warning: Could not parse extended backup details for $($item.properties.friendlyName)" -ForegroundColor Yellow
                }
                
                # Get comprehensive failure reason if backup failed
                if ($lastBackupStatus -eq "Failed" -or $lastBackupStatus -eq "CompletedWithWarnings") {
                    $errorCode = ""
                    $errorTitle = ""
                    $errorMessage = ""
                    
                    # If we haven't fetched detailed job info yet, fetch it now for error details
                    if (-not $detailedJob) {
                        try {
                            $jobId = $latestJob.name
                            Write-Host "  Fetching detailed error info for job: $jobId" -ForegroundColor Gray
                            $detailedJobJson = az backup job show --resource-group $config.resourceGroup --vault-name $config.vaultName --name $jobId --output json 2>$null
                            
                            if ($detailedJobJson) {
                                $detailedJob = $detailedJobJson | ConvertFrom-Json
                            }
                        } catch {
                            Write-Host "  Warning: Could not fetch detailed job info" -ForegroundColor Yellow
                        }
                    }
                    
                    # Extract error details from detailed job info
                    if ($detailedJob -and $detailedJob.properties.errorDetails -and $detailedJob.properties.errorDetails.Count -gt 0) {
                        $errorDetail = $detailedJob.properties.errorDetails[0]
                        if ($errorDetail.errorCode) {
                            $errorCode = $errorDetail.errorCode
                        }
                        if ($errorDetail.errorTitle) {
                            $errorTitle = $errorDetail.errorTitle
                        }
                        if ($errorDetail.errorString) {
                            $errorMessage = $errorDetail.errorString
                        }
                    }
                    
                    # Fallback to basic job error details if detailed fetch failed
                    if (-not $errorCode -and -not $errorTitle -and -not $errorMessage) {
                        if ($latestJob.properties.errorDetails -and $latestJob.properties.errorDetails.Count -gt 0) {
                            $errorDetail = $latestJob.properties.errorDetails[0]
                            if ($errorDetail.errorCode) {
                                $errorCode = $errorDetail.errorCode
                            }
                            if ($errorDetail.errorTitle) {
                                $errorTitle = $errorDetail.errorTitle
                            }
                            if ($errorDetail.errorString) {
                                $errorMessage = $errorDetail.errorString
                            }
                        }
                    }
                    
                    # Build comprehensive failure reason with priority: errorString > errorTitle > errorCode
                    if ($errorMessage) {
                        if ($errorTitle) {
                            $failureReason = "$errorMessage ($errorTitle)"
                        } else {
                            $failureReason = $errorMessage
                        }
                        if ($errorCode) {
                            $failureReason += " [Code: $errorCode]"
                        }
                    } elseif ($errorTitle) {
                        if ($errorCode) {
                            $failureReason = "$errorTitle (Code: $errorCode)"
                        } else {
                            $failureReason = $errorTitle
                        }
                    } elseif ($errorCode) {
                        $failureReason = "Error Code: $errorCode"
                    } else {
                        $failureReason = "Backup failed - No detailed error information available"
                    }
                    
                    # Truncate if too long (increase limit for more detail)
                    if ($failureReason.Length -gt 300) {
                        $failureReason = $failureReason.Substring(0, 297) + "..."
                    }
                }
            }
        } catch {
            Write-Host "Warning: Could not parse job data for $($item.properties.friendlyName)"
        }
    }
    
    # Create report entry
    $reportEntry = [PSCustomObject]@{
        ServerName = $item.properties.friendlyName
        VirtualMachineId = $item.properties.virtualMachineId
        ProtectionStatus = $item.properties.protectionStatus
        ProtectionState = $item.properties.protectionState
        LastBackupStatus = $lastBackupStatus
        LastBackupTime = $lastBackupTime
        BackupStartTime = $backupStartTime
        BackupEndTime = $backupEndTime
        BackupDuration = $backupDuration
        BackupSize = $backupSize
        FailureReason = $failureReason
        PolicyName = $item.properties.policyName
        BackupManagementType = $item.properties.backupManagementType
        WorkloadType = $item.properties.workloadType
        ContainerName = $item.properties.containerName
        HealthStatus = if ($item.properties.healthStatus) { $item.properties.healthStatus } else { "N/A" }
    }
    
    $report += $reportEntry
}

# Display Report Summary
Write-Host ""
Write-Host "=== BACKUP REPORT SUMMARY ===" -ForegroundColor Green
Write-Host "Total Protected VMs: $($report.Count)" -ForegroundColor Cyan

$report | ForEach-Object {
    Write-Host ""
    Write-Host "VM: $($_.ServerName)" -ForegroundColor White
    Write-Host "   Status: $($_.ProtectionStatus) / $($_.ProtectionState)" -ForegroundColor Gray
    Write-Host "   Last Backup: $($_.LastBackupTime) [$($_.LastBackupStatus)]" -ForegroundColor Gray
    if ($_.BackupStartTime -ne "Never") {
        Write-Host "   Start Time: $($_.BackupStartTime)" -ForegroundColor Gray
    }
    if ($_.BackupEndTime -ne "Never") {
        Write-Host "   End Time: $($_.BackupEndTime)" -ForegroundColor Gray
    }
    if ($_.BackupDuration -ne "N/A") {
        Write-Host "   Duration: $($_.BackupDuration)" -ForegroundColor Gray
    }
    if ($_.BackupSize -ne "N/A") {
        Write-Host "   Backup Size: $($_.BackupSize)" -ForegroundColor Gray
    }
    if ($_.FailureReason -and $_.FailureReason -ne "") {
        Write-Host "   Failure Reason: $($_.FailureReason)" -ForegroundColor Red
    }
    Write-Host "   Policy: $($_.PolicyName)" -ForegroundColor Gray
    Write-Host "   Health: $($_.HealthStatus)" -ForegroundColor Gray
}

# Export to CSV
Write-Host ""
Write-Host "Exporting report to: $($config.reportPath)" -ForegroundColor Yellow
try {
    $report | Export-Csv -Path $config.reportPath -NoTypeInformation -Encoding UTF8
    Write-Host "Report exported successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Report contains the following columns:"
    Write-Host "   - ServerName: VM friendly name"
    Write-Host "   - VirtualMachineId: Full Azure resource ID"
    Write-Host "   - ProtectionStatus: Current protection status"
    Write-Host "   - ProtectionState: Detailed protection state"
    Write-Host "   - LastBackupStatus: Status of most recent backup"
    Write-Host "   - LastBackupTime: Timestamp of most recent backup (dd-MM-yyyy - HH:mm:ss)"
    Write-Host "   - BackupStartTime: Start time of the backup job"
    Write-Host "   - BackupEndTime: End time of the backup job"
    Write-Host "   - BackupDuration: Duration of the backup job (hh:mm:ss)"
    Write-Host "   - BackupSize: Size of the backup data"
    Write-Host "   - FailureReason: Error details for failed backups"
    Write-Host "   - PolicyName: Backup policy applied"
    Write-Host "   - BackupManagementType: Type of backup management"
    Write-Host "   - WorkloadType: Type of workload being backed up"
    Write-Host "   - ContainerName: Azure backup container name"
    Write-Host "   - HealthStatus: Current health status"
} catch {
    Write-Host "Error exporting report: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== REPORT GENERATION COMPLETE ===" -ForegroundColor Green