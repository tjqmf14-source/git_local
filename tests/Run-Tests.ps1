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
function Assert-ThrowsMatch([scriptblock]$action,[string]$pattern,[string]$name) {
    $message = $null
    try { & $action } catch { $message = $_.Exception.Message }
    if ($null -eq $message) { Fail $name '예외가 발생해야 하지만 발생하지 않았습니다.' }
    if ($message -notmatch $pattern) { Fail $name ("예상 오류 패턴='{0}' actual='{1}'" -f $pattern,$message) }
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

$workflowPath = Join-Path $repoRoot '.github\workflows\windows-qa.yml'
$selfLines = @(Get-Content -LiteralPath $PSCommandPath)
$forcedExitLines = @($selfLines | Where-Object { $_.Trim() -eq 'exit 0' })
Assert-Equal $forcedExitLines.Count 0 'QA script does not force exit zero'
$lastExitOverwriteLines = @($selfLines | Where-Object { $_.Trim() -eq '$global:LASTEXITCODE = 0' })
Assert-Equal $lastExitOverwriteLines.Count 0 'QA script does not overwrite global LASTEXITCODE'
$workflowLines = @(Get-Content -LiteralPath $workflowPath)
$hiddenFailureLines = @($workflowLines | Where-Object {
    $line = $_.Trim()
    ($line -eq 'continue-on-error: true') -or $line.Contains('|| true')
})
Assert-Equal $hiddenFailureLines.Count 0 'QA workflow does not hide failures'

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
    $multiProjects = @(Get-GitLocalProjects)
    Assert-Equal $multiProjects.Count 2 'Multiple project persistence count'
    $mainProject = Get-GitLocalProject -Id $reg.Project.id
    $unicodeProject = Get-GitLocalProject -Id $unicode.Project.id
    Assert-True (-not [string]::Equals([string]$mainProject.localPath,[string]$unicodeProject.localPath,[StringComparison]::OrdinalIgnoreCase)) 'Multiple project isolation'
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

    Remove-GitLocalProject -Id $reg.Project.id | Out-Null
    Assert-Equal @(Get-GitLocalProjects).Count 0 'Remove final project persistence'

    Assert-Throws { Resolve-GitLocalRepositoryUrl 'https://github.com/owner' | Out-Null } 'Reject incomplete GitHub URL'

    $missingProject = [pscustomobject]@{ id='missing'; name='missing'; localPath=(Join-Path $base 'missing-local'); repositoryUrl=$remote; branch='main' }
    $missingStatus = Get-GitLocalProjectStatus -Project $missingProject
    Assert-Equal $missingStatus.State 'missing' 'Missing local path status'

    $noRemote = Join-Path $base 'no-remote'
    Invoke-GitLocalGit -Arguments @('clone',$remote,$noRemote) | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $noRemote -Arguments @('remote','remove','origin') | Out-Null
    $noRemoteProject = [pscustomobject]@{ id='no-remote'; name='no-remote'; localPath=$noRemote; repositoryUrl=$remote; branch='main' }
    $noRemoteStatus = Get-GitLocalProjectStatus -Project $noRemoteProject
    Assert-Equal $noRemoteStatus.State 'no-remote' 'Missing origin status'
    Assert-ThrowsMatch { Update-GitLocalProjectFromRemote -Project $noRemoteProject | Out-Null } 'origin 원격 저장소' 'Missing origin pull protection'

    $detached = Join-Path $base 'detached'
    Invoke-GitLocalGit -Arguments @('clone',$remote,$detached) | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $detached -Arguments @('config','user.name','GitLocal QA') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $detached -Arguments @('config','user.email','qa@example.invalid') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $detached -Arguments @('checkout','--detach','HEAD') | Out-Null
    $detachedProject = [pscustomobject]@{ id='detached'; name='detached'; localPath=$detached; repositoryUrl=$remote; branch='main' }
    $detachedStatus = Get-GitLocalProjectStatus -Project $detachedProject
    Assert-Equal $detachedStatus.State 'detached' 'Detached HEAD status'
    Assert-ThrowsMatch { Update-GitLocalProjectFromRemote -Project $detachedProject | Out-Null } 'detached HEAD' 'Detached HEAD pull protection'
    Add-Content -LiteralPath (Join-Path $detached 'README.txt') -Value 'detached-change' -Encoding UTF8
    Assert-ThrowsMatch { Publish-GitLocalProject -Project $detachedProject -CommitMessage 'qa: detached push' | Out-Null } 'detached HEAD' 'Detached HEAD push protection'

    $pushReject = Join-Path $base 'push-reject'
    Invoke-GitLocalGit -Arguments @('clone',$remote,$pushReject) | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $pushReject -Arguments @('config','user.name','GitLocal QA') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $pushReject -Arguments @('config','user.email','qa@example.invalid') | Out-Null
    Add-Content -LiteralPath (Join-Path $seed 'README.txt') -Value 'remote-ahead-for-push-reject' -Encoding UTF8
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('add','-A') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('commit','-m','qa: remote ahead for rejection') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('push','origin','main') | Out-Null
    Add-Content -LiteralPath (Join-Path $pushReject 'README.txt') -Value 'local-behind-push' -Encoding UTF8
    $pushRejectProject = [pscustomobject]@{ id='push-reject'; name='push-reject'; localPath=$pushReject; repositoryUrl=$remote; branch='main' }
    Assert-ThrowsMatch { Publish-GitLocalProject -Project $pushRejectProject -CommitMessage 'qa: rejected push' | Out-Null } 'GitHub 푸시에 실패했습니다' 'Rejected push protection'

    $pullConflict = Join-Path $base 'pull-conflict'
    Invoke-GitLocalGit -Arguments @('clone',$remote,$pullConflict) | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $pullConflict -Arguments @('config','user.name','GitLocal QA') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $pullConflict -Arguments @('config','user.email','qa@example.invalid') | Out-Null
    Add-Content -LiteralPath (Join-Path $pullConflict 'README.txt') -Value 'local-diverged-change' -Encoding UTF8
    Invoke-GitLocalGit -WorkingDirectory $pullConflict -Arguments @('add','-A') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $pullConflict -Arguments @('commit','-m','qa: local divergence') | Out-Null
    Add-Content -LiteralPath (Join-Path $seed 'README.txt') -Value 'remote-diverged-change' -Encoding UTF8
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('add','-A') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('commit','-m','qa: remote divergence') | Out-Null
    Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('push','origin','main') | Out-Null
    $pullConflictProject = [pscustomobject]@{ id='pull-conflict'; name='pull-conflict'; localPath=$pullConflict; repositoryUrl=$remote; branch='main' }
    Assert-ThrowsMatch { Update-GitLocalProjectFromRemote -Project $pullConflictProject | Out-Null } '분기|fast-forward' 'Diverged pull protection'

    $networkStub = Join-Path $base 'git-network-fail.cmd'
    @('@echo off','1>&2 echo fatal: unable to access https://github.com/example/repo.git/: Could not resolve host: github.com','exit /b 128') | Set-Content -LiteralPath $networkStub -Encoding ASCII
    $env:GITLOCAL_GIT_EXE = $networkStub
    Assert-ThrowsMatch { Test-GitLocalRemoteAccess 'https://github.com/example/repo' | Out-Null } '인터넷 연결' 'Simulated network failure handling'

    $permissionStub = Join-Path $base 'git-permission-fail.cmd'
    @('@echo off','1>&2 echo remote: Permission to example/repo.git denied to qa-user.','1>&2 echo fatal: unable to access repository','exit /b 128') | Set-Content -LiteralPath $permissionStub -Encoding ASCII
    $env:GITLOCAL_GIT_EXE = $permissionStub
    Assert-ThrowsMatch { Test-GitLocalRemoteAccess 'https://github.com/example/repo' | Out-Null } '인증 상태' 'Simulated permission denied handling'
    $env:GITLOCAL_GIT_EXE = $git

    Write-Host ''
    Write-Host 'ALL CORE QA TESTS PASSED' -ForegroundColor Green
}
finally {
    $env:GITLOCAL_CONFIG_HOME = $oldConfigHome
    $env:GITLOCAL_ALLOW_LOCAL_REMOTE = $oldAllowLocal
    $env:GITLOCAL_GIT_EXE = $oldGitExe
    if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}

