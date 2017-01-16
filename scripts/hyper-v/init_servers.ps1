param([String]$LabName="lab1", [String]$Password="nBHsvR<w>VDYa#W){4P+")

$lab_id = $LabName
$password = $Password

$pass = ConvertTo-SecureString -String "Hyper-v_vergelijken" -AsPlainText -force
$server_creds = New-Object -TypeName System.Management.Automation.PSCredential "NICE\administrator",$pass
$creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$pass
$new_pass = ConvertTo-SecureString -String $PassWord -AsPlainText -force
$new_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$new_pass
[hashtable]$servers = @{}
[array]$servers_provisioned = @()
[array]$servers_done = @()
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
[xml]$xml = Get-Content -Path "$dir\..\..\tmp\lab_config.xml"
$c = 0
$to = 0
$server_count = 0


function build_script ($vm_name, $ip, $dns) {
    "New-NetIPAddress -interfaceAlias `"Ethernet`" -IPAddress $ip -PrefixLength 16"
    "Set-DnsClientServerAddress -InterfaceAlias `"Ethernet`" -ServerAddresses $dns, 8.8.8.8"
    "Remove-Item C:\unattend.xml"
    "net user administrator `"$password`""
    "Rename-Computer -NewName `"$vm_name`" -Force -Restart"

    return
}


function init_server {

    foreach ($vm in $servers.Keys) {
        $vm_info = Get-VMNetworkAdapter -VMName $vm | Select VMName, IPAddresses
        $ip_addr = $servers.$($vm).'IP'

        if ($vm_info.IPAddresses[0] -notlike "10.0.*" -and $vm_info.IPAddresses[0] -like "169.254.*" -and $script:servers_provisioned -notcontains $vm) {
             Invoke-Command -ComputerName $vm_info.IPAddresses[0] -AsJob -Credential $creds -FilePath $dir\..\..\tmp\server_init_scripts\$vm.ps1
             $script:servers_provisioned += $vm
        }
    }

}


foreach ($lab in $xml.labs.ChildNodes) {
    if ($lab.'Name' -eq $lab_id) {
        [string]$ip = $($lab.'IP').split(".")[0,1,2] -join "."
        [string]$dns = $($lab.'DNS')
        $i = 2

        foreach ($machine in $lab.ChildNodes) {
            $servers.Add($machine.Name, @{})
            #$programs = $machine.Programs.Split(",")
            build_script $machine.Name "$ip.$i" $dns | Out-File $dir\..\..\tmp\server_init_scripts\$($machine.Name).ps1
            $servers.$($machine.Name).Add("Programs", $programs)
            $servers.$($machine.Name).Add("IP", $ip+"."+$i)
            $i ++
            $server_count ++
        }
    }
}

New-Item "$dir\..\..\disks\$lab_id" -type directory

foreach ($vm in $servers.Keys) {
    New-VHD -Differencing -Path "$dir\..\..\disks\$lab_id\$vm.vhdx" -ParentPath "G:\RAW_disks\2012-R2-RAW.vhdx"
    New-VM -Name "$vm" -MemoryStartupBytes 1024MB -VHDPath "$dir\..\..\disks\$lab_id\$vm.vhdx" -SwitchName "LAB" -Generation 2
    Start-VM -Name "$vm"
}

"`n`n Building VM's Done, now provisioing them `n`n"

while ($servers_provisioned.Count -lt $server_count) {
    Start-Sleep -s 10
    Write-Host -NoNewline "."
    init_server
}

"`n`n Systems all received scripts, testing if they execute succesfully `n`n"

$servers_provisioned = @()
while ($servers_done.Count -lt $server_count) {

    Start-Sleep -s 20
    Write-Host -NoNewline "."

    foreach ($vm in $servers.Keys) {
        $vm_info = Get-VMNetworkAdapter -VMName $vm | Select VMName, IPAddresses
        $ip_addr = $servers.$($vm).'IP'
        if ($vm_info.IPAddresses[0] -like "10.0.*" -and $servers_done -notcontains $vm) {
            $new_name = Invoke-Command -ComputerName $vm_info.IPAddresses[0] -Credential $new_creds -ScriptBlock {$env:COMPUTERNAME}
            if($new_name -eq $($vm.ToUpper())) {
                $servers_done += $vm
                $servers_provisioned += $vm
                "$new_name completed initialization"
                Remove-Item G:\lab-deployer\tmp\server_init_scripts\$vm.ps1

            }
        }
    }

    $c++
    if ($c -eq 25) {
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
"Server initialization done, now installing software and features"

.\install_features.ps1 -LabName $LabName -PassWord $Password