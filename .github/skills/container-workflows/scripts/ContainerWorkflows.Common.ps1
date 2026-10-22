#Requires -Version 7.4
<#
.SYNOPSIS
    Functions shared by the container build and deploy scripts. Dot-source this file.
#>

function Get-GitHubOwner {
    <#
    .SYNOPSIS
        Returns the lower-case GitHub owner of a repository's origin remote, used as the GHCR namespace.
    .PARAMETER RepositoryRoot
        Root directory of the Git repository.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $url = "$(git -C $RepositoryRoot remote get-url origin 2>$null)".Trim()
    if ($LASTEXITCODE -eq 0 -and $url -match 'github\.com[:/](?<owner>[^/]+)/') {
        return $Matches.owner.ToLowerInvariant()
    }
    throw "Could not derive a GitHub owner from the 'origin' remote of '$RepositoryRoot'."
}
