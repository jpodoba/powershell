<#
    .SYNOPSIS
        Script for retrive all PIP via Rest Api.
  
    .DESCRIPTION
        Script for retrive all PIP via Rest Api.
        You need to grant your Service Principal an appropriate role to subscription or resource group to allow query resources.

    .PARAMETER subscriptionId
        Mandatory. Id of your Azure subscription

    .PARAMETER ApplicationClientID
        Mandatory. Service Principal Application ID

    .PARAMETER ClientSecret
        Mandatory. Service Principal Secret

    .EXAMPLE
         Get-RestApiAzPublicIpAddress -subscriptionId "11111111-1111-1111-1111-111111111111" -ApplicationClientID "11111111-1111-1111-1111-111111111111" -ClientSecret "SuperSecretSPNPassword"

    .NOTES
        Author:     Jakub Podoba
        Created:    06/10/2019

#>
function Get-RestApiAzPublicIpAddress {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $subscriptionId,

        [Parameter(Mandatory = $true)]
        [string]
        $ApplicationClientID,

        [Parameter(Mandatory = $true)]
        [string]
        $ClientSecret
    )
    
    try {
        Write-Host "`nSelecting Azure subscription..."
        Select-AzSubscription -SubscriptionId $subscriptionId -ErrorAction Stop
    }
    catch {
        throw "Unable to select Azure subscription: $subscriptionId, because following error: $_"
    }
    
    $tenantID = (Get-AzTenant).Id
    $graphUrl = 'https://management.azure.com'
    $tokenEndpoint = "https://login.microsoftonline.com/$tenantID/oauth2/token"
    
    $tokenHeaders = @{
        "Content-Type" = "application/x-www-form-urlencoded";
    }
    
    $tokenBody = @{
        "grant_type"    = "client_credentials";
        "client_id"     = "$ApplicationClientID";
        "client_secret" = "$ClientSecret";
        "resource"      = "$graphUrl";
    }
    
    # Post request to get the access token so we can query the Microsoft Graph (valid for 1 hour)
    $response = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Headers $tokenHeaders -Body $tokenBody
    
    # Create the headers to send with the access token obtained from the above post
    $queryHeaders = @{
        "Content-Type"  = "application/json"
        "Authorization" = "Bearer $($response.access_token)"
    }
    
    # Create the URL to access all public ip addreses and send the query to the URL along with authorization headers
    $queryUrl = $graphUrl + "/subscriptions/$subscriptionId/providers/Microsoft.Network/publicIPAddresses?api-version=2019-09-01"
    $ipList = Invoke-RestMethod -Method Get -Uri $queryUrl -Headers $queryHeaders
    
    # Output the ipList
    Write-Output $ipList.value
}