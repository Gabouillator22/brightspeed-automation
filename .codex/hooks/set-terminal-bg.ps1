param(
    [string]$State = "idle",
    [string]$HookName = "Unknown"
)

$ErrorActionPreference = "SilentlyContinue"

function Get-StatusPaths {
    $statusDir = Join-Path (Split-Path $PSScriptRoot -Parent) "status"
    $logPath = Join-Path $statusDir "hook-events.log"
    return @{
        StatusDir = $statusDir
        LogPath = $logPath
    }
}

function Write-HookLog {
    param(
        [string]$Hook,
        [string]$RequestedState,
        [bool]$WroteConOut,
        [bool]$UsedConsoleFallback
    )

    try {
        $paths = Get-StatusPaths
        if (-not [System.IO.Directory]::Exists($paths.StatusDir)) {
            [System.IO.Directory]::CreateDirectory($paths.StatusDir) | Out-Null
        }

        $line = "{0} | {1} | {2} | script={3} | pid={4} | cwd={5} | wrote_conout={6} | fallback_console={7}" -f `
            [DateTime]::UtcNow.ToString("o"), `
            $Hook, `
            $RequestedState, `
            $PSCommandPath, `
            $PID, `
            (Get-Location).Path, `
            $WroteConOut.ToString().ToLowerInvariant(), `
            $UsedConsoleFallback.ToString().ToLowerInvariant()

        [System.IO.File]::AppendAllText($paths.LogPath, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    } catch {
    }
}

function Get-TerminalSequence {
    param(
        [string]$Name
    )

    $esc = [char]27
    $bel = [char]7

    switch ($Name.ToLowerInvariant()) {
        "idle" { return "$esc]2;Codex: idle$bel$esc]10;#d0d0d0$bel$esc]11;#151515$bel" }
        "running" { return "$esc]2;Codex: running$bel$esc]10;#e8f2ff$bel$esc]11;#001b3a$bel" }
        "completed" { return "$esc]2;Codex: completed$bel$esc]10;#eaffef$bel$esc]11;#003313$bel" }
        "input" { return "$esc]2;Codex: input required$bel$esc]10;#fff2cc$bel$esc]11;#3a2400$bel" }
        "error" { return "$esc]2;Codex: error$bel$esc]10;#ffecec$bel$esc]11;#3a0000$bel" }
        "reset" { return "$esc]2;Codex$bel$esc]110;$bel$esc]111;$bel$esc]112;$bel" }
        default { return "$esc]2;Codex: idle$bel$esc]10;#d0d0d0$bel$esc]11;#151515$bel" }
    }
}

function Initialize-ConsoleWriter {
    try {
        if ($null -eq [type]::GetType("BrightspeedTerminalNative")) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class BrightspeedTerminalNative {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);
}
"@ -ErrorAction Stop
        }
        return $true
    } catch {
        return $false
    }
}

function Write-ConOutSequence {
    param(
        [string]$Sequence
    )

    try {
        if (-not (Initialize-ConsoleWriter)) {
            return $false
        }

        $genericWrite = 0x40000000
        $fileShareRead = 1
        $fileShareWrite = 2
        $openExisting = 3
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Sequence)
        $handle = [BrightspeedTerminalNative]::CreateFile(
            "CONOUT$",
            $genericWrite,
            ($fileShareRead -bor $fileShareWrite),
            [IntPtr]::Zero,
            $openExisting,
            0,
            [IntPtr]::Zero
        )

        if ($handle.IsInvalid) {
            return $false
        }

        $stream = [System.IO.FileStream]::new($handle, [System.IO.FileAccess]::Write)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        } finally {
            if ($null -ne $stream) {
                $stream.Dispose()
            }
        }
        return $true
    } catch {
        return $false
    }
}

function Write-ConsoleFallback {
    param(
        [string]$Sequence
    )

    try {
        [Console]::Write($Sequence)
        return $true
    } catch {
        return $false
    }
}

$wroteConOut = $false
$usedConsoleFallback = $false

try {
    $sequence = Get-TerminalSequence -Name $State
    $wroteConOut = Write-ConOutSequence -Sequence $sequence
    if (-not $wroteConOut) {
        $usedConsoleFallback = Write-ConsoleFallback -Sequence $sequence
    }
} catch {
} finally {
    Write-HookLog -Hook $HookName -RequestedState $State -WroteConOut $wroteConOut -UsedConsoleFallback $usedConsoleFallback
}

exit 0
