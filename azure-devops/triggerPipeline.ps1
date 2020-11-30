<#
    .SYNOPSIS
        Script for remote trigger Azure DevOps pipelines.
  
    .DESCRIPTION
        Script was created for easily remote trigger Azure DevOps pipelines.
        Script using REST API for Azure DevOps to handle that process.
        Script can parse "PAT" - personal access token for authenticate to Azure DevOps but is not mandatory. 
        If "PAT" will be missing script will retrive token from Azure DevOps agent. 
        Script was created for organization "hotbee". 
        If you need to run script in other organization you need to adjust the code for it.
        After trigger the pipeline script will wait until pipeline will end.

    .PARAMETER azureDevOpsProjectName
        Mandatory. Name of the project in Azure DevOps.

    .PARAMETER pipelineName
        Mandatory. Name of the pipeline in Azure DevOps.

    .PARAMETER mode
        Mandatory. Type of the pipeline in Azure DevOps, allowed values 'Release', 'Build'.

    .PARAMETER azureDevOpsPAT
        Optional. Personal access tokens in Azure DevOps.
      
    .EXAMPLE
        .\triggerPipeline.ps1 -azureDevOpsProjectName "exampleProject" -pipelineName "HotBee-release-pipeline" -mode "Release" -azureDevOpsPAT "secretPersonalAccessToken"
        Script will trigger Azure DevOps release pipeline with name "HotBee-pipeline" from project "exampleProject" using personal token for authentication.

     .EXAMPLE
        .\triggerPipeline.ps1 -azureDevOpsProjectName "exampleProject" -pipelineName "HotBee-build-pipeline" -mode "Build" -azureDevOpsPAT "secretPersonalAccessToken"
        Script will trigger Azure DevOps release pipeline with name "HotBee-pipeline" from project "exampleProject" using personal token for authentication.

    .EXAMPLE
        .\triggerPipeline.ps1 -azureDevOpsProjectName "exampleProject" -pipelineName "HotBee-release-pipeline" -mode "Release"
        Script will trigger Azure DevOps release pipeline with name "HotBee-pipeline" from project "exampleProject" using agent token for authentication.

    .EXAMPLE
        .\triggerPipeline.ps1 -azureDevOpsProjectName "exampleProject" -pipelineName "HotBee-build-pipeline" -mode "Build"
        Script will trigger Azure DevOps release pipeline with name "HotBee-pipeline" from project "exampleProject" using agent token for authentication.

    .NOTES
        Author:     Jakub Podoba
        Created:    06/02/2020
#>
param(
    [Parameter(Mandatory = $true)]
    [string]
    $azureDevOpsProjectName,

    [Parameter(Mandatory = $true)]
    [string]
    $pipelineName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Release', 'Build')]
    [string]
    $mode,

    [Parameter(Mandatory = $false)]
    [string]
    $azureDevOpsPAT
)

$ErrorActionPreference = 'Stop';

$organizationUrl = $env:SYSTEM_TASKDEFINITIONSURI
if (!($organizationUrl)) {
    $organizationUrl = "https://hotbee.visualstudio.com/"
}

$releaseUrl = $env:SYSTEM_TEAMFOUNDATIONSERVERURI
if (!($releaseUrl)) {
    $releaseUrl = "https://hotbee.vsrm.visualstudio.com/"
}

switch ($mode) {
    "Release" {
        #uri
        $baseReleaseUri = "$($releaseUrl)$($azureDevOpsProjectName)/";
        $getUri = "_apis/release/definitions?searchText=$($pipelineName)&`$expand=environments&isExactNameMatch=true";
        $runRelease = "_apis/release/releases?api-version=5.0-preview.8"

        $uri = "$($baseReleaseUri)$($getUri)"
        $runUri = "$($baseReleaseUri)$($runRelease)"

    }
    "Build" {
        #uri
        $baseUri = "$($organizationUrl)$($azureDevOpsProjectName)/";
        $getUri = "_apis/build/definitions?name=$(${pipelineName})";
        $runBuild = "_apis/build/builds?api-version=5.0-preview.5"

        $uri = "$($baseUri)$($getUri)"
        $runUri = "$($baseUri)$($runBuild)"
    }
}

if ($azureDevOpsPAT) {
    # Base64-encodes the Personal Access Token (PAT) appropriately
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("token:{0}" -f $azureDevOpsPAT)))
    $azureDevOpsHeaders = @{Authorization = ("Basic {0}" -f $base64AuthInfo) };
}
else {
    $azureDevOpsHeaders = @{ Authorization = "Bearer $env:System_AccessToken" }
}

$pipelineDefinitions = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -Headers $azureDevOpsHeaders;

if ($pipelineDefinitions -and $pipelineDefinitions.count -eq 1) {
    $specificUri = $pipelineDefinitions.value[0].url
    $definition = Invoke-RestMethod -Uri $specificUri -Method Get -ContentType "application/json" -Headers $azureDevOpsHeaders;

    if ($definition) {
        switch ($mode) {
            "Release" {
                $splat = New-Object PSObject -Property @{            
                    definitionId = $definition.id                 
                    isDraft      = $false              
                    description  = $Description 
                    artifacts    = $artifactsItem           
                }
            }
            "Build" {
                $splat = New-Object PSObject -Property @{            
                    definition = New-Object PSObject -Property @{            
                        id = $definition.id                           
                    }
                    #sourceBranch = $Branch
                    reason     = "userCreated"          
                }
            }
        }

        $jsonbody = $splat | ConvertTo-Json -Depth 100

        Write-Host "`n--------------------------------------- Begin -----------------------------------------"
        Write-Host "Starting the pipeline: $pipelineName"
        try {
            $result = Invoke-RestMethod -Uri $runUri -Method Post -ContentType "application/json" -Headers $azureDevOpsHeaders -Body $jsonbody;
        }
        catch {
            if ($_.ErrorDetails.Message) {

                $errorObject = $_.ErrorDetails.Message | ConvertFrom-Json

                foreach ($result in $errorObject.customProperties.ValidationResults) {
                    Write-Warning $result.message
                }
                Write-Error $errorObject.message
            }

            throw $_.Exception 
        }
        Write-Host "Triggered $($mode): $($result.name)"

        do {
            $checkStatus = Invoke-RestMethod -Uri $result.url -Method get -ContentType "application/json" -Headers $azureDevOpsHeaders
            switch ($mode) {
                "Release" {
                    $status = $checkStatus.environments.status
                }
                "Build" {
                    $status = $checkStatus.status
                }
            }
            if ($status -eq "succeeded") {
                Write-Host "The pipeline status is: $status"
            }
            else {
                Write-Host "The pipeline status is: $status, waiting 5s for next checks..."   
            }
            Start-Sleep 5
        } until ($status -ne "inProgress" -and $status -ne "queued" -and $status -ne "notStarted")
        Write-Host "`n---------------------------------------- End ----------------------------------------"
    }
    else {
        Write-Error "The $($mode) definition could not be found."
    }
}
else {
    Write-Error "Problem occured while getting the $($mode)"
}