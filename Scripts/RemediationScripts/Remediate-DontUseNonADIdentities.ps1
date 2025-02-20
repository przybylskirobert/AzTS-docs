<##########################################

# Overivew:
    This script is used to remove external (guest) AD identities access on subscriptions.

ControlId: 
    Azure_Subscription_AuthZ_Dont_Use_NonAD_Identities

# Pre-requesites:
    You will need owner or User Access Administrator role at subscription level.

# Steps performed by the script
    1. Install and validate pre-requesites to run the script for subscription.

    2. Get role assignments for the subscription and filter external/Non-Ad identities.

    3. Taking backup of external/Non-Ad identities that are going to be removed using remediation script.

    4. Clean up external/Non-Ad object identities role assignments from subscription.

# Step to execute script:
    Download and load remediation script in PowerShell session and execute below command.
    To know how to load script in PowerShell session refer link: https://aka.ms/AzTS-docs/RemediationscriptExcSteps.

# Command to execute:
    Examples:
        1. Run below command to remove all external/Non-Ad identities role assignments from subscription

         Remove-AzTSNonADIdentities -SubscriptionId '<Sub_Id>' -PerformPreReqCheck: $true

        2. Run below command, if you have external/Non-Ad identities list with you. You will get external/Non-Ad account list from AzTS UI status reason section.

         Remove-AzTSNonADIdentities -SubscriptionId '<Sub_Id>' -ObjectIds @('<Object_Id_1>', '<Object_Id_2>') -PerformPreReqCheck: $true

    Note: 
        To rollback changes made by remediation script, execute below command
        Restore-AzTSNonADIdentities -SubscriptionId '<Sub_Id>' -RollbackFilePath "<user Documents>\AzTS\Remediation\Subscriptions\<subscriptionId>\<JobDate>\NonAADAccounts\NonAADAccountsRoleAssignments.json" -PerformPreReqCheck: $true   

To know more about parameter execute below command:
    a. Get-Help Remove-AzTSNonADIdentities -Detailed
    b. Get-Help Restore-AzTSNonADIdentities -Detailed

########################################
#>

function Pre_requisites
{
    <#
    .SYNOPSIS
    This command would check pre requisities modules.
    .DESCRIPTION
    This command would check pre requisities modules to perform remediation.
	#>

    Write-Host "Required modules are: Az.Resources, Az.Account, AzureAD" -ForegroundColor Cyan
    Write-Host "Checking for required modules..."
    $availableModules = $(Get-Module -ListAvailable Az.Resources, AzureAD, Az.Accounts)
    
    # Checking if 'Az.Accounts' module is available or not.
    if($availableModules.Name -notcontains 'Az.Accounts')
    {
        Write-Host "Installing module Az.Accounts..." -ForegroundColor Yellow
        Install-Module -Name Az.Accounts -Scope CurrentUser -Repository 'PSGallery'
    }
    else
    {
        Write-Host "Az.Accounts module is available." -ForegroundColor Green
    }

    # Checking if 'Az.Resources' module is available or not.
    if($availableModules.Name -notcontains 'Az.Resources')
    {
        Write-Host "Installing module Az.Resources..." -ForegroundColor Yellow
        Install-Module -Name Az.Resources -Scope CurrentUser -Repository 'PSGallery'
    }
    else
    {
        Write-Host "Az.Resources module is available." -ForegroundColor Green
    }
    
    # Checking if 'AzureAD' module is available or not.
    if($availableModules.Name -notcontains 'AzureAD')
    {
        Write-Host "Installing module AzureAD..." -ForegroundColor Yellow
        Install-Module -Name AzureAD -Scope CurrentUser -Repository 'PSGallery'
    }
    else
    {
        Write-Host "AzureAD module is available." -ForegroundColor Green
    }
}

