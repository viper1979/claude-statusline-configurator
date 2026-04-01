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
