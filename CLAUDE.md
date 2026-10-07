# go-wemix

go-ethereum(geth) 포크 기반 WEMIX 블록체인 클라이언트 — Clique 변형 PoA + etcd 마이닝 토큰 + Solidity 거버넌스 컨트랙트로 동작하는 메인넷 클라이언트.

## 빌드

```bash
make gwemix             # 메인 클라이언트 빌드 → build/bin/gwemix
make gwemix.tar.gz      # 배포 tarball (gwemix + logrot + conf)
make gwemix-linux       # Docker로 Linux 정적 빌드 (rocksdb 포함)
make logrot             # 로그 로테이션 도구
make geth               # 표준 geth 바이너리
make test               # 전체 테스트
make test-short         # 빠른 테스트 (-short)
make lint               # golangci-lint 실행
make devtools           # 코드 생성 도구 설치 (stringer, gencodec, protoc, abigen, solc)
```

## 프로젝트 구조

- 빌드 참여 파일 + 테스트 코드 목록: `.claude/docs/BUILD_SOURCE_FILES.md` 참조
  (`gwemix` = 120 패키지 / 630 파일, 테스트 302개 / `logrot` = 1 파일 wrapper)
- 메인 클라이언트: `cmd/gwemix/` — `cmd/geth`를 가리키는 심볼릭 링크다. git log·diff에는 `cmd/geth/...` 경로로 찍힌다
- 로그 로테이션: `cmd/logrot/` — 진입점만 있고 본체는 외부 모듈 `github.com/charlanxcc/logrot`
- 합의/마이닝 토큰: `wemix/` (admin.go, etcdutil.go, sync.go, miner_limit.go, spinlock.go)
- 거버넌스 Go 바인딩: `wemix/bind/gen_*_abi.go` *(수동 편집 금지 — abigen 재생성)*
- 거버넌스 Solidity: `wemix/governance-contract/contracts/`

## go-wemix 고유 코드 (geth 원본에 없는 것)

핵심 패키지:
- `wemix/` — wemixAdmin: 거버넌스 조회, etcd 마이닝 토큰, 보상 분배
- `wemix/api/` — WemixMinerStatus 이벤트 API
- `wemix/bind/` — abigen 산출 거버넌스 Go 바인딩
- `wemix/metclient/` — 트랜잭션 헬퍼
- `wemix/miner/` — wemix 보상 분배를 표준 miner에 주입
- `wemix/governance-contract/` — Solidity 거버넌스 컨트랙트 (Registry, GovImp, StakingImp, EnvStorageImp, BallotStorage, NCPExitImp)
- `cmd/gwemix/` — Wemix 메인 클라이언트

기존 패키지 내 고유 파일:
- `core/wemix_genesis.go` — Mainnet/Testnet 제네시스 JSON (alloc + chainConfig)
- `core/types/feedelegate_dynamic_fee_tx.go` — Fee Delegation tx (TxType `0x16`)
- `eth/protocols/eth/wemix_handlers.go` — Wemix 전용 eth 프로토콜 메시지 핸들러
- `params/wemix_config.go` — Wemix 부트노드, `WemixGenesisFile` 전역
- `params/config.go` *(부분)* — `Pangyo/Applepie/Brioche/Croissant` 하드포크, `BriocheConfig`
- `ethdb/rocksdb/*.go` — RocksDB 백엔드 (Linux 빌드만, `USE_ROCKSDB=YES`)

## 하드포크 히스토리

Pangyo → Applepie → **Brioche** (블록 리워드 halving) → **Croissant** (WBFT 합의 전환 — 별도 빌드)

- Pangyo: 초기 PoA 활성화 — Mainnet 0 / Testnet 10,000,000
- Applepie: Fee Delegation 트랜잭션 활성화 — Mainnet 20,476,911 / Testnet 26,240,268
- Brioche: 블록 리워드 halving 곡선 (`BriocheBlock`, `BriocheConfig`) — Mainnet 53,525,500 / Testnet 59,414,700
- Croissant: WBFT 합의 전환 (go-wbft에서 처리) — **활성 블록 미설정(nil)**, 필드·`IsCroissant`·포크 순서 검사만 준비됨

## 핵심 용어

| 용어 | 의미 |
|------|------|
| wemixAdmin | `wemix/admin.go`의 거버넌스/마이닝 토큰 통합 객체 |
| 마이닝 토큰 | etcd 락 기반 리더 선출 — 매 블록 1명의 마이너만 보유 |
| Registry | 거버넌스 도메인↔주소 매핑 (Ownable, 비-UUPS) |
| Gov / GovImp | 거버넌스 프록시(ERC1967) / 구현(UUPSUpgradeable) |
| Staking / StakingImp | 스테이킹 컨트랙트 (락업/언락업) |
| EnvStorageImp | 체인 파라미터(블록주기, 보상비율 등) — UUPS |
| BallotStorage | 거버넌스 투표 저장소 |
| NCPExit / NCPExitImp | NCP(Network Council Point) 탈퇴 컨트랙트 |
| Fee Delegation | 가스비를 별도 서명자(FeePayer)가 지불하는 tx (TxType 0x16) |
| Brioche halving | 블록 리워드 점진적 halving 곡선 |

## 보상 분배 (EnvStorage 4-way)

블록 리워드는 EnvStorage 설정에 따라 4-way로 분배된다:

| 대상 | 역할 |
|------|------|
| BlockProducer | 블록 생산자 |
| StakingReward | 스테이커 풀 |
| Ecosystem | 생태계 펀드 |
| Maintenance | 유지보수 펀드 |

