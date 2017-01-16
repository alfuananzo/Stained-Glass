param([String]$LabName="lab1")
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
[xml]$xml = Get-Content -Path "$dir\..\..\tmp\lab_config.xml"

$lab_id = $LabName
$vm_list = @()

"Are you sure you want to delete the following VM's from $LabName"
foreach ($lab in $xml.Labs.lab) {
    
    if ($lab.Name -eq $LabName) {

        $lab.ChildNodes.Name
        $vm_list += $lab.ChildNodes.Name
        
    } 
}

$response = Read-Host "(Y)es to delete lab (N)o to cancel"
if ($response.ToUpper() -eq "N" -or $response.ToUpper() -eq "NO") {
    "Cancelling"
    exit
} elseif ($response.ToUpper() -eq "Y" -or $response.ToUpper() -eq "YES") {
    
} else {
    "Unknown response, exiting"
    exit
}

foreach ($vm in $vm_list) {
    Stop-VM -name $vm -TurnOff
    remove-VM -name $vm -Force
}

Remove-Item -Path $dir\..\..\Disks\$lab_id\ -Force -Recurse

$data = Get-Content "$dir\..\..\tmp\lab_config.xml"
$out_buffer = @()
$can_write = $True

foreach ($line in $data) {

    if ($line -like "`t<lab Name=`"$LabName`"*"){
        $can_write = $False
    }

    if ($can_write) {
        $out_buffer += $line
    } else {
        if ($line -eq "`t</lab>") {
            $can_write = $True
        }
    }
}

$out_buffer | Out-File $dir\..\..\tmp\lab_config.xml

"Removal completed"