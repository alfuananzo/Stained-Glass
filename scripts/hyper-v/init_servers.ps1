param([String]$LabName, [String]$Password, $UnattendPassword)
$lab_id = $LabName
$password = $Password

$start_time = Get-Date

$pass = ConvertTo-SecureString -String $UnattendPassword -AsPlainText -force
$creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$pass
$new_pass = ConvertTo-SecureString -String $PassWord -AsPlainText -force
$new_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$new_pass
[hashtable]$servers = @{}
[hashtable]$clients = @{}
[array]$servers_provisioned = @()
[array]$servers_done = @()

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
[xml]$xml = Get-Content -Path "$dir\..\..\configs\labs_config.xml"
$c = 0
$to = 0
$server_count = 0
$client_count = 0

function build_script ($vm_name, $ip, $dns) {
    "New-NetIPAddress -interfaceAlias `"Ethernet`" -IPAddress $($ip[0]) -PrefixLength 24"
    if ($xml.labs.$LabName.$vm_name.Programs -like "*NAT*") {
        "New-NetIPAddress -interfaceAlias `"Ethernet 2`" -IPAddress $($ip[1]) -PrefixLength 24 -DefaultGateway 192.168.138.1"
    }

    "Set-DnsClientServerAddress -InterfaceAlias `"Ethernet`" -ServerAddresses $dns, 8.8.8.8"
    "Remove-Item C:\unattend.xml"
    "net user administrator `"$password`""
    "Rename-Computer -NewName `"$vm_name`" -Force -Restart"

    return
}


function init_server {
    $script:servers_provisioned
    foreach ($vm in $script:servers.Keys) {
        $vm_info = Get-VMNetworkAdapter -VMName $vm

            Try {
                if ($vm_info.IPAddresses[0] -notlike "10.0.*" -and $vm_info.IPAddresses[0] -like "169.254.*" -and $script:servers_provisioned -notcontains $vm) {
                    $ip_addr = "$ip.$script:i"
                    if ($script:servers.$vm.Programs -like "*NAT*") {
                        "Provisioning nat server"
                        $adapters = @{}
                        
                        foreach ($adapter in $vm_info) {
                                $mac_addr = ""
                                $y = 0
                                foreach ($x in 0..5) {
                                    $mac_addr += $adapter.MacAddress.substring($y, 2) + ":"
                                    $y+=2
                                }
                                $mac_addr = $mac_addr.Substring(0, ($mac_addr.Length -1))

                                $adapters.Add($adapter.SwitchName, $mac_addr)
                                if ($adapter.SwitchName -eq $LabName) { $vm_ip = $adapter.IpAddresses[0] }
                       }
                       $lab_ip = $adapters.$LabName
                              
                       Invoke-Command -ComputerName $vm_ip -Credential $creds { Get-WmiObject win32_networkadapterconfiguration | ?{$_.macaddress -eq $($using:adapters.'NAT')} | New-NetIPAddress -IPAddress $using:nat_ip -PrefixLength 24 -DefaultGateway 192.168.138.1 }
                       Invoke-Command -ComputerName $vm_ip -Credential $creds { Get-WmiObject win32_networkadapterconfiguration | ?{$_.macaddress -eq $using:lab_ip} | New-NetIPAddress -IPAddress $using:nat_inside_ip -PrefixLength 24 }  -ErrorAction Stop
                       $ip_addr = $nat_inside_ip          
                    } else {
                        Invoke-Command -ComputerName $vm_info.IPAddresses[0] -Credential $creds -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress $using:ip_addr -PrefixLength 24 -DefaultGateway $using:nat_inside_ip } -ErrorAction Stop
                    }
                    #$script:servers.$vm.Programs
                    #$ses = New-PSSession -ComputerName $interface.IPAddresses[0] -Credential $creds -ErrorAction Stop
                    #Invoke-Command -Session $ses -ScriptBlock { New-NetIPAddress -interfaceAlias "Ethernet" -IPAddress "$using:ip_addr" -PrefixLength 24 } -ErrorAction Stop
                    Start-Sleep -s 5
                    Invoke-Command -ComputerName $ip_addr -Credential $creds { Rename-Computer -NewName $using:vm ; net user administrator $using:PassWord ; Restart-Computer -Force }
                    #Remove-PSSession $ses
                    $script:i += 1
                    $script:servers_provisioned += $vm

                    
                }
            } catch {
                "Couldnt connect to $vm"
            }
                    #Invoke-Command -ComputerName $interface.IPAddresses[0] -AsJob -Credential $creds -FilePath $dir\..\..\tmp\server_init_scripts\$vm.ps1
                    #$script:servers_provisioned += $vm
                          
    }
}

[string]$ip = $($xml.labs.$LabName.'IP').split(".")[0,1,2] -join "."
[string]$apipa_ip = $($xml.labs.$LabName.'IP').split(".")[2]
$nat_ip = $($xml.labs.$LabName.'IP').split(".")[2]
$nat_ip = "192.168.138.$nat_ip"
[string]$dns = $($xml.labs.$LabName.'DNS')
$apipa_ip = "169.254.$apipa_ip.1"
$i = 3

foreach ($machine in $xml.labs.$LabName.ChildNodes) {
    if ($machine.Type -eq "Server") {     
        $servers.Add($machine.Name, @{})
        if ($machine.Programs -like "*NAT*") {
            $x = $ip.split(".")[-1]
            build_script $machine.Name @("$ip.$i", "192.168.138.$x") $dns | Out-File $dir\..\..\tmp\server_init_scripts\$($machine.Name).ps1
        } else {
            build_script $machine.Name @("$ip.$i") $dns | Out-File $dir\..\..\tmp\server_init_scripts\$($machine.Name).ps1
        }

        if ($machine.Programs -like "*Exchange*") {
            $servers.$($machine.Name).Add("ram", 4GB)
        } else {
            $servers.$($machine.Name).Add("ram", 1GB)
        }

        $servers.$($machine.Name).Add("IP", $ip+"."+$i)
        $servers.$($machine.Name).Add("OS", $machine.OS)
        $servers.$($machine.Name).Add("Programs", $machine.Programs)
        #$i++
        $server_count++
    } else {
        $clients.Add($machine.Name, @{})
        $clients.$($machine.Name).Add("OS", $machine.OS)
        $clients.$($machine.Name).Add("Programs", $machine.Programs)
        $client_count++
    }
}


"`n`n Building VM's `n`n"

New-Item "$dir\..\..\disks\$lab_id" -type directory
New-VMSwitch -Name $LabName -SwitchType Internal -Notes "Switch for lab $LabName"
$a = New-NetIPAddress -interfaceAlias "vEthernet ($LabName)" -IPAddress $apipa_ip -PrefixLength 16
$a.IPv4Address
$a = New-NetIPAddress -interfaceAlias "vEthernet ($LabName)" -IPAddress "$($ip).1" -PrefixLength 24
$nat_inside_ip = "$ip.2"



foreach ($vm in $servers.Keys) {
    $vhd = New-VHD -Differencing -Path "$dir\..\..\disks\$lab_id\$vm.vhdx" -ParentPath "$dir\..\..\disks\raw_disks\$($servers.$vm.OS).vhdx"

    $vm_output = New-VM -Name "$vm" -MemoryStartupBytes $servers.$vm.ram -VHDPath "$dir\..\..\disks\$lab_id\$vm.vhdx" -SwitchName $LabName -Generation 2

    if ($xml.labs.$LabName.$vm.Programs -like "*NAT*") {
        Add-VMNetworkAdapter -VMName $vm -SwitchName "NAT"
    }
    if ($xml.labs.$LabName.$vm.Programs -like "*Exchange*") {
        Add-VMDvdDrive -VMName $vm
    }
    $start_output = Start-VM -Name "$vm"
    $start_output.Name + " now starting"
}

Start-Sleep -s 600

foreach ($vm in $clients.Keys) {
    if ($($clients.$vm.OS) -eq "windows7") {
        $g = 1
    } else {
        $g = 2
    }
    
    New-VHD -Differencing -Path "$dir\..\..\disks\$lab_id\$vm.vhdx" -ParentPath "$dir\..\..\disks\library\$($clients.$vm.OS).vhdx"
    New-VM -Name "$vm" -MemoryStartupBytes 1024MB -VHDPath "$dir\..\..\disks\$lab_id\$vm.vhdx" -SwitchName $LabName -Generation $g
    Start-VM -Name "$vm"
}


"`n`n Building VM's Done, now provisioing them `n`n"

while ($servers_provisioned.Count -lt $server_count) {
   Start-Sleep -s 20
    Write-Host -NoNewline "."
    init_server
}

"`n`n Systems all received scripts, testing if they execute succesfully `n`n"

$servers_provisioned = @()
while ($servers_done.Count -lt $server_count) {

    Start-Sleep -s 60
    Write-Host -NoNewline "."

    foreach ($vm in $servers.Keys) {
        $vm_info = Get-VMNetworkAdapter -VMName $vm
        $ip_addr = $servers.$($vm).'IP'
        foreach ($interface in $vm_info) {
            if ($interface.SwitchName -eq $LabName) { $vm_info = $interface }
        }
        if ($vm_info.IPAddresses[0] -like "10.0.*" -and $servers_done -notcontains $vm) {
            
            try {
                $new_name = Invoke-Command -ComputerName $vm_info.IPAddresses[0] -Credential $new_creds -ScriptBlock {$env:COMPUTERNAME} -ErrorAction Stop
            } catch {
                continue
            }
            
            if($new_name -eq $($vm.ToUpper())) {
                $servers_done += $vm
                $servers_provisioned += $vm
                "`n$new_name completed initialization"
                Remove-Item G:\lab-deployer\tmp\server_init_scripts\$vm.ps1

            }
        }
    }

    $c++
    if ($c -eq 25) {
        $servers_provisioned = @()
        "Timeout reached, reprovisioning faulty servers"
        init_server
        $to++
        $c = 0
        if ($to -eq 5) {
            "Reinits not resolving problems, fix errors manually for the following servers or restart provisioning"

            $vm_list = get-vm | ?{$_.ReplicationMode -ne "Replica"} | Select -ExpandProperty NetworkAdapters | select VMName, IPAddresses
            foreach ($vm in $vm_list) {
                if ($servers_done -notcontains $vm.VMName) {
                    $vm.VMName
                }
            }
        }
    }
}

