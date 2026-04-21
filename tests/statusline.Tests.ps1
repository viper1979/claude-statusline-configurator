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
    It 'renders with brackets by default' {
        $result = Format-ProgressBar -Value 30 -Style 'normal' -Fg $null
        $result | Should -Match '\['
        $result | Should -Match '30%'
    }

    It 'renders without brackets when Brackets is false' {
        $result = Format-ProgressBar -Value 30 -Style 'normal' -Fg $null -Brackets $false
        $result | Should -Not -Match '\['
        $result | Should -Match '30%'
    }

    It 'renders circle charset' {
        $result = Format-ProgressBar -Value 50 -Style 'normal' -Fg $null -Charset 'circle'
        $result | Should -Match '●'
        $result | Should -Match '○'
    }

    It 'renders ascii charset' {
        $result = Format-ProgressBar -Value 50 -Style 'normal' -Fg $null -Charset 'ascii'
        $result | Should -Match '#'
        $result | Should -Match '-'
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

    It 'uses custom threshold colors when Thresholds parameter is provided' {
        $thresholds = @(
            [PSCustomObject]@{ upTo = 50;  fg = '#0000ff' },
            [PSCustomObject]@{ upTo = 80;  fg = '#ff00ff' },
            [PSCustomObject]@{ upTo = 100; fg = '#00ffff' }
        )
        $low = Format-ProgressBar -Value 20 -Style 'color-coded' -Fg $null -Thresholds $thresholds
        $low | Should -Match '0;0;255'      # blue = #0000ff

        $mid = Format-ProgressBar -Value 65 -Style 'color-coded' -Fg $null -Thresholds $thresholds
        $mid | Should -Match '255;0;255'    # magenta = #ff00ff

        $high = Format-ProgressBar -Value 85 -Style 'color-coded' -Fg $null -Thresholds $thresholds
        $high | Should -Match '0;255;255'   # cyan = #00ffff
    }

    It 'uses yellow (mid) color for value exactly 50 in color-coded style' {
        $result = Format-ProgressBar -Value 50 -Style 'color-coded' -Fg $null
        # pct=50 is exclusive from low threshold (upTo=50), falls into mid (upTo=80) → yellow #facc15
        $result | Should -Match '250;204;21'    # #facc15 = RGB 250,204,21
    }

    It 'uses red (high) color for value exactly 80 in color-coded style' {
        $result = Format-ProgressBar -Value 80 -Style 'color-coded' -Fg $null
        # pct=80 is exclusive from mid threshold (upTo=80), falls into high (upTo=100) → red #f87171
        $result | Should -Match '248;113;113'   # #f87171 = RGB 248,113,113
    }

    It 'renders pipe charset with filled and empty characters' {
        $result = Format-ProgressBar -Value 50 -Style 'normal' -Fg $null -Charset 'pipe'
        $result | Should -Match ([char]0x25AE)  # ▮ filled
        $result | Should -Match ([char]0x25AF)  # ▯ empty
    }

    It 'braille: left edge is edgeL char at 0 percent' {
        $result = Format-ProgressBar -Value 0 -Style 'normal' -Fg $null -Charset 'braille'
        $result[0] | Should -Be ([char]0x28CF)  # ⣏
    }

    It 'braille: left edge becomes fill char when first block is filled' {
        $result = Format-ProgressBar -Value 10 -Style 'normal' -Fg $null -Charset 'braille'
        $result[0] | Should -Be ([char]0x28FF)  # ⣿
    }

    It 'braille: right edge position is always edgeR char' {
        $result = Format-ProgressBar -Value 50 -Style 'normal' -Fg $null -Charset 'braille'
        $result[9] | Should -Be ([char]0x28F9)  # ⣹
    }

    It 'braille: brackets parameter is ignored' {
        $withBrackets    = Format-ProgressBar -Value 50 -Style 'normal' -Fg $null -Charset 'braille' -Brackets $true
        $withoutBrackets = Format-ProgressBar -Value 50 -Style 'normal' -Fg $null -Charset 'braille' -Brackets $false
        $withBrackets | Should -Be $withoutBrackets
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

    It 'wraps value with fg ANSI color when fg is set and fgOverride is true' {
        $field = [PSCustomObject]@{ type='field'; key='model.display_name'; fg='#ffffff'; fgOverride=$true; bg=$null }
        $result = Format-Field $field $sampleData
        # #ffffff = RGB 255,255,255
        $result | Should -Match '255;255;255'
        $result | Should -Match 'Opus'
    }

    It 'renders static type with its text' {
        $field = [PSCustomObject]@{ type='static'; text=' | '; fg=$null; bg=$null }
        Format-Field $field $sampleData | Should -Be ' | '
    }

    It 'renders static type with fg color when fgOverride is true' {
        $field = [PSCustomObject]@{ type='static'; text='|'; fg='#888888'; fgOverride=$true; bg=$null }
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

    It 'renders progressbar without brackets when barBrackets is false' {
        $field = [PSCustomObject]@{ type='progressbar'; key='context_window.used_percentage'; progressStyle='normal'; barBrackets=$false; barCharset='block'; fg=$null; bg=$null }
        $result = Format-Field $field $sampleData
        $result | Should -Match '45%'
        $result | Should -Not -Match '\['
    }

    It 'renders progressbar with circle charset' {
        $field = [PSCustomObject]@{ type='progressbar'; key='context_window.used_percentage'; progressStyle='normal'; barBrackets=$true; barCharset='circle'; fg=$null; bg=$null }
        $result = Format-Field $field $sampleData
        $result | Should -Match '●'
        $result | Should -Match '○'
    }

    It 'renders progressbar with ascii charset and no brackets' {
        $field = [PSCustomObject]@{ type='progressbar'; key='context_window.used_percentage'; progressStyle='normal'; barBrackets=$false; barCharset='ascii'; fg=$null; bg=$null }
        $result = Format-Field $field $sampleData
        $result | Should -Match '#'
        $result | Should -Match '-'
        $result | Should -Not -Match '\['
    }

    It 'returns empty string for unknown field path' {
        $field = [PSCustomObject]@{ type='field'; key='does.not.exist'; fg=$null; bg=$null }
        Format-Field $field $sampleData | Should -BeNullOrEmpty
    }

    It 'renders progressbar at 0% when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{ type='progressbar'; key='missing.value'; progressStyle='block'; fg=$null; bg=$null }
        $result = Format-Field $field $data
        $result | Should -Match '0%'
        $result | Should -Not -BeNullOrEmpty
    }

    It 'renders progressbar raw style as 0 when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{ type='progressbar'; key='missing.value'; progressStyle='raw'; fg=$null; bg=$null }
        $result = Format-Field $field $data
        $result | Should -Match '^.*0.*$'
        $result | Should -Not -Match '%'
    }

    It 'renders worktree.branch as none when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{ type='field'; key='worktree.branch'; fg=$null; bg=$null; dataType='string'; format=$null; formatOptions=$null; pathDepth=$null }
        Format-Field $field $data | Should -Be 'none'
    }

    It 'renders worktree.branch as none when value is empty string' {
        $data  = [PSCustomObject]@{ worktree = [PSCustomObject]@{ branch = '' } }
        $field = [PSCustomObject]@{ type='field'; key='worktree.branch'; fg=$null; bg=$null; dataType='string'; format=$null; formatOptions=$null; pathDepth=$null }
        Format-Field $field $data | Should -Be 'none'
    }

    It 'applies pathDepth truncation to cwd field' {
        $data  = [PSCustomObject]@{ cwd = '/home/user/myproject' }
        $field = [PSCustomObject]@{ type='field'; key='cwd'; fg=$null; bg=$null; pathDepth=2; dataType=$null; format=$null; formatOptions=$null }
        $result = Format-Field $field $data
        $result | Should -Match 'user/myproject'
        $result | Should -Match '\.\.\.'
    }

    It 'shows full path for cwd field when pathDepth is null' {
        $data  = [PSCustomObject]@{ cwd = '/home/user/myproject' }
        $field = [PSCustomObject]@{ type='field'; key='cwd'; fg=$null; bg=$null; pathDepth=$null; dataType=$null; format=$null; formatOptions=$null }
        $result = Format-Field $field $data
        $result | Should -Match '/home/user/myproject'
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

    It 'returns error message when config file does not exist' {
        $result = Invoke-Main -ConfigPath 'C:\nonexistent\config.json' -InputJson '{}'
        $result | Should -Match '\[.*statusline\]'
        $result | Should -Match 'Config not found'
    }

    It 'returns error message when input JSON is malformed' {
        $result = Invoke-Main -ConfigPath $configPath -InputJson 'not json'
        $result | Should -Match '\[.*statusline\]'
        $result | Should -Match 'Input JSON invalid'
    }

    It 'returns error message when config JSON is malformed' {
        $badConfig = Join-Path $TestDrive 'bad-config.json'
        Set-Content -Path $badConfig -Value 'not json' -Encoding UTF8
        $result = Invoke-Main -ConfigPath $badConfig -InputJson '{}'
        $result | Should -Match '\[.*statusline\]'
        $result | Should -Match 'Config JSON invalid'
    }

    It 'auto-detects git branch when not present in input JSON' {
        $branchConfig = @{
            lines = @(@{ fields = @(@{ type='field'; key='worktree.branch'; fg=$null; bg=$null; dataType='string'; format=$null; formatOptions=$null; pathDepth=$null }) })
        } | ConvertTo-Json -Depth 10
        $branchConfigPath = Join-Path $TestDrive 'branch-config.json'
        Set-Content -Path $branchConfigPath -Value $branchConfig -Encoding UTF8
        Mock git { 'feature/auto-detected' }
        $result = Invoke-Main -ConfigPath $branchConfigPath -InputJson '{}'
        $result | Should -Match 'feature/auto-detected'
    }

    It 'does not overwrite existing worktree.branch from input JSON' {
        $branchConfig = @{
            lines = @(@{ fields = @(@{ type='field'; key='worktree.branch'; fg=$null; bg=$null; dataType='string'; format=$null; formatOptions=$null; pathDepth=$null }) })
        } | ConvertTo-Json -Depth 10
        $branchConfigPath = Join-Path $TestDrive 'branch-existing-config.json'
        Set-Content -Path $branchConfigPath -Value $branchConfig -Encoding UTF8
        Mock git { 'feature/from-git' }
        $result = Invoke-Main -ConfigPath $branchConfigPath -InputJson '{"worktree":{"branch":"from-json"}}'
        $result | Should -Match 'from-json'
        $result | Should -Not -Match 'from-git'
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
            Should -BeExactly '12K'
    }

    It 'formats number with m suffix' {
        Format-FieldValue -Value 12000000 -DataType 'number' -Format 'm' -FormatOptions $null |
            Should -BeExactly '12M'
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

    It 'formats duration_ms 5000000 ms as hours format: 1h 23m' {
        # 5000000 ms = 5000 s = 83m = 1h 23m
        Format-FieldValue -Value 5000000 -DataType 'duration_ms' -Format 'hours' -FormatOptions $null |
            Should -Be '1h 23m'
    }

    It 'formats duration_ms 30000 ms as short format: 0h 0m' {
        # 30000 ms = 30 s — less than 1 minute, displays as 0h 0m
        Format-FieldValue -Value 30000 -DataType 'duration_ms' -Format 'short' -FormatOptions $null |
            Should -Be '0h 0m'
    }

    It 'formats duration_ms 90061000 ms as short format with days: 1d 1h 1m' {
        # 90061000 ms = 90061 s = 1d 1h 1m
        Format-FieldValue -Value 90061000 -DataType 'duration_ms' -Format 'short' -FormatOptions $null |
            Should -Be '1d 1h 1m'
    }

    It 'formats duration_ms 90061000 ms as long format with days: 1d 1hr 1min' {
        Format-FieldValue -Value 90061000 -DataType 'duration_ms' -Format 'long' -FormatOptions $null |
            Should -Be '1d 1hr 1min'
    }

    # --- null fallback tests ---
    It 'returns 0h 0m for null duration_ms value' {
        Format-FieldValue -Value $null -DataType 'duration_ms' -Format 'short' -FormatOptions $null |
            Should -Be '0h 0m'
    }

    It 'returns 0 for null number value with raw format' {
        Format-FieldValue -Value $null -DataType 'number' -Format 'raw' -FormatOptions $null |
            Should -Be '0'
    }

    It 'returns 0.00 for null currency value' {
        Format-FieldValue -Value $null -DataType 'currency' -Format $null -FormatOptions $null |
            Should -Be '0.00'
    }

    It 'returns false for null bool value' {
        Format-FieldValue -Value $null -DataType 'bool' -Format $null -FormatOptions $null |
            Should -Be 'false'
    }

    It 'returns empty string for null string value' {
        Format-FieldValue -Value $null -DataType 'string' -Format $null -FormatOptions $null |
            Should -Be ''
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

    It 'auto format returns raw integer below 1000' {
        Format-FieldValue -Value 456 -DataType 'number' -Format 'auto' -FormatOptions $null |
            Should -Be '456'
    }

    It 'auto format rounds to k for thousands' {
        Format-FieldValue -Value 32768 -DataType 'number' -Format 'auto' -FormatOptions $null |
            Should -BeExactly '33K'
    }

    It 'auto format rounds to m for millions' {
        Format-FieldValue -Value 938723466 -DataType 'number' -Format 'auto' -FormatOptions $null |
            Should -BeExactly '939M'
    }

    It 'auto format rounds to b for billions' {
        Format-FieldValue -Value 12000000000 -DataType 'number' -Format 'auto' -FormatOptions $null |
            Should -BeExactly '12B'
    }

    It 'deprecated k format falls back to auto behavior' {
        Format-FieldValue -Value 5000 -DataType 'number' -Format 'k' -FormatOptions $null |
            Should -BeExactly '5K'
    }

    It 'deprecated m format falls back to auto behavior' {
        Format-FieldValue -Value 5000000 -DataType 'number' -Format 'm' -FormatOptions $null |
            Should -BeExactly '5M'
    }

    It 'deprecated b format falls back to auto behavior' {
        Format-FieldValue -Value 2000000000 -DataType 'number' -Format 'b' -FormatOptions $null |
            Should -BeExactly '2B'
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
        # Parent container keys are not included — only leaf keys (fix for false new_fields_indicator)
        $result | Should -Not -Contain 'model'
        $result | Should -Contain 'model.display_name'
    }

    It 'returns leaf keys but not parent container objects' {
        $data = [PSCustomObject]@{
            model   = [PSCustomObject]@{ id = 'x'; display_name = 'Opus' }
            version = '1.0'
        }
        $keys = Get-AllKeys $data ''
        $keys | Should -Not -Contain 'model'
        $keys | Should -Contain 'model.id'
        $keys | Should -Contain 'model.display_name'
        $keys | Should -Contain 'version'
    }

    It 'returns nested leaf keys three levels deep' {
        $inner = [PSCustomObject]@{ used_percentage = 42 }
        $mid   = [PSCustomObject]@{ five_hour = $inner }
        $data  = [PSCustomObject]@{ rate_limits = $mid }
        $keys  = Get-AllKeys $data ''
        $keys | Should -Not -Contain 'rate_limits'
        $keys | Should -Not -Contain 'rate_limits.five_hour'
        $keys | Should -Contain 'rate_limits.five_hour.used_percentage'
    }

    It 'returns array values as leaf keys and skips top-level null values' {
        $data = [PSCustomObject]@{
            tags    = @('a', 'b')
            missing = $null
        }
        $keys = Get-AllKeys $data ''
        $keys | Should -Contain 'tags'
        # null leaf values are skipped — the API returns null for absent or unavailable data, which should not trigger new-field detection
        $keys | Should -Not -Contain 'missing'
    }

    It 'skips null leaf values' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                used_percentage = 42
                current_usage   = $null
            }
        }
        $keys = Get-AllKeys $data ''
        $keys | Should -Contain 'context_window.used_percentage'
        $keys | Should -Not -Contain 'context_window.current_usage'
    }

    It 'returns empty array for null input' {
        $keys = Get-AllKeys $null ''
        $keys | Should -BeNullOrEmpty
    }

    It 'does not recurse into string added via Add-Member -Force (PSObject wrapper quirk)' {
        # Regression: Add-Member -Force on native-command output (e.g. git) wraps the string in
        # a PSObject that falsely claims -is [PSCustomObject] = True. Get-AllKeys must not recurse
        # into the string; it must yield "worktree.branch", NOT "worktree.branch.Length".
        $data = [PSCustomObject]@{}
        $data | Add-Member -NotePropertyName 'worktree' -NotePropertyValue ([PSCustomObject]@{}) -Force
        # Simulate the exact enrichment: Add-Member -Force on a string (as Invoke-Main does after git rev-parse)
        $data.worktree | Add-Member -NotePropertyName 'branch' -NotePropertyValue 'master' -Force

        $keys = Get-AllKeys $data ''
        $keys | Should -Contain 'worktree.branch'
        $keys | Should -Not -Contain 'worktree.branch.Length'
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

Describe 'Truncate-Path' {
    It 'returns full path when depth is null' {
        Truncate-Path -Value '/home/user/myproject' -Depth $null | Should -Be '/home/user/myproject'
    }

    It 'returns full path when depth equals segment count' {
        Truncate-Path -Value '/home/user/myproject' -Depth 3 | Should -Be '/home/user/myproject'
    }

    It 'returns full path when depth exceeds segment count' {
        Truncate-Path -Value '/home/user/myproject' -Depth 10 | Should -Be '/home/user/myproject'
    }

    It 'truncates unix path to last 1 segment with ... prefix' {
        Truncate-Path -Value '/home/user/myproject' -Depth 1 | Should -Be '.../myproject'
    }

    It 'truncates unix path to last 2 segments with ... prefix' {
        Truncate-Path -Value '/home/user/myproject' -Depth 2 | Should -Be '.../user/myproject'
    }

    It 'truncates windows path to last 3 segments with ... prefix' {
        Truncate-Path -Value 'C:\Das\ist\mein\super\langer\Pfad' -Depth 3 | Should -Be '...\super\langer\Pfad'
    }

    It 'truncates windows path to last 1 segment with ... prefix' {
        Truncate-Path -Value 'C:\Das\ist\mein\Pfad' -Depth 1 | Should -Be '...\Pfad'
    }
}

Describe 'Invoke-Main theme integration' {
    It 'uses active theme progressbar thresholds when rendering' {
        $config = @{
            activeTheme = 'theme1'
            themes      = @(
                @{
                    id                 = 'theme1'
                    name               = 'Test'
                    fieldFg            = $null
                    fieldBg            = $null
                    progressThresholds = @(
                        @{ upTo = 50;  fg = '#0000ff' },
                        @{ upTo = 80;  fg = '#ff00ff' },
                        @{ upTo = 100; fg = '#00ffff' }
                    )
                }
            )
            lines       = @(
                @{ fields = @(@{ type='progressbar'; key='context_window.used_percentage'; progressStyle='color-coded'; fg=$null; bg=$null }) }
            )
        } | ConvertTo-Json -Depth 10

        $configPath = Join-Path $TestDrive 'statusline-config.json'
        Set-Content -Path $configPath -Value $config -Encoding UTF8

        $input = '{"context_window":{"used_percentage":20}}'
        $result = Invoke-Main -ConfigPath $configPath -InputJson $input
        # blue = #0000ff = RGB 0,0,255
        $result | Should -Match '0;0;255'
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

    Context 'regression: branch string via Add-Member -Force does not trigger indicator' {
        BeforeAll {
            # Simulate data after git-enrichment: worktree.branch set with Add-Member -Force.
            # The PSObject wrapper quirk formerly made -is [PSCustomObject] return True for
            # this string, causing Get-AllKeys to emit "worktree.branch.Length" and the
            # indicator to fire even though no genuine new key was present.
            $script:KnownKeys = @('worktree.branch')
            $script:enrichedData = [PSCustomObject]@{}
            $script:enrichedData | Add-Member -NotePropertyName 'worktree' -NotePropertyValue ([PSCustomObject]@{}) -Force
            $script:enrichedData.worktree | Add-Member -NotePropertyName 'branch' -NotePropertyValue 'master' -Force
            $script:ThemeFg   = $null
            $script:ThemeBg   = $null
            $script:ThemesMap = @{}
        }

        It 'returns empty string when branch is the only key and is known' {
            $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null }
            Format-Field $field $script:enrichedData | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-RateLimitsData' {
    BeforeAll {
        $testDir = Join-Path $TestDrive 'ratelimits'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    }

    It 'returns $null when no source has data' {
        $emptyDir = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        $result = Get-RateLimitsData -ScriptDir $emptyDir -LastPayloadPath (Join-Path $emptyDir 'nonexistent.json')
        $result | Should -BeNullOrEmpty
    }

    It 'reads rate_limits from last-payload.json when present' {
        $payloadPath = Join-Path $testDir 'last-payload.json'
        @{
            version = '1.0'
            rate_limits = @{
                five_hour = @{ used_percentage = 42; resets_at = 1744123456 }
                seven_day = @{ used_percentage = 18; resets_at = 1744567890 }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $payloadPath -Encoding UTF8
        $result = Get-RateLimitsData -ScriptDir $testDir -LastPayloadPath $payloadPath
        $result.five_hour.used_percentage | Should -Be 42
        $result.seven_day.used_percentage | Should -Be 18
    }

    It 'returns $null from last-payload.json when it has no rate_limits' {
        $payloadNoRL = Join-Path $testDir 'payload-no-rl.json'
        @{ version = '1.0' } | ConvertTo-Json | Set-Content -Path $payloadNoRL -Encoding UTF8
        $noCacheDir = Join-Path $TestDrive 'nocache'
        New-Item -ItemType Directory -Path $noCacheDir -Force | Out-Null
        $result = Get-RateLimitsData -ScriptDir $noCacheDir -LastPayloadPath $payloadNoRL
        $result | Should -BeNullOrEmpty
    }

    It 'reads rate_limits from rate-limits-cache.json when last-payload lacks them' {
        # last-payload without rate_limits
        $payloadNoRL = Join-Path $testDir 'payload-cache-test.json'
        @{ version = '1.0' } | ConvertTo-Json | Set-Content -Path $payloadNoRL -Encoding UTF8
        # Cache file with rate_limits
        $cachePath = Join-Path $testDir 'rate-limits-cache.json'
        @{
            rate_limits = @{
                five_hour = @{ used_percentage = 55; resets_at = 1744200000 }
                seven_day = @{ used_percentage = 30; resets_at = 1744600000 }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $cachePath -Encoding UTF8
        $result = Get-RateLimitsData -ScriptDir $testDir -LastPayloadPath $payloadNoRL
        $result.five_hour.used_percentage | Should -Be 55
        $result.seven_day.used_percentage | Should -Be 30
    }

    It 'calls request-usage.ps1 plugin when no other source has data and reads cache afterward' {
        $pluginDir = Join-Path $TestDrive 'plugin-test'
        New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
        # No last-payload, no cache — plugin should be called
        # Create a fake plugin that writes a cache file
        $pluginPath = Join-Path $pluginDir 'request-usage.ps1'
        $cacheDest  = Join-Path $pluginDir 'rate-limits-cache.json'
        @"
@{
    rate_limits = @{
        five_hour = @{ used_percentage = 77; resets_at = 1744300000 }
        seven_day = @{ used_percentage = 25; resets_at = 1744700000 }
    }
} | ConvertTo-Json -Depth 5 | Set-Content -Path '$($cacheDest -replace "'","''")' -Encoding UTF8
"@ | Set-Content -Path $pluginPath -Encoding UTF8

        $emptyPayload = Join-Path $pluginDir 'last-payload.json'
        @{ version = '1.0' } | ConvertTo-Json | Set-Content -Path $emptyPayload -Encoding UTF8

        $result = Get-RateLimitsData -ScriptDir $pluginDir -LastPayloadPath $emptyPayload
        $result.five_hour.used_percentage | Should -Be 77
        $result.seven_day.used_percentage | Should -Be 25
    }

    It 'returns $null when plugin does not exist and no other source has data' {
        $noPluginDir = Join-Path $TestDrive 'no-plugin'
        New-Item -ItemType Directory -Path $noPluginDir -Force | Out-Null
        $emptyPayload = Join-Path $noPluginDir 'last-payload.json'
        @{ version = '1.0' } | ConvertTo-Json | Set-Content -Path $emptyPayload -Encoding UTF8
        $result = Get-RateLimitsData -ScriptDir $noPluginDir -LastPayloadPath $emptyPayload
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-Main rate-limits enrichment' {
    BeforeAll {
        $enrichDir = Join-Path $TestDrive 'enrich'
        New-Item -ItemType Directory -Path $enrichDir -Force | Out-Null
        $enrichConfig = Join-Path $enrichDir 'statusline-config.json'
        @{
            lines = @(@{
                fields = @(@{
                    type = 'progressbar'
                    key  = 'rate_limits.five_hour.used_percentage'
                    fg   = $null
                    bg   = $null
                    progressStyle = 'color-coded'
                })
            })
            knownKeys = @('rate_limits.five_hour.used_percentage')
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $enrichConfig -Encoding UTF8
    }

    It 'uses rate_limits from stdin when present — no enrichment needed' {
        $inputWithRL = @{
            rate_limits = @{
                five_hour = @{ used_percentage = 60 }
            }
        } | ConvertTo-Json -Depth 5
        $result = Invoke-Main -ConfigPath $enrichConfig -InputJson $inputWithRL
        $result | Should -Match '60%'
    }

    It 'enriches from last-payload.json when stdin lacks rate_limits' {
        # Write a last-payload with rate_limits
        $payloadPath = Join-Path $enrichDir 'last-payload.json'
        @{
            rate_limits = @{
                five_hour = @{ used_percentage = 35 }
            }
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $payloadPath -Encoding UTF8

        # Stdin without rate_limits — enrichment should kick in
        $result = Invoke-Main -ConfigPath $enrichConfig -InputJson '{"version":"1.0"}'
        $result | Should -Match '35%'
    }
}

Describe 'Format-Field added_dirs' {
    It 'returns count when added_dirs is a populated array' {
        $data  = [PSCustomObject]@{
            workspace = [PSCustomObject]@{ added_dirs = @('/path/a', '/path/b') }
        }
        $field = [PSCustomObject]@{
            type='field'; key='workspace.added_dirs'; fg=$null; bg=$null
            dataType='number'; format='raw'; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        $script:ThemeFg   = $null
        $script:ThemeBg   = $null
        $script:ThemesMap = @{}
        $script:PathKeys  = @()
        Format-Field $field $data | Should -Match '2'
    }

    It 'returns 0 when added_dirs is an empty array' {
        $data  = [PSCustomObject]@{
            workspace = [PSCustomObject]@{ added_dirs = @() }
        }
        $field = [PSCustomObject]@{
            type='field'; key='workspace.added_dirs'; fg=$null; bg=$null
            dataType='number'; format='raw'; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        $script:ThemeFg   = $null
        $script:ThemeBg   = $null
        $script:ThemesMap = @{}
        $script:PathKeys  = @()
        Format-Field $field $data | Should -Match '0'
    }
}

Describe 'Format-Field placeholder' {
    BeforeAll {
        $script:ThemeFg   = $null
        $script:ThemeBg   = $null
        $script:ThemesMap = @{}
        $script:PathKeys  = @()
    }

    It 'returns per-dataType default -- for string when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='agent.name'; fg=$null; bg=$null
            dataType='string'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be '--'
    }

    It 'returns per-dataType default 0 for number when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='cost.total_lines_added'; fg=$null; bg=$null
            dataType='number'; format='raw'; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be '0'
    }

    It 'returns per-dataType default $0.00 for currency when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='cost.total_cost_usd'; fg=$null; bg=$null
            dataType='currency'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be '$0.00'
    }

    It 'returns per-dataType default -- for duration_ms when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='cost.total_duration_ms'; fg=$null; bg=$null
            dataType='duration_ms'; format='short'; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be '--'
    }

    It 'returns per-dataType default -- for unix_timestamp when value is null' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='rate_limits.five_hour.resets_at'; fg=$null; bg=$null
            dataType='unix_timestamp'; format='hours'; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be '--'
    }

    It 'uses explicit placeholder over dataType default' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='agent.name'; fg=$null; bg=$null
            dataType='string'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null; placeholder='(kein Agent)'
        }
        Format-Field $field $data | Should -Be '(kein Agent)'
    }

    It 'returns empty string when placeholder is explicitly empty string' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='agent.name'; fg=$null; bg=$null
            dataType='string'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null; placeholder=''
        }
        Format-Field $field $data | Should -BeNullOrEmpty
    }

    It 'retains none for worktree.branch when no placeholder is set' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='worktree.branch'; fg=$null; bg=$null
            dataType='string'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null
        }
        Format-Field $field $data | Should -Be 'none'
    }

    It 'respects placeholder for worktree.branch when explicitly set' {
        $data  = [PSCustomObject]@{}
        $field = [PSCustomObject]@{
            type='field'; key='worktree.branch'; fg=$null; bg=$null
            dataType='string'; format=$null; fgOverride=$false; bgOverride=$false
            pathDepth=$null; formatOptions=$null; placeholder='main'
        }
        Format-Field $field $data | Should -Be 'main'
    }
}

Describe 'Compute-DerivedFields' {
    It 'sets cache_efficiency correctly for normal values' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                total_input_tokens = 10000
                current_usage = [PSCustomObject]@{
                    cache_read_input_tokens = 7340
                }
            }
        }
        Compute-DerivedFields -Data $data
        $data.context_window.cache_efficiency | Should -Be 73.4
    }

    It 'rounds cache_efficiency to 1 decimal place' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                total_input_tokens = 3
                current_usage = [PSCustomObject]@{
                    cache_read_input_tokens = 1
                }
            }
        }
        Compute-DerivedFields -Data $data
        # 1/3 * 100 = 33.333... -> rounded to 33.3
        $data.context_window.cache_efficiency | Should -Be 33.3
    }

    It 'does not set cache_efficiency when total_input_tokens is 0' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                total_input_tokens = 0
                current_usage = [PSCustomObject]@{
                    cache_read_input_tokens = 0
                }
            }
        }
        Compute-DerivedFields -Data $data
        $data.context_window.PSObject.Properties['cache_efficiency'] | Should -BeNullOrEmpty
    }

    It 'does not set cache_efficiency when total_input_tokens is null' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                current_usage = [PSCustomObject]@{
                    cache_read_input_tokens = 500
                }
            }
        }
        Compute-DerivedFields -Data $data
        $data.context_window.PSObject.Properties['cache_efficiency'] | Should -BeNullOrEmpty
    }

    It 'does not set cache_efficiency when context_window is missing' {
        $data = [PSCustomObject]@{}
        Compute-DerivedFields -Data $data
        # Get-NestedValue returns $null for both paths; guard prevents Add-Member
        $data.PSObject.Properties['context_window'] | Should -BeNullOrEmpty
    }

    It 'sets used_tokens correctly' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                context_window_size = 200000
                used_percentage     = 15
            }
        }
        Compute-DerivedFields -Data $data
        $data.context_window.used_tokens | Should -Be 30000
    }

    It 'sets remain_tokens correctly' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                context_window_size  = 200000
                remaining_percentage = 85
            }
        }
        Compute-DerivedFields -Data $data
        $data.context_window.remain_tokens | Should -Be 170000
    }

    It 'does not set used_tokens when context_window_size is 0' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                context_window_size = 0
                used_percentage     = 15
            }
        }
        Compute-DerivedFields -Data $data
        $data.context_window.PSObject.Properties['used_tokens'] | Should -BeNullOrEmpty
    }

    It 'does not set remain_tokens when remaining_percentage is null' {
        $data = [PSCustomObject]@{
            context_window = [PSCustomObject]@{
                context_window_size = 200000
            }
        }
        Compute-DerivedFields -Data $data
        $data.context_window.PSObject.Properties['remain_tokens'] | Should -BeNullOrEmpty
    }
}

