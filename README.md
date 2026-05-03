# IntuneStack

> Modern Intune configuration management with progressive deployment rings and automated success gates.

> [!WARNING]
> This project is provided for testing and educational purposes. Use at your own risk. This is a foundational framework that should be thoroughly tested in your own development environment before any production use. Always review and understand the code before running it against your Intune tenant.

IntuneStack provides CI/CD orchestration for Intune policy deployment — adding progressive group deployment, automated success criteria evaluation, and OIDC-enabled CI/CD pipeline to operationalize through deployment rings (dev → test → prod).

> [!NOTE]
> This is the foundation of IntuneStack's deployment orchestration capabilities. This is a living project that will continue to evolve based on real-world usage.


## Key Features

- **Progressive Deployment Rings**: Automated dev → test → prod group promotion with configurable success gates
- **Automated Promotion**: Promotion based on device counts, success rates, and error thresholds
- **PR-Driven Promotion**: Open a pull request with policy details to trigger the promotion pipeline
- **OIDC Authentication**: Secure GitHub Actions integration with Azure App Registration — no stored credentials
- **Code Quality Gates**: PSScriptAnalyzer runs on every PR and blocks merge on errors
- **Self-Updating Module**: Automatically syncs with the latest version from GitHub on import


## Security & Privacy

This repository is configured to protect sensitive tenant information:

- Code quality and unit test results are uploaded as artifacts — no sensitive data
- Integration test results are not uploaded as artifacts — they contain real Intune tenant data
- All integration test results are available in GitHub Actions workflow logs only
- Fork pull requests cannot create artifacts
- Artifacts are retained for 7 days only

**Why this matters**: Integration tests connect to your real Intune tenant and may contain tenant IDs, policy names and assignments, group names and membership information, and device deployment statistics. By not uploading these as artifacts, sensitive information stays private even in a public repository.


## Project Structure

```
IntuneStack/                                        # repo root
├── README.md
├── Install-IntuneStack.ps1                         # One-line installation script
│
├── .github/
│   └── workflows/
│       ├── policy-promotion.yml                    # Promotion pipeline
│       └── pr-validation.yml                       # PR quality gate
│
├── IntuneStack.psd1                                # Module manifest
├── IntuneStack.psm1                                # Module loader and self-update
│
├── Public/                                         # Public functions
│   ├── Write-Log.ps1
│   ├── Connect-ToGraph.ps1
│   ├── Get-EntraGroup.ps1
│   ├── Get-DeviceConfigurationPolicy.ps1
│   ├── Get-DeviceConfigurationPolicyAssignment.ps1
│   ├── Get-DeviceConfigurationPolicyStatus.ps1
│   ├── Add-DeviceConfigurationPolicyAssignment.ps1
│   └── Start-PolicyPromotionAnalysis.ps1
│
├── src/
│   └── Invoke-CodeQuality.ps1
│
└── tests/
    └── PolicyPromotionAnalysis.Tests.ps1
```


## Quick Start

### Prerequisites

- Azure App Registration with OIDC configured for GitHub Actions
- PowerShell 7.1+
- Microsoft Graph Authentication module (automatically validated on import)
- Git (for installation and self-update)

### Installation

```powershell
Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/AllwaysHyPe/IntuneStack/main/Install-IntuneStack.ps1')
```

This will install Git if not present, clone the repository, and create a symbolic link in your PowerShell module path so `Import-Module IntuneStack` works from any session.

### Self-Updating

IntuneStack checks for updates automatically every time you import it:

```powershell
Import-Module IntuneStack
# IntuneStack update detected — downloading latest version...
# Reload your PowerShell session to apply the update.
```


## Setup

### App Registration

Create an App Registration with the following Graph API permissions:

```
DeviceManagementConfiguration.Read.All
DeviceManagementConfiguration.ReadWrite.All
Directory.Read.All
Policy.Read.All
Policy.ReadWrite.ConditionalAccess
```

### Configure OIDC for GitHub Actions

