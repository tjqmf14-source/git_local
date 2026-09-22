param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'src\GitLocal.Core.psm1'
$appPath = Join-Path $repoRoot 'src\GitLocal.App.ps1'

function Pass([string]$name) { Write-Host "[PASS] $name" -ForegroundColor Green }
function Fail([string]$name,[string]$message) { throw "[FAIL] $name :: $message" }
function Assert-True([bool]$condition,[string]$name) {
    if (-not $condition) { Fail $name '조건이 참이 아닙니다.' }
    Pass $name
}
function Assert-Equal($actual,$expected,[string]$name) {
    if ("$actual" -ne "$expected") { Fail $name "expected='$expected' actual='$actual'" }
    Pass $name
}
function Assert-Throws([scriptblock]$action,[string]$name) {
    $thrown = $false
    try { & $action } catch { $thrown = $true }
    if (-not $thrown) { Fail $name '예외가 발생해야 하지만 발생하지 않았습니다.' }
    Pass $name
}

$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($modulePath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host ("CORE PARSE ERROR line {0}: {1}" -f $_.Extent.StartLineNumber,$_.Message) } }
Assert-Equal $errors.Count 0 'Core PowerShell syntax'
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($appPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host ("UI PARSE ERROR line {0}: {1}" -f $_.Extent.StartLineNumber,$_.Message) } }
Assert-Equal $errors.Count 0 'UI PowerShell syntax'

Import-Module $modulePath -Force

$base = Join-Path ([System.IO.Path]::GetTempPath()) ('GitLocal-QA-' + [Guid]::NewGuid().ToString('N'))
$configRoot = Join-Path $base 'config'
$remote = Join-Path $base 'remote.git'
$seed = Join-Path $base 'seed'
$target = Join-Path $base 'work'
$verify = Join-Path $base 'verify'
$unicodeTarget = Join-Path $base '한글 경로\프로젝트'
New-Item -ItemType Directory -Path $base -Force | Out-Null

$oldConfigHome = $env:GITLOCAL_CONFIG_HOME
$oldAllowLocal = $env:GITLOCAL_ALLOW_LOCAL_REMOTE
$oldGitExe = $env:GITLOCAL_GIT_EXE
$env:GITLOCAL_CONFIG_HOME = $configRoot
$env:GITLOCAL_ALLOW_LOCAL_REMOTE = '1'

