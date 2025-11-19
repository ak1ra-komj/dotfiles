#Requires -Version 7.0

<#
.SYNOPSIS
    A lightweight GNU Stow emulator for PowerShell.

.DESCRIPTION
    Recursively symlinks files from a package directory to a target directory.
    - Uses relative paths for symbolic links.
    - Supports Stow and Unstow modes.
    - Supports Dry-run (-WhatIf).

.EXAMPLE
    .\Invoke-Stow.ps1 -PackageDir ".\bash" -TargetDir "$HOME" -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$PackageDir,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$TargetDir = $HOME,

    [switch]$Delete
)

Set-StrictMode -Version Latest

# -----------------------------------------------------------------------------
# Function: Get-RelativeLinkTarget
# Purpose: Calculates the relative path from the Link location to the Source file.
# -----------------------------------------------------------------------------
function Get-RelativeLinkTarget {
    param (
        [string]$FromDirectory,
        [string]$ToSourceFile
    )
    return [System.IO.Path]::GetRelativePath($FromDirectory, $ToSourceFile)
}

# -----------------------------------------------------------------------------
# Function: New-StowLink
# Purpose: Creates the directory structure and the symbolic link.
# -----------------------------------------------------------------------------
function New-StowLink {
    param (
        [string]$SourceFilePath,
        [string]$TargetFilePath
    )

    $TargetParentDir = Split-Path $TargetFilePath -Parent

    # 1. Ensure Parent Directory Exists
    if (-not (Test-Path $TargetParentDir)) {
        # New-Item supports WhatIf automatically based on the script scope
        New-Item -ItemType Directory -Path $TargetParentDir | Out-Null
    }

    # 2. Calculate Relative Path for the Symlink
    $RelLinkTarget = Get-RelativeLinkTarget -FromDirectory $TargetParentDir -ToSourceFile $SourceFilePath

    # 3. Create the Symbolic Link
    if (-not (Test-Path $TargetFilePath)) {
        Write-Verbose "Linking: $TargetFilePath -> $RelLinkTarget"
        New-Item -ItemType SymbolicLink -Path $TargetFilePath -Value $RelLinkTarget | Out-Null
    }
    else {
        # Conflict Resolution
        $ExistingItem = Get-Item $TargetFilePath
        if ($ExistingItem.LinkType -eq 'SymbolicLink') {
            Write-Verbose "Skipping '$TargetFilePath': Link already exists."
        }
        else {
            Write-Warning "Conflict: '$TargetFilePath' exists and is not a link. Skipping."
        }
    }
}

# -----------------------------------------------------------------------------
# Function: Remove-StowLink
# Purpose: Removes the symbolic link and cleans up empty parent directories.
# -----------------------------------------------------------------------------
function Remove-StowLink {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$TargetFilePath
    )

    if (Test-Path $TargetFilePath) {
        $Item = Get-Item $TargetFilePath

        # Safety Check: Only delete Symbolic Links
        if ($Item.LinkType -eq 'SymbolicLink') {
            Write-Verbose "Removing Link: $TargetFilePath"
            Remove-Item -Path $TargetFilePath

            # Clean up empty parent directory (Recursive cleanup is not implemented to keep it safe/simple)
            $ParentDir = Split-Path $TargetFilePath -Parent
            if (Test-Path $ParentDir) {
                $RemainingItems = Get-ChildItem $ParentDir
                if ($RemainingItems.Count -eq 0) {
                    # Check ShouldProcess explicitly for the directory removal
                    if ($PSCmdlet.ShouldProcess($ParentDir, "Remove Empty Directory")) {
                        Remove-Item $ParentDir -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        else {
            Write-Warning "Skipping Unstow for '$TargetFilePath': Not a symbolic link."
        }
    }
}

# -----------------------------------------------------------------------------
# Function: Main
# Purpose: Entry point. Resolves paths and iterates through the package.
# -----------------------------------------------------------------------------
function Main {
    # 1. Path Resolution
    if (-not (Test-Path $PackageDir)) {
        Write-Error "Package Directory not found: $PackageDir"
        return
    }

    $AbsPackagePath = Resolve-Path $PackageDir
    $AbsTargetPath = $TargetDir -replace "~", $HOME

    Write-Verbose "Stow Mode: $(if ($Delete) {'Unstow'} else {'Stow'})"
    Write-Verbose "Package: $AbsPackagePath"
    Write-Verbose "Target:  $AbsTargetPath"

    # 2. File Enumeration
    $Files = Get-ChildItem -Path $AbsPackagePath -Recurse -File

    foreach ($File in $Files) {
        # Compute paths
        $RelPath = [System.IO.Path]::GetRelativePath($AbsPackagePath, $File.FullName)
        $DestPath = Join-Path $AbsTargetPath $RelPath

        # Dispatch Operation
        if ($Delete) {
            Remove-StowLink -TargetFilePath $DestPath
        }
        else {
            New-StowLink -SourceFilePath $File.FullName -TargetFilePath $DestPath
        }
    }
}

# -----------------------------------------------------------------------------
# Execution
# -----------------------------------------------------------------------------
Main
