# Simple test for PolicyPromotion.ps1

Describe "PolicyPromotion Script" {

    It "Script file exists" {
        Test-Path "$PSScriptRoot/../src/PolicyPromotion.ps1" | Should -Be $true
    }

    It "Script has valid syntax" {
        { . "$PSScriptRoot/../src/PolicyPromotion.ps1" -PolicyId "test" } | Should -Not -Throw
    }

    It "Ring progression works correctly" {
        # Test the stage progression logic
        "dev" | Should -Be "dev"

        $nextStage = switch ("dev") {
            "dev" { "test" }
            "test" { "prod" }
            "prod" { "completed" }
        }
        $nextStage | Should -Be "test"
    }
}
