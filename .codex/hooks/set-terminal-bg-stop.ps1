param(
    [string]$State = "completed",
    [string]$HookName = "Stop"
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
        [bool]$UsedStderrFallback
    )

    try {
        $paths = Get-StatusPaths
        if (-not [System.IO.Directory]::Exists($paths.StatusDir)) {
            [System.IO.Directory]::CreateDirectory($paths.StatusDir) | Out-Null
        }

        $line = "{0} | {1} | {2} | script={3} | pid={4} | cwd={5} | wrote_conout={6} | fallback_stderr={7}" -f `
            [DateTime]::UtcNow.ToString("o"), `
            $Hook, `
            $RequestedState, `
            $PSCommandPath, `
            $PID, `
            (Get-Location).Path, `
            $WroteConOut.ToString().ToLowerInvariant(), `
            $UsedStderrFallback.ToString().ToLowerInvariant()

        [System.IO.File]::AppendAllText($paths.LogPath, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    } catch {
    }
}

function Get-TerminalSequence {
    $esc = [char]27
    $bel = [char]7
    return "$esc]2;Codex: completed$bel$esc]10;#eaffef$bel$esc]11;#003313$bel"
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

function Write-StderrSequence {
    param(
        [string]$Sequence
    )

    try {
        [Console]::Error.Write($Sequence)
        [Console]::Error.Flush()
        return $true
    } catch {
        return $false
    }
}

$wroteConOut = $false
$usedStderrFallback = $false

try {
    $sequence = Get-TerminalSequence
    $wroteConOut = Write-ConOutSequence -Sequence $sequence
    if (-not $wroteConOut) {
        $usedStderrFallback = Write-StderrSequence -Sequence $sequence
    }
} catch {
} finally {
    Write-HookLog -Hook $HookName -RequestedState $State -WroteConOut $wroteConOut -UsedStderrFallback $usedStderrFallback
}

[Console]::Out.Write('{"continue":true}')
[Console]::Out.Flush()
exit 0
