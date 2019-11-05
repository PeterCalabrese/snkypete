<#
.Synopsis
   Final customization and deployment script for a new ESXi Host.
.DESCRIPTION
   After the host has been built, this script will perform the following :
        1. Log you in to the correct vCenter
        2. Add the host to the correct vCenter
        3. Place the host in Maintenance Mode
        4. Set the following specifications :
            A. NTP
            B. Join the AQRCAPITAL Domain
            C. Configure Advanced System Settings
            D. Patch the Server to the Production Baseline if required
            E. Reboot the host
.EXAMPLE
   .\New_ESXi_Host_Deployment.ps1 -newhost st0pvdi203.aqrcapital.com
.EXAMPLE
   .\New_ESXi_Host_Deployment.ps1 -newhost st0pvmdprod15.aqrcapital.com
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>


###Set Parameters###

Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true, 
                   Position=0)]
        $newhost
    )

 . .\lib\Get-PIMSecret.ps1

###Credentials###
$DJA_Username = 'dja_svc@aqrcapital.com'
$DJA_Password = $(Get-PIMSecret -SecretId '1971').secret
$rootuser = 'root'
$rootpass = $(Get-PIMSecret -SecretId '4519').secret
$credentials = Get-Credential
$ESXi_License = $(Get-PIMSecret -SecretId '6791').secret
$TRM_VDI_ESXi_License = $(Get-PIMSecret -SecretId '7821').secret
$ASH_VDI_ESXi_License = $(Get-PIMSecret -SecretId '7820').secret

###vCenters###
$TRM_VDI = 'vt0pvcvdi01.aqrcapital.com'
$TRM_VSI = 'vt0pvcsa01.aqrcapital.com'
$ASH_VDI = 'va0pvcvdi01.aqrcapital.com'
$ASH_VSI = 'va0pvcsa01.aqrcapital.com'
$TRM_NPP = 'vt0dvcsa01.aqrcapital.com'

###Advanced System Settings###
$tcpvalue = 'tcp://trmlogger.aqrcapital.com:514'


######################################

###Connect to the proper vCenter###
If ($newhost -like "st0pvdi*" ){Connect-VIServer -Server $TRM_VDI -Credential $credentials}
elseif ($newhost -like "st0pvmwprod*" ){Connect-VIServer -Server $TRM_VSI -Credential $credentials}
elseif ($newhost -like "st0pvmwsql*" ){Connect-VIServer -Server $TRM_NPP -Credential $credentials}
elseif ($newhost -like "st0pvmw*" -or $newhost -like "st0pvmuc*" ){Connect-VIServer -Server $TRM_VSI -Credential $credentials}
elseif ($newhost -like "st0pvmdmz*" -or $newhost -like "st0pvmuc*" ){Connect-VIServer -Server $TRM_VSI -Credential $credentials}
elseif ($newhost -like "sa0pvdi*" ){Connect-VIServer -Server $ASH_VDI -Credential $credentials}
else {Connect-VIServer -Server $ASH_VSI -Credential $credentials}


###Add Host to vCenter###
If ($newhost -like "st0pvdi*" ){Add-VMHost  $newhost -Location "TRM_210" -User $rootuser -Password $rootpass -Force:$true}
elseif ($newhost -like "st0pvmwprod*"){Add-VMHost $newhost -Location "TRM_210" -User $rootuser -Password $rootpass -Force:$true}
elseif ($newhost -like "st0pvmdmz*"){Add-VMHost $newhost -Location "TRM_DMZ_210" -User $rootuser -Password $rootpass -Force:$true}
elseif ($newhost -like "sa0pvdi*" ){Add-VMHost $newhost -Location "Ashburn-VDI" -User $rootuser -Password $rootpass -Force:$true}
elseif ($newhost -like "st0pvmwsql*" ){Add-VMHost $newhost -Location "TRM_Datacenter" -User $rootuser -Password $rootpass -Force:$true}
elseif ($newhost -like "st0pvmw*" -or $newhost -like "st0pvmuc*"){Add-VMHost $newhost -Location "TRM_1B" -User $rootuser -Password $rootpass -Force:$true}
else {Add-VMHost $newhost -Location "Ashburn-VSI" -User $rootuser -Password $rootpass -Force:$true}

