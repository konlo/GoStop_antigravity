# LLM Coding Harness 교육자료

## 1. 교육 목표

이 문서는 `GoStop_antigravity` 프로젝트에서 실제로 남긴 작업 기록, skill 파일, 테스트 에이전트, artifact 체계를 바탕으로 LLM coding harness를 설명하기 위한 교육자료다.

교육 후 학습자는 다음을 설명할 수 있어야 한다.

- LLM coding harness가 단순 prompt나 test suite와 어떻게 다른지
- generation harness, validation harness, feedback harness의 역할 차이
- `SKILL.md`, `AGENTS.md`, scenario runner, artifact가 하나의 폐쇄 루프를 만드는 방식
- GoStop 프로젝트에서 harness가 어떤 파일과 실행 경로로 구현됐는지
- 새 프로젝트에 harness를 설계할 때 필요한 최소 구조

## 2. 핵심 정의

LLM coding harness는 LLM이 코드를 만들고, 검증하고, 실패 근거를 다시 읽어 고치는 전체 작업 루프를 제어하는 구조다.

단순 prompt는 "무엇을 해달라"를 말한다. 좋은 harness는 "어떤 맥락을 읽고, 어떤 경계를 지키고, 어떤 명령으로 검증하고, 실패하면 어떤 증거를 남기고, 다음 수정에 무엇을 사용해야 하는지"까지 고정한다.

```text
Generation Harness
  -> LLM이 정해진 규칙과 skill에 따라 구현
  -> Validation Harness
  -> 실행 결과와 artifact 생성
  -> Feedback Harness
  -> 실패 원인과 변경 이력이 다음 작업 입력으로 재사용
```

## 3. Harness의 세 가지 층

### 3.1 Generation Harness

Generation harness는 LLM이 결과물을 생성하기 전에 방향을 제어하는 층이다.

GoStop 프로젝트의 예시는 다음과 같다.

- `agents.md`: 프로젝트 정의, 역할, 책임 경계, 작업 순서, logging 규칙
- `SKILL.md`: 특정 작업 유형별 절차와 done criteria
- `agent_prompts/`: agent별 작업 prompt
- `docs/agent_tasks/archive/`: 라운드별 작업 지시와 범위

Generation harness가 답해야 하는 질문은 다음과 같다.

- 이 작업에서 먼저 읽어야 할 문서는 무엇인가?
- 룰, UI, ViewModel, test agent 중 어느 층을 고쳐야 하는가?
- 해서는 안 되는 변경은 무엇인가?
- 어떤 validation을 통과해야 완료인가?
- 결과를 어디에 기록해야 하는가?

### 3.2 Validation Harness

Validation harness는 생성된 코드가 실제로 맞는지 실행해서 판정하는 층이다.

GoStop 프로젝트의 예시는 다음과 같다.

- `tests/test_agent/test_scenarios.py`: single-player rule scenario
- `tests/test_agent/multiplayer_runner.py`: multiplayer fixture/socket runner
- `tests/test_agent/multi_test_scenario.py`: managed multiplayer entrypoint와 coverage mapping
- `tests/test_agent/multiplayer_ui_auto_play.py`: 2-simulator UI autoroute runner
- `scripts/run_multiplayer_cli_two_player_smoke.py`: CLI ingress smoke
- `GoStopCLI/`: Swift engine과 bridge를 외부 runner에서 구동하는 CLI target

Validation harness가 답해야 하는 질문은 다음과 같다.

- 이 변경이 실제 엔진에서 동작하는가?
- TCP fallback과 websocket transport가 같은 의미를 유지하는가?
- UI가 authoritative state를 실제 화면에 맞게 렌더링하는가?
- 실패 시 재현 가능한 로그와 snapshot이 남는가?

### 3.3 Feedback Harness

Feedback harness는 검증 결과와 작업 이력을 다음 생성 작업에 다시 넣는 층이다.

GoStop 프로젝트의 예시는 다음과 같다.

