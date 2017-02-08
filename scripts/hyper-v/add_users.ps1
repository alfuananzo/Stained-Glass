param($DC1, $DC2, $DC4, $domain1, $subdomain1, $subdomain2, $password, $smb)

#$domain2 = "$subdomain1.$domain1"
#$domain3 = "$subdomain2.$domain1"
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath


### credentials
$pass = ConvertTo-SecureString -String $password -AsPlainText -force
$server_creds = New-Object System.Management.Automation.PSCredential "administrator",$pass
$dc_creds = New-Object System.Management.Automation.PSCredential "administrator@$domain1",$pass


function create_users ($domain, $DC) {
    
    $creds = New-Object System.Management.Automation.PSCredential "administrator@$domain",$script:pass
    $ses = New-PSSession -ComputerName $DC -Credential $creds

    Copy-Item $dir\..\..\configs\users.csv -Destination C:\ -ToSession $ses

    Invoke-Command -Session $ses -ScriptBlock {
        $dep = import-csv C:\users.csv | where-object {$_.domain -ceq $using:domain } | % {$_.department} | select-object -Unique
        $dom1, $dom2, $dom3 = $($using:domain).split(".")[0,1,2]


        if ($dom3 -eq $null) {
            $path = "DC="+$dom1 +",DC="+$dom2
        } else {
            $path = "DC="+$dom1 +",DC="+$dom2 + ",DC="+$dom3
        }


        foreach ($departement in $dep) {
            new-ADorganizationalUnit  -name $departement -path "$path"
            New-ADGroup -Name "$departement"  -GroupCategory Security -GroupScope Global -DisplayName $departement -Path "OU=$departement,$path"
        }

        foreach ($user in import-csv C:\users.csv | where-object {$_.domain -ceq $using:domain } ) {
            $user_dep = $user.department
            if($user.enabled -ceq "TRUE"){
                [Bool]$enable = $true
            } else{
                [Bool]$enable = $false
            }

            if($user.expires -ceq "TRUE"){
                [Bool]$expires = $true
            } else{
                [Bool]$expires = $false
            }

            new-aduser -name $user.username -userprincipalName "$($user.username)@$($user.domain)" -accountpassword (ConvertTo-SecureString $user.password -AsPlainText -Force) -Enabled $enable -passwordNeverExpires $expires -Path "OU=$($user.department),$path"
            add-ADgroupmember $user.department $user.username 
        }

                # create extra groups (needs $path and alter csv path)
        $gr = import-csv C:\users.csv | where-object {$_.domain -ceq $using:domain } | % {$_.groups} 
        $gr = $gr.split(";") | select-object -Unique
        foreach ($item in $gr){
        if ($item -ne ""){ New-ADGroup -Name $item  -GroupCategory Security -GroupScope Global -DisplayName $item -Path "$path" }}
      
        foreach ($user in import-csv C:\users.csv | where-object {$_.domain -ceq $using:domain -and $_.groups -ne "" }  ){
        $ggr = $user.groups.split(";")
        foreach ($item in $ggr){ Add-ADGroupmember -identity "$item" -Member $user.username}}

    }

    Invoke-Command -Session $ses -ScriptBlock { remove-item C:\users.csv -Force }

    Remove-PSSession $ses

}


create_users $domain1 $DC1
$domain = $subdomain1, $domain1 -join(".")
create_users $domain $DC2
$domain = $subdomain2, $domain1 -join(".")
create_users $domain $DC4
 $users = import-csv $dir\..\..\configs\users.csvInvoke-Command -Computername $smb -Credential $server_creds -ScriptBlock { New-Item "C:\shared\users" -ItemType Directory }Invoke-Command -Computername $smb -Credential $server_creds -ScriptBlock { New-SmbShare -Name users -Path "C:\shared\users" -FullAccess "administrator","Everyone"  -Description " folders and files" }foreach ($user in $users){    $homeDirectory = "\\$smb\Users\$($user.username)"    Invoke-Command -ComputerName $smb -Credential $server_creds { mkdir C:\shared\Users\$($using:user.username) }    $domain = ($user.domain).split(".")[0]    if ($domain -eq $subdomain1) { invoke-command -ComputerName $DC2 -Credential $server_creds -ScriptBlock { Get-ADUser -Identity $using:user.username | Set-ADUser -Replace @{HomeDirectory=$using:homeDirectory; HomeDrive="H"} } }    elseif ($domain -eq $subdomain2) { invoke-command -ComputerName $DC4 -Credential $server_creds -ScriptBlock { Get-ADUser -Identity $using:user.username | Set-ADUser -Replace @{HomeDirectory=$using:homeDirectory; HomeDrive="H"} } }    else { invoke-command -ComputerName $DC1 -Credential $server_creds -ScriptBlock { Get-ADUser -Identity $using:user.username | Set-ADUser -Replace @{HomeDirectory=$using:homeDirectory; HomeDrive="H"} } }    Invoke-Command -ComputerName $smb -Credential $server_creds -ScriptBlock { $acl = Get-Acl -Path C:\shared\users\$($using:user.username) ; $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($($using:user.username), 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))) ; Set-Acl -Path C:\shared\users\$($using:user.username) -AclObject $acl }}