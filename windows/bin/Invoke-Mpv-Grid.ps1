<#
.SYNOPSIS
    Invokes MPV players in a grid layout.

.DESCRIPTION
    This script was created by a Windows user who had downloaded too many pornographic videos, didn't know where to start, and wanted to watch more than one video at the same time.

.EXAMPLE
    .\Invoke-Mpv-Grid.ps1 -Monitor 1 -Layout 4x4
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string[]]$Videos,

    [Parameter()]
    [int]$Monitor = 0,

    [Parameter()]
    [ValidatePattern("^\d+x\d+$")]
    [string]$Layout = "2x2"
)

Set-StrictMode -Version Latest

# Add Windows Forms for screen and taskbar handling
Add-Type -AssemblyName System.Windows.Forms

function Get-MonitorWorkingArea {
    [CmdletBinding()]
    param (
        [int]$monitorIndex
    )

    $screens = [System.Windows.Forms.Screen]::AllScreens

    if ($monitorIndex -ge $screens.Count -or $monitorIndex -lt 0) {
        throw "Invalid monitor index. Available monitors: 0 to $($screens.Count - 1)."
    }

    return $screens[$monitorIndex].WorkingArea
}

function Get-GridPositions {
    [CmdletBinding()]
    param (
        [string]$layout,
        [System.Drawing.Rectangle]$workingArea
    )

    $null = $layout -match "^(\d+)x(\d+)$"
    $rows = [int]$matches[1]
    $cols = [int]$matches[2]

    $windowWidth = [math]::Floor($workingArea.Width / $cols)
    $windowHeight = [math]::Floor($workingArea.Height / $rows)
    $originX = $workingArea.X
    $originY = $workingArea.Y

    $positions = @()
    for ($row = 0; $row -lt $rows; $row++) {
        for ($col = 0; $col -lt $cols; $col++) {
            $positions += [PSCustomObject]@{
                X      = $originX + ($col * $windowWidth)
                Y      = $originY + ($row * $windowHeight)
                Width  = $windowWidth
                Height = $windowHeight
            }
        }
    }
    return $positions
}

function Find-VideoFiles {
    [CmdletBinding()]
    param (
        [string]$path = '.'
    )

    Write-Verbose "Searching for video files in '$path'..."
    $supportedExtensions = @(".mp4", ".mkv", ".avi", ".mov", ".flv", ".wmv", ".webm")

    return Get-ChildItem -Path $path -Recurse -File | Where-Object {
        $supportedExtensions -contains $_.Extension.ToLower()
    } | Select-Object -ExpandProperty FullName
}

function Start-MpvProcess {
    [CmdletBinding()]
    param (
        [string]$filePath,
        [PSCustomObject]$position
    )

    # Ensure geometry values are integers to avoid locale issues (e.g., commas in floats)
    $width = [int]$position.Width
    $height = [int]$position.Height
    $x = [int]$position.X
    $y = [int]$position.Y

    $geometry = "{0}x{1}+{2}+{3}" -f $width, $height, $x, $y
    
    # Use a single string for arguments to handle spaces in paths correctly
    # Quote the filePath to ensure MPV receives it as a single argument
    $mpvArgs = "--geometry=$geometry --no-border `"$filePath`""

    try {
        $process = Start-Process -FilePath "mpv.exe" -ArgumentList $mpvArgs -PassThru -ErrorAction Stop
        if ($null -ne $process) {
            Write-Host "Playing: $filePath (Position: $geometry) [PID: $($process.Id)]"
        }
    }
    catch {
        Write-Error "Failed to launch MPV for $filePath. Ensure mpv.exe is in your PATH. Error: $($_.Exception.Message)"
    }
}

try {
    # Get monitor information
    $workingArea = Get-MonitorWorkingArea -monitorIndex $Monitor

    # Generate window positions
    $positions = Get-GridPositions -layout $Layout -workingArea $workingArea

    # If no video paths are provided, search for video files
    if (-not $Videos) {
        $foundVideos = Find-VideoFiles
        if (-not $foundVideos) {
            Write-Error "No video files found in the current directory."
            return
        }
        $Videos = $foundVideos | Get-Random -Count ([math]::Min($foundVideos.Count, $positions.Count))
    }

    # Warn if fewer than the required number of videos are available
    if ($Videos.Count -lt $positions.Count) {
        Write-Warning "Fewer videos ($($Videos.Count)) than positions ($($positions.Count)) in the layout."
    }

    # Launch MPV player for each video file
    for ($i = 0; $i -lt $Videos.Count; $i++) {
        Start-MpvProcess -filePath $Videos[$i] -position $positions[$i]
    }

    Write-Host "All videos have been launched."
}
catch {
    Write-Error $_.Exception.Message
}
