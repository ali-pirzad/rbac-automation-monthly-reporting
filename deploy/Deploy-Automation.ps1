<#
.SYNOPSIS
    Deploys the RBAC Changes Reporting Logic App via ARM template.
.DESCRIPTION
    Alternative to the Ansible playbook for environments without Ansible.
    Deploys:
    1. Resource Group
    2. Logic App (ARM template)
    3. Configures Diagnostic Settings on subscriptions
.NOTES
    After deployment, you must authorize the API connections in the Azure Portal.
.EXAMPLE
    .\Deploy-Automation.ps1
    .\Deploy-Automation.ps1 -ConfigPath "..\config\settings.json"
#>

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\config\settings.json")
)

$ErrorActionPreference = "Stop"

#region --- Load Config ---
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rgName = $config.resourceGroup
$location = $config.location
$logicAppName = $config.logicAppName
$workspaceResourceId = $config.logAnalyticsWorkspaceResourceId
$recipients = $config.recipients -join ';'
$senderAddress = $config.senderAddress
$lookbackDays = $config.lookbackDays
$subscriptions = $config.subscriptions
Write-Host "Configuration loaded." -ForegroundColor Cyan
#endregion

#region --- Verify Connection ---
$context = Get-AzContext
if (-not $context) {
    Write-Host "No Az context found, attempting az CLI login check..." -ForegroundColor Yellow
    $azAccount = az account show 2>$null | ConvertFrom-Json
    if (-not $azAccount) {
        throw "Not logged in to Azure. Run 'Connect-AzAccount' or 'az login' first."
    }
    Write-Host "Connected via az CLI as: $($azAccount.user.name)" -ForegroundColor Green
} else {
    Write-Host "Connected as: $($context.Account.Id)" -ForegroundColor Green
}
#endregion

#region --- Create Resource Group ---
Write-Host "`n[1/3] Creating Resource Group: $rgName..." -ForegroundColor Cyan
New-AzResourceGroup -Name $rgName -Location $location -Force | Out-Null
Write-Host "  Done." -ForegroundColor Green
#endregion

#region --- Deploy Logic App ARM Template ---
Write-Host "[2/3] Deploying Logic App ARM template..." -ForegroundColor Cyan
$templatePath = Join-Path $PSScriptRoot "..\arm\logic-app.json"

$params = @{
    logicAppName              = $logicAppName
    location                  = $location
    logAnalyticsWorkspaceId   = $workspaceResourceId
    recipients                = $recipients
    senderAddress             = $senderAddress
    lookbackDays              = $lookbackDays
    recurrenceFrequency       = $config.recurrence.frequency
    recurrenceInterval        = $config.recurrence.interval
    recurrenceStartTime       = $config.recurrence.startTime
}

New-AzResourceGroupDeployment -ResourceGroupName $rgName `
    -TemplateFile $templatePath `
    -TemplateParameterObject $params `
    -Name "rbac-report-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
    -ErrorAction Stop | Out-Null

Write-Host "  Logic App deployed." -ForegroundColor Green
#endregion

#region --- Configure Diagnostic Settings ---
Write-Host "[3/3] Configuring Diagnostic Settings on subscriptions..." -ForegroundColor Cyan

foreach ($sub in $subscriptions) {
    Write-Host "  Subscription: $($sub.name) ($($sub.id))..." -ForegroundColor Gray
    try {
        $diagExists = az monitor diagnostic-settings subscription show `
            --name "route-activity-to-central-la" `
            --subscription $sub.id 2>$null

        if (-not $diagExists) {
            az monitor diagnostic-settings subscription create `
                --name "route-activity-to-central-la" `
                --subscription $sub.id `
                --workspace $workspaceResourceId `
                --logs "[{""category"":""Administrative"",""enabled"":true},{""category"":""Security"",""enabled"":true}]" | Out-Null
            Write-Host "    Diagnostic settings created." -ForegroundColor Green
        }
        else {
            Write-Host "    Already configured." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "    Failed for subscription $($sub.id): $_"
    }
}
#endregion

#region --- Post-Deployment Instructions ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "REQUIRED: Authorize API connections (one-time, interactive):" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Log Analytics connection:" -ForegroundColor White
Write-Host "     Portal > Resource Group '$rgName' > 'azuremonitorlogs' > Edit API connection > Authorize > Save"
Write-Host ""
Write-Host "  2. Office 365 connection:" -ForegroundColor White
Write-Host "     Portal > Resource Group '$rgName' > 'office365' > Edit API connection > Authorize > Save"
Write-Host ""
Write-Host "After authorizing, test with:" -ForegroundColor Yellow
Write-Host "  .\Invoke-OnDemand.ps1"
Write-Host ""
Write-Host "Or via Azure CLI:" -ForegroundColor Yellow
Write-Host "  az logic workflow run trigger -g $rgName -n $logicAppName --trigger-name Recurrence"
Write-Host "========================================" -ForegroundColor Cyan
#endregion

exit 0
