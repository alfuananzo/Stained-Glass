param([String]$LabName="t2", [String]$PassWord="Hyper-v_installthings", [String]$MachineName)

$pass = $PassWord
$pass = ConvertTo-SecureString -String $pass -AsPlainText -force
$creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$pass
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
[xml]$xml = Get-Content -Path "$dir\..\..\tmp\lab_config.xml"

function iis ($machine) {
    Install-WindowsFeature -ConfigurationFilePath G:\lab-deployer\configs\IIS_Deployment.xml -ComputerName $machine -Credential $creds
}


function dns ($machine, $zones) {

    Install-WindowsFeature -ConfigurationFilePath G:\lab-deployer\configs\DNS_Deployment.xml -ComputerName $machine -Credential $creds

    foreach ($zone in $zones) {
        $zone = $zone.Split(",")

        Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { $newzone = ([WMIClass]"\\$env:COMPUTERNAME\root\MicrosoftDNS:MicrosoftDNS_Zone").CreateZone($using:zone[0], 0, $False, $Null, $Null, $Null) }
        Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { $newa = [WMIClass]"\\$env:COMPUTERNAME\root\MicrosoftDNS:MicrosoftDNS_AType" ; $newar = $newa.CreateInstanceFromPropertyData($env:COMPUTERNAME, $using:zone[0], $using:zone[0], $Null, $Null, $using:zone[1] ) }
        Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { $newa = [WMIClass]"\\$env:COMPUTERNAME\root\MicrosoftDNS:MicrosoftDNS_AType" ; $newar = $newa.CreateInstanceFromPropertyData($env:COMPUTERNAME, $using:zone[0], "www.$($using:zone[0])", $Null, $Null, $using:zone[1] ) }
    }
}

[array]$z = @()

foreach ($lab in $xml.labs.ChildNodes) {

    if($lab.Name -eq $LabName) {
        foreach ($vm in $lab.ChildNodes) {
            if ($vm.Programs -like "*IIS*") {
                $vm_info = Get-VMNetworkAdapter -VMName $vm.Name | Select IPAddresses
                $ip_addr = $vm_info.IPAddresses[0]
                $z += "$($vm.Name).com,$ip_addr"
            }
        }
    }
}

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
[xml]$xml = Get-Content -Path "$dir\..\..\tmp\lab_config.xml"

foreach ($lab in $xml.labs.ChildNodes) {
    if($lab.Name -eq $LabName) {
        foreach ($vm in $lab.ChildNodes) {
            $vm_info = Get-VMNetworkAdapter -VMName $vm.Name | Select IPAddresses
            $programs = $vm.Programs.Split(",") 
            foreach ($program in $programs) {
                switch ($program) {
                    "IIS" { iis $vm_info.IPAddresses[0] }
                    "DNS" { dns $vm_info.IPAddresses[0] $z }
                }
            } 
        }
    } 
}
