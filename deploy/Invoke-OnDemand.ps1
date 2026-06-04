<#
.SYNOPSIS
    Trigger the RBAC Changes Report Logic App on-demand (for demos/testing).
.DESCRIPTION
    Multiple methods to trigger the report manually:
    1. PowerShell (this script) - triggers the Logic App run
    2. Azure CLI
    3. Ansible playbook
    4. Azure Portal (click)

.EXAMPLE
    # Trigger via PowerShell (default)
    .\Invoke-OnDemand.ps1

    # With specific resource group / logic app name
    .\Invoke-OnDemand.ps1 -ResourceGroup "rg-rbac-reporting" -LogicAppName "la-rbac-changes-report"
#>

param(
    [string]$ResourceGroup = "",
    [string]$LogicAppName = "",
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\config\settings.json")
)

$ErrorActionPreference = "Stop"

#region --- Load Config ---
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if (-not $ResourceGroup) { $ResourceGroup = $config.resourceGroup }
    if (-not $LogicAppName) { $LogicAppName = $config.logicAppName }
}

if (-not $ResourceGroup -or -not $LogicAppName) {
    throw "ResourceGroup and LogicAppName are required. Set in config/settings.json or pass as parameters."
}
#endregion

#region --- Verify Connection ---
$context = Get-AzContext
if (-not $context) {
    Connect-AzAccount
    $context = Get-AzContext
}
Write-Host "Connected as: $($context.Account.Id)" -ForegroundColor Green
#endregion

#region --- Trigger Logic App ---
Write-Host ""
Write-Host "Triggering Logic App..." -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host "  Logic App:      $LogicAppName" -ForegroundColor Gray
Write-Host ""

try {
    # Get the trigger callback URL and invoke it
    $trigger = Get-AzLogicAppTriggerCallbackUrl -ResourceGroupName $ResourceGroup `
        -Name $LogicAppName -TriggerName "Recurrence" -ErrorAction Stop

    Invoke-RestMethod -Uri $trigger.Value -Method POST -ErrorAction Stop
    Write-Host "Logic App triggered successfully!" -ForegroundColor Green
    Write-Host "The report will be generated and emailed shortly." -ForegroundColor Green
}
catch {
    # Fallback: use Start-AzLogicApp
    Write-Host "  Trying alternative trigger method..." -ForegroundColor Yellow
    try {
        Start-AzLogicApp -ResourceGroupName $ResourceGroup -Name $LogicAppName `
            -TriggerName "Recurrence" -ErrorAction Stop
        Write-Host "Logic App triggered successfully!" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to trigger Logic App: $_"
        throw
    }
}
#endregion

#region --- Show All Manual Trigger Options ---
Write-Host ""
Write-Host "===== All Manual Trigger Options =====" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. PowerShell (this script):" -ForegroundColor White
Write-Host "   .\Invoke-OnDemand.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Azure CLI:" -ForegroundColor White
Write-Host "   az logic workflow run trigger -g $ResourceGroup -n $LogicAppName --trigger-name Recurrence" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Ansible:" -ForegroundColor White
Write-Host "   ansible-playbook ansible/trigger.yml" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Azure Portal:" -ForegroundColor White
Write-Host "   Logic App > Overview > Run Trigger > Recurrence" -ForegroundColor Gray
Write-Host ""
Write-Host "5. REST API (curl/Invoke-RestMethod):" -ForegroundColor White
Write-Host "   POST https://management.azure.com/subscriptions/{sub}/resourceGroups/$ResourceGroup/providers/Microsoft.Logic/workflows/$LogicAppName/triggers/Recurrence/run?api-version=2019-05-01" -ForegroundColor Gray
Write-Host "=========================================" -ForegroundColor Cyan
#endregion
