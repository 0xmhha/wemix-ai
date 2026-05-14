# go-wemix 코드 리뷰 상세 가이드

> 이 문서는 스킬·커맨드 프롬프트에서 분리된 상세 참조 자료입니다.
> 필요 시 `Read .claude/docs/REVIEW_GUIDE.md`로 로드합니다.

## Wemix 고유 코드 맵

geth 원본에 없는 Wemix 전용 코드.

### 핵심 패키지 (Wemix 전용)

| 패키지 | 역할 | 주요 파일 |
|--------|------|-----------|
| `wemix/` | wemixAdmin: 거버넌스 조회, etcd 토큰, 보상 분배 | `admin.go` (43KB), `etcdutil.go` (28KB), `sync.go`, `miner_limit.go`, `spinlock.go` |
| `wemix/api/` | WemixMinerStatus 이벤트 API | `api.go` |
| `wemix/bind/` | abigen 산출 거버넌스 Go 바인딩 (수동 편집 금지) | `gen_*_abi.go`, `const.go`, `structs.go` |
| `wemix/metclient/` | 트랜잭션 헬퍼 | `tx_params.go`, `util.go` |
| `wemix/miner/` | wemix 보상 분배를 표준 miner에 주입 | `miner.go` |
| `cmd/gwemix/` | Wemix 메인 클라이언트 | `main.go`, `wemixcmd.go`, `governancedeploy.go`, ... 12개 |
| `wemix/governance-contract/` | Solidity 거버넌스 컨트랙트 (빌드 비참여, 런타임 ABI는 `wemix/bind/`에 임베드) | `Registry.sol`, `GovImp.sol`, `StakingImp.sol`, `storage/EnvStorageImp.sol`, `BallotStorage.sol`, `NCPExitImp.sol`, ... |

### 기존 패키지 내 Wemix 고유 파일

| 파일 | 역할 |
|------|------|
| `core/wemix_genesis.go` | Wemix Mainnet/Testnet 제네시스 JSON (alloc + chainConfig) |
| `core/types/feedelegate_dynamic_fee_tx.go` | Fee Delegation tx (TxType `0x16`) |
| `eth/protocols/eth/wemix_handlers.go` | Wemix 전용 eth 프로토콜 메시지 핸들러 |
| `params/wemix_config.go` | Wemix 부트노드 + `WemixGenesisFile` 전역 |
| `params/config.go` *(부분)* | `Pangyo/Applepie/Brioche/Croissant` 하드포크, `BriocheConfig` |
| `ethdb/rocksdb/*.go` | RocksDB 백엔드 (Linux 빌드만) |

## 질문 유형별 탐색 가이드

### 유형 1: 특정 함수/타입 질문

1. `Grep`으로 함수/타입 정의 위치를 찾는다 (`func.*<name>\b` 또는 `type <Name>\b`)
2. `Read`로 해당 함수/타입의 코드를 읽는다
3. 함수 시그니처, 주석, 핵심 로직을 분석하여 답한다

### 유형 2: 호출 관계 / 흐름 질문

1. `Grep`으로 함수명이 호출되는 위치를 검색한다
2. 호출자 함수의 코드를 `Read`로 확인한다
3. 필요 시 호출자의 호출자도 추적한다 (최대 3홉)
4. 흐름을 순서대로 정리하여 답한다

### 유형 3: 영향도 / 삭제 안전성 질문

1. `Grep`으로 해당 심볼의 모든 참조를 찾는다
2. 참조가 있는 패키지 목록을 정리한다
3. 각 참조의 맥락(호출, 타입 사용, import)을 분류한다
4. 영향 범위와 위험도를 판정하여 답한다

### 유형 4: 합의 / 마이닝 토큰 질문

Wemix 합의는 **Clique 변형 PoA + etcd 마이닝 토큰**이다.