- `project_progress.md`: 요청, skill, 변경 파일, 검증, outcome 기록
- `test_artifacts/**/summary.md`: run별 요약
- `test_artifacts/**/anomaly_report.md`: 실패 원인과 재현 명령
- `multiplayer_test_scenarios.md`: scenario matrix, validation lens, change log
- NotebookLM source 구성: 프로젝트 기록과 skill 파일을 한 곳에 모아 질의 가능하게 만든 지식 베이스

Feedback harness가 답해야 하는 질문은 다음과 같다.

- 이전에 같은 문제가 있었는가?
- 어떤 artifact가 실제 실패 원인을 보여주는가?
- 실패가 product bug인지, harness race인지, stale binary 문제인지 구분 가능한가?
- 다음 LLM 작업이 어떤 증거를 읽고 시작해야 하는가?

## 4. GoStop 프로젝트 사례

### 4.1 프로젝트 맥락

GoStop 프로젝트는 SwiftUI 기반 iOS 고스톱 게임이며, 핵심 목표는 룰 정확성과 자동 검증 가능성이다.

주요 코드 경계는 다음과 같다.

| 영역 | 역할 |
| --- | --- |
| `GoStop/Core/` | 룰, 턴 진행, scoring, engine state |
| `GoStop/Views/` | SwiftUI 렌더링과 사용자 입력 연결 |
| `GoStopCLI/` | engine과 room transport를 외부에서 구동하는 CLI |
| `tests/test_agent/` | Python 기반 검증 agent와 scenario runner |
| `test_artifacts/` | 실패/성공 증거, replay, snapshot, summary |

이 경계가 generation harness의 핵심이다. LLM이 UI 수정 중 엔진 룰을 View에 넣거나, test agent 문제를 Core refactor로 해결하려 하면 harness가 이를 막아야 한다.

### 4.2 Skill 파일의 역할

이 프로젝트에서 반복 사용된 skill은 다음 역할을 나눠 갖는다.

원본 skill 파일의 문서화 복사본은 `docs/skills/` 아래에 정리돼 있고, 전체 인덱스는 `docs/skills/README.md`에서 확인할 수 있다. 원본 파일명이 모두 `SKILL.md`라 복사본은 `출처__디렉터리__skill-name.md` 형태의 고유 파일명을 사용한다.

| Skill | 역할 |
| --- | --- |
| `gostop-game-builder` | GoStop 게임 기능/룰 구현의 기본 작업 절차 |
| `gostop-ui-playability` | 카드 가시성, 애니메이션, simulator UI 검증 |
| `gostop-test-reliability` | scenario 실패, anomaly, flaky validation 수리 |
| `game-external-test-agent` | 외부 socket 기반 test agent와 artifact 수집 |
| `project_logger` | 요청별 작업 이력과 skill 사용 기록 |
| `basic-code-review` | 변경점 review와 리스크 정리 |

좋은 skill은 "언제 쓰는가"만 적지 않는다. 다음까지 포함해야 한다.

- 먼저 읽어야 할 파일
- 작업 순서
- layer invariant
- validation command
- artifact requirement
- failure handling
- done criteria

### 4.3 Test Agent와 Scenario Harness

GoStop의 validation harness는 여러 수준으로 나뉜다.

| 수준 | 예시 | 검증 내용 |
| --- | --- | --- |
| Single-player scenario | `tests/test_agent/test_scenarios.py` | 룰, scoring, 특수 상황 |
| Multiplayer fixture | `tests/test_agent/multiplayer_runner.py --mode fixture` | synthetic transcript 기반 계약 검증 |
| Multiplayer socket | `--mode socket --transport compare` | TCP fallback과 websocket parity |
| UI autoroute | `multi_test_scenario.py --mode ui` | 실제 simulator 2대의 product 화면 |
| CLI smoke | `scripts/run_multiplayer_cli_two_player_smoke.py` | room/bootstrap/heartbeat/gap ingress |

