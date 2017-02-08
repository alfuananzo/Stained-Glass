param($DC1, $DC2, $DC3, $DC4, $DC5, $domain1, $subdomain1, $subdomain2, $password, $nat)

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
[xml]$xml = Get-Content -Path "$dir\..\..\configs\labs_config.xml"

$domain2 = "$subdomain1.$domain1"
$domain3 = "$subdomain2.$domain1"
$netname = $domain1.split(".")[0]

### credentials
$pass = ConvertTo-SecureString -String $password -AsPlainText -force

$SafeModeAdministratorPassword = $pass
$creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$pass
$creds2 = New-Object System.Management.Automation.PSCredential "administrator@$domain1",$pass
$creds3 = New-Object System.Management.Automation.PSCredential "administrator@$domain2",$pass
$creds4 = New-Object System.Management.Automation.PSCredential "administrator@$domain3",$pass

#$pass2t = "Welkom12345"
#$pass2 = ConvertTo-SecureString -String $pass2t -AsPlainText -force
#$tcreds = New-Object System.Management.Automation.PSCredential "administrator",$pass2

$nat_i = Get-VMNetworkAdapter -VMName $nat

foreach ($adapter in $nat_i) {
    if ($adapter.IpAddresses[0] -like "10.0.*") {
        $nat_ip = $adapter.IpAddresses[0]
    }
}

# Setup Primary DNS server name
function set_dns($DC, $root_dc, $second_dc) {
    if ($DC -ne $nat_ip) {
        Invoke-Command -ComputerName $DC -Credential $creds -ScriptBlock { Set-DNSClientServerAddress –interfaceIndex 12 –ServerAddresses ($using:root_dc,$using:second_dc) }
    } else {                  
        foreach ($adapter in $nat_i) {
            if ($adapter.SwitchName -ne "NAT") {
                $mac_addr = ""
                $y = 0
                foreach ($x in 0..5) {
                    $mac_addr += $adapter.MacAddress.substring($y, 2) + ":"
                    $y+=2
                }
                $mac_addr = $mac_addr.Substring(0, ($mac_addr.Length -1))
               
                Invoke-Command -ComputerName $DC -Credential $creds -ScriptBlock { Get-WmiObject win32_networkadapterconfiguration | ?{$_.macaddress -eq $($using:mac_addr)} | Set-DNSClientServerAddress –ServerAddresses ($using:root_dc,$using:second_dc) }
            }
        }        
    }
}

set_dns $DC2 $DC1 "127.0.0.1"
set_dns $DC3 $DC1 $DC2
set_dns $DC4 $DC1 "127.0.0.1"
set_dns $DC5 $DC1 $DC4


Install-WindowsFeature -name AD-Domain-Services -IncludeManagementTools -ComputerName $DC1 -Credential $creds
Restart-Computer "$DC1" -Credential $creds -Force

Write-Host "Installing DC1"
start-sleep -s 100

# Install root domain
Invoke-Command -ComputerName $DC1 -Credential $creds -ScriptBlock {
Import-Module ADDSDeployment
Install-ADDSForest `
-CreateDnsDelegation:$false `
-DatabasePath "C:\Windows\NTDS" `
-DomainMode "Win2012R2" `
-DomainName $using:domain1 `
-DomainNetbiosName $using:netname `
-ForestMode "Win2012R2" `
-InstallDns:$true `
-LogPath "C:\Windows\NTDS" `
-NoRebootOnCompletion:$false `
-SysvolPath "C:\Windows\SYSVOL" `
-Force:$true `
-SafeModeAdministratorPassword ($using:SafeModeAdministratorPassword)
}

Start-Sleep -s 300
Restart-Computer $DC1 -Credential $creds2 -Force
Start-Sleep -s 200



#Set AD replication interval to 15 mins
Invoke-Command -ComputerName $DC1 -Credential $creds -ScriptBlock {
Get-ADObject -Filter 'objectClass -eq "siteLink"' -SearchBase (Get-ADRootDSE).ConfigurationNamingContext | Set-ADObject -Replace @{ReplInterval=15;Schedule=1}
}