function Remove-AzTSNonADIdentities
{
    <#
    .SYNOPSIS
    This command would help in remediating 'Azure_Subscription_AuthZ_Dont_Use_NonAD_Identities' control.
    .DESCRIPTION
    This command would help in remediating 'Azure_Subscription_AuthZ_Dont_Use_NonAD_Identities' control.
    .PARAMETER SubscriptionId
        Enter subscription id on which remediation need to perform.
    .PARAMETER ObjectIds
        Enter objectIds of non-ad identities.
    .Parameter Force
        Enter force parameter value to remove non-ad identities
    .PARAMETER PerformPreReqCheck
        Perform pre requisities check to ensure all required module to perform rollback operation is available.
    #>

    param (
        [string]
        $SubscriptionId,

        [string[]]
        $ObjectIds,

        [switch]
        $Force,

        [switch]
        $PerformPreReqCheck
    )

    Write-Host "======================================================"
    Write-Host "Starting with removal of Non-AD Identities from subscriptions..."
    Write-Host "------------------------------------------------------"

    if($PerformPreReqCheck)
    {
        try 
        {
            Write-Host "Checking for pre-requisites..."
            Pre_requisites
            Write-Host "------------------------------------------------------"  
        }
        catch 
        {
            Write-Host "Error occured while checking pre-requisites. ErrorMessage [$($_)]" -ForegroundColor $([Constants]::MessageType.Error)    
            break
        }
    }

    # Connect to AzAccount
    $isContextSet = Get-AzContext
    if ([string]::IsNullOrEmpty($isContextSet))
    {       
        Write-Host "Connecting to AzAccount..."
        Connect-AzAccount -ErrorAction Stop
        Write-Host "Connected to AzAccount" -ForegroundColor Green
    }

    # Setting context for current subscription.
    $currentSub = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop

    Write-Host "Note: `n 1. Exclude checking PIM assignment for external identities due to insufficient privilege. `n 2. Exclude checking external identities at MG scope. `n 3. Checking only for user type assignments." -ForegroundColor Yellow
    Write-Host "------------------------------------------------------"

    Write-Host "Metadata Details: `n SubscriptionId: $($SubscriptionId) `n AccountName: $($currentSub.Account.Id) `n AccountType: $($currentSub.Account.Type)"
    Write-Host "------------------------------------------------------"
    Write-Host "Starting with Subscription [$($SubscriptionId)]..."


    Write-Host "Step 1 of 3: Validating whether the current user [$($currentSub.Account.Id)] has the required permissions to run the script for subscription [$($SubscriptionId)]..."

    # Safe Check: Checking whether the current account is of type User and also grant the current user as UAA for the sub to support fallback
    if($currentSub.Account.Type -ne "User")
    {
        Write-Host "Warning: This script can only be run by user account type." -ForegroundColor Yellow
        return;
    }

    # Safe Check: Current user need to be either UAA or Owner for the subscription
    $currentLoginRoleAssignments = Get-AzRoleAssignment -SignInName $currentSub.Account.Id -Scope "/subscriptions/$($SubscriptionId)";

    if(($currentLoginRoleAssignments | Where { $_.RoleDefinitionName -eq "Owner" -or $_.RoleDefinitionName -eq "User Access Administrator" } | Measure-Object).Count -le 0)
    {
        Write-Host "Warning: This script can only be run by an Owner or User Access Administrator" -ForegroundColor Yellow
        return;
    }
    
    Write-Host "Step 2 of 3: Fetching all the role assignments for Subscription [$($SubscriptionId)]..."

    $distinctRoleAssignmentList = @();

    # Getting role assignment
    if(($ObjectIds | Measure-Object).Count -eq 0)
    {
        #  Getting all role assignments from ARM source.
        $currentRoleAssignmentList = Get-AzRoleAssignment 

        # Excluding MG scoped role assignment
        $currentRoleAssignmentList = $currentRoleAssignmentList | Where-Object { !$_.Scope.Contains("/providers/Microsoft.Management/managementGroups/") }
        
        # API call to get classic role assignment
        $classicAssignments = $null
        $armUri = "https://management.azure.com/subscriptions/$($subscriptionId)/providers/Microsoft.Authorization/classicadministrators?api-version=2015-06-01"
        $method = "Get"
        $classicAssignments = [ClassicRoleAssignments]::new()
        $headers = $classicAssignments.GetAuthHeader()
        $res = $classicAssignments.GetClassicRoleAssignmnets([string] $armUri, [string] $method, [psobject] $headers)
        if($null -ne $res)
        {
            $classicDistinctRoleAssignmentList = $res.value | Where-Object { ![string]::IsNullOrWhiteSpace($_.properties.emailAddress) }
            # Renaming property name
            $currentRoleAssignmentList += $classicDistinctRoleAssignmentList | select @{N='SignInName'; E={$_.properties.emailAddress}},  @{N='RoleDefinitionName'; E={$_.properties.role}}, @{N='RoleId'; E={$_.name}}, @{N='Type'; E={$_.type }}, @{N='RoleAssignmentId'; E={$_.id }}, ObjectId
        }
        
        # Get object id of classic role assignment
        $getObjectsByUserPrincipalNameAPIString = "https://graph.windows.net/myorganization/users?api-version=1.6&`$filter=(userPrincipalName+eq+'{0}')+or+(mail+eq+'{1}')&`$select=objectType,objectId,displayName,userPrincipalName"
        
        if(($currentRoleAssignmentList | Measure-Object).Count -gt 0)
        {
            $currentRoleAssignmentList | Where-Object { [string]::IsNullOrWhiteSpace($_.ObjectId) } | ForEach-Object { 
            $classicRoleAssignment = $_
            $signInName = $classicRoleAssignment.SignInName.Replace("#","%23")
            $url = [string]::Format($getObjectsByUserPrincipalNameAPIString, $signInName, $signInName)
            $header = [AzureADGraph]::new().GetAuthHeader()
            $adGraphResponse = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $header -Method Get

            if($adGraphResponse -ne $null)
            {
                    $adGraphResponse = $adGraphResponse.Content | ConvertFrom-Json
                    $classicRoleAssignment.ObjectId = $adGraphResponse.value.objectId
            }
            }
        }

        # Filtering service principal object type
        $distinctRoleAssignmentList += $currentRoleAssignmentList | Where-Object { ![string]::IsNullOrWhiteSpace($_.SignInName) }
    }
    else
    {
        $ObjectIds | Foreach-Object {
          $objectId = $_;
           if(![string]::IsNullOrWhiteSpace($objectId))
            {
                # Filtering service principal object type
                $distinctRoleAssignmentList += Get-AzRoleAssignment -ObjectId $objectId | Where-Object { ![string]::IsNullOrWhiteSpace($_.SignInName) -and !$_.Scope.Contains("/providers/Microsoft.Management/managementGroups/")}
            }
            else
            {
                Write-Host "Warning: Dont pass empty string array in the ObjectIds param. If you dont want to use the param, just remove while executing the command" -ForegroundColor Yellow
                break;
            }  
        }
    }

    # Adding ARM API call to fetch eligible role assignment [Commenting this part because used ARM API is currently in preview state, we can officially start supporting once it is publicly available]
    <#
    try
    {
        # PIM api
        $resourceAppIdUri = "https://management.core.windows.net/"
        $rmContext = Get-AzContext
        [Microsoft.Azure.Commands.Common.Authentication.AzureSession]
        $authResult = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
        $rmContext.Account,
        $rmContext.Environment,
        $rmContext.Tenant,
        [System.Security.SecureString] $null,
        "Never",
        $null,
        $resourceAppIdUri); 

        $header = "Bearer " + $authResult.AccessToken
        $headers = @{"Authorization"=$header;"Content-Type"="application/json";}
        $method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Get

        # API to get eligible PIM assignment
        $armUri = "https://management.azure.com/subscriptions/$($SubscriptionId)/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01-preview"
        $eligiblePIMRoleAssignments = Invoke-WebRequest -Method $method -Uri $armUri -Headers $headers -UseBasicParsing
        $res = ConvertFrom-Json $eligiblePIMRoleAssignments.Content

        # Exclude MG scope assignment
        $excludedMGScopeAssignment =  $res.value.properties | where-object { !$_.scope.contains("/providers/Microsoft.Management/managementGroups/") }
        $pimDistinctRoleAssignmentList += $excludedMGScopeAssignment.expandedProperties.principal | Where-Object { ![string]::IsNullOrWhiteSpace($_.email) }
        
        # Renaming property name
        $distinctRoleAssignmentList += $pimDistinctRoleAssignmentList | select @{N='SignInName'; E={$_.email}}, @{N='ObjectId'; E={$_.id}}, @{N='DisplayName'; E={$_.displayName}}, @{N='ObjectType'; E={$_.type }}
    }
    catch
    {
        Write-Host "Error occured while fetching eligible PIM role assignment. ErrorMessage [$($_)]" -ForegroundColor Red
    }
    #>
    
    # Find guest accounts from role assignments list
    $GuestAccountsObjectId = @()
    $getObjectsByObjectIdsBetaAPIUrl = "https://graph.microsoft.com/beta/directoryObjects/getByIds?$select=id,userPrincipalName,onPremisesExtensionAttributes,userType,creationType,externalUserState"
    if( ($distinctRoleAssignmentList | Measure-Object).Count -gt 0)
    {
        # Adding batch of 900
        for( $i = 0; $i -lt $distinctRoleAssignmentList.Length; $i = $i + 900)
        {
            if($i + 900 -lt $distinctRoleAssignmentList.Length)
            {
                $endRange = $i + 900
            }
            else
            {
                $endRange = $distinctRoleAssignmentList.Length - 1;
            }

            $subRange = $distinctRoleAssignmentList[$i..$endRange]

            $ObjectIds = @($subRange.ObjectId | Select -Unique)
            $header = [MicrosoftGraph]::new().GetAuthHeader()
            $body = @{
                        "ids"= @($ObjectIds);
                        "types"=@("user");
                    } | ConvertTo-Json
            $adGraphJsonResponse = Invoke-WebRequest -UseBasicParsing -Uri $getObjectsByObjectIdsBetaAPIUrl -Headers $header -Method Post -Body $body
            if( $null -ne $adGraphJsonResponse)
            {
                $adGraphResponse = $adGraphJsonResponse.Content | ConvertFrom-Json
                $GuestAccountsObjectId += $adGraphResponse.value | Where-Object { $_.userType -eq "Guest" } | Select -ExpandProperty Id
            }
        } 
    }

    $externalAccountsRoleAssignments = @($distinctRoleAssignmentList | Where-Object { $GuestAccountsObjectId -contains $_.ObjectId })

    # Safe Check: Check whether the current user accountId is part of Invalid AAD Object guids List 
    if(($externalAccountsRoleAssignments | where { $currentLoginRoleAssignments.ObjectId -contains $_.ObjectId } | Measure-Object).Count -gt 0)
    {
        Write-Host "Warning: Current User account is found as part of the Non-AD Account. This is not expected behaviour. This can happen typically during Graph API failures. Aborting the operation. Reach out to aztssup@microsoft.com" -ForegroundColor Yellow
        return;
    }

    if(($externalAccountsRoleAssignments | Measure-Object).Count -le 0)
    {
        Write-Host "No Non-AD identities found for the subscription [$($SubscriptionId)]. Exiting the process." -ForegroundColor Cyan
        return;
    }
    else
    {
        Write-Host "Found [$(($externalAccountsRoleAssignments | Measure-Object).Count)] Non-AD role assignments for the subscription [$($SubscriptionId)]" -ForegroundColor Cyan
    }

    $folderPath = [Environment]::GetFolderPath("MyDocuments") 
    if (Test-Path -Path $folderPath)
    {
        $folderPath += "\AzTS\Remediation\Subscriptions\$($subscriptionid.replace("-","_"))\$((Get-Date).ToString('yyyyMMdd_hhmm'))\NonADIdentities\"
        New-Item -ItemType Directory -Path $folderPath | Out-Null
    }

    # Safe Check: Taking backup of Non-AD identities    
    if ($externalAccountsRoleAssignments.length -gt 0)
    {
        Write-Host "Taking backup of role assignments for Non-AD identities that needs to be removed. Please do not delete this file. Without this file you wont be able to rollback any changes done through remediation script." -ForegroundColor Cyan
        $externalAccountsRoleAssignments | ConvertTo-json -Depth 10 | out-file "$($folderpath)NonADAccountsRoleAssignments.json"       
        Write-Host "Path: $($folderpath)NonADAccountsRoleAssignments.json"
    }

    if(-not $Force)
    {
        Write-Host "Do you want to delete the above listed role assignment? " -ForegroundColor Yellow -NoNewline
        $UserInput = Read-Host -Prompt "(Y|N)"

        if($UserInput -ne "Y")
        {
            return;
        }
    }
   

    Write-Host "Step 3 of 3: Clean up Non-AD identities for Subscription [$($SubscriptionId)]..."
    
    # Start deletion of all Non-AD identities.
    Write-Host "Starting to delete role assignments for Non-AD identities..." -ForegroundColor Cyan
    
    $isRemoved = $true
    $externalAccountsRoleAssignments | ForEach-Object {
        try
        {
            if($_.RoleDefinitionName -eq "CoAdministrator" -and $_.RoleAssignmentId.contains("/providers/Microsoft.Authorization/classicAdministrators/"))
            {
                $armUri = "https://management.azure.com" + $_.RoleAssignmentId + "?api-version=2015-06-01"
                $method = "Delete"
                $classicAssignments = $null
                $classicAssignments = [ClassicRoleAssignments]::new()
                $headers = $classicAssignments.GetAuthHeader()
                $res = $classicAssignments.DeleteClassicRoleAssignmnets([string] $armUri, [string] $method,[psobject] $headers)

                if(($null -ne $res) -and ($res.StatusCode -eq 202 -or $res.StatusCode -eq 200))
                {
                    $_ | Select-Object -Property "SignInName", "RoleAssignmentId", "RoleDefinitionName"
                }
            }
            else 
            {
                Remove-AzRoleAssignment $_ -ErrorAction SilentlyContinue
                $_ | Select-Object -Property "DisplayName", "SignInName", "Scope"
            }
        }
        catch
        {
            $isRemoved = $false
            Write-Host "Error occurred while removing role assignments for Non-AD identities. ErrorMessage [$($_)]" -ForegroundColor Red
        }
    }

    if($isRemoved)
    {
        Write-Host "Completed deleting role assignments for Non-AD identities." -ForegroundColor Green
    }
    else 
    {
        Write-Host "`n"
        Write-Host "Not able to successfully delete role assignments for Non-AD identities." -ForegroundColor Red
    }    
}


