<#

.SYNOPSIS
Get the storage location of all Hyper-V VMs in a cluster. This script must be run on a Hyper-V Cluster node


.PARAMETER ClusterName
    [Optional] Name of the Windows Hyper-V Cluster to examine. If not specified an attempt will be made to use the local cluster name

.PARAMETER ResultsFilePath
    [Optional] A file path to save the results to.  By default this is %temp%\ps_HyperV_GetVMStorageLocationResults.csv


.EXAMPLE

.\ps_HyperV_GetVMStorageLocation.ps1

This will check for the existance of a local cluster and will use the default ResultsFilePath location

.EXAMPLE

.\ps_HyperV_GetVMStorageLocation.ps1 -ClusterName MyClusterName

This will attempt to use the cluster called MyClusterName

.EXAMPLE

.\ps_HyperV_GetVMStorageLocation.ps1 -ResultsFilePath c:\temp\myResults.csv

This will check for the existance of a local cluster and will use the default ResultsFilePath location c:\temp\myResults.csv

It is recommended to save the results as .csv as this is format used for the results

.EXAMPLE

.\ps_HyperV_GetVMStorageLocation.ps1 -ClusterName MyClusterName -ResultsFilePath c:\temp\myResults.csv

This will attempt to use the cluster called MyClusterName and will save the results to c:\temp\myResults.csv

.NOTES
If you receive an error about not having permission to save to the temp folder then specify the ResultsFilePath manually

MVogwell - 06-05-19 - v1.0

#>

[CmdLetBinding()]
param (
        [Parameter(Mandatory=$false)][string]$ClusterName = "",	
		[Parameter(Mandatory=$false)][string]$ResultsFilePath = $($Env:Temp) + "\ps_HyperV_GetVMStorageLocationResults.csv"
)

$ErrorActionPreference = "Stop"

Function ps_Function_CheckRunningAsAdmin {
    [CmdletBinding()]
    param()

    # Constructor
    [bool]$bRunningAsAdmin = $False
    
    Try {
        # Attempt to check if the current powershell session is being run with admin rights
        # System.Security.Principal.WindowsIdentity -- https://msdn.microsoft.com/en-us/library/system.security.principal.windowsidentity(v=vs.110).aspx
        # Info on Well Known Security Identifiers in Windows: https://support.microsoft.com/en-gb/help/243330/well-known-security-identifiers-in-windows-operating-systems
        
        Write-Verbose "ps_Function_CheckRunningAsAdmin :: Checking for admin rights"
        $bRunningAsAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
    }
    Catch {
        $bRunningAsAdmin = $False
        Write-Verbose "ps_Function_CheckRunningAsAdmin :: ERROR Checking for admin rights in current session"
        Write-Verbose "ps_Function_CheckRunningAsAdmin :: Error: $($Error[0].Exception)"
    }
    Finally {}
    
    Write-Verbose "ps_Function_CheckRunningAsAdmin :: Result :: $bRunningAsAdmin"
    
    # Return result from function
    return $bRunningAsAdmin
    
}

