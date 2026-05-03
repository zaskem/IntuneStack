function Start-PolicyPromotionAnalysis {
    <#
    .SYNOPSIS
    Analyzes and automates Intune policy promotion through deployment rings.

    .DESCRIPTION
    Connects to the Graph API and analyzes policy deployment status, automating
    promotion through dev -> test -> prod stages.

    .PARAMETER PolicyId
    The policy ID (GUID) to analyze for promotion.

    .PARAMETER ComplianceThreshold
    The compliance threshold percentage required for promotion. Defaults to 80.

    .PARAMETER CurrentStage
    The current deployment stage (dev, test, prod). Defaults to the GitHub branch name.

    .PARAMETER AutoPromote
    Enable automatic promotion when compliance threshold is met.

    .EXAMPLE
    Start-PolicyPromotionAnalysis -PolicyId "12345678-1234-1234-1234-123456789012"

    .EXAMPLE
    Start-PolicyPromotionAnalysis -PolicyId "12345678-1234-1234-1234-123456789012" -ComplianceThreshold 85 -AutoPromote -CurrentStage "dev"

    .NOTES
    NAME: Start-PolicyPromotionAnalysis
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ $_ -match '^([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})$' })]
        [string]$PolicyId,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$ComplianceThreshold = 80,

        [Parameter(Mandatory = $false)]
        [ValidateSet('dev', 'test', 'prod')]
        [string]$CurrentStage = 'dev',

        [Parameter(Mandatory = $false)]
        [switch]$AutoPromote
    )

    $ErrorActionPreference = "Stop"
    $version = "1.0.0"

    $RingGroups = @{
        "dev"  = if ($env:INTUNESTACK_DEV_GROUP) { $env:INTUNESTACK_DEV_GROUP }  else { "Dev-Workstations" }
        "test" = if ($env:INTUNESTACK_TEST_GROUP) { $env:INTUNESTACK_TEST_GROUP } else { "Test-Workstations" }
        "prod" = if ($env:INTUNESTACK_PROD_GROUP) { $env:INTUNESTACK_PROD_GROUP } else { "Prod-Workstations" }
    }

    try {
        Write-Log -Message "IntuneStack Policy Promotion Analysis v$version" -Severity Start

        if ($env:OIDC_TOKEN) {
            Connect-ToGraph -TenantId $env:AZURE_TENANT_ID -AppId $env:AZURE_CLIENT_ID -OidcToken $env:OIDC_TOKEN
        } else {
            Connect-ToGraph
        }

        Write-Log -Message "Analysis started — Stage: $CurrentStage, Threshold: $ComplianceThreshold%, Auto Promote: $(if ($AutoPromote) { 'Enabled' } else { 'Disabled' })" -Severity Info

        $PolicyType = $null
        $PolicyDetails = $null

        foreach ($Category in @('DeviceConfiguration', 'DeviceConfigurationSC', 'CompliancePolicies', 'AutopilotProfile')) {
            $Match = Get-DeviceConfigurationPolicy -Category $Category | Where-Object { $_.id -eq $PolicyId }
            if ($Match) {
                $PolicyType = $Category
                $PolicyDetails = $Match
                Write-Log -Message "Detected $Category policy" -Severity Info
                break
            }
        }

        if (-not $PolicyType) {
            Write-Log -Message "Policy not found: $PolicyId" -Severity Error
            return $false
        }

        $displayName = if ($PolicyDetails.displayName) { $PolicyDetails.displayName } else { $PolicyDetails.name }
        Write-Log -Message "Policy found: $displayName ($PolicyType)" -Severity Info

        $AssignedGroups = Get-DeviceConfigurationPolicyAssignment -Category $PolicyType -Id $PolicyId
        Write-Log -Message "Current assignments: $($AssignedGroups.Count) group(s)" -Severity Info

        $PolicyStatus = Get-DeviceConfigurationPolicyStatus -Category $PolicyType -Id $PolicyId

        if (-not $PolicyStatus) {
            Write-Log -Message "Unable to retrieve policy status for $displayName" -Severity Error
            return $false
        }

        Write-Log -Message "$displayName — $($PolicyStatus.TotalDevices) devices, $($PolicyStatus.SuccessRate)% success" -Severity Info

        $CurrentStageGroup = $RingGroups[$CurrentStage]
        $AssignedToCurrentStage = $AssignedGroups | Where-Object { $_.Name -eq $CurrentStageGroup }

        if ($AssignedToCurrentStage) {
            $NextStage = switch ($CurrentStage) {
                "dev" { "test" }
                "test" { "prod" }
                "prod" { "completed" }
            }
            $ActionType = "promote"
        } else {
            $NextStage = $CurrentStage
            $ActionType = "deploy"
        }

        $ReadyForPromotion = $PolicyStatus.SuccessRate -ge $ComplianceThreshold -and $PolicyStatus.TotalDevices -gt 0

        $PromotionExecuted = $false
        $PromotionTargetStage = $null
        $PromotionTargetGroup = $null
        $PromotionTargetGroupId = $null
        $PromotionTimestamp = $null
        $PromotionGuidance = $null
        $PromotionCommand = $null

        Write-Log -Message "Ready: $ReadyForPromotion | Current stage assigned: $($null -ne $AssignedToCurrentStage) | Action: $ActionType to $NextStage" -Severity Info

        if ($ReadyForPromotion -and $NextStage -ne "completed") {
            $NextStageGroup = $RingGroups[$NextStage]
            Write-Log -Message "Policy ready for $NextStage — target group: $NextStageGroup" -Severity Info

            if ($AutoPromote) {
                Write-Log -Message "Starting auto-promotion to $NextStage" -Severity Start

                $TargetGroup = Get-EntraGroup -GroupName $NextStageGroup

                if (-not $TargetGroup) {
                    Write-Log -Message "Target group '$NextStageGroup' not found" -Severity Error
                    return $false
                }

                Add-DeviceConfigurationPolicyAssignment -Category $PolicyType -ConfigurationPolicyId $PolicyId -TargetGroupId $TargetGroup.id

                Write-Log -Message "Policy deployed to $NextStage (Group: $NextStageGroup)" -Severity End

                $UpdatedAssignments = Get-DeviceConfigurationPolicyAssignment -Category $PolicyType -Id $PolicyId
                Write-Log -Message "Updated assignments: $($UpdatedAssignments.Count) group(s) — $($UpdatedAssignments.Name -join ', ')" -Severity Info

                $PromotionExecuted = $true
                $PromotionTargetStage = $NextStage
                $PromotionTargetGroup = $NextStageGroup
                $PromotionTargetGroupId = $TargetGroup.id
                $PromotionTimestamp = (Get-Date).ToString()

            } else {
                $PromotionGuidance = "Policy is ready for $ActionType to $NextStage. Run with -AutoPromote to execute."
                $PromotionCommand = "Start-PolicyPromotionAnalysis -PolicyId '$PolicyId' -CurrentStage '$CurrentStage' -AutoPromote"
                Write-Log -Message "Ready for promotion but auto-promotion disabled. $PromotionGuidance" -Severity Info
            }

        } elseif ($NextStage -eq "completed") {
            $PromotionGuidance = "Policy has been deployed to all stages (dev -> test -> prod). No further promotion needed."
            Write-Log -Message "Policy deployment complete across all stages" -Severity End

        } else {
            $PromotionGuidance = "Policy needs $ComplianceThreshold% success rate before promotion. Current: $($PolicyStatus.SuccessRate)%"
            Write-Log -Message "Policy does not meet promotion threshold ($($PolicyStatus.SuccessRate)% / $ComplianceThreshold%)" -Severity Warn
        }

        Write-Log -Message "Policy promotion analysis completed" -Severity End

        $Report = [PSCustomObject]@{
            Timestamp              = (Get-Date).ToString()
            PolicyId               = $PolicyId
            PolicyType             = $PolicyType
            PolicyName             = $PolicyStatus.DisplayName
            CurrentStage           = $CurrentStage
            NextStage              = $NextStage
            ReadyForPromotion      = $ReadyForPromotion
            AssignedGroups         = $AssignedGroups
            Metrics                = $PolicyStatus
            ComplianceThreshold    = $ComplianceThreshold
            AutoPromoteEnabled     = $AutoPromote.IsPresent
            RingGroups             = $RingGroups
            PromotionExecuted      = $PromotionExecuted
            PromotionTargetStage   = $PromotionTargetStage
            PromotionTargetGroup   = $PromotionTargetGroup
            PromotionTargetGroupId = $PromotionTargetGroupId
            PromotionTimestamp     = if ($PromotionExecuted) { (Get-Date).ToString() } else { $null }
            PromotionGuidance      = $PromotionGuidance
            PromotionCommand       = $PromotionCommand
        }

        $null = $Report | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path "$PWD\Logs" "promotion-report.json") -Encoding UTF8
        Write-Log -Message "Promotion report saved to $PWD\Logs\promotion-report.json" -Severity Info

        return $ReadyForPromotion

    } catch {
        Write-Log -Message "Error during policy promotion analysis" -Severity Error
        throw
    }
}
