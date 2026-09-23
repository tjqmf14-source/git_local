param([switch]$SelfTest,[string]$ScreenshotPath)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

Import-Module (Join-Path $PSScriptRoot 'GitLocal.Core.psm1') -Force

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Git Local'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1100,720)
$form.MinimumSize = New-Object System.Drawing.Size(900,600)
$form.Font = New-Object System.Drawing.Font('Segoe UI',10)

$iconPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\GitLocal.ico'
if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
    try { $form.Icon = New-Object System.Drawing.Icon($iconPath) } catch {}
}

$top = New-Object System.Windows.Forms.TableLayoutPanel
$top.Dock = 'Fill'
$top.Height = 128
$top.ColumnCount = 4
$top.RowCount = 3
$top.Padding = New-Object System.Windows.Forms.Padding(12)
$top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',100)))
$top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',45)))
$top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',110)))
$top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',55)))

function Add-Label([string]$text,[int]$col,[int]$row) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.TextAlign = 'MiddleLeft'
    $l.Dock = 'Fill'
    $top.Controls.Add($l,$col,$row)
    return $l
}

Add-Label '프로젝트 이름' 0 0 | Out-Null
Add-Label 'GitHub 주소' 0 1 | Out-Null
Add-Label '로컬 폴더' 0 2 | Out-Null

$nameBox = New-Object System.Windows.Forms.TextBox
$nameBox.Dock = 'Fill'
$top.Controls.Add($nameBox,1,0)
$top.SetColumnSpan($nameBox,3)

$repoBox = New-Object System.Windows.Forms.TextBox
$repoBox.Dock = 'Fill'
$top.Controls.Add($repoBox,1,1)
$top.SetColumnSpan($repoBox,3)

$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Dock = 'Fill'
$top.Controls.Add($pathBox,1,2)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = '폴더 선택'
$browseButton.Dock = 'Fill'
$top.Controls.Add($browseButton,2,2)

$registerButton = New-Object System.Windows.Forms.Button
$registerButton.Text = '등록 / 연결'
$registerButton.Dock = 'Fill'
$top.Controls.Add($registerButton,3,2)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $true
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.RowHeadersVisible = $false

$null = $grid.Columns.Add('Id','ID')
$grid.Columns['Id'].Visible = $false
$null = $grid.Columns.Add('Name','프로젝트')
$null = $grid.Columns.Add('Branch','브랜치')
$null = $grid.Columns.Add('State','상태')
$null = $grid.Columns.Add('Path','로컬 경로')
$grid.Columns['Name'].FillWeight = 18
$grid.Columns['Branch'].FillWeight = 12
$grid.Columns['State'].FillWeight = 20
$grid.Columns['Path'].FillWeight = 50

$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Dock = 'Fill'
$buttonPanel.Height = 52
$buttonPanel.FlowDirection = 'LeftToRight'
$buttonPanel.Padding = New-Object System.Windows.Forms.Padding(10,8,10,8)

function New-ActionButton([string]$text,[int]$width=135) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Width = $width
    $b.Height = 32
    $buttonPanel.Controls.Add($b)
    return $b
}

$refreshButton = New-ActionButton '상태 새로고침'
$pullButton = New-ActionButton 'GitHub → 로컬'
$pushButton = New-ActionButton '커밋 + 푸시'
$openButton = New-ActionButton '폴더 열기'
$removeButton = New-ActionButton '등록 삭제'

$log = New-Object System.Windows.Forms.TextBox
$log.Dock = 'Fill'
$log.Height = 150
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.BackColor = [System.Drawing.Color]::White

function Write-Log([string]$message) {
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $log.AppendText("[$stamp] $message" + [Environment]::NewLine)
}

function Show-Error([Exception]$exception) {
    Write-Log ('오류: ' + $exception.Message)
    if ($SelfTest) { throw $exception }
    [System.Windows.Forms.MessageBox]::Show($form,$exception.Message,'Git Local - 오류','OK','Error') | Out-Null
}