#Install DC2
Write-Host "Installing DC2, waiting for replication"
Install-WindowsFeature -name AD-Domain-Services -IncludeManagementTools -ComputerName $DC2 -Credential $creds
Restart-Computer $DC2 -Credential $creds -Force
start-sleep -s 900

Invoke-Command -ComputerName $DC2 -Credential $creds -ScriptBlock {
Import-Module ADDSDeployment
Install-ADDSDomain `
-NoGlobalCatalog:$false `
-CreateDnsDelegation:$true `
-Credential ($using:creds2) `
-DatabasePath "C:\Windows\NTDS" `
-DomainMode "Win2012R2" `
-DomainType "ChildDomain" `
-InstallDns:$true `
-LogPath "C:\Windows\NTDS" `
-NewDomainName $using:subdomain1 `
-NewDomainNetbiosName $using:subdomain1 `
-ParentDomainName $using:domain1 `
-NoRebootOnCompletion:$false `
-SiteName "default-first-site-name" `
-SysvolPath "C:\Windows\SYSVOL" `
-Force:$true `
-SafeModeAdministratorPassword ($using:SafeModeAdministratorPassword)
}
start-sleep -s 300
Restart-Computer $DC2 -Credential $creds3 -Force
start-sleep -s 100



# Een DNS record wordt aangemaakt voor subdomain
Invoke-Command -ComputerName $DC1 -Credential $creds2 -ScriptBlock {
Add-DnsServerStubZone -Name $using:domain2 -MasterServers $using:DC2 -PassThru -ReplicationScope "Forest"
}

Invoke-Command -ComputerName $DC3 -Credential $creds -ScriptBlock {
ipconfig /flushdns
}
$pin = "Welkom12345"
#change admin password and restart client
Invoke-Command -ComputerName $DC3 -Credential $creds -ScriptBlock {
net user administrator $using:pin
}
Start-Sleep -s 10
Restart-Computer $DC3 -Credential ( New-Object System.Management.Automation.PSCredential "administrator", (ConvertTo-SecureString 'Welkom12345' -AsPlainText -Force))
start-Sleep -s 100


# join domain
Invoke-Command -ComputerName $DC3 -Credential ( New-Object System.Management.Automation.PSCredential "administrator", (ConvertTo-SecureString 'Welkom12345' -AsPlainText -Force)) -ScriptBlock {
$domain = $using:domain2
$username = "$domain\administrator" 
$credential = New-Object System.Management.Automation.PSCredential($username,$using:pass)
Add-Computer -DomainName $domain -Credential $credential
}
Start-Sleep -s 10
Restart-Computer $DC3 -Credential ( New-Object System.Management.Automation.PSCredential "administrator", (ConvertTo-SecureString 'Welkom12345' -AsPlainText -Force))

Start-Sleep -s 100

# Install DC-3
Write-Host "Installing DC3, waiting for replication"
#Install-WindowsFeature -name AD-Domain-Services -IncludeManagementTools -ComputerName $DC3 -Credential ( New-Object System.Management.Automation.PSCredential "administrator", (ConvertTo-SecureString 'Welkom12345' -AsPlainText -Force))
Install-WindowsFeature -name AD-Domain-Services -IncludeManagementTools -ComputerName $DC3 -Credential $creds3
Restart-Computer $DC3 -Credential $creds3 -Force
start-sleep -s 900



