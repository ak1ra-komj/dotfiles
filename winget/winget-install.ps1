
$packages_url = "https://raw.githubusercontent.com/ak1ra-komj/dotfiles/master/winget/winget-packages.txt"
$packages = (Invoke-RestMethod $packages_url) -split "`n"

foreach ($package in $packages) {
    Write-Host ('Installing package {0}...' -f $package) -ForegroundColor Green
    winget install --id=$package --exact --accept-package-agreements --accept-source-agreements
}