Describe 'new_fields_indicator logging' {
    BeforeAll {
        $script:ThemeFg   = $null
        $script:ThemeBg   = $null
        $script:ThemesMap = @{}
        $script:KnownKeys = @('version')
        $logPath = Join-Path $TestDrive 'statusline-new-fields.log'
        $script:NewFieldsLogPath = $logPath
    }

    AfterEach {
        if (Test-Path $script:NewFieldsLogPath) { Remove-Item $script:NewFieldsLogPath -Force }
    }

    It 'writes unknown key names to log file when LogNewFields is true' {
        $script:LogNewFields = $true
        $data  = [PSCustomObject]@{ version = '1.0'; unknownKey = 'value' }
        $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null; fgOverride=$false; bgOverride=$false }
        Format-Field $field $data | Out-Null
        Test-Path $script:NewFieldsLogPath | Should -BeTrue
        $logContent = Get-Content $script:NewFieldsLogPath -Raw
        $logContent | Should -Match 'unknownKey'
    }

    It 'does not write log when LogNewFields is false' {
        $script:LogNewFields = $false
        $data  = [PSCustomObject]@{ version = '1.0'; unknownKey = 'value' }
        $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null; fgOverride=$false; bgOverride=$false }
        Format-Field $field $data | Out-Null
        Test-Path $script:NewFieldsLogPath | Should -BeFalse
    }

    It 'does not write log when no unknown keys exist' {
        $script:LogNewFields = $true
        $data  = [PSCustomObject]@{ version = '1.0' }
        $field = [PSCustomObject]@{ type='new_fields_indicator'; fg=$null; bg=$null; fgOverride=$false; bgOverride=$false }
        Format-Field $field $data | Out-Null
        Test-Path $script:NewFieldsLogPath | Should -BeFalse
    }
}

