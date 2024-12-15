param (
    [string[]]$VideoPaths,   # Command-line video file paths
    [int]$TargetMonitor = 0  # Target monitor index (0-based)
)

Add-Type -AssemblyName System.Windows.Forms

# Get monitor information
$monitors = [System.Windows.Forms.Screen]::AllScreens

if ($TargetMonitor -ge $monitors.Count -or $TargetMonitor -lt 0) {
    Write-Host "Error: Invalid monitor index. Exiting."
    exit
}

# Select the target monitor
$selectedMonitor = $monitors[$TargetMonitor]
$monitorX = $selectedMonitor.Bounds.X
$monitorY = $selectedMonitor.Bounds.Y
$screenWidth = $selectedMonitor.Bounds.Width
$screenHeight = $selectedMonitor.Bounds.Height

# Calculate window size based on the target monitor
$windowWidth = [math]::Floor($screenWidth / 2)
$windowHeight = [math]::Floor($screenHeight / 2)

# Window positions for the 4 quadrants (top-left, bottom-left, top-right, bottom-right)
$positions = @(
    "0,0",                  # Top-left
    "0,$($windowHeight)",   # Bottom-left
    "$($windowWidth),0",    # Top-right
    "$($windowWidth),$($windowHeight)" # Bottom-right
)

# Adjust positions to the target monitor's coordinates
$positions = $positions | ForEach-Object {
    $coords = $_.Split(",")
    "$($monitorX + [int]$coords[0]),$($monitorY + [int]$coords[1])"
}

# If no video paths are provided, search for video files in the current directory
if (-not $VideoPaths) {
    Write-Host "No video paths provided. Searching for video files in the current directory..."

    # Supported video file extensions
    $supportedExtensions = @(".mp4", ".mkv", ".avi", ".mov", ".flv")

    # Recursively find video files
    $VideoPaths = Get-ChildItem -Path . -Recurse -File | Where-Object {
        $supportedExtensions -contains $_.Extension.ToLower()
    } | Select-Object -ExpandProperty FullName

    # Exit if no video files are found
    if ($VideoPaths.Count -eq 0) {
        Write-Host "Error: No video files found. Exiting."
        exit
    }

    # Randomly select up to 4 video files
    $VideoPaths = $VideoPaths | Get-Random -Count ([math]::Min($VideoPaths.Count, 4))
}

# Warn if fewer than 4 video files are available
if ($VideoPaths.Count -lt 4) {
    Write-Host "Warning: Fewer than 4 video files found. Playing available files."
}

# Debug: Log video paths
Write-Host "Video paths: $($VideoPaths -join ', ')"

# Launch MPV player for each video file with the specified layout
for ($i = 0; $i -lt $VideoPaths.Count; $i++) {
    $position = $positions[$i]
    $geometry = "$($windowWidth)x$($windowHeight)+$($position.Replace(',', '+'))"
    $videoFile = $VideoPaths[$i]

    # Launch MPV player with geometry and no border
    Start-Process -NoNewWindow -FilePath "mpv.exe" -ArgumentList "--geometry=$geometry", "--no-border", "`"$videoFile`""
    Write-Host "Playing: $videoFile (Position: $geometry)"
}

Write-Host "All videos have been launched."
