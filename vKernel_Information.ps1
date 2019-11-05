
#
# Specify vCenter Server(s), vCenter Server username, vCenter Server user password.
#$vCenterServers=("vt0pvcsa01.aqrcapital.com","vt0pvcvdi01.aqrcapital.com")
$vCenterServers=("vt0pvcsa01.aqrcapital.com", "vt0pvcvdi01.aqrcapital.com", "va0pvcsa01.aqrcapital.com", "va0pvcvdi01.aqrcapital.com")
#$vCenterUser="magander@vcdx56"
#$vCenterUserPassword="not-secret"
#
# Specify script output file name and location on the workstation where you run the script
$outfile="H:\scripts\EnabledVMkernelInterfaces.csv"
#
# You don't have to change anything below this line
# ---------------------------------------------------
#
#
foreach ($vCenterServer in $vCenterServers) {
# Connect to vCenter Server
write-host Connecting to vCenter Server $vcenterserver -foreground green
Connect-viserver $vCenterServer -WarningAction 0 | out-null
#Get-VMHost * | sort | Get-VMHostNetworkAdapter -VMKernel | select VMHost,IP,SubNetMask,PortGroupName,DeviceName,VMotionEnabled | where VMotionEnabled -eq $True | Export-Csv $outfile -Append
Get-VMHost * | sort | Get-VMHostNetworkAdapter -VMKernel | select VMHost,IP,SubNetMask,PortGroupName,DeviceName,VMotionEnabled | Export-Csv $outfile -Append
# Disconnect from vCenter Server
write-host "Disconnecting to vCenter Server $vCenterServer" -foreground green
disconnect-viserver -confirm:$false | out-null
echo ""
}
