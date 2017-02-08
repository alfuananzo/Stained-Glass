$DC = "10.0.0.11"
$pass = ConvertTo-SecureString -String "Hyper-v_vergelijken" -AsPlainText -force$creds2 = New-Object System.Management.Automation.PSCredential "WERK\administrator", $pass

$ADUsers = Get-ADUser -server $DC -Filter * -Credential $creds2 -Properties *   # Get Domain name$Domain = (get-Wmiobject Win32_computersystem).Domain$Domain = $Domain.split(".")[0] New-Item "C:\shared\users" -ItemType Directory New-SmbShare -Name users -Path "C:\shared\users" -FullAccess "administrator"   -Description " folders and files"#Create Profile shareForEach ($ADUser in $ADUsers)  { New-Item -ItemType Directory -Path "\\$DC\Users\$($ADUser.sAMAccountname)" $UsersAm = "$Domain\$($ADUser.sAMAccountname)"
$acl = Get-Acl -Path C:\shared\users\$($ADUser.sAMAccountname)
$Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($($ADUser.sAMAccountname), 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.SetAccessRule($Ar)
Set-Acl -Path C:\shared\users\$($ADUser.sAMAccountname) -AclObject $acl$homeDirectory = "\\$DC\Users\$($ADUser.sAMAccountname)" $homeDrive = "H" Set-ADUser -server $DC -Credential $creds2 -Identity $ADUser.sAMAccountname -Replace @{HomeDirectory=$homeDirectory} Set-ADUser -server $DC -Credential $creds2 -Identity $ADUser.sAMAccountname -Replace @{HomeDrive=$homeDrive} }