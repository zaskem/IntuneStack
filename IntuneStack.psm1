$gitResults = New-TemporaryFile

$Process = @{
    FilePath               = 'git'
    WorkingDirectory       = $PSScriptRoot
    RedirectStandardOutput = $gitResults
    Wait                   = $true
    NoNewWindow            = $true
}

Start-Process @Process -ArgumentList 'branch --show-current'
$content = Get-Content -LiteralPath $gitResults -Raw

if ($content.Trim() -ne 'main') {
    Start-Process @Process -ArgumentList 'checkout main'
}

Start-Process @Process -ArgumentList 'fetch'
Start-Process @Process -ArgumentList 'diff main origin/main --compact-summary'
$content = Get-Content -LiteralPath $gitResults -Raw

if ($content) {
    Write-Host "IntuneStack update detected — downloading latest version..."
    Start-Process @Process -ArgumentList 'reset --hard origin/main'
    $content = Get-Content -LiteralPath $gitResults
    Write-Host $content
    Write-Host "Reload your PowerShell session to apply the update."
}

if (Test-Path $gitResults) {
    Remove-Item -Path $gitResults -Force
}

# Import public functions
$Path = Join-Path $PSScriptRoot 'Public'
$Functions = Get-ChildItem -Path $Path -Filter '*.ps1'

foreach ($import in $Functions) {
    try {
        Write-Verbose "dot-sourcing file '$($import.fullname)'"
        . $import.fullname
    } catch {
        Write-Error -Message "Failed to import function $($import.name)"
    }
}

# Validate required modules
[System.Collections.Generic.List[PSObject]]$RequiredModules = @()
$RequiredModules.Add([PSCustomObject]@{
        Name    = 'Microsoft.Graph.Authentication'
        Version = '1.1.5'
    })

foreach ($module in $RequiredModules) {
    $Check = Get-Module $module.Name -ListAvailable

    if (-not $Check) {
        throw "Module $($module.Name) not found"
    }

    $VersionCheck = $Check | Where-Object { $_.Version -ge $module.Version }

    if (-not $VersionCheck) {
        Write-Error "Module $($module.Name) running older version"
    }

    Import-Module -Name $module.Name
}
