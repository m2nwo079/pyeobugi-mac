# 개발 환경 세팅

새 저장소를 만들고 Xcode 프로젝트를 구성하는 순서. 처음 한 번만 하면 되는 단계와 클론할 때마다 하는 단계를 구분했다.

> Xcode 메뉴·설정 이름은 버전에 따라 조금씩 다를 수 있다. 아래는 SwiftUI 앱 템플릿 기준이다.

## 0. 준비물

- macOS, Xcode (App Store), Xcode 첫 실행 시 추가 구성 요소 설치
- Git (Xcode Command Line Tools에 포함: `xcode-select --install`)
- Apple ID를 Xcode > Settings > Accounts에 로그인 (개발 서명용, 무료 계정으로도 로컬 실행 가능)

## 1. GitHub 저장소 만들기 (최초 1회)

`main`에 직접 커밋하지 않는 규칙을 처음부터 지키기 위해, 초기 커밋은 GitHub가 만들게 한다.

1. GitHub에서 새 저장소 `pyeobugi-mac` 생성
   - **Add a README file 체크** (GitHub가 `main`에 첫 커밋을 만든다)
   - `.gitignore` 템플릿은 선택하지 않는다 (이 저장소의 `.gitignore`를 쓴다)
2. 클론한다.

```bash
cd ~/Developer
git clone https://github.com/<owner>/pyeobugi-mac.git
cd pyeobugi-mac
```


## 2. 커밋 차단 훅 설치 (클론할 때마다)

훅 경로 설정은 저장소에 저장되지 않으므로 클론할 때마다 실행해야 한다.
최초 세팅 때는 아직 `.githooks/`가 없으므로, 3번에서 파일을 복사한 직후에 실행한다.

```bash
git config core.hooksPath .githooks
chmod +x .githooks/*
```

확인:

```bash
git switch main
git commit --allow-empty -m "test"
# error: direct commits to 'main' are not allowed.
```

작업 브랜치에서 확인했다면 `git switch -`로 원래 브랜치로 돌아간다.

훅이 막는 것: `main`에서의 커밋(pre-commit), `main`에서의 머지 커밋(pre-merge-commit), 원격 `main`으로의 푸시(pre-push).
GitHub 쪽 보호 규칙은 따로 걸지 않는다. 이 훅과 `CLAUDE.md` 규칙으로만 지키며, `--no-verify`로 우회하지 않는다.

## 3. 이 문서 묶음 넣기 (최초 1회, 작업 브랜치에서)

```bash
git switch -c chore/project-docs
# CLAUDE.md, CLAUDE.local.md, local/, README.md, .gitignore, .githooks/, Config/, docs/ 를 저장소 루트에 복사
# 다운로드 과정에서 실행 권한이 빠지므로 다시 준다 (이 상태로 커밋되어 클론해도 실행 권한이 유지된다)
chmod +x .githooks/*
git config core.hooksPath .githooks
git status
```

`git status`에 `CLAUDE.local.md`와 `local/`이 나오지 않으면 `.gitignore`가 제대로 동작하는 것이다.
기존 `README.md`(GitHub가 만든 것)는 이 묶음의 `README.md`로 덮어쓴다.

## 4. Xcode 프로젝트 만들기 (최초 1회)

1. Xcode > File > New > Project > **macOS** > **App**
2. 옵션
   - Product Name: `PyeobugiMac`
   - Organization Identifier: 예) `com.pyeobugi` → Bundle ID `com.pyeobugi.PyeobugiMac`
   - Interface: SwiftUI, Language: Swift
   - Testing System: Swift Testing
   - Storage: None
3. 저장 위치는 클론한 `pyeobugi-mac` 폴더. **Create Git repository 체크는 해제** (이미 Git 저장소다)

### 4-1. 기본 설정 (TARGETS > PyeobugiMac)

| 위치 | 설정 |
| --- | --- |
| General > Minimum Deployments | macOS 14.0 권장 (`docs/roadmap.md` 미결정 사항 참고) |
| Signing & Capabilities > Signing | Automatically manage signing, Team 선택 |
| Signing & Capabilities > App Sandbox | Hardware: **Camera** 체크, Network: **Outgoing Connections (Client)** 체크 |
| Signing & Capabilities > Hardened Runtime | 추가 (배포 공증에 필요). Resource Access에서 **Camera** 체크 |
| Build Settings > Default Actor Isolation | `MainActor` (새 템플릿 기본값인지 확인) |