이 구조의 장점은 실패 위치를 좁힐 수 있다는 점이다.

- fixture가 실패하면 scenario contract나 validator 문제일 가능성이 크다.
- socket compare가 실패하면 transport 의미 차이일 가능성이 크다.
- UI만 실패하면 product render, coordinator sync, simulator bridge 문제일 가능성이 크다.

### 4.4 Artifact 체계

GoStop multiplayer artifact의 표준 구조는 다음과 같다.

```text
test_artifacts/multiplayer/<scenario_id>/<run_id>/
  manifest.json
  summary.md
  checklist_report.md
  anomaly_report.md
  logs/
    agent.log
    room.log
    engine.log
  timeline/
    commands.ndjson
    events.ndjson
    assertions.ndjson
  snapshots/
    player_a_initial.json
    player_b_initial.json
    latest_server.json
  replay/
    replay_manifest.json
    event_stream.ndjson
  ui/
    README.md
```

좋은 artifact는 "테스트 실패"만 말하지 않는다. 다음을 말해야 한다.

- 어떤 scenario였는가
- 마지막 성공 command는 무엇인가
- 어느 `eventId` 또는 `stateVersion`에서 drift가 시작됐는가
- expected와 observed의 차이가 무엇인가
- 재현 명령은 무엇인가
- 다음 수정자가 읽어야 할 로그와 snapshot은 어디인가

## 5. 잘 된 Harness를 판단하는 기준

### 5.1 생성 전 기준

좋은 generation harness는 LLM에게 다음을 강제한다.

- 작업 전 context 읽기
- 책임 경계 준수
- 기존 패턴 우선
- 변경 범위 최소화
- validation 계획 수립
- project log 기록

반대로 약한 harness는 다음처럼 동작한다.

- "잘 만들어줘" 같은 추상 지시만 있음
- LLM이 어디를 고칠지 매번 새로 추측함
- 실패 시 어떤 evidence를 남겨야 하는지 없음
- 같은 실수를 다음 turn에서 반복함

### 5.2 실행 검증 기준

좋은 validation harness는 다음을 갖춘다.

- scenario registry
- suite 정의
- deterministic seed 또는 deterministic fixture
- bridge client
- validator
- artifact writer
- replay 또는 raw event stream
- PASS criteria
- failure classification

GoStop에서는 `final-validation` suite가 좋은 예다. `MP-001`, `MP-002`, `MP-004`, `MP-007`, `MP-008`, `MP-013`, `MP-014`를 고정하고, 각 scenario별 required artifact를 명시한다.

### 5.3 feedback 기준

좋은 feedback harness는 다음을 남긴다.

- request별 사용 skill
- 수정 파일
- 실행한 검증
- 실패 원인
- 최종 outcome
- 남은 risk
- 다음 action item

이 정보가 있어야 새 LLM 세션이 "처음부터 다시 추측"하지 않고 이전 판단 위에서 이어갈 수 있다.

## 6. 실습 자료

### 실습 1: Skill 파일 평가하기

아래 질문으로 `SKILL.md` 하나를 평가한다.

1. 이 skill은 언제 사용해야 하는지 명확한가?
2. 먼저 읽어야 할 프로젝트 파일이 적혀 있는가?
3. 구현 위치와 금지 위치를 구분하는가?
4. validation command가 구체적인가?
5. 실패 시 남길 artifact가 명시돼 있는가?
6. 완료 기준이 실행 결과로 판정 가능한가?

### 실습 2: Scenario 하나를 Harness로 바꾸기

예시 요구:

```text
멀티플레이에서 중복 actionId가 두 번째 상태 변경을 만들면 안 된다.
```

Harness로 바꾸면 다음처럼 된다.

