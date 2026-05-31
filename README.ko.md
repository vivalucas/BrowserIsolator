# 브라우저 분리 (BrowserIsolator)

한 대의 Mac에서 여러 개의 독립된 Chrome 환경을 동시에 실행합니다. 각 환경은 Cookie, LocalStorage, 비밀번호, 로그인 상태를 따로 저장하므로 여러 계정을 훨씬 편하게 관리할 수 있습니다.

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator의 목표는 명확합니다. 로컬 브라우저 환경을 안정적으로 분리하는 것입니다. 복잡한 우회/반탐지 플랫폼이 아니며, 웹사이트의 위험 제어를 우회한다고 보장하지 않습니다.

## 기능

- **독립 환경**: 환경마다 별도의 Chrome 데이터 디렉터리 사용
- **빠른 실행/종료**: 메인 패널 또는 메뉴 막대에서 시작, 닫기, 모두 닫기. 선택된 환경 행을 한 번 더 클릭해 시작할 수 있고, 닫을 때 Chrome 종료를 기다립니다
- **환경 정보 표시**: 왼쪽 목록은 상태, 디스크 사용량, 마지막 사용 시간을 보여주고, 오른쪽 세부 정보 패널은 profile 경로, 실행 모드, 오류, 작업, 고급 정보를 보여줍니다. 디버깅 포트는 필요할 때 고급 정보에만 표시
- **레이아웃 기억**: 메인 창 크기, 위치, 사이드바 너비가 다음 실행 시 복원됩니다
- **이름과 메모**: 계정이나 용도에 맞게 환경 이름과 짧은 메모 지정
- **안전한 삭제**: 삭제할 때 환경 이름을 입력해야 하며 데이터는 휴지통으로 이동합니다
- **기본 모드 우선**: 기본값은 profile 데이터만 분리하며 디버깅 포트나 페이지 스크립트 주입을 사용하지 않습니다
- **선택적 차이 모드**: 설정에서 환경별로 켤 수 있습니다. 켠 환경은 다음 시작 때 `navigator.hardwareConcurrency`와 `navigator.deviceMemory`를 주입합니다
- **외부 링크**: BrowserIsolator를 기본 브라우저로 지정하고, 다른 앱에서 연 링크가 들어갈 환경 선택. 대상이 사용할 수 없으면 링크가 사라지지 않도록 안내를 표시합니다
- **브라우저 자동 설치**: 처음 실행할 때 공식 Google Chrome 자동 다운로드
- **설정 패널**: Chrome 상태와 버전, 데이터 폴더, 경로 복사, Chrome 다시 다운로드, 외부 링크, 언어, 외관, 고급 세부 정보, 업데이트, 작성자 연락처, 피드백을 확인합니다
- **설정 복구**: `config.json`이 손상되었거나 읽을 수 없으면 기본 설정으로 시작하고 가능한 경우 손상된 파일을 백업합니다
- **로컬 우선**: 설정, Chrome, 환경 데이터는 Mac에만 저장되며 사용자 데이터를 업로드하거나 수집하지 않습니다
- **7개 언어 지원**: 中文, English, 日本語, 한국어, Deutsch, Français, Русский

## 요구 사항

- macOS 13 Ventura 이상
- Apple Silicon Mac (M1 이상)

현재 릴리스는 `arm64-apple-macosx13.0`용이며 Intel Mac은 지원하지 않습니다.

## 설치

### 방법 1: DMG 다운로드

1. [Releases](../../releases)에서 최신 `BrowserIsolator.dmg` 다운로드
2. DMG를 열고 `BrowserIsolator.app`을 Applications 폴더로 이동
3. 처음 실행할 때 macOS가 개발자를 확인할 수 없거나 앱이 손상되었다고 표시하면 다음을 실행하세요:

   ```bash
   xattr -cr /Applications/BrowserIsolator.app
   ```

이후 앱 업데이트는 **설정 -> 정보 및 지원 -> 업데이트 확인**에서 확인할 수 있습니다. 첫 설치는 계속 Releases의 DMG로 시작합니다.

### 방법 2: 직접 빌드

실행 파일만 빌드:

```bash
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx13.0
```

더블 클릭 가능한 `.app` 생성:

```bash
./build.sh
```

## 브라우저 엔진

BrowserIsolator는 별도의 공식 Google Chrome 복사본을 사용합니다. 기존 Chrome 설정을 읽거나 변경하지 않습니다.

저장 위치:

```text
~/Library/Application Support/BrowserIsolator/Chromium/Google Chrome.app/
```

자동 다운로드가 실패하면 Google Chrome을 수동으로 내려받고 `Google Chrome.app`을 `~/Library/Application Support/BrowserIsolator/Chromium/`에 넣으세요.

## 사용법

