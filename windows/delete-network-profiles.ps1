# Get the list of active network profile names
$ActiveProfiles = (Get-NetConnectionProfile).Name

# Define registry paths
$ProfilesPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles"
$SignaturesPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\Unmanaged"

# Iterate over all stored network profiles
Get-ChildItem $ProfilesPath | ForEach-Object {
    $ProfileGUID = $_.PSChildName
    $ProfileName = (Get-ItemProperty $_.PsPath).ProfileName

    # If the profile is unused, delete it
    if ($ProfileName -and ($ProfileName -notin $ActiveProfiles)) {
        Write-Host "Deleting Profile: $ProfileName ($ProfileGUID)"

        # Delete the profile from NetworkList\Profiles
        # Remove-Item -Path $_.PsPath -Force

        # Now check Signatures\Unmanaged for matching ProfileGuid
        Get-ChildItem $SignaturesPath | ForEach-Object {
            $SignatureKey = $_.PsPath
            $SignatureData = Get-ItemProperty -Path $SignatureKey

            # Check if the ProfileGuid matches in any signature entry
            if ($SignatureData.ProfileGuid -eq $ProfileGUID) {
                Write-Host "Deleting Signature Entry for ProfileGuid: $ProfileGUID"
                # Remove-Item -Path $SignatureKey -Force
            }
        }
    }
}
