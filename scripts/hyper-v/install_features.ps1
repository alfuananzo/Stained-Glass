param([String]$LabName, [String]$PassWord, $dc1, $dns)


$pass = $PassWord
$pass = ConvertTo-SecureString -String $pass -AsPlainText -force
$creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$pass
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
[xml]$xml = Get-Content -Path "$dir\..\..\configs\labs_config.xml"


[string]$ip = $xml.labs.$LabName.IP.split(".")[0,1,2] -join(".")
[string]$domain = $xml.labs.$LabName.domain
[string]$subdomain1 = $xml.labs.$labName.subdomain1
[string]$subdomain2 = $xml.labs.$labName.subdomain2

function iis ($machine) {
    Install-WindowsFeature -ConfigurationFilePath G:\lab-deployer\configs\IIS_Deployment.xml -ComputerName $machine -Credential $creds
}

function dns ($machine, $zones) {

    Install-WindowsFeature -ConfigurationFilePath G:\lab-deployer\configs\DNS_Deployment.xml -ComputerName $machine -Credential $creds
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { Add-DnsServerForwarder -IPAddress 8.8.8.8 }
    foreach ($zone in $zones) {
        $zone = $zone.Split(",")

        Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { $newzone = ([WMIClass]"\\$env:COMPUTERNAME\root\MicrosoftDNS:MicrosoftDNS_Zone").CreateZone($using:zone[0], 0, $False, $Null, $Null, $Null) }
        Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { $newa = [WMIClass]"\\$env:COMPUTERNAME\root\MicrosoftDNS:MicrosoftDNS_AType" ; $newar = $newa.CreateInstanceFromPropertyData($env:COMPUTERNAME, $using:zone[0], $using:zone[0], $Null, $Null, $using:zone[1] ) }
        Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { $newa = [WMIClass]"\\$env:COMPUTERNAME\root\MicrosoftDNS:MicrosoftDNS_AType" ; $newar = $newa.CreateInstanceFromPropertyData($env:COMPUTERNAME, $using:zone[0], "www.$($using:zone[0])", $Null, $Null, $using:zone[1] ) }
    }
}

function dhcp ($machine, $ip, $nat_ip, $vm_name) {
    Install-WindowsFeature -ConfigurationFilePath G:\lab-deployer\configs\DHCP_Deployment.xml -ComputerName $machine -Credential $creds
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { Add-DhcpServerv4Scope -Name $using:LabName -StartRange "$($using:ip).20" -EndRange "$($using:ip).254" -SubnetMask 255.255.255.0 -Description "$using:LabName clients scope" }
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { Set-DhcpServerv4OptionValue -DnsServer $using:dns -ScopeId "$($using:ip).0" -Force }
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { Set-DhcpServerv4OptionValue -Router "$($using:nat_ip)" -ScopeId "$($using:ip).0" -Force }

    # Authorize DHCP server
    Invoke-Command -ComputerName $dc1 -Credential $creds -ScriptBlock { Add-DhcpServerInDC -DnsName $using:vm_name -IPAddress $using:machine }
    Start-Sleep -Seconds 30
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { Restart-Service -Name DHCPServer -Force } 
}

function nat ($machine, $name) {
    Install-WindowsFeature -ConfigurationFilePath G:\lab-deployer\configs\NAT_Deployment.xml -ComputerName $machine -Credential $creds

    # Find the correct NIC to do the nat things
    $nat_i = Get-VMNetworkAdapter -VMName $name
    foreach ($adapter in $nat_i) {
        $mac_addr = ""
        $y = 0
        foreach ($x in 0..5) {
            $mac_addr += $adapter.MacAddress.substring($y, 2) + ":"
            $y+=2
        }
        $mac_addr = $mac_addr.Substring(0, ($mac_addr.Length -1))
        if ($adapter.SwitchName -eq "NAT") {
            $nat_adapter = Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { Get-WmiObject win32_networkadapter | select netconnectionid, name, macaddress, description | ?{$_.macaddress -eq $($using:mac_addr)} } 
        } else {
            $private_adapter = Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { Get-WmiObject win32_networkadapter | select netconnectionid, name, macaddress, description | ?{$_.macaddress -eq $($using:mac_addr)} } 
        }
    }
    
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock {  Set-Service -Name RemoteAccess -StartupType Automatic }
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock {  Start-Service -Name RemoteAccess }
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock {  netsh routing ip nat install }
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock {  netsh routing ip nat add interface $($using:nat_adapter.netconnectionid) }
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock {  netsh routing ip nat set interface $($using:nat_adapter.netconnectionid) mode=full }
    Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock {  netsh routing ip nat add interface $($using:private_adapter.netconnectionid) private }
}

function smb ($machine) {
    $ses = New-PSSession -ComputerName $machine -Credential $creds
    Invoke-Command -Session $ses -ScriptBlock { New-Item "C:\shared\" -ItemType Directory }
    $department_list = import-csv $dir\..\..\configs\users.csv | % {$_.department} | select-object -Unique
    Invoke-Command -Session $ses -ScriptBlock { Import-module SmbShare }
    foreach ($dep in $department_list) {
        $acl = @()
        foreach ($entry in import-csv $dir\..\..\configs\users.csv) {
            if ($entry.department -eq $dep -and "$dep@$($entry.domain)" -notin $acl) { $acl += "$dep@$($entry.domain)" }
        }

        Invoke-Command -Session $ses -ScriptBlock { New-Item "C:\shared\$using:dep" -ItemType Directory }
        Invoke-Command -Session $ses -ScriptBlock { New-SmbShare -Name $using:dep -Path "C:\shared\$using:dep" -FullAccess $using:acl -Description "$using:dep folders and files" }

    }
    & $dir\create_content.ps1 -smb $machine -PassWord Hyper-v_exchange?

}

[array]$z = @()

foreach ($vm in $xml.labs.$LabName.ChildNodes) {
    if($vm.Type -eq "Server") {
        $vm_info = Get-VMNetworkAdapter -VMName $vm.Name | Select IPAddresses, SwitchName
        if ($vm.Programs -like "*IIS*") {   
            $ip_addr = $vm_info.IPAddresses[0]
            $z += "$($vm.Name).com,$ip_addr" 
        }
        if ($vm.Programs -like "*NAT*") {
            foreach ($interface in $vm_info) {
                if ($interface.SwitchName -eq $LabName) { $nat_ip = $interface.IpAddresses[0] }
                
            }
        }
    }
}



foreach ($vm in $xml.labs.$LabName.ChildNodes) {
    if ($vm.Type -eq "Server") {
        $vm_info = Get-VMNetworkAdapter -VMName $vm.Name | Select IPAddresses, SwitchName, VMName
        #$vm_info.GetType().BaseType.Name
        
        # Check if type is array e.g if it has multiple ip's
        if ($vm_info.GetType().BaseType.Name -match [Array]) {
            foreach ($interface in $vm_info) {
                if ($interface.SwitchName -eq $LabName) { $vm_info = $interface }
            }
        }

        $programs = $vm.Programs.Split(",") 
        foreach ($program in $programs) {
            switch ($program) {
                "IIS" { iis $vm_info.IPAddresses[0] }
                "DNS" { dns $vm_info.IPAddresses[0] $z }
                "DHCP" { dhcp $vm_info.IPAddresses[0] $ip $nat_ip $vm_info.VMName}
                "NAT" { nat $vm_info.IPAddresses[0] $vm.Name }
                "SMB" { smb $vm_info.IPAddresses[0] }
            }
        }
    }
}