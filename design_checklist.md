# GoStop Animation/Debug Design Checklist

이 문서는 `table -> captured` 같은 카드 이동 이슈를 설계 단계에서 미리 차단하기 위한 체크리스트입니다.
개발 시작 전, 구현 중, 릴리스 전 게이트로 나눠서 사용합니다.

## 1) 설계 시작 전 (Architecture Gate)
- [ ] `전환(route) 1개 = 애니메이션 엔진 1개` 원칙을 문서화했는가?
- [ ] 각 route(`hand->table`, `table->captured`, `captured->captured` 등)별로 담당 렌더 방식(overlay vs matchedGeometry)을 고정했는가?
- [ ] route 결정 로직이 View 분기 여러 곳에 흩어지지 않고 단일 정책으로 관리되는가?
- [ ] route별 종료 조건(cleanup 시점, hidden card 복구 시점)을 명시했는가?

## 2) 상태 머신 (State Machine Gate)
- [ ] 이동 상태가 `idle -> start -> inFlight -> end -> cleanup`으로 명시되어 있는가?
- [ ] 각 이동에 고유 `moveId`가 부여되는가?
- [ ] 같은 카드/같은 moveId에 대해 중복 start가 발생하면 차단되는가?
- [ ] cleanup 누락 시 타임아웃/강제복구 경로가 있는가?

## 3) 좌표/앵커 계약 (Anchor Contract Gate)
- [ ] source/target 좌표가 같은 coordinate space(`GameSpace`)에서 계산되는가?
- [ ] target anchor 우선순위가 정의되어 있는가? (`CARD_HIT > REAL_HIT > SURROGATE > FALLBACK`)
- [ ] fallback은 정상 경로가 아니라 예외 경로로 취급되는가?
- [ ] fallback 발생 횟수/지속 프레임 제한이 있는가?
- [ ] ownerId 변경(재시작/조건세팅) 시 stale center 정리 정책이 있는가?

## 4) Bridge/동기화 (State Consistency Gate)
- [ ] `get_state`는 mutation과 경합 시 stale snapshot을 보내지 않는가?
- [ ] snapshot 생성 중 mutation이 들어오면 dirty 처리 후 재스냅샷하는가?
- [ ] 고빈도 polling 시 응답 coalescing/backpressure가 동작하는가?
- [ ] action 응답과 state 응답 순서가 테스트에서 재현 가능하게 정의되어 있는가?

## 5) Debug/관측성 (Observability Gate)
- [ ] 표준 로그 키를 고정했는가? (`moveId, route, p, src, tgt, cur, anchorQuality`)
- [ ] 문제 route에 대해 프레임별 로그 on/off 토글이 있는가?
- [ ] 디버그 화면에서 최근 로그 + 누적 이력을 둘 다 확인할 수 있는가?
- [ ] 이력 전체 복사(clipboard) 또는 파일 내보내기가 가능한가?

## 6) UI/레이어링 (Visual Safety Gate)
- [ ] overlay, HUD, panel 간 zIndex 우선순위가 route별로 정의되어 있는가?
- [ ] 버튼/디버그 UI가 다른 레이어에 가려지지 않는가? (hit-test 포함)
- [ ] source/target hide opacity 정책이 route별로 명시되어 있는가?
- [ ] 애니메이션 중 카드가 영역 밖으로 보일 수 있는 경우 의도된 연출인지 검토했는가?

## 7) 테스트 시나리오 (Regression Gate)
- [ ] 최소 재현 시나리오 1개를 고정했는가? (예: `--mode socket 65`)
- [ ] slow 모드에서 재현/비재현을 모두 검증하는가?
- [ ] route별 핵심 assertion이 있는가?
- [ ] 실패 시 artifact(로그/스크린샷/state dump) 저장 위치가 표준화되어 있는가?

## 8) 릴리스 게이트 (Release Gate)
- [ ] fallback 관련 warning이 허용 기준 이하인가?
- [ ] scenario 회귀 테스트가 모두 통과했는가?
- [ ] debug 옵션 OFF 시 성능/시각 회귀가 없는가?
- [ ] 최종 수정 내역과 재현 방법이 문서화되어 있는가?

---

## Route 추가 시 템플릿
새 route를 추가할 때 아래를 반드시 채웁니다.

- Route 이름:
- Source Zone:
- Target Zone:
- 애니메이션 엔진(overlay/matchedGeometry):
- Anchor 우선순위:
- Fallback 허용 조건:
- cleanup 트리거:
- 필요 로그 키:
- 회귀 시나리오 ID:
- 실패 시 수집 artifact:
