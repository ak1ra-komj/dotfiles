#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
Modifies the default network interface's gateway and DNS settings

.DESCRIPTION
This script operates in two modes:

Set Mode (default):
1. Automatically detects the current default route interface
2. Validates the proxy gateway IP is reachable on the local subnet
3. Records original configuration before making changes
4. Converts DHCP to static IP if necessary
5. Updates gateway and DNS settings atomically with rollback on failure
6. Outputs original configuration for restoration

Restore Mode (-Restore):
1. Fully reverts the interface to DHCP
2. Removes all static configurations (IP, route, DNS)
3. Enables DHCP and waits for lease confirmation
4. Clears DNS cache

.PARAMETER ProxyGatewayIP
The IP address of the proxy gateway to use for routing and DNS.
Must be a valid IPv4 address reachable on the current subnet.

.PARAMETER Restore
Switch to restore the interface to full DHCP configuration.

.PARAMETER AdapterRestartWaitSeconds
Maximum seconds to wait for adapter to come back up after restart. Default: 10

.PARAMETER DhcpLeaseTimeoutSeconds
Maximum seconds to wait for DHCP lease acquisition. Default: 30

.EXAMPLE
.\Set-ProxyGateway.ps1 -ProxyGatewayIP 192.168.1.100
Sets the proxy gateway to 192.168.1.100

.EXAMPLE
.\Set-ProxyGateway.ps1 -Restore
Restores the interface to DHCP configuration

.NOTES
Requires: PowerShell 7.0+, Administrator privileges
Author: ak1ra
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Set')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Set')]
    [ValidateScript({
            if (-not [System.Net.IPAddress]::TryParse($_, [ref]$null)) {
                throw "Invalid IP address format: $_"
            }
            $true
        })]
    [string]$ProxyGatewayIP,

    [Parameter(Mandatory = $true, ParameterSetName = 'Restore')]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'Restore')]
    [ValidateRange(5, 60)]
    [int]$AdapterRestartWaitSeconds = 10,

    [Parameter(ParameterSetName = 'Restore')]
    [ValidateRange(10, 120)]
    [int]$DhcpLeaseTimeoutSeconds = 30
)

Set-StrictMode -Version Latest

# Constants
$script:DHCP_POLL_INTERVAL_MS = 800
$script:IPV4_ADDRESS_FAMILY = 'IPv4'
$script:DEFAULT_ROUTE_PREFIX = '0.0.0.0/0'

#region Helper Functions

function Get-DefaultNetworkInterface {
    <#
    .SYNOPSIS
    Gets the default route interface and its configuration
    .DESCRIPTION
    Selects the lowest metric IPv4 default route with a valid next hop and adapter in Up state.
    Returns the first Preferred IPv4 address and complete network configuration.
    .OUTPUTS
    Hashtable containing interface configuration details
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        # Find the default route with lowest metric
        $defaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
        Where-Object { $null -ne $_.NextHop -and $_.NextHop -ne '0.0.0.0' } |
        Sort-Object RouteMetric |
        Select-Object -First 1

        if (-not $defaultRoute) {
            throw 'No default route found. Please ensure network connectivity is established.'
        }

        $interfaceIndex = $defaultRoute.InterfaceIndex

        # Validate adapter state
        $adapter = Get-NetAdapter -InterfaceIndex $interfaceIndex -ErrorAction Stop
        if ($adapter.Status -ne 'Up') {
            throw "Network adapter '$($adapter.Name)' (ifIndex=$interfaceIndex) is not in Up state (current: $($adapter.Status))."
        }

        $interface = Get-NetIPInterface -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -ErrorAction Stop

        # Get preferred IPv4 addresses
        $ipAddresses = Get-NetIPAddress -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.AddressState -eq 'Preferred' }

        if (-not $ipAddresses) {
            throw "No Preferred IPv4 address found on interface '$($adapter.Name)' (ifIndex=$interfaceIndex)."
        }

        # Use first preferred address for deterministic behavior
        $primaryIP = $ipAddresses | Select-Object -First 1

        $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses

        return @{
            InterfaceIndex = $interfaceIndex
            InterfaceName  = $adapter.Name
            DhcpEnabled    = ($interface.Dhcp -eq 'Enabled')
            IPAddress      = $primaryIP.IPAddress
            PrefixLength   = $primaryIP.PrefixLength
            PrefixOrigin   = $primaryIP.PrefixOrigin
            DefaultGateway = $defaultRoute.NextHop
            DNS            = $dnsServers
            AdapterStatus  = $adapter.Status
        }
    }
    catch {
        Write-Error "Failed to retrieve network interface configuration: $_"
        throw
    }
}

function Test-IPInSameSubnet {
    <#
    .SYNOPSIS
    Validates that a target IP is in the same subnet as the source IP
    .DESCRIPTION
    Calculates network addresses for both IPs using the prefix length and compares them.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceIP,

        [Parameter(Mandatory = $true)]
        [int]$PrefixLength,

        [Parameter(Mandatory = $true)]
        [string]$TargetIP
    )

    try {
        $sourceAddr = [System.Net.IPAddress]::Parse($SourceIP)
        $targetAddr = [System.Net.IPAddress]::Parse($TargetIP)

        # Calculate subnet mask from prefix length
        $maskBytes = [byte[]]::new(4)
        $remainingBits = $PrefixLength

        for ($i = 0; $i -lt 4; $i++) {
            if ($remainingBits -ge 8) {
                # Full octet is masked
                $maskBytes[$i] = 255
                $remainingBits -= 8
            }
            elseif ($remainingBits -gt 0) {
                # Partial octet: create mask by setting leftmost bits
                # Example: 6 bits = 11111100 = 252
                $maskBytes[$i] = [byte](256 - [Math]::Pow(2, 8 - $remainingBits))
                $remainingBits = 0
            }
            else {
                # No more bits to mask
                $maskBytes[$i] = 0
            }
        }

        # Calculate network addresses by applying mask to both IPs
        $sourceBytes = $sourceAddr.GetAddressBytes()
        $targetBytes = $targetAddr.GetAddressBytes()

        $sourceNetwork = [byte[]]::new(4)
        $targetNetwork = [byte[]]::new(4)

        for ($i = 0; $i -lt 4; $i++) {
            $sourceNetwork[$i] = $sourceBytes[$i] -band $maskBytes[$i]
            $targetNetwork[$i] = $targetBytes[$i] -band $maskBytes[$i]
        }

        # Compare network addresses for equality
        $sourceNetworkInt = [System.BitConverter]::ToUInt32($sourceNetwork, 0)
        $targetNetworkInt = [System.BitConverter]::ToUInt32($targetNetwork, 0)

        return ($sourceNetworkInt -eq $targetNetworkInt)
    }
    catch {
        Write-Error "Failed to validate subnet compatibility: $_"
        return $false
    }
}

function Set-StaticIPConfiguration {
    <#
    .SYNOPSIS
    Converts interface from DHCP to static IP configuration
    .DESCRIPTION
    Disables DHCP, removes DHCP-assigned addresses, and applies static IPv4 configuration.
    Performs operations atomically to maintain network state consistency.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [int]$InterfaceIndex,

        [Parameter(Mandatory = $true)]
        [string]$InterfaceName,

        [Parameter(Mandatory = $true)]
        [string]$IPAddress,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 32)]
        [int]$PrefixLength
    )

    if ($PSCmdlet.ShouldProcess("Adapter '$InterfaceName'", 'Convert from DHCP to static IP configuration')) {
        try {
            Write-Output "Converting adapter '$InterfaceName' from DHCP to static IP..."

            # Remove DHCP-assigned addresses first
            $dhcpAddresses = Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.PrefixOrigin -eq 'Dhcp' }

            if ($dhcpAddresses) {
                $dhcpAddresses | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
                Write-Output "  Removed DHCP-assigned addresses"
            }

            # Apply static IP configuration
            New-NetIPAddress -InterfaceIndex $InterfaceIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -ErrorAction Stop | Out-Null
            Write-Output "  Applied static IP: $IPAddress/$PrefixLength"

            # Disable DHCP last to ensure static IP is already in place
            Set-NetIPInterface -InterfaceIndex $InterfaceIndex -Dhcp Disabled -ErrorAction Stop
            Write-Output "  DHCP disabled"
        }
        catch {
            Write-Error "Failed to set static IP configuration on adapter '$InterfaceName': $_"
            throw
        }
    }
}

function Set-NetworkGatewayAndDNS {
    <#
    .SYNOPSIS
    Atomically updates default gateway and DNS server
    .DESCRIPTION
    Removes existing default route and applies new gateway and DNS in a single transaction.
    Provides rollback capability if any step fails.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [int]$InterfaceIndex,

        [Parameter(Mandatory = $true)]
        [string]$InterfaceName,

        [Parameter(Mandatory = $true)]
        [string]$GatewayIP,

        [Parameter(Mandatory = $true)]
        [hashtable]$OriginalConfig
    )

    if ($PSCmdlet.ShouldProcess("Adapter '$InterfaceName'", "Update gateway and DNS to $GatewayIP")) {
        $rollbackNeeded = $false
        try {
            Write-Output "Updating gateway and DNS on adapter '$InterfaceName'..."

            # Remove existing default route
            Remove-NetRoute -InterfaceIndex $InterfaceIndex -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
            $rollbackNeeded = $true

            # Apply new default gateway
            New-NetRoute -InterfaceIndex $InterfaceIndex -DestinationPrefix '0.0.0.0/0' -NextHop $GatewayIP -ErrorAction Stop | Out-Null
            Write-Output "  Gateway updated: $GatewayIP"

            # Update DNS settings
            Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses $GatewayIP -ErrorAction Stop
            Write-Output "  DNS server updated: $GatewayIP"

            # Clear DNS cache to ensure clean state
            Clear-DnsClientCache -ErrorAction Stop
            Write-Output "  DNS cache cleared"

            $rollbackNeeded = $false
        }
        catch {
            if ($rollbackNeeded) {
                Write-Warning "Operation failed, attempting to restore original gateway..."
                try {
                    New-NetRoute -InterfaceIndex $InterfaceIndex -DestinationPrefix '0.0.0.0/0' -NextHop $OriginalConfig.DefaultGateway -ErrorAction Stop | Out-Null
                    Write-Output "  Original gateway restored: $($OriginalConfig.DefaultGateway)"
                }
                catch {
                    Write-Error "Critical: Failed to restore original gateway. Manual intervention required."
                }
            }
            Write-Error "Failed to update gateway and DNS: $_"
            throw
        }
    }
}

function Restore-DHCPConfiguration {
    <#
    .SYNOPSIS
    Fully restores the adapter to DHCP configuration
    .DESCRIPTION
    Systematically removes all static configurations and re-enables DHCP.
    Performs a hard reset of the adapter to force DHCP lease negotiation.
    Waits for DHCP lease confirmation before completing.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [int]$InterfaceIndex,

        [Parameter(Mandatory = $true)]
        [string]$InterfaceName,

        [Parameter(Mandatory = $false)]
        [int]$AdapterRestartWaitSeconds = 10,

        [Parameter(Mandatory = $false)]
        [int]$DhcpLeaseTimeoutSeconds = 30
    )

    if ($PSCmdlet.ShouldProcess("Adapter '$InterfaceName'", 'Restore to DHCP configuration')) {
        try {
            Write-Output "Restoring DHCP configuration on adapter '$InterfaceName'..."

            # Step 1: Reset DNS to DHCP-provided servers
            Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ResetServerAddresses -ErrorAction Stop
            Write-Output "  DNS servers reset to DHCP"

            # Step 2: Remove static default routes
            $staticRoutes = Get-NetRoute -InterfaceIndex $InterfaceIndex -AddressFamily $script:IPV4_ADDRESS_FAMILY -DestinationPrefix $script:DEFAULT_ROUTE_PREFIX -ErrorAction SilentlyContinue
            if ($staticRoutes) {
                $staticRoutes | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
                Write-Output "  Static routes removed"
            }

            # Step 3: Remove manually configured IP addresses
            $manualIPs = Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily $script:IPV4_ADDRESS_FAMILY -ErrorAction SilentlyContinue |
            Where-Object { $_.PrefixOrigin -eq 'Manual' }
            if ($manualIPs) {
                $manualIPs | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Write-Output "  Static IP addresses removed"
            }

            # Step 4: Enable DHCP
            Set-NetIPInterface -InterfaceIndex $InterfaceIndex -Dhcp Enabled -ErrorAction Stop
            Write-Output "  DHCP enabled"

            # Step 5: Force adapter restart to trigger DHCP discovery
            Write-Output "  Restarting adapter to trigger DHCP negotiation..."
            Restart-NetworkAdapter -InterfaceIndex $InterfaceIndex -MaxWaitSeconds $AdapterRestartWaitSeconds

            # Step 6: Wait for DHCP lease
            Write-Output "  Waiting for DHCP lease..."
            $dhcpIP = Wait-ForDHCPLease -InterfaceIndex $InterfaceIndex -InterfaceName $InterfaceName -TimeoutSeconds $DhcpLeaseTimeoutSeconds
            Write-Output "  DHCP lease confirmed: $dhcpIP"

            # Step 7: Clear DNS cache
            Clear-DnsClientCache -ErrorAction Stop
            Write-Output "  DNS cache cleared"

            Write-Output 'DHCP restoration completed successfully'
        }
        catch {
            Write-Error "Failed to restore DHCP configuration on adapter '$InterfaceName': $_"
            throw
        }
    }
}

function Restart-NetworkAdapter {
    <#
    .SYNOPSIS
    Restarts a network adapter and waits for it to come back up
    .DESCRIPTION
    Disables and re-enables the adapter, polling for Up status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$InterfaceIndex,

        [Parameter(Mandatory = $false)]
        [int]$MaxWaitSeconds = 10
    )

    $adapter = Get-NetAdapter -InterfaceIndex $InterfaceIndex -ErrorAction Stop

    # Disable adapter
    Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
    Write-Output "    Adapter disabled"

    # Wait for adapter to fully disable
    Start-Sleep -Seconds 2

    # Re-enable adapter
    Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
    Write-Output "    Adapter enabled"

    # Wait for adapter to come back up
    $waited = 0
    while ($waited -lt $MaxWaitSeconds) {
        $adapterState = Get-NetAdapter -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue
        if ($adapterState -and $adapterState.Status -eq 'Up') {
            Write-Output "    Adapter is Up"
            return
        }
        Start-Sleep -Seconds 1
        $waited++
    }

    throw "Adapter did not come back up after restart within $MaxWaitSeconds seconds"
}

function Wait-ForDHCPLease {
    <#
    .SYNOPSIS
    Waits for a Preferred DHCP IPv4 address to appear
    .DESCRIPTION
    Polls the interface until a Preferred IPv4 address with DHCP origin appears.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$InterfaceIndex,

        [Parameter(Mandatory = $true)]
        [string]$InterfaceName,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30
    )

    $maxAttempts = [math]::Ceiling(($TimeoutSeconds * 1000) / $script:DHCP_POLL_INTERVAL_MS)

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $dhcpAddress = Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily $script:IPV4_ADDRESS_FAMILY -ErrorAction SilentlyContinue |
        Where-Object { $_.AddressState -eq 'Preferred' -and $_.PrefixOrigin -eq 'Dhcp' } |
        Select-Object -First 1

        if ($dhcpAddress) {
            return $dhcpAddress.IPAddress
        }

        Start-Sleep -Milliseconds $script:DHCP_POLL_INTERVAL_MS
    }

    throw "Timeout: No DHCP Preferred IPv4 address received on adapter '$InterfaceName' (ifIndex=$InterfaceIndex) after $TimeoutSeconds seconds."
}

function Show-ConfigurationSummary {
    <#
    .SYNOPSIS
    Displays current and original network configuration in a clear format
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$InterfaceIndex,

        [Parameter(Mandatory = $true)]
        [hashtable]$OriginalConfig
    )

    Write-Output "`n=== Current Network Configuration ==="
    Get-NetIPConfiguration -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue | Format-List
    Get-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Format-List

    Write-Output "`n=== Original Configuration (for restoration) ==="
    Write-Output "Interface: $($OriginalConfig.InterfaceName) (ifIndex=$($OriginalConfig.InterfaceIndex))"
    Write-Output "DHCP Enabled: $($OriginalConfig.DhcpEnabled)"
    Write-Output "IP Address: $($OriginalConfig.IPAddress)/$($OriginalConfig.PrefixLength)"
    Write-Output "Default Gateway: $($OriginalConfig.DefaultGateway)"
    Write-Output "DNS Servers: $($OriginalConfig.DNS -join ', ')"
}

function Get-NetworkConfigurationDetails {
    <#
    .SYNOPSIS
    Retrieves and formats network configuration for display
    .DESCRIPTION
    Consolidates Get-NetIPConfiguration and Get-DnsClientServerAddress calls.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$InterfaceIndex
    )

    $ipConfig = Get-NetIPConfiguration -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue
    $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -AddressFamily $script:IPV4_ADDRESS_FAMILY -ErrorAction SilentlyContinue

    return @{
        IPConfiguration  = $ipConfig
        DNSConfiguration = $dnsConfig
    }
}