```
miner.Start()
   │
   ├─ clique: 라운드 로빈 서명자 선출 → 자기 차례인지 검증
   │
   └─ wemixminer.AcquireMiningTokenFunc (wemix/sync.go) 호출
        │
        ├─ wemix/sync.go: loadMiningToken()
        │    → etcd에서 mining-token 키 조회
        │
        ├─ wemix/etcdutil.go: acquireTokenSync(ctx, height, hash, parentHash, ttl)
        │    → CAS로 토큰 획득 (다른 노드가 이미 잡았으면 실패)
        │
        ├─ 블록 빌드 파라미터 조회
        │    wemix/admin.go: getBlockBuildParameters(height)
        │      → EnvStorageImp.{GetBlockCreationTime, GetGasLimitAndBaseFee, GetMaxBaseFee, ...}
        │
        ├─ 블록 시그니처
        │    wemix/admin.go: signBlock(height, hash)
        │
        └─ 보상 분배
             wemix/admin.go: distributeRewards(height, rp, blockReward, fees)
              → 4-way 분배: BlockProducer / StakingReward / Ecosystem / Maintenance
              → Brioche 이후 BriocheConfig.GetBriocheBlockReward 사용
```

주요 파일:
- `wemix/admin.go` — wemixAdmin 본체. `distributeRewards`, `signBlock`, `getBlockBuildParameters`, `getWemixNodes`
- `wemix/sync.go` — `loadMiningToken`, `findConsensusBlock`
- `wemix/etcdutil.go` — etcd embedded 운영, 토큰 acquire/release
- `wemix/spinlock.go` — 토큰 임계 영역 보호
- `wemix/miner/miner.go` — 표준 miner ↔ wemix 함수 변수 IoC
- `consensus/clique/clique.go` — PoA 합의 본체 (Wemix는 위에 admin 레이어)

### 유형 5: 거버넌스 컨트랙트 질문

```
wemix/bind/ 구조:
  const.go                       — 도메인/컨트랙트 이름 상수
  structs.go                     — 공통 구조체
  gen_registry_abi.go            — Registry 바인딩
  gen_gov_abi.go                 — Gov / GovImp 바인딩
  gen_staking_abi.go             — Staking / StakingImp 바인딩
  gen_ballotStorage_abi.go       — BallotStorage 바인딩
  gen_envStorage_abi.go          — EnvStorage / EnvStorageImp 바인딩
  gen_ncpExit_abi.go             — NCPExit / NCPExitImp 바인딩

wemix/governance-contract/contracts/ (Solidity 소스):
  Registry.sol                   — 도메인↔주소 매핑
  Gov.sol / GovImp.sol           — 거버넌스 (UUPS)
  Staking.sol / StakingImp.sol   — 스테이킹 (UUPS)
  BallotStorage.sol              — 투표 영구 저장
  storage/EnvStorageImp.sol      — 체인 파라미터 (UUPS)
  NCPExit.sol / NCPExitImp.sol   — NCP 퇴출 (UUPS, Pangyo 이후)
```

상세 흐름: `.claude/docs/GOVERNANCE_FLOW.md`

### 유형 6: 트랜잭션 / EVM 질문

- Fee Delegation: `core/types/feedelegate_dynamic_fee_tx.go` → `core/types/transaction_signing.go` → `core/state_transition.go`
- EVM 실행: `core/vm/evm.go` → `core/vm/interpreter.go` → `core/vm/instructions.go`
- 트랜잭션 처리: `core/state_processor.go` → `core/state_transition.go`
- 트랜잭션 풀: `core/tx_pool.go` (Applepie 게이팅 위치)

### 유형 7: 네트워크 / P2P 질문

- Wemix 핸들러: `eth/protocols/eth/wemix_handlers.go`
- 표준 eth 프로토콜: `eth/handler.go` → `eth/protocols/eth/handler.go`
- 피어 관리: `p2p/server.go` → `p2p/peer.go`
- 노드 발견: `p2p/discover/`
- 부트노드: `params/wemix_config.go` (`WemixMainnetBootnodes`, `WemixTestnetBootnodes`)

### 유형 8: 제네시스 / 체인 설정 질문

- 제네시스: `core/wemix_genesis.go` → `core/genesis.go`
- 체인 설정: `params/config.go` + `params/wemix_config.go`
- 네트워크 파라미터: `params/network_params.go`
- 거버넌스 배포: `cmd/gwemix/governancedeploy.go`
- 부트노드: `params/wemix_config.go`

