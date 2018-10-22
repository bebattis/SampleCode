configuration DomainJoin 
{ 
   param 
    ( 
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [String]$domainName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [PSCredential]$adminCreds,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullorEmpty()]
        [String]$certUrl = "https://vmssdsc001.blob.core.windows.net/dsc/backend.pfx?st=2018-10-22T22%3A04%3A44Z&se=2018-11-23T22%3A04%3A00Z&sp=rl&sv=2018-03-28&sr=b&sig=YxCcTbsWSQnV6eVQNkjz7dDeguvt63oUZHCwDXuhyc0%3D",

        [Parameter(Mandatory = $false)]
        [ValidateNotNullorEmpty()]
        [String]$certThumbprint,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullorEmpty()]
        [PSCredential]$certCreds
    ) 
    
    Import-DscResource -ModuleName xComputerManagement, CertificateDsc

    $domainCreds = New-Object System.Management.Automation.PSCredential("$domainName\$($adminCreds.UserName)", $adminCreds.Password)

    #$certPassword = New-Object System.Management.Automation.PSCredential ("unnused", $certCreds.Password)
    $certPassword = New-Object System.Management.Automation.PSCredential ("unnused", (ConvertTo-SecureString -String "P@ssw0rd12345" -Force -AsPlainText))

    $localCertPath = "C:\temp\cert.pfx"
   
    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }

        WindowsFeature ADPowershell
        {
            Ensure = "Present"
            Name = "RSAT-AD-PowerShell"
        } 

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $domainName
            Credential = $domainCreds
            DependsOn = "[WindowsFeature]ADPowershell" 
        }

        WindowsFeature IIS
        {
            Ensure = "Present"
            Name = "Web-Server"
            IncludeAllSubFeature = $true
            DependsOn = "[xComputer]DomainJoin"
        }

        Script DownloadCertificate
        {
            GetScript = { return @{ 'Result' = (dir $localCertPath) } }
            TestScript = { Test-Path $localCertPath }
            SetScript = {
                if(!(Test-Path "C:\temp")){
                    New-Item -ItemType Directory -Force -Path "C:\temp"
                }
                $client = New-Object System.Net.WebClient
                $client.DownloadFile($certUrl, $localCertPath)
            }
            DependsOn = "[WindowsFeature]IIS"
        }

        PfxImport ImportCertificate
        {
            Thumbprint = "AB13159697214458FB53C6F5D180EA6C68E0BBE6" #$certThumbprint
            Path = $localCertPath
            Location = 'LocalMachine'
            Store = 'My'
            Credential = $certPassword
            DependsOn = "[Script]DownloadCertificate"
        }
   }
}
