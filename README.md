# NotiOpener

macOS 알림 배너를 키보드만으로 열어보는 메뉴바 앱.

마우스에 손 뻗을 필요 없이, 단축키 하나로 배너 알림을 탐색하고 클릭할 수 있습니다.

## Features

- **단축키로 알림 클릭** — 배너가 뜨면 단축키를 눌러 바로 열기
- **복수 알림 탐색** — 여러 알림이 있으면 단축키 반복으로 순회, modifier 해제로 선택
- **알림 접기** — 펼쳐진 알림 목록을 단축키로 다시 접기
- **커스텀 단축키** — 메뉴바에서 열기/접기 단축키를 각각 변경 가능
- **멀티 모니터 지원** — 어느 모니터에 알림이 뜨든 정확한 하이라이트 표시
- **지속적/임시 배너 모두 지원** — 알림 스타일과 관계없이 동작

## Install

터미널에 붙여넣기:

```bash
curl -sL https://raw.githubusercontent.com/JinkwonHeo/NotiOpener/main/install.sh | bash
```

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

| 동작 | 기본 단축키 |
|------|------------|
| 알림 열기/탐색 | `Ctrl+Enter` |
| 펼쳐진 알림 접기 | `Ctrl+\` |

1. 실행하면 메뉴바에 🔔 아이콘이 나타남
2. 알림 배너가 뜨면 **Ctrl+Enter**
   - 단일 알림: 바로 클릭
   - 복수 알림: 반복 누르면 다음 알림으로 이동, Ctrl 해제 시 선택
3. 펼쳐진 알림이 많을 때 **Ctrl+\\** 로 접기
4. 🔔 메뉴에서 열기/접기 단축키를 각각 변경 가능

## Requirements

- macOS 13+ (Ventura 이상)
- Accessibility 권한 필요

## License

MIT
