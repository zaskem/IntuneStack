@{    # Use all default rules
    IncludeDefaultRules = $true

    # Exclude specific rules if needed
    ExcludeRules        = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidOverwritingBuiltInCmdlets',
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )

    # Custom severity levels
    Severity            = @('Error', 'Warning')

    # Custom rules settings
    Rules               = @{
        PSUseCompatibleCmdlets     = @{
            # Target PowerShell versions
            Compatibility = @('core-6.1.0-windows', 'core-6.1.0-linux', 'core-6.1.0-macos')
        }

        PSUseCompatibleSyntax      = @{
            # Target PowerShell versions
            TargetVersions = @('7.0', '7.1', '7.2', '7.3', '7.4')
        }

        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }

        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }

        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }

        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }

        PSUseConsistentWhitespace  = @{
            Enable          = $true
            CheckInnerBrace = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $true
            CheckPipe       = $true
            CheckSeparator  = $true
        }

        PSUseCorrectCasing         = @{
            Enable = $true
        }
    }
}
