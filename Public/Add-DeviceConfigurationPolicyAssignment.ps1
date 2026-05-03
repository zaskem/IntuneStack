function Add-DeviceConfigurationPolicyAssignment {
    <#
    .SYNOPSIS
    This function is used to add a device configuration policy assignment using the Graph API REST interface.

    .DESCRIPTION
    The function connects to the Graph API Interface and adds a device configuration policy assignment,
    preserving any existing assignments.

    .PARAMETER Category
    Category of policy (AutopilotProfile, ApplicationProtection, ConditionalAccess, CompliancePolicies, DeviceConfiguration, DeviceConfigurationSC).

    .PARAMETER ConfigurationPolicyId
    The policy ID to assign. Must be a valid GUID.

    .PARAMETER TargetGroupId
    The group ID to assign the policy to. Must be a valid GUID.

    .PARAMETER AssignmentType
    Whether to include or exclude the group.

    .EXAMPLE
    Add-DeviceConfigurationPolicyAssignment -Category "DeviceConfiguration" -ConfigurationPolicyId $PolicyId -TargetGroupId $GroupId -AssignmentType Included

    .EXAMPLE
    Add-DeviceConfigurationPolicyAssignment -Category "DeviceConfigurationSC" -ConfigurationPolicyId $PolicyId -TargetGroupId $GroupId -AssignmentType Included -WhatIf

    .NOTES
    NAME: Add-DeviceConfigurationPolicyAssignment
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('AutopilotProfile', 'CompliancePolicies', 'DeviceConfiguration', 'DeviceConfigurationSC', 'ApplicationProtection', 'ConditionalAccess')]
        [string]$Category,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ $_ -match '^([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})$' })]
        [string]$ConfigurationPolicyId,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ $_ -match '^([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})$' })]
        [string]$TargetGroupId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Included', 'Excluded')]
        [string]$AssignmentType = 'Included',
        [string]$graphApiVersion = "beta"
    )

    $DCP_resource = switch ($Category) {
        'AutopilotProfile' { "deviceManagement/windowsAutopilotDeploymentProfiles" }
        'CompliancePolicies' { "deviceManagement/deviceCompliancePolicies" }
        'DeviceConfiguration' { "deviceManagement/deviceConfigurations" }
        'DeviceConfigurationSC' { "deviceManagement/configurationPolicies" }
        'ApplicationProtection' { "deviceAppManagement/managedAppPolicies" }
        'ConditionalAccess' { "identity/conditionalAccess/policies" }
    }

    try {
        $DCPA = Get-DeviceConfigurationPolicyAssignment -Category $Category -Id $ConfigurationPolicyId

        if (@($DCPA).Count -ge 1) {
            if ($DCPA.Id -contains $TargetGroupId) {
                Write-Log -Message "Group '$TargetGroupId' is already assigned to policy '$ConfigurationPolicyId'" -Severity Warn
                return
            }
        }

        $TargetGroups = @()

        # Preserve existing assignments
        foreach ($Assignment in $DCPA) {
            $TargetGroup = [PSCustomObject]@{
                '@odata.type' = if ($Assignment.AssignmentType -eq "Exclude") {
                    '#microsoft.graph.exclusionGroupAssignmentTarget'
                } else {
                    '#microsoft.graph.groupAssignmentTarget'
                }
                groupId       = $Assignment.Id
            }
            $TargetGroups += [PSCustomObject]@{ target = $TargetGroup }
        }

        # Add new assignment
        $TargetGroup = [PSCustomObject]@{
            '@odata.type' = if ($AssignmentType -eq "Excluded") {
                '#microsoft.graph.exclusionGroupAssignmentTarget'
            } else {
                '#microsoft.graph.groupAssignmentTarget'
            }
            groupId       = $TargetGroupId
        }
        $TargetGroups += [PSCustomObject]@{ target = $TargetGroup }

        $graphParams = @{
            Uri         = "https://graph.microsoft.com/$graphApiVersion/$DCP_resource/$ConfigurationPolicyId/assign"
            Method      = "POST"
            Body        = ([PSCustomObject]@{ assignments = $TargetGroups } | ConvertTo-Json -Depth 5)
            ContentType = "application/json"
        }

        if ($PSCmdlet.ShouldProcess("Policy '$ConfigurationPolicyId'", "Assign group '$TargetGroupId' as $AssignmentType")) {
            Invoke-MgGraphRequest @graphParams
            Write-Log -Message "Assigned group to $Category policy as $AssignmentType" -Severity Info
        }

    } catch {
        Write-Log -Message "Error assigning group to $Category policy" -Severity Error
        throw
    }
}
