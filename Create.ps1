param(
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Load JSON config
$config = Get-Content -Path "C:\Users\wimwauters\OneDrive - Microsoft\CUSTOMERS\EUROFINS\AzureBackupScript\config.json" | ConvertFrom-Json

# Generate VM list based on config parameters
$vmsToProcess = @()
for ($i = 0; $i -lt $config.vmCount; $i++) {
    $vmNumber = $config.vmStartNumber + $i
    $vmName = "$($config.vmNamePrefix)-$vmNumber"
    $vmsToProcess += @{
        vmName = $vmName
        image = $config.vmConfig.image
        adminUsername = $config.vmConfig.adminUsername
        size = $config.vmConfig.size
    }
}

Write-Host "=== VM Configuration ===" -ForegroundColor Cyan
Write-Host "Will process $($config.vmCount) VMs:" -ForegroundColor Yellow
foreach ($vm in $vmsToProcess) {
    Write-Host "  - $($vm.vmName)" -ForegroundColor Gray
}
Write-Host ""

# Login with Azure CLI
az login

# Set subscription context
az account set --subscription $config.subscriptionId

# CREATION LOGIC ONLY
Write-Host "=== CREATION MODE ===" -ForegroundColor Green

# Create Resource Group
$rgExists = az group show --name $config.resourceGroup 2>$null
if (-not $rgExists) {
    Write-Host "Creating Resource Group..."
    az group create --name $config.resourceGroup --location $config.location
} else {
    Write-Host "Resource Group already exists, skipping creation..."
}

# Create VMs
$createdVMs = @()
$existingVMs = @()

foreach ($vm in $vmsToProcess) {
    $vmExists = az vm show --name $vm.vmName --resource-group $config.resourceGroup 2>$null
    if (-not $vmExists) {
        Write-Host "Creating VM '$($vm.vmName)'..."
        az vm create `
          --resource-group $config.resourceGroup `
          --name $vm.vmName `
          --image $vm.image `
          --admin-username $vm.adminUsername `
          --size $vm.size `
          --generate-ssh-keys
        $createdVMs += $vm.vmName
        Write-Host "VM '$($vm.vmName)' created successfully"
    } else {
        Write-Host "VM '$($vm.vmName)' already exists, skipping creation..."
        $existingVMs += $vm.vmName
    }
}

# Create Recovery Services Vault
$vaultExists = az backup vault show --name $config.vaultName --resource-group $config.resourceGroup 2>$null
if (-not $vaultExists) {
    Write-Host "Creating Recovery Services Vault..."
    az backup vault create `
      --resource-group $config.resourceGroup `
      --name $config.vaultName `
      --location $config.location
} else {
    Write-Host "Recovery Services Vault already exists, skipping creation..."
}

# Enable Backup Protection
Write-Host ""
Write-Host "=== CONFIGURING BACKUP PROTECTION ===" -ForegroundColor Cyan
$protectedItems = az backup item list --resource-group $config.resourceGroup --vault-name $config.vaultName --output json 2>$null

$protectedVMs = @()
$unprotectedVMs = @()

foreach ($vm in $vmsToProcess) {
    Write-Host "Checking protection status for VM '$($vm.vmName)'..."
    $vmAlreadyProtected = $false
    
    if ($protectedItems -and $protectedItems -ne "[]") {
        $items = $protectedItems | ConvertFrom-Json
        $vmProtected = $items | Where-Object { 
            $_.properties.friendlyName -eq $vm.vmName -or 
            $_.properties.virtualMachineId -like "*/$($vm.vmName)" 
        }
        if ($vmProtected) {
            $vmAlreadyProtected = $true
            $protectedVMs += $vm.vmName
            Write-Host "VM '$($vm.vmName)' is already protected"
        }
    }
    
    if (-not $vmAlreadyProtected) {
        $unprotectedVMs += $vm.vmName
        Write-Host "Enabling backup protection for VM '$($vm.vmName)'..."
        az backup protection enable-for-vm `
          --resource-group $config.resourceGroup `
          --vault-name $config.vaultName `
          --vm $vm.vmName `
          --policy-name DefaultPolicy
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Backup protection enabled for VM '$($vm.vmName)'"
        } else {
            Write-Host "Protection enable had warnings for VM '$($vm.vmName)'"
        }
    }
}

# Trigger Initial Backups
Write-Host ""
Write-Host "=== TRIGGERING INITIAL BACKUPS ===" -ForegroundColor Cyan

if ($unprotectedVMs.Count -gt 0) {
    Write-Host "Waiting 30 seconds for backup protection to be configured..."
    Start-Sleep -Seconds 30
}

$allBackupResults = @{}

    foreach ($vm in $vmsToProcess) {
    Write-Host ""
    Write-Host "Processing backup for VM '$($vm.vmName)'..." -ForegroundColor Yellow
    
    $backupSucceeded = $false
    $maxAttempts = 3
    
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Host "  Backup attempt $attempt of $maxAttempts for VM '$($vm.vmName)'..."
        
        az backup protection backup-now `
          --resource-group $config.resourceGroup `
          --vault-name $config.vaultName `
          --container-name "iaasvmcontainerv2;$($config.resourceGroup);$($vm.vmName)" `
          --item-name $vm.vmName `
          --retain-until $config.backupRetainUntil `
          --output json
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Backup job initiated successfully for VM '$($vm.vmName)'!" -ForegroundColor Green
            $backupSucceeded = $true
            $allBackupResults[$vm.vmName] = "Success"
            break
        } else {
            Write-Host "  Attempt $attempt failed for VM '$($vm.vmName)'" -ForegroundColor Yellow
            if ($attempt -lt $maxAttempts) {
                Write-Host "  Waiting 15 seconds before retry..."
                Start-Sleep -Seconds 15
            }
        }
    }
    
    if (-not $backupSucceeded) {
        Write-Host "  Could not trigger backup for VM '$($vm.vmName)' after $maxAttempts attempts" -ForegroundColor Red
        $allBackupResults[$vm.vmName] = "Failed"
    }
}

# Final Summary
Write-Host ""
Write-Host "=== BACKUP RESULTS SUMMARY ===" -ForegroundColor Cyan
$successfulBackups = ($allBackupResults.GetEnumerator() | Where-Object { $_.Value -eq "Success" }).Count
$failedBackups = ($allBackupResults.GetEnumerator() | Where-Object { $_.Value -eq "Failed" }).Count

Write-Host "Successful backups: $successfulBackups/$($vmsToProcess.Count)" -ForegroundColor Green
Write-Host "Failed backups: $failedBackups/$($vmsToProcess.Count)" -ForegroundColor $(if ($failedBackups -gt 0) { "Red" } else { "Green" })

Write-Host ""
Write-Host "=== SCRIPT COMPLETION SUMMARY ===" -ForegroundColor Green
Write-Host "Resource Group: $($config.resourceGroup) - $(if($rgExists) { 'Already existed' } else { 'Created' })"
Write-Host "Recovery Vault: $($config.vaultName) - $(if($vaultExists) { 'Already existed' } else { 'Created' })"
Write-Host ""
Write-Host "VMs Summary:"
foreach ($vm in $vmsToProcess) {
    $status = if ($vm.vmName -in $createdVMs) { "Created" } else { "Already existed" }
    $backupStatus = $allBackupResults[$vm.vmName]
    $backupIcon = if ($backupStatus -eq "Success") { "Success" } else { "Warning" }
    Write-Host "   - $($vm.vmName): $status | Backup: $backupIcon $backupStatus"
}

Write-Host ""
Write-Host "Script Usage Examples:"
Write-Host "   .\create_infra_v3.ps1                    # Create resources"