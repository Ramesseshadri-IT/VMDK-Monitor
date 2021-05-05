$ScriptFromGithHub = Invoke-WebRequest https://raw.githubusercontent.com/VMDK-Monitor/master/VMDK-Monitor/VMHC.ps1
Invoke-Expression $($ScriptFromGithHub.Content)
