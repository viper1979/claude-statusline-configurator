BeforeAll {
    $script:PluginPath = Join-Path $PSScriptRoot '../request-usage.ps1'
}

Describe 'request-usage.ps1' {
    BeforeEach {
        $testDir = Join-Path $TestDrive "run-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    }

    It 'writes rate-limits-cache.json on successful API response (string resets_at)' {
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
        $cache.rate_limits.five_hour.resets_at       | Should -Be 1775660400
        $cache.rate_limits.seven_day.used_percentage | Should -Be 18
        $cache.rate_limits.seven_day.resets_at       | Should -Be 1775779200
    }

    It 'writes rate-limits-cache.json when Invoke-RestMethod returns DateTime objects (PowerShell 7 auto-parse)' {
        # PowerShell 7's Invoke-RestMethod auto-parses ISO 8601 strings in JSON responses
        # to [System.DateTime] objects. ConvertTo-UnixTimestamp must handle this correctly
        # instead of coercing to a US-culture string ("04/21/2026 11:00:00") which fails to parse.
        $credsDir = Join-Path $testDir '.claude'
        New-Item -ItemType Directory -Path $credsDir -Force | Out-Null
        $credsPath = Join-Path $credsDir '.credentials.json'
        @{ claudeAiOauth = @{ accessToken = 'fake-token' } } | ConvertTo-Json -Depth 3 |
            Set-Content -Path $credsPath -Encoding UTF8

        Mock Invoke-RestMethod {
            # Simulate PowerShell 7 auto-parsing ISO 8601 strings to [datetime] objects
            return [PSCustomObject]@{
                five_hour = [PSCustomObject]@{ utilization = 0.42; resets_at = [datetime]::Parse('2026-04-08T15:00:00Z').ToUniversalTime() }
                seven_day = [PSCustomObject]@{ utilization = 0.18; resets_at = [datetime]::Parse('2026-04-10T00:00:00Z').ToUniversalTime() }
            }
        }

        $cachePath = Join-Path $testDir 'rate-limits-cache.json'
        & $script:PluginPath -CredentialsPath $credsPath -CachePath $cachePath

        Test-Path $cachePath | Should -Be $true
        $cache = Get-Content $cachePath -Raw | ConvertFrom-Json
        $cache.rate_limits.five_hour.used_percentage | Should -Be 42
        $cache.rate_limits.five_hour.resets_at       | Should -Be 1775660400
        $cache.rate_limits.seven_day.used_percentage | Should -Be 18
        $cache.rate_limits.seven_day.resets_at       | Should -Be 1775779200
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
