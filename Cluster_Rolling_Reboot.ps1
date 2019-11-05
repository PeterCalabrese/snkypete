<#
.Synopsis
   Cluster Rolling Reboot Script.
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
   .\Cluster_Rolling_Reboot.ps1 -vcenter vt0pvcsa01.aqrcapital.com -cluster VSI_A
.EXAMPLE
   .\Cluster_Rolling_Reboot.ps1 -vcenter vt0pvcvdi01.aqrcapital.com -cluster TRM_VDI_1
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

Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true, 
                   Position=0)]
        $vcenter,
     
        [Parameter(Mandatory=$true, 
                   Position=1)]
        $cluster,
        [string]$test
    )

<#
param (
    [string]$vcenter,	
    [string]$cluster,
	[string]$test
)
#>
 
 ###Credentials###
  . .\lib\Get-PIMSecret.ps1
$vSphere_Username = 'administrator@vsphere.local'
$vSphere_Password = $(Get-PIMSecret -SecretId '2484').secret

###Alarm Information###
$alarmMgr = Get-View AlarmManager

#changes:  email comma issue, host not vmotion after reboot workaround, add evac retry

# make sure everything is here for VMware
Get-Module -Name VMware* -ListAvailable | Import-Module
<#import-module vmware.vimautomation.cis.core
import-module vmware.vimautomation.core
import-module vmware.vimautomation.ha
import-module vmware.vimautomation.sdk
import-module vmware.vimautomation.storage
import-module vmware.vimautomation.vds
#>

# see if connected, it not, connect and auth via kerberos

if ($test) {
	write-host "Test mode"
	$to="peter.calabrese@aqr.com"
	$mode=$true
}
else {
	$to=@("tim.jackson@aqr.com","peter.calabrese@aqr.com")
	$mode=$false
}


$check=$false
foreach ($vc in $defaultviservers) {
  if ($vc.name -match "vt0*") {
     $check=$true
  }
}


$starttime=get-date

if ($check) {
   write-host "Connected to $vcenter"
}
else {
	try {
		connect-viserver -server $vcenter -erroraction stop -user $vSphere_Username -password $vSphere_Password
	}
	catch {
		write-host "Cannot connect to vCenter : NOT Connected to $vcenter"
		exit 10
	}
}

try {
  $q=get-cluster $cluster -erroraction stop
}
catch {
	write-host "Please specify -cluster <cluster> to specify which cluster to reboot.  For NPP: SQLCluster02_210 or SQLCluster03_210"
	exit 5
}

write-host "Script starting $starttime"

send-mailmessage -to $to -subject "Cluster Rolling reboots starting for $cluster"   -body "Starting on $cluster...email when complete" -Smtpserver mailrelay.aqrcapital.com -from peter.calabrese@aqr.com