## 코드 분석 시 주의사항

- `.claude/docs/BUILD_SOURCE_FILES.md`에 나열된 파일만 실제 바이너리에 포함됨
- go-wemix 고유 코드와 geth 원본 코드를 구분할 것 — geth 코드 수정은 upstream 호환성 영향
- 거버넌스 컨트랙트 주소는 항상 `Registry.GetContractAddress(domain)` 경유 — 하드코딩 금지
- `wemix/bind/gen_*_abi.go`는 abigen 산출물 — 수동 편집 금지, Solidity 변경 후 재생성
- `core/wemix_genesis.go`는 운영 네트워크 제네시스 — 변경 시 라이브 상태에 영향, 신중히 검토
- 하드포크 추가/변경 시 `params/config.go`의 4종(필드/Is*/CheckConfigForkOrder/CheckCompatible) 모두 갱신

## 보안 불변식 (되돌리지 말 것)

이미 취약점으로 확인되어 방어가 들어간 지점이다. 상세는 `.claude/docs/CLAUDE_DEV_GUIDE.md` §15,
`.claude/docs/GOVERNANCE_FLOW.md` §6.

| 영역 | 불변식 |
|------|--------|
| StatusEx 신뢰 경계 | `NodeName`은 `NodeNameForPeerID(peer.ID())` 거버넌스 조회로만 결정. 페이로드 값 신뢰 시 정족수 위조 가능 |
| RLP nil 가드 | `LatestBlockHeight`/`LatestBlockTd`/`RttMs`의 nil 검사는 **핸들러 경계**에서. 호출처별 가드로 되돌리지 말 것 |
| wemixWorkKey | 기록 전 도달성 / 해시·높이 정합 / 높이 역행 3중 검증 + `etcdResetWork` CAS. 토큰 TTL 갱신(구 `renew()`, v0.10.15에서 제거)을 다시 넣더라도 CAS 직전에 호출 금지 |
| 마이닝 토큰 획득 | `worker.commitWork`는 `isRunning()`이 거짓이면 `AcquireMiningToken`을 호출하지 않는다. 블록 빌드와 토큰 반환이 `isRunning()` 뒤에 있어서, 멈춘 워커가 토큰을 잡으면 Till 만료까지 클러스터 전체가 멈춘다 |
| 블록 크기 상한 | RLP 인코딩 블록은 `params.MaxBlockSize`(8 MiB, EIP-7934) 이하. 수신은 `ValidateBody`가 `ErrBlockOversized`로 거부하고, 생성은 `txFitsSize`가 1,000,000 바이트 여유를 두고 tx 패킹을 멈춘다. 하드포크 게이트 없이 항상 적용된다 |
| 블록 타임스탬프 하한 | `worker.timeIt`의 하한은 `parent.Time()`이다. `parent.Number()`와 비교하던 버그가 v0.10.15에서 고쳐졌으니 되돌리지 말 것 |
| etcd 자동 가입 | `etcdAutoJoin`은 `gap == 0`(피어 없음)이면 `ErrNotFound`로 일찍 반환한다. 이 가드가 없으면 `ct/tt`에서 0 나눗셈 panic이 나고, recover 없는 고루틴이라 프로세스가 죽는다 |
| FeePayer 검증 | `types.RecoverFeePayer` 단일 진입점. tx **타입** 기준 분기(FeePayer nil 여부 아님). RPC 레이어 중복 검증 부활 금지 |
| AccessList 복사 | `SetSenderTx`는 `make` 후 `copy` — 사전 할당 없으면 전부 유실 |
| 거버넌스 임의 실행 | `addProposalToExecute` / `BallotTypes.Execute` / `createBallotForExecute`는 의도적 제거. 복원 금지 |
| mock 픽스처 | `wemix/governance-contract/contracts/mock/*.sol`은 버그 보존용 red→green 픽스처 — 수정 금지 |

관련 회귀 테스트: `wemix/sync_regression_test.go`, `wemix/etcd_test.go`, `wemix/api/api_test.go`,
`core/types/transaction_test.go`, `core/block_validator_test.go`, `miner/worker_test.go`,
`wemix/governance-contract/test/gov_test.go`

## 코드 컨벤션

- Go 코드: geth 컨벤션 준수 (gofmt, goimports, errcheck)
- Solidity: solc **0.8.14 고정** (`wemix/governance-contract/compiler.go`)
- UUPS 호환성: 스토리지 슬롯 레이아웃 보존, 새 변수는 항상 맨 뒤 추가

## Claude Code 도구

- 코드 리뷰: `/wemix-review-code [질문]`
- PR 리뷰 (서브 에이전트): `pr-reviewer` (자동 환경 감지 + 빌드/린트/테스트 실행)
- 거버넌스 워크플로우 스킬: `wemix-governance-workflow` — Solidity → abigen → 배포까지 레이어별 절차

## 상세 참조

- 개발 가이드 (아키텍처/하드포크/Fee Delegation/Brioche/etcd): `.claude/docs/CLAUDE_DEV_GUIDE.md`
- 거버넌스 컨트랙트 흐름: `.claude/docs/GOVERNANCE_FLOW.md`
- 리뷰 가이드 (질문 유형별 탐색, 합의 흐름): `.claude/docs/REVIEW_GUIDE.md`
- 빌드 파일 목록: `.claude/docs/BUILD_SOURCE_FILES.md`