try {
    $git = Resolve-GitLocalGitExecutable
    Assert-True (Test-Path -LiteralPath $git -PathType Leaf) 'Git executable detected'

    Invoke-GitLocalGit -Arguments @('init','--bare',$remote) | Out-Null
    New-Item -ItemType Directory -Path $seed -Force | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('init','-b','main') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('config','user.name','GitLocal QA') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('config','user.email','qa@example.invalid') | Out-Null
    Set-Content -LiteralPath (Join-Path $seed 'README.txt') -Value 'seed' -Encoding UTF8
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('add','-A') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('commit','-m','seed') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('remote','add','origin',$remote) | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('push','-u','origin','main') | Out-Null
    Invoke-GitLocalGit -Arguments @("--git-dir=$remote",'symbolic-ref','HEAD','refs/heads/main') | Out-Null
    Pass 'Temporary remote repository prepared'

    $reg = Register-GitLocalProject -Name 'QA Project' -RepositoryUrl $remote -LocalPath $target
    Assert-Equal $reg.Mode 'cloned' 'GitHub-to-local clone path'
    Assert-True (Test-Path -LiteralPath (Join-Path $target 'README.txt') -PathType Leaf) 'Cloned content exists'

    $saved = @(Get-GitLocalProjects)
    Assert-Equal $saved.Count 1 'Project persistence count'
    Assert-Equal $saved[0].name 'QA Project' 'Project persistence data'

    $status = Get-GitLocalProjectStatus -Project $reg.Project
    Assert-Equal $status.Branch 'main' 'Current branch detection'
    Assert-Equal $status.State 'clean' 'Initial clean state'

    Invoke-GitLocalGit -WorkingDirectory $target -Arguments @('config','user.name','GitLocal QA') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $target -Arguments @('config','user.email','qa@example.invalid') | Out-Null
    Add-Content -LiteralPath (Join-Path $target 'README.txt') -Value 'local-change' -Encoding UTF8
    $pushResult = Publish-GitLocalProject -Project $reg.Project -CommitMessage 'qa: local push'
    Assert-Equal $pushResult.Result 'pushed' 'Local commit and push'

    $noChange = Publish-GitLocalProject -Project $reg.Project -CommitMessage 'qa: no changes'
    Assert-Equal $noChange.Result 'no-changes' 'No-change commit guard'

    Invoke-GitLocalGit -Arguments @('clone',$remote,$verify) | Out-Null
    $verifiedText = Get-Content -LiteralPath (Join-Path $verify 'README.txt') -Raw
    Assert-True ($verifiedText -match 'local-change') 'Remote received local push'

    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('pull','--rebase','origin','main') | Out-Null
    Add-Content -LiteralPath (Join-Path $seed 'README.txt') -Value 'remote-change' -Encoding UTF8
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('add','-A') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('commit','-m','qa: remote change') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('push','origin','main') | Out-Null
    $pullResult = Update-GitLocalProjectFromRemote -Project $reg.Project
    Assert-Equal $pullResult.Result 'pulled' 'Remote-to-local fast-forward pull'
    $pulledText = Get-Content -LiteralPath (Join-Path $target 'README.txt') -Raw
    Assert-True ($pulledText -match 'remote-change') 'Remote change visible locally'

    Add-Content -LiteralPath (Join-Path $target 'README.txt') -Value 'dirty' -Encoding UTF8
    Assert-Throws { Update-GitLocalProjectFromRemote -Project $reg.Project | Out-Null } 'Dirty working tree pull protection'
    Invoke-GitLocalGit -WorkingDirectory $target -Arguments @('checkout','--','README.txt') | Out-Null

    $unicode = Register-GitLocalProject -Name '한글 프로젝트' -RepositoryUrl $remote -LocalPath $unicodeTarget
    Assert-Equal $unicode.Mode 'cloned' 'Unicode path clone'
    Assert-True (Test-Path -LiteralPath (Join-Path $unicodeTarget 'README.txt')) 'Unicode path content'
    Remove-GitLocalProject -Id $unicode.Project.id | Out-Null
    Assert-Equal @(Get-GitLocalProjects).Count 1 'Project removal persistence'

    Assert-Equal (Resolve-GitLocalRepositoryUrl 'https://github.com/openai/openai-python') 'https://github.com/openai/openai-python.git' 'GitHub URL normalization'
    Assert-Throws { Resolve-GitLocalRepositoryUrl 'https://example.com/owner/repo' | Out-Null } 'Reject non-GitHub URL'
    Assert-Throws { Resolve-GitLocalRepositoryUrl 'https://token@github.com/owner/repo' | Out-Null } 'Reject credentials in URL'
    Assert-Throws { Register-GitLocalProject -Name 'dup' -RepositoryUrl $remote -LocalPath $target -SkipRemoteValidation | Out-Null } 'Reject duplicate local path'

    $filePath = Join-Path $base 'not-a-folder.txt'
    Set-Content -LiteralPath $filePath -Value 'x'
    Assert-Throws { Register-GitLocalProject -Name 'bad' -RepositoryUrl $remote -LocalPath $filePath -SkipRemoteValidation | Out-Null } 'Reject file as local path'

    $env:GITLOCAL_GIT_EXE = Join-Path $base 'missing-git.exe'
    Assert-Throws { Resolve-GitLocalGitExecutable | Out-Null } 'Git missing error handling'
    $env:GITLOCAL_GIT_EXE = $git

    $broken = Join-Path $base 'broken'
    New-Item -ItemType Directory -Path $broken -Force | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $broken -Arguments @('init','-b','main') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $broken -Arguments @('remote','add','origin',(Join-Path $base 'does-not-exist.git')) | Out-Null
    $brokenProject = [pscustomobject]@{ id='broken'; name='broken'; localPath=$broken; repositoryUrl='broken'; branch='main' }
    Assert-Throws { Update-GitLocalProjectFromRemote -Project $brokenProject | Out-Null } 'Unreachable remote error handling'

    Write-Host ''
    Write-Host 'ALL CORE QA TESTS PASSED' -ForegroundColor Green
}
finally {
    $env:GITLOCAL_CONFIG_HOME = $oldConfigHome
    $env:GITLOCAL_ALLOW_LOCAL_REMOTE = $oldAllowLocal
    $env:GITLOCAL_GIT_EXE = $oldGitExe
    if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}