#endregion

#region Main Logic

function Set-ProxyGatewayConfiguration {
    <#
    .SYNOPSIS
    Applies proxy gateway configuration to the default network interface
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProxyGatewayIP
    )

    try {
        # Get current network configuration
        $originalConfig = Get-DefaultNetworkInterface
        Write-Output "Detected interface: $($originalConfig.InterfaceName) (ifIndex=$($originalConfig.InterfaceIndex))"
        Write-Output "Current IP: $($originalConfig.IPAddress)/$($originalConfig.PrefixLength)"
        Write-Output "Current Gateway: $($originalConfig.DefaultGateway)"

        # Validate proxy gateway is in same subnet
        if (-not (Test-IPInSameSubnet -SourceIP $originalConfig.IPAddress -PrefixLength $originalConfig.PrefixLength -TargetIP $ProxyGatewayIP)) {
            throw "Proxy gateway $ProxyGatewayIP is not in the same subnet as current IP $($originalConfig.IPAddress)/$($originalConfig.PrefixLength). Cannot proceed."
        }
        Write-Output "Validated: Proxy gateway $ProxyGatewayIP is reachable on local subnet"

        # Convert to static IP if currently using DHCP
        if ($originalConfig.DhcpEnabled) {
            Write-Output "`nInterface is currently using DHCP, converting to static configuration..."
            Set-StaticIPConfiguration `
                -InterfaceIndex $originalConfig.InterfaceIndex `
                -InterfaceName $originalConfig.InterfaceName `
                -IPAddress $originalConfig.IPAddress `
                -PrefixLength $originalConfig.PrefixLength
        }
        else {
            Write-Output "`nInterface is already using static IP configuration"
        }

        # Apply new gateway and DNS
        Write-Output "`nApplying proxy gateway configuration..."
        Set-NetworkGatewayAndDNS `
            -InterfaceIndex $originalConfig.InterfaceIndex `
            -InterfaceName $originalConfig.InterfaceName `
            -GatewayIP $ProxyGatewayIP `
            -OriginalConfig $originalConfig

        # Display summary
        Show-ConfigurationSummary -InterfaceIndex $originalConfig.InterfaceIndex -OriginalConfig $originalConfig

        Write-Output "`n=== Configuration Applied Successfully ==="
    }
    catch {
        Write-Error "Failed to apply proxy gateway configuration: $_"
        throw
    }
}

function Restore-DHCPNetworkConfiguration {
    <#
    .SYNOPSIS
    Restores the default network interface to DHCP configuration
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [int]$AdapterRestartWaitSeconds = 10,

        [Parameter(Mandatory = $false)]
        [int]$DhcpLeaseTimeoutSeconds = 30
    )

    try {
        $originalConfig = Get-DefaultNetworkInterface
        Write-Output "Detected interface: $($originalConfig.InterfaceName) (ifIndex=$($originalConfig.InterfaceIndex))"

        Restore-DHCPConfiguration `
            -InterfaceIndex $originalConfig.InterfaceIndex `
            -InterfaceName $originalConfig.InterfaceName `
            -AdapterRestartWaitSeconds $AdapterRestartWaitSeconds `
            -DhcpLeaseTimeoutSeconds $DhcpLeaseTimeoutSeconds

        Write-Output "`n=== Restored Network Configuration ==="
        $networkConfig = Get-NetworkConfigurationDetails -InterfaceIndex $originalConfig.InterfaceIndex
        $networkConfig.IPConfiguration | Format-List
        $networkConfig.DNSConfiguration | Format-List

        Write-Output "`n=== DHCP Restoration Completed Successfully ==="
    }
    catch {
        Write-Error "Failed to restore DHCP configuration: $_"
        throw
    }
}

#endregion

# Main execution
try {
    if ($Restore) {
        Restore-DHCPNetworkConfiguration -AdapterRestartWaitSeconds $AdapterRestartWaitSeconds -DhcpLeaseTimeoutSeconds $DhcpLeaseTimeoutSeconds
    }
    else {
        Set-ProxyGatewayConfiguration -ProxyGatewayIP $ProxyGatewayIP
    }
}
catch {
    # Let PowerShell handle the error display, just ensure non-zero exit
    exit 1
}
