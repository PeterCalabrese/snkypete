<#Get-Cluster 'VSI_TRM_NonPRD' | get-vm | where {$_.powerstate -ne "PoweredOff" } | % { get-view $_.id } | select Name, @{ Name="ToolsVersion"; Expression={$_.config.tools.toolsVersion}},@{ Name="ToolStatus"; Expression={$_.Guest.ToolsVersionStatus}}



Get-Cluster 'VSI_TRM_NonPRD' | get-vm | Where {$_.Guest -match "Windows" -and $_.powerstate -ne "PoweredOff" -and $_.config.tools.ToolsVersion -eq "9541"}

 -and $_.powerstate -eq "PoweredOn"}

 get-vm 
#>


 Get-Cluster 'VSI_B' | get-vm | Where {$_.Guest -match "Windows" -and $_.powerstate -ne "PoweredOff"} | Get-VMGuest | Select VMName, OSFullName, ToolsVersion | Export-CSV H:\Projects\Tools_Upgrade\VSI_B.csv -NoTypeInformation -UseCulture


 Get-VM | Where-Object { $_.Name -like 'vt0pcma*'} | Select Name, @{N="ESX Host";E={Get-VMHost -VM $_}}
 
 Get-VM | Where-Object { $_.Name -like '*sql*'} | Select Name, @{N="ESX Host";E={Get-VMHost -VM $_}} | sort Name | Export-CSV H:\Projects\Tools_Upgrade\Prod_SQL_Servers.csv -NoTypeInformation -UseCulture


 $Date = Get-Date
$HAVMrestartold =5
Get-VIEvent -maxsamples 100000 -Start ($Date).AddDays(-$HAVMrestartold) -type warning | Where {$_.FullFormattedMessage -match "restarted"} |select CreatedTime,FullFormattedMessage |sort CreatedTime -Descending

Get-Module -Name VMware* -ListAvailable | Import-Module


get-motionhistory -Entity (get-cluster "TRM_VDI_2" | get-vm) -Days 2 | Export-csv -NoTypeInformation -UseCulture H:\vmotions\TRM_VDI_2.csv

Get-Cluster "TRM_VDI_1" | Get-MotionHistory -Hours 24 -Recurse:$true | Export-Csv H:\vMotions\2019_02_14_TRM_VDI_1.csv -NoTypeINformation -UseCulture




Get-VMHost | Select Name,
  @{N="Uptime"; E={New-Timespan -Start $_.ExtensionData.Summary.Runtime.BootTime -End (Get-Date) | Select -ExpandProperty Days}}


  $view = (Get-VMHost $vmHost | Get-View)
(Get-View $view.ConfigManager.PowerSystem).ConfigurePowerPolicy(1)



Get-VMHost | Select Name, @{N='Power Technology';E={$_.ExtensionData.Hardware.CpuPowerManagementInfo.HardwareSupport}}, @{N='Current Policy';E={$_.ExtensionData.Hardware.CpuPowerManagementInfo.CurrentPolicy}}
