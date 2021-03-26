<#
.SYNOPSIS 
Overview of NUMA locality per VM per cluster.

NUMA statistics per VM per cluster. According to Yellow-Bricks the LocalityPct (N%L) should preferably be above 80%.
With this script we check our environment to see what the LocalityPct (N%L) per VM is.

Be aware this is just a single snapshot in time and is meant to give you a quick glance, based on the assumption 
that clusters that have all VMs steady above 95% locality, will not turn bad in a few minutes.

Read more about NUMA at Frank Denneman's site: NUMA.AF. My script is based on Get-EsxtopAPI.ps1 by William Lam.

.NOTES Author:       Gabrie van Zanten
.NOTES Site:         www.GabesVirtualWorld.com
.NOTES Reference:    https://github.com/TheGabeMan/NUMAlocality-esxtop
.NOTES Reference:    http://www.GabesVirtualWorld.com
.NOTES Reference:    https://github.com/lamw/vghetto-scripts/blob/master/powershell/Get-EsxtopAPI.ps1
.NOTES Reference:    https://www.virtuallyghetto.com/2017/02/using-the-vsphere-api-in-vcenter-server-to-collect-esxtop-vscsistats-metrics.html
.PARAMETER Vmhost
  ESXi host
.EXAMPLE
  PS> Get-VMHost -Name "esxi-1" | Get-EsxtopAPI
#>


Function Get-EsxTopNUMA {
        param(
            $VMHost
        )
    $serviceManager = Get-View ($global:DefaultVIServer.ExtensionData.Content.serviceManager) -property "" -ErrorAction SilentlyContinue
    $locationString = "vmware.host." + $VMHost.Name
    $services = $serviceManager.QueryServiceList($null,$locationString)

    ## Filter the services on esxtop. Another option would be vscsistat
    $services = $services | Where-Object { $_.ServiceName -eq "Esxtop" } 
    $serviceView = Get-View $services.Service -Property "entity"
    
    ## Read the counters esxtop can provider
    $esxtopCounters = $serviceView.ExecuteSimpleCommand("CounterInfo")

    ## Read the stats from esxtop
    $esxtopStats = $serviceView.ExecuteSimpleCommand("FetchStats")

    ## After collecting stats, you will need to run the "freestats" operation and this will release any server side resources used during the collection.
    $serviceView.ExecuteSimpleCommand("freestats")

    ## Counter info comes in as one long string with linefeeds, like this:
    ## |PCPU|NumOfLCPUs,U32|NumOfCores,U32|NumOfPackages,U32|
    ## |LCPU|LCPUID,U32|CPUHz,U64|UsedTimeInUsec,U64|HaltTimeInUsec,U64|CoreHaltTimeInUsec,U64|ElapsedTimeInUsec,U64|BusyWaitTimeInUsec,U64|
    ## |PMem|PhysicalMemInKB,U32|COSMemInKB,U32|KernelManagedInKB,U32|NonkernelUsedInKB,U32|FreeMemInKB,U32|PShareSharedInKB,U32|PShareCommonInKB,U32|SchedManagedInKB,U32|SchedMinFreeInKB,U32|SchedReservedInKB,U32|SchedAvailInKB,U32|SchedState,U32|SchedStateStr,CSTR|MemCtlMaxInKB,U32|MemCtlCurInKB,U32|MemCtlTgtInKB,U32|SwapUsedInKB,U32|SwapTgtInKB,U32|SwapReadInKB,U32|SwapWrtnInKB,U32|ZippedInKB,U32|ZipSavedInKB,U32|MemOvercommitInPct1Min,U32|MemOvercommitInPct5Min,U32|MemOvercommitInPct15Min,U32|NumOfNUMANodes,U32|
    ## |NUMANode|NodeID,U32|TotalInPages,U32|FreeInPages,U32|

    ## We now split the counter info in separate headers
    $HeaderInLines = $esxtopCounters -split "`n" | select-string "|"

    ## The NUMA stats can be found onder 'SchedGroup'
    $HeaderSchedGroup = $HeaderInLines | where-object {$_.Line -match "[|]SchedGroup[|]"}
    $Headers = $HeaderSchedGroup -replace ",.{1,4}[|]","|" 
    $Headers = $Headers.split("|", [StringSplitOptions]::RemoveEmptyEntries) 
 
    ## We now split the stats into separate values
    $DataInLines = $esxtopStats -split "`n" | Select-String "|"
    $DataSchedGroup = $DataInLines | where-object {$_.Line -match "[|]SchedGroup[|]"}

    ## Gebruik van [|] ipv alleen | omdat het een speciaal karakter is in een string
    ## Gebruik van [.] ipv alleen . omdat het een speciaal karakter is in een string
    $DataSchedGroup = $DataSchedGroup | Where-Object {$_.line -match "[|]vm[.]" }

    ## Stats are now filter to just VM entries:
    ## |SchedGroup|13567824|vm.4430541|1|1|VMDC002|10416|0|-1|-3|-1|1|mhz|0|-1|-3|80896|4|kb|1|2|0|0|0|0|3913712|100|0|11|2|2|1|4430541|
    ## |SchedGroup|12883482|vm.4316334|1|1|VMTEST|15260|0|-1|-3|-1|1|mhz|0|-1|-3|93184|4|kb|1|1|0|0|0|0|8179712|100|0|9|3|2|1|4316334|
    ## |SchedGroup|13558449|vm.4429332|1|1|VMDF02|1000|0|-1|-3|-1|1|mhz|0|-1|-3|77824|4|kb|1|2|0|0|0|0|3494260|100|0|11|1|2|1|4429332|

    $DataSetRAW = $DataSchedGroup -replace '^\||\|$'
    $DataSetRAW = $DataSetRAW -replace "[|]", ","
    
    ## Convert to CSV to get headers combined with stats in one object
    $DataSet = $DataSetRAW | ConvertFrom-Csv -Delimiter "," -Header $Headers

    $DataSet

}

