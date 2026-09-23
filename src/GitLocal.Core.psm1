Set-StrictMode -Version Latest

function Get-GitLocalConfigRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:GITLOCAL_CONFIG_HOME)) {
        return [System.IO.Path]::GetFullPath($env:GITLOCAL_CONFIG_HOME)
    }
    $base = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($base)) { throw 'LOCALAPPDATA 경로를 확인할 수 없습니다.' }
    return (Join-Path $base 'GitLocal')
}

function Get-GitLocalConfigFile { return (Join-Path (Get-GitLocalConfigRoot) 'projects.json') }

function Resolve-GitLocalGitExecutable {
    if (-not [string]::IsNullOrWhiteSpace($env:GITLOCAL_GIT_EXE)) {
        if (-not (Test-Path -LiteralPath $env:GITLOCAL_GIT_EXE -PathType Leaf)) {
            throw "Git 실행 파일을 찾을 수 없습니다: $($env:GITLOCAL_GIT_EXE)"
        }
        return [System.IO.Path]::GetFullPath($env:GITLOCAL_GIT_EXE)
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        throw 'Git이 설치되어 있지 않거나 PATH에서 찾을 수 없습니다. Git for Windows를 설치한 뒤 다시 실행하세요.'
    }
    return $git.Source
}

function Invoke-GitLocalGit {
    [CmdletBinding()]
    param([string]$WorkingDirectory,[Parameter(Mandatory=$true)][string[]]$Arguments,[switch]$AllowFailure)

    $git = Resolve-GitLocalGitExecutable
    $pushed = $false
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
                throw "로컬 폴더가 존재하지 않습니다: $WorkingDirectory"
            }
            Push-Location -LiteralPath $WorkingDirectory
            $pushed = $true
        }

        # Windows PowerShell 5.1 can promote a native program's stderr to
        # NativeCommandError when ErrorActionPreference is Stop, even if the
        # program exits successfully. Git writes normal progress to stderr.
        # Capture both streams and trust Git's process exit code instead.
        $ErrorActionPreference = 'Continue'
        $raw = & $git @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $output = ($raw | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($pushed) { Pop-Location }
    }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $safeArgs = ($Arguments -join ' ')
        throw ("Git 명령이 실패했습니다. (exit={0}) git {1}{2}{3}" -f $exitCode,$safeArgs,[Environment]::NewLine,$output)
    }
    [pscustomobject]@{ ExitCode=$exitCode; Output=$output; Arguments=@($Arguments) }
}

function Resolve-GitLocalRepositoryUrl {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RepositoryUrl)

    $value = $RepositoryUrl.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'GitHub 저장소 주소가 비어 있습니다.' }

    if ($env:GITLOCAL_ALLOW_LOCAL_REMOTE -eq '1' -and (Test-Path -LiteralPath $value -PathType Container)) {
        return [System.IO.Path]::GetFullPath($value)
    }

    if ($value -match '^git@github\.com:(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+?)(?:\.git)?$') {
        return "https://github.com/$($Matches.owner)/$($Matches.repo).git"
    }

    try { $uri = [Uri]$value } catch { throw 'GitHub 저장소 주소 형식이 올바르지 않습니다.' }
    if ($uri.Scheme -ne 'https' -or $uri.Host.ToLowerInvariant() -ne 'github.com') {
        throw 'HTTPS GitHub 저장소 주소만 지원합니다. 예: https://github.com/owner/repo'
    }
    if (-not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
        throw '보안을 위해 사용자명이나 토큰이 포함된 URL은 저장할 수 없습니다. Git Credential Manager를 사용하세요.'
    }

    $segments = @($uri.AbsolutePath.Trim('/') -split '/')
    if ($segments.Count -ne 2) { throw 'GitHub 저장소 주소는 owner/repo 형식이어야 합니다.' }
    $owner = $segments[0]
    $repo = $segments[1]
    if ($repo.EndsWith('.git',[StringComparison]::OrdinalIgnoreCase)) { $repo = $repo.Substring(0,$repo.Length-4) }
    if ($owner -notmatch '^[A-Za-z0-9_.-]+$' -or $repo -notmatch '^[A-Za-z0-9_.-]+$') {
        throw 'GitHub 저장소 owner 또는 repo 이름에 지원하지 않는 문자가 있습니다.'
    }
    return "https://github.com/$owner/$repo.git"
}

