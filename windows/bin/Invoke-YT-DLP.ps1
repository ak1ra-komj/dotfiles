#Requires -Version 5.1

<#
.SYNOPSIS
    Wrapper script for yt-dlp with aria2c downloader integration.

.DESCRIPTION
    Invokes yt-dlp with Chrome cookies and aria2c as the downloader.
    Automatically configures aria2c with CA certificates and optimal download settings.

.PARAMETER Arguments
    All arguments to pass through to yt-dlp.

.EXAMPLE
    Invoke-YT-DLP.ps1 "https://youtube.com/watch?v=example"

.NOTES
    yt-dlp: https://github.com/yt-dlp/yt-dlp
    aria2c: https://git.q3aql.dev/q3aql/aria2-static-builds
    Chrome cookie issue: https://github.com/yt-dlp/yt-dlp/issues/7271#issuecomment-1584404779
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest

function Get-ExecutablePath {
    <#
    .SYNOPSIS
        Gets the absolute path of an executable.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    try {
        $command = Get-Command $CommandName -ErrorAction Stop
        return $command.Source
    }
    catch {
        Write-Error "Failed to locate $CommandName. Ensure it is installed and available in PATH."
        throw
    }
}

function Get-Aria2cArguments {
    <#
    .SYNOPSIS
        Constructs aria2c downloader arguments with CA certificate path.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Aria2cPath
    )

    $aria2cDirectory = Split-Path $Aria2cPath
    $caCertificatePath = Join-Path $aria2cDirectory "ca-certificates.crt"

    if (-not (Test-Path $caCertificatePath)) {
        Write-Warning "CA certificate not found at: $caCertificatePath"
    }

    # Normalize path separators for aria2c
    $normalizedPath = $caCertificatePath -replace '\\', '/'

    return @(
        "--ca-certificate=$normalizedPath",
        "--max-concurrent-downloads=8",
        "--max-connection-per-server=4"
    ) -join ' '
}

function Invoke-YtDlpWithAria2c {
    <#
    .SYNOPSIS
        Executes yt-dlp with aria2c downloader and Chrome cookies.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$YtDlpPath,

        [Parameter(Mandatory = $true)]
        [string]$Aria2cArgs,

        [Parameter(Mandatory = $false)]
        [string[]]$PassthroughArgs
    )

    try {
        & $YtDlpPath --cookies-from-browser=chrome `
            --downloader=aria2c `
            --downloader-args="aria2c:$Aria2cArgs" `
            @PassthroughArgs
    }
    catch {
        Write-Error "Failed to execute yt-dlp: $_"
        throw
    }
}

function Main {
    <#
    .SYNOPSIS
        Main entry point for the script.
    #>
    try {
        $ytDlpPath = Get-ExecutablePath -CommandName "yt-dlp"
        $aria2cPath = Get-ExecutablePath -CommandName "aria2c"

        $aria2cArgs = Get-Aria2cArguments -Aria2cPath $aria2cPath

        Invoke-YtDlpWithAria2c -YtDlpPath $ytDlpPath `
            -Aria2cArgs $aria2cArgs `
            -PassthroughArgs $Arguments
    }
    catch {
        exit 1
    }
}

# Script entry point
Main