# Done with server initialisation, cleaning up
"Server initialization done, now instaling DC's this may take a while...`n`n`n"
$dc_list = @{}
#Build up DC list
foreach ($vm in $servers.Keys) {
    if ($servers.$vm.Programs -like "*DC*" -or $servers.$vm.Programs -like "*Exchange*") {
        $programs = $servers.$vm.Programs.split(",")
        foreach ($program in $programs) {
            if ($program -like "*DC*") {
                $dc = $program.split(";")
                $dc_ip = (Get-VMNetworkAdapter -VMName $vm | select IPAddresses).IpAddresses[0]
                $dc_list.Add($dc[1], $dc_ip)
            } elseif ($program -like "*Exchange*") {
                $exchange = $vm
                $exchange_ip = (Get-VMNetworkAdapter -VMName $vm | select IPAddresses).IpAddresses[0]
            }

            if ($program -like "*DNS*") {
                $dns_ip = @((Get-VMNetworkAdapter -VMName $vm | select IPAddresses).IpAddresses[0])
            }

            if ($program -like "*SMB*") {
                $smb_ip = (Get-VMNetworkAdapter -VMName $vm | select IPAddresses).IpAddresses[0]
            }

            if ($program -like "*NAT*") {
                $nat = $vm
            }
        }
    }
}


