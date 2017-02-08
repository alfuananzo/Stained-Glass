param([String]$LabName, [String]$PassWord, [string]$exchange, $DC1, $DC2, $DC4, $dhcp_ip)

$pass = ConvertTo-SecureString -String $PassWord -AsPlainText -force
$client_creds = New-Object -TypeName System.Management.Automation.PSCredential "lab",$pass
$server_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$pass
#$server_creds2 = New-Object -TypeName System.Management.Automation.PSCredential "MARC\administrator",$pass
$rand = New-Object System.Random
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
$words = Import-Csv $dir\..\..\configs\dict.csv
$upper_bound = $words.Count
$users = Import-Csv $dir\..\..\configs\users.csv
[xml]$xml = Get-Content -Path "$dir\..\..\configs\labs_config.xml"
$client_list = @()

function write_script ($domain, $ip, $password) {
    '$pass = ConvertTo-SecureString -String "' + $password + '" -AsPlainText -force'
    '$creds = New-Object -TypeName System.Management.Automation.PSCredential "' + $domain + '\administrator",$pass'
    '$bad_creds = New-Object -TypeName System.Management.Automation.PSCredential "fjbdbf",$pass'    
    '$rand = New-Object System.Random'
    'while ($True) {'
    'start-sleep -s 5'
    'net time \\' + $ip + ' /set /y'
    'if ($rand.Next(0,100) -eq 1){'
    'if ($rand.Next(0,10) -ne 1){'
    '$ses = New-pssession -Computername ' + $ip + ' -Credential $creds'
    'Invoke-command -Session $ses -ScriptBlock { ipconfig }'
    'Remove-PSSession $ses'
    '} else {'
    'New-pssession -Computername ' + $ip + ' -Credential $bad_creds'
    '}'
    '}'
    '}'
    return
}

function schedule_task ($task, $ses) { 
    $date = Invoke-Command -Session $ses -Scriptblock { Get-Date }
    $time = Invoke-Command -Session $ses -Scriptblock { Get-Date -UFormat %R }

    $hour, [int]$minute = $time.Split(":")
    $minute = $minute + 1

    $month, $day, $year = $date.ToShortDateString().split("/")

    if ($month.Length -lt 2) {
        $month = "0$month"
    }

    if ($day.Length -lt 2) {
        $day = "0$day"
    }

    if ($hour.Length -lt 2) {
        $hour = "0$hour"
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
        $hour = "01"
        [string]$minute = "01"
    }

    $date = $month, $day, $year -join("/")
    $time = $hour, $minute -join(":")

    $taskname = $month, $day, $year, $hour, $minute -join("")
    $taskname += " time machine"
    $time

    Invoke-Command -Session $ses -ScriptBlock {
        SCHTASKS /create /tn "$using:taskname" /TR "$using:task"  /sc ONCE /sd $using:date /st $using:time
    }
}

# Build user list
$users_list = @()
foreach ($user in $users) { if ($user.domain -eq "demo.com") { $users_list += $user } }

$ses = New-PSSession -ComputerName $exchange -Credential $server_creds
$i = 0
$n = 50
foreach ($y in 1..$n) {
    foreach ($user in $users_list) {
        $sender = "$($user.name) <$($user.username)@demo.com>"
    
        #Build title and body
        $subject = ($words[$rand.Next(0,$upper_bound)]).Word + " " + ($words[$rand.Next(0,$upper_bound)]).Word
        $body_length = $rand.Next(5,40)
        $rn = $rand.Next(0,$users_list.Count)
        $recipient = "$($users_list[$rn].Name) <$($users_list[$rn].username)@demo.com>"
        $body = "Dear $($users_list[$rn].name)`n`n"
        foreach ($x in 0..$body_length) {
            $body += ($words[$rand.Next(0,$upper_bound)]).Word + " "
        }

        $body += "`n`nYours truly`n$($user.name)"
        Invoke-Command -Session $ses -ScriptBlock { Send-MailMessage -to $using:recipient -from $using:sender -Subject $using:subject -Body $using:body -SmtpServer localhost }
        $i++
        Write-Progress -Activity "Sending mail" -Status "Sending mail for $($user.Name)" -PercentComplete ($i / ($users_list.Count * $n) * 100)
    }

}

