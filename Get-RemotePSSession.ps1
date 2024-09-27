function Global:Get-RemotePSSession
{
# v1.0.5 - added Port parameter (in addition to UseSSL option/5986) + simplified .net class add-type statement
# v1.0.4 - added support for ConfigurationName, ProcessID and session state + fixed delay bug with non-responsive computer(s)
# v1.0.3 - added support for Computername parameter to query multiple hosts in a single command run
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
     # Use SSL (5986)
     [switch]$UseSSL,
     # Optional, to specify port number
     [int]$Port,
     # Resolve IPs to hostnames
     [switch]$ResolveClientHostname
    )
 
    Begin
    {
        try{
            Add-Type  @"
namespace GetRemotePSSession{
public class PSSessionInfo
            {
public string Owner;
public string ClientIP;
public string ClientHostname;
public string SessionTime;
public string IdleTime;
public string ShellID;
public string ConnectionURI;
public bool UseSSL;
public string Name;
public string RemoteComputer;
public string ConfigurationName;
public string ProcessId;
public string State;
public string Port;
            }}
"@
        }
        catch{}
        $results = @() 
    }
    Process
    { 

# Set port
[int]$global:PortNumber = if ($UseSSL) {5986} else {5985}
if ($Port) {$global:PortNumber = $Port}

# declare port ping function & some variables for error handling + results array
filter Invoke-PortPing {((New-Object System.Net.Sockets.TcpClient).ConnectAsync($_,$global:PortNumber)).Wait(100)}
$EAP = $ErrorActionPreference;
$ErrorActionPreference = "SilentlyContinue";
$results = @();
$AvailableComputers = @();

# first check if host(s) is/are available on winrm port
$ComputerName | ForEach-Object {
    $Computer = $_;
    if (($Computer | Invoke-PortPing) -eq $False) 
        {
            Write-Host "Computer $($Computer.ToUpper()) is not responsive on port $global:PortNumber. Skipping." -ForegroundColor Yellow
        }
    else
        {
            $AvailableComputers += $Computer
        }
}

# Get session(s) information
$AvailableComputers | ForEach-Object {
$Computer = $_; 

# enum sessions
$URI = "http://$($Computer):$global:PortNumber/wsman";
$sessions = Get-WSManInstance -ConnectionURI $URI shell -Enumerate;

# handle errors, abort if no access
if (!$?) {
    Write-Warning "An error occured while trying to access $URI";
    $Error[0].exception;
}

if ($sessions -ne $null) {
foreach($session in $sessions)
        {
            $obj = New-Object GetRemotePSSession.PSSessionInfo;
            $obj.Owner = $session.owner;
            $obj.ClientIP = $session.clientIp;
	        if ($ResolveClientHostname) {
                if ($obj.clientIP -eq "::1" -xor $obj.clientIP -eq "127.0.0.1") {$obj.ClientHostname = $Computer}
                else {$obj.ClientHostname = [System.Net.Dns]::GetHostEntry($obj.ClientIP).HostName.ToUpper()}
            }
            $obj.SessionTime = [System.Xml.XmlConvert]::ToTimeSpan($session.shellRunTime).tostring();
            $obj.IdleTime = [System.Xml.XmlConvert]::ToTimeSpan($session.shellInactivity).tostring();
            $obj.ShellID = $session.shellid;
            $obj.ConnectionURI = $uri;
            if ($UseSSL) {$obj.UseSSL = $true} else {$UseSSL = $false}
	        $obj.Name = $session.Name;
            $obj.RemoteComputer = $Computer.ToUpper();
            $obj.ConfigurationName = $session.ResourceURI.Split("/")[-1];
            $obj.ProcessId = $session.ProcessId;
            $obj.State = $session.State;
            $obj.Port = $global:PortNumber;
            $results += $obj
        }
      }
      else {Write-Host "No Sessions found on $($Computer.ToUpper()) on port $global:PortNumber." -ForegroundColor Cyan}
    }}
    End
    {        
      $results;
      $ErrorActionPreference = $EAP
    }
}