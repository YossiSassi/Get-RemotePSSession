function Global:Get-RemotePSSession
{
# v1.0.3 - added support for Computername parameter to query multiple hosts in one command run
# v1.0.2 - added error handling and better indication for access denied etc.
# v1.0.1 - added wincompat shell name to identify local PWSH runspaces
# comments to yossis@protonmail.com
[CmdletBinding()]
    Param
    (
     # Computer to query
     [Parameter(Mandatory=$true,
                ValueFromPipeline=$true,
                Position=0)]
                [string[]]$ComputerName, 
     # use SSL
     [switch]$UseSSL,
     # Resolve IPs to hostnames
     [switch]$ResolveClientHostname
    )
 
    Begin
    {
        try{
            if ($ResolveClientHostname)
            {
            Add-Type  @"
namespace GetRemotePSSession{
public class PSSession1
            {
public string Owner;
public string ClientIP;
public string ClientHostname;
public string SessionTime;
public string IdleTime;
public string ShellID;
public string ConnectionURI;
public bool UseSSL=false;
public string Name;
public string RemoteComputer;
            }}
"@
    } else {
    Add-Type  @"
namespace GetRemotePSSession{
public class PSSession2
            {
                public string Owner;
public string ClientIP;
public string SessionTime;
public string IdleTime;
public string ShellID;
public string ConnectionURI;
public bool UseSSL=false;
public string Name;
public string RemoteComputer;
            }}
"@
    }
        }
        catch{}
        $results = @() 
    }
    Process
    { 

# Set port
$Port = if ($UseSSL) {5986} else {5985}
$results = @();

$ComputerName | ForEach-Object {
$Computer = $_; 
$URI = "http://$($Computer):$port/wsman";

# enum sessions
$EAP = $ErrorActionPreference;
$ErrorActionPreference = "SilentlyContinue";
$sessions = Get-WSManInstance -ConnectionURI $URI shell -Enumerate;

# handle errors, abort if no access
if (!$?) {
    Write-Warning "An error occured while trying to access $URI";
    $Error[0].exception;
    $ErrorActionPreference = $EAP;
    break
}

if ($sessions -ne $null) {
foreach($session in $sessions)
        {
            if ($ResolveClientHostname) {$obj = New-Object GetRemotePSSession.PSSession1} else {$obj = New-Object GetRemotePSSession.PSSession2}
            $obj.Owner = $session.owner
            $obj.ClientIP = $session.clientIp
	        if ($ResolveClientHostname) {
                if ($obj.clientIP -eq "::1" -xor $obj.clientIP -eq "127.0.0.1") {$obj.ClientHostname = $Computer}
                else {$obj.ClientHostname = [System.Net.Dns]::GetHostEntry($obj.ClientIP).HostName.ToUpper()}
            }
            $obj.SessionTime = [System.Xml.XmlConvert]::ToTimeSpan($session.shellRunTime).tostring()
            $obj.IdleTime = [System.Xml.XmlConvert]::ToTimeSpan($session.shellInactivity).tostring()
            $obj.ShellID = $session.shellid
            $obj.ConnectionURI = $uri
            $obj.UseSSL = $UseSSL
	        $obj.Name = $session.Name
            $obj.RemoteComputer = $Computer
            $results += $obj
        }
      }
      else {Write-Host "No Remote PSSessions found on $Computer on port $Port." -ForegroundColor Cyan}
    }}
    End
    {        
      $results;
      $ErrorActionPreference = $EAP
    }
}