Sleep 10


###Set Host into Maintenance Mode###
$MaintMode = Set-VMHost -VMHost $newhost -State "Maintenance"

Sleep 5


###License Host###
If ($newhost -like "st0pvdi*" ){Set-VMHost -VMHost $newhost -LicenseKey $TRM_VDI_ESXi_License}
elseif ($newhost -like "st0pvmwprod*"){Set-VMHost -VMHost $newhost -LicenseKey $ESXi_Licensee}
elseif ($newhost -like "st0pvmdmz*"){Set-VMHost -VMHost $newhost -LicenseKey $ESXi_License}
elseif ($newhost -like "st0pvmwsql*"){Set-VMHost -VMHost $newhost -LicenseKey WJ6CJ-FY05H-28388-0T9A2-8EX20}
elseif ($newhost -like "sa0pvdi*" ){Set-VMHost -VMHost $newhost -LicenseKey 00000-00000-00000-00000-00000}
elseif ($newhost -like "st0pvmwsql*" ){Set-VMHost -VMHost $newhost -LicenseKey $ESXi_License}
elseif ($newhost -like "st0pvmw*" -or $newhost -like "st0pvmuc*"){Set-VMHost -VMHost $newhost -LicenseKey $ESXi_License}
else {Set-VMHost -VMHost $newhost -LicenseKey $ESXi_License}

Sleep 5


###Set NTP Settings###
Add-VMHostNtpServer -VMHost $newhost -NtpServer ntp1.aqrcapital.com, ntp2.aqrcapital.com
Get-VmHostService -VMHost $newhost | ? {$_.key -eq "ntpd"} | Start-VMHostService
Get-VmHostService -VMHost $newhost | ? {$_.key -eq "ntpd"} | Set-VMHostService -policy "on"

###Set Power Management Settings###
Get-AdvancedSetting -Entity $newhost -Name 'Power.CPUPolicy' |
Set-AdvancedSetting -Value 'High Performance' -Confirm:$false


###Join Domain###
$JoinDomain = Get-VMHost $newhost | Get-VMHostAuthentication | Set-VMHostAuthentication -JoinDomain -Domain "AQRCAPITAL.COM" -User $DJA_Username -Password $DJA_Password -Confirm:$false

Sleep 10


###Set Advanced System Settings###

Get-VMHost $newhost | Get-AdvancedSetting -Name NFS.MaxVolumes | Set-AdvancedSetting -Value 256 -Confirm:$false
Get-VMHost $newhost | Get-AdvancedSetting -Name NFS41.MaxVolumes | Set-AdvancedSetting -Value 256 -Confirm:$false
Get-VMHost $newhost | Get-AdvancedSetting -Name 'Syslog.Global.Loghost' | Set-AdvancedSetting -Value $tcpvalue -Confirm:$false
If ($($newhost -notlike "st0pvdi*") -or $($newhost -notlike "sa0pvdi*")){Get-VMHost $newhost | Get-AdvancedSetting -Name Mem.ShareForceSalting | Set-AdvancedSetting -Value 0 -Confirm:$false}


###Enable vMotion###

Get-VMHost $newhost | Get-VMHostNetworkAdapter -VMKernel | Set-VMHostNetworkAdapter -VMotionEnabled $true -Confirm:$false

Sleep 10


###Patch Host to Production Baseline###

$baseline = Get-Baseline -Name 'HPE ESXi v6.7 Management Bundle v3.4.0.14'
Add-EntityBaseline -Entity $newhost -Baseline $baseline
#Test-Compliance -Entity $newhost
#$HostCompliance = Get-Compliance -Entity $newhost -Baseline $baseline

#if ($HostCompliance.Status -ne 'Compliant')
#{
  Update-Entity –Entity $newhost –Baseline $baseline –HostFailureAction Retry –HostNumberOfRetries 3 -HostDisableMediaDevices $true -Confirm:$false  
#}
#else
#{
#  Restart-VMHost $newhost -Confirm:$false  
#}
