<#
.NOTES
 	==================================================================================================================================================================
	Azure FastTrack - Managed Disks Program
	File:		UnmanagedDisksReport.ps1
	Purpose:	Generate a CSV report of ARM virtual machine and virtual machine scale set resiliency
	Version: 	1.0 - November 2017 - Jason Beck, Azure Fast Track
 	==================================================================================================================================================================
 .SYNOPSIS
    Generate a CSV report of virtual machine and virtual machine scale set resiliency
 .DESCRIPTION
    This script will gather information in an Azure subscription about the resiliency of
    virtual machines and virtual machine scale sets as it relates unmanaged disks, managed disks, and availability sets.
    
 .EXAMPLE
		UnmanagedDisksReport.ps1 `
        -SubscriptionID "xxxxx-xxxxxx-xxxxxxx-xxxxx"
   ===================================================================================================================================================================
#>

param(
	[Parameter(Mandatory=$true)]
    [string]$SubscriptionID,
    [Parameter(Mandatory=$true)]
    [string]$ReportOutputFolder
)

Write-Output "Script start`n"

if(-not(Test-Path -Path $ReportOutputFolder)){
    throw "The output folder specified does not exist at $ReportOutputFolder"
}

try{
    #Login to Azure
    $account = Login-AzureRmAccount
    if(!$account) {
        Throw "Could not login to Azure"
    }
    Write-Output "Successfully logged into Azure"
     
    #Set context to the subscription
    Select-AzureRMSubscription -SubscriptionName $SubscriptionID
    Write-Output "The subscription context is set to Subscription ID: $SubscriptionID"
}
catch{
    Write-Error "Error logging in subscription ID $SubscriptionID" -ErrorAction Stop
}

$timeStamp = Get-Date -Format yyyyMMddHHmm
$VmssOutputPath = "$ReportOutputFolder\VMSSUnmanagedDiskReport-$timeStamp.csv"
$VmOutputPath = "$ReportOutputFolder\VMUnmanagedDisk-$timeStamp.csv"

# this function calculates the Managed Disk based upon the disk size and storage account type
function Calculate-MDType{

    param ([string] $diskUri, [int] $diskSizeInGB)

    [string] $managedDiskType = ""

    $diskSA = Get-AzureRmStorageAccount | Where-Object { $_.StorageAccountName -eq $(($diskUri).Split('.')[0].Split('/')[2]) }

    if($diskSA.Sku.Tier -eq "Standard"){
        if($diskSizeInGB -lt 32){
            $managedDiskType = "S4"
        }
        elseif($diskSizeInGB -lt 64){
            $managedDiskType = "S6"
        }
        elseif($diskSizeInGB -lt 128){
            $managedDiskType = "S10"
        }
        elseif($diskSizeInGB -lt 512){
            $managedDiskType = "S20"
        }
        elseif($diskSizeInGB -lt 1024){
            $managedDiskType = "S30"
        }
        elseif($diskSizeInGB -lt 2048){
            $managedDiskType = "S40"
        }
        elseif($diskSizeInGB -lt 4095){
            $managedDiskType = "S50"
        }
    }
    elseif($diskSA.Sku.Tier -eq "Premium"){
        if($diskSizeInGB -lt 32){
            $managedDiskType = "P4"
        }
        elseif($diskSizeInGB -lt 64){
            $managedDiskType = "P6"
        }
        elseif($diskSizeInGB -lt 128){
            $managedDiskType = "P10"
        }
        elseif($diskSizeInGB -lt 256){
            $managedDiskType = "P15"
        }
        elseif($diskSizeInGB -lt 512){
            $managedDiskType = "P20"
        }
        elseif($diskSizeInGB -lt 1024){
            $managedDiskType = "P30"
        }
        elseif($diskSizeInGB -lt 2048){
            $managedDiskType = "P40"
        }
        elseif($diskSizeInGB -lt 4095){
            $managedDiskType = "P50"
        }
    }
    
    return $managedDiskType
}

#############################################
# Region: Virtual Machines
#############################################
Write-Output "Gathering information for virtual machines.`n"

# Get all VMs the user has access to in the subscription
$vms = Get-AzureRmVm
$unmanagedVms = @()