### 4-2. 카메라 권한 문구

TARGETS > Info (또는 Build Settings의 `INFOPLIST_KEY_NSCameraUsageDescription`)

- Privacy - Camera Usage Description: `바른 자세를 확인하기 위해 카메라를 사용합니다. 영상은 기기 밖으로 나가지 않습니다.`

이 문구가 없으면 카메라 접근 시 앱이 종료된다.

### 4-3. xcconfig 연결 (API 주소)

1. `Config/` 폴더를 프로젝트 네비게이터로 끌어다 놓는다 (타깃 멤버십은 해제).
2. PROJECT > PyeobugiMac > Info > Configurations
   - Debug → `Debug`
   - Release → `Release`
3. 앱이 값을 읽을 수 있게 Info.plist에 키를 추가한다. TARGETS > Info > Custom macOS Application Target Properties에
   `APIBaseURL` (String) = `$(API_BASE_URL)` 추가
4. 코드에서 읽기

```swift
let baseURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as! String)!
```

5. Debug는 `http://localhost`를 쓰므로 App Transport Security에서 로컬 네트워크를 허용한다.
   Info에 `App Transport Security Settings` > `Allows Local Networking` = YES

xcconfig에서 `//`는 주석으로 해석되기 때문에 URL을 `http:/$()/localhost:8080/api`처럼 쓴다.
개인적으로 다른 주소를 쓰려면 `Config/Debug.local.xcconfig`를 만들어 덮어쓴다 (gitignore 대상).

### 4-4. 로컬 Swift 패키지 추가

판정 로직과 서버 연동은 패키지로 분리한다.

1. File > New > Package > Library, 이름 `PostureCore`, 위치 `pyeobugi-mac/Packages/`
   - Add to: `PyeobugiMac` 프로젝트, Group: 프로젝트 루트
2. 같은 방법으로 `PyeobugiAPI` 생성
3. TARGETS > PyeobugiMac > General > Frameworks, Libraries, and Embedded Content > `+` > 두 라이브러리 추가
4. 각 `Package.swift`의 플랫폼을 앱과 맞춘다.

```swift
platforms: [.macOS(.v14)],
```

5. 터미널에서 로직 테스트만 빠르게 돌릴 수 있다.

```bash
cd Packages/PostureCore
swift test
```

### 4-5. 첫 커밋 (작업 브랜치에서, 성격별로 나눠서)

```bash
git branch --show-current
# chore/project-docs 여야 한다

git add .gitignore .githooks
git commit -m "chore: add gitignore and hooks that block commits to main"

git add CLAUDE.md README.md docs
git commit -m "docs: add project guide, setup and design docs"

git add Config
git commit -m "build: add xcconfig with API base URL per configuration"

git add PyeobugiMac PyeobugiMac.xcodeproj PyeobugiMacTests Packages
git commit -m "chore: create Xcode project with PostureCore and PyeobugiAPI packages"

git status
# CLAUDE.local.md, local/ 이 커밋 대상에 없어야 한다
git push -u origin chore/project-docs
```

폴더 이름은 Xcode가 만든 실제 이름에 맞춘다. GitHub에서 `chore/project-docs` → `main` PR을 열어 머지한다.

## 5. 로컬 서버

Debug 빌드는 `http://localhost:8080/api`를 바라본다. 운영 서버에 테스트 데이터가 쌓이지 않도록 개발 중에는 로컬 서버를 띄워 쓴다.
다른 주소를 쓰려면 `Config/Debug.local.xcconfig`에서 `API_BASE_URL`을 덮어쓴다.

## 6. 일상 작업 흐름

```bash
git switch main
git pull
git switch -c feature/<name>
# work and commit
git push -u origin feature/<name>
# open a PR: feature/<name> -> main, then merge on GitHub

git switch main
git pull
git branch -d feature/<name>
```

- 작업 브랜치는 하루~며칠 안에 머지할 크기로 나눈다. 오래 걸리는 기능은 미완성 부분을 숨긴 채 단계별로 머지한다.
- 작업 중 `main`이 많이 바뀌었으면 `git rebase main`(푸시 전) 또는 `git merge main`(푸시 후)으로 따라간다.
- 릴리스할 때는 `main`의 해당 커밋에 태그를 붙인다.

```bash
git switch main
git pull
git tag v0.1.0
git push origin v0.1.0
```

태그 푸시는 브랜치 푸시가 아니므로 pre-push 훅에 막히지 않는다.