function Get-SelectedProject {
    if ($grid.SelectedRows.Count -lt 1) { throw '프로젝트를 먼저 선택하세요.' }
    $id = [string]$grid.SelectedRows[0].Cells['Id'].Value
    return Get-GitLocalProject -Id $id
}

function Refresh-Grid {
    $selectedId = $null
    if ($grid.SelectedRows.Count -gt 0) { $selectedId = [string]$grid.SelectedRows[0].Cells['Id'].Value }
    $grid.Rows.Clear()

    foreach ($p in @(Get-GitLocalProjects)) {
        try {
            $s = Get-GitLocalProjectStatus -Project $p
            $state = $s.Message
            $branch = $s.Branch
        } catch {
            $state = '상태 확인 실패'
            $branch = [string]$p.branch
        }
        $index = $grid.Rows.Add($p.id,$p.name,$branch,$state,$p.localPath)
        if ($p.id -eq $selectedId) { $grid.Rows[$index].Selected = $true }
    }
    Write-Log ('프로젝트 ' + $grid.Rows.Count + '개 상태 확인 완료')
}

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Git 프로젝트를 저장하거나 연결할 로컬 폴더를 선택하세요.'
    if ($dialog.ShowDialog($form) -eq 'OK') { $pathBox.Text = $dialog.SelectedPath }
})

$registerButton.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($repoBox.Text)) { throw 'GitHub 주소를 입력하세요.' }
        if ([string]::IsNullOrWhiteSpace($pathBox.Text)) { throw '로컬 폴더를 입력하세요.' }
        $result = Register-GitLocalProject -Name $nameBox.Text -RepositoryUrl $repoBox.Text -LocalPath $pathBox.Text
        Write-Log ("등록 완료: {0} ({1})" -f $result.Project.name,$result.Mode)
        $nameBox.Clear(); $repoBox.Clear(); $pathBox.Clear()
        Refresh-Grid
    } catch { Show-Error $_.Exception }
})

$refreshButton.Add_Click({ try { Refresh-Grid } catch { Show-Error $_.Exception } })

$pullButton.Add_Click({
    try {
        $p = Get-SelectedProject
        Write-Log ("가져오기 시작: " + $p.name)
        $r = Update-GitLocalProjectFromRemote -Project $p
        Write-Log ("가져오기 완료: " + $r.Result)
        Refresh-Grid
    } catch { Show-Error $_.Exception }
})

$pushButton.Add_Click({
    try {
        $p = Get-SelectedProject
        $defaultMessage = 'sync: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        if ($SelfTest) { $message = 'qa: ui interaction smoke push' }
        else { $message = [Microsoft.VisualBasic.Interaction]::InputBox('커밋 메시지를 입력하세요.','Git Local - 커밋',$defaultMessage) }
        if ([string]::IsNullOrWhiteSpace($message)) { return }
        Write-Log ("커밋/푸시 시작: " + $p.name)
        $r = Publish-GitLocalProject -Project $p -CommitMessage $message
        if ($r.Result -eq 'no-changes') { Write-Log '변경사항이 없어 커밋하지 않았습니다.' }
        else { Write-Log ("푸시 완료: " + $r.Branch) }
        Refresh-Grid
    } catch { Show-Error $_.Exception }
})

$openButton.Add_Click({
    try {
        $p = Get-SelectedProject
        if (-not (Test-Path -LiteralPath $p.localPath -PathType Container)) { throw '로컬 폴더가 없습니다.' }
        Start-Process explorer.exe -ArgumentList @($p.localPath)
    } catch { Show-Error $_.Exception }
})

