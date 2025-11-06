param (
    [Parameter(Mandatory = $false)]
    [string]$PackagesUrl = "https://raw.githubusercontent.com/ak1ra-komj/dotfiles/refs/heads/master/windows/winget-install.json",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

function Install-WingetIfNeeded {
    try {
        $null = winget --version
    }
    catch {
        Write-Host "Installing winget..." -ForegroundColor Yellow
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
    }
}

function Install-Package {
    param(
        [string]$package,
        [switch]$DryRun
    )

    $cmd = "winget install --id=$package --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"

    if ($DryRun) {
        Write-Host "[Dry-run] $cmd" -ForegroundColor Yellow
        return $true
    }

    try {
        Invoke-Expression $cmd
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
            Write-Host "[OK] $package" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "[FAIL] $package : $($_.Exception.Message)" -ForegroundColor Red
    }
    return $false
}

function Main {
    try {
        $packagesConfig = Invoke-RestMethod -Uri $PackagesUrl -ErrorAction Stop
        $script:packages = @($packagesConfig.PSObject.Properties.Value | ForEach-Object { $_ }) | Where-Object { $_ }
        Write-Host "Loaded package configuration from $PackagesUrl" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }

    Install-WingetIfNeeded
    winget source update

    $results = @{
        Success = @()
        Failed  = @()
    }

    if ($WhatIf) {
        Write-Host "`nDry-run: The following installations would be performed:" -ForegroundColor Cyan
    }

    $packages | ForEach-Object {
        if (Install-Package -package $_ -DryRun:$WhatIf) {
            $results.Success += $_
        }
        else {
            $results.Failed += $_
        }
    }

    # Display results
    Write-Host "`nInstallation Results:" -ForegroundColor Cyan
    Write-Host "Successful: $($results.Success.Count)" -ForegroundColor Green
    if ($results.Failed.Count -gt 0) {
        Write-Host "Failed: $($results.Failed.Count)" -ForegroundColor Red
        Write-Host ($results.Failed -join "`n") -ForegroundColor Yellow
        return 1
    }
    return 0
}

Main