In your Azure App Registration go to **Certificates & secrets** → **Federated credentials** and add a credential for GitHub Actions. Set your organization, repository name, entity type to Branch, and branch name to `main`.

### GitHub Secrets and Variables

In your repository go to **Settings** → **Secrets and variables** → **Actions**.

**Secrets:**
```
AZURE_TENANT_ID=your-tenant-id
AZURE_CLIENT_ID=your-application-client-id
```

**Variables** (optional — defaults shown):
```
INTUNESTACK_DEV_GROUP=Dev-Workstations
INTUNESTACK_TEST_GROUP=Test-Workstations
INTUNESTACK_PROD_GROUP=Prod-Workstations
```

### Deployment Ring Groups

Create Entra ID groups following the naming convention `{Stage}-{Scope}`:

```
Dev-Workstations    Test-Workstations    Prod-Workstations
Dev-Users           Test-Users           Prod-Users
```

The consistent naming convention ensures unambiguous exact-match lookups when IntuneStack resolves groups during promotion.


## Usage

### Import the Module

```powershell
Import-Module IntuneStack
```

### PR-Driven Promotion

The primary way to trigger promotion is by opening a pull request from `development` to `main` and filling in the PR template. The workflow parses the policy details directly from the PR body and kicks off the promotion pipeline automatically once the quality gate passes.

### Manual Promotion via workflow_dispatch

1. Go to **Actions** → **Policy Promotion**
2. Click **Run workflow**
3. Enter your Policy ID, current stage, threshold, and whether to auto-promote

Integration test results will appear in the workflow logs only — no artifacts containing tenant data will be uploaded.

### Analyze a Policy for Promotion

```powershell
# Check if a policy is ready to promote from dev
Start-PolicyPromotionAnalysis -PolicyId "12345678-1234-1234-1234-123456789012" -CurrentStage dev

# Automatically promote if success criteria met
Start-PolicyPromotionAnalysis -PolicyId "12345678-1234-1234-1234-123456789012" -CurrentStage dev -AutoPromote

# Use a custom success threshold
Start-PolicyPromotionAnalysis -PolicyId "12345678-1234-1234-1234-123456789012" -CurrentStage dev -ComplianceThreshold 85 -AutoPromote
```

### Individual Functions

```powershell
# Find a group by ID
Get-EntraGroup -GroupId "12345678-1234-1234-1234-123456789012"

# Search groups by name
Get-EntraGroup -SearchTerm "Dev"

# Get all compliance policies
Get-DeviceConfigurationPolicy -Category CompliancePolicies

# Get a specific policy by name
Get-DeviceConfigurationPolicy -Category DeviceConfiguration -Name "HYPE-Baseline Device Restrictions"

# Get assignments for a policy
Get-DeviceConfigurationPolicyAssignment -Category DeviceConfiguration -Id "12345678-1234-1234-1234-123456789012"

# Get deployment status for a policy
Get-DeviceConfigurationPolicyStatus -Category DeviceConfiguration -Id "12345678-1234-1234-1234-123456789012"

# Assign a policy to a group
Add-DeviceConfigurationPolicyAssignment -Category DeviceConfiguration -ConfigurationPolicyId $PolicyId -TargetGroupId $GroupId

# Assign as excluded
Add-DeviceConfigurationPolicyAssignment -Category DeviceConfiguration -ConfigurationPolicyId $PolicyId -TargetGroupId $GroupId -AssignmentType Excluded
```


## How It Works

### Deployment Ring Flow

```
Policy Created in Intune (unassigned)
            |
            v
    Stage 1: DEV
    Assign to Dev-Workstations
    Monitor success rate (target: 80%)
            |
            | Auto-promote if criteria met
            v
    Stage 2: TEST
    Assign to Test-Workstations
    Monitor success rate (target: 80%)
            |
            | Auto-promote if criteria met
            v
    Stage 3: PROD
    Assign to Prod-Workstations
    Policy now in production
```

### Promotion Logic

The module analyzes each policy and determines:

