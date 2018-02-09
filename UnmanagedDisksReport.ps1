<#
.NOTES
 	==================================================================================================================================================================
	Azure Managed Disks Program
	File:		UnmanagedDisksReport.ps1
	Purpose:	Generate a CSV report of ARM virtual machine and virtual machine scale set resiliency
	Version: 	1.0 - February 2018
 	==================================================================================================================================================================
 .SYNOPSIS
    Generate a CSV report for virtual machines using unmanaged disks
 .DESCRIPTION
    This script will gather information in an Azure subscription about unmanaged disks used by ARM virtual machines 
    and at what capacity they are being used.
 .PARAMTERS
    SubscriptionID - Azure subscription ID to run this script against
    ReportOutputFolder - Output location for the CSV generated in this script
 .EXAMPLE
		UnmanagedDisksReport.ps1 -SubscriptionID "xxxxx-xxxxxx-xxxxxxx-xxxxx" -ReportOutputFolder "C:\ScriptReports\"
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
    # login to Azure
    # to skip logging into Azure for authenticated sessions, comment out the next 5 lines
    $account = Login-AzureRmAccount
    if(!$account) {
        Throw "Could not login to Azure"
    }
    Write-Output "Successfully logged into Azure"
    
    # set context to the subscription
    Select-AzureRMSubscription -SubscriptionName $SubscriptionID
    Write-Output "The subscription context is set to Subscription ID: $SubscriptionID`n"
}
catch{
    Write-Error "Error logging in subscription ID $SubscriptionID" -ErrorAction Stop
}

$timeStamp = Get-Date -Format yyyyMMddHHmm
$VmOutputPath = "$ReportOutputFolder\VMUnmanagedDisk-$timeStamp.csv"

# this function calculates the Managed Disk based upon the disk size and storage account type
function EstimateMDType{

    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Standard","Premium")]
        [string] $storageType,

        [Parameter(Mandatory=$true)]
        [int] $dataSizeInGB)

    [single] $expectedGrowthMultiplier = 0.3
    [string] $managedDiskType = ""
    
    $dataSizeInGB += [math]::Round($dataSizeInGB*$expectedGrowthMultiplier)
    
    
    if($storageType -eq "Standard"){
        if($dataSizeInGB -le 32){
            $managedDiskType = "S4"
        }
        elseif($dataSizeInGB -le 64){
            $managedDiskType = "S6"
        }
        elseif($dataSizeInGB -le 128){
            $managedDiskType = "S10"
        }
        elseif($dataSizeInGB -le 512){
            $managedDiskType = "S20"
        }
        elseif($dataSizeInGB -le 1024){
            $managedDiskType = "S30"
        }
        elseif($dataSizeInGB -le 2048){
            $managedDiskType = "S40"
        }
        elseif($dataSizeInGB -le 4095){
            $managedDiskType = "S50"
        }
    }
    elseif($storageType -eq "Premium"){
        if($dataSizeInGB -le 32){
            $managedDiskType = "P4"
        }
        elseif($dataSizeInGB -le 64){
            $managedDiskType = "P6"
        }
        elseif($dataSizeInGB -le 128){
            $managedDiskType = "P10"
        }
        elseif($dataSizeInGB -le 256){
            $managedDiskType = "P15"
        }
        elseif($dataSizeInGB -le 512){
            $managedDiskType = "P20"
        }
        elseif($dataSizeInGB -le 1024){
            $managedDiskType = "P30"
        }
        elseif($dataSizeInGB -le 2048){
            $managedDiskType = "P40"
        }
        elseif($dataSizeInGB -le 4095){
            $managedDiskType = "P50"
        }
    }
    
    return $managedDiskType
}

# This function will gather detailed information about unmanaged disks
function GetUnmanagedDiskDetails{

    param(
        [Parameter(Mandatory=$true)] $vhduri)

    $diskUri = New-Object System.Uri($vhduri)

    $storageAccount =  $diskUri.Host.Split('.')[0]
    $vhdFileName = $diskUri.Segments[$diskUri.Segments.Length-1]
    $container = $diskUri.Segments[1].Trim('/')

    $storageAccounts = Find-AzureRmResource -ResourceType 'Microsoft.Storage/storageAccounts'  

    foreach($sa in $storageAccounts){
            if($sa.ResourceName -eq $storageAccount){   
                    $rg = $sa.ResourceGroupName
            }
    }

    $type = (Get-AzureRmStorageAccount -Name $storageAccount -ResourceGroupName $rg).Sku.Tier
    $storageAccountKey = (Get-AzureRMStorageAccountKey -Name $storageAccount -ResourceGroupName $rg)[0].Value
    $storageAccountContext = New-AzureStorageContext –StorageAccountName $storageAccount -StorageAccountKey $storageAccountKey 

    
    try{
        $blob = Get-AzureStorageBlob -Blob $vhdFileName -Container $container -Context $storageAccountContext -ErrorAction Stop
    
        # Calculate provisioned size GB
        $provisionedSizeInGib = [math]::Round($($blob.Length)/1073741824)

        # Base + blob name 
        $blobSizeInBytes = 124 + $blob.Name.Length * 2 
  
        # Get size of metadata 
        $metadataEnumerator = $blob.ICloudBlob.Metadata.GetEnumerator() 
        while ($metadataEnumerator.MoveNext()) { 
            $blobSizeInBytes += 3 + $metadataEnumerator.Current.Key.Length + $metadataEnumerator.Current.Value.Length 
        } 
  
        $blob.ICloudBlob.GetPageRanges() |  ForEach-Object { $blobSizeInBytes += 12 + $_.EndOffset - $_.StartOffset } 
    
        # Calculate used size in GB
        $usedSizeInGiB = $blobSizeInBytes/(1073741824)

        # Calculate percentage of used disk space rounding to 2 decimals
        $usedDiskPercentage = [math]::Round($usedSizeInGiB/$provisionedSizeInGib,2)
        $usedSizeInGiB = [math]::Round($usedSizeInGiB)
    }
    # Catching any errors for getting the storage blob
    catch{
        Write-Host -ForegroundColor Red "There was an error while accessing the blob with the URI: $vhduri"
        Write-Host -ForegroundColor Red $_.Exception
    }

    $blobDetails = New-Object psobject -Property @{Uri=$vhduri;StorageType=$type;ProvisionedSize=$provisionedSizeInGib;UsedSize=$usedSizeInGiB;UsedDiskPercentage=$usedDiskPercentage}
    
    return $blobDetails
}

