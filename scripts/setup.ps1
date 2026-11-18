#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9-]+/[a-zA-Z0-9_.-]+$')]
    [string]$Repository,

    [switch]$Apply,
    [switch]$MarkAsTemplate,
    [switch]$EnableReleasePlease,
    [switch]$SkipRuleset
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$gh = (Get-Command gh -CommandType Application).Source

function Invoke-GitHub {
    param([string]$Method, [string]$Path, [hashtable]$Body)

    $arguments = @('api', '--hostname', 'github.com', '--method', $Method, $Path)
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 20 -Compress
        $response = $json | & $gh @arguments --input -
    } else {
        $response = & $gh @arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub rechazó $Method $Path. Revisá el error y volvé a ejecutar el setup."
    }
    if ($response) {
        ($response -join "`n") | ConvertFrom-Json -Depth 30
    }
}

$remote = git -C $PSScriptRoot remote get-url origin
if ($LASTEXITCODE -ne 0 -or $remote -notmatch '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)(?<repo>[\w.-]+/[\w.-]+?)(?:\.git)?/?$' -or
    $Matches.repo -ine $Repository) {
    throw "El origin de esta copia debe apuntar a github.com/$Repository."
}

$account = Invoke-GitHub GET user
$path = "repos/$Repository"
$repo = Invoke-GitHub GET $path
if ($repo.full_name -ine $Repository -or $repo.archived -or $repo.disabled -or -not $repo.permissions.admin) {
    throw "Confirmá el destino y el acceso de administración de @$($account.login). El repositorio debe estar activo."
}
if (-not $repo.default_branch) {
    throw 'El repositorio debe tener una rama predeterminada con los archivos del template.'
}
Write-Host "Cuenta: @$($account.login) | Destino: $($repo.full_name) | Visibilidad: $($repo.visibility) | Rama: $($repo.default_branch)"

$branch = [uri]::EscapeDataString($repo.default_branch)
$tree = Invoke-GitHub GET "${path}/contents/.github/workflows?ref=$branch"
foreach ($workflow in @('ci.yml', 'pr-title.yml', 'security.yml', 'release.yml')) {
    if ($workflow -cnotin @($tree.name)) {
        throw "Falta .github/workflows/$workflow en la rama predeterminada."
    }
}

$settings = @{
    has_issues = $true
    allow_squash_merge = $true
    allow_merge_commit = $false
    allow_rebase_merge = $false
    delete_branch_on_merge = $true
    squash_merge_commit_title = 'PR_TITLE'
    squash_merge_commit_message = 'PR_BODY'
}
if ($MarkAsTemplate) {
    $settings.is_template = $true
}
$changes = @{}
foreach ($key in $settings.Keys) {
    if ($repo.$key -cne $settings[$key]) {
        $changes[$key] = $settings[$key]
    }
}
if ($changes.ContainsKey('squash_merge_commit_message')) {
    $changes.squash_merge_commit_title = $settings.squash_merge_commit_title
}

$actions = Invoke-GitHub GET "$path/actions/permissions"
if (-not $actions.enabled) {
    throw 'GitHub Actions está desactivado para el repositorio.'
}

