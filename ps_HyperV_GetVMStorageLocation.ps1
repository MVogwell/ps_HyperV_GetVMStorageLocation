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
        
        write-verbose "ps_Function_CheckRunningAsAdmin :: Checking for admin rights"
        $bRunningAsAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
    }
    Catch {
        $bRunningAsAdmin = $False
        write-verbose "ps_Function_CheckRunningAsAdmin :: ERROR Checking for admin rights in current session"
        write-verbose "ps_Function_CheckRunningAsAdmin :: Error: $($Error[0].Exception)"
    }
    Finally {}
    
    write-verbose "ps_Function_CheckRunningAsAdmin :: Result :: $bRunningAsAdmin"
    
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
	# MVogwell - 04-06-18 - v1.1
	# 
	# Change log:
	#	v1: Working function
	#	v1.1: Changed params to mandatory. Added method to Append log file rather than create overwrite
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
				write-verbose "File already exists. Checking with user if it should be replaced`n"
	
				write-host "The results output file $OutputFile already exists!" -fore yellow
		
				Do {
					write-host "Do you want to overwrite it? yes/no" -fore yellow -noNewLine
					$sOverwriteResultsFile = read-host " "
					write-verbose "User answer: $sOverwriteResultsFile `n"
				}
				While (!($arrAnswers.Contains($sOverwriteResultsFile.toLower())))
		
				if (($sOverwriteResultsFile -eq "n") -or ($sOverwriteResultsFile -eq "no")) {
					write-verbose "User selected no"
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
		
			write-verbose "Attempting to create the results file"
		
			Try {
				New-Item $OutputFile -ItemType File -Force | out-null
			
			}
			Catch {
				write-verbose "Error creating new file $($Error[0])"
		
				$bResultsFileCreationSuccess = $False
				$ErrorMsg.value = $Error[0].exception -replace ("`n"," ") -replace ("`r"," ")
			}
		}
	}

	return $bResultsFileCreationSuccess
}


#@# Main

write-host "`n`nps_HyperV_GetVMStorageLocation - MVogwell - May 2019 - v1.0`n`n" -fore green