```text
Scenario ID: MP-004
Precondition:
  - live match bootstrap 완료
Action:
  - legal command with actionId=act_dup_001
  - exact duplicate resend
  - conflicting duplicate resend
Expected:
  - exact duplicate => exactReplay
  - conflicting duplicate => actionIdConflict
  - no second stateVersion bump
Artifacts:
  - duplicate_probe.json
  - timeline/commands.ndjson
  - timeline/events.ndjson
  - transport_parity.json
```

### 실습 3: 실패를 Repair Input으로 만들기

나쁜 실패 보고:

```text
MP-017 failed.
```

좋은 실패 보고:

```text
Scenario: MP-017
Expected:
  - host captured total이 authoritative handoff 전에 guest rendered captured zone에도 반영
Observed:
  - expectedCapturedTotal=4
  - hostRendered=4
  - guestRendered=0
First bad transition:
  - host playCard 직후 authoritative preview는 capture delta를 보였지만 guest UI handoff는 아직 이전 state
Classification:
  - probe 기준이 authoritative preview를 너무 이르게 신뢰한 false fail 가능성
Artifacts:
  - timeline.jsonl
  - host_failure.png
  - guest_failure.png
  - debug_log_multiplayer.ndjson
Repair:
  - capture probe를 authoritative preview 기준이 아니라 host/guest UI currentPlayerId handoff 기준으로 보정
```

이 형태가 되어야 LLM이 다음 turn에서 정확히 고칠 수 있다.

## 7. 새 프로젝트에 적용할 최소 구조

새 프로젝트에서 LLM coding harness를 만들 때 최소 파일 구조는 다음과 같다.

```text
AGENTS.md
skills/
  domain-builder/SKILL.md
  ui-playability/SKILL.md
  test-reliability/SKILL.md
docs/
  architecture.md
  rtm.md
  change_contract_template.md
  gate_checklist.md
  e2e_evidence_log.md
  loopback_log.md
  orchestrator_board.md
  orchestrator_prompt_template.md
  scenario_matrix.md
  validation_runbook.md
  runbooks/
    halo_operating_flow.md
    orchestrator_agent_flow.md
tests/
  scenario_registry.py
  runner.py
  validators.py
  artifacts.py
  bridge_client.py
  fixtures.py
  replay.py
test_artifacts/
  README.md
project_progress.md
```

각 파일의 역할은 다음과 같다.

| 파일 | 역할 |
| --- | --- |
| `AGENTS.md` | 전체 project contract와 LLM 행동 규칙 |
| `SKILL.md` | 작업 유형별 실행 절차 |
| `architecture.md` | 코드 책임 경계 |
| `rtm.md` | 요구사항에서 contract, 구현, 검증, evidence까지 추적 |
| `change_contract_template.md` | 구현 전 pre-state, trigger, post-state, evidence를 고정 |
| `gate_checklist.md` | 구현/계약 변경/E2E 생략/완료 승인 기록 |
| `e2e_evidence_log.md` | PASS를 artifact 경로와 함께 기록 |
| `loopback_log.md` | 실패 시 어느 phase/layer로 돌아갔는지 기록 |
| `orchestrator_board.md` | orchestrator의 현재 queue, decision, handoff 상태 |
| `orchestrator_prompt_template.md` | Codex 세션을 HALO orchestrator agent로 시작하는 prompt |
| `runbooks/halo_operating_flow.md` | RTM -> Contract Gate -> Implementation -> E2E Evidence -> Loopback Log 운영 규칙 |
| `runbooks/orchestrator_agent_flow.md` | request triage, owner lane 선택, delegation, evidence review, loopback decision 절차 |
| `scenario_matrix.md` | 무엇을 검증할지 |
| `validation_runbook.md` | 어떻게 실행할지 |
| `runner.py` | scenario 실행 |
| `validators.py` | expected/observed 판정 |
| `artifacts.py` | evidence 저장 |
| `project_progress.md` | feedback memory |

## 8. Checklist

### Generation Harness Checklist

