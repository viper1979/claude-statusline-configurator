<#
.SYNOPSIS
    Conformance tests between the two Render Adapters: statusline.ps1 (ANSI, the
    reference) and the preview renderer inside statusline-configurator.html (HTML).
.DESCRIPTION
    The preview JavaScript is not split into its own file; the block between the
    markers `// @conformance-begin` and `// @conformance-end` is extracted by
    tests/conformance/render-harness.js and executed in Node without a DOM.
    Conformance Fixtures under tests/conformance/*.fixture.json hold inputs only —
    the PowerShell adapter is the oracle at test time.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '../statusline.ps1')

    $script:HtmlPath    = Join-Path $PSScriptRoot '../statusline-configurator.html'
    $script:HarnessPath = Join-Path $PSScriptRoot 'conformance/render-harness.js'
    $script:MarkerBegin = '// @conformance-begin'
    $script:MarkerEnd   = '// @conformance-end'

    # Node is a hard requirement: a silently skipped drift check would defeat the
    # purpose of this suite, so the run fails loudly instead.
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        throw "node not found on PATH, required by tests/conformance.Tests.ps1"
    }

    # Counts non-overlapping occurrences of a literal marker in the HTML source.
    function Get-MarkerCount {
        param([string]$Marker)
        $html = Get-Content -Path $script:HtmlPath -Raw
        return ([regex]::Matches($html, [regex]::Escape($Marker))).Count
    }
}

Describe 'Conformance block guards' {
    It 'marks the pure rendering block with exactly one begin and one end marker' {
        # Arrange / Act
        $beginCount = Get-MarkerCount $script:MarkerBegin
        $endCount   = Get-MarkerCount $script:MarkerEnd

        # Assert
        $beginCount | Should -Be 1 -Because 'the harness extracts the block by its unique begin marker'
        $endCount   | Should -Be 1 -Because 'the harness extracts the block by its unique end marker'
    }

    It 'evaluates the rendering block in Node without any DOM access' {
        # Arrange
        $expectedFunctions = @('formatFieldValue', 'renderFieldHtml', 'formatAgo')

        # Act
        $output   = & node $script:HarnessPath --check $script:HtmlPath 2>&1
        $exitCode = $LASTEXITCODE

        # Assert
        $exitCode | Should -Be 0 -Because "the harness reported: $output"
        $defined = ($output -join "`n" | ConvertFrom-Json).functions
        foreach ($name in $expectedFunctions) {
            $defined | Should -Contain $name
        }
    }
}

# One Describe per Conformance Fixture file, one It per case. The fixture holds inputs
# only: the PowerShell adapter renders the expected text at test time, the harness
# renders the same case through the preview adapter, and both visible texts must match.
BeforeDiscovery {
    $fixtureFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot 'conformance') -Filter '*.fixture.json' |
        ForEach-Object {
            $doc = Get-Content -Path $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            @{
                FixtureName = $_.BaseName -replace '\.fixture$', ''
                FixturePath = $_.FullName
                Now         = [long]$doc.now
                Cases       = @($doc.cases | ForEach-Object { @{ Name = $_.name; Field = $_.field; Payload = $_.payload } })
            }
        }
}

Describe 'Render Adapter conformance: <FixtureName>' -ForEach $fixtureFiles {
    BeforeAll {
        $ansiPattern = "`e\[[0-9;]*m"
        $script:renderContext = New-RenderContext -Config ([PSCustomObject]@{}) -Now ([DateTimeOffset]::FromUnixTimeSeconds($Now))

        # One Node process per fixture file; results keyed by case name.
        $harnessOutput = & node $script:HarnessPath $script:HtmlPath $FixturePath 2>&1
        if ($LASTEXITCODE -ne 0) { throw "render-harness failed for ${FixtureName}: $harnessOutput" }
        $script:previewTexts = @{}
        foreach ($entry in ($harnessOutput -join "`n" | ConvertFrom-Json)) {
            $script:previewTexts[$entry.name] = $entry.text
        }

        # Renders a case through the reference adapter and strips the ANSI color codes.
        function Get-ReferenceText {
            param($Field, $Payload)
            $rendered = Format-Field -Field $Field -Data $Payload -Context $script:renderContext
            return [regex]::Replace("$rendered", $ansiPattern, '')
        }
    }

    It '<Name>' -ForEach $Cases {
        # Arrange
        $expected = Get-ReferenceText -Field $Field -Payload $Payload

        # Act
        $actual = $script:previewTexts[$Name]

        # Assert
        $script:previewTexts.ContainsKey($Name) | Should -BeTrue -Because 'the harness must render every case'
        $actual | Should -BeExactly $expected
    }
}
