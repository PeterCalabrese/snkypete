#Requires -Version 3
#Requires -RunAsAdministrator
<#
	.SYNOPSIS
		Automation task for Setting the Cores per Socket to match the Total Cores for a given list of Target VMs.
	.INPUTS
		This Script requires the script path location of a Text file of Target VM Names
	.OUTPUTS
		This script does not output any objects or information.
	.PARAMETER VIServer
		Name of the vCenter server to connect to. Default = 'vt0pvcvdi01.aqrcapital.com'
	.PARAMETER SkipPowerOn
		Switch to skip power on, and will leave the targeted machine powered off.
	.NOTES
        ----------
        Tasks:
        ----------
        1. Query the admin for Text file of target VMs
        2. Check Power State of VM -- Shuts down VM gracefully
        3. Checks and sets the cores per socket
        4. Powers back on VM if Power State was previously on.
	

DEPENDENCIES : 
	- Appropriate Access levels for VMWare VI server	- VMware PS Snap-in vmware.vimautomation.core

	- UDF PowerShell Library File: STD_PSLibrary.psm1
	- UDF PowerShell Library File: STD_PSMail.ps1
	- AQR Load PowerCLI: AQR-LoadPowerCLI.ps1



Revision History

 Date           Personnel        Version      Comments
 ----           ---------        -------      --------
 05/07/2019     G. Chew          1.0.0        Script Created
 05/24/2019     G. Chew          1.0.1        Added SkipPowerOn Flag
 05/28/2019     G. Chew          1.0.2        Added force shutdown in case Tools is not running
#>
[cmdLetBinding()]
Param (
	[Parameter(Mandatory = $false)]
	[string]$VIServer = "vt0pvcvdi01.aqrcapital.com",
	[Parameter(Mandatory = $false)]
	[switch]$SkipPowerOn
)

# PS 3.0+
$ScriptDir = (Get-Item $PSCommandPath).DirectoryName
$ScriptName = (Get-Item $PSCommandPath).Basename

$DateStamp = Get-Date -UFormat "%Y-%m-%d_%H-%M"
$DateStampSec = Get-Date -UFormat "%Y-%m-%d_%H-%M-%s"

# ==========================
# Include Library functions
# ==========================
#region Includes
$librarypath = '\\aqrcapital.com\shares\FS007\SysAdmin\Scripts\PRD\lib\'
## $librarypath = "$($ScriptDir)\lib\"
Write-Verbose "Library Path: $($librarypath)"

$error.Clear()
Try {
	
	Write-Verbose "Loading Library File: $($librarypath)STD_PSLibrary.psm1"
	Import-Module "$($librarypath)STD_PSLibrary.psm1" ## GRC Standard Library Functions
	
	Write-Verbose "Loading Library File: $($librarypath)STD_PSMail.ps1"
	. "$($librarypath)STD_PSMail.ps1" ## GRC Email Functions
	
	Write-Verbose "Loading VMware PS-Snapins"
	. "$($librarypath)\AQR-LoadPowerCLI.ps1" ## Load PowerCLI
	
} Catch [System.Management.Automation.PSArgumentException] {
	
	Write-Error "One or more library files could not be loaded. Please check and try again."
	Exit
	
} Catch [System.IO.FileNotFoundException] {
	
	Write-Error "One or more library files were not found. Please check and try again."
	Exit
	
} Finally {
	
	Write-Host "Library files have been loaded successfully."
	
}
$UseVMWareVI = Load-AQRPowerCLI
If (!$UseVMWareVI) {
	Write-Host "Warning: Could not load PowerCLI. Cannot continue."
	Exit
}
#endregion

## =====================================================================================
## UDFS
#region UDF

