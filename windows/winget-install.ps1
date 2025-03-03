
param (
    [string]$packages_url = "https://raw.githubusercontent.com/ak1ra-komj/dotfiles/master/windows/winget-packages.txt"
)

$packages = (Invoke-RestMethod $packages_url) -split "`n"

foreach ($package in $packages) {
    $package = $package.Trim()
    if ($package -eq "" -or $package -match "^#") {
        continue
    }

    Write-Host ('Installing package {0}...' -f $package) -ForegroundColor Green
    winget install --id=$package --exact --accept-package-agreements --accept-source-agreements
}