- **시작**: 환경 행의 시작 클릭, 선택된 환경 행 한 번 더 클릭, 또는 오른쪽 세부 정보 패널에서 시작합니다. 실패하면 오류가 표시됩니다
- **닫기**: 실행 중인 환경의 닫기 클릭. Chrome이 종료될 때까지 닫는 중 상태가 표시됩니다
- **모두 닫기**: 툴바의 모두 닫기
- **추가**: 툴바의 환경 추가
- **이름 변경 / 메모 / 삭제**: 환경을 우클릭하거나 오른쪽 세부 정보 패널에서 작업합니다. 삭제 시 데이터는 휴지통으로 이동합니다
- **외부 링크**: **설정 -> 외부 링크**에서 열기 위치를 선택하고 BrowserIsolator를 기본 브라우저로 지정할 수 있습니다. 환경이 아직 준비되지 않았거나 사용할 수 있는 환경이 없으면 링크를 복사할 수 있고, 사용할 수 있는 환경이 없을 때는 메인 패널도 열 수 있습니다
- **설정**: Chrome 상태, 데이터 폴더, 경로 복사, Chrome 다시 다운로드, 외관, 언어, 업데이트, 작성자 정보, 피드백 링크를 확인합니다. Chrome 다시 다운로드는 시작 중, 실행 중, 닫는 중인 환경이 없을 때만 사용할 수 있습니다
- **차이 모드**: 설정에서 환경별로 켭니다. 실행 중인 환경은 변경할 수 없으며, 닫은 뒤 바꾸고 다음 시작 때 적용됩니다
- **언어 변경**: 툴바 또는 메뉴 막대의 지구본 메뉴

## 데이터 위치

```text
~/Library/Application Support/BrowserIsolator/
├── config.json          # 환경, 이름, 메모
├── Chromium/
│   └── Google Chrome.app/
└── Profiles/
    ├── p1/
    ├── p2/
    └── p3/
```

완전히 제거하려면 이 `BrowserIsolator` 폴더를 삭제하세요.

`config.json`이 손상되었거나 읽을 수 없으면 BrowserIsolator는 경고를 표시하고 기본 설정을 불러오며, 가능한 경우 원본 파일을 `config.corrupt-<timestamp>.json`으로 보존합니다.

## FAQ

### 기존 Chrome을 사용하지 않는 이유는?

일상적으로 사용하는 브라우저와 데이터를 분리하기 위해서입니다. BrowserIsolator는 자체 Chrome과 profile 폴더를 사용합니다.

### 계정 차단을 막을 수 있나요?

보장할 수 없습니다. 이 프로젝트는 로컬 데이터 분리를 중심으로, 필요할 때 가벼운 지문 차별화를 제공합니다. 탐지 우회를 약속하지 않습니다.

### 차이 모드는 무엇을 하나요?

기본값에서는 아무것도 주입하지 않습니다. BrowserIsolator는 기본 모드를 우선하며 로컬 profile 데이터만 분리합니다.

설정에서 차이 모드를 켠 환경은 다음 시작 때 Chrome DevTools Protocol로 `navigator.hardwareConcurrency`와 `navigator.deviceMemory` 값을 환경별로 설정합니다. 현재 page target을 주기적으로 동기화하므로 새로 연 탭에도 주입됩니다. 완전한 기기 시뮬레이션은 아닙니다.

이 모드는 Chrome 시작 인자와 CDP 사용에 영향을 주므로 실행 중인 환경에서는 전환할 수 없습니다.

### Chrome은 자동 업데이트되나요?

아니요. 업데이트하려면 먼저 **설정 -> Chrome 다시 다운로드**를 사용하세요. 모든 환경이 중지되어 있어야 하며 시작 중이나 닫는 중이면 안 됩니다. 수동으로 업데이트하려면 `~/Library/Application Support/BrowserIsolator/Chromium/`을 삭제한 뒤 앱을 다시 실행하세요.

### BrowserIsolator는 자동 업데이트되나요?

앱 내에서 업데이트를 확인할 수 있습니다. 메뉴 막대의 업데이트 확인 또는 **설정 -> 정보 및 지원**을 사용하세요. 업데이트 확인은 Sparkle과 GitHub Releases를 사용합니다.

### 다른 앱에서 연 링크를 특정 환경으로 보내려면?

**설정 -> 외부 링크**에서 열기 위치를 선택하고 “기본 브라우저로 지정”을 클릭하세요. 메일, 채팅, 메모 등에서 연 http/https 링크가 선택한 환경으로 전달됩니다. 환경이 아직 준비되지 않았거나 사용할 수 있는 환경이 없으면 링크를 복사할 수 있는 안내가 표시됩니다. 사용할 수 있는 환경이 없을 때는 메인 패널도 열 수 있습니다.