##########
# $test = true to skip logins for easy testing
$test = $true
If( !$test)
{
    ## vCenter name:
    $vCenterServer = Read-Host "Which vCenter?"
    $vCenterLogin = Get-Credential -Message "Log in to vCenter Server:" 
    # Connect to vCenter Server
    Connect-VIServer -Server $vCenterServer -Credential $vCenterLogin | out-null   
}

$ClusterCheck = get-cluster | Out-GridView -Title "Select one or more clusters to check." -PassThru
$TotalOverview = @()
ForEach( $cluster in $ClusterCheck)
{
    ForEach( $ESXi in ( $cluster | get-vmhost | Sort-Object Name ))
    {
        write-host "Reading $($ESXi.name)"
        $DataPerHost = Get-EsxTopNUMA $ESXi
        $DataPerHost | Add-Member -MemberType NoteProperty "vCenter" -Value $vCenterServer
        $DataPerHost | Add-Member -MemberType NoteProperty "esxihost" -Value $($esxi.name)
        $DataPerHost | Add-Member -MemberType NoteProperty "cluster" -Value $($cluster.name)
     
        $TotalOverview += $DataPerHost
    }

}


### From Get-EsxtopNuma we also receive empty lines because of the conversion from data to CSV object.
### I filter them out by filtering on vmname -ne $null
$TotalOverview = $TotalOverview | Where-Object{$_.vmname -ne $null} | Sort-Object vcenter, cluster, esxihost, HomeNodes, vmname

$HTMLPage = ""
$HTMLPage += "<h1>Overview of NUMA locality</h1>"
$HTMLPage += "<p>NUMA statistics per VM per cluster. According the <a href=http://www.yellow-bricks.com/esxtop/>Yellow-Bricks</a> the LocalityPct (N%L) should preferably be above 80%.<br>"
$HTMLPage += "Be aware this is just a single snapshot in time and is meant to give you a quick glance, based on the assumption that clusters that have all VMs steady above 95% locality, will not turn bad in a few minutes.</p>"

