$configurationUrl = "https://github.com/JasonBeck2/SampleCode/raw/master/vmss-dsc/DSC/Configuration.zip"
$configurationScript = "Configuration.ps1"
$configurationFunction = "DomainJoin"
$domainName = "jb.local"
$certThumbprint = "AB13159697214458FB53C6F5D180EA6C68E0BBE6"

$adminCreds = Get-Credential
$certCreds = Get-Credential
$certUrl = "https://vmssdsc001.blob.core.windows.net/dsc/backend.pfx?st=2018-10-22T22%3A04%3A44Z&se=2018-11-23T22%3A04%3A00Z&sp=rl&sv=2018-03-28&sr=b&sig=YxCcTbsWSQnV6eVQNkjz7dDeguvt63oUZHCwDXuhyc0%3D"

$settings = @{
    "configuration" = @{
        "url" = "$configurationUrl";
        "script" = "$configurationScript";
        "function" = "$configurationFunction";
    };
    "configurationArguments" = @{
        "domainName" = "$domainName";
        "certThumbprint" = "$certThumbprint";
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

$vmssName = "vmss07"
$vmssRg = "vmss"

$vmss = Get-AzureRmVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName

Add-AzureRmVmssExtension -VirtualMachineScaleSet $vmss -Name "dscdomainjoin" -Publisher "Microsoft.Powershell" -Type "DSC" -TypeHandlerVersion "2.7" -AutoUpgradeMinorVersion $True -Setting $settings -ProtectedSetting $protectedSettings