1. **Current State**: Which groups is the policy currently assigned to?
2. **Target Stage**: Where should the policy go next?
3. **Success Metrics**: Total devices, success rate, error rate
4. **Action Decision**:
   - Ready for promotion: Success rate meets or exceeds threshold
   - Not ready: Success rate below threshold
   - Complete: Already deployed to all stages

### CI/CD Pipeline

Two workflows run on every PR to `main` or `development`:

- **PR Validation** (`pr-validation.yml`): Runs PSScriptAnalyzer on changed files only and Pester tests. Errors block merge. Warnings are informational.
- **Policy Promotion** (`policy-promotion.yml`): Parses policy details from the PR body and runs the promotion analysis. Only triggers on PRs to `main`.

### Logging

All activity is written to `$PWD\Logs\intunestack.log` as structured JSON:

```json
{
  "Timestamp": "5/1/2026 10:01:45 PM",
  "Severity": "Info",
  "CallingFunction": "Start-PolicyPromotionAnalysis",
  "Message": "Policy deployed to test (Group: Test-Workstations)",
  "Metadata": { "Invoking_User": "hphillips" }
}
```

Error entries capture full exception detail and a call stack dump for debugging. A promotion report is also saved to `$PWD\Logs\promotion-report.json` after each run.


## Testing

> [!WARNING]
> Do not run integration tests on the public IntuneStack repository. Integration tests connect to your real Intune tenant and may expose tenant details in workflow logs even with masking enabled.

### What Runs Automatically

On pull requests:

- Code quality checks (PSScriptAnalyzer) — no tenant connection
- Unit tests (Pester) — no tenant connection

On manual workflow dispatch only:

- Integration tests — connects to real Intune tenant, use with caution

### Running Tests Locally

```powershell
# Run Pester tests
Invoke-Pester -Path "./tests/PolicyPromotionAnalysis.Tests.ps1"

# Run with code coverage
$config = New-PesterConfiguration
$config.Run.Path = "./tests/PolicyPromotionAnalysis.Tests.ps1"
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = "./Public"
Invoke-Pester -Configuration $config

# Run code quality check
./src/Invoke-CodeQuality.ps1

# Run with auto-fix for formatting
./src/Invoke-CodeQuality.ps1 -CheckFormatting -Fix
```


## Configuration

### Success Thresholds

| Stage | Default | Recommended |
|-------|---------|-------------|
| Dev   | 80%     | 70-80%      |
| Test  | 80%     | 80-85%      |
| Prod  | 80%     | 85-95%      |


## Authentication

### OIDC (GitHub Actions)

Automatically used in CI/CD — no secrets stored in code. The workflow requests an OIDC token from GitHub and exchanges it for a Graph API access token using your App Registration.

### Interactive (Local Development)

The module automatically falls back to interactive browser authentication when OIDC environment variables are not present.


## Resources

- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)
- [GitHub OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Intune Graph API](https://learn.microsoft.com/en-us/graph/api/resources/intune-graph-overview)
- [Pester](https://pester.dev/)
- [Practical Automation with PowerShell — Matthew Dowst](https://www.manning.com/books/practical-automation-with-powershell)


## Disclaimer & License

**USE AT YOUR OWN RISK**: This software is provided "as is" without warranty of any kind. The authors and contributors are not responsible for any damages or issues that may arise from using this software. Always test in a non-production environment first, review all code before running against your tenant, understand the permissions you are granting, and have a rollback plan.

Licensed under the GPL License — see the [LICENSE](LICENSE) file for details.


## Acknowledgments

- **[Andrew Taylor](https://github.com/andrew-s-taylor/public)** — Intune management function foundation
- **[Maester Team](https://maester.dev/)** — OIDC and testing patterns
- **[Matthew Dowst](https://www.manning.com/books/practical-automation-with-powershell)** — Module self-update pattern from Practical Automation with PowerShell
- **[Ironman Software](https://blog.ironmansoftware.com/write-psulog/)** — Universal log function
- **Microsoft Graph Team** — Comprehensive PowerShell SDK