& $dir\install_dc.ps1 -DC1 $dc_list."1" -DC2 $dc_list."2" -DC3 $dc_list."3" -DC4 $dc_list."4" -DC5 $dc_list."5" -password $PassWord -domain1 demo.com -subdomain1 mark -subdomain2 marc -nat $nat

"Waiting for all servers remoting to come up"
$ses = $False
while (-not $ses) {
    try {
        $ses = New-PSSession -ComputerName $dc_list."5" -Credential $new_creds -ErrorAction stop
        Remove-PSSession $ses
        $ses = $True
    } catch {
        $ses = $False
        Start-Sleep -s 30
    }
}

Invoke-Command -ComputerName $dc_list."1" -Credential $new_creds -ScriptBlock { Stop-Computer -Force }
Invoke-Command -ComputerName $dc_list."2" -Credential $new_creds -ScriptBlock { Stop-Computer -Force }
Invoke-Command -ComputerName $dc_list."3" -Credential $new_creds -ScriptBlock { Stop-Computer -Force }
Invoke-Command -ComputerName $dc_list."4" -Credential $new_creds -ScriptBlock { Stop-Computer -Force }
Invoke-Command -ComputerName $dc_list."5" -Credential $new_creds -ScriptBlock { Stop-Computer -Force }

Start-Sleep -s 300

