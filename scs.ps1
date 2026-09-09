# scs.ps1 — switch between multiple Claude Code accounts on native Windows
# (PowerShell), without keeping separate CLAUDE_CONFIG_DIRs around.
#
# Same idea as scs.sh: only account-specific fields are swapped —
#   - claudeAiOauth  in  $CLAUDE_CONFIG_DIR\.credentials.json  (token)
#   - oauthAccount   in  $env:USERPROFILE\.claude.json         (account identity)
# Everything else stays shared and is never duplicated.
#
# Install: add to your PowerShell profile ($PROFILE):
#   . "$HOME\.scs.ps1"
#
# Usage:
#   claude
#   scs save work
#   claude /logout; claude
#   scs save personal
#   scs use work
#   scs list
#   scs current
#   scs remove <name>

$script:ScsProfilesDir = Join-Path $env:USERPROFILE ".scs-profiles"
$script:ScsActiveFile  = Join-Path $env:USERPROFILE ".scs-active-account"
$script:ScsJson        = Join-Path $env:USERPROFILE ".claude.json"

function _scs-creds-file {
    $configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }
    Join-Path $configDir ".credentials.json"
}

function _scs-merge-json($base, $overlay) {
    # shallow merge, overlay wins — same semantics as `jq -s '.[0] * .[1]'`
    # for the flat objects this tool writes.
    foreach ($prop in $overlay.PSObject.Properties) {
        if ($base.PSObject.Properties.Name -contains $prop.Name) {
            $base.($prop.Name) = $prop.Value
        } else {
            $base | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }
    }
    return $base
}

function scs {
    param(
        [Parameter(Position = 0)][string]$Command,
        [Parameter(Position = 1)][string]$Name
    )

    $credsFile = _scs-creds-file

    switch ($Command) {
        "save" {
            if (-not $Name) { Write-Host "Usage: scs save <name>"; return }
            if (-not (Test-Path $credsFile) -or -not (Test-Path $script:ScsJson)) {
                Write-Host "No active login found. Run 'claude' and log in first."
                return
            }
            $profileDir = Join-Path $script:ScsProfilesDir $Name
            New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

            $creds = Get-Content $credsFile -Raw | ConvertFrom-Json
            [PSCustomObject]@{ claudeAiOauth = $creds.claudeAiOauth } |
                ConvertTo-Json -Depth 10 | Set-Content (Join-Path $profileDir "credentials.json")

            $json = Get-Content $script:ScsJson -Raw | ConvertFrom-Json
            [PSCustomObject]@{ oauthAccount = $json.oauthAccount } |
                ConvertTo-Json -Depth 10 | Set-Content (Join-Path $profileDir "account.json")

            Set-Content $script:ScsActiveFile $Name
            Write-Host "Current login saved as profile '$Name'."
        }
        "use" {
            if (-not $Name) { Write-Host "Usage: scs use <name>"; return }
            $profileDir = Join-Path $script:ScsProfilesDir $Name
            if (-not (Test-Path $profileDir)) {
                Write-Host "Profile '$Name' does not exist. Save it first with: scs save $Name"
                return
            }

            if (Test-Path $credsFile) { Copy-Item $credsFile "$credsFile.bak" -Force }
            if (Test-Path $script:ScsJson) { Copy-Item $script:ScsJson "$script:ScsJson.bak" -Force }

            $creds = Get-Content $credsFile -Raw | ConvertFrom-Json
            $credsOverlay = Get-Content (Join-Path $profileDir "credentials.json") -Raw | ConvertFrom-Json
            _scs-merge-json $creds $credsOverlay | ConvertTo-Json -Depth 10 | Set-Content $credsFile

            $json = Get-Content $script:ScsJson -Raw | ConvertFrom-Json
            $jsonOverlay = Get-Content (Join-Path $profileDir "account.json") -Raw | ConvertFrom-Json
            _scs-merge-json $json $jsonOverlay | ConvertTo-Json -Depth 10 | Set-Content $script:ScsJson

            Set-Content $script:ScsActiveFile $Name
            Write-Host "Active Claude account: $Name"

            # ponytail: matches processes by command line containing "claude";
            # no ancestry-based filtering (unlike scs.sh's --disallowedTools
            # exclusion) — add if sub-agent processes need excluding on Windows.
            $reply = Read-Host "Kill running Claude CLI sessions now so they restart as '$Name'? [y/N]"
            if ($reply -match '^[Yy]$') {
                $procs = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
                    Where-Object { $_.CommandLine -match 'claude' }
                if ($procs) {
                    $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
                    Write-Host "Killed: $($procs.ProcessId -join ', ')"
                } else {
                    Write-Host "No running Claude CLI session found."
                }
            }
            Write-Host "VS Code: the Claude extension does not reconnect automatically — use Command Palette -> 'Developer: Reload Window'."
        }
        "list" {
            Write-Host "Saved profiles:"
            $active = if (Test-Path $script:ScsActiveFile) { Get-Content $script:ScsActiveFile } else { $null }
            if (Test-Path $script:ScsProfilesDir) {
                Get-ChildItem $script:ScsProfilesDir -Directory | ForEach-Object {
                    if ($_.Name -eq $active) {
                        Write-Host "  * $($_.Name) (active)"
                    } else {
                        Write-Host "    $($_.Name)"
                    }
                }
            }
        }
        "current" {
            if (Test-Path $script:ScsJson) {
                $json = Get-Content $script:ScsJson -Raw | ConvertFrom-Json
                Write-Host ($json.oauthAccount | ConvertTo-Json -Depth 10)
            }
            $active = if (Test-Path $script:ScsActiveFile) { Get-Content $script:ScsActiveFile } else { "none" }
            Write-Host "assigned profile: $active"
        }
        "remove" {
            if (-not $Name) { Write-Host "Usage: scs remove <name>"; return }
            Remove-Item -Recurse -Force (Join-Path $script:ScsProfilesDir $Name) -ErrorAction SilentlyContinue
            Write-Host "Profile '$Name' removed."
        }
        default {
            Write-Host "Usage: scs {save|use|list|current|remove} [name]"
        }
    }
}