function Restore-AzTSNonADIdentities
{
    <#
    .SYNOPSIS
    This command would help in performing rollback operation for 'Azure_Subscription_AuthZ_Dont_Use_NonAD_Identities' control.
    .DESCRIPTION
    This command would help in performing rollback operation for 'Azure_Subscription_AuthZ_Dont_Use_NonAD_Identities' control.
    .PARAMETER SubscriptionId
        Enter subscription id on which rollback operation need to perform.
    .PARAMETER RollbackFilePath
        Json file path which containing remediation log to perform rollback operation.
    .PARAMETER PerformPreReqCheck
        Perform pre requisities check to ensure all required module to perform rollback operation is available.
	#>

    param (
        [string]
        $SubscriptionId,       

        [string]
        $RollbackFilePath,
        
        [switch]
        $PerformPreReqCheck
    )

    Write-Host "======================================================"
    Write-Host "Starting with restore role assignments for Non-AD identities from subscriptions..."
    Write-Host "------------------------------------------------------"
    
    if($PerformPreReqCheck)
    {
        try 
        {
            Write-Host "Checking for pre-requisites..."
            Pre_requisites
            Write-Host $([Constants]::SingleDashLine)    
        }
        catch 
        {
            Write-Host "Error occured while checking pre-requisites. ErrorMessage [$($_)]" -ForegroundColor $([Constants]::MessageType.Error)    
            break
        }    
    }

    $isContextSet = Get-AzContext
    if ([string]::IsNullOrEmpty($isContextSet))
    {       
        Write-Host "Connecting to AzAccount..."
        Connect-AzAccount -ErrorAction Stop
        Write-Host "Connected to AzAccount" -ForegroundColor Green
    }

    # Setting context for current subscription.
    $currentSub = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop

    Write-Host "------------------------------------------------------"
    Write-Host "Metadata Details: `n SubscriptionId: $($SubscriptionId) `n AccountName: $($currentSub.Account.Id) `n AccountType: $($currentSub.Account.Type)"
    Write-Host "------------------------------------------------------"
    Write-Host "Starting with Subscription [$($SubscriptionId)]..."


    Write-Host "Step 1 of 3: Validating whether the current user [$($currentSub.Account.Id)] has the required permissions to run the script for subscription [$($SubscriptionId)]..."

    # Safe Check: Checking whether the current account is of type User and also grant the current user as UAA for the sub to support fallback
    if($currentSub.Account.Type -ne "User")
    {
        Write-Host "Warning: This script can only be run by user account type." -ForegroundColor Yellow
        break;
    }

    # Safe Check: Current user need to be either UAA or Owner for the subscription
    $currentLoginRoleAssignments = Get-AzRoleAssignment -SignInName $currentSub.Account.Id -Scope "/subscriptions/$($SubscriptionId)";

    if(($currentLoginRoleAssignments | Where { $_.RoleDefinitionName -eq "Owner" -or $_.RoleDefinitionName -eq "User Access Administrator" } | Measure-Object).Count -le 0)
    {
        Write-Host "Warning: This script can only be run by an Owner or User Access Administrator." -ForegroundColor Yellow
        break;
    }

    Write-Host "Step 2 of 3: Check for presence of rollback file for Subscription: [$($SubscriptionId)]..."

    if (-not (Test-Path -Path $RollbackFilePath))
    {
        Write-Host "Warning: Rollback file is not found. Please check if the initial Remediation script has been run from the same machine. Exiting the process" -ForegroundColor Yellow
        break;        
    }
    $backedUpRoleAssingments = Get-Content -Raw -Path $RollbackFilePath | ConvertFrom-Json     

    # Checking if no assignments found in given json file
    if(($backedUpRoleAssingments | Measure-Object).count -eq 0)
    {
        Write-Host "No assignment found to perform rollback operation. Please check if the initial Remediation script has been run from the same machine. Exiting the process" -ForegroundColor Yellow
        break;
    }

    Write-Host "Step 3 of 3: Restore role assignments [$($SubscriptionId)]..."
    
    $isRestored = $true

    $backedUpRoleAssingments | ForEach-Object {
        try
        {
            if($_.RoleDefinitionName -eq "CoAdministrator" -and $_.RoleAssignmentId.contains("/providers/Microsoft.Authorization/classicAdministrators/"))
            {
                $armUri = "https://management.azure.com" + $_.RoleAssignmentId + "?api-version=2015-06-01"
                $method = "PUT"

                # Create body for making PUT request
                $body = ([PSCustomObject]@{
                    properties = @{
                      "emailAddress"= $_.SignInName;
                       "role"=$_.RoleDefinitionName;
                    }
                  } | ConvertTo-Json)

                $classicAssignments = $null
                $classicAssignments = [ClassicRoleAssignments]::new()
                $headers = $classicAssignments.GetAuthHeader()
                $res = $classicAssignments.PutClassicRoleAssignmnets([string] $armUri, [string] $method, [psobject] $headers,[System.Object] $body)
                if(($null -ne $res) -and ($res.StatusCode -eq 202 -or $res.StatusCode -eq 200))
                {
                    $_ | Select-Object -Property "SignInName", "RoleAssignmentId", "RoleDefinitionName"
                }
            }
            else 
            {
                $roleAssignment = $_;
                New-AzRoleAssignment -ObjectId $roleAssignment.ObjectId -Scope $roleAssignment.Scope -RoleDefinitionName $roleAssignment.RoleDefinitionName -ErrorAction SilentlyContinue | Out-Null;    
                $roleAssignment | Select-Object -Property "DisplayName", "SignInName", "Scope"
            }
        }
        catch
        {
            $isRestored = $false
            Write-Host "Error occurred while adding role assignments for Non-AD identities. ErrorMessage [$($_)]" -ForegroundColor Red
        }
    }
    
    if($isRestored)
    {
        Write-Host "Completed restoring role assignments for Non-AD identities." -ForegroundColor Green
    }
    else 
    {
        Write-Host "`n"
        Write-Host "Not able to successfully restore role assignments for Non-AD identities." -ForegroundColor Red   
    }
}

