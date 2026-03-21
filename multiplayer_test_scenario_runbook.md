# Multiplayer Test Scenario Runbook

## 목적
- 이 문서는 다른 LLM이나 새 작업자가 이 저장소에서 멀티플레이 테스트 시나리오를 바로 실행하고, 필요한 코드를 어디서 봐야 하는지 빠르게 파악하도록 돕는 실행 가이드다.
- 기준 entrypoint는 `tests/test_agent/multi_test_scenario.py`다.
- 이 문서는 "무엇을 실행할지", "어떤 파일을 봐야 할지", "새 시나리오를 어디에 추가할지"를 한 곳에 모은다.

## 먼저 알아둘 핵심
- 멀티플레이 테스트는 `fixture`, `socket`, `ui` 세 층으로 나뉜다.
- 관리형 진입점은 `tests/test_agent/multi_test_scenario.py`다.
- 실제 runner 본체는 `tests/test_agent/multiplayer_runner.py`와 `tests/test_agent/multiplayer/` 아래 모듈들이다.
- 실제 2 simulator UI autoroute는 `tests/test_agent/multiplayer_ui_auto_play.py`가 담당한다.
- single-player 시나리오 파일 `tests/test_agent/test_scenarios.py`는 multiplayer runtime으로 직접 실행하지 않는다.
  coverage inventory와 migration planning 용도로만 참조한다.

## 추천 진입 순서
1. suite 목록과 coverage를 먼저 본다.
2. `fixture`로 빠른 회귀를 확인한다.
3. 필요하면 `socket`으로 authoritative transport를 검증한다.
4. 실제 product UI 문제가 의심되면 `ui` mode로 2 simulator를 돌린다.

## 가장 먼저 볼 파일

### 1. 관리형 entrypoint
- `tests/test_agent/multi_test_scenario.py`
- 이 파일이 가장 중요하다.
- 하는 일:
  - managed suite alias 제공
  - `test_scenarios.py`를 AST로 읽어 multiplayer coverage mapping 출력
  - `fixture`, `socket`, `ui` 실행 경로를 하나의 CLI로 묶음
- 먼저 이 파일의 `MANAGED_SUITES`, `UI_SUPPORTED_SCENARIOS`, `_parse_args()`를 보면 된다.

### 2. 시나리오 registry
- `tests/test_agent/multiplayer/scenarios.py`
- `MP-001` 같은 scenario definition이 여기 있다.
- 어떤 시나리오가 존재하는지, 목적이 무엇인지, required artifact가 무엇인지 확인할 때 가장 먼저 본다.

### 3. 실제 실행 골격
- `tests/test_agent/multiplayer/skeletons.py`
- fixture/scaffold 단계의 step skeleton이 있다.
- 새 시나리오를 추가할 때 registry만 추가하고 끝내면 안 되고, 보통 여기까지 같이 맞춘다.

### 4. fixture 데이터
- `tests/test_agent/multiplayer/fixtures.py`
- deterministic transcript fixture가 있다.
- socket/UI 전에 먼저 회귀를 잠그고 싶으면 여기서 fixture를 만든다.

### 5. validator
- `tests/test_agent/multiplayer/validators.py`
- fixture 결과를 어떤 기준으로 PASS/FAIL 처리하는지 정의한다.
- 새 회귀를 만들면 assertion을 여기서 명시적으로 잠그는 경우가 많다.

### 6. socket authoritative live runner
- `tests/test_agent/multiplayer/socket_transport.py`
- 실제 GoStopCLI room transport 서버와 통신하는 live path가 여기 있다.
- transport parity, terminal lifecycle, always-go probe, capture visibility probe 같은 실제 authoritative 검증 로직은 여기서 본다.

### 7. 2 simulator UI autoroute harness
- `tests/test_agent/multiplayer_ui_auto_play.py`
- 실제 SwiftUI app 두 개를 설치/실행하고 invite/join/ready/live/leave를 자동으로 돌린다.
- 현재 UI mode는 `MP-016`, `MP-017`만 직접 지원한다.
- UI 문제를 재현하거나 screen parity, action log, screenshot artifact를 확인할 때 본다.

