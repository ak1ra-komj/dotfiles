
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    $args
)

# Get the absolute paths of yt-dlp and aria2c
$ytDlpPath = (Get-Command yt-dlp).Source
$aria2cPath = (Get-Command aria2c).Source

# Determine the path to the CA certificate relative to the aria2c executable
$caCertificatePath = (Join-Path (Split-Path $aria2cPath) "ca-certificates.crt") -replace '\\', '/'

# Execute yt-dlp with additional parameters
& $ytDlpPath --cookies-from-browser=chrome `
             --downloader=aria2c `
             --downloader-args="aria2c:--max-concurrent-downloads=8 --max-connection-per-server=4 --ca-certificate=$caCertificatePath" `
             @args
