BeforeAll {
    # Dot-source the script under test
    . (Join-Path $PSScriptRoot '../statusline.ps1')
}

Describe 'Get-NestedValue' {
    It 'returns top-level property' {
        $data = [PSCustomObject]@{ version = '1.0.80' }
        Get-NestedValue $data 'version' | Should -Be '1.0.80'
    }

    It 'returns nested property two levels deep' {
        $data = [PSCustomObject]@{
            model = [PSCustomObject]@{ display_name = 'Opus' }
        }
        Get-NestedValue $data 'model.display_name' | Should -Be 'Opus'
    }

    It 'returns nested property three levels deep' {
        $inner = [PSCustomObject]@{ used_percentage = 23.5 }
        $limits = [PSCustomObject]@{ five_hour = $inner }
        $data   = [PSCustomObject]@{ rate_limits = $limits }
        Get-NestedValue $data 'rate_limits.five_hour.used_percentage' | Should -Be 23.5
    }

    It 'returns $null for unknown path' {
        $data = [PSCustomObject]@{ version = '1.0' }
        Get-NestedValue $data 'nonexistent.path' | Should -BeNullOrEmpty
    }

    It 'returns $null when input is $null' {
        Get-NestedValue $null 'any.path' | Should -BeNullOrEmpty
    }
}

Describe 'Format-ProgressBar' {
    It 'renders block style with brackets' {
        $result = Format-ProgressBar -Value 30 -Style 'block' -Fg $null
        $result | Should -Match '\['
        $result | Should -Match '30%'
    }

    It 'renders slim style without brackets' {
        $result = Format-ProgressBar -Value 30 -Style 'slim' -Fg $null
        $result | Should -Not -Match '\['
        $result | Should -Match '30%'
    }

    It 'uses green ANSI for value below 50 in color-coded style' {
        $result = Format-ProgressBar -Value 20 -Style 'color-coded' -Fg $null
        # Green = 4ade80 = RGB 74,222,128
        $result | Should -Match '74;222;128'
    }

    It 'uses yellow ANSI for value 50-79 in color-coded style' {
        $result = Format-ProgressBar -Value 65 -Style 'color-coded' -Fg $null
        # Yellow = facc15 = RGB 250,204,21
        $result | Should -Match '250;204;21'
    }

    It 'uses red ANSI for value 80+ in color-coded style' {
        $result = Format-ProgressBar -Value 85 -Style 'color-coded' -Fg $null
        # Red = f87171 = RGB 248,113,113
        $result | Should -Match '248;113;113'
    }

    It 'uses custom fg color when provided' {
        $result = Format-ProgressBar -Value 50 -Style 'block' -Fg '#00ff00'
        # #00ff00 = RGB 0,255,0
        $result | Should -Match '0;255;0'
    }

    It 'clamps value above 100 to 100' {
        $result = Format-ProgressBar -Value 150 -Style 'block' -Fg $null
        $result | Should -Match '100%'
    }

    It 'clamps value below 0 to 0' {
        $result = Format-ProgressBar -Value -5 -Style 'block' -Fg $null
        $result | Should -Match '0%'
    }
}

Describe 'Format-Field' {
    BeforeAll {
        $sampleData = [PSCustomObject]@{
            model = [PSCustomObject]@{ display_name = 'Opus' }
            cost  = [PSCustomObject]@{ total_cost_usd = 0.0123 }
            context_window = [PSCustomObject]@{ used_percentage = 45 }
        }
    }

    It 'renders a field type with its raw value' {
        $field = [PSCustomObject]@{ type='field'; key='model.display_name'; fg=$null; bg=$null }
        Format-Field $field $sampleData | Should -Match 'Opus'
    }

    It 'wraps value with fg ANSI color when fg is set' {
        $field = [PSCustomObject]@{ type='field'; key='model.display_name'; fg='#ffffff'; bg=$null }
        $result = Format-Field $field $sampleData
        # #ffffff = RGB 255,255,255
        $result | Should -Match '255;255;255'
        $result | Should -Match 'Opus'
    }

    It 'renders static type with its text' {
        $field = [PSCustomObject]@{ type='static'; text=' | '; fg=$null; bg=$null }
        Format-Field $field $sampleData | Should -Be ' | '
    }

    It 'renders static type with fg color' {
        $field = [PSCustomObject]@{ type='static'; text='|'; fg='#888888'; bg=$null }
        $result = Format-Field $field $sampleData
        $result | Should -Match '\|'
        # #888888 = RGB 136,136,136
        $result | Should -Match '136;136;136'
    }

    It 'renders progressbar type as a bar string' {
        $field = [PSCustomObject]@{ type='progressbar'; key='context_window.used_percentage'; progressStyle='block'; fg=$null; bg=$null }
        $result = Format-Field $field $sampleData
        $result | Should -Match '45%'
        $result | Should -Match '\['
    }

    It 'renders progressbar with raw style as plain number without bar characters' {
        $field = [PSCustomObject]@{ type='progressbar'; key='context_window.used_percentage'; progressStyle='raw'; fg=$null; bg=$null }
        $result = Format-Field $field $sampleData
        $result | Should -Match '45'
        $result | Should -Not -Match '\['
        $result | Should -Not -Match '%'
    }

    It 'returns empty string for unknown field path' {
        $field = [PSCustomObject]@{ type='field'; key='does.not.exist'; fg=$null; bg=$null }
        Format-Field $field $sampleData | Should -BeNullOrEmpty
    }
}