# Region Gather Unmanaged Disk Information

Write-Host "Gathering virtual machine information...`n"
Write-Host "Progress Status:"
Write-Host "[<Current Number> of <Total Number of VMs>] <VM Name>`n"

# Get all ARM virtual machines
$vms = Get-AzureRmVM
$unmanDisks = @()
[int]$i = 1

# Loop through each virtual machine and gather disk information for unmanaged disks only
foreach($vm in $vms){

    Write-Host "[$i of $($vms.Count)] $($vm.Name)"
    $i++

   if($vm.StorageProfile.OsDisk.Vhd){
       
        $unmanDisk = New-Object System.Object
        $unmanDisk | Add-Member -Type NoteProperty -Name VmName -Value $vm.Name
        $unmanDisk | Add-Member -Type NoteProperty -Name VmResourceGroup -Value $vm.ResourceGroupName
        $unmanDisk | Add-Member -Type NoteProperty -Name Location -Value $vm.Location
        $unmanDisk | Add-Member -Type NoteProperty -Name AvailabilitySet -Value ""

        
        if($vm.AvailabilitySetReference.Id){
            $unmanDisk.AvailabilitySet = ($vm.AvailabilitySetReference.Id | Split-Path -Leaf )                    
        }
       
        # Gather unmnaged disk details and store as a PS custom object
        $osDiskDetails = GetUnmanagedDiskDetails $vm.StorageProfile.OsDisk.Vhd.Uri
        $estimatedMDType = EstimateMDType -storageType $osDiskDetails.StorageType -dataSizeInGB $osDiskDetails.UsedSize

        $unmanDisk | Add-Member -Type NoteProperty -Name VhdUri -Value $osDiskDetails.Uri
        $unmanDisk | Add-Member -Type NoteProperty -Name StorageType -Value $osDiskDetails.StorageType
        $unmanDisk | Add-Member -Type NoteProperty -Name DiskType -Value "OS"
        $unmanDisk | Add-Member -Type NoteProperty -Name ProvisionedSizeInGb -Value $osDiskDetails.ProvisionedSize
        $unmanDisk | Add-Member -Type NoteProperty -Name UsedSizeInGb -Value $osDiskDetails.UsedSize
        $unmanDisk | Add-Member -Type NoteProperty -Name UsedDiskPercentage -Value $osDiskDetails.UsedDiskPercentage
        $unmanDisk | Add-Member -Type NoteProperty -Name EstimatedMDType -Value $estimatedMDType     

        $unmanDisks += $unmanDisk
   }

   foreach($disk in $vm.StorageProfile.DataDisks){
        
        if($disk.Vhd){
          
            $unmanDisk = New-Object System.Object
            $unmanDisk | Add-Member -Type NoteProperty -Name VmName -Value $vm.Name
            $unmanDisk | Add-Member -Type NoteProperty -Name VmResourceGroup -Value $vm.ResourceGroupName
            $unmanDisk | Add-Member -Type NoteProperty -Name Location -Value $vm.Location
            $unmanDisk | Add-Member -Type NoteProperty -Name AvailabilitySet -Value ""
        
            if($vm.AvailabilitySetReference.Id){
                $unmanDisk.AvailabilitySet = ($vm.AvailabilitySetReference.Id | Split-Path -Leaf )                    
            }

            # Gather unmnaged disk details and store as a PS custom object
            $dataDiskDetails = GetUnmanagedDiskDetails $disk.Vhd.Uri
            $estimatedMDType = EstimateMDType -storageType $dataDiskDetails.StorageType -dataSizeInGB $dataDiskDetails.UsedSize

            $unmanDisk | Add-Member -Type NoteProperty -Name VhdUri -Value $dataDiskDetails.Uri
            $unmanDisk | Add-Member -Type NoteProperty -Name StorageType -Value $dataDiskDetails.StorageType
            $unmanDisk | Add-Member -Type NoteProperty -Name DiskType -Value "Data"
            $unmanDisk | Add-Member -Type NoteProperty -Name ProvisionedSizeInGb -Value $dataDiskDetails.ProvisionedSize
            $unmanDisk | Add-Member -Type NoteProperty -Name UsedSizeInGb -Value $dataDiskDetails.UsedSize
            $unmanDisk | Add-Member -Type NoteProperty -Name UsedDiskPercentage -Value $dataDiskDetails.UsedDiskPercentage
            $unmanDisk | Add-Member -Type NoteProperty -Name EstimatedMDType -Value $estimatedMDType
        
            $unmanDisks += $unmanDisk
        }
   }
}

# If any unmanaged VMs exist, output results to CSV
if($unmanDisks){

    # Output to CSV
    $unmanDisks | Export-Csv -Path $VmOutputPath -NoTypeInformation
    Write-Output "`nExported unmanaged disk report at $VmOutputPath`n"
}
else{

    Write-Output "`nNo virtual machines with unmanaged disks were found'n"
}

# End Region

Write-Output "Script end"