### 8. 상세 문서
- `multiplayer_test_scenarios.md`
- 시나리오 매트릭스, artifact 정책, 배경 설명이 정리돼 있다.
- 빠른 실행법보다 상세 계약을 읽고 싶을 때 참고한다.

## 관련 Swift 파일
멀티플레이 UI나 product render mismatch를 디버깅할 때는 아래 파일들을 같이 본다.

- `GoStop/Core/MultiplayerSimulatorBridge.swift`
  - simulator bridge의 `get_state`, `play_card_by_id`, render probe payload
- `GoStop/Views/MultiplayerShellState.swift`
  - room/live snapshot 반영, statePatched 처리, product render probe 저장
- `GoStop/Views/MultiplayerShellViews.swift`
  - room/live route wiring, autoroute 연동
- `GoStop/Views/MultiplayerPlayCoordinator.swift`
  - authoritative snapshot을 `GameView`에 연결하는 coordinator
- `GoStop/Views/GameView.swift`
  - 실제 product 화면 렌더, remote choice waiting overlay, product render probe emission
- `GoStop/Core/MultiplayerStateMapper.swift`
  - authoritative snapshot -> product `GameManager` 투영
- `GoStopCLI/main.swift`
  - room transport websocket server reset/bootstrap 관련 동작

## 빠른 실행 명령

### 1. 목록 확인
```bash
python3 tests/test_agent/multi_test_scenario.py --list-suites
python3 tests/test_agent/multi_test_scenario.py --coverage
```

### 2. 전체 runnable fixture 회귀
```bash
python3 tests/test_agent/multi_test_scenario.py \
  --suite managed-all-runnable \
  --mode fixture
```

### 3. room readiness guard만 빠르게 확인
```bash
python3 tests/test_agent/multi_test_scenario.py \
  --suite managed-room-readiness-guard \
  --mode fixture
```

### 4. full-match end-to-end UI 시나리오
```bash
python3 tests/test_agent/multi_test_scenario.py \
  --suite managed-end-to-end-always-go \
  --mode ui \
  --install-app \
  --app-path /tmp/gostop_ios_build/Build/Products/Debug-iphonesimulator/GoStop.app \
  --fast-animation \
  --capture-final-screenshot
```

### 5. short captured-zone UI probe
```bash
python3 tests/test_agent/multi_test_scenario.py \
  --suite managed-capture-visibility-short \
  --mode ui \
  --install-app \
  --app-path /tmp/gostop_ios_build/Build/Products/Debug-iphonesimulator/GoStop.app \
  --fast-animation \
  --capture-final-screenshot
```

### 6. socket authoritative end-to-end
```bash
python3 tests/test_agent/multiplayer_runner.py \
  --suite socket-end-to-end \
  --mode socket \
  --binary /tmp/gostop_cli_local/Build/Products/Debug/GoStopCLI \
  --skip-build
```

## 추천 작업 플로우

### A. "현재 멀티플레이가 깨졌는지" 빠르게 보고 싶을 때
1. `--list-suites`로 suite 이름을 확인한다.
2. `managed-all-runnable --mode fixture`를 돌린다.
3. transport 레벨 문제면 `socket-smoke` 또는 `socket-end-to-end`를 돌린다.
4. 실제 UI 문제면 `managed-end-to-end-always-go --mode ui` 또는 `managed-capture-visibility-short --mode ui`를 돌린다.

### B. "먹은 카드가 늦게 보인다" 같은 product render 문제를 보고 싶을 때
1. `MP-017`을 먼저 본다.
2. 파일은 아래 순서로 본다.
   - `tests/test_agent/multiplayer_ui_auto_play.py`
   - `GoStop/Core/MultiplayerSimulatorBridge.swift`
   - `GoStop/Views/MultiplayerShellState.swift`
   - `GoStop/Views/MultiplayerPlayCoordinator.swift`
   - `GoStop/Views/GameView.swift`
   - `GoStop/Core/MultiplayerStateMapper.swift`
