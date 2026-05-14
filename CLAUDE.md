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

- 빌드 참여 파일: `.claude/docs/BUILD_SOURCE_FILES.md` 참조
- 메인 클라이언트: `cmd/gwemix/`
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

- Pangyo: 초기 PoA 활성화
- Applepie: Fee Delegation 트랜잭션 활성화
- Brioche: 블록 리워드 halving 곡선 — `BriocheBlock`, `BriocheConfig`
- Croissant: WBFT 합의 전환 (go-wbft에서 처리)

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
