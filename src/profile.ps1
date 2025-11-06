# Azure Functions profile.ps1
if ($env:AZURE_CLIENT_ID) {
    Write-Host "Authenticating with user-assigned managed identity: $($env:AZURE_CLIENT_ID)"
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity -AccountId $env:AZURE_CLIENT_ID | Out-Null
} elseif ($env:MSI_SECRET) {
    Write-Host "Authenticating with system-assigned managed identity"
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity | Out-Null
} else {
    Write-Host "No managed identity configuration found - functions will authenticate individually if needed"
}