# -------------------------------------------------------
# Function:   Get-FileName
# Decription: Retrieves File Text path and name utilizing
#             File Open Windows Dialog
#
# Inputs:     InitialDirectory - Initial directory to query
#             title = title for the dialog box
# Dependencies:
# -------------------------------------------------------
Function Get-FileName () {
	
	Param (
		[Parameter(Mandatory = $true)]
		[String]$initialdirectory,
		[Parameter(Mandatory = $false)]
		[String]$title = "Select Input Text File"
	)
	
	[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
	$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$OpenFileDialog.InitialDirectory = $initialdirectory
	$OpenFileDialog.filter = "Text Files (*.txt)|*.txt"
	$OpenFileDialog.ShowHelp = $false
	$OpenFileDialog.Title = $title
	$OpenFileDialog.ShowDialog() | Out-Null
	
	Return $OpenFileDialog.FileName
	
}

Function Exit-AQRScript ([string]$LogFile, $VISession, $ViewSession) {
	
	WriteToLog $logfile "End Execution"
	WriteToLog $logfile $sep1
	## Exit-PSSession -ErrorAction SilentlyContinue
	
	If ($VISession) {
		WriteToLog $logfile "Disconnecting from vSphere"
		Disconnect-VIServer -Server $VISession -Force -Confirm:$false -ErrorAction SilentlyContinue
	}
	
	If ($ViewSession) {
		WriteToLog $logfile "Disconnecting PSSession"
		Remove-PSSession -Session $ViewSession -ErrorAction SilentlyContinue
	}
	
	Exit
}


#endregion
## UDFS
## =====================================================================================


# =====================
# AQR Variables
# =====================
$AQRFunction = "VM_SetCoresPerSocket"
$ScriptVersion = "1.0.2"
## Current User executing script
$Admin = $env:Username

# =====================
# Read INI
# =====================
#region Read INI
## Read INI file
$inifile = "$($ScriptDir)\$($ScriptName).ini"
If (!(Test-Path -Path $inifile)) {
	Write-Host "INI file not found: $($inifile)" -foregroundcolor Red
	Exit
}

Write-Host "Reading INI File: $($inifile)"
$AQRini = Get-IniContent "$($inifile)"

## Verbosity, What-Ifness, Debug output
$IsDebug = $AQRini["Main"]["DebugMode"]
$IsVerbose = $AQRini["Main"]["Verbose"]
$IsWhatIf = $AQRini["Main"]["WhatIf"]

If ($IsDebug -eq 1) {
	$DebugMode = $True
} Else {
	$DebugMode = $False
}
If ($IsVerbose -eq 1) {
	$VerbosePreference = "Continue"
} Else {
	$VerbosePreference = "SilentlyContinue"
}
If ($IsWhatIf -eq 1) {
	$WhatIfPreference = $True
} Else {
	$WhatIfPreference = $False
}

## Common Variables
$VMWareDomain = $AQRini["Common"]["VMWareDomain"] ## VMware domain (e.g. aqrcapital.com)

## Email variables
$MailFrom = $AQRini["Email"]["MailFrom"]
$MailTo = $AQRini["Email"]["MailTo"]
$MailCC = $AQRini["Email"]["MailCC"]
$MailBCC = $AQRini["Email"]["MailBCC"]
$MailServer = $AQRini["Email"]["MailServer"]
$MailSubject = $AQRini["Email"]["MailSubject"]

## some CSS hacking
$CSS = $strStyleCSS -replace "table.report", "table"
$CSS = $CSS -replace "table th", "th"
$CSS = $CSS -replace "table tr", "tr"

#endregion

# =====================
# Logging Variables
# =====================
#region Logging
# Set report output directory
$outputDir = $AQRini["Main"]["LogDir"]

If (!(Test-Path -Path $outputDir)) {
	New-Item -ItemType directory -Path $outputDir
}
If (!($outputDir.EndsWith("\"))) {
	$outputDir = "$($outputDir)\"
}

$Year = Get-Date -uformat "%Y"
$outputDir = "$($outputDir)$($Year)\"
If (!(Test-Path -Path $outputDir)) {
	New-Item -ItemType directory -Path $outputDir
}

$resultDir = "$($PSScriptRoot)\Results\"
If (!(Test-Path -Path $resultDir)) {
	New-Item -ItemType directory -Path $resultDir
}

# Set date format for use in file name
$date = Get-Date -uformat "%Y-%m-%d"

## Here is the Log File
$logfile = $outputDir + "$($AQRFunction)_$($DateStampSec).log"
Write-Host "Log file: $logfile" -ForegroundColor Cyan

$sep1 = "=" * 75
$sep2 = "*" * 38
#endregion


## =================================================================================================
## =================================================================================================
## =================================================================================================
## =================================================================================================

WriteToLog $logfile $sep1
WriteToLog $logfile "Begin Execution"
WriteToLog $logfile "Script Version: $($ScriptVersion)"
WriteToLog $logfile "Parameters-"
WriteToLog $logfile "Executor: $($Admin)"
WriteToLog $logfile "VMWare VI Server: $($VIServer)"
WriteToLog $logfile "Skip Power On:    $($SkipPowerOn)"

## ==========================
## VMware stuff
## ==========================
#region Connect vCenter
WriteToLog $logfile "Connecting to vSphere: $($VIServer)"
$Error.clear()
Try {
	
	$VIObj = Connect-VIServer -Server $VIServer -WarningAction SilentlyContinue -ErrorAction Stop
	
} Catch {
	
	$err1 = $error[0]
	WriteToLog $logfile "Could not connect!" 5
	WriteToLog $logfile $err1.Exception.Message 5
	Exit-AQRScript $logfile
}
#endregion

## ==========================
## Ask for Input File
## ==========================
#region Ask for Input File
$DefaultInputFileDir = $ScriptDir
WriteToLog $logfile "Asking for Input File from Admin"
$InputFile = Get-FileName -InitialDirectory $DefaultInputfileDir -title "Select an Input File"

If (!$InputFile) {
	
	WriteToLog $logfile "Input File not Specified."
	Exit-AQRScript $LogFile -VISession $VIObj
	
} Else {
	
	WriteToLog $logfile "Input File: $($InputFile)"
	
}

## Read Input File
WriteToLog $logfile "Reading file"
$Error.clear()
Try {
	
	$TargetComputers = Get-Content -Path $InputFile -Force -ErrorAction Stop
	
} Catch {
	
	$err1 = $error[0]
	WriteToLog $logfile "Could not read input file!" 5
	WriteToLog $logfile $err1.Exception.Message 5
	Exit-AQRScript $logfile
}
#endregion

## ==========================
## Input File Iteration
## ==========================
#region MAIN
$ResultsCollection = @()
foreach ($computer in $TargetComputers) {

    $VMView = $VM = $TotalCPU = $CoresperSocket = $null

    $ResultObject = New-Object -TypeName psobject
    Add-Member -InputObject $ResultObject -MemberType NoteProperty -Name 'Computer' -Value $Computer
	Add-Member -InputObject $ResultObject -MemberType NoteProperty -Name 'PowerState' -Value ''
    Add-Member -InputObject $ResultObject -MemberType NoteProperty -Name 'TotalCores' -Value ''
    Add-Member -InputObject $ResultObject -MemberType NoteProperty -Name 'CoresperSocket' -Value ''
	Add-Member -InputObject $ResultObject -MemberType NoteProperty -Name 'ToolsRunning' -Value ''
    Add-Member -InputObject $ResultObject -MemberType NoteProperty -Name 'PowerOff' -Value ''
    Add-Member -InputObject $ResultObject -MemberType NoteProperty -Name 'SetCoresperSocket' -Value ''
    Add-Member -InputObject $ResultObject -MemberType NoteProperty -Name 'PowerOn' -Value ''

    WriteToLog $logfile $sep1 3

    ## ===============================
    ## Get the VM View
    ## ===============================
    $filter = @{
        ## "Runtime.PowerState" ="poweredOn";
        ## "Summary.Guest.GuestId"="windows9_64Guest";
        "Name"="^$($computer)$"
        }
    $VMView = Get-View -Server $VIObj -ViewType VirtualMachine -Filter $filter

    If (!($VMView)){

        WriteToLog $logfile "$($Computer) - Not found"
        $ResultObject.PowerState = "Not Found"

    } else {

        WriteToLog $logfile "$($Computer) - Total Cores = $($VMView.Config.Hardware.numCPU) - Cores/Socket = $($VMView.Config.Hardware.NumCoresPerSocket)" 2

        $ResultObject.PowerState     = $VMView.Summary.Runtime.PowerState
        $ResultObject.TotalCores     = $VMView.Config.Hardware.numCPU
        $ResultObject.CoresperSocket = $VMView.Config.Hardware.NumCoresPerSocket
		$ResultObject.ToolsRunning   = $VMView.Guest.ToolsRunningStatus
		
        ## GRC
		If ($ResultObject.TotalCores -eq $ResultObject.CoresperSocket) {
			
			$mesg = "Cores per socket is already equal to $($ResultObject.TotalCores)"
			WriteToLog $logfile $mesg 2
			$ResultObject.SetCoresperSocket = $mesg
			
		} Else {
			
			$mesg = "Processing..."
			WriteToLog $logfile $mesg 2
			
			## ===========================================
            WriteToLog $logfile "Getting VM object"
            ## ===========================================
            #region Get VM Object
            $error.clear()
            Try {

                $VM = Get-VM -Name $ResultObject.Computer -Server $VIObj -ErrorAction Stop

            } Catch {

                $err1 = $error[0]
                $mesg = "ERROR - $($err1.Exception.Message)"
                WriteToLog $logfile $mesg 5
                $ResultObject.PowerOff = $mesg
                $ResultObject.SetCoresperSocket = "SKIPPED"
				$ResultObject.PowerOn = "SKIPPED"
				$ResultsCollection += $ResultObject
				Continue

            }
            #endregion

            ## ========================================
            ## Shut down the VM if powered On
            ## ========================================
            #region Shut down VM
			If ($VM.PowerState -eq 'PoweredOff') {
				
				WriteToLog $logfile "VM is not Powered On"
				$ResultObject.PowerOff = "Already powered off"
				
			} else {
				
				WriteToLog $logfile "Powering down VM."
				
                $error.clear()
                Try {
					
					If ($ResultObject.ToolsRunning = "guestToolsRunning") {
						
						WriteToLog $logfile "Sending graceful shutdown"
						Stop-VMGuest -VM $VM -Confirm:$false -ErrorAction Stop
						
					} Else {
						
						WriteToLog $logfile "Sending force power-off" 2
						Stop-VM -VM $VM -Server $VIObj -Confirm:$false -ErrorAction Stop
						
					}
                    

                } Catch {

                    $err1 = $error[0]
                    $mesg = "ERROR - $($err1.Exception.Message)"
                    WriteToLog $logfile $mesg 5
                    $ResultObject.PowerOff = $mesg
                    $ResultObject.SetCoresperSocket = "SKIPPED"
                    $ResultObject.PowerOn = "SKIPPED"
					$ResultsCollection += $ResultObject
					Continue
					
                }
    
                While ($VMView.runtime.PowerState -ne 'PoweredOff') {

                    WriteToLog $logfile "Waiting until powered off..." 4
                    Start-Sleep -Seconds 5
                    $filter = @{
                        "Name"="^$($computer)$"
                        }
                    $VMView = Get-View -Server $VIObj -ViewType VirtualMachine -Filter $filter

                }
                $ResultObject.PowerOff = "OK"

            } 
            #endregion

            ## ========================================
            ## Set Cores per socket
            ## ========================================
			#region Set Cores per Socket
			$TotalCPU = [int]$VM.NumCpu
			$CoresperSocket = $TotalCPU
			
			WriteToLog $logfile "Setting Cores per socket to $($CoresperSocket)"
			$error.clear()
			Try {
				
				$VM = Set-VM -VM $VM -CoresPerSocket $CoresperSocket -NumCpu $TotalCPU -Server $VIObj -Confirm:$false -ErrorAction Stop
				
			} Catch {
				
				$err1 = $error[0]
				$mesg = "ERROR - $($err1.Exception.Message)"
				WriteToLog $logfile $mesg 5
				$ResultObject.SetCoresperSocket = $mesg
				$ResultObject.PowerOn = "SKIPPED"
				$ResultsCollection += $ResultObject
				Continue
				
			}
			
			$ResultObject.SetCoresperSocket = "OK"
			WriteToLog $logfile "OK"
			#endregion

            ## ========================================
            ## Power back on
            ## ========================================
			#region Power Back On
			If ($SkipPowerOn) {
				
				$mesg = "SKIPPED, SkipPowerOn Flag is Set"
				$ResultObject.PowerOn = $mesg
				WriteToLog $logfile $mesg
				
			} ElseIf ($ResultObject.PowerState -ne "PoweredOn") {
				
				$mesg = "SKIPPED, VM Was not originally powered on"
				$ResultObject.PowerOn = $mesg
				WriteToLog $logfile $mesg
				
			} Else {
				
				If ($VM.PowerState -ne 'PoweredOff') {
					
					$mesg = 'Already powered on'
					$ResultObject.PowerOn = $mesg
					WriteToLog $logfile $mesg
					
				} else {
				
					WriteToLog $logfile "Powering on VM."
					$error.clear()
					Try {
						
						$VM = Start-VM -VM $VM -Server $VIObj -Confirm:$false -ErrorAction Stop -RunAsync
						
					} Catch {
						
						$err1 = $error[0]
						$mesg = "ERROR - $($err1.Exception.Message)"
						WriteToLog $logfile $mesg 5
						$ResultObject.PowerOn = $mesg
						$ResultsCollection += $ResultObject
						Continue
						
					}
					
					$ResultObject.PowerOn = "OK"
					
				}
				
			}
				
			#endregion

        }

    }

    $ResultsCollection += $ResultObject

}
#endregion

WriteToLog $logfile $sep1 3

## ===========================
## Save / Send report
## ===========================
#region Save Results
$ReportName = "$($AQRFunction)_$($DateStampSec)"
$ReportCSV = "$($resultDir)$($ReportName).csv"

For ($i = 1; $i -le 20; $i++) {
	
	If (Test-Path -Path $ReportCSV) {
		$ReportCSV = "$($resultDir)$($ReportName)_$i.csv"
	}
	
}

## Converting Results
WriteToLog $logfile "Converting results to CSV"
$ResultsCollection | Export-Csv -Path $ReportCSV -NoTypeInformation -Force
WriteToLog $logfile "Converting results to HTML"
$ReportHTML = $ResultsCollection | ConvertTo-Html -Head $CSS

$ReportHTML = $ReportHTML -replace '<td>Timeout</td>', '<td class="dataError">Timeout</td>'
$ReportHTML = $ReportHTML -replace '<td>ERROR', '<td class="dataError">Error'

If ($DebugMode) {
	$htmlfile = "$($resultDir)\$($ReportName).html"
	WriteToLog $logfile "Saving HTML: $($htmlfile)"
	
	$ReportHTML | Out-File $htmlfile
}

$ReportHTML += "<br /><br />Sent From: $($ENV:COMPUTERNAME)"
#endregion

## ================================================================
## Send E-Mail
## ================================================================
#region Send mail result
WriteToLog $logfile "Sending Email"

## $MailBody = "CSV File attached: $ReportCSV"

$MailParams = @{
	ServerName  = $MailServer;
	Subject	    = $MailSubject;
	To		    = $MailTo;
	From	    = $MailFrom;
	CC		    = $MailCC;
	BCC		    = $MailBCC;
	attachments = @($ReportCSV);
	Body	    = $ReportHTML
}

$rslt = Send-AQRHTMLEmail @MailParams


If (!$rslt) {
	
	WriteToLog $logfile "SUCCESS"
	
} Else {
	
	WriteToLog $logfile "ERROR sending email: $($rslt[0].Exception.Message)"
	
} # If
#endregion

Exit-AQRScript $LogFile -VISession $VIObj 

## ================================================================================================
## ================================================================================================
## ================================================================================================
## ================================================================================================