function Read-GitLocalConfig {
    $path = Get-GitLocalConfigFile
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ version=1; projects=@() }
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { throw '설정 파일이 비어 있습니다.' }
        $config = $raw | ConvertFrom-Json
    } catch { throw ("설정 파일을 읽을 수 없습니다: {0}{1}{2}" -f $path,[Environment]::NewLine,$_.Exception.Message) }
    if ($null -eq $config.projects) { $config | Add-Member -NotePropertyName projects -NotePropertyValue @() }
    return $config
}

function Write-GitLocalConfig {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Projects)
    $root = Get-GitLocalConfigRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    $path = Get-GitLocalConfigFile
    $tmp = "$path.tmp"
    $payload = [ordered]@{ version=1; projects=@($Projects) } | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $tmp -Value $payload -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Get-GitLocalProjects { return @((Read-GitLocalConfig).projects) }

function Get-GitLocalProject {
    param([Parameter(Mandatory=$true)][string]$Id)
    $p = @(Get-GitLocalProjects | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
    if ($null -eq $p) { throw "등록된 프로젝트를 찾을 수 없습니다: $Id" }
    return $p
}

function Test-GitLocalRemoteAccess {
    param([Parameter(Mandatory=$true)][string]$RepositoryUrl)
    $repo = Resolve-GitLocalRepositoryUrl $RepositoryUrl
    $r = Invoke-GitLocalGit -Arguments @('ls-remote',$repo) -AllowFailure
    if ($r.ExitCode -ne 0) {
        throw ("원격 저장소에 접근할 수 없습니다. 주소, 인터넷 연결, GitHub 인증 상태를 확인하세요.{0}{1}" -f [Environment]::NewLine,$r.Output)
    }
    return $true
}

function Initialize-GitLocalRepository {
    param([Parameter(Mandatory=$true)][string]$LocalPath)
    $r = Invoke-GitLocalGit -WorkingDirectory $LocalPath -Arguments @('init','-b','main') -AllowFailure
    if ($r.ExitCode -ne 0) {
        Invoke-GitLocalGit -WorkingDirectory $LocalPath -Arguments @('init') | Out-Null
        Invoke-GitLocalGit -WorkingDirectory $LocalPath -Arguments @('branch','-M','main') | Out-Null
    }
}

function Register-GitLocalProject {
    [CmdletBinding()]
    param([string]$Name,[Parameter(Mandatory=$true)][string]$RepositoryUrl,[Parameter(Mandatory=$true)][string]$LocalPath,[switch]$SkipRemoteValidation)

    Resolve-GitLocalGitExecutable | Out-Null
    $repo = Resolve-GitLocalRepositoryUrl $RepositoryUrl
    $fullPath = [System.IO.Path]::GetFullPath($LocalPath)
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) { throw "로컬 경로가 폴더가 아니라 파일입니다: $fullPath" }

    $projects = @(Get-GitLocalProjects)
    foreach ($existing in $projects) {
        if ([string]::Equals([System.IO.Path]::GetFullPath([string]$existing.localPath),$fullPath,[StringComparison]::OrdinalIgnoreCase)) {
            throw "이미 등록된 로컬 폴더입니다: $fullPath"
        }
    }

    if (-not $SkipRemoteValidation) { Test-GitLocalRemoteAccess $repo | Out-Null }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        $parent = Split-Path -Parent $fullPath
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Invoke-GitLocalGit -WorkingDirectory $parent -Arguments @('clone',$repo,$fullPath) | Out-Null
        $mode = 'cloned'
    } else {
        $gitDir = Join-Path $fullPath '.git'
        if (-not (Test-Path -LiteralPath $gitDir)) {
            Initialize-GitLocalRepository $fullPath
            Invoke-GitLocalGit -WorkingDirectory $fullPath -Arguments @('remote','add','origin',$repo) | Out-Null
            $mode = 'initialized'
        } else {
            $remote = Invoke-GitLocalGit -WorkingDirectory $fullPath -Arguments @('remote','get-url','origin') -AllowFailure
            if ($remote.ExitCode -ne 0) {
                Invoke-GitLocalGit -WorkingDirectory $fullPath -Arguments @('remote','add','origin',$repo) | Out-Null
            } else {
                $existingRemote = $remote.Output.Trim()
                try { $normalizedExisting = Resolve-GitLocalRepositoryUrl $existingRemote } catch { $normalizedExisting = $existingRemote }
                if (-not [string]::Equals($normalizedExisting,$repo,[StringComparison]::OrdinalIgnoreCase)) {
                    throw ("현재 폴더의 origin이 다른 저장소를 가리킵니다.{0}현재: {1}{0}요청: {2}" -f [Environment]::NewLine,$existingRemote,$repo)
                }
            }
            $mode = 'connected'
        }
    }

    $branch = (Invoke-GitLocalGit -WorkingDirectory $fullPath -Arguments @('branch','--show-current') -AllowFailure).Output.Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch='main' }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        if ($repo -match '/(?<name>[^/\\]+?)(?:\.git)?$') { $Name=$Matches.name } else { $Name=Split-Path -Leaf $fullPath }
    }

    $now=[DateTimeOffset]::Now.ToString('o')
    $project=[pscustomobject][ordered]@{
        id=[Guid]::NewGuid().ToString('N'); name=$Name.Trim(); repositoryUrl=$repo; localPath=$fullPath;
        branch=$branch; createdAt=$now; updatedAt=$now
    }
    $projects += $project
    Write-GitLocalConfig $projects
    [pscustomobject]@{ Project=$project; Mode=$mode }
}

