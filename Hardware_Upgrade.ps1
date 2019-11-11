<#
.Synopsis
   Hardware Upgrade script for Windows VMs
.DESCRIPTION
   This script takes an input file of VMs and performs the following :
        1. Confirms the Hardware Version requires updating
        2. Confirms VMTools is up to date
        3. Checks to see if the VM is powered off
        4. Powers off the VM, upgrades the Hardware Version, Powers it back on.
.EXAMPLE
   .\HardwareUpgrade.ps1 -vCenter vt0pvcsa01.aqrcapital.com -changeID CHG0043706
.INPUTS
   A .CSV Input file is required with the name of the change, in a folder named for the change as well.  The VM column should have the header 'VMName'
.OUTPUTS
   Text files are generated in the folder with the results for each VM
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
        $vCenter,

        [Parameter(Mandatory=$true, 
                   Position=1)]
        $changeID
    )

# Import VMware Modules
Get-Module -Name VMware* -ListAvailable | Import-Module

#Connect to vCenter Server
Connect-VIServer $vCenter

#Determine if Working Path is Valid
$WorkPath = "C:\aqr\Hardware_Upgrade\" + $changeID + "\"
If (-not (Test-Path $WorkPath)){
    Write-Host 'The Working Directory Does Not Exist' -ErrorAction Stop
} else {
    Write-Host 'The Working Directory is Valid' 
}

##########
#Execute Hardware Upgrade Process
##########

$VMs = Import-CSV $WorkPath + $changeID + ".csv"

##########
#Create Text Files
##########

$Misconfigured_VM = @()
$VMs_Ok_To_Process = @()
$Processed = @()
$Skipped = @()
$Problem = @()

##########
#Determine if VMTools are Current and Hardware Version requires upgrading.  If so POWER OFF the VM
##########

foreach($vm in $VMs){
    $Current_VM = Get-VM $vm.VMName
    If (($Current_VM.ExtensionData.Guest.ToolsVersionStatus -eq "guestToolsCurrent") -and ($Current_VM.ExtensionData.Config.Version -ne "vmx-14")){
        Shutdown-VMGuest $vm.VMName -Confirm:$false
        Write-Host "Shutting down VM :" $vm.VMName
        $VMs_Ok_To_Process +=$Current_VM
    }
    else {
        $Misconfigured_VM +=$Current_VM
        Write-Host $Current_VM "is being skipped"
    }
}

Sleep 20

##########
#Upgrade the Hardware Version
##########

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

##########
#Power ON the VM
##########

foreach($vm in $Processed){
    Start-VM $vm -Confirm:$false
    Write-Host "Powering on VM :" $vm
}

##########
#Write Output Files
##########

$Misconfigured_VM | Out-File -LiteralPath $WorkPath + "Misconfigured_VM.txt"
$VMs_Ok_To_Process | Out-File -LiteralPath $WorkPath + "VMs_Ok_To_Process.txt"
$Processed | Out-File -LiteralPath $WorkPath + "Processed.txt"
$Skipped | Out-File -LiteralPath $WorkPath + "Skipped.txt"
$Problem | Out-File -LiteralPath $WorkPath + "Problem.txt"