Describe 'Get-VisibleWidth' {
    It 'returns length of plain string' {
        Get-VisibleWidth 'hello' | Should -Be 5
    }

    It 'strips ANSI color codes before measuring' {
        # ESC[38;2;74;222;128m = green color, ESC[0m = reset
        $ansiString = "$([char]27)[38;2;74;222;128mhello$([char]27)[0m"
        Get-VisibleWidth $ansiString | Should -Be 5
    }

    It 'returns 0 for empty string' {
        Get-VisibleWidth '' | Should -Be 0
    }

    It 'returns 0 for ANSI-only string' {
        Get-VisibleWidth "$([char]27)[0m" | Should -Be 0
    }
}

Describe 'Build-Groups' {
    It 'returns one group per field when no mergeWithNext flags set' {
        $fields = @(
            [PSCustomObject]@{ type = 'field'; key = 'a' },
            [PSCustomObject]@{ type = 'field'; key = 'b' },
            [PSCustomObject]@{ type = 'field'; key = 'c' }
        )
        $groups = Build-Groups $fields
        $groups.Count | Should -Be 3
        $groups[0].Count | Should -Be 1
        $groups[1].Count | Should -Be 1
        $groups[2].Count | Should -Be 1
    }

    It 'groups two fields when first has mergeWithNext' {
        $fields = @(
            [PSCustomObject]@{ type = 'field'; key = 'a'; mergeWithNext = $true },
            [PSCustomObject]@{ type = 'field'; key = 'b' }
        )
        $groups = Build-Groups $fields
        $groups.Count | Should -Be 1
        $groups[0].Count | Should -Be 2
        $groups[0][0].key | Should -Be 'a'
        $groups[0][1].key | Should -Be 'b'
    }

    It 'creates three groups from chain A-B-C, D, E-F' {
        $fields = @(
            [PSCustomObject]@{ key = 'a'; mergeWithNext = $true },
            [PSCustomObject]@{ key = 'b'; mergeWithNext = $true },
            [PSCustomObject]@{ key = 'c' },
            [PSCustomObject]@{ key = 'd' },
            [PSCustomObject]@{ key = 'e'; mergeWithNext = $true },
            [PSCustomObject]@{ key = 'f' }
        )
        $groups = Build-Groups $fields
        $groups.Count | Should -Be 3
        $groups[0].Count | Should -Be 3   # a, b, c
        $groups[1].Count | Should -Be 1   # d
        $groups[2].Count | Should -Be 2   # e, f
    }

    It 'handles single field' {
        $fields = @([PSCustomObject]@{ key = 'a' })
        $groups = Build-Groups $fields
        $groups.Count | Should -Be 1
    }

    It 'handles empty array' {
        $groups = Build-Groups @()
        $groups.Count | Should -Be 0
    }
}