- [ ] 작업 유형별 skill이 있다
- [ ] skill마다 trigger condition이 명확하다
- [ ] 먼저 읽을 파일이 지정돼 있다
- [ ] 책임 경계가 적혀 있다
- [ ] 금지 패턴이 적혀 있다
- [ ] RTM row가 생성되어 있다
- [ ] change contract가 pre-state / trigger / post-state / evidence를 정의한다
- [ ] gate approval 또는 waiver가 기록되어 있다
- [ ] validation command가 있다
- [ ] done criteria가 있다

### Validation Harness Checklist

- [ ] scenario registry가 있다
- [ ] suite가 있다
- [ ] deterministic fixture 또는 seed가 있다
- [ ] bridge/client가 있다
- [ ] validator가 expected/observed를 비교한다
- [ ] 실패 시 anomaly report가 남는다
- [ ] replay나 raw event stream이 남는다
- [ ] PASS criteria가 문서화돼 있다
- [ ] real E2E evidence가 필요할 때 artifact path로 남는다
- [ ] E2E 생략 시 waiver와 residual risk가 기록된다

### Feedback Harness Checklist

- [ ] 요청별 로그가 남는다
- [ ] 사용 skill이 기록된다
- [ ] 수정 파일이 기록된다
- [ ] 실행한 검증이 기록된다
- [ ] 실패 원인과 outcome이 기록된다
- [ ] 다음 action item이 남는다
- [ ] NotebookLM 또는 유사 도구로 과거 context를 검색할 수 있다
- [ ] 실패한 run은 loopback log에 first bad transition과 return layer가 남는다
- [ ] RTM status가 PASS / FAIL / Loopback / Deferred 중 하나로 갱신된다

## 9. 교육 진행안

### 60분 버전

1. 10분: LLM coding harness 개념
2. 10분: generation / validation / feedback harness 구분
3. 15분: GoStop 프로젝트 파일 구조 walkthrough
4. 15분: MP-017 failure-to-repair 사례 분석
5. 10분: 새 프로젝트용 checklist 작성

### 120분 버전

1. 15분: 개념 설명
2. 20분: `AGENTS.md`와 skill 파일 평가
3. 20분: scenario matrix 읽기
4. 25분: artifact 기반 failure analysis 실습
5. 25분: 새 scenario를 harness로 설계
6. 15분: 팀별 발표와 개선안 정리

## 10. 핵심 메시지

좋은 LLM coding harness는 LLM을 더 자유롭게 만드는 장치가 아니다. 반대로 LLM이 불필요하게 추측하지 않게 만드는 장치다.

핵심은 세 가지다.

1. 생성 전에는 context와 책임 경계를 고정한다.
2. 생성 후에는 실행 가능한 검증으로 판정한다.
3. 실패 후에는 artifact와 progress log를 다음 생성 입력으로 되돌린다.

이 세 가지가 연결될 때, LLM coding은 단발성 prompt가 아니라 재현 가능한 engineering loop가 된다.

GoStop harness의 다음 운영 단계는 이 루프를 더 명시적으로 강제하는 것이다.

```text
RTM -> Contract Gate -> Implementation -> E2E Evidence -> Loopback Log
```

이 흐름에서 `RTM`은 요구사항의 단일 추적표이고, `Contract Gate`는 구현 전 승인 지점이며, `E2E Evidence`는 거짓 성공을 막는 artifact index다. `Loopback Log`는 실패 시 같은 코드를 계속 고치는 대신 책임 있는 phase나 layer로 되돌아가기 위한 구조적 복구 기록이다.

멀티 에이전트나 cross-layer 변경에서는 이 흐름 앞에 `Orchestrator Agent`를 둔다.

```text
Orchestrator
  -> RTM
  -> Contract Gate
  -> Delegation
  -> Implementation
  -> E2E Evidence
  -> Loopback Log
```

Orchestrator는 직접 코드를 많이 고치는 agent가 아니라, 요청을 위험도와 owner lane으로 분류하고 bounded specialist prompt를 생성하며, evidence가 contract를 만족하는지 판정하는 agent다.
