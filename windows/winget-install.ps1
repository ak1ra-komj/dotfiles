
[String[]]$packages = @(
    "Microsoft.VCRedist.2015+.x64"
    "Microsoft.VCRedist.2015+.x86"

    "Google.Chrome"
    "Obsidian.Obsidian"

    "7zip.7zip"
    "ShareX.ShareX"
    "voidtools.Everything"

    "Notepad++.Notepad++"
    "Rizonesoft.Notepad3"
    "Microsoft.VisualStudioCode"

    "Git.Git"
    "Microsoft.PowerShell"
    "Microsoft.WindowsTerminal"

    "Python.Python.3.14"
    "Microsoft.OpenJDK.25"

    "astral-sh.ruff"
    "astral-sh.uv"
    "mvdan.shfmt"
    "koalaman.shellcheck"
    "Smallstep.step"
    "FujiApple.Trippy"
    "jj-vcs.jj"

    "Gyan.FFmpeg"
    "ImageMagick.ImageMagick"
    "MediaArea.MediaInfo.GUI"
    "PeterPawlowski.foobar2000"

    "ch.LosslessCut"
    "OBSProject.OBSStudio"

    "WireGuard.WireGuard"
    "CrystalDewWorld.CrystalDiskInfo"
    "CrystalDewWorld.CrystalDiskMark"
    "FastCopy.FastCopy"
    "JAMSoftware.TreeSize.Free"

    # "AutoHotkey.AutoHotkey"
    # "AntSoftware.AntRenamer"

    # "Fork.Fork"
    # "oldj.switchhosts"
    # "LocalSend.LocalSend"

    # "HeidiSQL.HeidiSQL"
    # "MongoDB.Compass.Isolated"
    # "qishibo.AnotherRedisDesktopManager"
)

foreach ($package in $packages) {
    $package = $package.Trim()
    if ($package -eq "" -or $package -match "^#") {
        continue
    }

    Write-Host ('Installing package {0}...' -f $package) -ForegroundColor Green
    winget install --id=$package --exact --accept-package-agreements --accept-source-agreements
}