Describe 'Format-Lines-Aligned' {
    It 'renders single line without padding' {
        $lines = @([PSCustomObject]@{
            fields = @(
                [PSCustomObject]@{ type = 'static'; text = 'hi'; fg = $null; bg = $null }
            )
        })
        $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
        $result | Should -Be 'hi'
    }

    It 'pads shorter group to match longer group across lines' {
        $lines = @(
            [PSCustomObject]@{ mergeWithNext = $true; fields = @(
                [PSCustomObject]@{ type = 'static'; text = 'hi';    fg = $null; bg = $null },
                [PSCustomObject]@{ type = 'static'; text = ' | ';   fg = $null; bg = $null },
                [PSCustomObject]@{ type = 'static'; text = 'world'; fg = $null; bg = $null }
            )},
            [PSCustomObject]@{ fields = @(
                [PSCustomObject]@{ type = 'static'; text = 'hello'; fg = $null; bg = $null },
                [PSCustomObject]@{ type = 'static'; text = ' | ';   fg = $null; bg = $null },
                [PSCustomObject]@{ type = 'static'; text = 'x';     fg = $null; bg = $null }
            )}
        )
        $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
        $resultLines = $result -split "`n"
        # Group 1: 'hi' padded to width of 'hello' (5), group 2: ' | ' (3), group 3: no padding on last
        $resultLines[0] | Should -Be 'hi    | world'
        $resultLines[1] | Should -Be 'hello | x'
    }

    It 'groups merged fields and aligns by group width' {
        $lines = @(
            [PSCustomObject]@{ mergeWithNext = $true; fields = @(
                [PSCustomObject]@{ type = 'static'; text = 'a'; fg = $null; bg = $null; mergeWithNext = $true },
                [PSCustomObject]@{ type = 'static'; text = 'b'; fg = $null; bg = $null },
                [PSCustomObject]@{ type = 'static'; text = 'X'; fg = $null; bg = $null }
            )},
            [PSCustomObject]@{ fields = @(
                [PSCustomObject]@{ type = 'static'; text = 'longgroup'; fg = $null; bg = $null },
                [PSCustomObject]@{ type = 'static'; text = 'Y';         fg = $null; bg = $null }
            )}
        )
        $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
        $resultLines = $result -split "`n"
        # Group 1: 'ab' (2 chars) vs 'longgroup' (9 chars) → 'ab' padded to 9
        $resultLines[0] | Should -Be 'ab       X'
        $resultLines[1] | Should -Be 'longgroupY'
    }

    It 'skips empty lines' {
        $lines = @(
            [PSCustomObject]@{ fields = @() },
            [PSCustomObject]@{ fields = @(
                [PSCustomObject]@{ type = 'static'; text = 'ok'; fg = $null; bg = $null }
            )}
        )
        $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
        $result | Should -Be 'ok'
    }

    It 'does not pad the last group of each line' {
        $lines = @(
            [PSCustomObject]@{ fields = @(
                [PSCustomObject]@{ type = 'static'; text = 'short'; fg = $null; bg = $null }
            )},
            [PSCustomObject]@{ fields = @(
                [PSCustomObject]@{ type = 'static'; text = 'much longer text'; fg = $null; bg = $null }
            )}
        )
        $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
        $resultLines = $result -split "`n"
        # Last group — no trailing padding on either line
        $resultLines[0] | Should -Be 'short'
        $resultLines[1] | Should -Be 'much longer text'
    }

    It 'pads correctly when groups contain ANSI color codes' {
        # ESC[31m = red, ESC[0m = reset — 'hi' has 2 visible chars despite ANSI wrapper
        $red   = "$([char]27)[31m"
        $reset = "$([char]27)[0m"
        $lines = @(
            [PSCustomObject]@{ mergeWithNext = $true; fields = @(
                [PSCustomObject]@{ type = 'static'; text = "${red}hi${reset}";    fg = $null; bg = $null },
                [PSCustomObject]@{ type = 'static'; text = 'X';                  fg = $null; bg = $null }
            )},
            [PSCustomObject]@{ fields = @(
                [PSCustomObject]@{ type = 'static'; text = 'hello'; fg = $null; bg = $null },
                [PSCustomObject]@{ type = 'static'; text = 'Y';     fg = $null; bg = $null }
            )}
        )
        $result = Format-Lines-Aligned $lines ([PSCustomObject]@{})
        $resultLines = $result -split "`n"
        # Group 1: 'hi' (2 visible) padded to width of 'hello' (5) → 3 spaces appended after ANSI sequence
        # Visible: 'hi   X' and 'helloY'
        $resultLines[0] | Should -Match 'hi.*   X$'
        $resultLines[1] | Should -Be 'helloY'
    }
}

