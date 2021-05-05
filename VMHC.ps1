Import-Module -Name VMware.PowerCLI
#Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Confirm:$false
Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Scope Session -Confirm:$false
#Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCeip $false -InvalidCertificateAction Ignore

# Input & Output #
Remove-Item "C:\VMwareTeam\Script\VMHC\Report\*"
$Date = (Get-Date).tostring("dd-MM-yyyy")
$VAMIList = Get-Content -Path C:\VMwareTeam\Script\VMHC\List\VAMIList.txt
$VCSAList = Get-Content -Path C:\VMwareTeam\Script\VMHC\List\vCenterList.txt
$ESXiList = Get-Content -Path C:\VMwareTeam\Script\VMHC\List\ESXiList.txt
$Outputfile = "C:\VMwareTeam\Script\VMHC\Report\VHCR_$Date.html"
#. "./vCSA"
#. "./GeneralInfo"
#. "./SetCell"

Function Get-VAMISummary
{
<#VCSA Syntax#>
$Hostname = (Get-CisService -Name 'com.vmware.appliance.networking.dns.hostname').get()
$systemVersionAPI = Get-CisService -Name 'com.vmware.appliance.system.version'
$results = $systemVersionAPI.get() | select product, type, version, build, install_time

$systemUptimeAPI = Get-CisService -Name 'com.vmware.appliance.system.uptime'
$ts = [timespan]::fromseconds($systemUptimeAPI.get().toString())
#$uptime = $ts.ToString("hh\:mm\:ss\,fff")
#$uptime = ($ts.ToString("ddd") + ' Days')
$uptime = $ts.ToString()

$healthOverall = (Get-CisService -Name 'com.vmware.appliance.health.system').get()
$healthLastCheck = (Get-CisService -Name 'com.vmware.appliance.health.system').lastcheck()
$healthCPU = (Get-CisService -Name 'com.vmware.appliance.health.load').get()
$healthMem = (Get-CisService -Name 'com.vmware.appliance.health.mem').get()
$healthSwap = (Get-CisService -Name 'com.vmware.appliance.health.swap').get()
$healthStorage = (Get-CisService -Name 'com.vmware.appliance.health.storage').get()
# DB health only applicable for Embedded/External VCSA Node
$vami = (Get-CisService -Name 'com.vmware.appliance.system.version').get()
if($vami.type -eq "vCenter Server with an embedded Platform Services Controller" -or $vami.type -eq "vCenter Server with an external Platform Services Controller") {
$healthVCDB = (Get-CisService -Name 'com.vmware.appliance.health.databasestorage').get()
} else {
$healthVCDB = "N/A"
}
$healthSoftwareUpdates = (Get-CisService -Name 'com.vmware.appliance.health.softwarepackages').get()

$summaryResult = [pscustomobject] @{
        vCenterName = $Hostname;
        Product = $results.product;
        Type = $results.type;
        Version = $results.version;
        Build = $results.build;
        InstallTime = $results.install_time;
        HealthSoftware = $healthSoftwareUpdates;
        Uptime = $uptime;
        HealthLastCheck = $healthLastCheck;
        HealthCPU = $healthCPU;
        HealthMem = $healthMem;
        HealthSwap = $healthSwap;
        HealthStorage = $healthStorage;
        HealthVCDB = $healthVCDB;
        OverallStatus = $healthOverall;      
        }
        $summaryResult
}
Function Get-GeneralSummary
{
<#VCSA Syntax#>
$VMCount = Get-VM | Sort-Object Name
$VMH = Get-VMHost | Sort-Object Name
$Clusters = Get-Cluster | Sort-Object Name
$Datastores = Get-Datastore | Sort-Object Name
$FullVM = Get-View -ViewType VirtualMachine | Where-Object {-not $_.Config.Template}
$VMTmpl = Get-Template
$Datacenter = Get-Datacenter | Sort-Object Name

$vcInfo = New-Object -TypeName PSObject -Property ([ordered]@{
#"vCenter" = ([System.Uri]$global:defaultviserver.Client.Config.ServiceUrl).Host
"vCenter" = (@($global:DefaultVIServers).Name)
"NumberofHosts" = (@($VMH).Count)
   "NumberofVMs" = (@($VMCount).Count)
   "NumberofTemplates" = (@($VMTmpl).Count)
   "NumberofDatacenter" = (@($Datacenter).Count)
   "NumberofClusters" = (@($Clusters).Count)
   "NumberofDatastores" = (@($Datastores).Count)
   "ActiveVMs" = (@($FullVM | Where-Object { $_.Runtime.PowerState -eq "poweredOn" }).Count) 
   "In-activeVMs" = (@($FullVM | Where-Object { $_.Runtime.PowerState -eq "poweredOff" }).Count)
        })
        $vcInfo
}
Function Set-CellColor
{   
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory,Position=0)]
        [string]$Property,
        [Parameter(Mandatory,Position=1)]
        [string]$Color,
        [Parameter(Mandatory,ValueFromPipeline)]
        [Object[]]$InputObject,
        [Parameter(Mandatory)]
        [string]$Filter,
        [switch]$Row
    )
    
    Begin {
        Write-Verbose "$(Get-Date): Function Set-CellColor begins"
        If ($Filter)
        {   If ($Filter.ToUpper().IndexOf($Property.ToUpper()) -ge 0)
            {   $Filter = $Filter.ToUpper().Replace($Property.ToUpper(),"`$Value")
                Try {
                    [scriptblock]$Filter = [scriptblock]::Create($Filter)
                }
                Catch {
                    Write-Warning "$(Get-Date): ""$Filter"" caused an error, stopping script!"
                    Write-Warning $Error[0]
                    Exit
                }
            }
            Else
            {   Write-Warning "Could not locate $Property in the Filter, which is required.  Filter: $Filter"
                Exit
            }
        }
    }
    
    Process {
        ForEach ($Line in $InputObject)
        {   If ($Line.IndexOf("<tr><th") -ge 0)
            {   Write-Verbose "$(Get-Date): Processing headers..."
                $Search = $Line | Select-String -Pattern '<th ?[a-z\-:;"=]*>(.*?)<\/th>' -AllMatches
                $Index = 0
                ForEach ($Match in $Search.Matches)
                {   If ($Match.Groups[1].Value -eq $Property)
                    {   Break
                    }
                    $Index ++
                }
                If ($Index -eq $Search.Matches.Count)
                {   Write-Warning "$(Get-Date): Unable to locate property: $Property in table header"
                    Exit
                }
                Write-Verbose "$(Get-Date): $Property column found at index: $Index"
            }
            If ($Line -match "<tr( style=""background-color:.+?"")?><td")
            {   $Search = $Line | Select-String -Pattern '<td ?[a-z\-:;"=]*>(.*?)<\/td>' -AllMatches
                $Value = $Search.Matches[$Index].Groups[1].Value -as [double]
                If (-not $Value)
                {   $Value = $Search.Matches[$Index].Groups[1].Value
                }
                If (Invoke-Command $Filter)
                {   If ($Row)
                    {   Write-Verbose "$(Get-Date): Criteria met!  Changing row to $Color..."
                        If ($Line -match "<tr style=""background-color:(.+?)"">")
                        {   $Line = $Line -replace "<tr style=""background-color:$($Matches[1])","<tr style=""background-color:$Color"
                        }
                        Else
                        {   $Line = $Line.Replace("<tr>","<tr style=""background-color:$Color"">")
                        }
                    }
                    Else
                    {   Write-Verbose "$(Get-Date): Criteria met!  Changing cell to $Color..."
                        $Line = $Line.Replace($Search.Matches[$Index].Value,"<td style=""background-color:$Color"">$Value</td>")
                    }
                }
            }
            Write-Output $Line
        }
    }
    
    End {
        Write-Verbose "$(Get-Date): Function Set-CellColor completed"
    }
}
# AES 64-Bit Encrypt Credentials #
$User = "ctsscript@vsphere.local"
$User1 = "ctsscript"
$PasswordFile = "C:\VMwareTeam\Script\VMHC\AES\AESpassword.txt"
$KeyFile = "C:\VMwareTeam\Script\VMHC\AES\AES.Key"
$key = Get-Content $KeyFile
$VIcred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, (Get-Content $PasswordFile | ConvertTo-SecureString -Key $key)
$VIcred1 = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User1, (Get-Content $PasswordFile | ConvertTo-SecureString -Key $key)
# Import HTML #
$Head = @"
<Title>CSM - VMware Daily Health Check Report $Date</Title><style>
body { background-color:#E5E4E2;font-family:Monospace;font-size:10pt; }
td, th { border:0px solid black;border-collapse:collapse;white-space:pre;}
th { color:white;     background-color:black;}
table, tr, td, th { padding: 2px; margin: 0px ;white-space:pre;text-align:center;}
tr:nth-child(odd) {background-color: lightgray}
table { width:95%;margin-left:5px; margin-bottom:20px;}
h2 { font-family:Tahoma; color:#6D7B8D;}
.alert { color: red;  }
.footer { color:green;   margin-left:10px;   font-family:Tahoma;  font-size:8pt;  font-style:italic;}
</style>
"@
ConvertTo-Html –body "<H1>CSM - VMware Daily Health Check Report $Date</H1>" -head $head | Out-File -Append $OutputFile
ConvertTo-Html -body "<H5>Report Start time: $(Get-Date -Format g) </H5>" -head $head |  Out-File -Append $OutputFile
###############
# VAMI Report #
###############
Write-Host ""
Write-Host "Fetching VAMI Information" -ForegroundColor Green
Function Get-VCSAInventory
{
foreach($VAMI in $VAMIList) 
{
Write-Host ""
Write-Host "Collecting details from $VAMI" -ForegroundColor Yellow
$Connectvcsa = Connect-CisServer -server $VAMI -Credential $VIcred
$VC = Get-VAMISummary 
$VC | Select-Object vCenterName, Version, Build, Uptime, HealthLastCheck, HealthCPU, HealthMem, HealthSwap, HealthStorage, HealthVCDB, OverallStatus
$Disconnectvcsa = Disconnect-Cisserver -server * -Force -confirm:$false 
}
}
Get-VCSAInventory | Sort-Object vCenterName | ConvertTo-HTML -head $head -Body "<H2>Info: vCenter Appliance</H2>" |
Set-CellColor -Property OverallStatus -Color Orange -Filter "OverallStatus -eq 'Orange'" -Row |
Set-CellColor -Property OverallStatus -Color Orange -Filter "OverallStatus -eq 'Yellow'" -Row |
Set-CellColor -Property OverallStatus -Color Red -Filter "OverallStatus -eq 'Red'" -Row |
Out-File -Append $OutputFile
Write-Host ""
Write-Host "Fetching VAMI Information Completed" -ForegroundColor Green
############
# Gen Info #
############
Write-Host ""
Write-Host "Fetching VC Information" -ForegroundColor Green
Function Get-GenInventory
{
foreach($VCs in $VCSAList) 
{
Write-Host ""
Write-Host "Collecting details from $VCs" -ForegroundColor Yellow
$Connectvc = Connect-VIServer -server $VCs -Credential $VIcred
$VC1 = Get-GeneralSummary
$VC1 | Select-Object vCenter, NumberofHosts, NumberofVMs, ActiveVMs, In-activeVMs, NumberofTemplates, NumberofDatacenter, NumberofClusters, NumberofDatastores
$Disconnectvc = Disconnect-VIserver -server * -Force -confirm:$false 
}
}
Get-GenInventory | Sort-Object vCenter | ConvertTo-HTML -head $head -Body "<H2>Info: vCenter Inventory</H2>" | Out-File -Append $OutputFile
Write-Host ""
Write-Host "Fetching VC Information Completed" -ForegroundColor Green
###############
# ESXi Report #
###############
Write-Host ""
Write-Host "Fetching ESXi Host Information" -ForegroundColor Green
Connect-VIServer -Server $ESXiList -Credential $VIcred1
Write-Host ""
Write-Host "Collecting details from $ESXiList" -ForegroundColor Yellow
Get-VMHost | 
Select @{N="Hostname";E={($_ | Get-VMHostNetwork).Hostname}},
@{N="IP Address";E={(Get-VMHostNetworkAdapter -VMHost $_.Name  | Where-Object {$_.Name -eq "vmk0"}).IP }},
@{N="vCenter Name";E={[System.Net.Dns]::GetHostEntry(($_ | Get-View).Summary.ManagementServerIp).HostName}},
@{N="vCenter IP Address";E={($_ | Get-View).Summary.ManagementServerIp}},
@{N=“Model“;E={($_ | Get-View).Hardware.SystemInfo.Vendor+ “ “ + ($_ | Get-View).Hardware.SystemInfo.Model}},
@{N='ServiceTag';E={($_.ExtensionData.Hardware.SystemInfo.OtherIdentifyingInfo | where {$_.IdentifierType.Key -eq "ServiceTag"}).IdentifierValue}},
@{N="CPU Model";E={($_ | Get-View).Summary.Hardware.CPUModel}},
@{N=“CPU“;E={“SOC:“ + ($_ | Get-View).Hardware.CpuInfo.NumCpuPackages + “ CORE:“ + ($_ | Get-View).Hardware.CpuInfo.NumCpuCores + “ MHZ:“ + [math]::round(($_ | Get-View).Hardware.CpuInfo.Hz / 1000000, 0)}},
@{N="HT Enable";E={($_).HyperthreadingActive}},
@{N="CPU-TotalGHZ";E={“” + [Math]::Round($_.CpuTotalMhz/1000,0) + "GHz"}},
@{N='CPU-UsedGHz';E={“” + [math]::Round($_.CpuUsageMhz/1000,0) + "GHz"}},
@{N='CPU-FreeGHz';E={“” + [math]::Round(($_.CpuTotalMhz - $_.CpuUsageMhz)/1000,0) + "GHz"}},
@{N='MEM-TotalGB';E={“” + [math]::Round($_.MemoryTotalGB,0) + "GB"}},
@{N='MEM-UsedGB';E={“” + [math]::Round($_.MemoryUsageGB,0) + "GB"}},
@{N='MEM-FreeGB';E={“” + [math]::Round(($_.MemoryTotalGB - $_.MemoryUsageGB),0) + "GB"}},
@{N='Version & Build Number';E={($_ | Get-View).Config.Product.FullName}},
@{N="UptimeDays";E={New-Timespan -Start $_.ExtensionData.Summary.Runtime.BootTime -End (Get-Date) | Select -ExpandProperty Days}},
@{N="ConfigurationStatus"; E={$_.ExtensionData.ConfigStatus}},
@{N="OverallStatus"; E={$_.ExtensionData.OverallStatus}}  | sort Hostname |
ConvertTo-HTML -head $head -Body "<H2>Info: ESXi Host</H2>" |
Set-CellColor -Property OverallStatus -Color Orange -Filter "OverallStatus -eq 'Yellow'" -Row |
Set-CellColor -Property OverallStatus -Color Red -Filter "OverallStatus -eq 'Red'" -Row |
Set-CellColor -Property ConfigurationStatus -Color Orange -Filter "ConfigurationStatus -eq 'Yellow'" -Row |
Set-CellColor -Property ConfigurationStatus -Color Red -Filter "ConfigurationStatus -eq 'Red'" -Row |
Set-CellColor -Property UptimeDays -Color Red -Filter "UptimeDays -eq '1'" |
Out-File -Append $Outputfile
DisConnect-VIServer -Server * -Force -Confirm:$false
Write-Host ""
Write-Host "Fetching ESXi Host Information Completed" -ForegroundColor Green
#############
# VM Report #
#############
Write-Host ""
Write-Host "Fetching VM Information" -ForegroundColor Green
Function Get-VMInventory
{
foreach($ESXi1 in $ESXiList) 
{
$ConnectvCenter = Connect-VIServer -Server $ESXi1 -Credential $VIcred1
Write-Host ""
Write-Host "Collecting details from $ESXi1" -ForegroundColor Yellow
$vms = get-vm
$vms | Select @{N="VM Name";E={($_ | Get-View).Name}},
            @{N="PowerState";E={($_ | Get-View).summary.runtime.PowerState}},
            @{N='VM Host';E={$_.VMHost.Name}},
            @{N="Guest OS";E={$_.ExtensionData.Config.GuestFullName}},
            @{N="TotalCPU";E={[Math]::Round(($_ | Get-View).summary.config.NumCpu,0)}},
            @{N="CPU Usage Avg %";E={[Math]::Round((($_ | Get-Stat -Stat cpu.usage.average -Start (Get-Date).AddDays(-1) -IntervalMins 60 | Measure-Object Value -Average).Average),0)}},
            @{N="TotalMemGB";E={[Math]::Round(($_ | Get-View).summary.config.MemorysizeMB/1024,0)}},
            @{N="Mem Usage Avg %";E={[Math]::Round((($_ | Get-Stat -Stat mem.usage.average -Start (Get-Date).AddDays(-1) -IntervalMins 60 | Measure-Object Value -Average).Average),0)}},
            @{N="Total SpaceGB";E={[math]::Round(($_.ExtensionData.Summary.Storage.Committed + $_.ExtensionData.Summary.Storage.UnCommitted)/1GB,0)}},
            @{N="Used SpaceGB";E={[math]::Round($_.ExtensionData.Summary.Storage.Committed/1GB,0)}},
            @{N="Hardware ver.";E={$_.ExtensionData.config.Version}},
            @{N="VMTools ver.";E={$_.ExtensionData.config.tools.toolsversion}},
            @{N="VMToolsStatus";E={$_.ExtensionData.guest.toolsstatus}},
            @{N="ToolsState";E={$_.Guest.State}},
            @{N="OverallStatus";E={$_.ExtensionData.Summary.OverallStatus}}             
$DisconnectvCenter = disconnect-viserver -server * -force -confirm:$false
}
}
Get-VMInventory | sort "VM Name" | ConvertTo-Html -Head $head -Body "<H2>Info: Virtual Machines</H2>" |
Set-CellColor -Property OverallStatus -Color Orange -Filter "OverallStatus -eq 'Orange'" -Row |
Set-CellColor -Property OverallStatus -Color Red -Filter "OverallStatus -eq 'Red'" -Row |
Set-CellColor -Property OverallStatus -Color Green -Filter "OverallStatus -eq 'green'" |
Set-CellColor -Property ToolsState -Color Green -Filter "ToolsState -eq 'running'" | 
Set-CellColor -Property ToolsState -Color Red -Filter "ToolsState -eq 'NotRunning'" |
Set-CellColor -Property VMToolsStatus -Color Green -Filter "VMToolsStatus -eq 'toolsOk'" | 
Set-CellColor -Property VMToolsStatus -Color Orange -Filter "VMToolsStatus -eq 'toolsOld'" |
Set-CellColor -Property VMToolsStatus -Color Red -Filter "VMToolsStatus -eq 'toolsNotRunning'" |
Set-CellColor -Property VMToolsStatus -Color Red -Filter "VMToolsStatus -eq 'toolsNotInstalled'" |
Out-File -Append $Outputfile
Write-Host ""
Write-Host "Fetching VM Information Completed" -ForegroundColor Green
##################
# Datastore Info #
##################
Write-Host ""
Write-Host "Fetching Datastore Information" -ForegroundColor Green
Function Get-DSInventory
{
foreach($ESXi2 in $ESXiList) 
{
$ConnectvCenter = Connect-VIServer -Server $ESXi2 -Credential $VIcred1
Write-Host ""
Write-Host "Collecting details from $ESXi2" -foregroundcolor Yellow
$DS = Get-VMHost | Get-Datastore
$DS | Select-Object -Property  @{N="Datastore Name";E={$_.Name}},
            @{N="Hostname";E={($_ | Get-VMHost).name}},
            @{N="Type";E={($_.type)+ " " + ($_.FileSystemVersion)}},
            @{N="CapacityGB";E={[math]::Round($_.CapacityGB,0)}},
            @{N="FreeSpaceGB";E={[math]::Round($_.FreeSpaceGB,0)}},
            @{N='UsedGB';E={[math]::Round($_.CapacityGB - $_.FreeSpaceGB,0)}},
            @{N="SpaceforPerformanceGB";E={[math]::Round($_.CapacityGB * 0.1,0)}},
            @{N="AvailablespaceGB";E={[math]::Round($_.FreespaceGB - $_.SpaceforPerformanceGB,0)}},
            @{N="PercentFree";E={[math]::Round(100 * $_.FreeSpaceGB/$_.CapacityGB,0)}}
$DisconnectvCenter = disconnect-viserver -server * -force -confirm:$false
}
}
Get-DSInventory | Sort-Object PercentFree | ConvertTo-HTML -head $head -Body "<H2>Info: DataStore</H2>" |
Set-CellColor -Property PercentFree -Color red -Filter "PercentFree -le 10" -Row |
Out-File -Append $Outputfile
Write-Host ""
Write-Host "Fetching Datastore Information Completed" -ForegroundColor Green
####################
# VM Snapshot Info #
####################
Write-Host ""
Write-Host "Fetching VM Snapshot Information" -ForegroundColor Green
Function Get-SnapInventory
{
foreach($ESXi3 in $ESXiList) 
{
$ConnectESXi = Connect-VIServer -Server $ESXi3 -Credential $VIcred1
Write-Host ""
Write-Host "Collecting details from $ESXi3" -ForegroundColor Yellow
$vmsnapshot = get-vm | Get-Snapshot
$vmsnapshot | Select @{N="VM Name";E={$_.VM.Name}},
            @{N="Power State";E={$_.PowerState}},
            @{N='VM Host';E={$ESXi3}},
            Name,
            @{N="DaysOld";E={((Get-Date) - $_.Created).Days}},
            @{N="SizeGB"; E={ [math]::round( $_.SizeGB, 0) }},
            Created,
            Description                        
$DisconnectESXi = disconnect-viserver -server * -force -confirm:$false
}
}
Get-SnapInventory | sort "VM Name" | ConvertTo-Html -Head $head -Body "<H2>Info: VM Snapshot</H2>" | 
Set-CellColor -Property DaysOld -Color green -Filter "DaysOld -le 2" |
Set-CellColor -Property DaysOld -Color Red -Filter "DaysOld -gt 2" |
Out-File -Append $Outputfile
Write-Host ""
Write-Host "Fetching VM Snapshot Information Completed" -ForegroundColor Green
#################
# VM CDROM Info #
#################
Write-Host ""
Write-Host "Fetching VM CDROM Information" -ForegroundColor Green
Function Get-CDROMInventory
{
foreach($ESXi4 in $ESXiList) 
{
$ConnectESXi = Connect-VIServer -Server $ESXi4 -Credential $VIcred1
Write-Host ""
Write-Host "Collecting details from $ESXi4" -ForegroundColor Yellow
$FullVM = Get-View -ViewType VirtualMachine
$FullVM | Where-Object {$_.runtime.powerState -eq "PoweredOn"} | 
   % { $VMName = $_.Name; $_.config.hardware.device | Where-Object {($_ -is [VMware.Vim.VirtualFloppy] -or $_ -is [VMware.Vim.VirtualCdrom]) -and $_.Connectable.Connected} | 
      Select-Object @{Name="VMName"; Expression={ $VMName}},
             @{N='VM Host';E={$ESXi4}},
             @{Name="Device Type"; Expression={ $_.GetType().Name}},
             @{Name="Device Name"; Expression={ $_.DeviceInfo.Label}},
             @{Name="Device Backing"; Expression={ $_.DeviceInfo.Summary}}
     }                      
$DisconnectESXi = disconnect-viserver -server * -force -confirm:$false
}
}
Get-CDROMInventory | sort "VMName" | ConvertTo-Html -Head $head -Body "<H2>Info: VM CDROM State</H2>" | 
Out-File -Append $Outputfile
Write-Host ""
Write-Host "Fetching VM CDROM Information Completed" -ForegroundColor Green
#####################
# VM Created/Cloned #
#####################
Write-Host ""
Write-Host "Fetching VM Created/Cloned Information" -ForegroundColor Green
Connect-VIServer -server $VCSAlist -Credential $VIcred
Write-Host ""
Write-Host "Collecting details from $VCSAList" -ForegroundColor Yellow
$CDT = Get-Date # CDT stands for 'Current Date and Time'
Get-VM | Get-VIEvent -Types Info -Start $CDT.AddDays(-1) -Finish $CDT |`
Where {$_ -is [Vmware.vim.VmBeingDeployedEvent]`
-or $_ -is [Vmware.vim.VmCreatedEvent]`
-or $_ -is [Vmware.vim.VmRegisteredEvent]`
-or $_ -is [Vmware.vim.VmBeingClonedEvent]}|`
Sort CreatedTime -Descending | Select @{ Name="VM"; Expression={$_.Vm.Name}},@{N=”Host”; E={$_.Host.Name}},CreatedTime, UserName, FullFormattedMessage | 
ConvertTo-Html -Head $head -Body "<H2>Info: VMs Created or Cloned Event (-1 days)</H2>" | 
Out-File -Append $Outputfile
Disconnect-VIServer -server * -force -Confirm:$false
Write-Host ""
Write-Host "Fetching VM Created/Cloned Information Completed" -ForegroundColor Green
##############
# VM Removed #
##############
Write-Host ""
Write-Host "Fetching VM Removed Information" -ForegroundColor Green
Connect-VIServer -server $VCSAlist -Credential $VIcred
Write-Host ""
Write-Host "Collecting details from $VCSAList" -ForegroundColor Yellow
Get-VIEvent -Start (Get-Date).AddDays(-1) -MaxSamples ([int]::MaxValue) |
where{$_ -is [VMware.Vim.VmRemovedEvent]} | Sort CreatedTime -Descending | Select @{N='VM';E={$_.Vm.Name}},@{N=”Host”; E={$_.Host.Name}},CreatedTime, UserName,FullFormattedMessage |
ConvertTo-Html -Head $head -Body "<H2>Info: VMs Removed Event (-1 days)</H2>" | 
Out-File -Append $Outputfile
Disconnect-VIServer -server * -force -Confirm:$false
Write-Host ""
Write-Host "Fetching VM Removed Information Completed" -ForegroundColor Green
###############################
# VM Power ON/Off/Reset Event #
###############################
Write-Host ""
Write-Host "Fetching VM Power ON/Off/Reset Information" -ForegroundColor Green
Connect-VIServer -server $VCSAlist -Credential $VIcred
Write-Host ""
Write-Host "Collecting details from $VCSAList" -ForegroundColor Yellow
Get-VIEvent -Start (Get-Date).AddDays(-1) -MaxSamples ([int]::MaxValue) |
where{$_ -is [VMware.Vim.VmPoweredOffEvent] -or
      $_ -is [VMware.Vim.VmGuestShutdownEvent] -or
      $_ -is [VMware.Vim.VmPoweredOnEvent] -or
      $_ -is [VMware.Vim.VmResettingEvent] -or
      $_ -is [VMware.Vim.VmDasBeingResetEvent] -or
      $_ -is [VMware.Vim.VmDasBeingResetWithScreenshotEvent]} | Sort CreatedTime -Descending |
Select @{N='VM';E={$_.Vm.Name}},@{N=”Host”; E={$_.Host.Name}},CreatedTime,UserName,FullFormattedMessage |
ConvertTo-Html -Head $head -Body "<H2>Info: VM Power ON/Off/Reset Event (-1 days)</H2>" | 
Out-File -Append $Outputfile
Disconnect-VIServer -server * -force -Confirm:$false
Write-Host ""
Write-Host "Fetching VM Power ON/Off/Reset Event Information Completed" -ForegroundColor Green
#############################
# Guest OS drive with <=1GB #
#############################
Write-Host ""
Write-Host "Fetching Guest OS drive with <=1GB Information" -ForegroundColor Green
Function Get-LessVMDiskSpace
{
foreach($ESXi5 in $ESXiList) 
{
$ConnectESXi = Connect-VIServer -Server $ESXi5 -Credential $VIcred1
Write-Host ""
Write-Host "Collecting details from $ESXi5" -ForegroundColor Yellow
$MBFree = 1024
$MBDiskMinSize = 1024
$FullVM = Get-View -ViewType VirtualMachine | Where-Object {-not $_.Config.Template}
$AllVMs = $FullVM | Where-Object {-not $_.Config.Template -and $_.Runtime.PowerState -eq "poweredOn" -And ($_.Guest.toolsStatus -ne "toolsNotInstalled" -And $_.Guest.ToolsStatus -ne "toolsNotRunning")} | Select-Object *, @{N="NumDisks";E={@($_.Guest.Disk.Length)}} | Sort-Object -Descending NumDisks
ForEach ($VMdsk in $AllVMs){
   Foreach ($disk in $VMdsk.Guest.Disk){
      if ((([math]::Round($disk.Capacity / 1MB)) -gt $MBDiskMinSize) -and (([math]::Round($disk.FreeSpace / 1MB)) -lt $MBFree)){
         New-Object -TypeName PSObject -Property ([ordered]@{
            "Name"            = $VMdsk.name
            "Path"            = $Disk.DiskPath
            "Capacity (MB)"   = ([math]::Round($disk.Capacity/ 1MB))
            "Free Space (MB)" =([math]::Round($disk.FreeSpace / 1MB))
         })
      }
   }
}                              
$DisconnectESXi = disconnect-viserver -server * -force -confirm:$false
}
}
Get-LessVMDiskSpace | sort "Name" | ConvertTo-Html -Head $head -Body "<H2>Info: Guest OS drive with <=1GB</H2>" | 
Out-File -Append $Outputfile
Write-Host ""
Write-Host "Fetching Guest OS drive with <=1GB Information Completed" -ForegroundColor Green
Write-Host ""
Write-Host "Updating Report End time" -ForegroundColor Yellow
ConvertTo-Html -body "<H5>Report End time: $(Get-Date -Format g) </H5>" -head $head |  Out-File -Append $OutputFile
Write-Host "Report End time Updated" -ForegroundColor Yellow
#########
# EMail #
#########
Write-Host ""
Write-Host "Sending Email with attachment" -ForegroundColor Yellow
$smtpServer = 'smtprelay.domain.com'
$to = ""
$cc = ""
$from = 'VMwareHealthCheck@rs.com'
$body = "
Hi Team,

Please find the attached VMware Health Check report generated on $(Get-Date -Format g)(CET).

Thanks,
Team
"
 
Send-MailMessage -SmtpServer $smtpServer -Subject "CSM VMware Health Check report  $(Get-Date -format dd.MM.yyyy)" -To $to -CC $cc -From $from -Attachments $Outputfile -Body $body
Write-Host ""
Write-Host "Email with attachment sent" -ForegroundColor Yellow
Write-Host ""
Write-Host "Health Check Report Completed" -ForegroundColor Blue