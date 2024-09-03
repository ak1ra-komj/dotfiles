
# yt-dlp: https://github.com/yt-dlp/yt-dlp
# aria2c: https://git.q3aql.dev/q3aql/aria2-static-builds
# https://github.com/ak1ra-komj/dotfiles/blob/master/windows/ytdlp.ps1

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
# Try after closing chrome completely OR Launch chrome.exe with the flag: --disable-features=LockProfileCookieDatabase
# Ref: https://github.com/yt-dlp/yt-dlp/issues/7271#issuecomment-1584404779
& $ytDlpPath --cookies-from-browser=chrome `
             --downloader=aria2c `
             --downloader-args="aria2c:--max-concurrent-downloads=8 --max-connection-per-server=4 --ca-certificate=$caCertificatePath" `
             @args
