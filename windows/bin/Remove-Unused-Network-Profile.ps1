#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Removes unused network profiles from the Windows registry.

.DESCRIPTION
    This script identifies and removes network profiles that are not currently active.
    It cleans up both the profile registry keys and their associated signature entries.
    Requires administrative privileges to modify registry keys.

.PARAMETER WhatIf
    Shows what would happen if the script runs without actually making changes.

.PARAMETER Confirm
    Prompts for confirmation before removing each profile.

.EXAMPLE
    Remove-Unused-Network-Profile.ps1
    Removes all unused network profiles with confirmation prompts.

.EXAMPLE
    Remove-Unused-Network-Profile.ps1 -WhatIf
    Shows which profiles would be removed without making changes.

.EXAMPLE
    Remove-Unused-Network-Profile.ps1 -Confirm:$false
    Removes all unused profiles without confirmation prompts.

.NOTES
    This script modifies the Windows registry and requires administrator privileges.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest

function Get-ActiveNetworkProfileNames {
    <#
    .SYNOPSIS
        Retrieves the names of all currently active network profiles.

    .DESCRIPTION
        Queries active network connection profiles to determine which profiles are currently in use.

    .OUTPUTS
        System.String[]
        An array of active network profile names.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    try {
        $profiles = Get-NetConnectionProfile -ErrorAction Stop
        return $profiles.Name
    }
    catch {
        Write-Error "Failed to retrieve active network profiles: $_"
        throw
    }
}

function Remove-NetworkProfileRegistryKey {
    <#
    .SYNOPSIS
        Removes a network profile registry key.

    .DESCRIPTION
        Deletes the specified network profile registry key from the Windows registry.

    .PARAMETER Path
        The registry path to the profile key.

    .PARAMETER Name
        The friendly name of the network profile.

    .PARAMETER Guid
        The GUID of the network profile.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Guid
    )

    try {
        if ($PSCmdlet.ShouldProcess("Profile: $Name ($Guid)", "Delete Profile Registry Key")) {
            Write-Verbose "Deleting profile registry key: $Name ($Guid)"
            Remove-Item -Path $Path -Force -ErrorAction Stop
            Write-Output "Deleted profile: $Name"
        }
    }
    catch {
        Write-Error "Failed to delete profile registry key '$Path': $_"
    }
}

function Remove-NetworkSignatureRegistryKey {
    <#
    .SYNOPSIS
        Removes network signature registry keys associated with a profile.

    .DESCRIPTION
        Searches for and removes signature registry entries that match the specified profile GUID.

    .PARAMETER SignaturesPath
        The registry path to the network signatures.

    .PARAMETER ProfileGuid
        The GUID of the network profile to match against signatures.

    .PARAMETER ProfileName
        The friendly name of the network profile (for logging purposes).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SignaturesPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProfileGuid,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProfileName
    )

    try {
        $signatures = Get-ChildItem -Path $SignaturesPath -ErrorAction Stop

        foreach ($signature in $signatures) {
            $signatureKey = $signature.PsPath
            $signatureData = Get-ItemProperty -Path $signatureKey -ErrorAction SilentlyContinue

            if ($signatureData.ProfileGuid -eq $ProfileGuid) {
                if ($PSCmdlet.ShouldProcess("Signature for $ProfileName", "Delete Signature Registry Key")) {
                    Write-Verbose "Deleting signature entry for ProfileGuid: $ProfileGuid"
                    Remove-Item -Path $signatureKey -Force -ErrorAction Stop
                    Write-Output "Deleted signature for: $ProfileName"
                }
            }
        }
    }
    catch {
        Write-Error "Failed to process signature registry keys for '$ProfileName': $_"
    }
}

function Get-NetworkProfiles {
    <#
    .SYNOPSIS
        Retrieves all network profiles from the registry.

    .DESCRIPTION
        Queries the registry for all network profiles and returns them as custom objects.

    .PARAMETER ProfilesPath
        The registry path to the network profiles.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        An array of profile objects with PsPath, PSChildName, and ProfileName properties.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProfilesPath
    )

    try {
        $profiles = Get-ChildItem -Path $ProfilesPath -ErrorAction Stop | ForEach-Object {
            $props = Get-ItemProperty -Path $_.PsPath -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                PsPath      = $_.PsPath
                PSChildName = $_.PSChildName
                ProfileName = $props.ProfileName
            }
        } | Sort-Object ProfileName

        return $profiles
    }
    catch {
        Write-Error "Failed to retrieve network profiles from registry: $_"
        throw
    }
}

function Main {
    <#
    .SYNOPSIS
        Main entry point for the script.

    .DESCRIPTION
        Orchestrates the process of identifying and removing unused network profiles.
    #>
    try {
        Write-Verbose "Starting unused network profile removal process"

        # Get active network profiles
        $activeProfiles = Get-ActiveNetworkProfileNames
        Write-Verbose "Found $($activeProfiles.Count) active profile(s)"

        # Define registry paths
        $profilesPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles"
        $signaturesPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\Unmanaged"

        # Get all network profiles from registry
        $profiles = Get-NetworkProfiles -ProfilesPath $profilesPath
        Write-Verbose "Found $($profiles.Count) total profile(s) in registry"

        # Process each profile
        $removedCount = 0
        foreach ($profile in $profiles) {
            $profileGuid = $profile.PSChildName
            $profileName = $profile.ProfileName

            # Skip if profile name is empty or profile is currently active
            if (-not $profileName) {
                Write-Verbose "Skipping profile with empty name: $profileGuid"
                continue
            }

            if ($profileName -in $activeProfiles) {
                Write-Verbose "Skipping active profile: $profileName"
                continue
            }

            # Remove unused profile
            Write-Verbose "Processing unused profile: $profileName ($profileGuid)"
            Remove-NetworkProfileRegistryKey -Path $profile.PsPath -Name $profileName -Guid $profileGuid
            Remove-NetworkSignatureRegistryKey -SignaturesPath $signaturesPath -ProfileGuid $profileGuid -ProfileName $profileName
            $removedCount++
        }

        Write-Output "Removal complete. Processed $removedCount unused profile(s)."
    }
    catch {
        Write-Error "Script execution failed: $_"
        exit 1
    }
}

# Script entry point
Main
