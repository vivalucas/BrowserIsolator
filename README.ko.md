# 브라우저 분리 (BrowserIsolator)

한 대의 Mac에서 여러 개의 독립된 Chrome 환경을 동시에 실행합니다. 각 환경은 Cookie, LocalStorage, 비밀번호, 로그인 상태를 따로 저장하므로 여러 계정을 훨씬 편하게 관리할 수 있습니다.

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator의 목표는 명확합니다. 로컬 브라우저 환경을 안정적으로 분리하는 것입니다. 복잡한 우회/반탐지 플랫폼이 아니며, 웹사이트의 위험 제어를 우회한다고 보장하지 않습니다.

## 기능

- **독립 환경**: 환경마다 별도의 Chrome 데이터 디렉터리 사용
- **빠른 실행/종료**: 메인 패널 또는 메뉴 막대에서 시작, 닫기, 모두 닫기
- **환경 정보 표시**: 상태, 폴더, 디버깅 포트, 디스크 사용량, 마지막 사용 시간
- **사용자 지정 이름**: 계정이나 용도에 맞게 환경 이름 변경
- **지문 차별화**: 환경별 `navigator.hardwareConcurrency`, `navigator.deviceMemory` 값 주입
- **브라우저 자동 설치**: 처음 실행할 때 공식 Google Chrome 자동 다운로드
- **로컬 우선**: 설정과 모든 환경 데이터는 Mac에만 저장
- **7개 언어 지원**: 中文, English, 日本語, 한국어, Deutsch, Français, Русский

## 요구 사항

- macOS 26 Tahoe 이상
- Apple Silicon Mac (M1 이상)

현재 릴리스는 `arm64-apple-macosx26.0`용이며 Intel Mac은 지원하지 않습니다.

## 설치

### 방법 1: DMG 다운로드

1. [Releases](../../releases)에서 최신 `BrowserIsolator.dmg` 다운로드
2. DMG를 열고 `BrowserIsolator.app`을 Applications 폴더로 이동
3. 처음 실행할 때 macOS가 개발자를 확인할 수 없거나 앱이 손상되었다고 표시하면 다음을 실행하세요:

   ```bash
   xattr -cr /Applications/BrowserIsolator.app
   ```

### 방법 2: 직접 빌드

실행 파일만 빌드:

```bash
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx26.0
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

- **시작**: 환경 행의 시작 클릭
- **닫기**: 실행 중인 환경의 닫기 클릭
- **모두 닫기**: 툴바의 모두 닫기
- **추가**: 툴바의 환경 추가
- **이름 변경 / 삭제**: 환경을 우클릭
- **언어 변경**: 툴바 또는 메뉴 막대의 지구본 메뉴

## 데이터 위치

```text
~/Library/Application Support/BrowserIsolator/
├── config.json
├── Chromium/
└── Profiles/
```

완전히 제거하려면 이 `BrowserIsolator` 폴더를 삭제하세요.

## FAQ

### 기존 Chrome을 사용하지 않는 이유는?

일상적으로 사용하는 브라우저와 데이터를 분리하기 위해서입니다. BrowserIsolator는 자체 Chrome과 profile 폴더를 사용합니다.

### 계정 차단을 막을 수 있나요?

보장할 수 없습니다. 이 프로젝트는 로컬 데이터 분리와 가벼운 지문 차별화를 제공합니다. 탐지 우회를 약속하지 않습니다.

### 지문 차별화는 무엇을 하나요?

Chrome DevTools Protocol로 `navigator.hardwareConcurrency`와 `navigator.deviceMemory` 값을 환경별로 설정합니다. 완전한 기기 시뮬레이션은 아닙니다.

### Chrome은 자동 업데이트되나요?

아니요. 업데이트하려면 `~/Library/Application Support/BrowserIsolator/Chromium/`을 삭제한 뒤 앱을 다시 실행하세요.
