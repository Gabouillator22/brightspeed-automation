$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$hookScript = Join-Path $repoRoot '.codex/hooks/set-terminal-bg.ps1'

if (-not (Test-Path $hookScript)) {
    Write-Error "Hook script not found: $hookScript"
    exit 1
}

$states = @('running', 'input', 'error', 'idle')

foreach ($state in $states) {
    & $hookScript $state
    Start-Sleep -Seconds 1
}

& $hookScript 'reset'