Function CreateResultsFile {
	Param (
		[Parameter(Mandatory=$true)][string]$OutputFile,
		[Parameter(Mandatory=$true)][ref]$ErrorMsg,
		[Parameter(Mandatory=$true)][bool]$AllowAppend
	)

	##############################
	#
	# Function to create a results file for a given path. Returns True if successful and False if it fails
	# MVogwell - 2022-11-24 - v1.2
	# 
	# Change log:
	#	v1: Working function
	#	v1.1: Changed params to mandatory. Added method to Append log file rather than create overwrite
	#	v1.2: Chaged write-host to write-output
	#
	##############################
	
	$ErrorActionPreference = "Stop"
	$arrAnswers = @("yes","y","no","n")
	
	$bResultsFileCreationSuccess = $True
	
	if ($OutputFile.length -eq 0) {
		$bResultsFileCreationSuccess = $False
	}
	Else {
		if (Test-Path($OutputFile)) {	# Run only if the file already exists to check if it should be overwritten
			If ($AllowAppend -eq $False) {
				Write-Verbose "File already exists. Checking with user if it should be replaced`n"
	
				Write-Output "The results output file $OutputFile already exists!"
		
				Do {
					Write-Output "Do you want to overwrite it? yes/no"
					$sOverwriteResultsFile = read-host " "
					Write-Verbose "User answer: $sOverwriteResultsFile `n"
				}
				While (!($arrAnswers.Contains($sOverwriteResultsFile.toLower())))
		
				if (($sOverwriteResultsFile -eq "n") -or ($sOverwriteResultsFile -eq "no")) {
					Write-Verbose "User selected no"
					$bResultsFileCreationSuccess = $False
					$ErrorMsg.value = "User has decided not to overwrite the existing results file"
				}
			}
			Else { # Test open file if AllowAppend has been set to True
				Try {
					[io.file]::OpenWrite($OutputFile).close()
				}
				Catch {
					$bResultsFileCreationSuccess = $False
					$ErrorMsg.value = "Unable to append the file"
				}
			}
		}	

		# Create the results file - unless allow append has been set to true
		if (($bResultsFileCreationSuccess) -and (!($AllowAppend))) {	
		
			Write-Verbose "Attempting to create the results file"
		
			Try {
				New-Item $OutputFile -ItemType File -Force | out-null
			
			}
			Catch {
				Write-Verbose "Error creating new file $($Error[0])"
		
				$bResultsFileCreationSuccess = $False
				$ErrorMsg.value = $Error[0].exception -replace ("`n"," ") -replace ("`r"," ")
			}
		}
	}

	return $bResultsFileCreationSuccess
}


#@# Main

Write-Output "`n`nps_HyperV_GetVMStorageLocation - MVogwell - Nov 2022 - v1.2`n`n"

# Check running as admin - stop script if not
$bRunningAsAdmin = ps_Function_CheckRunningAsAdmin
if(!($bRunningAsAdmin)) {
	Write-Output "You must run this script as an administrator user with elevated rights"
	Write-Output "Please re-run the script as an admin.`n`n"
}
Else {
	# Create or ask to overwrite the results file
	[bool]$bResult = $False
    [string]$ErrorMsg = ""
    
    $bResult = CreateResultsFile -OutputFile $ResultsFilePath -ErrorMsg ([ref]$ErrorMsg) -AllowAppend:$False
    
	# Only continue if creating the results file was successful
    if ($bResult) {
		$bClusterCheck = $True
		# If no cluster name is specified then attempt to retrieve it. If one is specified try to attach to it. End script on error
		Try {
			If ($ClusterName -eq "") { $ClusterName = (Get-Cluster).Name }
			Else { Get-Cluster -Name $ClusterName | out-null }
		}
		Catch {
				$bClusterCheck = $False
				Write-Output "It has not been possible to attach to the cluster '$ClusterName' or find a valid cluster"
				Write-Output "The script will now exit.`n`n"
		}

		# Get the results data - but only if the cluster could be found
		If($bClusterCheck) {
			$arrRes = @() 
			
			$arrRes += "VMName,ControllerType,ClusterStorageDiskId,Path"	# Set the headers for the csv file
			$cn = (Get-ClusterNode -Cluster $ClusterName).name 					# Get the name(s) of the cluster nodes
			foreach ($c in $cn) { 
				Write-Output "Checking VMs on $c"
				Try {
					$vms = get-vm -ComputerName $c 											# Get the VMs hosted on the Cluster Node
					foreach ($vm in $vms) { 
						foreach($hd in ($vm.harddrives)) { 
							
							#Attempt to get the Cluster Vol ID (e.g. c:\ClusterStorage\Volume1 would be 1)
							Try {
								$ClusterVolId = $(($hd.Path).substring(24,1))
							}
							Catch {
								$ClusterVolId = "n/a"
							}
							
							# Attempt to get the data and add to the results array $arrRes
							$arrRes += $($hd.VMName) + "," + $($hd.ControllerType) + "," + $ClusterVolId + "," + $($hd.Path)
						} 
					} 
				}
				Catch {
					$arrRes += "Unable to retrieve data for cluster node " + $c
				}
			} 

			# Export the results to file and end script
			$arrRes | out-file $ResultsFilePath        
			Write-Output "Finished. View the results in $ResultsFilePath`n`n" 		
		}
	}
    Else {
        Write-Output "`nFailed to create hosts file: "
        Write-Output $ErrorMsg
	}
}