$removeButton.Add_Click({
    try {
        $p = Get-SelectedProject
        if ($SelfTest) { $answer = 'Yes' }
        else { $answer = [System.Windows.Forms.MessageBox]::Show($form,"'$($p.name)' 등록만 삭제합니다. 로컬 파일은 삭제하지 않습니다.",'Git Local','YesNo','Question') }
        if ($answer -eq 'Yes') {
            Remove-GitLocalProject -Id $p.id | Out-Null
            Write-Log ("등록 삭제: " + $p.name)
            Refresh-Grid
        }
    } catch { Show-Error $_.Exception }
})

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 1
$layout.RowCount = 4
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',128)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',52)))
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',150)))
$layout.Controls.Add($top,0,0)
$layout.Controls.Add($grid,0,1)
$layout.Controls.Add($buttonPanel,0,2)
$layout.Controls.Add($log,0,3)
$form.Controls.Add($layout)

$form.Add_Shown({
    try {
        Resolve-GitLocalGitExecutable | Out-Null
        Refresh-Grid
    } catch { Show-Error $_.Exception }
})

if ($SelfTest) {
    $oldConfigHome = $env:GITLOCAL_CONFIG_HOME
    $oldAllowLocal = $env:GITLOCAL_ALLOW_LOCAL_REMOTE
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ('GitLocal-UI-QA-' + [Guid]::NewGuid().ToString('N'))
    $configRoot = Join-Path $base 'config'
    $remote = Join-Path $base 'remote.git'
    $seed = Join-Path $base 'seed'
    $target = Join-Path $base 'work'

    try {
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        $env:GITLOCAL_CONFIG_HOME = $configRoot
        $env:GITLOCAL_ALLOW_LOCAL_REMOTE = '1'
        Resolve-GitLocalGitExecutable | Out-Null

        Invoke-GitLocalGit -Arguments @('init','--bare',$remote) | Out-Null
        New-Item -ItemType Directory -Path $seed -Force | Out-Null
        Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('init','-b','main') | Out-Null
        Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('config','user.name','GitLocal UI QA') | Out-Null
        Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('config','user.email','ui-qa@example.invalid') | Out-Null
        Set-Content -LiteralPath (Join-Path $seed 'README.txt') -Value 'ui-seed' -Encoding UTF8
        Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('add','-A') | Out-Null
        Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('commit','-m','ui qa seed') | Out-Null
        Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('remote','add','origin',$remote) | Out-Null
        Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('push','-u','origin','main') | Out-Null
        Invoke-GitLocalGit -Arguments @("--git-dir=$remote",'symbolic-ref','HEAD','refs/heads/main') | Out-Null

        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        if (-not $form.IsHandleCreated -or -not $form.Visible) { throw 'UI 창 핸들이 생성되거나 표시되지 않았습니다.' }

        $buttons = @($registerButton,$refreshButton,$pullButton,$pushButton,$openButton,$removeButton)
        if ($buttons.Count -ne 6) { throw '필수 UI 버튼 개수가 올바르지 않습니다.' }
        foreach ($button in $buttons) {
            if (-not $button.IsHandleCreated) { throw "UI 버튼 핸들이 생성되지 않았습니다: $($button.Text)" }
        }

        $refreshButton.PerformClick()
        [System.Windows.Forms.Application]::DoEvents()

        $nameBox.Text = 'UI QA Project'
        $repoBox.Text = $remote
        $pathBox.Text = $target
        $registerButton.PerformClick()
        [System.Windows.Forms.Application]::DoEvents()
        if ($grid.Rows.Count -ne 1) { throw "등록 버튼 실행 후 프로젝트 행 수가 올바르지 않습니다: $($grid.Rows.Count)" }
        if (@(Get-GitLocalProjects).Count -ne 1) { throw '등록 버튼 실행 결과가 설정에 저장되지 않았습니다.' }
        Invoke-GitLocalGit -WorkingDirectory $target -Arguments @('config','user.name','GitLocal UI QA') | Out-Null
        Invoke-GitLocalGit -WorkingDirectory $target -Arguments @('config','user.email','ui-qa@example.invalid') | Out-Null

        $grid.ClearSelection()
        $grid.Rows[0].Selected = $true
        $grid.CurrentCell = $grid.Rows[0].Cells['Name']

        Add-Content -LiteralPath (Join-Path $seed 'README.txt') -Value 'ui-remote-change' -Encoding UTF8
        Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('add','-A') | Out-Null
        Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('commit','-m','ui qa remote change') | Out-Null
        Invoke-GitLocalGit -WorkingDirectory $seed -Arguments @('push','origin','main') | Out-Null

        $pullButton.PerformClick()
        [System.Windows.Forms.Application]::DoEvents()
        $pulled = Get-Content -LiteralPath (Join-Path $target 'README.txt') -Raw
        if ($pulled -notmatch 'ui-remote-change') { throw 'GitHub → 로컬 버튼이 원격 변경을 반영하지 못했습니다.' }

        Add-Content -LiteralPath (Join-Path $target 'README.txt') -Value 'ui-local-push' -Encoding UTF8
        $pushButton.PerformClick()
        [System.Windows.Forms.Application]::DoEvents()
        $remoteText = (Invoke-GitLocalGit -Arguments @("--git-dir=$remote",'show','main:README.txt')).Output
        if ($remoteText -notmatch 'ui-local-push') { throw '커밋 + 푸시 버튼이 로컬 변경을 원격에 반영하지 못했습니다.' }

        $refreshButton.PerformClick()
        [System.Windows.Forms.Application]::DoEvents()
        if ($log.Text -notmatch '등록 완료' -or $log.Text -notmatch '가져오기 완료' -or $log.Text -notmatch '푸시 완료') {
            throw 'UI 작업 로그에 필수 성공 이벤트가 기록되지 않았습니다.'
        }

        if (-not [string]::IsNullOrWhiteSpace($ScreenshotPath)) {
            $shotParent = Split-Path -Parent $ScreenshotPath
            if (-not [string]::IsNullOrWhiteSpace($shotParent) -and -not (Test-Path -LiteralPath $shotParent -PathType Container)) {
                New-Item -ItemType Directory -Path $shotParent -Force | Out-Null
            }
            $form.Refresh()
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 250
            $width = [Math]::Max(1,$form.ClientSize.Width)
            $height = [Math]::Max(1,$form.ClientSize.Height)
            $bitmap = New-Object System.Drawing.Bitmap $width,$height
            try {
                $bounds = New-Object System.Drawing.Rectangle -ArgumentList 0,0,$width,$height
                $form.DrawToBitmap($bitmap,$bounds)
                $bitmap.Save($ScreenshotPath,[System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $bitmap.Dispose()
            }
            if (-not (Test-Path -LiteralPath $ScreenshotPath -PathType Leaf)) { throw 'UI 스모크 스크린샷이 생성되지 않았습니다.' }
            Write-Output "GITLOCAL_UI_SCREENSHOT=$ScreenshotPath"
        }

        $grid.ClearSelection()
        $grid.Rows[0].Selected = $true
        $grid.CurrentCell = $grid.Rows[0].Cells['Name']
        $removeButton.PerformClick()
        [System.Windows.Forms.Application]::DoEvents()
        if (@(Get-GitLocalProjects).Count -ne 0) { throw '등록 삭제 버튼이 프로젝트 설정을 제거하지 못했습니다.' }

        Write-Output 'GITLOCAL_UI_INTERACTION_SMOKE_OK'
        Write-Output 'GITLOCAL_UI_SELFTEST_OK'
    }
    finally {
        if (-not $form.IsDisposed) {
            try { $form.Close() } catch {}
            try { $form.Dispose() } catch {}
        }
        $env:GITLOCAL_CONFIG_HOME = $oldConfigHome
        $env:GITLOCAL_ALLOW_LOCAL_REMOTE = $oldAllowLocal
        if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return
}

[System.Windows.Forms.Application]::Run($form)