Describe 'Format-Progressbar Braille' {
    It 'shows all filled chars at 100%' {
        $result = Format-Progressbar -Value 100 -Charset 'braille'
        # At 100%, all 10 positions should be the filled braille char ⣿ (U+28FF)
        $bar = $result -replace ' 100%$', ''
        $bar | Should -Be ([string][char]0x28FF * 10)
    }

    It 'shows right-edge char at last position when not full' {
        $result = Format-Progressbar -Value 90 -Charset 'braille'
        $bar = $result -replace ' 90%$', ''
        # Position 9 (last) must be the right-edge char ⣹ (U+28F9), not ⣿
        $bar[-1] | Should -Be ([char]0x28F9)
        # Positions 0-8 should all be filled ⣿
        $bar.Substring(0, 9) | Should -Be ([string][char]0x28FF * 9)
    }

    It 'shows left-edge char at position 0 when empty' {
        $result = Format-Progressbar -Value 0 -Charset 'braille'
        $bar = $result -replace ' 0%$', ''
        # Position 0 must be the left-edge char ⣏ (U+28CF)
        $bar[0] | Should -Be ([char]0x28CF)
        # Position 9 (last) must be the right-edge char ⣹ (U+28F9)
        $bar[-1] | Should -Be ([char]0x28F9)
    }
}

