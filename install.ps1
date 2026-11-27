# Vicaro helper installer (Windows). Reads like a script, because you should read it:
#   irm https://vicaro.creativeducks.com/install.ps1 | iex
#
# What it does, in order: download the Windows zip, verify its SHA-256, install
# into %LOCALAPPDATA%\Vicaro\app, add vicaro-helper to your user PATH, register
# the vicaro:// URL scheme and login startup item, and start the helper + tray.
# It asks for no Administrator privileges and keeps user data in
# %LOCALAPPDATA%\Vicaro\helper.
#
# Options (when invoked as a file or via env vars):
#   $env:VICARO_NO_AGENT = "1"   skip login startup registration
#   $env:VICARO_DRY_RUN  = "1"   print what would happen, change nothing
#   $env:VICARO_ZIP      = "..." install from a local zip instead of downloading
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$StoreUrl = "https://chromewebstore.google.com/detail/vicaro-beta/inemnoeadlodgmheeijooeknmladelok"
$BaseUrl = if ($env:VICARO_BASE_URL) { $env:VICARO_BASE_URL.TrimEnd("/") } else { "https://github.com/sandeshwar/vicaro-public/releases/latest/download" }
$Port = if ($env:VICARO_PORT) { [int]$env:VICARO_PORT } else { 8792 }
$NoAgent = ($env:VICARO_NO_AGENT -eq "1")
$DryRun = ($env:VICARO_DRY_RUN -eq "1")

$RawArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
switch -Regex ($RawArch) {
    "ARM64" { $Arch = "arm64" }
    "AMD64|x86_64" { $Arch = "x86_64" }
    default { throw "Unsupported Windows architecture: $RawArch (supported: x86_64, arm64)" }
}

$ArchiveName = "Vicaro-windows-$Arch.zip"
$LocalBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE "AppData\Local" }
$Root = Join-Path $LocalBase "Vicaro"
$AppDir = Join-Path $Root "app"
$BinDir = Join-Path $Root "bin"
$DataDir = Join-Path $Root "helper"
$LogDir = Join-Path $Root "Logs"