foreach ($x in 1..6){
    foreach ($vm in $servers.Keys) {
        if ($servers.$vm.Programs -like "*DC*") {
            $programs = $servers.$vm.Programs.split(",")
            foreach ($program in $programs) {
                if ($program -like "*DC*") {
                    $dc = $program.split(";")
                    if ($dc[1] -eq $x) {Start-VM $vm ; Start-Sleep -s 120 }
                }
            }
        }
    }
}

"Waiting for DC's to come back up"
$ses = $False
while (-not $ses) {
    try {
        $ses = New-PSSession -ComputerName $dc_list."5" -Credential $new_creds -ErrorAction stop
        Remove-PSSession $ses
        $ses = $True
    } catch {
        $ses = $False
        Start-Sleep -s 30
    }
}

$domain = $xml.labs.$LabName.domain
$subdomain1 = $xml.labs.$LabName.subdomain1
$subdomain2 = $xml.labs.$LabName.subdomain2

& $dir\add_users.ps1 -DC1 $dc_list."1" -DC2 $dc_list."2" -DC4 $dc_list."4" -password $PassWord -domain1 $domain -subdomain1 $subdomain1 -subdomain2 $subdomain2 -smb $smb_ip

& $dir\install_exchange.ps1 -DC1 $dc_list."1" -MAIL1 $exchange -domain1 demo.com -password $PassWord

& $dir\install_features.ps1 -LabName $LabName -PassWord $Password -dns $dns_ip -dc1 $dc_list."1"

# Servers are fully operational, now doing client things
"Servers fully operational, provisioning clients"

foreach ($server in $servers.Keys) {
    if ($servers.$server.Programs -like "*dhcp*") {
        $vm_info = Get-VMNetworkAdapter -VMName $server | select IPAddresses
        foreach ($ip in $vm_info.IPAddresses) {
            if ($ip -like "10.0.*") {
                $dhcp_server = $ip
            }
        }
    }
}

& $dir\init_clients.ps1 -LabName $LabName -PassWord $Password -DhcpServer $dhcp_server -ClientCount $client_count
#
#"All cliensts initialized, moving on to installing client software"
#
& $dir\install_programs.ps1 -LabName $LabName -PassWord $Password -ClientCount $client_count

Start-sleep -s 30

& $dir\stain_systems.ps1 -LabName $LabName -PassWord $Password -exchange $exchange_ip

$end_time = Get-Date

"Starting time"
$start_time

"Ending time"
$end_time
