BeforeAll {
    $script:PluginPath = Join-Path $PSScriptRoot '../request-usage.ps1'
}

Describe 'request-usage.ps1' {
    BeforeEach {
        $testDir = Join-Path $TestDrive "run-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    }

    It 'writes rate-limits-cache.json on successful API response' {
        $credsDir = Join-Path $testDir '.claude'
        New-Item -ItemType Directory -Path $credsDir -Force | Out-Null
        $credsPath = Join-Path $credsDir '.credentials.json'
        @{ claudeAiOauth = @{ accessToken = 'fake-token' } } | ConvertTo-Json -Depth 3 |
            Set-Content -Path $credsPath -Encoding UTF8

        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                five_hour = [PSCustomObject]@{ utilization = 0.42; resets_at = '2026-04-08T15:00:00Z' }
                seven_day = [PSCustomObject]@{ utilization = 0.18; resets_at = '2026-04-10T00:00:00Z' }
            }
        }

        $cachePath = Join-Path $testDir 'rate-limits-cache.json'
        & $script:PluginPath -CredentialsPath $credsPath -CachePath $cachePath

        Test-Path $cachePath | Should -Be $true
        $cache = Get-Content $cachePath -Raw | ConvertFrom-Json
        $cache.rate_limits.five_hour.used_percentage | Should -Be 42
        $cache.rate_limits.seven_day.used_percentage | Should -Be 18
    }

    It 'does not write cache when credentials file is missing' {
        $cachePath = Join-Path $testDir 'rate-limits-cache.json'
        $nonExistent = Join-Path $testDir 'no-creds.json'
        & $script:PluginPath -CredentialsPath $nonExistent -CachePath $cachePath
        Test-Path $cachePath | Should -Be $false
    }

    It 'preserves existing cache when API call fails' {
        $credsDir = Join-Path $testDir '.claude'
        New-Item -ItemType Directory -Path $credsDir -Force | Out-Null
        $credsPath = Join-Path $credsDir '.credentials.json'
        @{ claudeAiOauth = @{ accessToken = 'fake-token' } } | ConvertTo-Json -Depth 3 |
            Set-Content -Path $credsPath -Encoding UTF8

        $cachePath = Join-Path $testDir 'rate-limits-cache.json'
        @{ rate_limits = @{ five_hour = @{ used_percentage = 99 } } } | ConvertTo-Json -Depth 5 |
            Set-Content -Path $cachePath -Encoding UTF8

        Mock Invoke-RestMethod { throw 'Network error' }

        & $script:PluginPath -CredentialsPath $credsPath -CachePath $cachePath

        $cache = Get-Content $cachePath -Raw | ConvertFrom-Json
        $cache.rate_limits.five_hour.used_percentage | Should -Be 99
    }
}
