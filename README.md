Overview of NUMA locality per VM per cluster.

NUMA statistics per VM per cluster. According to <a href=http://www.yellow-bricks.com/esxtop/>Yellow-Bricks</a> the LocalityPct (N%L) should preferably be above 80%. With this script we check our environment to see what the LocalityPct (N%L) per VM is. 

Be aware this is just a single snapshot in time and is meant to give you a quick glance, based on the assumption that clusters that have all VMs steady above 95% locality, will not turn bad in a few minutes.

Read more about NUMA at Frank Denneman's site: <a href=https://numa.af/>NUMA.AF</a>.

My script is based on <a href=https://github.com/lamw/vghetto-scripts/blob/master/powershell/Get-EsxtopAPI.ps1>Get-EsxtopAPI.ps1</a> by <a href=https://www.virtuallyghetto.com/2017/02/using-the-vsphere-api-in-vcenter-server-to-collect-esxtop-vscsistats-metrics.html>William Lam</a>"
