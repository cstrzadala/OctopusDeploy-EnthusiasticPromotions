#automatically provided variables
$projectName = $OctopusParameters["Octopus.Project.Name"]
$spaceId = $OctopusParameters["Octopus.Space.Id"]
$projectId = $OctopusParameters["Octopus.Project.Id"]

#variables provided from additional packages
$octopusToolsPath = $OctopusParameters["Octopus.Action.Package[OctopusTools].ExtractedPath"]
$octopusVersioningPath = $OctopusParameters["Octopus.Action.Package[Octopus.Versioning].ExtractedPath"]

#variables from the project
$octofrontApiKey = $OctopusParameters["OctofrontSoftwareProblemsAuthToken"]
$octofrontUrl = $OctopusParameters["OctofrontUrl"]
$octopusApiKey = $OctopusParameters["OctopusApiKey"]

#lookup table for "how long the release needs to be in the specified environment, before allowing it to move on"
$waitTimeForEnvironmentLookup = @{
    "Environments-2583" = @{ "Name" = "Branch Instances (Staging)"; "BakeTime" = New-TimeSpan -Hours 2;   }
    "Environments-2621" = @{ "Name" = "Octopus Cloud Tests";        "BakeTime" = New-TimeSpan -Minutes 0; }
    "Environments-2601" = @{ "Name" = "Production";   				"BakeTime" = New-TimeSpan -Minutes 0; }
    "Environments-2584" = @{ "Name" = "Branch Instances (Prod)";    "BakeTime" = New-TimeSpan -Days 1;    }
    "Environments-2585" = @{ "Name" = "Staff";                      "BakeTime" = New-TimeSpan -Days 1;    }
    "Environments-2586" = @{ "Name" = "Friends of Octopus";         "BakeTime" = New-TimeSpan -Days 1;    }
    "Environments-2587" = @{ "Name" = "Early Adopters";             "BakeTime" = New-TimeSpan -Days 7;    }
    "Environments-2588" = @{ "Name" = "Stable";                     "BakeTime" = New-TimeSpan -Days 7;    }
    "Environments-2589" = @{ "Name" = "General Availablilty";       "BakeTime" = New-TimeSpan -Days 1;    }
}


function Test-PipelineBlocked($release) {
    $body = @{
        Product = "OctopusServer";
        Version = $release.Release.Version
    }
    $activeProblems =  (Invoke-restmethod -Uri "$octofrontUrl/api/Problem/ActiveProblems" -Headers @{ 'Authorization' = "Bearer $($octofrontApiKey)"} -Method POST -Body ($body | ConvertTo-Json)).ActiveProblems

    return $activeProblems.Count -gt 0
}

function Get-CurrentEnvironment($progression, $release) {
    $nextEnvironmentId = $release.NextDeployments[0]
    $channelId = $release.Release.ChannelId
    $channelEnvironments = ((,$progression.ChannelEnvironments.PSObject.Properties | where-object { $_.Name -eq $channelId }).Value)
    foreach($environment in $channelEnvironments) {
        if ($environment.Id -eq $nextEnvironmentId) { break; }
        $currentEnvironmentId = $environment.Id
    }
    return $currentEnvironmentId
}

Add-Type -Path "$octopusVersioningPath/lib/netstandard2.0/Octopus.Versioning.dll"

$progression = Invoke-restmethod -Uri "https://deploy.octopus.app/api/$spaceId/progression/$projectId" -Headers @{ 'X-Octopus-ApiKey' = $octopusApiKey }

$promotionCandidates = @{}

