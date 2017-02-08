param([String]$LabName, [String]$PassWord, [string]$DhcpServer, [int32]$ClientCount)

$pass = $PassWord
$password = $pass
$total_leases = @{"Count" = 0}
$provisioned_clients = @()

$dir = Split-Path $scriptpath
[xml]$xml = Get-Content -Path "$dir\..\..\configs\labs_config.xml"

$root_domain = ($xml.labs.$LabName.domain).split(".")[0] 
$sub_domain1 = $xml.labs.$LabName.subdomain1
$sub_domain2 = $xml.Labs.$LabName.subdomain2

$pass = ConvertTo-SecureString -String $pass -AsPlainText -force
$new_client_creds = New-Object -TypeName System.Management.Automation.PSCredential "lab",$pass
$creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$pass
$root_domain_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator@$root_domain",$pass
$sub_domain1_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator@$sub_domain1",$pass
$sub_domain2_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator@$sub_domain2",$pass

$key_locker = @{$root_domain = $root_domain_creds; $sub_domain1 = $sub_domain1_creds; $sub_domain2 = $sub_domain2_creds}

Start-Sleep -s 10

$pass = "Hyper-v_test"
$pass = ConvertTo-SecureString -String $pass -AsPlainText -force
$client_creds = New-Object -TypeName System.Management.Automation.PSCredential "lab",$pass

$scriptpath = $MyInvocation.MyCommand.Path

$client_count = $ClientCount
$client_list = @()


Start-Sleep -s 10

function build_script ($vm_name, $os, $domain) {
    if ($os -eq "windows7") {
        $rename = "(Get-WmiObject Win32_ComputerSystem).Rename('$vm_name') ; Restart-Computer -Force"
    } else {
        $rename = "Rename-Computer -NewName `"$vm_name`" -Restart -Force"
    }
    "Remove-Item C:\$os-unattend.xml"
    "net user lab `"$password`""
    $rename
    return
}

$dhcp_ses = New-PSSession -ComputerName $DhcpServer -Credential $key_locker[$root_domain]
$scope = $xml.Labs.$labName.IP

foreach ($vm in $xml.labs.$LabName.ChildNodes) {
    if ($vm.Type -eq "Client") {
        Start-VM -Name $vm.Name
    }
}

#Start-Sleep -s 120

"Initiating clients, waiting till they all get a DHCP lease"
while ($total_leases.Count -lt $client_count) {
    $dhcp_leases = Invoke-Command -Session $dhcp_ses -ScriptBlock { Get-DhcpServerv4Lease -ScopeID $using:scope }
    $total_leases = $dhcp_leases | measure 
    #foreach ($dhcp_lease in $dhcp_leases ) { $dhcp_lease; $c ++ }
    Start-Sleep -s 30
}





foreach ($vm in $xml.labs.$LabName.ChildNodes) {
    if ($vm.Type -eq "Client") {
        $vm_info = Get-VMNetworkAdapter -VMName $vm.Name
        foreach ($dhcp_lease in $dhcp_leases ) {
            if ($dhcp_lease.ClientId.Replace("-", "").toUpper() -eq $vm_info.MacAddress) {
                $client_list += "$($vm.Name),$($dhcp_lease.IPAddress),$($vm.OS),$($vm.Domain)"
            }
        }
    }
}

foreach ($client in $client_list) {
    $name, $ip, $os, $domain = $client.split(",")
    "$name with ip $ip now initializing on domain $domain"
    build_script $name $os $domain | Out-File $dir\..\..\tmp\server_init_scripts\$name.ps1
    Invoke-Command -ComputerName $ip -Credential $client_creds -FilePath $dir\..\..\tmp\server_init_scripts\$name.ps1
    Start-Sleep -s 300
    $cred = $key_locker[$domain]
    Invoke-Command -ComputerName $ip -Credential $new_client_creds -ScriptBlock { Add-Computer -DomainName $using:domain -Credential $using:cred }
    Invoke-Command -ComputerName $ip -Credential $new_client_creds -ScriptBlock { Restart-Computer -Force }

}

while ($provisioned_clients.Count -lt $ClientCount) {
    Start-Sleep -s 20
    foreach ($client in $client_list) {
        $name, $ip, $os = $client.split(",")
        $computer_name = Invoke-Command -ComputerName $ip -Credential $new_client_creds -ScriptBlock { $env:COMPUTERNAME }
        if ($computer_name -eq $name -and $provisioned_clients -notcontains $computer_name) {
            "$computer_name provisioned succesfully"
            $provisioned_clients += $computer_name
        }
    }
}

    

Remove-PSSession -Session $dhcp_ses