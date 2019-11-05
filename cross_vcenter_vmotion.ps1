. .\lib\Get-PIMSecret.ps1  
$sourceVC = 'vt0pvcvdi01.aqrcapital.com'
$sourceVCUsername = 'administrator@vsphere.local'
$sourceVCPassword= $(Get-PIMSecret -SecretId '2261').secret
  
$destVC = 'va0pvcvdi01.aqrcapital.com'
$destVCUsername = 'administrator@vsphere.local'
$destVCPassword= $(Get-PIMSecret -SecretId '2261').secret

# Connect to the vCenter Servers
$sourceVCConn = Connect-VIServer -Server $sourceVC -user $sourceVCUsername -password $sourceVCPassword
$destVCConn = Connect-VIServer -Server $destVC -user $destVCUsername -password $destVCPassword

$vm = Get-VM ASH_VW10CORE_b1809_2019-04-23 -Server $sourceVCConn
#$networkAdapter = Get-NetworkAdapter -VM $vm -Server $sourceVCConn

$destination = Get-VMHost 'sa0pvdi007.aqrcapital.com'
$destinationPortGroup = Get-VDPortgroup -VDSwitch 'VDI_4uplink' -Name 'Windows_Dynamic_22_VLAN901' -Server $destVCConn
$destinationDatastore = Get-Datastore 'VDI20_ASH_PPUR01_DS03' -Server $destVCConn

#Move-VM -VM $vm -Destination $destination -NetworkAdapter $networkAdapter -PortGroup $destinationPortGroup -Datastore $destinationDatastore
Move-VM -VM 'ASH_VW10CORE_b1809_2019-04-23' -Destination 'sa0pvdi001' -Datastore 'VDI20_ASH_PPUR01_DS03'