$clustername=$cluster
$done=@()
$phase=@("Maintenance","NotResponding","Maintenance")
$vhosts=get-cluster $clustername|get-vmhost|where-object {$_.connectionstate -eq "Connected"}|sort-object name
$bad=$false
$index=0
# the meat of this thing
foreach ($h in $vhosts) {
	# go to the each host, spread the load around
	# check the uptime...
	$tu=$(get-date).touniversaltime().subtract($h.extensiondata.runtime.boottime).totalhours
	if ( $tu -lt 0) {
		write-host "Skipping $h, uptime $tu hours"
	}
	else {
		$hvm=get-vmhost $h|get-vm|where-object {$_.powerstate -eq "PoweredOn"}
		$lct=0
		$f=$cluster + "_" + $h.name + ".txt"
		$hvm|select name|export-csv -path $f
		write-host "$h is current host, vhost.count is" $vhosts.count "hvm.count is "$hvm.count
		foreach ($v in $hvm) {
			if ($lct -gt $vhosts.count-1) {
				$lct=0
			}
			$ch=$vhosts[$lct].name
			$chh=$h.name
			#write-host "1$ch 2$chh 3 $lct"
			if ( $ch -eq $chh) {
				# skip the current host
				write-host "skipping $h $chh $ch"
				$lct++
			}
			if ($lct -gt $vhosts.count-1) {
				$lct=0
			}
			write-host "Moving $v to "$($vhosts[$lct].name)" and $lct"
			$q=move-vm $v -destination $($vhosts[$lct].name) -runasync:$true -whatif:$mode
			$lct++
		}
		$waiting=$true
		$timer=0
		write-host "Waiting for guests to move..."
		$skiphost=$false
		while ($waiting) {
			$cct=get-vmhost $h|get-vm|where-object {$_.powerstate -eq "PoweredOn"}
			if ($cct.count -eq 0) {
				$waiting=$false
			}
			else {
				write-host "Guests remaining:  " $cct.count
			}
			$timer++
			start-sleep -seconds 30
			if ($timer -gt 30) {
				# timeout...abend and alert..
				write-host "hit timeout...trying anger mode"
				# add anger mode...
				# pick a host, we reboot in numeric order so below is best unless
				# going single threaded
				$tgh=$vhosts[$($index-1)]
				foreach ($tt in $(get-vmhost $h|get-vm|where {$_.powerstate -eq "PoweredOn"})) {
					move-vm $tt -destination $tgh -whatif:$mode
				}
				if ($(get-vmhost $h|get-vm|where-object {$_.powerstate -eq "PoweredOn"}) -ne 0) {
					# something bad, we cannot empty out the host, send an email and skip this host
					$result="Cannot evacuate host $h, skipping"
					send-mailmessage -to $to -subject "Cluster Rolling reboot error"   -body $result -Smtpserver mailrelay.aqrcapital.com -from peter.calabrese@aqr.com
					$skiphost=$true
				}

			}
		}
		if (-not $skiphost) {
			# reboot the host
			write-host "Disabling Alarms and setting maintenance mode"
			$q=set-vmhost $h -state maintenance
            $DisableAlarms=$alarmMgr.EnableAlarmActions($h.Extensiondata.MoRef,$false)
			write-host "Rebooting host"
			$q=restart-vmhost $h -confirm:$false
			# wait for host to go away
			$phasect=0
			write-host "Entering phase check, waiting for host reboot return"
			while ($phasect -lt $phase.count) {
				$t=get-vmhost $h -erroraction silentlycontinue
				if ($t.connectionstate -eq $phase[$phasect]) {
					write-host $phase[$phasect]
					$phasect++
				}
				start-sleep -seconds 30
			}
			# host is back
			write-host "$h has returned from reboot, enabling alarms and setting connected"
            $EnableAlarms=$alarmMgr.EnableAlarmActions($h.Extensiondata.MoRef,$true)
			$q=set-vmhost $h -state connected
			# make sure we can vmote to rebooted host, there is a delay there...
			start-sleep -seconds 30
		}
		# this code is required as a host will not accept VM's for a while after reboot
		$testing=$true
		while ($testing) {
			try {
				$q=move-vm $hvm[0] -destination $h -erroraction stop
				$testing=$false
			}
			catch {
				# it failed...
				write-host "Waiting on host $h to be fully operational"
				start-sleep -seconds 60
			}
		}
		
		# then put back once rebooted
		foreach ($v in $hvm) {
			write-host "Moving $v to $h"
			$q=move-vm $v -destination $h -runasync:$true
		}
	}
	# end of the meat
	$index++
}

$endtime=get-date

$result="Start time $starttime`nEnd time $endtime"
$diff=$endtime.subtract($starttime)
[int]$d=$diff.totalminutes
$result+="`nTotal runtime in minutes $d`n`n"

foreach ($vv in $(get-cluster $cluster|get-vmhost|sort name)) {
   $st=$(get-date).touniversaltime()
   [int]$uptime=$st.subtract($vv.extensiondata.runtime.boottime).totalhours
   $result+= $vv.name + " " + $uptime + " hours`n"
}

send-mailmessage -to $to -subject "Cluster Rolling reboot complete for $cluster"   -body $result -Smtpserver mailrelay.aqrcapital.com -from peter.calabrese@aqr.com
