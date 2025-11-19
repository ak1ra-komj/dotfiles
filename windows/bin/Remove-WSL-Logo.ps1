#Requires -RunAsAdministrator

$target = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{B2B4A4D1-2754-4140-A2EB-9A76D9D7CDC6}"

if (Test-Path -Path $target) {
    Write-Out "Remove-Item $target"
    Remove-Item -Path $target
}