3. artifact는 아래를 본다.
   - `summary.md`
   - `action_log.jsonl`
   - `screen_checks.json`
   - `action_screens/`

### C. "처음부터 끝까지 게임이 도는지" 확인하고 싶을 때
1. `MP-016`을 본다.
2. 이 시나리오는 room bootstrap -> ready -> live gameplay -> terminalSummary -> leaveRoom -> roomClosed까지 본다.
3. 이 시나리오는 full-match는 보장하지만, "덱의 모든 화투를 다 소진했다"를 명시적으로 assert하지는 않는다.

## 현재 중요한 managed suite

| Suite | 시나리오 | 용도 |
| --- | --- | --- |
| `managed-all-runnable` | runnable 전체 | 현재 가능한 멀티플레이 회귀 전체 확인 |
| `managed-room-readiness-guard` | `MP-015` | premature ready / disconnect 회귀 |
| `managed-end-to-end-always-go` | `MP-016` | full-match UI/socket/fixture end-to-end |
| `managed-capture-visibility-short` | `MP-017` | 첫 2턴씩 captured-zone parity, render lag 검출 |
| `managed-choice-visibility` | `MP-005`, `MP-013` | choice privacy / actor-only visibility |
| `managed-terminal-consistency` | `MP-002`, `MP-007`, `MP-008` | terminal / timeout / resync |

## artifact를 어디서 볼지

### 관리형 artifact 기본 위치
- `test_artifacts/multiplayer/managed/`

### 주요 예시
- `test_artifacts/multiplayer/managed/managed-all-runnable/fixture/`
- `test_artifacts/multiplayer/managed/managed-end-to-end-always-go/ui/`
- `test_artifacts/multiplayer/managed/managed-capture-visibility-short/ui/`

### UI artifact에서 중요한 파일
- `summary.md`
  - 실행 요약
- `timeline.jsonl`
  - host/guest route transition과 action 흐름
- `action_log.jsonl`
  - action 단위 before/after screen summary
- `screen_checks.json`
  - render parity, hand removal, progression 체크 결과
- `host_live.png`, `guest_live.png`, `host_terminal.png`, `guest_terminal.png`
  - 핵심 화면 증거
- `action_screens/`
  - action 직후 host/guest 스크린샷

## UI mode 전제조건
- host simulator UDID 기본값:
  - `988B3B75-DD16-49AE-B5D7-B046B19A357C`
- guest simulator UDID 기본값:
  - `01DE5F5D-C372-4BE2-8CAB-3FF25E5AFBFD`
- bridge port 기본값:
  - host `8080`
  - guest `8081`
- transport URL 기본값:
  - `ws://127.0.0.1:9092`

UI mode에서 보통 먼저 필요한 명령은 아래 둘이다.

```bash
xcodebuild -project GoStop.xcodeproj \
  -scheme GoStop_Host \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/gostop_ios_build \
  build CODE_SIGNING_ALLOWED=NO
```

```bash
python3 tests/test_agent/multi_test_scenario.py \
  --suite managed-end-to-end-always-go \
  --mode ui \
  --install-app \
  --app-path /tmp/gostop_ios_build/Build/Products/Debug-iphonesimulator/GoStop.app \
  --fast-animation \
  --capture-final-screenshot
```

## socket mode 전제조건
- `GoStopCLI` binary가 필요하다.
- 보통 아래 둘 중 하나를 쓴다.
  - 이미 빌드된 binary 경로를 `--binary`로 넘긴다.
  - fresh build를 허용하고 `--skip-build`를 빼고 실행한다.

자주 쓰는 예시:
```bash
xcodebuild -project GoStop.xcodeproj \
  -scheme GoStopCLI \
  -configuration Debug \
  -derivedDataPath /tmp/gostop_cli_local \
  build CODE_SIGNING_ALLOWED=NO
```

```bash
python3 tests/test_agent/multiplayer_runner.py \
  --suite socket-end-to-end \
  --mode socket \
  --binary /tmp/gostop_cli_local/Build/Products/Debug/GoStopCLI \
  --skip-build
```