$ruleName = 'github-starter / default branch'
$checks = @('Repository checks', 'Conventional PR title', 'Secret scan', 'Dependency review')
$rulePayload = @{
    name = $ruleName
    target = 'branch'
    enforcement = 'active'
    bypass_actors = @()
    conditions = @{ ref_name = @{ include = @('~DEFAULT_BRANCH'); exclude = @() } }
    rules = @(
        @{ type = 'deletion' }
        @{ type = 'non_fast_forward' }
        @{ type = 'required_linear_history' }
        @{ type = 'pull_request'; parameters = @{
            required_approving_review_count = 0
            dismiss_stale_reviews_on_push = $false
            require_code_owner_review = $false
            require_last_push_approval = $false
            required_review_thread_resolution = $true
        } }
        @{ type = 'required_status_checks'; parameters = @{
            strict_required_status_checks_policy = $false
            required_status_checks = @($checks | ForEach-Object { @{ context = $_; integration_id = 15368 } })
        } }
    )
}
$createRuleset = $false
if ($SkipRuleset) {
    Write-Host 'Ruleset omitido para esta ejecución.'
} elseif ($repo.visibility -eq 'public') {
    $existing = @(Invoke-GitHub GET "$path/rulesets?includes_parents=false&per_page=100" |
        Where-Object name -CEQ $ruleName)
    if ($existing.Count -gt 1) {
        throw "Hay varios rulesets con el nombre '$ruleName'."
    }
    if ($existing.Count -eq 1) {
        $current = Invoke-GitHub GET "$path/rulesets/$($existing[0].id)"
        if ($current.target -ne 'branch' -or
            ($current.conditions.ref_name.include -join ',') -ne '~DEFAULT_BRANCH' -or
            $current.conditions.ref_name.exclude.Count -ne 0 -or
            $null -eq $current.PSObject.Properties['bypass_actors'] -or $current.bypass_actors.Count -ne 0) {
            throw "El ruleset '$ruleName' tiene otro alcance o excepciones. Revisalo antes de ejecutar el setup."
        }
        $expectedTypes = ($rulePayload.rules.type | Sort-Object) -join ','
        $actualTypes = ($current.rules.type | Sort-Object) -join ','
        if ($current.enforcement -ne 'active' -or $actualTypes -ne $expectedTypes) {
            throw "El ruleset '$ruleName' difiere de la configuración esperada."
        }
        foreach ($rule in $rulePayload.rules | Where-Object { $_.type -eq 'pull_request' -or $_.type -eq 'required_status_checks' }) {
            $actual = ($current.rules | Where-Object type -EQ $rule.type).parameters
            foreach ($key in $rule.parameters.Keys) {
                if ($key -eq 'required_status_checks') {
                    $actualChecks = ($actual.$key | ForEach-Object { "$($_.context):$($_.integration_id)" } | Sort-Object) -join ','
                    $expectedChecks = ($rule.parameters[$key] | ForEach-Object { "$($_.context):$($_.integration_id)" } | Sort-Object) -join ','
                    if ($actualChecks -cne $expectedChecks) {
                        throw "El ruleset '$ruleName' tiene otros checks obligatorios."
                    }
                } elseif ($actual.$key -cne $rule.parameters[$key]) {
                    throw "El ruleset '$ruleName' difiere en $key."
                }
            }
        }
        Write-Host "Ruleset verificado: $($current._links.html.href)"
    } else {
        $createRuleset = $true
    }
} else {
    Write-Host 'Se omite el ruleset. En GitHub Free está disponible para repositorios públicos.'
}

$enableActionsPullRequests = $false
if ($EnableReleasePlease) {
    $workflowPermissions = Invoke-GitHub GET "$path/actions/permissions/workflow"
    $enableActionsPullRequests = -not $workflowPermissions.can_approve_pull_request_reviews
}

if ($changes.Count) {
    Write-Host "Configuración a actualizar: $(($changes.Keys | Sort-Object) -join ', ')"
}
if ($createRuleset) {
    Write-Host "Ruleset a crear: $ruleName"
}
if ($enableActionsPullRequests) {
    Write-Host 'Se habilitará la opción de GitHub Actions para crear y aprobar PRs.'
}
if (-not $Apply) {
    Write-Host 'Vista previa. Ejecutá con -Apply para guardar los cambios.'
    return
}
if ($changes.Count) {
    $null = Invoke-GitHub PATCH $path $changes
}
if ($createRuleset) {
    $null = Invoke-GitHub POST "$path/rulesets" $rulePayload
}
if ($enableActionsPullRequests) {
    $null = Invoke-GitHub PUT "$path/actions/permissions/workflow" @{
        default_workflow_permissions = $workflowPermissions.default_workflow_permissions
        can_approve_pull_request_reviews = $true
    }
}
Write-Host 'Configuración aplicada.'
