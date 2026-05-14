---
description: "go-wemix 코드 분석 및 질의응답. 코드 구조, 동작 흐름, 영향도 분석, 수정 제안 등을 수행한다."
---

# go-wemix 코드 리뷰

## 규칙
1. 빌드 범위 내 코드만 분석 대상: `.claude/docs/BUILD_SOURCE_FILES.md` 참조
2. Wemix 고유 코드와 go-ethereum 원본 코드를 구분할 것
3. 추측 금지 — Read/Grep으로 실제 코드를 확인 후 답변
4. 최소한의 도구 호출로 답변 (목표: 5회 이하, 동일 패턴 반복 Grep 금지)
5. 충분한 컨텍스트 확보 시 즉시 결론으로 이동

## Wemix 핵심 경로
- 합의/마이닝 토큰: `wemix/admin.go`, `wemix/sync.go`, `wemix/etcdutil.go`, `wemix/spinlock.go`
- 거버넌스 Go 바인딩: `wemix/bind/gen_*_abi.go` (수동 편집 금지)
- 거버넌스 Solidity: `wemix/governance-contract/contracts/`
- 메인 클라이언트: `cmd/gwemix/`
- 고유 파일:
  - `core/wemix_genesis.go` (제네시스)
  - `core/types/feedelegate_dynamic_fee_tx.go` (Fee Delegation tx)
  - `eth/protocols/eth/wemix_handlers.go` (Wemix 메시지 핸들러)
  - `params/wemix_config.go`, `params/config.go` *(부분: Pangyo/Applepie/Brioche/Croissant)*

## 상세 참조 (필요 시에만 Read로 로드)
- 빌드 파일 목록: `.claude/docs/BUILD_SOURCE_FILES.md`
- 개발 가이드 (하드포크/Fee Delegation/Brioche/etcd 등): `.claude/docs/CLAUDE_DEV_GUIDE.md`
- 거버넌스 컨트랙트 흐름: `.claude/docs/GOVERNANCE_FLOW.md`
- 질문 유형별 탐색 가이드, 합의 흐름, 응답 형식: `.claude/docs/REVIEW_GUIDE.md`

$ARGUMENTS