### 유형 9: etcd / 멤버십 운영 질문

- 임베디드 etcd 설정: `wemix/etcdutil.go` (`etcdNewConfig`, `etcdIsRunning`, `etcdMemberExists`, `etcdFixCluster`)
- 마이닝 토큰: `acquireToken`, `acquireTokenSync`, `releaseTokenSync`, `renew`
- 멤버십 동기화: `wemix/sync.go: findConsensusBlock`, `wemix/admin.go: getWemixNodes`
- 락 프리미티브: `wemix/spinlock.go`

> **`wemix/etcdutil.go.new`는 빌드 비참여 보관 파일.** 운영 코드는 `etcdutil.go`임에 주의.

### 유형 10: 보상 분배 / 가스 정책 질문

- 보상 분배: `wemix/admin.go: distributeRewards`, `rewardParameters` 구조체
- Brioche 곡선: `params/config.go: BriocheConfig.GetBriocheBlockReward`
- EnvStorage getter:
  - `GetBlockRewardAmount`, `GetBlockRewardDistributionMethod`
  - `GetBlockCreationTime`, `GetBlocksPer`, `GetMaxIdleBlockInterval`
  - `GetMaxPriorityFeePerGas`, `GetMaxBaseFee`, `GetGasLimitAndBaseFee`

### 유형 11: 패키지 구조 / 아키텍처 질문

1. `.claude/docs/BUILD_SOURCE_FILES.md`의 Section 2 (패키지 목록)와 Section 4 (카테고리별 집계)를 읽는다
2. 해당 패키지의 주요 파일을 `Read`로 확인한다
3. 패키지 간 관계는 `Grep`으로 import 관계를 추적한다

### 유형 12: 코드 수정 / 기능 추가 요청

1. 유사한 기존 구현을 먼저 찾는다 (패턴 참고)
2. 수정 대상 파일과 영향 범위를 파악한다
3. 코드 수정 전에 변경 계획을 사용자에게 제시한다
4. 수정 후 `make gwemix && make lint && make test-short`로 검증을 안내한다

## 리뷰 관점 (Wemix 특화)

| 관점 | 설명 | 심각도 |
|------|------|--------|
| 합의 안전성 | 마이닝 토큰 누락·이중 발급, etcd 락 race | critical |
| 거버넌스 일관성 | Registry 우회 직접 주소 사용, UUPS 깨짐 | critical |
| 하드포크 게이팅 | `IsApplepie/IsBrioche/IsPangyo/IsCroissant` 누락 분기 | critical |
| 보상 분배 정확성 | %·반올림 오류, fees 이중 계산 | critical |
| 보안 | Fee Delegation 서명 검증, 입력 검증, RPC 권한 | critical |
| 성능 | EnvStorage 호출 캐싱 누락, 매 블록 N+1 | warning |
| 동시성 | wemixAdmin 필드 race, spinlock 누락 | critical |
| 스타일 | 네이밍, 가독성, geth 코드 컨벤션 일관성 | suggestion |
| 테스트 | rewards_test, simulated backend 커버리지 | warning |

## 응답 형식

```
## 분석 결과

### 대상
- 파일: `wemix/admin.go:794`
- 함수: `distributeRewards(height *big.Int, rp *rewardParameters, blockReward *big.Int, fees *big.Int)`

### 동작
[함수의 핵심 동작을 단계별로 설명]

### 호출 관계
[호출자 → 대상 → 피호출자 흐름]

### 영향 범위 (해당 시)
[변경/삭제 시 영향받는 코드 목록]

### 관련 코드
[참고해야 할 다른 파일/함수 목록]
```

## 추가 참조

- 빌드 파일 목록: `.claude/docs/BUILD_SOURCE_FILES.md`
- 개발 가이드 (하드포크/Fee Delegation/Brioche/etcd 등): `.claude/docs/CLAUDE_DEV_GUIDE.md`
- 거버넌스 컨트랙트 흐름: `.claude/docs/GOVERNANCE_FLOW.md`
