param([String]$LabName, [String]$PassWord, [String]$MachineName)

$pass = $PassWord
$pass = ConvertTo-SecureString -String "Hyper-v_time" -AsPlainText -force
$creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$pass

function iis ($machine) {
    Install-WindowsFeature -ConfigurationFilePath G:\lab-deployer\configs\IIS_Deployment.xml -ComputerName $machine -Credential $creds
}

function dns ($machine, $zones) {

    Install-WindowsFeature -ConfigurationFilePath G:\lab-deployer\configs\DNS_Deployment.xml -ComputerName $machine -Credential $creds

    foreach ($zone in $zones) {
        Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { $newzone = ([WMIClass]"\\$env:COMPUTERNAME\root\MicrosoftDNS:MicrosoftDNS_Zone").CreateZone($using:zone[0], 0, $False, $Null, $Null, $Null) }
        Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { $newa = [WMIClass]"\\$env:COMPUTERNAME\root\MicrosoftDNS:MicrosoftDNS_AType" ; $newar = $newa.CreateInstanceFromPropertyData($env:COMPUTERNAME, $using:zone[0], $using:zone[0], $Null, $Null, $using:zone[1] ) }
        Invoke-Command -ComputerName $machine -Credential $creds -ScriptBlock { $newa = [WMIClass]"\\$env:COMPUTERNAME\root\MicrosoftDNS:MicrosoftDNS_AType" ; $newar = $newa.CreateInstanceFromPropertyData($env:COMPUTERNAME, $using:zone[0], "www.$($using:zone[0])", $Null, $Null, $using:zone[1] ) }
    }
}

#dns "10.0.0.2" $z

#iis "10.0.0.3"