class AzureADGraph
{
    [PSObject] GetAuthHeader()
    {
        [psobject] $headers = $null
        try 
        {
            $resourceAppIdUri = "https://graph.windows.net"
            $rmContext = Get-AzContext
            $authResult = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
            $rmContext.Account,
            $rmContext.Environment,
            $rmContext.Tenant,
            [System.Security.SecureString] $null,
            "Never",
            $null,
            $resourceAppIdUri); 

            $header = "Bearer " + $authResult.AccessToken
            $headers = @{"Authorization"=$header;"Content-Type"="application/json";}
        }
        catch 
        {
            Write-Host "Error occured while fetching auth header. ErrorMessage [$($_)]" -ForegroundColor Red   
        }
        return($headers)
    }
}


class MicrosoftGraph
{
    [PSObject] GetAuthHeader()
    {
        [psobject] $headers = $null
        try 
        {
            $resourceAppIdUri = "https://graph.microsoft.com"
            $rmContext = Get-AzContext
            $authResult = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
            $rmContext.Account,
            $rmContext.Environment,
            $rmContext.Tenant,
            [System.Security.SecureString] $null,
            "Never",
            $null,
            $resourceAppIdUri); 

            $header = "Bearer " + $authResult.AccessToken
            $headers = @{"Authorization"=$header;"Content-Type"="application/json";}
        }
        catch 
        {
            Write-Host "Error occured while fetching auth header. ErrorMessage [$($_)]" -ForegroundColor Red   
        }
        return($headers)
    }
}