function Remove-GitLocalProject {
    param([Parameter(Mandatory=$true)][string]$Id)
    $all=@(Get-GitLocalProjects)
    $remaining=@($all | Where-Object { $_.id -ne $Id })
    if ($remaining.Count -eq $all.Count) { throw "등록된 프로젝트를 찾을 수 없습니다: $Id" }
    Write-GitLocalConfig $remaining
    return $true
}

function Get-GitLocalProjectStatus {
    param([Parameter(Mandatory=$true)][object]$Project)
    $path=[string]$Project.localPath
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        return [pscustomobject]@{State='missing';Branch='';Dirty=$false;Ahead=0;Behind=0;Remote=[string]$Project.repositoryUrl;Message='로컬 폴더 없음'}
    }
    $inside=Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('rev-parse','--is-inside-work-tree') -AllowFailure
    if ($inside.ExitCode -ne 0 -or $inside.Output.Trim() -ne 'true') {
        return [pscustomobject]@{State='not-git';Branch='';Dirty=$false;Ahead=0;Behind=0;Remote=[string]$Project.repositoryUrl;Message='Git 저장소가 아님'}
    }

    $branch=(Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('branch','--show-current') -AllowFailure).Output.Trim()
    $dirty=-not [string]::IsNullOrWhiteSpace((Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('status','--porcelain')).Output)
    $remoteResult=Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('remote','get-url','origin') -AllowFailure
    $remote=if ($remoteResult.ExitCode -eq 0) { $remoteResult.Output.Trim() } else { '' }
    $headProbe=Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('rev-parse','--verify','HEAD') -AllowFailure
    if ($headProbe.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($branch)) {
        return [pscustomobject]@{State='detached';Branch='';Dirty=$dirty;Ahead=0;Behind=0;Remote=$remote;Message='detached HEAD 상태'}
    }
    $ahead=0; $behind=0
    $up=Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('rev-parse','--abbrev-ref','--symbolic-full-name','@{u}') -AllowFailure
    if ($up.ExitCode -eq 0) {
        $count=Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('rev-list','--left-right','--count','HEAD...@{u}') -AllowFailure
        if ($count.ExitCode -eq 0) {
            $parts=@($count.Output.Trim() -split '\s+')
            if ($parts.Count -ge 2) { [int]::TryParse($parts[0],[ref]$ahead)|Out-Null; [int]::TryParse($parts[1],[ref]$behind)|Out-Null }
        }
    }

    $state='clean'; $message='동기화됨'
    if ($dirty) { $state='modified'; $message='로컬 변경사항 있음' }
    if ($ahead -gt 0 -and $behind -eq 0) { $state='ahead'; $message="푸시 필요 +$ahead" }
    elseif ($behind -gt 0 -and $ahead -eq 0) { $state='behind'; $message="가져오기 필요 -$behind" }
    elseif ($behind -gt 0 -and $ahead -gt 0) { $state='diverged'; $message="분기됨 +$ahead / -$behind" }
    if ($dirty -and $state -ne 'modified') { $message += ' / 로컬 변경 있음' }
    [pscustomobject]@{State=$state;Branch=$branch;Dirty=$dirty;Ahead=$ahead;Behind=$behind;Remote=$remote;Message=$message}
}