Write-Host "Vicaro installer (Windows $Arch)"
Write-Host "  target: $AppDir"

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("vicaro-install-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null

try {
    $ZipPath = Join-Path $Tmp "app.zip"
    $ShaPath = Join-Path $Tmp "app.sha256"

    if ($env:VICARO_ZIP) {
        Copy-Item -LiteralPath $env:VICARO_ZIP -Destination $ZipPath -Force
        if (Test-Path -LiteralPath "$($env:VICARO_ZIP).sha256") {
            Copy-Item -LiteralPath "$($env:VICARO_ZIP).sha256" -Destination $ShaPath -Force
        }
    } else {
        Write-Host "  fetching $ArchiveName"
        Invoke-WebRequest -Uri "$BaseUrl/$ArchiveName" -OutFile $ZipPath -UseBasicParsing -TimeoutSec 180
        Invoke-WebRequest -Uri "$BaseUrl/$ArchiveName.sha256" -OutFile $ShaPath -UseBasicParsing -TimeoutSec 30
    }

    if (Test-Path -LiteralPath $ShaPath) {
        $Expected = ((Get-Content -LiteralPath $ShaPath -Raw).Trim() -split "\s+")[0].ToLowerInvariant()
        $Actual = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($Expected -ne $Actual) {
            throw "checksum mismatch - refusing to install (expected $Expected, got $Actual)"
        }
        Write-Host "  checksum ok"
    } else {
        Write-Host "  warning: no checksum published for this build"
    }

    if ($DryRun) {
        Write-Host "  platform: windows ($Arch)"
        Write-Host "  would install into $AppDir"
        Write-Host "  would register login startup: $(if ($NoAgent) { 'no' } else { 'yes' })"
        Write-Host "  would start the helper now: yes"
        Write-Host "  the Chrome extension is installed separately: $StoreUrl"
        return
    }

    $Extract = Join-Path $Tmp "extract"
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $Extract -Force
    $Source = Join-Path $Extract "vicaro-helper"
    if (-not (Test-Path -LiteralPath (Join-Path $Source "vicaro-helper.exe"))) {
        throw "archive did not contain vicaro-helper\vicaro-helper.exe"
    }

    # Stop any running Vicaro Helper processes from this installation.
    try {
        $targetExe = (Join-Path $AppDir "vicaro-helper.exe").ToLowerInvariant()
        Get-CimInstance Win32_Process -Filter "Name = 'vicaro-helper.exe'" | ForEach-Object {
            if ($_.ExecutablePath -and $_.ExecutablePath.ToLowerInvariant() -eq $targetExe) {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}
    Start-Sleep -Milliseconds 500

    foreach ($dir in @($Root, $BinDir, $DataDir, $LogDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Restrict %LOCALAPPDATA%\Vicaro to the current user, SYSTEM, and Administrators.
    try {
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $prop = [System.Security.AccessControl.PropagationFlags]::None
        $full = [System.Security.AccessControl.FileSystemRights]::FullControl
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $system = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $admins = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, $full, $inherit, $prop, $allow)))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($system, $full, $inherit, $prop, $allow)))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($admins, $full, $inherit, $prop, $allow)))
        Set-Acl -LiteralPath $Root -AclObject $acl
    } catch {}

    if (Test-Path -LiteralPath $AppDir) { Remove-Item -LiteralPath $AppDir -Recurse -Force }
    Copy-Item -LiteralPath $Source -Destination $AppDir -Recurse -Force
    Write-Host "  installed: $AppDir"

    # CLI shim in %LOCALAPPDATA%\Vicaro\bin + add to user PATH if not already present.
    $ShimPath = Join-Path $BinDir "vicaro-helper.cmd"
    "@echo off`r`n`"$AppDir\vicaro-helper.cmd`" %*`r`n" | Set-Content -LiteralPath $ShimPath -Encoding ASCII
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $Parts = if ($UserPath) { $UserPath -split ";" | Where-Object { $_ } } else { @() }
    if ($Parts -notcontains $BinDir) {
        [Environment]::SetEnvironmentVariable("Path", (($Parts + $BinDir) -join ";"), "User")
    }
    Write-Host "  cli:       $ShimPath"

    # Register vicaro:// URL scheme under HKCU (no admin required).
    $ProtoKey = "HKCU:\Software\Classes\vicaro"
    $IconIco = Join-Path $AppDir "icons\vicaro.ico"
    New-Item -Path "$ProtoKey\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path $ProtoKey -Name "(Default)" -Value "URL:Vicaro Protocol"
    Set-ItemProperty -Path $ProtoKey -Name "URL Protocol" -Value ""
    if (Test-Path -LiteralPath $IconIco) {
        New-Item -Path "$ProtoKey\DefaultIcon" -Force | Out-Null
        Set-ItemProperty -Path "$ProtoKey\DefaultIcon" -Name "(Default)" -Value "`"$IconIco`",0"
    }
    Set-ItemProperty -Path "$ProtoKey\shell\open\command" -Name "(Default)" -Value "wscript.exe `"$AppDir\vicaro-tray.vbs`" open-uri `"%1`""

    # Create Start Menu shortcut.
    try {
        $Wsh = New-Object -ComObject WScript.Shell
        $LinkPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Vicaro Helper.lnk"
        $Shortcut = $Wsh.CreateShortcut($LinkPath)
        $Shortcut.TargetPath = "wscript.exe"
        $Shortcut.Arguments = "`"$AppDir\vicaro-tray.vbs`" tray"
        $Shortcut.WorkingDirectory = $AppDir
        $Shortcut.Description = "Vicaro Helper (local browser agent)"
        if (Test-Path -LiteralPath $IconIco) {
            $Shortcut.IconLocation = "$IconIco,0"
        }
        $Shortcut.Save()
    } catch {}

    # Register startup entry unless -NoAgent.
    if ($NoAgent) {
        Write-Host "  login startup: skipped"
    } else {
        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Force | Out-Null
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "VicaroHelper" -Value "wscript.exe `"$AppDir\vicaro-tray.vbs`" tray"
        Write-Host "  login startup: registered"
    }

    # Start tray + helper silently.
    Write-Host "  helper: starting"
    Start-Process -FilePath "wscript.exe" -ArgumentList "`"$AppDir\vicaro-tray.vbs`" tray" -WindowStyle Hidden

    $Up = $false
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($r.StatusCode -lt 500) { $Up = $true; break }
        } catch [System.Net.WebException] {
            if ($_.Exception.Response) { $Up = $true; break }
        } catch {}
        Start-Sleep -Seconds 1
    }
    if ($Up) {
        Write-Host "  helper: running on $Port"
    } else {
        Write-Host "  helper: started, not answering yet - check $LogDir\helper.log"
    }

    Write-Host ""
    Write-Host "Vicaro Helper is installed."
    Write-Host ""
    Write-Host "Add Vicaro Beta to Chrome:"
    Write-Host "  $StoreUrl"
    Write-Host ""
    Write-Host "Open the setup tab or side panel and sign in with Google or an email magic link."
    Write-Host "Data: $DataDir"
    Write-Host "Logs: $LogDir\helper.log"
    Write-Host "CLI:  vicaro-helper status"
    Write-Host "Uninstall (keeps chats, memories and settings):"
    Write-Host "  vicaro-helper uninstall"
} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