Invoke-Command -ComputerName $DC3 -Credential $creds3 -ScriptBlock {
Import-Module ADDSDeployment
Install-ADDSDomainController `
-NoGlobalCatalog:$false `
-CreateDnsDelegation:$true `
-Credential ($using:creds3) `
-CriticalReplicationOnly:$false `
-DatabasePath "C:\Windows\NTDS" `
-DomainName $using:domain2 `
-InstallDns:$true `
-LogPath "C:\Windows\NTDS" `
-NoRebootOnCompletion:$false `
-SiteName "default-first-site-name" `
-SysvolPath "C:\Windows\SYSVOL" `
-Force:$true `
-SafeModeAdministratorPassword ($using:SafeModeAdministratorPassword)
}

Start-Sleep -s 300
Restart-Computer $DC3 -Credential $creds3

Start-Sleep -s 300

# DC-4 wordt toegevoegd en geinstalleerd
Write-Host "Installing DC4, waiting for replication"

Install-WindowsFeature -name AD-Domain-Services -IncludeManagementTools -ComputerName $DC4 -Credential $creds
Restart-Computer $DC4 -Credential $creds -force
Start-Sleep -s 900

Invoke-Command -ComputerName $DC4 -Credential $creds -ScriptBlock {
Import-Module ADDSDeployment
Install-ADDSDomain `
-NoGlobalCatalog:$false `
-CreateDnsDelegation:$true `
-Credential ($using:creds2) `
-DatabasePath "C:\Windows\NTDS" `
-DomainMode "Win2012R2" `
-DomainType "ChildDomain" `
-InstallDns:$true `
-LogPath "C:\Windows\NTDS" `
-NewDomainName $using:subdomain2 `
-NewDomainNetbiosName $using:subdomain2 `
-ParentDomainName $using:domain1 `
-NoRebootOnCompletion:$false `
-SiteName "default-first-site-name" `
-SysvolPath "C:\Windows\SYSVOL" `
-Force:$true `
-SafeModeAdministratorPassword ($using:SafeModeAdministratorPassword)
} 

Start-Sleep -s 300
Restart-Computer $DC4 -Credential $creds4

Start-Sleep -s 300

#Een DNS record wordt toegevoegd voor subdomain 2
Invoke-Command -ComputerName $DC1 -Credential $creds2 -ScriptBlock {
Add-DnsServerStubZone -Name $using:domain3 -MasterServers $using:DC4 -PassThru -ReplicationScope "Forest"
}
Start-Sleep -s 10
Invoke-Command -ComputerName $DC5 -Credential $creds -ScriptBlock {
ipconfig /flushdns
}

#change admin password and restart
Invoke-Command -ComputerName $DC5 -Credential $creds -ScriptBlock {
net user administrator $using:pin
}
Start-Sleep -s 10
Restart-Computer $DC5 -Credential ( New-Object System.Management.Automation.PSCredential "administrator", (ConvertTo-SecureString 'Welkom12345' -AsPlainText -Force))
Start-Sleep -s 100


# join domain
Invoke-Command -ComputerName $DC5 -Credential ( New-Object System.Management.Automation.PSCredential "administrator", (ConvertTo-SecureString 'Welkom12345' -AsPlainText -Force)) -ScriptBlock {
$domain = $using:domain3
$username = "$domain\administrator" 
$credential = New-Object System.Management.Automation.PSCredential($username,$using:pass)
Add-Computer -DomainName $domain -Credential $credential
}


Start-Sleep -s 10
Restart-Computer $DC5 -Credential ( New-Object System.Management.Automation.PSCredential "administrator", (ConvertTo-SecureString 'Welkom12345' -AsPlainText -Force))
Start-Sleep -s 100

# DC-5 wordt toegevoegd en geinstalleerd.
Write-Host "Installing DC5, waiting for replication"
Install-WindowsFeature -name AD-Domain-Services -IncludeManagementTools -ComputerName $DC5 -Credential ( New-Object System.Management.Automation.PSCredential "administrator", (ConvertTo-SecureString 'Welkom12345' -AsPlainText -Force)) -ErrorAction Stop
Restart-Computer $DC5 -Credential ( New-Object System.Management.Automation.PSCredential "administrator", (ConvertTo-SecureString 'Welkom12345' -AsPlainText -Force))
Start-Sleep -s 900

 Invoke-Command -ComputerName $DC5 -Credential $creds4 -ScriptBlock {
 Import-Module ADDSDeployment
 Install-ADDSDomainController `
 -NoGlobalCatalog:$false `
 -CreateDnsDelegation:$true `
 -Credential ($using:creds4) `
 -CriticalReplicationOnly:$false `
 -DatabasePath "C:\Windows\NTDS" `
 -DomainName $using:domain3 `
 -InstallDns:$true `
 -LogPath "C:\Windows\NTDS" `
 -NoRebootOnCompletion:$false `
 -SiteName "default-first-site-name" `
 -SysvolPath "C:\Windows\SYSVOL" `
 -Force:$true `
 -SafeModeAdministratorPassword ($using:SafeModeAdministratorPassword)
    }

Write-Host "All 5 DCs controllers are installed and configured!"