function Update-GitLocalProjectFromRemote {
    param([Parameter(Mandatory=$true)][object]$Project)
    $path=[string]$Project.localPath
    $status=Get-GitLocalProjectStatus $Project
    if ($status.State -in @('missing','not-git','detached')) { throw "프로젝트 폴더 상태가 올바르지 않습니다: $($status.Message)" }
    if ($status.Dirty) { throw '로컬 변경사항이 있어 가져오기를 중단했습니다. 먼저 커밋하거나 변경사항을 정리하세요.' }

    Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('fetch','origin','--prune') | Out-Null
    $branch=(Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('branch','--show-current') -AllowFailure).Output.Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch='main' }

    $hasHead=Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('rev-parse','--verify','HEAD') -AllowFailure
    $remoteRef="refs/remotes/origin/$branch"
    $hasRemote=Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('show-ref','--verify','--quiet',$remoteRef) -AllowFailure
    if ($hasHead.ExitCode -ne 0 -and $hasRemote.ExitCode -eq 0) {
        Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('checkout','-B',$branch,"origin/$branch") | Out-Null
        return [pscustomobject]@{Result='checked-out';Branch=$branch}
    }
    if ($hasRemote.ExitCode -ne 0) { return [pscustomobject]@{Result='no-remote-branch';Branch=$branch} }

    $up=Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('rev-parse','--abbrev-ref','--symbolic-full-name','@{u}') -AllowFailure
    if ($up.ExitCode -ne 0) { Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('branch','--set-upstream-to',"origin/$branch",$branch) | Out-Null }
    Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('pull','--ff-only') | Out-Null
    [pscustomobject]@{Result='pulled';Branch=$branch}
}

function Publish-GitLocalProject {
    param([Parameter(Mandatory=$true)][object]$Project,[Parameter(Mandatory=$true)][string]$CommitMessage)
    if ([string]::IsNullOrWhiteSpace($CommitMessage)) { throw '커밋 메시지를 입력하세요.' }

    $path=[string]$Project.localPath
    $status=Get-GitLocalProjectStatus $Project
    if ($status.State -in @('missing','not-git','detached')) { throw "프로젝트 폴더 상태가 올바르지 않습니다: $($status.Message)" }
    $changes=(Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('status','--porcelain')).Output
    if ([string]::IsNullOrWhiteSpace($changes)) { return [pscustomobject]@{Result='no-changes';Branch=$status.Branch} }

    Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('add','-A') | Out-Null
    try { Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('commit','-m',$CommitMessage.Trim()) | Out-Null }
    catch { throw ("커밋에 실패했습니다. Git user.name / user.email 설정도 확인하세요.{0}{1}" -f [Environment]::NewLine,$_.Exception.Message) }

    $branch=(Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('branch','--show-current')).Output.Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch='main'; Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('branch','-M',$branch)|Out-Null }
    try { Invoke-GitLocalGit -WorkingDirectory $path -Arguments @('push','-u','origin',$branch) | Out-Null }
    catch { throw ("GitHub 푸시에 실패했습니다. 원격 변경사항, 권한 또는 인증 상태를 확인하세요. 강제 푸시는 자동으로 수행하지 않습니다.{0}{1}" -f [Environment]::NewLine,$_.Exception.Message) }
    [pscustomobject]@{Result='pushed';Branch=$branch}
}

Export-ModuleMember -Function @(
    'Get-GitLocalConfigRoot','Get-GitLocalConfigFile','Resolve-GitLocalGitExecutable','Invoke-GitLocalGit',
    'Resolve-GitLocalRepositoryUrl','Test-GitLocalRemoteAccess','Get-GitLocalProjects','Get-GitLocalProject',
    'Register-GitLocalProject','Remove-GitLocalProject','Get-GitLocalProjectStatus',
    'Update-GitLocalProjectFromRemote','Publish-GitLocalProject'
)
