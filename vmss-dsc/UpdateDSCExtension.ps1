$vmssName = "vmss09"
$vmssRg = "vmss"

$configurationUrl = "https://github.com/JasonBeck2/SampleCode/raw/master/vmss-dsc/DSC/Configuration.zip"
$configurationScript = "Configuration.ps1"
$configurationFunction = "DomainJoin"
$domainName = "jb.local"
$certThumbprint = "AB13159697214458FB53C6F5D180EA6C68E0BBE6"
$sourceCodeUrl = "https://github.com/JasonBeck2/SampleCode/raw/master/vmss-dsc/DSC/Configuration.zip"

$adminCreds = Get-Credential
$certCreds = Get-Credential
$certUrl = "https://vmssdsc001.blob.core.windows.net/dsc/backend.pfx?st=2018-10-22T22%3A04%3A44Z&se=2018-11-23T22%3A04%3A00Z&sp=rl&sv=2018-03-28&sr=b&sig=YxCcTbsWSQnV6eVQNkjz7dDeguvt63oUZHCwDXuhyc0%3D"


## Do not edit this region ##
$settings = @{
    "configuration" = @{
        "url" = "$configurationUrl";
        "script" = "$configurationScript";
        "function" = "$configurationFunction";
    };
    "configurationArguments" = @{
        "domainName" = "$domainName";
        "certThumbprint" = "$certThumbprint";
        "sourceCodeUrl" = "$sourceCodeUrl";
    }
}

$protectedSettings = @{
    "configurationArguments" = @{
        "adminCreds" = @{
            "userName" = "$adminCreds.UserName";
            "password" = "$adminCreds.Password";
        };
        "certCreds" = @{
            "userName" = "unused";
            "password" = "$certCreds.Password";
        };
        "certUrl" = "$certUrl";
    }
}

$vmss = Get-AzureRmVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName
## End Region ##

# Remove previous extension
Remove-AzureRmVmssExtension -VirtualMachineScaleSet $vmss -Name "dscdomainjoin"

# Update VMSS
Update-AzureRmVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName -VirtualMachineScaleSet $vmss

# Add extension
Add-AzureRmVmssExtension -VirtualMachineScaleSet $vmss -Name "updateddscdomainjoin" -Publisher "Microsoft.Powershell" -Type "DSC" -TypeHandlerVersion "2.76" -AutoUpgradeMinorVersion $True -Setting $settings -ProtectedSetting $protectedSettings

# Update VMSS
Update-AzureRmVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName -VirtualMachineScaleSet $vmss