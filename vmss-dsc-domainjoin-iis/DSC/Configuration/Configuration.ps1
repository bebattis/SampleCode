configuration DomainJoinIIS 
{ 
   param 
    ( 
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [String]$domainName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [PSCredential]$adminCreds
    ) 
    
    Import-DscResource -ModuleName xComputerManagement

    $domainCreds = New-Object System.Management.Automation.PSCredential("$domainName\$($adminCreds.UserName)", $adminCreds.Password)
   
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
   }
}