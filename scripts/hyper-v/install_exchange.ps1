param($DC1, $MAIL1, $domain1, $password)
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath

function write_bat($domain) {
    "D:\Setup.exe /role:ClientAccess,Mailbox /OrganizationName:$domain /IAcceptExchangeServerLicenseTerms /EnableErrorReporting"
    "Start-Sleep -s 120"
    "Restart-Computer -Force"
    return
}

$exchange_ip = (Get-VMNetworkAdapter -VMName $MAIL1 | select IPAddresses).IpAddresses[0]
Set-VMDvdDrive -VMName $MAIL1 -Path $dir\..\..\installers\Exchange\Exchange2013.iso

write_bat $domain1.Split(".")[0] | Out-File $dir\..\..\installers\exchange\r-install.ps1


#### credentials
$pass = ConvertTo-SecureString -String $password -AsPlainText -force

$creds1 = New-Object System.Management.Automation.PSCredential "administrator",$pass
$creds2 = New-Object System.Management.Automation.PSCredential "administrator@$domain1", $pass

function schedule_task ($task, $ses) { 
    $date = Get-Date
    $time = Get-Date -UFormat %R

    $hour, [int]$minute = $time.Split(":")
    $minute = $minute + 2

    $month, $day, $year = $date.ToShortDateString().split("/")

    if ($month.Length -lt 2) {
        [string]$month = "0$month"
    }

    if ($day.Length -lt 2) {
        [string]$day = "0$day"
    }

    if ($hour.Length -lt 2) {
        [string]$hour = "0$hour"
    }

    if (($minute | measure-object -Character).Characters -lt 2) {
        [string]$minute = "0$minute"
    }

    # fix edge cases
    if (($minute -eq "60" -or $minute -eq "61") -and $hour -ne "23") {
        $hour = [String](($hour -as [int]) + 1)
        if ($hour.Length -lt 2) { $hour = "0$hour" }
        [string]$minute = "01"
    } elseif ($minute -eq "60") {
        [string]$hour = "01"
        [string]$minute = "01"
    }

    $date = $month, $day, $year -join("/")
    $time = $hour, $minute -join(":")

    $taskname = $month, $day, $year, $hour, $minute -join("")
    $taskname += " exchange"

    Invoke-Command -Session $ses -ScriptBlock {
        SCHTASKS /create /tn "$using:taskname" /TR "$using:task"  /sc ONCE /sd $using:date /st $using:time 
    }
}

# Setup Primary DNS server name and hostname
$ses = New-PSSession -ComputerName $exchange_ip -Credential $creds1

Invoke-Command -Session $ses -ScriptBlock { Set-DNSClientServerAddress –interfaceIndex 12 –ServerAddresses ($using:DC1) }

### join domain
#
Invoke-Command -Session $ses -ScriptBlock {
    $domain = $using:domain1
    $username = "$domain\administrator" 
    Add-Computer -DomainName $domain -Credential $using:creds2 -Restart -Force
}

Remove-PSSession $ses


start-sleep -s 120

$ses = New-PSSession -ComputerName $exchange_ip -Credential $creds2

Invoke-Command -Session $ses -ScriptBlock {
    set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoAdminLogon -Value 1
    new-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultUserName -Value "$using:domain1\Administrator"
    new-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultPassword -Value $using:password
    new-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\system' -Name DisableLockWorkstation -Value 1
}

## install features
Invoke-Command -Session $ses -ScriptBlock {
Install-WindowsFeature AS-HTTP-Activation, Desktop-Experience, NET-Framework-45-Features, RPC-over-HTTP-proxy, RSAT-Clustering, RSAT-Clustering-CmdInterface, RSAT-Clustering-Mgmt, RSAT-Clustering-PowerShell, Web-Mgmt-Console, WAS-Process-Model, Web-Asp-Net45, Web-Basic-Auth, Web-Client-Auth, Web-Digest-Auth, Web-Dir-Browsing, Web-Dyn-Compression, Web-Http-Errors, Web-Http-Logging, Web-Http-Redirect, Web-Http-Tracing, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Lgcy-Mgmt-Console, Web-Metabase, Web-Mgmt-Console, Web-Mgmt-Service, Web-Net-Ext45, Web-Request-Monitor, Web-Server, Web-Stat-Compression, Web-Static-Content, Web-Windows-Auth, Web-WMI, Windows-Identity-Foundation, RSAT-ADDS
}


