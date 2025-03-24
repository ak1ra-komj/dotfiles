
[String[]]$packages = @(
    "Microsoft.VCRedist.2015+.x64"
    "Microsoft.VCRedist.2015+.x86"

    "Google.Chrome"
    "Obsidian.Obsidian"

    "7zip.7zip"
    "ShareX.ShareX"
    "voidtools.Everything"
    "KeePassXCTeam.KeePassXC"

    "Notepad++.Notepad++"
    "Rizonesoft.Notepad3"
    "Microsoft.VisualStudioCode"

    "Git.Git"
    "Microsoft.PowerShell"
    "Microsoft.WindowsTerminal"

    "Python.Python.3.13"
    "Microsoft.OpenJDK.17"
    "AutoHotkey.AutoHotkey"

    "Gyan.FFmpeg"
    "ImageMagick.ImageMagick"
    "ch.LosslessCut"
    "OBSProject.OBSStudio"
    "PeterPawlowski.foobar2000"

    "WireGuard.WireGuard"
    "CrystalDewWorld.CrystalDiskInfo"
    "CrystalDewWorld.CrystalDiskMark"
    "FastCopy.FastCopy"
    "JAMSoftware.TreeSize.Free"

    "HeidiSQL.HeidiSQL"
    "MongoDB.Compass.Isolated"
    "qishibo.AnotherRedisDesktopManager"
)

foreach ($package in $packages) {
    $package = $package.Trim()
    if ($package -eq "" -or $package -match "^#") {
        continue
    }

    Write-Host ('Installing package {0}...' -f $package) -ForegroundColor Green
    winget install --id=$package --exact --accept-package-agreements --accept-source-agreements
}