class ClassicRoleAssignments
{
    [PSObject] GetAuthHeader()
    {
        [psobject] $headers = $null
        try 
        {
            $resourceAppIdUri = "https://management.core.windows.net/"
            $rmContext = Get-AzContext
            $authResult = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
            $rmContext.Account,
            $rmContext.Environment,
            $rmContext.Tenant,
            [System.Security.SecureString] $null,
            "Never",
            $null,
            $resourceAppIdUri); 

            $header = "Bearer " + $authResult.AccessToken
            $headers = @{"Authorization"=$header;"Content-Type"="application/json";}
        }
        catch 
        {
            Write-Host "Error occured while fetching auth header. ErrorMessage [$($_)]" -ForegroundColor Red   
        }
        return($headers)
    }

    [PSObject] GetClassicRoleAssignmnets([string] $armUri, [string] $method, [psobject] $headers)
    {
        $content = $null
        try
        {
            $method = [Microsoft.PowerShell.Commands.WebRequestMethod]::$method
            
            # API to get classic role assignments
            $response = Invoke-WebRequest -Method $method -Uri $armUri -Headers $headers -UseBasicParsing
            $content = ConvertFrom-Json $response.Content
        }
        catch
        {
            Write-Host "Error occured while fetching classic role assignment. ErrorMessage [$($_)]" -ForegroundColor Red
        }
        
        return($content)
    }

    [PSObject] DeleteClassicRoleAssignmnets([string] $armUri, [string] $method, [psobject] $headers)
    {
        $content = $null
        try
        {
            $method = [Microsoft.PowerShell.Commands.WebRequestMethod]::$method
            
            # API to get classic role assignments
            $response = Invoke-WebRequest -Method $method -Uri $armUri -Headers $headers -UseBasicParsing
            $content = $response
        }
        catch
        {
            Write-Host "Error occured while deleting classic role assignment. ErrorMessage [$($_)]" -ForegroundColor Red
        }
        
        return($content)
    }

    [PSObject] PutClassicRoleAssignmnets([string] $armUri, [string] $method, [psobject] $headers, [System.Object] $body)
    {
        $content = $null
        try
        {
            $method = [Microsoft.PowerShell.Commands.WebRequestMethod]::$method
            
            # API to get classic role assignments
            $response = Invoke-WebRequest -Method $method -Uri $armUri -Headers $headers -Body $body -UseBasicParsing
            $content = $response
        }
        catch
        {
            Write-Host "Error occured while adding classic role assignment. ErrorMessage [$($_)]" -ForegroundColor Red
        }
        
        return($content)
    }
}

# ***************************************************** #
<#
Function calling with parameters.
Remove-AzTSNonADIdentities -SubscriptionId '<Sub_Id>' -ObjectIds @('<Object_Ids>')  -Force:$false -PerformPreReqCheck: $true

Function to rollback role assignments as per input remediated log
Restore-AzTSNonADIdentities -SubscriptionId '<Sub_Id>' -RollbackFilePath "<user Documents>\AzTS\Remediation\Subscriptions\<subscriptionId>\<JobDate>\NonAADAccounts\NonAADAccountsRoleAssignments.json"
Note: You can only rollback valid role assignments.
#>