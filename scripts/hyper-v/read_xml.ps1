param([string]$LabName)
$lab_name = $LabName

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath

[xml]$xml = Get-Content -Path "$dir\..\..\tmp\lab_config.xml"

foreach ($lab in $xml.labs.ChildNodes) {
    if ( $lab.Name -eq $lab_name) {
        foreach ($machine in $lab.ChildNodes) {
            $programs = $machine.Programs.Split(",")
            "$($machine.Name) to install $programs"
        }
    }
}