$ClusterList = $totaloverview | Sort-Object cluster -Unique | Select-Object cluster,vcenter
ForEach( $cluster in $ClusterList)
{
    write-host "Cluster: $($cluster.cluster) $($cluster.vcenter)"

    $HTMLVMList = $TotalOverview  | select esxihost, VMName, IsNUMAValid, HomeNodes, NumOfBalanceMigrations, NumOfLocalitySwap, NumOfLoadSwap, `
                                    @{n="RemoteMemoryGB";e={[math]::Round($_.RemoteMemoryInKB/1024/1024,2)}}, @{n="LocalMemoryGB";e={[math]::Round($_.LocalMemoryInKB/1024/1024,2)}}, @{n="LocalityPct";e={($_.LocalityPct -as [int])}}, NumOfNUMANodes |  `
                                    Where-Object{ $_.LocalityPct -lt 80} | `
                                    Sort-Object LocalityPct | `
                                    ConvertTo-Html -Property esxihost, VMName, IsNUMAValid, HomeNodes, NumOfBalanceMigrations, NumOfLocalitySwap, NumOfLoadSwap, RemoteMemoryGB, LocalMemoryGB, LocalityPct, NumOfNUMANodes `
                                    -PreContent "<h1>Cluster: $($cluster.cluster) - $($cluster.vCenter)</h1><br><h3>VMs with less than 80% locality</h3>" -as Table
    $HTMLPage += $HTMLVMList

    $HTMLVMList = $TotalOverview  | select esxihost, VMName, IsNUMAValid, HomeNodes, NumOfBalanceMigrations, NumOfLocalitySwap, NumOfLoadSwap, `
                                    @{n="RemoteMemoryGB";e={[math]::Round($_.RemoteMemoryInKB/1024/1024,2)}}, @{n="LocalMemoryGB";e={[math]::Round($_.LocalMemoryInKB/1024/1024,2)}}, @{n="LocalityPct";e={($_.LocalityPct -as [int])}}, NumOfNUMANodes |  `
                                    Where-Object{ $_.LocalityPct -ge 80} | `
                                    Sort-Object LocalityPct | `
                                    ConvertTo-Html -Property esxihost, VMName, IsNUMAValid, HomeNodes, NumOfBalanceMigrations, NumOfLocalitySwap, NumOfLoadSwap, RemoteMemoryGB, LocalMemoryGB, LocalityPct, NumOfNUMANodes `
                                    -PreContent "<h3>VMs with more than 80% locality</h3>" -as Table
    $HTMLPage += $HTMLVMList
}
$HTMLPage += "<h6>Script is based on <a href=https://github.com/lamw/vghetto-scripts/blob/master/powershell/Get-EsxtopAPI.ps1>Get-EsxtopAPI.ps1</a> by <a href=https://www.virtuallyghetto.com/2017/02/using-the-vsphere-api-in-vcenter-server-to-collect-esxtop-vscsistats-metrics.html>William Lam</a></h6>"
$HTMLPage += "<h6><a href=https://github.com/TheGabeMan/NUMAlocality-esxtop>NUMAlocality-esxtop</a> by <a href=http://www.gabesvirtualworld.com/find-vm-numa-locality-with-powershell/>Gabrie van Zanten</a></h6>"

$ScriptPath = "H:\"
$CSSFile = "H:\ccs-code.css"
convertto-html -body $HTMLPage  -CSSUri $CSSFile -Title "NUMA Locality" | Set-Content $("h:\numa-htmlreport.html")
Invoke-Expression $("h:\numa-htmlreport.html")
    
If( !$test)
{
    # Disconnect met vCenter Server
    Disconnect-VIServer -Server $vCenterServer -Confirm:$false | out-null   
}
