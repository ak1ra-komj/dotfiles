#Requires -Version 7.0

<#
.SYNOPSIS
    Move user directories to another drive and create junctions.
.DESCRIPTION
    Renames user directories with date suffix and creates junctions pointing to new locations on target drive.
    This script must be executed in the directory containing the user directories (Desktop, Downloads, etc.).
.PARAMETER TargetDrive
    The target drive letter (default: D)
.EXAMPLE
    cd $env:USERPROFILE
    .\Move-UserDirs.ps1 -TargetDrive E -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidatePattern('^[A-Z]$')]
    [string]$TargetDrive = 'D'
)

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Move a user directory and create a junction.
.PARAMETER sourcePath
    Full path of the source directory to move.
.PARAMETER TargetDriveLetter
    Target drive letter.
#>
function Move-UserDirectory {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$sourcePath,

        [Parameter(Mandatory)]
        [string]$TargetDriveLetter
    )

    try {
        $targetPath = $sourcePath -replace '^[A-Z]:', "${TargetDriveLetter}:"

        # Check if source path exists
        if (-not (Test-Path -Path $sourcePath)) {
            Write-Warning "Directory not found: $sourcePath"
            return
        }

        # Check if source is already a junction pointing to the target
        $item = Get-Item -Path $sourcePath
        if ($item.LinkType -eq 'Junction') {
            $currentTarget = $item.Target
            if ($currentTarget -eq $targetPath) {
                Write-Output "Skipped (already a junction to target): $sourcePath -> $targetPath"
                return
            }
            else {
                Write-Warning "Source is a junction pointing elsewhere: $sourcePath -> $currentTarget"
                return
            }
        }

        # Ensure target path exists
        if (-not (Test-Path -Path $targetPath -PathType Container)) {
            Write-Warning "Target directory not found: $targetPath. Please create it first."
            return
        }

        $dateSuffix = Get-Date -Format "yyyyMMdd"
        $renamedPath = "${sourcePath}_${dateSuffix}"

        # Check if renamed path already exists
        if (Test-Path -Path $renamedPath) {
            Write-Warning "Backup already exists: $renamedPath. Skipping to avoid overwrite."
            return
        }

        # Rename original directory
        if ($PSCmdlet.ShouldProcess($sourcePath, "Rename to $renamedPath")) {
            Rename-Item -Path $sourcePath -NewName $renamedPath -ErrorAction Stop
            Write-Output "Renamed: $sourcePath -> $renamedPath"
        }

        # Create junction
        if ($PSCmdlet.ShouldProcess($sourcePath, "Create junction to $targetPath")) {
            New-Item -ItemType Junction -Path $sourcePath -Target $targetPath -ErrorAction Stop | Out-Null
            Write-Output "Created junction: $sourcePath -> $targetPath"
        }
    }
    catch {
        Write-Error "Failed to process ${sourcePath}: $_"
    }
}

<#
.SYNOPSIS
    Main entry point.
#>
function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$TargetDrive
    )

    $userDirs = @(
        "Desktop",
        "Downloads",
        "Videos",
        "Pictures",
        "Documents",
        "Music",
        "OneDrive"
    )

    Write-Output "Starting user directory migration to ${TargetDrive}:\"
    Write-Output "Processing $($userDirs.Count) directories..."
    Write-Output ""

    foreach ($dir in $userDirs) {
        $sourcePath = Join-Path -Path $PWD -ChildPath $dir
        if (Test-Path -Path $sourcePath) {
            Move-UserDirectory -sourcePath $sourcePath -TargetDriveLetter $TargetDrive -WhatIf:$WhatIfPreference
        }
        else {
            Write-Warning "Directory not found in current location: $sourcePath"
        }
    }

    Write-Output ""
    Write-Output "Migration completed."
}

# Entry point
Main -TargetDrive $TargetDrive