Describe 'Format-Line' {
    BeforeAll {
        $sampleData = [PSCustomObject]@{
            model = [PSCustomObject]@{ display_name = 'Sonnet' }
        }
    }

    It 'joins multiple field outputs into one string' {
        $fields = @(
            [PSCustomObject]@{ type='field'; key='model.display_name'; fg=$null; bg=$null },
            [PSCustomObject]@{ type='static'; text=' v1'; fg=$null; bg=$null }
        )
        $line = [PSCustomObject]@{ fields = $fields }
        $result = Format-Line $line $sampleData
        $result | Should -Match 'Sonnet'
        $result | Should -Match 'v1'
    }

    It 'returns empty string for a line with no fields' {
        $line = [PSCustomObject]@{ fields = @() }
        Format-Line $line $sampleData | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-Main' {
    BeforeAll {
        $configPath = Join-Path $TestDrive 'statusline-config.json'
        $config = @{
            lines = @(
                @{
                    fields = @(
                        @{ type='field'; key='model.display_name'; fg=$null; bg=$null }
                        @{ type='static'; text=' | '; fg=$null; bg=$null }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $configPath -Value $config -Encoding UTF8
    }

    It 'renders a line from config and input data' {
        $inputJson = '{"model":{"display_name":"Sonnet"}}'
        $result = Invoke-Main -ConfigPath $configPath -InputJson $inputJson
        $result | Should -Match 'Sonnet'
    }

    It 'returns empty string when config file does not exist' {
        $result = Invoke-Main -ConfigPath 'C:\nonexistent\config.json' -InputJson '{}'
        $result | Should -BeNullOrEmpty
    }

    It 'returns empty string when input JSON is malformed' {
        $result = Invoke-Main -ConfigPath $configPath -InputJson 'not json'
        $result | Should -BeNullOrEmpty
    }

    It 'returns empty string when config JSON is malformed' {
        $badConfig = Join-Path $TestDrive 'bad-config.json'
        Set-Content -Path $badConfig -Value 'not json' -Encoding UTF8
        $result = Invoke-Main -ConfigPath $badConfig -InputJson '{}'
        $result | Should -BeNullOrEmpty
    }

    It 'outputs empty field as empty string without crashing' {
        $configNoKey = @{
            lines = @(
                @{ fields = @(@{ type='field'; key='nonexistent.key'; fg=$null; bg=$null }) }
            )
        } | ConvertTo-Json -Depth 10
        $path = Join-Path $TestDrive 'config-nokey.json'
        Set-Content -Path $path -Value $configNoKey -Encoding UTF8
        $result = Invoke-Main -ConfigPath $path -InputJson '{"model":{}}'
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Format-FieldValue' {
    It 'returns raw string for string type' {
        Format-FieldValue -Value 'claude-opus-4-6' -DataType 'string' -Format $null -FormatOptions $null |
            Should -Be 'claude-opus-4-6'
    }

    It 'formats currency rounded to 2 decimal places' {
        Format-FieldValue -Value 0.01234 -DataType 'currency' -Format $null -FormatOptions $null |
            Should -Be '0.01'
    }

    It 'formats currency with exactly 2 decimal places even for whole number' {
        Format-FieldValue -Value 5 -DataType 'currency' -Format $null -FormatOptions $null |
            Should -Be '5.00'
    }

    It 'formats number with k suffix' {
        Format-FieldValue -Value 12345 -DataType 'number' -Format 'k' -FormatOptions $null |
            Should -Be '12k'
    }

    It 'formats number with m suffix' {
        Format-FieldValue -Value 12000000 -DataType 'number' -Format 'm' -FormatOptions $null |
            Should -Be '12m'
    }

    It 'formats number raw' {
        Format-FieldValue -Value 42 -DataType 'number' -Format 'raw' -FormatOptions $null |
            Should -Be '42'
    }

    It 'formats bool true as true_false' {
        Format-FieldValue -Value $true -DataType 'bool' -Format 'true_false' -FormatOptions $null |
            Should -Be 'true'
    }

    It 'formats bool false as true_false' {
        Format-FieldValue -Value $false -DataType 'bool' -Format 'true_false' -FormatOptions $null |
            Should -Be 'false'
    }

    It 'formats bool as yes_no' {
        Format-FieldValue -Value $true -DataType 'bool' -Format 'yes_no' -FormatOptions $null |
            Should -Be 'yes'
        Format-FieldValue -Value $false -DataType 'bool' -Format 'yes_no' -FormatOptions $null |
            Should -Be 'no'
    }

    It 'formats bool as checkmark' {
        Format-FieldValue -Value $true -DataType 'bool' -Format 'checkmark' -FormatOptions $null |
            Should -Be '✓'
        Format-FieldValue -Value $false -DataType 'bool' -Format 'checkmark' -FormatOptions $null |
            Should -Be '✗'
    }

    It 'formats bool with custom labels' {
        $opts = [PSCustomObject]@{ trueLabel = 'aktiv'; falseLabel = 'inaktiv' }
        Format-FieldValue -Value $true  -DataType 'bool' -Format 'custom' -FormatOptions $opts | Should -Be 'aktiv'
        Format-FieldValue -Value $false -DataType 'bool' -Format 'custom' -FormatOptions $opts | Should -Be 'inaktiv'
    }

    It 'falls back to raw value for bool custom format when FormatOptions is null' {
        Format-FieldValue -Value $true -DataType 'bool' -Format 'custom' -FormatOptions $null |
            Should -Be 'true'
    }

    It 'formats past unix_timestamp as 0h 0m (already elapsed)' {
        # A timestamp in the past has no remaining time — clamps to 0
        $pastTs = [DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeSeconds()
        Format-FieldValue -Value $pastTs -DataType 'unix_timestamp' -Format 'hours' -FormatOptions $null |
            Should -Be '0h 0m'
    }

    It 'formats duration 5000 seconds as hours format: 1h 23m' {
        Format-FieldValue -Value 5000 -DataType 'duration' -Format 'hours' -FormatOptions $null |
            Should -Be '1h 23m'
    }

    It 'formats duration 90061 seconds as short format with days: 1d 1h 1m' {
        Format-FieldValue -Value 90061 -DataType 'duration' -Format 'short' -FormatOptions $null |
            Should -Be '1d 1h 1m'
    }

    It 'formats duration 90061 seconds as long format with days: 1d 1hr 1min' {
        Format-FieldValue -Value 90061 -DataType 'duration' -Format 'long' -FormatOptions $null |
            Should -Be '1d 1hr 1min'
    }

    It 'formats duration under 1 day as short without day prefix' {
        # 3661 seconds = 1h 1m
        Format-FieldValue -Value 3661 -DataType 'duration' -Format 'short' -FormatOptions $null |
            Should -Be '1h 1m'
    }

    It 'formats unix_timestamp as raw string' {
        Format-FieldValue -Value 1738857600 -DataType 'unix_timestamp' -Format 'raw' -FormatOptions $null |
            Should -Be '1738857600'
    }

    It 'formats unix_timestamp hours format as a time string matching pattern' {
        # Use a timestamp 2 hours and 5 minutes in the future
        $futureTs = [DateTimeOffset]::UtcNow.AddHours(2).AddMinutes(5).ToUnixTimeSeconds()
        $result = Format-FieldValue -Value $futureTs -DataType 'unix_timestamp' -Format 'hours' -FormatOptions $null
        $result | Should -Match '^\d+h \d+m$'
    }

    It 'returns raw string for unknown data type' {
        Format-FieldValue -Value 'anything' -DataType 'unknown_type' -Format $null -FormatOptions $null |
            Should -Be 'anything'
    }
}

Describe 'Get-AllKeys' {
    It 'returns top-level keys' {
        $data = [PSCustomObject]@{ version = '1.0'; cwd = '/tmp' }
        $result = Get-AllKeys $data ''
        $result | Should -Contain 'version'
        $result | Should -Contain 'cwd'
    }

    It 'returns nested keys with dot notation' {
        $inner = [PSCustomObject]@{ display_name = 'Opus' }
        $data  = [PSCustomObject]@{ model = $inner }
        $result = Get-AllKeys $data ''
        $result | Should -Contain 'model'
        $result | Should -Contain 'model.display_name'
    }

    It 'returns empty array for null input' {
        $result = Get-AllKeys $null ''
        $result.Count | Should -Be 0
    }
}

Describe 'Format-Field with dataType' {
    BeforeAll {
        $data = [PSCustomObject]@{
            cost = [PSCustomObject]@{ total_cost_usd = 0.01234 }
            model = [PSCustomObject]@{ display_name = 'Opus' }
        }
    }

    It 'formats field value using dataType=currency' {
        $field = [PSCustomObject]@{
            type='field'; key='cost.total_cost_usd'; dataType='currency'; format=$null; formatOptions=$null; fg=$null; bg=$null
        }
        Format-Field $field $data | Should -Be '0.01'
    }

    It 'falls back to raw value when dataType is not set' {
        $field = [PSCustomObject]@{
            type='field'; key='model.display_name'; dataType=$null; format=$null; formatOptions=$null; fg=$null; bg=$null
        }
        Format-Field $field $data | Should -Be 'Opus'
    }
}

Describe 'Invoke-Main JSON persistence' {
    BeforeAll {
        $configPath = Join-Path $TestDrive 'statusline-config.json'
        $config = @{
            lines = @(@{ fields = @(@{ type='field'; key='version'; fg=$null; bg=$null }) })
            knownKeys = @('version')
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $configPath -Value $config -Encoding UTF8
    }

    It 'writes last-payload.json next to the config file' {
        $payloadPath = Join-Path $TestDrive 'last-payload.json'
        Invoke-Main -ConfigPath $configPath -InputJson '{"version":"1.0"}'
        Test-Path $payloadPath | Should -Be $true
        Get-Content $payloadPath -Raw | Should -Match '"version"'
    }

    It 'does not crash when Set-Content fails — payload directory blocked by a directory at that path' {
        # Create a DIRECTORY at the location where last-payload.json would be written.
        # Set-Content cannot write a file when a directory exists at that path — it throws.
        # The try/catch in Invoke-Main must swallow this error silently.
        $blockedDir = Join-Path $TestDrive 'blocked'
        New-Item -ItemType Directory -Path $blockedDir -Force | Out-Null
        # Create a DIRECTORY called 'last-payload.json' to block the file write
        New-Item -ItemType Directory -Path (Join-Path $blockedDir 'last-payload.json') -Force | Out-Null
        $blockedConfig = Join-Path $blockedDir 'statusline-config.json'
        Set-Content -Path $blockedConfig -Value $config -Encoding UTF8
        { Invoke-Main -ConfigPath $blockedConfig -InputJson '{"version":"1.0"}' } | Should -Not -Throw
    }

    It 'sets script:KnownKeys from config so new_fields_indicator works in same call' {
        $cfgWithIndicator = @{
            lines = @(@{ fields = @(@{ type='new_fields_indicator'; fg=$null; bg=$null }) })
            knownKeys = @('version')
        } | ConvertTo-Json -Depth 10
        $indicatorConfig = Join-Path $TestDrive 'indicator-config.json'
        Set-Content -Path $indicatorConfig -Value $cfgWithIndicator -Encoding UTF8
        # Input has 'version' (known) + 'extra' (unknown) → indicator fires
        $result = Invoke-Main -ConfigPath $indicatorConfig -InputJson '{"version":"1.0","extra":"new"}'
        $result | Should -Match '●'
    }
}

Describe 'new_fields_indicator in Format-Field' {
    BeforeAll {
        $data = [PSCustomObject]@{
            model   = [PSCustomObject]@{ display_name = 'Opus' }
            version = '1.0'
            newKey  = 'surprise'
        }
    }

    AfterAll {
        $script:KnownKeys = $null
    }

    Context 'when unknown keys are present' {
        BeforeAll { $script:KnownKeys = @('model.display_name', 'version') }

        It 'returns indicator string with bullet and count' {
            $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null }
            $result = Format-Field $field $data
            $result | Should -Match '●'
            $result | Should -Match 'neue'
        }
    }

    Context 'when all keys are known' {
        BeforeAll { $script:KnownKeys = @('model', 'model.display_name', 'version', 'newKey') }

        It 'returns empty string' {
            $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null }
            Format-Field $field $data | Should -BeNullOrEmpty
        }
    }
}