## 새 멀티플레이 시나리오를 추가할 때

### 최소 변경 파일
1. `tests/test_agent/multiplayer/scenarios.py`
   - scenario definition 추가
2. `tests/test_agent/multiplayer/skeletons.py`
   - step skeleton 추가
3. `tests/test_agent/multiplayer/fixtures.py`
   - fixture regression이 필요하면 추가
4. `tests/test_agent/multiplayer/validators.py`
   - PASS/FAIL 기준 추가
5. `tests/test_agent/multi_test_scenario.py`
   - managed suite alias와 coverage classification 필요 시 추가

### socket까지 지원하려면
- `tests/test_agent/multiplayer/socket_transport.py`도 수정해야 한다.

### UI까지 지원하려면
- `tests/test_agent/multiplayer_ui_auto_play.py`도 수정해야 한다.
- 현재 `UI_SUPPORTED_SCENARIOS`와 `parse_args()`가 `MP-016`, `MP-017`만 허용하므로 새 시나리오 ID를 추가해야 한다.

## 새 시나리오를 만들 때 참고할 기존 기준

### full-match 기준이 필요하면
- `MP-016`
- 참고 파일:
  - `tests/test_agent/multiplayer/scenarios.py`
  - `tests/test_agent/multiplayer/socket_transport.py`
  - `tests/test_agent/multiplayer_ui_auto_play.py`

### captured visibility / render parity 기준이 필요하면
- `MP-017`
- 참고 파일:
  - `tests/test_agent/multiplayer/scenarios.py`
  - `tests/test_agent/multiplayer/socket_transport.py`
  - `tests/test_agent/multiplayer_ui_auto_play.py`
  - `GoStop/Core/MultiplayerSimulatorBridge.swift`
  - `GoStop/Core/MultiplayerStateMapper.swift`
  - `GoStop/Views/GameView.swift`

### room lifecycle / ready guard 기준이 필요하면
- `MP-015`
- 참고 파일:
  - `tests/test_agent/multiplayer/scenarios.py`
  - `tests/test_agent/multiplayer/fixtures.py`
  - `tests/test_agent/multiplayer/validators.py`
  - `GoStop/Views/MultiplayerShellViews.swift`
  - `GoStop/Views/MultiplayerShellState.swift`

## 자주 헷갈리는 점
- `tests/test_agent/test_scenarios.py`는 single-player source inventory다.
  multiplayer runtime 시나리오 registry가 아니다.
- `MP-016`은 full-match end-to-end 시나리오지만, deck exhaustion 자체를 assert하지는 않는다.
- `MP-017`은 짧은 시나리오지만 product render mismatch를 잡는 데 훨씬 민감하다.
- UI mode는 현재 한 번에 정확히 하나의 scenario만 지원한다.
- UI 문제는 shell snapshot만 보면 놓칠 수 있으므로, 가능하면 render probe와 `screen_checks.json`을 같이 본다.

## 다른 LLM에게 바로 넘길 수 있는 최소 지시문
아래 순서대로 작업하면 된다.

1. `python3 tests/test_agent/multi_test_scenario.py --list-suites`
2. `python3 tests/test_agent/multi_test_scenario.py --coverage`
3. 빠른 회귀면 `managed-all-runnable --mode fixture`
4. full-match UI면 `managed-end-to-end-always-go --mode ui`
5. render lag 확인이면 `managed-capture-visibility-short --mode ui`
6. 결과는 `test_artifacts/multiplayer/managed/...` 아래 `summary.md`, `timeline.jsonl`, `action_log.jsonl`, `screen_checks.json` 순서로 본다.
7. 새 시나리오를 만들면 `scenarios.py`만이 아니라 `skeletons.py`, `fixtures.py`, `validators.py`, 필요 시 `socket_transport.py`와 `multiplayer_ui_auto_play.py`까지 같이 본다.

## 관련 문서
- `multiplayer_test_scenarios.md`
- `multiplayer_contract.md`
- `room_protocol.md`
- `multiplayer_ui_flow.md`
