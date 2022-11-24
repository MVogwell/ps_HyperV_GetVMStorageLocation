# ps_HyperV_GetVMStorageLocation.ps1

Retrieves the storage location of all Hyper-V VMs in a cluster and exports to csv. This script must be run on a Hyper-V Cluster node.

<br>

## Examples

### Example 1

.\ps_HyperV_GetVMStorageLocation.ps1 -ClusterName MyClusterName

This will attempt to use the cluster called MyClusterName

<br>

### Example 2

.\ps_HyperV_GetVMStorageLocation.ps1 -ClusterName MyClusterName -ResultsFilePath c:\temp\myResults.csv

This will attempt to use the cluster called MyClusterName and will save the results to c:\temp\myResults.csv