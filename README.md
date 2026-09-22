# Git Local

여러 GitHub 저장소와 여러 Windows 로컬 폴더를 한 화면에서 관리하는 로컬 동기화 도구입니다.

## 현재 제공 기능

- GitHub 저장소 주소 + 로컬 폴더를 프로젝트별로 등록/저장
- 저장소가 로컬에 없으면 자동 clone
- 기존 Git 폴더를 안전하게 연결
- 현재 브랜치 / 로컬 변경 / ahead / behind 상태 확인
- **GitHub → 로컬**: fetch + fast-forward only pull
- **로컬 → GitHub**: add → commit → push
- 변경사항이 없으면 불필요한 커밋 차단
- dirty working tree에서 자동 pull 차단
- origin이 다른 저장소를 가리키면 자동 변경하지 않고 오류 표시
- URL 안에 토큰/비밀번호가 포함되면 저장 거부
- 프로젝트 등록 정보는 `%LOCALAPPDATA%\GitLocal\projects.json`에 저장
- 한글 경로 지원
- Windows GUI와 아이콘 적용

## 실행

배포 ZIP에서는 `GitLocal.exe`를 실행합니다.

소스 체크아웃에서는 `Git_Local_START.cmd`를 실행할 수 있습니다. Git 인증은 프로그램이 토큰을 저장하는 방식이 아니라 **Git for Windows / Git Credential Manager**를 사용합니다.

## 안전 원칙

- 자동 force push를 하지 않습니다.
- 로컬 변경사항이 있는 상태에서 pull을 자동 진행하지 않습니다.
- pull은 `--ff-only`로 실행합니다.
- 다른 origin을 발견하면 자동 덮어쓰기하지 않습니다.
- 인증정보가 포함된 GitHub URL은 등록하지 않습니다.

## QA

`tests/Run-Tests.ps1`이 임시 bare Git 저장소를 직접 생성하여 clone, commit/push, pull, 한글 경로, 예외 처리를 검증합니다. Windows Actions는 UI self-test, EXE self-test, ZIP 및 SHA-256 생성까지 확인합니다.

실제 GitHub 계정의 인증 성공/실패는 사용자의 Git Credential Manager 상태에 의존하므로 CI에서 개인 계정 인증정보를 사용해 PASS 처리하지 않습니다.

## 개발 규칙

개발 변경은 `dev/**` 브랜치에서 검증하고, Windows QA가 PASS한 뒤에만 `main`에 반영합니다.