# Check all VMs in subscription and gather information for VMs using unmanaged disks
Foreach ($vm in $vms){
    
    # Check if VMs are using unmanaged disks
    if($vm.StorageProfile.OsDisk.Vhd){
            
        # Create custom object to store VM information        
        $unmanagedVm = New-Object System.Object
        $unmanagedVm | Add-Member -Type NoteProperty -Name Name -Value $vm.Name
        $unmanagedVm | Add-Member -Type NoteProperty -Name VMResourceGroup -Value $vm.ResourceGroupName
        $unmanagedVm | Add-Member -Type NoteProperty -Name Location -Value $vm.Location
        $unmanagedVm | Add-Member -Type NoteProperty -Name AvailabilitySet -Value ""

        if($vm.AvailabilitySetReference.Id){
            $unmanagedVm.AvailabilitySet = ($vm.AvailabilitySetReference.Id | Split-Path -Leaf )                    
        }

        $unmanagedVm | Add-Member -Type NoteProperty -Name OsDiskName -Value $vm.StorageProfile.OsDisk.Name
        $unmanagedVm | Add-Member -Type NoteProperty -Name OsDiskSizeGb -Value $vm.StorageProfile.OsDisk.DiskSizeGB
        $unmanagedVm | Add-Member -Type NoteProperty -Name OsDiskSA -Value ($vm.StorageProfile.OsDisk.Vhd.Uri).Split('.')[0].Split('/')[2]
        $unmanagedVm | Add-Member -Type NoteProperty -Name OsDiskType -Value "[$(Calculate-MDType -diskUri $vm.StorageProfile.OsDisk.Vhd.Uri -diskSizeInGB $vm.StorageProfile.OsDisk.DiskSizeGB)] "
        $unmanagedVm | Add-Member -Type NoteProperty -Name DataDiskNames -Value ""
        $unmanagedVm | Add-Member -Type NoteProperty -Name DataDiskLuns -Value ""
        $unmanagedVm | Add-Member -Type NoteProperty -Name DataDiskSizeGb -Value ""
        $unmanagedVm | Add-Member -Type NoteProperty -Name DataDiskSA -Value ""
        $unmanagedVm | Add-Member -Type NoteProperty -Name DataDiskType -Value ""

        # Retrieve all data disk information, if any
        Foreach($dataDisk in $vm.StorageProfile.DataDisks){
            $unmanagedVm.DataDiskSA += "[$(($dataDisk.Vhd.Uri).Split('.')[0].Split('/')[2])] "
            $unmanagedVm.DataDiskNames +=  "[$($dataDisk.Name)] "
            $unmanagedVm.DataDiskLuns += "[$($dataDisk.Lun)] "
            $unmanagedVm.DataDiskSizeGb += "[$($dataDisk.DiskSizeGb)] "
            $unmanagedVm.DataDiskType += "[$(Calculate-MDType -diskUri $dataDisk.Vhd.Uri -diskSizeInGB $dataDisk.DiskSizeGb)] "
        }
        
        # Add VM to list of unmanaged VMs
        $unmanagedVms += $unmanagedVm
    }
}

# If any unmanaged VMs exist, output results to CSV
if($unmanagedVms){

    # Output to CSV
    $unmanagedVms | Export-Csv -Path $VmOutputPath -NoTypeInformation
    Write-Output "Exported virtual machine report at $VmOutputPath`n"
}
else{

    Write-Output "No virtual machines were found'n"
}

# End Region

#############################################
# Region: Virtual Machine Scale Sets
#############################################
Write-Output "Gathering information for virtual machine scale sets.`n"

# Get all VMSSs user has access to in the subscription
$vmsss = Get-AzureRmVmss
$unmanagedVMSSs = @()

# Check all VMSSs in subscription and gather information for VMSSs using unmanaged disks
Foreach ($vmss in $vmsss){

    # Check if VMSSs are using unmanaged disks
    if($vmss.VirtualMachineProfile.StorageProfile.OsDisk.VhdContainers -or $vmss.VirtualMachineProfile.StorageProfile.OsDisk.imageUrl){
        
        # Create custom object to store VMSS information        
        $unmanagedVmss = New-Object System.Object
        $unmanagedVmss | Add-Member -Type NoteProperty -Name Name -Value $vmss.Name
        $unmanagedVmss | Add-Member -Type NoteProperty -Name VmssResourceGroup -Value $vmss.ResourceGroupName
        $unmanagedVmss | Add-Member -Type NoteProperty -Name Location -Value $vmss.Location
        $unmanagedVmss | Add-Member -Type NoteProperty -Name OsDiskName -Value $vmss.VirtualMachineProfile.StorageProfile.OsDisk.Name
        $unmanagedVmss | Add-Member -Type NoteProperty -Name Instances -Value (Get-AzureRmVmssVm -ResourceGroup $vmss.ResourceGroupName -Name $vmss.Name).Count
        $unmanagedVmss | Add-Member -Type NoteProperty -Name StorageAccounts -Value ""

        # Retrieve all vhd containers where the OS disks reside
        Foreach($vhdContainer in $vmss.VirtualMachineProfile.StorageProfile.OsDisk.VhdContainers){
            #$unmanagedVmss.StorageAccounts += "$vhdContainer "
            $unmanagedVmss.StorageAccounts += "[$(($vhdContainer).Split('.')[0].Split('/')[2])] "
        }

        # Add VMSS to list of unmanaged VMSSs
        $unmanagedVMSSs += $unmanagedVmss
    }
}

# If any unmanaged VMSSs exist, output to CSV
if($unmanagedVMSSs){

    # Output to CSV
    $unmanagedVMSSs | Export-Csv -Path $VmssOutputPath -NoTypeInformation
    Write-Output "Exported virtual machine scale sets report at $VmssOutputPath`n"
}
else{

    Write-Output "No virtual machine scale sets were found`n"
}

# End Region

Write-Output "Script end"