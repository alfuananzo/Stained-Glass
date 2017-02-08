$pass = ConvertTo-SecureString -String "Hyper-v_vergelijken" -AsPlainText -force
$client_creds = New-Object -TypeName System.Management.Automation.PSCredential "lab",$pass
$machine_name = "windows7-gold"
$machine = "192.168.138.200"
$vm = Get-VM -Name $machine_name
$prev_uptime  = $vm.Uptime

function start_update ($machine) {
    
    $date = Invoke-Command -ComputerName $machine -Credential $client_creds -ScriptBlock { Get-Date }
    $time = Invoke-Command -ComputerName $machine -Credential $client_creds -ScriptBlock { Get-Date -UFormat %R }
    Invoke-Command -ComputerName $machine -Credential $client_creds -ScriptBlock { "running" | Out-File C:\Windows\Stained-Glass\status.txt }

    $hour, [int]$minute = $time.Split(":")
    $minute = $minute + 2

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
    if ($minute -eq "60" -or $minute -eq "59" -and $hour -ne "23") {
        $hour ++
        $minute = "01"
    } elseif ($minute -eq "60") {
        $hour = "01"
        $minute = "01"
    }

    $date = $month, $day, $year -join("/")
    $time = $hour, $minute -join(":")

    $taskname = $month, $day, $year, $hour, $minute -join("")
    $taskname += " windows update"

    Invoke-Command -ComputerName $machine -Credential $client_creds -ScriptBlock { SCHTASKS /create /tn "$using:taskname" /TR "powershell.exe C:\Windows\Stained-Glass\wupdate.ps1" /sc ONCE /sd $using:date /st $using:time /RL HIGHEST }

    Start-Sleep -s 120

    while ((Invoke-Command -ComputerName $machine -Credential $client_creds -ScriptBlock { Get-Content C:\Windows\Stained-Glass\status.txt }) -eq "running") {
       "Working"
        Start-Sleep -s 60
    }

    Restart-Computer -ComputerName $machine -Credential $client_creds -Force

}

$ses = New-PSSession -ComputerName $machine -Credential $client_creds

Try {
    $log = Invoke-Command -Session $ses -ScriptBlock { get-item C:\Windows\Stained-Glass\update.log } -ErrorAction Stop
} catch [System.Management.Automation.RemoteException] {
    "First time running the auto updater, creating necisarry files"
    $out = Invoke-Command -Session $ses -ScriptBlock { mkdir C:\Windows\Stained-Glass\ }
    "Created $out on $($out.PSComputerName)"
    copy-item $dir\..\..\Installers\Update\wupdate.ps1 -Destination C:\Windows\Stained-Glass\ -ToSession $ses  
    "Moved the update script to Stained-Glass folder"
}

start_update $machine
Remove-PSSession $ses
Start-Sleep -s 120



"Installation of updates done"
$log = Invoke-Command -Session $ses -ScriptBlock { Get-Content C:\Windows\Stained-Glass\update.log }

while ($log -ne $null) {
    "More windows updates needed"
    $log = Invoke-Command -Session $ses -ScriptBlock { Get-Content C:\Windows\Stained-Glass\update.log }
} 

"No further installation needed. Script completed"





Get-PSSession | Remove-PSSession
Start-Sleep -s 100

#while ($True) {
#
#    
#    $vm = Get-VM -Name $machine_name
#
#    $uptime = $vm.Uptime
#    Start-Sleep -s 120
#    if ($uptime -lt $prev_uptime) {
#        "Shit restarted lets get to work"
#        Start-Sleep -s 600
#
#        $log = Invoke-Command -ComputerName $machine -Credential $client_creds -ScriptBlock { Get-Content C:\Users\Lab\Desktop\update_log.txt }
#        $log
#        if ($log -eq $null) {
#            "Updates finished succesfully"
#            exit
#        }
#
#        $date = Get-Date
#        $time = Get-Date -UFormat %R
#
#        $hour, [int]$minute = $time.Split(":")
#        $minute = $minute + 1
#
#        $month, $day, $year = $date.ToShortDateString().split("/")
#
#        if ($month.Length -lt 2) {
#            $month = "0$month"
#        }
#
#        if ($day.Length -lt 2) {
#            $day = "0$day"
#        }
#
#        if ($hour.Length -lt 2) {
#            $hour = "0$hour"
#        }
#
#        if (($minute | measure-object -Character).Characters -lt 2) {
#            [string]$minute = "0$minute"
#        }
#
#        # fix edge cases
#        if ($minute -eq "60" -and $hour -ne "23") {
#            $hour ++
#            $minute = "00"
#        } elseif ($minute -eq "60") {
#            $hour = "00"
#            $minute = "00" 
#        }
#
#        $date = $month, $day, $year -join("/")
#        $time = $hour, $minute -join(":")
#
#        $taskname = $month, $day, $year, $hour, $minute -join("")
#        $taskname += " windows update"
#
#        Invoke-Command -ComputerName $machine -Credential $client_creds -ScriptBlock { SCHTASKS /create /tn "$using:taskname" /TR "powershell.exe C:\Windows\Stained-Glass\update.ps1" /sc ONCE /sd $using:date /st $using:time /RL HIGHEST }
#
#        $log = Invoke-Command -ComputerName $machine -Credential $client_creds -ScriptBlock { Get-Content C:\Windows\Stained-Glass\update_log.txt }
#        
#        if ($log -eq $null) {
#            "Updates finished succesfully"
#            exit
#        }
#
#        
#    } else {
#        "No restart yet moving on"
#        $prev_uptime = $uptime
#    }
#}