#Start-Sleep -s 100
### time to fill log files
#
### Stop hyper-v time syncs
##Invoke-command -ComputerName $DC1 -Credential $server_creds -ScriptBlock { Stop-Service -name vmictimesync }
##Invoke-command -ComputerName $DC2 -Credential $server_creds -ScriptBlock { Stop-Service -name vmictimesync }
##Invoke-command -ComputerName $DC4 -Credential $server_creds -ScriptBlock { Stop-Service -name vmictimesync }
#
#$dhcp_leases = Invoke-Command -Computername $dhcp_ip -Credential $server_creds -ScriptBlock { Get-DhcpServerv4Lease -ScopeID $using:scope }
#foreach ($vm in $xml.labs.$LabName.ChildNodes) {
#    if ($vm.Type -eq "Client") {
#        $vm_info = Get-VMNetworkAdapter -VMName $vm.Name
#        foreach ($dhcp_lease in $dhcp_leases ) {
#            if ($dhcp_lease.ClientId.Replace("-", "").toUpper() -eq $vm_info.MacAddress) {
#                $client_list += "$($vm.Name),$($dhcp_lease.IPAddress),$($vm.OS),$($vm.Domain)"
#            }
#        }
#    }
#}
#
#$root_domain = $xml.labs.$LabName.domain
#$sub_domain1 = $xml.labs.$LabName.subdomain1
#$sub_domain2 = $xml.labs.$LabName.subdomain2
#
#$root_domain_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator@$root_domain",$pass
#$sub_domain1_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator@$sub_domain1",$pass
#$sub_domain2_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator@$sub_domain2",$pass
#
#$key_locker = @{$root_domain = $root_domain_creds; $sub_domain1 = $sub_domain1_creds; $sub_domain2 = $sub_domain2_creds}
#
#$client_list
#foreach ($client in $client_list) {
#    $name, $client_ip, $os, $domain = $client.split(",")
#    if ($client.domain -eq $root_domain.split(".")[0]) { $ip = $DC1 }
#    elseif ($client.domain -eq $sub_domain1) { $ip = $DC2 }
#    else { $ip = $DC4 }
#
#    write_script $domain $ip $PassWord | Out-File $dir\..\..\tmp\$($name).ps1
#    $ses = New-PSSession -ComputerName $client_ip -Credential $client_creds
#    Invoke-Command -Session $ses -ScriptBlock {
#    set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoAdminLogon -Value 1
#    new-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultUserName -Value "$using:domain\Administrator"
#    new-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultPassword -Value $using:password
#    new-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\system' -Name DisableLockWorkstation -Value 1
#    }
#    Invoke-Command -Session $ses -ScriptBlock { Restart-Computer -Force }
#    Start-Sleep -s 30
#    Remove-PSSession $ses
#    $ses = $False
#    while (-not $ses) {
#        try {
#            $ses = New-PSSession -ComputerName $client_ip -Credential $key_locker[$domain] -ErrorAction Stop
#            } catch {
#            $ses = $False
#            Start-Sleep -s 10
#            }
#    }
#
#    Invoke-Command -Session $ses -ScriptBlock { Stop-Service -name vmictimesync }
#    Copy-Item -Path $dir\..\..\tmp\$name.ps1 -Destination C:\ -ToSession $ses
#    schedule_task "powershell.exe C:\$name.ps1" $ses
#}
#
#Start-Sleep -s 100
#foreach ($client in $client_list) {
#    $name, $ip, $os, $domain = $client.split(",")
#    $ses = New-PSSession -ComputerName $ip -Credential $server_creds2
#    schedule_task "powershell.exe C:\time_machine.ps1" $ses
#    #Invoke-Command -ComputerName $ip -Credential $client_creds -ScriptBlock { net time \\d2s-4 /set /y }
#    Remove-PSSession $ses
#}
#
#Start-Sleep -s 60
#
## Travel trough time!
#
#$i = 0
## 525600 = minutes in a year
#while ($i -lt 525600) {
#    $m = $rand.Next(10,100)
#    Invoke-command -ComputerName $DC1 -Credential $server_creds -ScriptBlock { Set-Date (Get-Date).AddMinutes($using:m) }
#    Invoke-command -ComputerName $DC2 -Credential $server_creds -ScriptBlock { Set-Date (Get-Date).AddMinutes($using:m) }
#    Invoke-command -ComputerName $DC4 -Credential $server_creds -ScriptBlock { Set-Date (Get-Date).AddMinutes($using:m) }
#    Start-Sleep -s 5
#    #foreach ($client in $client_list) {
#    #    $name, $ip, $os, $domain = $client.split(",")
#    #    Invoke-Command -ComputerName $ip -Credential $server_creds2 -ScriptBlock { net time \\10.0.11.5 /set /y }
#    #}
#}