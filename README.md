# NotiOpener

macOS 알림 배너를 키보드만으로 열어보는 메뉴바 앱.

마우스에 손 뻗을 필요 없이, 단축키 하나로 배너 알림을 탐색하고 클릭할 수 있습니다.

## Features

- **단축키로 알림 클릭** — 배너가 뜨면 단축키를 눌러 바로 열기
- **복수 알림 탐색** — 여러 알림이 있으면 단축키 반복으로 순회, modifier 해제로 선택
- **커스텀 단축키** — 메뉴바에서 원하는 키 조합으로 변경 가능 (기본: Ctrl+Enter)
- **멀티 모니터 지원** — 어느 모니터에 알림이 뜨든 정확한 하이라이트 표시
- **지속적/임시 배너 모두 지원** — 알림 스타일과 관계없이 동작

## Install

### Download (권장)

[**NotiOpener.zip 다운로드 (v1.0.0)**](https://github.com/JinkwonHeo/NotiOpener/releases/download/v1.0.0/NotiOpener.zip)

1. zip 해제
2. `NotiOpener.app`을 `/Applications` 폴더로 드래그
3. "손상되었기 때문에 열 수 없습니다" 경고가 뜨면 터미널에서 실행:
   ```bash
   xattr -cr /Applications/NotiOpener.app
   ```
4. 더블클릭으로 실행

> 최초 실행 시 **손쉬운 사용(Accessibility)** 권한을 요청합니다. 허용해주세요.

### Build from source

```bash
git clone https://github.com/JinkwonHeo/NotiOpener.git
cd NotiOpener
chmod +x build.sh
./build.sh
```

빌드 결과:
- `NotiOpener.app` — 더블클릭 또는 `/Applications`에 드래그
- `NotiOpener.zip` — 배포용

## Usage

1. 실행하면 메뉴바에 🔔 아이콘이 나타남
2. 알림 배너가 뜨면 **Ctrl+Enter** (기본 단축키)
   - 단일 알림: 바로 클릭
   - 복수 알림: 반복 누르면 다음 알림으로 이동, Ctrl 해제 시 선택
3. 🔔 > **단축키 변경...** 에서 원하는 키 조합으로 변경 가능

## Requirements

- macOS 13+ (Ventura 이상)
- Accessibility 권한 필요

## License

MIT