Remove-PSSession $ses

Start-Sleep -s 3
Restart-Computer $exchange_ip -Credential $creds2 -Force
Start-Sleep -s 600

$ses = New-PSSession -ComputerName $exchange_ip -Credential $creds2
Invoke-Command -Session $ses -ScriptBlock {mkdir C:\exchange_install }

Copy-Item $dir\..\..\installers\exchange\r-* -ToSession $ses -Destination C:\exchange_install 

Remove-PSSession $ses


$ses = New-PSSession -ComputerName $exchange_ip -Credential $creds2


Invoke-Command -Session $ses -ScriptBlock {
C:\exchange_install\r-ucma.exe -q
}

Remove-PSSession $ses

Start-Sleep -s 3
Restart-Computer $exchange_ip -Credential $creds2 -Force
Start-Sleep -s 200

$ses = New-PSSession -ComputerName $exchange_ip -Credential $creds2

schedule_task "powershell.exe C:\exchange_install\r-install.ps1" $ses

Start-Sleep -s 120

schedule_task "powershell.exe C:\exchange_install\r-nosleep.ps1" $ses
$time = Get-VM -name $MAIL1 | select Uptime 
$start = $time.UpTime.TotalSeconds
start-sleep -s 2 

$time = Get-VM -name $MAIL1 | select Uptime 
$run = $time.UpTime.TotalSeconds

while ($run -gt $start ) {
    Write-Host -NoNewline "."
    start-sleep -s 60
    $time = Get-VM -name $MAIL1 | select Uptime 
    $run = $time.UpTime.TotalSeconds
}

start-sleep -s 60

Write-Host "mission accomplished!" 

$server_up = $false
while (-not $server_up) {

    try {
        $ses = New-PSSession -ComputerName $script:exchange_ip -Credential $script:creds2 -ErrorAction Stop
        $server_up = $true
    } catch {
        "Waiting for server"
        Start-Sleep -s 60
    }
}

Remove-PSSession $ses
$to = 0
"Server up, checkinf if exchange started"while ((Invoke-Command -ComputerName $exchange_ip -Credential $creds1 -ScriptBlock { (Get-Service -Name "*MSexchange*" | ?{$_.Status -eq "Running"}).Count }) -lt 21) {    "Exchange is not yet up"    $to ++    if ($to -eq 10) {        $to = 0       "Exchange installation appears to have failed, trying to mend the situation"        Invoke-Command -ComputerName $DC1 -Credential $creds2 -ScriptBlock { Remove-ADGroup -Identity "Discovery Management" -Confirm:$false }        Start-Sleep -s 20        $ses = New-PSSession -ComputerName $exchange_ip -Credential $creds2        schedule_task "powershell.exe C:\exchange_install\r-install.ps1" $ses
        Remove-PSSession $ses
        $time = Get-VM -name $MAIL1 | select Uptime 
        $start = $time.UpTime.TotalSeconds
        start-sleep -s 2 

        $time = Get-VM -name $MAIL1 | select Uptime 
        $run = $time.UpTime.TotalSeconds

        while ($run -gt $start ) {
            Write-Host -NoNewline "."
            start-sleep -s 60
            $time = Get-VM -name $MAIL1 | select Uptime 
            $run = $time.UpTime.TotalSeconds
        }        Start-Sleep -s 120    }    Start-Sleep -s 60}Start-Sleep -s 300
$ses = New-PSSession -ComputerName $exchange_ip -Credential $creds2

schedule_task "powershell.exe C:\exchange_install\r-connecter.ps1" $ses

Start-Sleep -s 180

schedule_task "powershell.exe C:\exchange_install\r-users.ps1" $ses

Invoke-Command -Session $ses -ScriptBlock {

set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoAdminLogon -Value 0
set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultUserName -Value "Administrator"
set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultPassword -Value WWW
}

Get-PSSession | Remove-PSSession