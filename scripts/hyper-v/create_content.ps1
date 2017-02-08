param([String]$LabName, [String]$PassWord, [string]$smb)
Get-PSSession | Remove-PSSession

$pass = ConvertTo-SecureString -String $PassWord -AsPlainText -force
$client_creds = New-Object -TypeName System.Management.Automation.PSCredential "lab",$pass
$server_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$pass
$rand = New-Object System.Random
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
$words = Import-Csv $dir\..\..\configs\dict.csv
#$users = Import-Csv $dir\..\..\configs\users.csv
$upper_bound = $words.Count

function random_file {
    $extensions = "docx", "ps1", "png", "jpg", "pptx", "txt", "pdf", "csv", "xml", "mp3", "avi", "mp4", "gif", "bmp", "sql", "exe", "com", "bat", "html", "php", "dll", "ico", "7z", "zip", "tar.gz", "torrent", "pgp"
    $length = $rand.Next(1,4)

    $file_name = ""

    foreach ($x in 0..$length) {
        $file_name += ($words[$rand.Next(0,$upper_bound)]).Word
    }

    $ext = ($extensions[$rand.Next(0, $extensions.Count)])
    return $file_name, ".$ext" -join("")
}

$ses = New-PSSession -ComputerName $smb -Credential $server_creds
$disks = Invoke-Command -Session $ses -ScriptBlock { ls C:\shared }

#Create folder structure
foreach ($x in 0..100) {
    $dir_tree = Invoke-Command -Session $ses -ScriptBlock { Get-ChildItem C:\shared -Recurse | ?{ $_.PSIsContainer } | Select-Object FullName }
    $parent_dir = $dir_tree[$rand.Next(0,$dir_tree.Count)]

    $dir_name = ($words[$rand.Next(0,$upper_bound)]).Word
    $full_dir = $parent_dir.FullName + "\" + $dir_name
    $outcome = Invoke-Command -Session $ses -ScriptBlock { New-Item $using:full_dir -ItemType Directory }
    "Creating: $($outcome.FullName)"
    Start-Sleep -Milliseconds 100
}

$dir_tree = Invoke-Command -Session $ses -ScriptBlock { Get-ChildItem C:\shared -Recurse | ?{ $_.PSIsContainer } | Select-Object FullName }

foreach ($x in 0..500) {
    $dir = ($dir_tree[$rand.Next(0,$dir_tree.Count)]).FullName
    $file = random_file
    $full_path = $dir + "\" + $file
    $outcome = Invoke-Command -Session $ses -ScriptBlock { New-Item $using:full_path -ItemType File }
    "Creating: $($outcome.FullName)"
    Start-Sleep -Milliseconds 100
}