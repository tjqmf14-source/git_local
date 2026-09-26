# Git Local

여러 GitHub 저장소와 여러 Windows 로컬 폴더를 한 화면에서 관리하는 로컬 동기화 도구입니다.

## 현재 제공 기능

- GitHub 저장소 주소 + 로컬 폴더를 프로젝트별로 등록/저장
- 저장소가 로컬에 없으면 자동 clone
- 기존 Git 폴더를 안전하게 연결
- 현재 브랜치 / 로컬 변경 / ahead / behind 상태 확인
- **GitHub → 로컬**: 최신 상태를 fetch한 뒤 behind-only는 fast-forward, diverged는 충돌이 없을 때 안전하게 merge
- **로컬 → GitHub**: 로컬 변경사항을 add → commit한 뒤 기존 미푸시 커밋까지 push
- 충돌 없는 분기 상태는 자동 병합
- 충돌 파일이 `package-lock.json`에 한정되면 npm 스크립트를 실행하지 않고 잠금파일을 자동 재생성해 병합
- 그 외 충돌은 merge를 자동 취소해 시작 전 상태로 복구
- 변경사항이 없고 미푸시 커밋도 없으면 불필요한 커밋/푸시 차단
- dirty working tree에서는 파일 보호를 위해 자동 병합/가져오기 차단
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
- 커밋하지 않은 로컬 변경사항이 있는 상태에서는 자동 가져오기/병합을 진행하지 않습니다.
- behind-only는 fast-forward만 사용하고, diverged는 일반 merge를 시도합니다.
- `package-lock.json` 단독 충돌만 `npm install --package-lock-only --ignore-scripts`로 재생성하며, 재생성/검증에 실패하면 즉시 abort하여 원래 HEAD/작업트리로 복구합니다.
- 소스 코드·`package.json` 등 다른 충돌은 자동 선택하거나 덮어쓰지 않습니다.
- 다른 origin을 발견하면 자동 덮어쓰기하지 않습니다.
- 인증정보가 포함된 GitHub URL은 등록하지 않습니다.

## QA

`tests/Run-Tests.ps1`이 임시 bare Git 저장소를 직접 생성하여 clone, commit/push, fast-forward, ahead-only, diverged 자동 병합, 일반 충돌 rollback, package-lock 단독 충돌 자동 재생성, dirty 보호, 한글 경로, 예외 처리를 검증합니다. Windows Actions는 UI self-test, EXE self-test, ZIP 및 SHA-256 생성까지 확인합니다.

실제 GitHub 계정의 인증 성공/실패는 사용자의 Git Credential Manager 상태에 의존하므로 CI에서 개인 계정 인증정보를 사용해 PASS 처리하지 않습니다.

## 개발 규칙

개발 변경은 `dev/**` 브랜치에서 검증하고, Windows QA가 PASS한 뒤에만 `main`에 반영합니다.