Describe 'Build-LineGroups' {
    It 'returns one group per line when no mergeWithNext set' {
        $lines = @(
            [PSCustomObject]@{ id = 'a' },
            [PSCustomObject]@{ id = 'b' }
        )
        $groups = Build-LineGroups $lines
        $groups.Count | Should -Be 2
        $groups[0].Count | Should -Be 1
        $groups[1].Count | Should -Be 1
    }

    It 'groups two lines when first has mergeWithNext' {
        $lines = @(
            [PSCustomObject]@{ id = 'a'; mergeWithNext = $true },
            [PSCustomObject]@{ id = 'b' }
        )
        $groups = Build-LineGroups $lines
        $groups.Count | Should -Be 1
        $groups[0].Count | Should -Be 2
    }

    It 'creates two groups from A+B and C' {
        $lines = @(
            [PSCustomObject]@{ id = 'a'; mergeWithNext = $true },
            [PSCustomObject]@{ id = 'b' },
            [PSCustomObject]@{ id = 'c' }
        )
        $groups = Build-LineGroups $lines
        $groups.Count | Should -Be 2
        $groups[0].Count | Should -Be 2
        $groups[1].Count | Should -Be 1
    }

    It 'handles empty array' {
        $groups = Build-LineGroups @()
        $groups.Count | Should -Be 0
    }
}

Describe 'Format-Line-Group single line' {
    It 'renders a single static field' {
        $lines = @([PSCustomObject]@{
            fields = @(
                [PSCustomObject]@{ type = 'static'; text = 'hi'; fg = $null; bg = $null }
            )
        })
        $result = Format-Line-Group $lines ([PSCustomObject]@{})
        $result | Should -Be 'hi'
    }
}

