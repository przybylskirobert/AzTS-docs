# . ".\Remediate-AnonymousAccessOnContainers.ps1"
# # Remove-AnonymousAccessOnContainers   -FailedControlsPath  'abb5301a-22a4-41f9-9e5f-99badff261f8.json'
# function WrapperScript
# {
    # PARAMETER FailedControlsPath
    # Json file path which contain failed controls detail to remediate.
    $files = @(Get-ChildItem *.json)
    $currentLocation = Get-Location
    $remediationScriptsLocation = $currentLocation + "\RemediationScripts\"
    new-item $remediationScriptsLocation -itemtype directory
    foreach ($file in $files) {
        Write-Host "Filename is [$($file)]" 
        $JsonContent =  Get-content -path $file | ConvertFrom-Json
        $SubscriptionId = $JsonContent.SubscriptionId
        $uniqueControls = $JsonContent.UniqueControls
        foreach ($uniqueControl in $uniqueControls){
            if(-Not( Test-Path ($remediationScriptsLocation + $uniqueControl.file_name) )){
                Invoke-WebRequest -Uri  $uniqueControl.url -OutFile  $uniqueControl.file_name
            }
            . "./"+$uniqueControl.file_name
            $commandString = $uniqueControl.init_command + "-FailedControlsPath" + $SubscriptionId + ".json"
            function runCommand($command) {
                if ($command[0] -eq '"') { Invoke-Expression "& $command" }
                else { Invoke-Expression $command }
            }
            runCommand($commandString)
        }

    }
# }