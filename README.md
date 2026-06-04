# RBAC Changes Monitoring Automation

Automated Azure RBAC (Role-Based Access Control) changes tracking using a Logic App that generates monthly CSV reports and emails them to stakeholders.

## What It Does

- Queries Azure Activity Logs for all role assignment changes (adds, removes, PIM activations/eligibility)
- Generates a CSV report with details: who made the change, what role, which scope, when
- Flags privileged roles (Owner, Contributor, User Access Administrator)
- Emails the report to configured recipients on a schedule
- Sends a "No Changes" notification if no RBAC changes occurred

## Architecture

```
┌─────────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│ Azure Subscriptions │────▶│ Log Analytics         │────▶│ Logic App       │
│ (Activity Logs)     │     │ Workspace (KQL)       │     │ (Monthly Run)   │
└─────────────────────┘     └──────────────────────┘     └────────┬────────┘
                                                                   │
                                                          ┌────────▼────────┐
                                                          │ Email + CSV     │
                                                          │ (O365 Connector)│
                                                          └─────────────────┘
```

## Prerequisites

- Azure subscription with Activity Logs
- Log Analytics workspace
- Office 365 account for sending emails
- Subscription-level Diagnostic Setting routing Activity Logs to the workspace

## Quick Start

### 1. Configure

Edit `config/settings.json` with your Azure resource IDs, email recipients, and schedule.

### 2. Deploy

**PowerShell:**
```powershell
./deploy/Deploy-Automation.ps1 -ConfigPath "./config/settings.json"
```

**Ansible:**
```bash
ansible-playbook ansible/deploy.yml --tags all
```

**Azure CLI (direct):**
```bash
az deployment group create \
  --resource-group <RG_NAME> \
  --template-file arm/logic-app.json \
  --parameters logicAppName=<NAME> \
    logAnalyticsWorkspaceId=<WORKSPACE_RESOURCE_ID> \
    recipients=<EMAIL> \
    senderAddress=<SENDER>
```

### 3. Authorize Connections (one-time)

After deployment, authorize the Office 365 API connection in the Azure Portal:
- Portal → Resource Group → `office365` connection → Edit API connection → Authorize → Save

### 4. Test

```powershell
./deploy/Invoke-OnDemand.ps1
```

## Project Structure

```
├── arm/
│   └── logic-app.json          # ARM template (Logic App + O365 connection)
├── kql/
│   └── rbac-changes.kql        # KQL query (reference, for testing in portal)
├── config/
│   └── settings.json           # Configuration (update with your values)
├── deploy/
│   ├── Deploy-Automation.ps1   # PowerShell deployment script
│   └── Invoke-OnDemand.ps1     # Manual trigger script
├── ansible/
│   ├── deploy.yml              # Ansible deployment playbook
│   ├── trigger.yml             # Ansible manual trigger
│   └── vars/main.yml           # Ansible variables
├── .github/workflows/
│   └── deploy.yml              # GitHub Actions CI/CD workflow
└── docs/
    └── architecture.excalidraw # Architecture diagram
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| HTTP action + Managed Identity | Azure Monitor Logs connector doesn't support MI in Consumption Logic Apps |
| Case-insensitive KQL operators (`in~`, `=~`) | Activity Log `OperationNameValue` can arrive in ALL CAPS depending on environment |
| No `ResourceProvider` filter | Field is empty for role assignment events in some environments |
| Condition check before email | Prevents failure when CSV is empty (O365 rejects empty attachments) |

## RBAC Required

| Principal | Role | Scope |
|-----------|------|-------|
| Logic App Managed Identity | Log Analytics Reader | Log Analytics Workspace |
| Deployer | Contributor | Resource Group |
| (Diagnostic Setting) | N/A | Subscription-level setting |

## Tracked RBAC Operations

- `Microsoft.Authorization/roleAssignments/write` (direct assignment)
- `Microsoft.Authorization/roleAssignments/delete` (removal)
- `Microsoft.Authorization/roleAssignmentScheduleRequests/write` (PIM activation)
- `Microsoft.Authorization/roleEligibilityScheduleRequests/write` (PIM eligibility)
- `Microsoft.Authorization/elevateAccess/action` (global admin elevate)

## License

MIT