Describe 'Get-EffortLevel' {
    It 'returns effortLevel from user settings when project settings are absent' {
        # Arrange: write a user settings file with effortLevel
        $userDir = Join-Path $TestDrive 'user-effort'
        New-Item -ItemType Directory -Path (Join-Path $userDir '.claude') -Force | Out-Null
        $userSettings = Join-Path $userDir '.claude\settings.json'
        @{ effortLevel = 'high' } | ConvertTo-Json | Set-Content -Path $userSettings -Encoding UTF8

        # Act: override USERPROFILE env var so Get-EffortLevel reads from our temp dir.
        # Push-Location to a clean dir so no project .claude/settings.json is found.
        $emptyProject = Join-Path $TestDrive 'empty-project'
        New-Item -ItemType Directory -Path $emptyProject -Force | Out-Null
        $result = Push-Location $emptyProject
        try {
            $env:USERPROFILE_BACKUP = $env:USERPROFILE
            $env:USERPROFILE = $userDir
            $result = Get-EffortLevel
        } finally {
            $env:USERPROFILE = $env:USERPROFILE_BACKUP
            Remove-Item Env:USERPROFILE_BACKUP -ErrorAction SilentlyContinue
            Pop-Location
        }

        # Assert
        $result | Should -Be 'high'
    }

    It 'project .claude/settings.json overrides user settings' {
        # Arrange: user settings say "medium", project says "max"
        $userDir = Join-Path $TestDrive 'user-effort-override'
        New-Item -ItemType Directory -Path (Join-Path $userDir '.claude') -Force | Out-Null
        $userSettings = Join-Path $userDir '.claude\settings.json'
        @{ effortLevel = 'medium' } | ConvertTo-Json | Set-Content -Path $userSettings -Encoding UTF8

        $projectDir = Join-Path $TestDrive 'project-effort-override'
        New-Item -ItemType Directory -Path (Join-Path $projectDir '.claude') -Force | Out-Null
        $projectSettings = Join-Path $projectDir '.claude\settings.json'
        @{ effortLevel = 'max' } | ConvertTo-Json | Set-Content -Path $projectSettings -Encoding UTF8

        $result = Push-Location $projectDir
        try {
            $env:USERPROFILE_BACKUP = $env:USERPROFILE
            $env:USERPROFILE = $userDir
            $result = Get-EffortLevel
        } finally {
            $env:USERPROFILE = $env:USERPROFILE_BACKUP
            Remove-Item Env:USERPROFILE_BACKUP -ErrorAction SilentlyContinue
            Pop-Location
        }

        $result | Should -Be 'max'
    }

    It 'returns null when neither file has effortLevel' {
        $userDir = Join-Path $TestDrive 'user-no-effort'
        New-Item -ItemType Directory -Path (Join-Path $userDir '.claude') -Force | Out-Null
        @{ model = 'opus' } | ConvertTo-Json | Set-Content -Path (Join-Path $userDir '.claude\settings.json') -Encoding UTF8

        $emptyProject = Join-Path $TestDrive 'project-no-effort'
        New-Item -ItemType Directory -Path $emptyProject -Force | Out-Null
        $result = Push-Location $emptyProject
        try {
            $env:USERPROFILE_BACKUP = $env:USERPROFILE
            $env:USERPROFILE = $userDir
            $result = Get-EffortLevel
        } finally {
            $env:USERPROFILE = $env:USERPROFILE_BACKUP
            Remove-Item Env:USERPROFILE_BACKUP -ErrorAction SilentlyContinue
            Pop-Location
        }

        $result | Should -BeNullOrEmpty
    }

    It 'silently ignores corrupted settings file and falls through' {
        $userDir = Join-Path $TestDrive 'user-corrupt-effort'
        New-Item -ItemType Directory -Path (Join-Path $userDir '.claude') -Force | Out-Null
        Set-Content -Path (Join-Path $userDir '.claude\settings.json') -Value 'not valid json {{{' -Encoding UTF8

        $emptyProject = Join-Path $TestDrive 'project-corrupt-effort'
        New-Item -ItemType Directory -Path $emptyProject -Force | Out-Null
        $result = Push-Location $emptyProject
        try {
            $env:USERPROFILE_BACKUP = $env:USERPROFILE
            $env:USERPROFILE = $userDir
            { Get-EffortLevel } | Should -Not -Throw
            $result = Get-EffortLevel
        } finally {
            $env:USERPROFILE = $env:USERPROFILE_BACKUP
            Remove-Item Env:USERPROFILE_BACKUP -ErrorAction SilentlyContinue
            Pop-Location
        }

        $result | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-Main effort_level enrichment' {
    BeforeAll {
        $effortDir = Join-Path $TestDrive 'effort-enrich'
        New-Item -ItemType Directory -Path $effortDir -Force | Out-Null
        $effortConfig = Join-Path $effortDir 'statusline-config.json'
        @{
            lines = @(@{
                fields = @(@{
                    type   = 'effort_level'
                    format = 'raw'
                    fg     = $null
                    bg     = $null
                })
            })
            knownKeys = @('effort_level')
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $effortConfig -Encoding UTF8
    }

    It 'enriches effort_level from user settings.json when stdin lacks it' {
        $userDir = Join-Path $TestDrive 'effort-enrich-user'
        New-Item -ItemType Directory -Path (Join-Path $userDir '.claude') -Force | Out-Null
        @{ effortLevel = 'high' } | ConvertTo-Json | Set-Content -Path (Join-Path $userDir '.claude\settings.json') -Encoding UTF8

        $emptyProject = Join-Path $TestDrive 'effort-enrich-project'
        New-Item -ItemType Directory -Path $emptyProject -Force | Out-Null
        $result = Push-Location $emptyProject
        try {
            $env:USERPROFILE_BACKUP = $env:USERPROFILE
            $env:USERPROFILE = $userDir
            $result = Invoke-Main -ConfigPath $effortConfig -InputJson '{}'
        } finally {
            $env:USERPROFILE = $env:USERPROFILE_BACKUP
            Remove-Item Env:USERPROFILE_BACKUP -ErrorAction SilentlyContinue
            Pop-Location
        }

        $result | Should -Be 'high'
    }
}

Describe 'Format-Field effort_level rendering' {
    BeforeAll {
        $script:ThemeFg   = $null
        $script:ThemeBg   = $null
        $script:ThemesMap = @{}
        $script:PathKeys  = @()

        function script:Make-EffortField($fmt) {
            [PSCustomObject]@{
                type        = 'effort_level'
                format      = $fmt
                fg          = $null
                bg          = $null
                fgOverride  = $false
                bgOverride  = $false
            }
        }

        function script:Make-EffortData($level) {
            [PSCustomObject]@{ effort_level = $level }
        }
    }

    It "format=raw returns raw value 'medium'" {
        Format-Field (Make-EffortField 'raw') (Make-EffortData 'medium') | Should -Be 'medium'
    }

    It "format=raw returns raw value 'low'" {
        Format-Field (Make-EffortField 'raw') (Make-EffortData 'low') | Should -Be 'low'
    }

    It "format=short returns 'M' for medium" {
        Format-Field (Make-EffortField 'short') (Make-EffortData 'medium') | Should -Be 'M'
    }

    It "format=short returns 'L' for low" {
        Format-Field (Make-EffortField 'short') (Make-EffortData 'low') | Should -Be 'L'
    }

    It "format=short returns 'H' for high" {
        Format-Field (Make-EffortField 'short') (Make-EffortData 'high') | Should -Be 'H'
    }

    It "format=short returns 'X' for max" {
        Format-Field (Make-EffortField 'short') (Make-EffortData 'max') | Should -Be 'X'
    }

    It 'format=symbol emits correct UTF-8 bytes for medium (U+25D0 ◐)' {
        $output = Format-Field (Make-EffortField 'symbol') (Make-EffortData 'medium')
        $bytes  = [System.Text.Encoding]::UTF8.GetBytes($output)
        $hex    = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''
        # U+25D0 ◐ → UTF-8: E2 97 90
        $hex | Should -Match 'E29790'
    }

    It 'format=symbol emits correct UTF-8 bytes for low (U+25CB ○)' {
        $output = Format-Field (Make-EffortField 'symbol') (Make-EffortData 'low')
        $bytes  = [System.Text.Encoding]::UTF8.GetBytes($output)
        $hex    = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''
        # U+25CB ○ → UTF-8: E2 97 8B
        $hex | Should -Match 'E2978B'
    }

    It 'format=symbol emits correct UTF-8 bytes for high (U+25CF ●)' {
        $output = Format-Field (Make-EffortField 'symbol') (Make-EffortData 'high')
        $bytes  = [System.Text.Encoding]::UTF8.GetBytes($output)
        $hex    = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''
        # U+25CF ● → UTF-8: E2 97 8F
        $hex | Should -Match 'E2978F'
    }

    It 'format=symbol emits correct UTF-8 bytes for max (U+25C9 ◉)' {
        $output = Format-Field (Make-EffortField 'symbol') (Make-EffortData 'max')
        $bytes  = [System.Text.Encoding]::UTF8.GetBytes($output)
        $hex    = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''
        # U+25C9 ◉ → UTF-8: E2 97 89
        $hex | Should -Match 'E29789'
    }

    It "format=icon+raw returns symbol and raw value for medium" {
        $output = Format-Field (Make-EffortField 'icon+raw') (Make-EffortData 'medium')
        $output | Should -Match 'medium'
        # Symbol ◐ must be present (UTF-8 E2 97 90)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($output)
        $hex   = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''
        $hex | Should -Match 'E29790'
    }

    It "format=icon+short returns symbol and short char for high" {
        $output = Format-Field (Make-EffortField 'icon+short') (Make-EffortData 'high')
        $output | Should -Match 'H'
        # Symbol ● must be present (UTF-8 E2 97 8F)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($output)
        $hex   = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''
        $hex | Should -Match 'E2978F'
    }

    It 'returns empty string when effort_level is null' {
        Format-Field (Make-EffortField 'raw') ([PSCustomObject]@{}) | Should -Be ''
    }
}

Describe 'Encoding — barCharset emits stable UTF-8 codepoints' {
    # Byte-level assertions for every barCharset supported by Format-ProgressBar.
    # Ensures that the Unicode codepoints emitted are deterministic and do not
    # silently change (e.g. when the script is parsed under a non-UTF-8 codepage),
    # so that any terminal font — including Nerd Fonts — always receives the same
    # codepoints to render.

    BeforeAll {
        # Expected UTF-8 byte sequences (hex, no spaces) for filled and empty
        # glyph of each charset.  Derived from the charMap in statusline.ps1:177-184.
        $script:expectedGlyphs = @{
            block  = @{ filled = 'E29693'; empty = 'E29691' }  # U+2593 ▓ / U+2591 ░
            solid  = @{ filled = 'E29688'; empty = 'E29691' }  # U+2588 █ / U+2591 ░
            circle = @{ filled = 'E2978F'; empty = 'E2978B' }  # U+25CF ● / U+25CB ○
            square = @{ filled = 'E296A0'; empty = 'E296A1' }  # U+25A0 ■ / U+25A1 □
            ascii  = @{ filled = '23';     empty = '2D' }       # '#' / '-'
            pipe   = @{ filled = 'E296AE'; empty = 'E296AF' }  # U+25AE ▮ / U+25AF ▯
        }
    }

    It 'charset <charset> emits expected filled+empty UTF-8 bytes at 50%' -ForEach @(
        @{ charset = 'block'  }
        @{ charset = 'solid'  }
        @{ charset = 'circle' }
        @{ charset = 'square' }
        @{ charset = 'ascii'  }
        @{ charset = 'pipe'   }
    ) {
        # Arrange
        $expected = $script:expectedGlyphs[$charset]

        # Act: -Fg $null + -Style 'block' = no ANSI colour codes, pure glyph output
        $output  = Format-ProgressBar -Value 50 -Style 'block' -Fg $null `
                                      -Brackets $false -Charset $charset
        # Strip the trailing percentage label, keep only the bar glyphs
        $barOnly = ($output -replace '\s*\d+%$', '').Trim()
        $bytes   = [System.Text.Encoding]::UTF8.GetBytes($barOnly)
        $hex     = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''

        # Assert
        $hex | Should -Match $expected.filled
        $hex | Should -Match $expected.empty
    }

    It 'charset braille emits expected fill, right-edge and empty UTF-8 bytes at 50%' {
        # Arrange: at value 50 the bar has 5 filled (U+28FF ⣿), 4 empty (U+28C9 ⣉),
        # and a right edge at position 9 (U+28F9 ⣹).  No left-edge at position 0
        # because position 0 is filled when value >= 10%.

        # Act
        $output  = Format-ProgressBar -Value 50 -Style 'block' -Fg $null -Charset 'braille'
        $barOnly = ($output -replace '\s*\d+%$', '').Trim()
        $bytes   = [System.Text.Encoding]::UTF8.GetBytes($barOnly)
        $hex     = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''

        # Assert
        $hex | Should -Match 'E2A3BF'   # U+28FF ⣿ filled segment
        $hex | Should -Match 'E2A3B9'   # U+28F9 ⣹ right edge
        $hex | Should -Match 'E2A389'   # U+28C9 ⣉ empty segment
    }

    It 'charset braille emits left-edge byte E2A38F for U+28CF at 0%' {
        # At 0% position 0 gets the left-edge glyph U+28CF ⣏ instead of a fill char.

        # Act
        $output  = Format-ProgressBar -Value 0 -Style 'block' -Fg $null -Charset 'braille'
        $barOnly = ($output -replace '\s*\d+%$', '').Trim()
        $bytes   = [System.Text.Encoding]::UTF8.GetBytes($barOnly)
        $hex     = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''

        # Assert
        $hex | Should -Match 'E2A38F'   # U+28CF ⣏ left edge
    }

    It 'no two non-ascii charsets share the same filled-glyph codepoint' {
        # Guards against accidentally reusing a codepoint across charsets, which
        # would make two visually identical bars indistinguishable in tests.
        $filledHexValues = $script:expectedGlyphs.GetEnumerator() |
            Where-Object { $_.Key -ne 'ascii' } |
            ForEach-Object { $_.Value.filled }

        ($filledHexValues | Sort-Object -Unique).Count | Should -Be $filledHexValues.Count
    }
}

Describe 'Encoding — new_fields_indicator emits UTF-8 bullet' {
    # End-to-end byte-level assertion: spawn the script as a fresh pwsh subprocess,
    # pipe stdin, capture raw stdout bytes, and verify the bullet character is
    # emitted as its UTF-8 byte sequence (E2 97 8F = U+25CF ●). This guards against
    # regressions where the script is parsed under a non-UTF-8 codepage and the
    # literal bullet is corrupted into garbage bytes before output.

    It 'emits bytes E2 97 8F for U+25CF in subprocess output' {
        # Arrange: create a disposable temp dir with a copy of the script and a
        # minimal config that declares a new_fields_indicator field plus a
        # knownKeys list that does NOT contain the test input key.
        $tempDir = [System.IO.Path]::Combine(
            [System.IO.Path]::GetTempPath(),
            [Guid]::NewGuid().ToString()
        )
        $null = New-Item -ItemType Directory -Path $tempDir -Force
        try {
            $srcScript  = Join-Path $PSScriptRoot '..' 'statusline.ps1'
            $tempScript = Join-Path $tempDir    'statusline.ps1'
            $tempConfig = Join-Path $tempDir    'statusline-config.json'
            Copy-Item -Path $srcScript -Destination $tempScript

            $configObj = @{
                lines     = @(@{ fields = @(@{ type = 'new_fields_indicator' }) })
                knownKeys = @('session_id')
            }
            $configJson = $configObj | ConvertTo-Json -Depth 5 -Compress
            [System.IO.File]::WriteAllText(
                $tempConfig,
                $configJson,
                [System.Text.UTF8Encoding]::new($false)
            )

            # Input JSON contains a key not in knownKeys → triggers new_fields_indicator
            $inputJson = '{ "probe_unknown_key_for_encoding_test": 42 }'

            # Act: launch pwsh as subprocess and capture raw stdout bytes
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = 'pwsh'
            $psi.ArgumentList.Add('-NoProfile')
            $psi.ArgumentList.Add('-File')
            $psi.ArgumentList.Add($tempScript)
            $psi.RedirectStandardInput  = $true
            $psi.RedirectStandardOutput = $true
            $psi.UseShellExecute        = $false

            $proc = [System.Diagnostics.Process]::Start($psi)
            $proc.StandardInput.Write($inputJson)
            $proc.StandardInput.Close()

            $ms = [System.IO.MemoryStream]::new()
            $proc.StandardOutput.BaseStream.CopyTo($ms)
            $proc.WaitForExit()
            $rawBytes = $ms.ToArray()

            # Assert: the raw output must contain the UTF-8 byte sequence for ●
            $hex = ($rawBytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''
            $hex | Should -Match 'E2978F'
        }
        finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
