param (
    [string[]]$VideoPaths,   # Command-line video file paths
    [int]$TargetMonitor = 0,  # Target monitor index (0-based)
    [string]$Layout = "2x2"  # Layout (e.g., "2x2", "3x2", "4x4")
)

# Add Windows Forms for screen and taskbar handling
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

# Adjust height to account for the taskbar (if it's on the selected monitor)
$taskbar = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if (-not $selectedMonitor.Bounds.Equals($taskbar)) {
    $taskbarHeight = $screenHeight - $taskbar.Height
    $screenHeight -= $taskbarHeight
    Write-Host "Adjusted for taskbar height: $taskbarHeight pixels."
}

# Parse layout parameter (e.g., "2x2")
if ($Layout -notmatch "^(\d+)x(\d+)$") {
    Write-Host "Error: Invalid layout format. Use format NxM (e.g., 2x2, 3x2). Exiting."
    exit
}

# Extract rows and columns from the layout
$rows = [int]$matches[1]
$cols = [int]$matches[2]

# Calculate window size based on the layout
$windowWidth = [math]::Floor($screenWidth / $cols)
$windowHeight = [math]::Floor($screenHeight / $rows)

# Generate window positions for the specified layout
$positions = @()
for ($row = 0; $row -lt $rows; $row++) {
    for ($col = 0; $col -lt $cols; $col++) {
        $x = $col * $windowWidth
        $y = $row * $windowHeight
        $positions += "$x,$y"
    }
}

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

    # Randomly select up to the number of available positions
    $VideoPaths = $VideoPaths | Get-Random -Count ([math]::Min($VideoPaths.Count, $positions.Count))
}

# Warn if fewer than the required number of videos are available
if ($VideoPaths.Count -lt $positions.Count) {
    Write-Host "Warning: Fewer videos than positions in the layout. Playing available files."
}

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
