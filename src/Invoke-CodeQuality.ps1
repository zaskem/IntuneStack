<#
.SYNOPSIS
    IntuneStack code quality checker

.DESCRIPTION
    Run PSScriptAnalyzer and other code quality checks locally

.PARAMETER Path
    Path to analyze (default: current directory)

.PARAMETER FailOnError
    Exit with error code if issues found

.PARAMETER CheckFormatting
    Check code formatting only

.PARAMETER Fix
    Attempt to fix formatting issues automatically
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Path = ".",

    [Parameter(Mandatory = $false)]
    [switch]$FailOnError,

    [Parameter(Mandatory = $false)]
    [switch]$CheckFormatting,

    [Parameter(Mandatory = $false)]
    [switch]$Fix
)

#region Functions
function Test-PowerShellModules {
    $RequiredModules = @('PSScriptAnalyzer')

    foreach ($Module in $RequiredModules) {
        if (-not (Get-Module -ListAvailable -Name $Module)) {
            Write-Log -Message "Installing required module: $Module" -Severity Warn
            Install-Module -Name $Module -Force -Scope CurrentUser
        }
    }
}

function Invoke-PSScriptAnalyzerCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-Log -Message "Running PSScriptAnalyzer..." -Severity Info

    $PowerShellFiles = Get-ChildItem -Path $Path -Include "*.ps1", "*.psm1", "*.psd1" -Recurse |
        Where-Object { $_.FullName -notmatch '(node_modules|\.git|\.vscode|bin|obj)' }

    if (-not $PowerShellFiles) {
        Write-Log -Message "No PowerShell files found to analyze" -Severity Warn
        return @()
    }

    Write-Log -Message "Found $($PowerShellFiles.Count) PowerShell files to analyze" -Severity Info

    $AllResults = @()
    $SettingsPath = Join-Path $Path "PSScriptAnalyzerSettings.psd1"

    foreach ($File in $PowerShellFiles) {
        Write-Log -Message "Analyzing: $($File.Name)" -Severity Info

        try {
            $Results = if (Test-Path $SettingsPath) {
                Invoke-ScriptAnalyzer -Path $File.FullName -Settings $SettingsPath
            } else {
                Invoke-ScriptAnalyzer -Path $File.FullName
            }

            if ($Results) {
                $AllResults += $Results

                foreach ($Result in $Results) {
                    $severity = switch ($Result.Severity) {
                        'Error' { 'Error' }
                        'Warning' { 'Warn' }
                        'Information' { 'Info' }
                    }

                    Write-Log -Message "[$($Result.Severity)] $($Result.RuleName): $($Result.Message) (Line: $($Result.Line))" -Severity $severity
                }
            }
        } catch {
            Write-Log -Message "Error analyzing file: $($File.Name)" -Severity Error
        }
    }

    return $AllResults
}

function Invoke-FormattingCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$Fix
    )

    Write-Log -Message "Checking PowerShell formatting..." -Severity Info

    $PowerShellFiles = Get-ChildItem -Path $Path -Include "*.ps1", "*.psm1", "*.psd1" -Recurse |
        Where-Object { $_.FullName -notmatch '(node_modules|\.git|\.vscode|bin|obj)' }

    $FormattingIssues = 0

    foreach ($File in $PowerShellFiles) {
        $Content = Get-Content -Path $File.FullName -Raw
        $Issues = @()

        if ($Content -match '\s+$') {
            $Issues += "Trailing whitespace found"
        }

        if ($Content -match '\r\n' -and $Content -match '(?<!\r)\n') {
            $Issues += "Mixed line endings (CRLF and LF)"
        }

        if ($Content -match '\t') {
            $Issues += "Tabs found (should use spaces)"
        }

        if ($Issues) {
            $FormattingIssues += $Issues.Count
            Write-Log -Message "$($File.Name) has formatting issues:" -Severity Warn

            foreach ($Issue in $Issues) {
                Write-Log -Message "  - $Issue" -Severity Warn
            }

            if ($Fix) {
                Write-Log -Message "Attempting to fix formatting issues in $($File.Name)..." -Severity Info

                $Content = $Content -replace '\s+$', ''
                $Content = $Content -replace '\t', '    '
                $Content = $Content -replace '\r\n', "`n"

                Set-Content -Path $File.FullName -Value $Content -NoNewline
                Write-Log -Message "Fixed formatting issues in $($File.Name)" -Severity Info
            }
        }
    }

    return $FormattingIssues
}
#endregion

#region Main Execution
try {
    Write-Log -Message "IntuneStack Code Quality Check starting" -Severity Start
    Write-Log -Message "Path: $Path" -Severity Info

    Test-PowerShellModules

    $TotalIssues = 0
    $ErrorCount = 0

    if ($CheckFormatting) {
        $FormattingIssues = Invoke-FormattingCheck -Path $Path -Fix:$Fix

        $TotalIssues += $FormattingIssues

        Write-Log -Message "Formatting Issues: $FormattingIssues" -Severity $(if ($FormattingIssues -gt 0) { 'Warn' } else { 'Info' })
    } else {

        $AnalysisResults = Invoke-PSScriptAnalyzerCheck -Path $Path
        $FormattingIssues = Invoke-FormattingCheck -Path $Path -Fix:$Fix

        $ErrorCount = ($AnalysisResults | Where-Object Severity -EQ 'Error').Count
        $WarningCount = ($AnalysisResults | Where-Object Severity -EQ 'Warning').Count
        $InfoCount = ($AnalysisResults | Where-Object Severity -EQ 'Information').Count
        $TotalIssues = $AnalysisResults.Count + $FormattingIssues

        Write-Log -Message "PSScriptAnalyzer Issues: $($AnalysisResults.Count) | Errors: $ErrorCount | Warnings: $WarningCount | Info: $InfoCount" -Severity Info
        
        Write-Log -Message "Formatting Issues: $FormattingIssues" -Severity $(if ($FormattingIssues -gt 0) { 'Warn' } else { 'Info' })
        Write-Log -Message "Total Issues: $TotalIssues" -Severity $(if ($TotalIssues -gt 0) { 'Warn' } else { 'Info' })
    }

    if ($FailOnError -and ($ErrorCount -gt 0 -or $TotalIssues -gt 0)) {
        Write-Log -Message "Code quality check failed" -Severity Error
        exit 1
    }

    Write-Log -Message "Code quality check complete" -Severity End

} catch {
    Write-Log -Message "Code quality check failed: $($_.Exception.Message)" -Severity Error
    exit 1
}
#endregion
