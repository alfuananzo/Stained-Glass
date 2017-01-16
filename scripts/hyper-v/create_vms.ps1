param([Int32]$ServerCount=3, [String]$LabName="lab")
$server_count = $ServerCount
$lab_id = $LabName

New-Item "G:\Hyper-v\Disks\$lab_id" -type directory

for ($i = 1; $i -le $server_count; $i++) {
    New-VHD -Differencing -Path "G:\Hyper-v\Disks\$lab_id\$lab_id-$i.vhdx" -ParentPath "G:\RAW_disks\2012-R2-RAW.vhdx"
    New-VM -Name "$lab_id-$i" -MemoryStartupBytes 1024MB -VHDPath "G:\Hyper-v\Disks\$lab_id\$lab_id-$i.vhdx" -SwitchName "LAB" -Generation 2
    Start-VM -Name "$lab_id-$i"
}