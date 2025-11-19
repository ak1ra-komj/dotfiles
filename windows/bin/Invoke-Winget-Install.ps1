#Requires -Version 5.1

<#
.SYNOPSIS
    Installs Windows packages using winget from a remote configuration.

.DESCRIPTION
    Downloads a package list from a URL or local file and installs each package using winget.
    Supports dry-run mode with -WhatIf parameter.

.PARAMETER Source
    URL or local file path to the JSON file containing package IDs to install.

.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs without actually executing.

.EXAMPLE
    .\Invoke-Winget-Install.ps1

.EXAMPLE
    .\Invoke-Winget-Install.ps1 -WhatIf

.EXAMPLE
    .\Invoke-Winget-Install.ps1 -Source "C:\path\to\packages.json"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Source = "https://raw.githubusercontent.com/ak1ra-komj/dotfiles/refs/heads/master/windows/.config/winget/packages.json"
)

Set-StrictMode -Version Latest

function Install-WingetIfNeeded {
    <#
    .SYNOPSIS
        Ensures winget is installed on the system.
    #>
    [CmdletBinding()]
    param()

    try {
        $null = Get-Command winget -ErrorAction Stop
        Write-Verbose "winget is already installed"
    }
    catch {
        Write-Warning "Installing winget..."
        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
            Write-Output "winget installed successfully"
        }
        catch {
            Write-Error "Failed to install winget: $($_.Exception.Message)"
            throw
        }
    }
}

function Install-WingetPackage {
    <#
    .SYNOPSIS
        Installs a single package using winget.

    .PARAMETER PackageId
        The winget package ID to install.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId
    )

    $arguments = @(
        'install'
        "--id=$PackageId"
        '--exact'
        '--silent'
        '--accept-package-agreements'
        '--accept-source-agreements'
        '--disable-interactivity'
    )

    if ($PSCmdlet.ShouldProcess($PackageId, "Install winget package")) {
        try {
            $process = Start-Process -FilePath 'winget' -ArgumentList $arguments -Wait -NoNewWindow -PassThru -ErrorAction Stop

            # Exit code 0 or -1978335189 (already installed) are considered success
            if ($process.ExitCode -eq 0 -or $process.ExitCode -eq -1978335189) {
                Write-Output "[OK] $PackageId"
                return $true
            }
            else {
                Write-Error "[FAIL] $PackageId : Exit code $($process.ExitCode)"
                return $false
            }
        }
        catch {
            Write-Error "[FAIL] $PackageId : $($_.Exception.Message)"
            return $false
        }
    }
    else {
        Write-Output "[Dry-run] Would install: $PackageId"
        return $true
    }
}

function Get-PackageConfiguration {
    <#
    .SYNOPSIS
        Loads package configuration from a URL or local file.

    .PARAMETER Source
        URL or local file path to the JSON configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Source
    )

    try {
        # Check if source is a local file path
        if (Test-Path -Path $Source -PathType Leaf -ErrorAction SilentlyContinue) {
            Write-Verbose "Loading package configuration from local file: $Source"
            $content = Get-Content -Path $Source -Raw -ErrorAction Stop
            return ($content | ConvertFrom-Json)
        }
        # Otherwise treat as URL
        else {
            Write-Verbose "Loading package configuration from URL: $Source"
            return (Invoke-RestMethod -Uri $Source -ErrorAction Stop)
        }
    }
    catch {
        Write-Error "Failed to load configuration from '$Source': $($_.Exception.Message)"
        throw
    }
}

function Main {
    [CmdletBinding()]
    param()

    $results = @{
        Success = [System.Collections.Generic.List[string]]::new()
        Failed  = [System.Collections.Generic.List[string]]::new()
    }

    # Load package configuration
    try {
        $packagesConfig = Get-PackageConfiguration -Source $Source
        $packages = @($packagesConfig.PSObject.Properties.Value | ForEach-Object { $_ }) | Where-Object { $_ }

        if ($packages.Count -eq 0) {
            Write-Warning "No packages found in configuration"
            return 0
        }

        Write-Output "Loaded $($packages.Count) package(s) from configuration"
    }
    catch {
        Write-Error "Failed to load configuration: $($_.Exception.Message)"
        return 1
    }

    # Ensure winget is available
    try {
        Install-WingetIfNeeded
    }
    catch {
        Write-Error "Cannot proceed without winget"
        return 1
    }

    # Update winget sources
    Write-Verbose "Updating winget sources..."
    $null = Start-Process -FilePath 'winget' -ArgumentList 'source', 'update' -Wait -NoNewWindow -PassThru

    if ($WhatIfPreference) {
        Write-Output "`nDry-run: The following installations would be performed:"
    }

    # Install packages
    foreach ($package in $packages) {
        if (Install-WingetPackage -PackageId $package) {
            $results.Success.Add($package)
        }
        else {
            $results.Failed.Add($package)
        }
    }

    # Display results
    Write-Output "`nInstallation Results:"
    Write-Output "Successful: $($results.Success.Count)"

    if ($results.Failed.Count -gt 0) {
        Write-Warning "Failed: $($results.Failed.Count)"
        Write-Output "Failed packages:"
        $results.Failed | ForEach-Object { Write-Output "  - $_" }
        return 1
    }

    return 0
}

# Execute main function
exit (Main)