Write-Host "Looking for possible releases to promote:"
foreach ($release in $progression.Releases) {
    write-host "--------------------------------------------------------"
    Write-Host "Evaluating candidate release $($release.Release.Version):"
    write-host "--------------------------------------------------------"

    if ($release.NextDeployments.length -eq 0) {
        Write-Host " - Release has already progressed as far as it can."
    } elseif ($release.NextDeployments.length -gt 1) {
        Write-Warning " - Unexpected number of NextDeployments - expected 1, but found $($release.NextDeployments.length)."
        exit 1
    } else {
        $currentEnvironmentId = Get-CurrentEnvironment $progression $release
        $currentEnvironmentName = ($progression.Environments | Where-Object { $_.Id -eq $currentEnvironmentId }).Name
        Write-Host " - Current environment is '$($currentEnvironmentName)'"

        $nextEnvironmentId = $release.NextDeployments[0]
        $nextEnvironmentName = ($progression.Environments | Where-Object { $_.Id -eq $nextEnvironmentId }).Name
        Write-Host " - Next environment is '$($nextEnvironmentName)'"

        $alreadyDeployedEnvironments = @($release.Deployments.PSObject.Properties.Name)
        $deploymentsToNextEnvironment = (,$release.Deployments.PSObject.Properties | where-object { $_.Name -eq $nextEnvironmentId })
        if ($null -ne $deploymentsToNextEnvironment) {
            $deploymentsToNextEnvironment = $deploymentsToNextEnvironment.Value | Sort-Object -Property CompletedTime -Descending
        }
        if ($alreadyDeployedEnvironments.Contains($nextEnvironmentId)) {
            Write-Host " - Deployment to '$nextEnvironmentName' already exists in state $($deploymentsToNextEnvironment[0].State)."
        } else {
            $bakeTime = $waitTimeForEnvironmentLookup[$currentEnvironmentId].BakeTime
            $deploymentsToCurrentEnvironment = (,$release.Deployments.PSObject.Properties | where-object { $_.Name -eq $currentEnvironmentId })
            if ($null -ne $deploymentsToCurrentEnvironment) {
                $deploymentsToCurrentEnvironment = $deploymentsToCurrentEnvironment.Value | Sort-Object -Property CompletedTime -Descending
            }
            
            Write-Host " - Calculated the bake time that releases should stay in environment '$currentEnvironmentName' before being promoted to '$nextEnvironmentName' to be $bakeTime."
            
            if (($deploymentsToCurrentEnvironment.length -gt 0) -and ($deploymentsToCurrentEnvironment[0].CompletedTime.Add($bakeTime) -gt (Get-Date))) {
                Write-Host " - Completion time of last deployment to $currentEnvironmentName was $($deploymentsToCurrentEnvironment[0].CompletedTime) (UTC)"
                Write-Host " - This release is still baking. Will try again later after $($deploymentsToCurrentEnvironment[0].CompletedTime.Add($bakeTime)) (UTC)."
            } else {
            	if ($deploymentsToCurrentEnvironment.length -eq 0) {
                	Write-Host " - Bake time was ignored as there was no deployments to the environment $currentEnvironmentName"
                } else {
                    Write-Host " - Completion time of last deployment to $currentEnvironmentName was $($deploymentsToCurrentEnvironment[0].CompletedTime) (UTC)"
                }
                Write-Host " - Checking Andon cord to see if release pipeline is blocked..."
                if (Test-PipelineBlocked $release) {
                    Write-Host " - Release pipeline is currently blocked with problems. Release will not be promoted."
                } else {
                    Write-Host " - Release pipeline doesn't currently have any blocking problems. Release can be promoted."
                    Write-Host " - Found candidate for promotion - release $($release.Release.Version) to '$nextEnvironmentName' ($nextEnvironmentId)."

                    $key = $release.Release.ChannelId + "|" + $nextEnvironmentId
                    $semanticVersion = New-Object Octopus.Versioning.Semver.SemanticVersion $release.Release.Version
                    if ($promotionCandidates.ContainsKey($key)) {
                        $existing = $promotionCandidates[$key]
                        if ($existing.Version -lt $semanticVersion) {
                            Write-Host " - This is a newer version than the previous promotion candidate ($($existing.Version)). Overriding promotion candidate to this version."
                            $existing.Version = $semanticVersion
                        }
                    } else {
                        $promotionCandidates.Add($key, [PSCustomObject]@{
                            ChannelId       = $release.Release.ChannelId
                            EnvironmentId   = $nextEnvironmentId
                            EnvironmentName = $nextEnvironmentName
                            Version         = $semanticVersion
                        })
                    }
                }
            }
        }
    }
}

write-host "--------------------------------------------------------"
if ($promotionCandidates.Count -eq 0) {
    Write-Host "No promotion candidates found"
} else {
    write-host "Promoting releases:"
    $promotionCandidates.keys | ForEach-Object {
        $promotionCandidate = $promotionCandidates.Item($_)
        Write-Host " - Promoting release '$($promotionCandidate.Version)' to environment '$($promotionCandidate.EnvironmentName)' ($($promotionCandidate.EnvironmentId))."
        & $octopusToolsPath\tools\octo.exe deploy-release --deployTo $promotionCandidate.EnvironmentId --version $promotionCandidate.Version --project "$projectName" --apiKey $OctopusApiKey --server "https://deploy.octopus.app" --space "Octopus Server"
    }
}