# Check running as admin - stop script if not
$bRunningAsAdmin = ps_Function_CheckRunningAsAdmin
if(!($bRunningAsAdmin)) {
	write-host "You must run this script as an administrator user with elevated rights" -fore red
	write-host "Please re-run the script as an admin.`n`n" -fore red
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
				write-host "It has not been possible to attach to the cluster '$ClusterName' or find a valid cluster" -fore red
				write-host "The script will now exit.`n`n" -fore red
		}

		# Get the results data - but only if the cluster could be found
		If($bClusterCheck) {
			$arrRes = @() 
			
			$arrRes += "VMName,ControllerType,ClusterStorageDiskId,Path"	# Set the headers for the csv file
			$cn = (Get-ClusterNode -Cluster $ClusterName).name 					# Get the name(s) of the cluster nodes
			foreach ($c in $cn) { 
				write-host "Checking VMs on $c"
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
			write-host "Finished. View the results in $ResultsFilePath`n`n" -fore green 		
		}
	}
    Else {
        write-host "`nFailed to create hosts file: " -noNewLine
        write-host $ErrorMsg -fore red
	}
}
# SIG # Begin signature block
# MIIPBQYJKoZIhvcNAQcCoIIO9jCCDvICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUqcxqCtLcYpbSnhNf/uHJNvdl
# s4OgggygMIIGMzCCBBugAwIBAgICEAIwDQYJKoZIhvcNAQELBQAwgcIxCzAJBgNV
# BAYTAkdCMRgwFgYDVQQIDA9HbG91Y2VzdGVyc2hpcmUxEzARBgNVBAcMCkNoZWx0
# ZW5oYW0xGjAYBgNVBAoMEVVsdHJhIEVsZWN0cm9uaWNzMSUwIwYDVQQLDBxQcmVj
# aXNpb24gQWlyICYgTGFuZCBTeXN0ZW1zMRcwFQYDVQQDDA5VRVBBTFMgUm9vdCBD
# QTEoMCYGCSqGSIb3DQEJARYZcG9zdG1hc3RlckB1bHRyYS1wYWxzLmNvbTAeFw0x
# NjEyMDkxMTA0MjFaFw0yNjEyMDcxMTA0MjFaMBcxFTATBgNVBAMTDHVlcGFscy1z
# dWJjYTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJqHNDWz19b3boAY
# I6fg+ckQdy6gkO+/5O3IELAoQBsDbMQyEgDVpL/S+7d17YdhgPU6gZ9+XIsREScf
# D2ZKXhEfuPgF/MQKehKX3U+3WcbLqDXAH4XQxpDlwE9TIa4KBKOJy/26aR85AOpi
# 9K65x3tY3g6cAGqxu+GVMkPcWzczO8WmdLnFPQte2LGTVKa5W1oLPAGy6q03LLFj
# SaIDLFgjXBlsmoFazFUQdpfqbcHanx86/fdh8pFnOd1xMc2TgpNeLkwVkJv5lMgC
# kRkWWKD/EwxQGTKUM+FUkWSLRWNO/xih5Ao8vbeUjsP/XNbFQSrQA3cgkva7VE2Z
# ZKOjCRHzrr4qbYm9gEOG/1Q6YeKMroNbKRjZItJnfsFeQ/hiejG5wZTEbughJkO6
# AKk0mcNlRhqvH3sLQsOS0KPDUWbHiHvtqEyM1WQMOTkJ9hyPzVSmouMEn/1ccqDG
# KsETQkGkjZvJFSWYwOUYgcPyRI6aCIo2m41OOoG64oJngJe4BbyYbT5D6XQqWwbe
# aFP6j8ZYJUoOdcZVpH3PC+rzfCyEPSQAcQ9YLlPihrAMCBRg3xHokG/g5RZbMWuI
# /knannYuDhHk3c/8xmdX1suVyJDsXRMKhRdHWBdD5eOYD3CTJqnWYFfcMo6uyUTH
# yyMDfSdbpprY9DmnAA7LOwH+kdUnAgMBAAGjgdwwgdkwHQYDVR0OBBYEFMuTvwev
# EDx4zd4gXSsEvzgejembMB8GA1UdIwQYMBaAFKNyjxR1xvhIhmiVgzis7rO70yxq
# MBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMD4GCCsGAQUFBwEB
# BDIwMDAuBggrBgEFBQcwAoYiaHR0cDovL3Jvb3QtY2EudWVwYWxzLmNvbS9yb290
# LnBlbTAzBgNVHR8ELDAqMCigJqAkhiJodHRwOi8vcm9vdC1jYS51ZXBhbHMuY29t
# L3Jvb3QuY3JsMA0GCSqGSIb3DQEBCwUAA4ICAQDA3Fb0UC0kuTKU6hAgqbAlJFQn
# k/dXMDUKPSoZFYn5T+Ha+Z/5QwOQ/hPHAnRN4ozHXW1S3KPCTKwh60fLD/WRHinj
# 6L7RBUGgI8FtShdkl0MqPfdADNJOUKNpIkgbmbH5I5crXkVVwSdGpNHMK/zgiumn
# 6tJL3R0XAkyibzLrUE1ud9n2AmKLppBuHZO6L2/wP0rn2K2rM4IxwhWXJlB7r428
# +RU6vQGcNYwO1Ppes+1nEV8Ss0zMV9qC9C5uWUf5Tb/OPgA6AHSzqzdn1n/EsAXK
# vvSRfaQBiSMu99cBz4/t4bF9ziXhK4+1jpZ81LYA47udqouUtIvk3Q0aDdxkU602
# BUktGafM3QVVokOE8svr7DNFyFNos6xOteiwhlQ/I1zn5ZJhQfViBaC6KSZACmEe
# gpy4GfRyAbHgRL7/A4dWf2/CFfqHv5UZktMqTn7l6U4ARgiJkqYREiBG0iVW8Vyn
# 5ZbCEX9UOtxCNAIU54ojga52Yx1ZjrtBWRddq6vRyHzpZZm2deovpJgMlmhhOnpq
# ALQroJ16Wg3Gwk/UCDmV50l3O21tQujtPdUO1qQmgKQMra5X0mBzmHRqBfdc8SNP
# hEGIGK/k1WFQODdAlWmt34SyCnJBBAS27MWOCIaLbxwxjDNnWczSP2UEwsLBx8lD
# xS9QeAyovfsiSynRoTCCBmUwggRNoAMCAQICE1cAABKJj15OrhfwSsgAAAAAEokw
# DQYJKoZIhvcNAQELBQAwFzEVMBMGA1UEAxMMdWVwYWxzLXN1YmNhMB4XDTE5MDUx
# NjA4NTMxNVoXDTIwMDUxNTA4NTMxNVowdDETMBEGCgmSJomT8ixkARkWA2NvbTEW
# MBQGCgmSJomT8ixkARkWBnVlcGFsczEVMBMGA1UECwwMVUVQQUxTX1VzZXJzMRUw
# EwYDVQQLDAxVc2Vyc19BZG1pbnMxFzAVBgNVBAMTDk1hcnRpbiBWb2d3ZWxsMIIB
# IjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAhuQ4sSU7PECDLEzHofWjsOo9
# 7gybV6dlLjpjdIiinpEQzdB1dU83zq5gdA+PEqEUP+3+8HEsrOtkj1y6qSMQOI1A
# +ktslnGjVRdWwuRuNBtD4eCfSRI2REmTJuTmv/ltqLOSQ8nP9fIzA3d8wqtOgmne
# JQyP2BfqjhPjCT+E2LD+Ya8qt59RNOLhSoF8Eg1FzhsWGmIY1pXBV43rkTZcKwab
# M9nLbtmdZcEGsdJ1Hw4cKYx77DjTVKzwv/NLb1JhSTSunTN5vM5PZLms34Ekm7jO
# Ed4xmi2Ye5gstE3m1VCfVpqhfdefp2ErPIJeNIALNhI1iZJEV59katco47Pl0QID
# AQABo4ICSzCCAkcwJQYJKwYBBAGCNxQCBBgeFgBDAG8AZABlAFMAaQBnAG4AaQBu
# AGcwEwYDVR0lBAwwCgYIKwYBBQUHAwMwDgYDVR0PAQH/BAQDAgeAMB0GA1UdDgQW
# BBSf6JAtRMyFS53KiYNGyeIRRDY9LzAfBgNVHSMEGDAWgBTLk78HrxA8eM3eIF0r
# BL84Ho3pmzCByAYDVR0fBIHAMIG9MIG6oIG3oIG0hoGxbGRhcDovLy9DTj11ZXBh
# bHMtc3ViY2EsQ049VUxUUkE1LENOPUNEUCxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2
# aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPXVlcGFscyxEQz1j
# b20/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9iYXNlP29iamVjdENsYXNzPWNS
# TERpc3RyaWJ1dGlvblBvaW50MIG9BggrBgEFBQcBAQSBsDCBrTCBqgYIKwYBBQUH
# MAKGgZ1sZGFwOi8vL0NOPXVlcGFscy1zdWJjYSxDTj1BSUEsQ049UHVibGljJTIw
# S2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixEQz11
# ZXBhbHMsREM9Y29tP2NBQ2VydGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0
# aWZpY2F0aW9uQXV0aG9yaXR5MC4GA1UdEQQnMCWgIwYKKwYBBAGCNxQCA6AVDBNt
# dm9nd2VsbEB1ZXBhbHMuY29tMA0GCSqGSIb3DQEBCwUAA4ICAQAU+r8yF85Lb2oT
# Mq72cECvNL2vPhqNJ9YhPc/fia7ZNpWddupXXAhmVRDZG7wn3K3wRAotWsfoD27r
# B05ct1Ayd7Up0iFxSnLZzexCBXyfsm5aZNBIPRs224HhxBku/5gVQsBw0ZOjFJ5B
# I7P8zgp1yyUEBz6aeVcuC5FF/OETiF4RzREf8jmuNOauRERDuBBvTs3jpinwaOFO
# vw1SKcjqBFKr8asqnbeM+hBRv31MzVvFjmILLcRdUusghH2ZfA0UDv+2WdCh1LJd
# qz7bTSfR5PEMjMuqM6Bvm/8f6bRDQvGvgi+uJ4TBNCe/Pj5GTgkwqubeYUstWPnV
# 3AXIZUbmZjFKsnojiF/9YNrF7VfrwGVndy1mWKJxoGmBRCj3LIMUs7E5Nu584pM8
# 1WQ687rHfO28Orw6kQ8ZD42BkFAL3NV1GTgSQ1a0/G2xOpm0oehSUgSRntM2iN9x
# bC327ZCgkeKLVxhdWvZFwl6je9XmVQoc9vT9KhkB30JMluRxc6f7VXKVouilaaVA
# sptQWLY6kqPk5/euUtF7xiA2+UtGWG6CtvJG56ZYGt+SDUWth1768Ri1YkmbJUGt
# hrwxH9/rXW9nl3EAxIACc+hPPxXHTRmcjftyuNFJRicsPOal9Qbnn2KK4tflk90w
# jjSu0ik5pOE80M3Qo0gls4ccFEXbXDGCAc8wggHLAgEBMC4wFzEVMBMGA1UEAxMM
# dWVwYWxzLXN1YmNhAhNXAAASiY9eTq4X8ErIAAAAABKJMAkGBSsOAwIaBQCgeDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEW
# BBTAUNbAADSYh8hVbnX7jt1ZQx7lYTANBgkqhkiG9w0BAQEFAASCAQAjpTbD+s8D
# so/uPITdCzlcMbH+LOrwDLA0AjMq1B1ZTue5IF76Swwni4DIJRIFUVLB6+JESBWz
# GX4P54nNPJKb78yKq1ICqhnN3ucULJDwwas0UfQQGt6bNiZajy77XCyLrfL1/OnT
# ey0nj1ecWO3mu83UsLtU5VD4tD7rJpcIHecpt2f4RMF5krJWxiaSFg9KBUZilJ57
# noL40LDtfxlFN+zXXgIcRcd8MkdZAbPpcDG20H6VRI06LI0bjfKsTOCc+8p8KJML
# l1UMCB83N6lENki0kVEFhK4EbLNbQg/sUs8Ci0x7niiEHjnq8wtXQdPSSiL+4bcI
# mTZizn1+epXc
# SIG # End signature block
