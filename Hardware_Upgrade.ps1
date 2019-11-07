# Import VMware Modules
Get-Module -Name VMware* -ListAvailable | Import-Module

#Connect to vCenter Server
Connect-VIServer vt0pvcsa01.aqrcapital.com


$VMs = Import-CSV "C:\aqr\Hardware_Upgrade\CHG0043679\CHG0043679.csv"
$Outdated_Tools = @()
$VMs_Ok_To_Process = @()


foreach($vm in $VMs){
    $Current_VM = Get-VM $vm.VMName
    If ($Current_VM.ExtensionData.Guest.ToolsVersionStatus -eq "guestToolsCurrent"){
        Shutdown-VMGuest $vm.VMName -Confirm:$false
        Write-Host "Shutting down VM :" $vm.VMName
        $VMs_Ok_To_Process +=$Current_VM
    }
    else {
        $Outdated_Tools +=$Current_VM
        Write-Host "Tools Not Current for VM" $Current_VM
    }
}

Sleep 60


$Processed = @()
$Skipped = @()
$Problem = @()

foreach($vm in $VMs_Ok_To_Process){
    $Current_VM = Get-VM $vm
    If ($Current_VM.PowerState -eq "PoweredOff") {
        Try {
            Set-VM $Current_VM -Version v14 -Confirm:$false -erroraction stop
            Write-Host "Upgrading Hardware Version for VM :" $Current_VM
            $Processed +=$Current_VM
        }
        Catch {
			# It Failed...
			$Problem +=$Current_VM
            Write-Host "Hardware Upgrade failed for VM" $Current_VM
        }
    }
    else {
        $Skipped +=$Current_VM
        Write-Host $Current_VM "Is still powered on"
    }
}

foreach($vm in $Processed){
    Start-VM $vm -Confirm:$false
    Write-Host "Powering on VM :" $vm
}
$Outdated_Tools | Out-File -LiteralPath "C:\aqr\Hardware_Upgrade\CHG0043679\Outdated_Tools.txt"
$VMs_Ok_To_Process | Out-File -LiteralPath "C:\aqr\Hardware_Upgrade\CHG0043679\VMs_Ok_To_Process.txt"
$Processed | Out-File -LiteralPath "C:\aqr\Hardware_Upgrade\CHG0043679\Processed.txt"
$Skipped | Out-File -LiteralPath "C:\aqr\Hardware_Upgrade\CHG0043679\Skipped.txt"
$Problem | Out-File -LiteralPath "C:\aqr\Hardware_Upgrade\CHG0043679\Problem.txt"
