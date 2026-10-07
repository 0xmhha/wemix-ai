# go-wemix 개발 가이드 (Claude Code용)

> 이 문서는 Claude Code를 통해 go-wemix를 개발할 때 알아야 할 제약사항, 아키텍처, 규칙을 정리한 참고 문서입니다.

---

## 목차

### 기본 참조
1. [프로젝트 개요](#1-프로젝트-개요)
2. [빌드 시스템](#2-빌드-시스템)
3. [코드 생성 파일 (수동 편집 금지)](#3-코드-생성-파일-수동-편집-금지)
4. [아키텍처 & 패키지 구조](#4-아키텍처--패키지-구조)
5. [핵심 인터페이스](#5-핵심-인터페이스)
6. [테스트](#6-테스트)
7. [린팅 & 포맷팅](#7-린팅--포맷팅)

### Wemix 고유 기능 (수정 시 필수 참조)
8. [거버넌스 컨트랙트](#8-거버넌스-컨트랙트)
9. [하드포크 추가 방법](#9-하드포크-추가-방법)
10. [Fee Delegation 트랜잭션](#10-fee-delegation-트랜잭션)
11. [Brioche 블록 보상 정책](#11-brioche-블록-보상-정책)
12. [Wemix 합의 / 마이닝 토큰](#12-wemix-합의--마이닝-토큰)
13. [etcd 클러스터 운영](#13-etcd-클러스터-운영)
14. [거버넌스 컨트랙트 흐름](#14-거버넌스-컨트랙트-흐름)

### 보안 불변식 (회귀 방지)
15. [StatusEx 신뢰 경계 & wemixWorkKey 보호](#15-statusex-신뢰-경계--wemixworkkey-보호)

### 운영
16. [CI/CD](#16-cicd)
17. [제네시스 생성](#17-제네시스-생성)
18. [주요 설정값 참조](#18-주요-설정값-참조)

---

## 1. 프로젝트 개요

| 항목 | 값 |
|------|-----|
| 바이너리 이름 | `gwemix` (+ 배포 tarball 동봉 `logrot`) |
| 현재 버전 | **v0.10.15-stable** (`params/version.go`) |
| Go 모듈 경로 | `github.com/ethereum/go-ethereum` *(geth fork — 모듈명 그대로 유지)* |
| Go 버전 | 1.19 (go.mod 선언) |
| Chain ID | Mainnet: **1111**, Testnet: **1112** *(`params/config.go`의 `WemixMainnetChainConfig.ChainID` 확인)* |
| 합의 알고리즘 | Clique 변형 + etcd 기반 마이닝 토큰 락 + Governance Contract |
| 블록 주기 | 1초 *(EnvStorage `getBlockCreationTime()`으로 동적 조정 가능)* |
| 보상 분배 | EnvStorage 4-way 분배: BlockProducer / StakingReward / Ecosystem / Maintenance |
| 멤버십 관리 | etcd 클러스터 (`go.etcd.io/etcd v3`, 임베디드 실행) + Solidity `Staking`/`Gov` |

---

## 2. 빌드 시스템

### 주요 Makefile 타겟

```bash
make gwemix          # 메인 바이너리 빌드 → build/bin/gwemix
make gwemix.tar.gz   # 배포 tarball (gwemix + logrot + conf)
make gwemix-linux    # Docker로 Linux 정적 빌드 (rocksdb 포함)
make logrot          # 로그 로테이션 도구
make geth            # 표준 geth 바이너리
make dbbench         # DB 벤치마크 도구
make test            # 전체 테스트
make test-short      # 빠른 테스트 (-short 플래그)
make lint            # golangci-lint 실행
make devtools        # 코드 생성 도구 설치 (stringer, gencodec, protoc, abigen, solc)
make clean           # 빌드 캐시 및 출력물 + rocksdb 정리
```

### USE_ROCKSDB 환경변수

```
USE_ROCKSDB = YES   → rocksdb 디렉토리를 정적 빌드 (Linux 기본)
              NO    → norocksdb.go 스텁 사용 (darwin/Windows 기본)
              EXISTING → 기존 RocksDB 공유 라이브러리 사용
```

RocksDB 모드에서는 `-tags rocksdb`로 빌드되어 `ethdb/rocksdb/rocksdb.go`가 활성화된다.

### 빌드 출력 위치

```
build/bin/         ← 빌드된 바이너리 (gwemix, logrot, geth 등)
build/conf/        ← 패키징용 설정 (gwemix.tar.gz 생성 시)
build/cache/       ← 빌드 캐시 (.gitignore)
build/_workspace/  ← 빌드 워크스페이스 (.gitignore)
rocksdb/           ← RocksDB submodule (USE_ROCKSDB=YES 시)
```

### 빌드 오케스트레이터

실제 빌드 로직은 `build/ci.go`에 있다. Makefile은 이 파일을 `go run`으로 호출하는 wrapper이며, `//go:build none` 태그로 일반 빌드에서 제외된다.

---

## 3. 코드 생성 파일 (수동 편집 금지)

### protobuf 생성 파일

위치: `accounts/usbwallet/trezor/`

```
messages.pb.go
messages-common.pb.go
messages-management.pb.go
messages-ethereum.pb.go
```

재생성: `protoc -I/usr/local/include:. --go_out=import_path=trezor:. *.proto`

### gencodec 생성 파일 (JSON 마샬링)

패턴: `gen_*.go`

위치: `core/types/`, `core/beacon/`, `eth/tracers/logger/`, `eth/ethconfig/`

재생성: `go run github.com/fjl/gencodec -type <Type> -field-override <override> -out gen_<file>.go`

### RLP 생성 파일

패턴: `gen_*_rlp.go`

위치: `core/types/`

재생성: `go run ../../rlp/rlpgen -type <Type> -out gen_<type>_rlp.go`

### Wemix 거버넌스 컨트랙트 Go 바인딩

위치: `wemix/bind/gen_*_abi.go`

```
gen_registry_abi.go        — Registry
gen_gov_abi.go             — Gov / GovImp / TestnetGovImp
gen_staking_abi.go         — Staking / StakingImp
gen_ballotStorage_abi.go   — BallotStorage / BallotStorageImp
gen_envStorage_abi.go      — EnvStorage / EnvStorageImp
gen_ncpExit_abi.go         — NCPExit / NCPExitImp
```

재생성 흐름 (`wemix/governance-contract/`):
1. `wemix/governance-contract/contracts/*.sol` 수정
2. `wemix/governance-contract/compiler.go`로 solc 컴파일 (solc 0.8.14)
3. `wemix/governance-contract/contracts/abigen.go`가 `abigen`을 호출해 `wemix/bind/`에 `gen_*_abi.go` 갱신
4. 변경된 ABI/바인딩을 commit

> **주의**: solc 버전(`0.8.14`)이 바뀌면 바이트코드 해시가 변동되어 제네시스 alloc과 어긋난다. 반드시 동일 버전 사용.

---

## 4. 아키텍처 & 패키지 구조

```
cmd/gwemix/          ← 진입점 (main.go, wemixcmd.go, governancedeploy.go)
params/              ← 체인 설정 (config.go, wemix_config.go, protocol_params.go)
consensus/clique/    ← Clique 기반 PoA (Wemix가 위에 wemix admin 레이어를 얹음)
core/                ← blockchain, state_transition, wemix_genesis.go
core/types/          ← 트랜잭션 타입 (feedelegate_dynamic_fee_tx.go 포함)
eth/                 ← 이더리움 백엔드
eth/protocols/eth/   ← wemix_handlers.go (Wemix 메시지 핸들러)
wemix/               ← Wemix 어드민·합의 코디네이션
  admin.go           ← wemixAdmin: 거버넌스 조회, 보상 분배, 멤버십
  etcdutil.go        ← etcd 임베디드 운영 + 마이닝 토큰 (acquireToken, etcdResetWork)
  miner_limit.go     ← 마이너 상태 수집 (electNextMiner)
  sync.go            ← 멤버십 동기화 (loadMiningToken, findConsensusBlock, syncCheck)
  spinlock.go        ← etcd 락 보호용 스핀락
  api/               ← WemixMinerStatus 이벤트 API
  bind/              ← abigen 산출 Go 바인딩 (gen_*_abi.go)
  metclient/         ← 트랜잭션 헬퍼 (tx_params.go, util.go)
  miner/             ← wemix 보상 주입 (miner.go)
  governance-contract/ ← Solidity 소스 + 컴파일 도구 (빌드 비참여)
  scripts/           ← 런타임 자산 (gwemix.sh, config.json.example, genesis-template.json)
```

### 패키지 의존 규칙

- `internal/` 패키지는 이 모듈 내에서만 import 가능
- `wemix/admin.go`는 `wemix/bind`의 거버넌스 Go 바인딩을 의존성으로 사용
- `miner` ↔ `wemix/miner` 사이는 함수 변수(`wemixminer.SignBlockFunc`, `wemixminer.GetBlockBuildParametersFunc`)로 IoC — 직접 import 방지

---

## 5. 핵심 인터페이스

### consensus.Engine

파일: `consensus/consensus.go` — Wemix는 `consensus/clique` 위에 `wemix` admin 패키지가 보조 레이어를 얹는 구조.

```go
type Engine interface {
    Author(header *types.Header) (common.Address, error)
    VerifyHeader(chain ChainHeaderReader, header *types.Header, seal bool) error
    VerifyHeaders(...)
    VerifyUncles(chain ChainReader, block *types.Block) error
    Prepare(chain ChainHeaderReader, header *types.Header) error
    Finalize(...) // 보상 분배 적용 지점
    FinalizeAndAssemble(...) (*types.Block, []*types.Receipt, error)
    Seal(chain ChainHeaderReader, block *types.Block, results chan<- *types.Block, stop <-chan struct{}) error
    SealHash(header *types.Header) common.Hash
    CalcDifficulty(...)
    APIs(chain ChainHeaderReader) []rpc.API
    Close() error
}
```

### Wemix 마이너 IoC

파일: `wemix/admin.go:1519 init()` (패키지 초기화 시점에 함수 변수 주입)

```go
wemixminer.SignBlockFunc            = signBlock
wemixminer.GetBlockBuildParametersFunc = getBlockBuildParameters
// + DistributeRewards, AmPartner 등 모듈 변수
```

이 변수들은 `wemix/miner/miner.go`에서 export되며, 표준 `miner` 패키지가 이를 통해 Wemix 정책에 접근한다.

### Wemix Admin API (RPC)

`wemix/admin.go`는 다수의 RPC 메서드를 노출한다 (`eth_call`이 아닌 `admin_*` / `wemix_*` 네임스페이스). 대표:

- 멤버 노드 목록 / 상태 (`getMiners`, `getMinerStatus`)
- 거버넌스 컨트랙트 조회 wrapper
- etcd 클러스터 가입/탈퇴 액션

수정 시 RPC 시그니처가 외부 모니터링 도구와 호환되어야 함 — breaking change 금지.

---

## 6. 테스트

### 테스트 실행

```bash
make test         # 전체 테스트
make test-short   # 빠른 단위 테스트
```

### 주요 테스트 위치

Wemix 고유 코드 (수정 시 필수 실행):

| 파일 | 커버 대상 |
|------|-----------|
| `wemix/rewards_test.go` | `distributeRewards` 4-way 분배, 보상 검증, Brioche halving (`TestDistributeRewards`, `TestRewardValidation`, `TestBriocheHardFork`) |
| `wemix/etcd_test.go` | 임베디드 etcd 위 `etcdResetWork` CAS 동작 (`TestEtcdResetWork_*` 5종) |
| `wemix/sync_regression_test.go` | StatusEx 위조 / `wemixWorkKey` 오염 공격 체인의 pre-fix 재현 ↔ post-fix 방어 쌍 (§15) |
| `wemix/api/api_test.go` | `WemixMinerStatus.Clone()` nil-safe 복사 |
| `core/types/transaction_test.go` | Fee Delegation — `TestRecoverFeePayer`, `TestAsMessageFeeDelegation`, `TestSetSenderTxAccessListPreserved` |
| `core/block_validator_test.go` | EIP-7934 블록 크기 상한 수신 경로 — `TestValidateBodyBlockOversized` (§12) |
| `miner/worker_test.go` | 블록 크기 상한 생성 경로 `TestCommitTransactions[Simple]BlockSizeLimit`, 타임스탬프 하한 `TestTimeItTimestampLowerBound`, 멈춘 워커의 토큰 획득 생략 `TestSkipMiningTokenAcquisitionWhenWorkerStopped` (§12) |
| `cmd/gwemix/*_test.go` | CLI / 제네시스 / `governancedeploy` 검증 (8개) |
| `params/config_test.go` | 하드포크 순서·호환성 |

빌드 의존성 밖 (별도 실행):

- `wemix/bind/backends/wemix_simulated_test.go` — 거버넌스 시뮬레이션 백엔드
- `wemix/governance-contract/test/gov_test.go` — GovImp 거버넌스 시나리오. `TestGov`, `TestGov_IndexCorruptionAfterRemoveMember`, `TestW1G01`~`TestW1G04` 계열(CertiK W1G 대응), `TestW1G_LegacyUpgrade_FullLifecycle`
- `wemix/governance-contract/test/gov_bind_test.go` — abigen 바인딩 정합성

> **red→green 픽스처**: `wemix/governance-contract/contracts/mock/GovImpLegacy.sol`, `GovImpPreMarker.sol`은 **취약했던 시점의 구현을 그대로 보존한 테스트 픽스처**다. 최신 GovImp에 맞춰 "고치면" 회귀 테스트가 무의미해지므로 수정 금지.

geth 원본 테스트 중 자주 걸리는 것: `core/blockchain_test.go`, `core/state_processor_test.go`, `core/tx_pool_test.go`, `eth/protocols/eth/handler_test.go`.

전체 목록: `.claude/docs/BUILD_SOURCE_FILES.md` §3 (85개 패키지 / 302개 테스트 파일).

### CI 분기

PR이 `dev`/`master`로 향할 때 GitHub Actions에서 `make gwemix && make test-short && make lint`를 실행한다 (`.github/workflows/` 참조).

---

## 7. 린팅 & 포맷팅

설정 파일: `.golangci.yml`

### 활성화된 주요 린터

| 린터 | 역할 |
|------|------|
| goimports | import 순서 포맷팅 |
| govet | go vet 검사 |
| staticcheck | 정적 분석 |
| unused | 미사용 식별자 검출 |
| misspell | 오탈자 |
| revive | 수신자 명명 등 |
| copyloopvar | Go 1.22+ loop var 이슈 (Go 1.19에서는 일부 비활성) |

### 린트 제외 경로

- `core/genesis_alloc.go`, `core/wemix_genesis.go` (대형 생성 파일)
- `crypto/bn256/cloudflare/` (서드파티 코드)
- `wemix/bind/gen_*_abi.go` (abigen 생성물)

### 린트 실행

```bash
make lint
# 또는 변경 라인만:
golangci-lint run --new-from-rev=origin/dev ./...
```

---

## 8. 거버넌스 컨트랙트

### 도메인 키 (`wemix/bind/const.go`)

| Domain 상수 | 컨트랙트 | 역할 |
|-------------|----------|------|
| `Registry` | Registry | 모든 도메인↔주소 매핑 보유 (소유주: 거버넌스 owner) |
| `GovernanceContract` (`DOMAIN_Gov`) | `GovImp` *(또는 `TestnetGovImp`)* | 멤버 등록/투표/실행, EnvStorage 변경 위임 |
| `Staking` | `StakingImp` | 스테이킹/언스테이킹, 락업/슬래시 |
| `BallotStorage` | `BallotStorageImp` | 투표·발의 영구 저장소 |
| `EnvStorage` | `EnvStorageImp` | 체인 파라미터 (블록 보상, baseFee 한도, gas limit 등) |
| `NCPExit` | `NCPExitImp` | NCP(노드 운영 사업자) 퇴출 처리 |
| `StakingReward` | (지갑/EOA) | 스테이킹 리워드 풀 |
| `Ecosystem` | (지갑/EOA) | 생태계 보상 풀 |
| `Maintenance` | (지갑/EOA) | 운영 비용 풀 |
| `FeeCollector` | (지갑/EOA) | 트랜잭션 수수료 수집 풀 |

### 업그레이드 모델

대부분의 거버넌스 컨트랙트는 **UUPSUpgradeable** 패턴 (`@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol`)을 사용한다:

- 프록시(`Gov.sol`, `Staking.sol`, ...) ↔ 구현(`GovImp.sol`, `StakingImp.sol`, ...) 분리
- Registry는 프록시 주소만 보관 (구현이 바뀌어도 도메인 매핑은 불변)
- `upgradeTo(newImpl)` 호출은 거버넌스 투표 통과 후 GovImp가 실행

### 컨트랙트 재컴파일 / 바인딩 재생성

```bash
cd wemix/governance-contract
go run ./solcdownloader     # solc 0.8.14 다운로드
go run ./compiler.go        # 직접 호출 또는 compile/ 패키지 main 사용

# abigen으로 Go 바인딩 재생성 (wemix/governance-contract/contracts/abigen.go 참조)
go generate ./...
```

> **주의**: 컨트랙트 변경 시 다음을 모두 갱신해야 한다:
> 1. `wemix/governance-contract/contracts/*.sol` (소스)
> 2. `wemix/bind/gen_*_abi.go` (Go 바인딩 — 자동 생성)
> 3. 제네시스 alloc 안의 컨트랙트 바이트코드 (생성기로 갱신 필요)
> 4. 마이그레이션 / 거버넌스 투표 시나리오 (운영자 공지)

---

## 9. 하드포크 추가 방법

하드포크를 안전하게 추가하려면 아래 단계를 순서대로 따를 것.

### Step 1: ChainConfig에 필드 추가

파일: `params/config.go`

```go
type ChainConfig struct {
    // ... 기존 필드
    PangyoBlock     *big.Int
    ApplepieBlock   *big.Int
    BriocheBlock    *big.Int
    CroissantBlock  *big.Int
    MyNewForkBlock  *big.Int `json:"myNewForkBlock,omitempty"`  // 추가
}
```

### Step 2: 활성화 체크 메서드 추가

```go
func (c *ChainConfig) IsMyNewFork(num *big.Int) bool {
    return isForked(c.MyNewForkBlock, num)
}
```

### Step 3: Rules 구조체 / Rules() 메서드 업데이트

```go
type Rules struct {
    // ... 기존
    IsPangyo, IsApplepie, IsBrioche, IsCroissant bool
    IsMyNewFork                                  bool
}

func (c *ChainConfig) Rules(num *big.Int, ...) Rules {
    return Rules{
        // ...
        IsMyNewFork: c.IsMyNewFork(num),
    }
}
```

### Step 4: `CheckConfigForkOrder` / `CheckCompatible` 등록

```go
// CheckConfigForkOrder의 검증 목록에 순서대로 추가 (이전 포크보다 뒤에)
{name: "myNewForkBlock", block: c.MyNewForkBlock, optional: true},

// CheckCompatible의 비호환 검사
if isForkIncompatible(c.MyNewForkBlock, newcfg.MyNewForkBlock, head) {
    return newCompatError("MyNewFork fork block", c.MyNewForkBlock, newcfg.MyNewForkBlock)
}
```

### Step 5: Mainnet/Testnet 블록 번호 설정

`params/config.go`의 `WemixMainnetChainConfig`, `WemixTestnetChainConfig`에 활성 블록 번호 지정.

### Step 6: 런타임 분기 추가

```go
if config.IsMyNewFork(blockNum) {
    // 새 동작
} else {
    // 기존 동작
}
```

### Step 7: Description() 출력 갱신

`ChainConfig.Description`/`String` 메서드 또는 출력 배너에 새 포크 줄 추가.

### 하드포크 검증 규칙

- 블록 번호는 이전 포크보다 반드시 크거나 같아야 함 (`CheckConfigForkOrder`가 enforce)
- Mainnet과 Testnet의 활성 블록은 독립적이며, Mainnet 활성 시점이 Testnet보다 늦을 수도 있음
- 거버넌스 컨트랙트가 변경되는 포크라면 §8의 재컴파일 + 제네시스 갱신을 동반

---

## 10. Fee Delegation 트랜잭션

### 개요

파일: `core/types/feedelegate_dynamic_fee_tx.go`

트랜잭션 타입 **`0x16` (`FeeDelegateDynamicFeeTxType = 22`)**. Sender 대신 별도의 FeePayer가 가스비를 지불하는 **이중 서명 트랜잭션**.

> **하드포크 게이팅**: `Applepie` 이후에만 활성화 (`core/state_transition.go` / `core/txpool` 검증 지점).

### 구조

```go
type FeeDelegateDynamicFeeTx struct {
    SenderTx DynamicFeeTx     // Sender의 원본 트랜잭션 (EIP-1559)
    FeePayer *common.Address  // 가스비 지불자 주소
    FV       *big.Int         // FeePayer 서명 V
    FR       *big.Int         // FeePayer 서명 R
    FS       *big.Int         // FeePayer 서명 S
}
```

### 이중 서명 모델

```
1단계: Sender가 SenderTx(DynamicFeeTx) 서명 → SenderTx.V/R/S에 저장
2단계: FeePayer가 [SenderTx 전체 + FeePayer 주소]에 대해 서명 → FV/FR/FS에 저장
```

### FeePayer 검증 단일 진입점 — `RecoverFeePayer`

FeePayer 검증 로직은 여러 곳에 흩어져 있었으나 현재는 **`core/types/transaction_signing.go`의 `RecoverFeePayer` 하나로 통합**되어 있다.

```go
// core/types/transaction_signing.go
var (
    ErrFeePayerNotSet  = errors.New("fee delegation: feePayer not set")   // FeePayer 필드가 nil
    ErrInvalidFeePayer = errors.New("fee delegation: invalid feePayer")   // FV/FR/FS 복구 결과 불일치
)

// FV/FR/FS에서 주소를 복구하고, 선언된 FeePayer 주소와 일치하는지 검증한다.
func RecoverFeePayer(chainID *big.Int, tx *Transaction) (common.Address, error)
```

호출 지점:

| 위치 | 역할 |
|------|------|
| `core/types/transaction.go: AsMessage()` | `tx.Type() == FeeDelegateDynamicFeeTxType`일 때 **항상** 검증 후 `msg.feePayer` 설정. 실패 시 에러 반환 |
| `core/tx_pool.go: validateTx()` | txpool 진입 검증 + FeePayer 잔액 확인 |
| `light/txpool.go: validateTx()` | 라이트 클라이언트 동일 검증 |

> **중요 — 검증 위치 변경**: 예전에는 `internal/ethapi/api.go: SubmitTransaction()`이 RPC 경계에서 FeePayer nil/서명을 따로 검사했다. 이 중복 검사는 제거되었고, 검증은 txpool과 `AsMessage`로 일원화되었다. **RPC 레이어에 FeePayer 검증을 되살리지 말 것** — 중복 검증이고, P2P로 들어온 tx는 어차피 RPC를 거치지 않으므로 실효도 없다.
>
> `AsMessage`의 검사는 `tx.FeePayer() != nil` 여부가 아니라 **트랜잭션 타입**으로 분기한다. 타입이 fee-delegated인데 FeePayer가 없으면 조용히 넘어가지 않고 `ErrFeePayerNotSet`으로 실패해야 한다.

### `SetSenderTx`의 AccessList 사전 할당

```go
// core/types/feedelegate_dynamic_fee_tx.go
tx.SenderTx.AccessList = make(AccessList, len(senderTx.AccessList))  // ← 필수
copy(tx.SenderTx.AccessList, senderTx.AccessList)
```

`copy`는 목적지 슬라이스 길이만큼만 복사한다. 제로값 초기화된 `SenderTx`의 `AccessList`는 nil(len 0)이므로 `make` 없이 `copy`하면 **엔트리가 전부 유실되고 sender 서명 복구가 실패**한다. RPC 조립 경로에서 재현되며, 회귀 테스트는 `TestSetSenderTxAccessListPreserved`.

### 수정 시 주의사항

| 영역 | 주의 |
|------|------|
| `setSignatureValues(chainID, v, r, s)` | **FeePayer 서명**에 적용됨 (sender 아님) |
| `rawSignatureValues()` | **Sender 서명** (SenderTx.V/R/S)을 반환 |
| `rawFeePayerSignatureValues()` | **FeePayer 서명** (FV/FR/FS)을 반환 |
| 가스 가격 계산 | Sender의 `GasFeeCap/GasTipCap` 사용 (FeePayer 값 없음) |
| 트랜잭션 검증 | Sender + FeePayer 두 서명 모두 검증 필요 |
| txpool 진입 검증 | `Applepie` 활성 전 거부 |

### 관련 파일

| 파일 | 역할 |
|------|------|
| `core/types/feedelegate_dynamic_fee_tx.go` | 트랜잭션 타입 정의, `SetSenderTx` |
| `core/types/transaction.go:48` | `FeeDelegateDynamicFeeTxType = 22` 상수 |
| `core/types/transaction.go: AsMessage()` | 타입 기반 FeePayer 검증 진입점 |
| `core/types/transaction_signing.go` | Sender/FeePayer 서명 처리, **`RecoverFeePayer`**, `ErrFeePayerNotSet`, `ErrInvalidFeePayer` |
| `core/state_transition.go` | FeePayer 잔액 차감 처리 |
| `core/error.go` | `ErrFeePayerInsufficientFunds` *(`ErrInvalidFeePayer`는 `core/types`로 이동)* |
| `internal/ethapi/api.go` | `SignRawFeeDelegateTransaction()` 등 RPC *(FeePayer 검증은 제거됨)* |
| `internal/ethapi/transaction_args.go` | `FeePayer`, `FV/FR/FS` JSON 필드 |
| `core/tx_pool.go` | Applepie 게이팅 + `RecoverFeePayer` + FeePayer 잔액 검사 |
| `light/txpool.go` | 라이트 클라이언트 측 동일 검증 |
| `core/types/transaction_test.go` | `TestRecoverFeePayer`, `TestAsMessageFeeDelegation`, `TestSetSenderTxAccessListPreserved` |

---

## 11. Brioche 블록 보상 정책

### 개요

파일: `params/config.go` (`BriocheConfig`, `GetBriocheBlockReward`) — Wemix Brioche 하드포크에서 도입된 **반감(halving) 기반 보상 곡선**.

### BriocheConfig 구조

```go
type BriocheConfig struct {
    BlockReward       *big.Int  // 초기 블록 보상 (Wei). 설정 시 defaultReward를 덮어씀
    FirstHalvingBlock *big.Int  // nil → halving 비활성. 이 블록부터 halving 시작
    HalvingPeriod     *big.Int  // 반감 주기 (블록 수)
    FinishRewardBlock *big.Int  // 이 블록 이후 보상 0 (nil → 무한 지속)
    HalvingTimes      uint64    // 최대 반감 횟수 (0 → halving 없음)
    HalvingRate       uint32    // 반감 비율 (% — 50이면 절반, 100이면 무반감, >100이면 증가)
}
```

### 보상 계산 흐름 (`GetBriocheBlockReward` → `calcHalvedReward`)

```
0. blockReward = BlockReward (설정 시) 아니면 defaultReward
1. FinishRewardBlock != nil && num >= FinishRewardBlock  → 0
2. FirstHalvingBlock/HalvingPeriod 미설정, HalvingTimes == 0,
   또는 num < FirstHalvingBlock                          → blockReward 그대로
3. elapsed = num - FirstHalvingBlock
4. times   = min(1 + elapsed / HalvingPeriod, HalvingTimes)   ← 1부터 시작
5. reward  = blockReward * HalvingRate^times / 100^times
```

> **`times`는 0이 아니라 1부터 시작한다.** `FirstHalvingBlock` 블록 자체가 이미 1차 반감이 적용된 시점이다 (`params/config.go:464`의 `common.Big1 + elapsed/HalvingPeriod`). 보상 곡선을 손으로 검산할 때 흔히 틀리는 지점.

### Mainnet vs Testnet 활성 블록

| 항목 | Mainnet | Testnet |
|------|--------:|--------:|
| `BriocheBlock` | 53,525,500 | 59,414,700 |
| `FirstHalvingBlock` | 53,525,500 | 59,414,700 |
| `BlockReward` | 1e18 | 1e18 |
| `HalvingPeriod` | 63,115,200 | 63,115,200 |
| `HalvingTimes` | 16 | 16 |
| `HalvingRate` | 50 | 50 |
| `FinishRewardBlock` | 2,467,714,000 (≈2101-01-01 KST) | 2,473,258,000 (≈2100-12-01 KST) |

### 수정 시 주의사항

- **Brioche 활성 전**: `EnvStorageImp.getBlockRewardAmount()` 사용
- **Brioche 활성 후**: `BriocheConfig.GetBriocheBlockReward(defaultReward, num)` 사용
- 호출 분기는 `wemix/admin.go` 안의 `distributeRewards` 호출 경로에 위치 (search: `not brioche chain`)
- 보상 분배 비율 (`getBlockRewardDistributionMethod`)은 EnvStorage가 관리하므로 코드 변경 없이 거버넌스 투표로 조정 가능

---

## 12. Wemix 합의 / 마이닝 토큰

### 합의 개요

Wemix는 **Clique 변형 PoA** + **etcd 마이닝 토큰 락**의 조합으로 단일 라이터를 보장한다:

```
1. Clique 합의: 멤버(authorized signer) 집합과 라운드 로빈 서명자 선출
2. etcd 토큰: 동일 블록 높이에 대해 단일 마이너만 ‘토큰’을 보유 → 중복 블록 생성 방지
3. Governance Contract: 멤버 추가/제거, 보상 분배 비율, 가스 파라미터 등 동적 정책
```

### 마이닝 토큰 흐름

```
miner/worker.go: commitWork()
    ├─ !w.isRunning() → refreshPending 후 반환 (토큰을 잡지 않음)
    └─ wemixminer.AcquireMiningToken(height, parentHash)
         ↓
wemix/sync.go: acquireMiningToken() → miningToken.Store(lck)
    ↓
wemix/etcdutil.go:
   ma.acquireToken(ctx, height, ttl)                     — 토큰 획득 (CAS 기반)
   ma.acquireTokenSync(ctx, height, parentHash, ttl)     — work가 parent와 맞을 때만 획득
   ma.etcdResetWork(token, newWork)                      — 토큰 보유 중일 때만 wemixWorkKey 갱신 (CAS)
   lck.release(ctx)                                      — 토큰 반환
   lck.releaseTokenSync(ctx, height, hash, parentHash)   — work 갱신과 함께 반환

wemix/sync.go: loadMiningToken() / hasMiningToken()       — 보유 토큰 조회
wemix/spinlock.go: SpinLock — 토큰 임계 영역 보호
```

> v0.10.15에서 토큰 TTL 갱신 함수 `lck.renew()`가 쓰이지 않는 코드로 정리되며 삭제됐다. 같은 정리에서 `lockedPut`, `ttl2`도 사라졌다. 현재 토큰의 수명은 획득 시 정한 `Till`로만 결정된다.

### 마이닝 토큰 획득 게이트 — 멈춘 워커는 토큰을 잡지 않는다

`miner/worker.go: commitWork`는 PoA 모드에서 `AcquireMiningToken`을 부르기 **전에** `w.isRunning()`을 확인한다 (v0.10.15, #192).

- 블록 빌드(`commitEx`)와 `ReleaseMiningToken`은 모두 `isRunning()` 뒤에 있다. 동기화 중처럼 워커가 멈춘 상태에서 토큰을 잡으면 반환할 경로가 없다.
- 반환되지 않은 토큰은 `Till`이 지날 때까지 클러스터 공유 락을 쥐고 있다. 그동안 다른 노드도 블록을 만들지 못해 체인이 멈춘다.
- 이 가드를 `AcquireMiningToken` 뒤로 옮기거나 빼지 말 것. 회귀 테스트: `TestSkipMiningTokenAcquisitionWhenWorkerStopped`

### `syncCheck` — stale work 덮어쓰기 방지 (`wemix/sync.go:242`)

노드가 `SyncIdleThreshold` 동안 진전이 없으면 `syncCheck`가 `wemixWorkKey`를 재설정한다. 이 경로는 잘못 쓰면 **클러스터 전체의 마이닝 타깃을 오염**시키므로 여러 겹의 가드가 걸려 있다. 순서대로:

| 단계 | 가드 | 이유 |
|------|------|------|
| 피어 수집 | `getMiners("", MiningTokenTTL/2)` | 수집 타임아웃이 토큰 TTL보다 짧아야 `etcdResetWork`까지 토큰이 살아 있다. TTL 이상이면 다른 노드가 work를 진행시킨 뒤 stale 값으로 덮어쓴다 |
| 거버넌스 캐시 | `len(nodes) == 0` → abort | 거버넌스 노드 목록이 비면 정족수를 판단할 근거가 없다 |
| work가 앞설 때 | 피어 state 1개라도 `(work.Height, work.Hash)`를 echo하면 catch-up으로 보고 조용히 종료 | 동기화 중에는 `HeaderByHash(work.Hash)`가 항상 NotFound라 reachability 게이트만 쓰면 매 사이클 오탐 로그가 발생 |
| 합의 블록 도달성 | `HeaderByHash(consensusHash)` 실패 → abort | 로컬 체인에 없는 해시를 쓰면 모든 검증자의 `acquireTokenSync`가 `ErrInvalidWork`로 영구 실패 |
| 해시/높이 정합 | `peerHeader.Number != consensusHeight` → abort | 실제 해시 + 가짜 높이 조합(정족수 조작)이 도달성 검사와 회귀 가드 사이를 빠져나가는 구멍을 막음 |
| 높이 역행 | `consensusHeight < header.Number` → abort | 오래된(여전히 canonical인) 해시를 echo해 마이닝 타깃을 뒤로 밀어버리는 공격 차단 |
| 최종 기록 | `admin.etcdResetWork(token, newWork)` | 토큰을 여전히 보유 중일 때만 CAS로 기록. 만료됐으면 `ErrInvalidToken`으로 거부 |

> **획득과 `etcdResetWork` 사이에서 토큰의 `Till`을 바꾸지 말 것.** `etcdResetWork`는 in-memory 토큰을 직렬화한 값과 etcd에 저장된 값을 `Compare`한다. 그 사이에 `Till`을 갱신하면 두 값이 어긋나 CAS가 항상 실패한다. 예전에는 `renew()`가 이 일을 했다. 함수는 v0.10.15에서 삭제됐지만 `wemix/sync.go:439-440`의 WARNING 주석은 여전히 `renew()`를 언급한다. TTL 갱신 기능을 다시 넣는다면 이 제약을 지켜야 한다.
>
> v0.10.15부터 `syncCheck`는 성공 경로에서 `nil`을 반환하고 `Info` 레벨로 로그를 남긴다. 예전에는 성공해도 `log.Error`를 찍었다. `wemixWorkKey` 값이 JSON으로 풀리지 않으면 에러 원인을 함께 로그에 남기고 work를 `nil`로 취급한다.

### 블록 빌드 파라미터

`wemix/admin.go:getBlockBuildParameters(height)`가 EnvStorage에서 다음을 가져와 마이너에 주입:

- `blockInterval` (밀리초)
- `maxBaseFee`, `gasLimit`
- `baseFeeMaxChangeRate`, `gasTargetPercentage`

### 블록 타임스탬프 하한 (`miner/worker.go:1515 timeIt`)

`timeIt`은 현재 시각(초)을 헤더 `Time`으로 쓰되, 부모 블록 시각보다 작아지지 않게 하한을 건다.

```go
timestamp = uint64(nowInSeconds)
if timestamp < parent.Time() {
    timestamp = parent.Time()
}
```

v0.10.14까지는 `parent.Number()`와 비교하는 버그가 있었다 (#189). 블록 번호는 초 단위 시각보다 훨씬 작아서 하한이 사실상 걸리지 않았다. 시계가 뒤로 간 노드는 부모보다 이른 타임스탬프를 고를 수 있었다. 회귀 테스트: `TestTimeItTimestampLowerBound`

블록이 모자라 서둘러야 할 때(`offset == -1`)는 같은 초에 블록이 몰리지 않도록 빌드 마감을 다음 초 경계로 미룬다.

### 블록 크기 상한 — EIP-7934 (v0.10.15, #196)

RLP 인코딩한 블록 크기는 `params.MaxBlockSize` = 8,388,608 바이트(8 MiB)를 넘을 수 없다. **하드포크 게이트가 없다.** 동기화로 받는 과거 블록을 포함해 모든 블록에 항상 적용된다.

| 경로 | 위치 | 동작 |
|------|------|------|
| 수신 | `core/block_validator.go: ValidateBody` | 맨 앞에서 `block.Size() > MaxBlockSize`이면 `ErrBlockOversized`(`core/error.go`) 반환 |
| 생성 | `miner/worker.go: environment.txFitsSize` | `env.size + tx.Size() < MaxBlockSize - maxBlockSizeBufferZone`(1,000,000)일 때만 tx를 담는다. `commitTransactions`와 `commitTransactionsSimple` 두 패킹 루프 모두 넘으면 즉시 `break` |
| P2P | `eth/protocols/eth/protocol.go: maxMessageSize` | eth 프로토콜 메시지 상한을 100 MiB에서 **10 MiB**로 낮췄다. 블록 바디를 포함한 과대 메시지를 읽는 단계에서 거부한다 |

- `environment.size`는 `makeEnv`에서 헤더 크기로 시작하고, `commitTransaction`이 tx를 담을 때마다 늘어난다. `environment.copy()`도 이 값을 복사한다. 새 패킹 경로를 추가하면 이 세 곳의 규칙을 그대로 따라야 한다.
- 생성 쪽 여유분 1,000,000 바이트는 tx를 담은 뒤에 블록에 추가되는 데이터를 위한 것이다 (코드 주석의 "auxiliary data"). 생성 상한을 수신 상한과 같게 맞추면 직접 만든 블록을 피어가 거부할 수 있다.
- 수신 쪽 검사를 빼면 크기 상한을 넘은 블록이 canonical이 되는 순간 다른 노드가 받아들이지 못해 체인이 영구히 멈춘다.
- 회귀 테스트: `TestValidateBodyBlockOversized`, `TestCommitTransactionsBlockSizeLimit`, `TestCommitTransactionsSimpleBlockSizeLimit`

### 수정 시 주의사항

- **etcd 임베디드**는 노드 프로세스 내부에서 실행 — 별도 클러스터 관리 불필요. `wemix/etcdutil.go` 참조
- **토큰 재진입 금지**: SpinLock 임계 영역 내부에서 etcd 호출은 짧게 (블록 검증 같은 무거운 작업 금지)
- **토큰 갱신 실패 처리**: TTL 만료 시 다른 노드가 토큰을 가져가도록 fail-fast — 무리한 재시도 금지
- **`findConsensusBlock`** (`wemix/sync.go:197`)이 멤버 다수가 동의하는 블록 높이를 찾아 동기화 지점 결정

---

## 13. etcd 클러스터 운영

### 개요

각 Wemix 마이너 노드는 **embedded etcd 서버**를 함께 실행한다 (`go.etcd.io/etcd v3` + `server/v3/embed`). 멤버 추가/제거는 거버넌스 컨트랙트와 etcd 멤버십을 동시 갱신.

### 주요 메서드 (`wemix/etcdutil.go`)

| 함수 | 역할 |
|------|------|
| `etcdMemberExists(name, cluster)` | 클러스터 문자열에 멤버 존재 확인 |
| `etcdFixCluster(cluster)` | 신규 가입 멤버의 누락된 name 채움 |
| `etcdNewConfig(newCluster)` | embed.Config 생성 (Dir, InitialClusterToken 등) |
| `etcdIsRunning()` | 서버 실행 여부 |
| `acquireToken(ctx, height, ttl)` | 마이닝 토큰 획득 |
| `releaseTokenSync(...)` | 동기 반환 (블록 확정 시) |
| `etcdResetWork(token, newWork)` | **토큰 보유 확인 후에만** `wemixWorkKey` 기록 (etcd Txn CAS). 토큰 불일치/부재 시 `ErrInvalidToken` |
| `etcdGet(key)` | 키 하나만 조회. `WithPrefix`/`WithRange` 없이 호출하므로 결과는 최대 1건이고 `Kvs[0]`을 바로 쓴다. 접두사·범위 조회가 필요하면 이 함수를 늘리지 말고 별도 함수를 만든다 (코드 주석에 명시된 계약) |
| `etcdAutoJoin()` | 다른 마이너 수에 맞춰 가입 시점을 분산한다. `gap == 0`(피어 없음)이면 `ErrNotFound`로 일찍 반환 |

> **v0.10.15에서 삭제된 미사용 함수** (#194): `etcdWipe`, `etcdStop`, `etcdIsLeader`, `etcdPut2`, `etcdCompact`, `WemixToken.renew`, `WemixToken.lockedPut`, `ttl2`, `admin.go`의 `pendingEmpty`. 호출하던 곳이 없어서 지웠다. 이 이름으로 코드를 찾거나 새 코드에서 호출하지 말 것.

### 임베디드 etcd 설정

```
etcdDir              ← 데이터 디렉토리 (gwemix datadir 하위)
etcdClusterName      ← initial-cluster-token
ListenClientUrls     ← 내부 RPC용
ListenPeerUrls       ← 멤버 간 통신용
```

### 수정 시 주의사항

- `wemix/etcdutil.go.new` 보관 파일은 v0.10.15에서 삭제됐다. etcd 운영 코드는 `etcdutil.go` 하나뿐이다
- **`etcdAutoJoin`의 `gap == 0` 가드 유지** (#193): `getMiners`가 빈 목록을 돌려주면 `tt = sz * gap = 0`이 되어 `ct/tt`에서 0 나눗셈 panic이 난다. recover가 없는 고루틴이라 프로세스 전체가 죽는다
- 클러스터 재구성 시 `etcdReady` 플래그 / `etcdAutoJoinLock` 채널이 race-free하게 동기화되어야 함
- etcd 임베디드를 비활성화한 단독 모드 빌드는 현재 지원하지 않음 (의존성 깊이 박힘)
- etcd 데이터 경로의 디스크 용량 부족이 합의 실패의 흔한 원인 — 모니터링 필수

---

## 14. 거버넌스 컨트랙트 흐름

상세는 `.claude/docs/GOVERNANCE_FLOW.md` 참조. 요약:

```
Genesis JSON (core/wemix_genesis.go)
    │
    ├─ alloc[Registry]  ← 컴파일된 Registry 바이트코드 + 초기 도메인 매핑 스토리지
    ├─ alloc[Gov]       ← Gov 프록시 + GovImp 구현
    ├─ alloc[Staking]   ← Staking 프록시 + StakingImp 구현
    ├─ alloc[BallotStorage], alloc[EnvStorage], alloc[NCPExit] (동일 패턴)
    └─ alloc[GovImp/StakingImp/...] ← 구현 컨트랙트 (프록시가 가리킴)
```

### 런타임 호출 경로 (대표)

```
gwemix process start
    │
    ▼
wemix/admin.go: NewWemixAdmin()
    │
    ├─ bind.NewRegistry(registryAddr, client)
    ├─ registry.GetContractAddress(DOMAIN_GovernanceContract)  → Gov 프록시
    ├─ bind.NewGovImp(govAddr, client)                          → Gov 호출
    ├─ registry.GetContractAddress(DOMAIN_Staking)              → Staking 프록시
    ├─ registry.GetContractAddress(DOMAIN_EnvStorage)           → EnvStorage 프록시
    └─ EnvStorageImp.getBlocksPer/getBlockRewardAmount/...      → 합의 파라미터
```

### 새 거버넌스 메서드 추가 흐름

1. `wemix/governance-contract/contracts/*.sol`에 새 함수 작성 (UUPS 업그레이드 가능 시 신구현)
2. `go generate ./wemix/governance-contract/contracts/` → `wemix/bind/gen_*_abi.go` 갱신
3. Go 측 호출: `contracts.GovImp.NewMethod(opts, ...)` 형태로 사용
4. 거버넌스 투표로 `upgradeTo(newImpl)` 실행 (운영 절차)

---

## 15. StatusEx 신뢰 경계 & wemixWorkKey 보호

Wemix 노드는 파트너 노드끼리 `StatusEx` 메시지로 서로의 최신 블록 상태를 교환하고, 그 집합(`miningPeers`)에서 `findConsensusBlock`이 정족수 블록을 뽑아 `wemixWorkKey`(= 클러스터 공통 마이닝 타깃)를 결정한다. 즉 **`StatusEx` 페이로드는 합의 입력**이며, 하나의 침해된 파트너가 이 경로로 클러스터를 정지시킬 수 있다.

관련 회귀 테스트: `wemix/sync_regression_test.go` (32KB) — 각 항목마다 pre-fix 재현과 post-fix 방어가 쌍으로 들어 있다.

### 불변식 1 — NodeName은 거버넌스 조회로만 결정된다

`eth/protocols/eth/wemix_handlers.go: handleStatusEx()`

```go
// 페이로드의 NodeName은 공격자가 통제한다. 검증된 peer.ID()를
// 거버넌스 등록 이름으로 해석해 덮어쓰고, 미등록 피어는 드롭한다.
nodeName, ok := wemixminer.NodeNameForPeerID(peer.ID())
if !ok {
    return fmt.Errorf("%w: unknown peerID %v", errDecode, peer.ID())
}
status.NodeName = nodeName
```

- 페이로드의 `NodeName`을 그대로 믿으면, 침해된 파트너 **1대가 여러 거버넌스 이름을 사칭해 `miningPeers`에 다중 엔트리를 심고 `findConsensusBlock` 정족수를 위조**할 수 있다.
- 조회 경로: `wemix/admin.go: NodeNameForPeerID()` → `wemix/miner/miner.go: NodeNameForPeerIDFunc` (프로토콜 레이어가 `wemix/admin`을 직접 import하지 않도록 하는 함수 변수 IoC).
- 신뢰 경계는 **핸들러 한 곳에 모여 있다.** 다운스트림(`getMiners`, `collectMinerStates`, `miningPeers`)은 그대로 node name을 키로 쓴다. 여기서 검증을 빼고 하위에서 방어하려는 리팩터링은 금지.
- 회귀 테스트: `TestNodeNameRebind_PreventsQuorumForgery`, `TestRegression_SpoofedStatusExPoisonsWorkKey`

### 불변식 2 — RLP에서 생략된 `*big.Int`는 nil이다

RLP 페이로드에서 필드를 빼면 `*big.Int`가 nil로 디코드된다. 크래프트된 메시지 한 통이 패닉을 일으킬 수 있는 지점이 세 곳 있었다:

| 위치 | 방어 |
|------|------|
| `handleStatusEx` decode 직후 | `status.LatestBlockHeight == nil` → 즉시 거부. 다운스트림 `wemix/miner_limit.go: electNextMiner`가 `.Int64()`를 nil 가드 없이 호출하기 때문 |
| `handleStatusEx` 내부 goroutine | `status.LatestBlockTd != nil &&` 를 `Cmp(td)` 앞에 둠 |
| `wemix/api/api.go: Clone()` | `safeBig()` 헬퍼로 `LatestBlockHeight`/`LatestBlockTd`/`RttMs` 복사. `new(big.Int).Set(nil)`은 패닉 |

정상 송신자는 `getMinerStatus`에서 `header.Number`로 항상 채우므로, nil은 오직 크래프트 페이로드에서만 도달한다. **경계에서 거부**하는 것이 정책이며, 호출처마다 가드를 다는 방식으로 되돌리지 말 것.

회귀 테스트: `TestRegression_NilLatestBlockHeightPanicsElectNextMiner`, `TestNilLatestBlockHeightGuard_RejectedAtHandler`, `TestRegression_NilLatestBlockTdPanicsHandler`, `TestNilLatestBlockTdGuard_PreventsHandlerPanic`, `TestWemixMinerStatus_Clone_NilSafe`

### 불변식 3 — `wemixWorkKey`에 쓰기 전 3중 검증

`syncCheck`의 도달성 / 해시·높이 정합 / 높이 역행 가드 (§12 표) 세 가지는 **각각 다른 구멍을 막는다.** 하나라도 빼면:

- 도달성 없음 → 로컬에 없는 해시가 기록되어 모든 검증자의 `acquireTokenSync`가 영구 `ErrInvalidWork`
- 해시·높이 정합 없음 → (진짜 해시 + 가짜 높이) 조합이 나머지 둘을 통과해 내부 모순 값이 기록됨
- 높이 역행 없음 → 오래된 canonical 해시로 마이닝 타깃을 뒤로 밀어 블록 생산 정지

회귀 테스트: `TestRegression_StaleConsensusHeightBlocked`, `TestRegression_EndToEndAttackChain`

### 의도적으로 채택하지 않은 방어

리뷰 중 도입했다가 되돌린 것들이다. **다시 제안하기 전에 아래 근거를 확인할 것.**

| 제안 | 철회 이유 |
|------|-----------|
| StatusEx per-peer rate limit (5초 최소 간격) | 1초 블록 환경에서 `admin.wemixNodes` RPC를 블록 주기로 폴링하는 운영 대시보드의 정상 응답을 ~80% 드롭시킨다. 상수를 조정해도 트레이드오프를 벗어날 수 없다 (폴링 주기 이상이면 드롭 발생, 이하면 DoS 방어 무의미). 원래 막으려던 정족수 위조는 불변식 1이 이미 커버 |
| `release()` 시 `wemixWorkKey` 자가 복구 (`maybeRecoverWorkKey`) | 느린 동기화 중이거나 소수 포크에 있는 파트너가 **정상 etcd 값을 자기 lagging head로 덮어써** 클러스터 전체를 오염시킨다. 도달성 검사만으로는 이 둘을 구분할 수 없음 |
| `findConsensusBlock` 결과에 정족수 요구 (work-ahead catch-up 판정) | 연결된 악성 피어 1대가 임의 값을 echo할 수 있으므로, all-honest가 아닌 어떤 정족수 크기도 공격자 메시지 1건에 영향받는다. 현재 정책은 side-effect 최소화 + 다운스트림 가드에 위임 |

---

## 16. CI/CD

### GitHub Actions

| 워크플로우 | 트리거 | 내용 |
|-----------|--------|------|
| `dev-ci.yml` *(또는 유사)* | PR → `dev` 브랜치 | build, lint, test-short |
| `release.yml` | tag push | gwemix.tar.gz 빌드 & 배포 |

### CI 검사 항목

1. **build**: `make gwemix` 빌드 성공 여부
2. **lint**: `make lint` 통과 여부
3. **test-short**: `make test-short` 통과 여부

> PR 머지 전 위 3가지를 로컬에서 먼저 확인할 것: `make lint && make test-short && make gwemix`

### Docker

```
Dockerfile          — 표준 geth 이미지
Dockerfile.alltools — geth + 전체 부속 바이너리
Dockerfile.wemix    — gwemix 전용 (RocksDB 정적 빌드용 빌더 이미지)
```

`make gwemix-linux`가 `Dockerfile.wemix`를 사용해 Linux용 RocksDB 정적 바이너리를 생성한다.

---

## 17. 제네시스 생성

### 도구 / 입력

`cmd/gwemix governancedeploy` 서브커맨드 + `wemix/scripts/genesis-template.json` + `wemix/scripts/config.json.example` 조합으로 **신규 네트워크 부트스트랩 시** 사용한다.

이미 운영 중인 Mainnet/Testnet은 `core/wemix_genesis.go` 안에 임베드된 JSON (alloc + chainConfig)을 그대로 사용.

### 제네시스 alloc 핵심

```
Registry (≈0x0…) — owner: deployer
Gov / GovImp     — UUPS proxy + implementation
Staking / StakingImp — UUPS proxy + implementation
BallotStorage / BallotStorageImp
EnvStorage / EnvStorageImp
NCPExit / NCPExitImp        (Pangyo 이후)
초기 멤버 계정 잔액 (대규모)
```

### gwemix governancedeploy 흐름

`cmd/gwemix/governancedeploy.go:66 deployGovernanceContracts(ctx)` — CLI 등록은 `cmd/gwemix/wemixcmd.go`의 `wemix deploy-governance` 서브커맨드다.

```
gwemix wemix deploy-governance [--password <file>] [--url <url>] [--gas <gas>] [--gasprice <gas-price>] \
    <config-file> <account-file> [lockAmount]
```

```
1. 위치 인자 파싱: 2개면 lockAmount = gov.DefaultInitEnvStorage.STAKING_MIN, 3개면 3번째 인자(10진수, 0보다 커야 함)
2. 사용자가 제공한 config (StakingReward, Maintenance, FeeCollector 등) 파싱
3. EOA 키 로드 → bind.TransactOpts 생성
4. deployGovernance(client, opts, lockAmount, configFile)
   ├─ Registry / Staking / BallotStorage / EnvStorage / Gov 프록시 + 구현 배포
   ├─ EnvStorage 초기값 주입 (gov.InitEnvStorage)
   ├─ Registry에 모든 도메인 등록
   └─ 최초 멤버 등록 (Staking에 lockAmount 락업 → Gov에 멤버로 add)
5. 최종 Registry/Staking/EnvStorage/BallotStorage/Gov 주소 출력
```

> **lockAmount 섀도잉 주의** (v0.10.15, #190): 인자가 3개인 분기에서 `lockAmount, ok := ...`로 쓰면 바깥 `lockAmount`가 가려져 nil인 채로 남고, 이어지는 배포에서 panic이 난다. `var ok bool` 후 `=`로 대입해야 한다.

### 신규 네트워크 부트스트랩 절차

1. `wemix/scripts/config.json.example` 복사 → 운영용 config 작성 (validator 주소, 보상 풀 주소, 초기 staking 등)
2. `wemix/scripts/genesis-template.json` 기반으로 alloc/chainConfig 채우기
3. `gwemix init <genesis.json>` 으로 chaindata 초기화
4. `gwemix wemix deploy-governance <config-file> <account-file> [lockAmount]`로 거버넌스 컨트랙트 배포
5. 출력된 Registry 주소를 `WemixGenesisFile` 또는 환경변수에 고정

---

## 18. 주요 설정값 참조

### 가스/수수료 (대부분 EnvStorage 동적, 일부 protocol_params.go)

| 파라미터 | 출처 | 설명 |
|----------|------|------|
| `getBlockCreationTime()` | EnvStorageImp | 블록 주기 (ms) |
| `getBlockRewardAmount()` | EnvStorageImp | 기본 블록 보상 |
| `getBlockRewardDistributionMethod()` | EnvStorageImp | `(blockProducer, stakingReward, ecosystem, maintenance)` 4-way 비율 |
| `getMaxPriorityFeePerGas()` | EnvStorageImp | 최대 tip cap |
| `getGasLimitAndBaseFee()` | EnvStorageImp | `(gasLimit, baseFeeMaxChangeRate, gasTargetPercentage)` |
| `getMaxBaseFee()` | EnvStorageImp | baseFee 상한 |
| `getMaxIdleBlockInterval()` | EnvStorageImp | 마이너 idle 한계 |
| `MaxBlockSize` | `params/protocol_params.go` | RLP 인코딩 블록 상한 8,388,608 바이트 (EIP-7934, §12) |
| `MaxTransactionSize` | `params/protocol_params.go` | tx 크기 상한 262,144 바이트 |
| `maxMessageSize` | `eth/protocols/eth/protocol.go` | eth 프로토콜 메시지 상한 10 MiB (v0.10.14까지 100 MiB) |

### Staking (`wemix/governance-contract/contracts/Staking.sol`)

| 항목 | 값 (`DefaultInitEnvStorage`) |
|------|----------------------------|
| `STAKING_MIN` | 초기 락업 최소량 |
| `BALLOT_DURATION_MIN_MAX` | 투표 지속 시간 범위 |
| `GAS_PRICE_MIN_MAX` | gasPrice 범위 |

### 하드포크 (요약)

| 포크 | Mainnet | Testnet |
|------|--------:|--------:|
| Pangyo | 0 | 10,000,000 |
| Applepie | 20,476,911 | 26,240,268 |
| Brioche | 53,525,500 | 59,414,700 |
| Croissant | TBD | TBD |

---

## 주의사항 요약

### 절대 수정 금지
1. **`wemix/bind/gen_*_abi.go` 직접 수정 금지** — `wemix/governance-contract/`에서 Solidity 재컴파일 후 abigen으로 재생성
2. **`gen_*.go`, `*.pb.go` 직접 수정 금지** — 도구로 재생성
3. **`core/wemix_genesis.go`의 임베디드 alloc**은 운영 네트워크 상태이므로 변경 금지 — 신규 네트워크는 별도 제네시스 파일 사용
4. **`wemix/governance-contract/contracts/mock/*.sol` 수정 금지** — 취약했던 시점을 보존한 red→green 회귀 픽스처 (§6)

### 하드포크/업그레이드
5. **하드포크 추가 시 블록 번호 순서 검증** — 이전 포크 블록보다 반드시 크거나 같아야 함 (`CheckConfigForkOrder`)
6. **거버넌스 컨트랙트 ABI 변경 시 4종 동반 갱신** — Solidity / Go 바인딩 / 제네시스 / 운영 절차 (§8)
7. **Brioche 하드포크 활성 후 보상 계산 경로 분기** — `BriocheConfig.GetBriocheBlockReward` 사용. halving 횟수는 **1부터** 시작 (§11)

### 트랜잭션/보안
8. **Fee Delegation `setSignatureValues`는 FeePayer 서명** — Sender 서명이 아님 (§10)
9. **`Applepie` 이전 블록에서 Fee Delegation tx 금지** — txpool에서 거부되어야 함
10. **FeePayer 검증은 `types.RecoverFeePayer` 단일 진입점** — RPC 레이어에 중복 검증 되살리지 말 것. 분기 기준은 FeePayer nil 여부가 아니라 **tx 타입** (§10)
11. **`SetSenderTx`의 AccessList는 `make` 후 `copy`** — 사전 할당 없이 `copy`하면 전부 유실 (§10)
12. **`StatusEx`의 `NodeName`은 거버넌스 조회로만 결정** — 페이로드 값을 신뢰하면 정족수 위조 가능 (§15)
13. **RLP `*big.Int` nil 가드는 핸들러 경계에서** — 호출처마다 가드하는 방식으로 되돌리지 말 것 (§15)
14. **`wemixWorkKey` 기록 전 3중 검증 유지** — 도달성 / 해시·높이 정합 / 높이 역행. 각각 다른 구멍을 막음 (§12, §15)
15. **토큰 획득과 `etcdResetWork` 사이에 `Till` 변경 금지** — CAS가 항상 실패한다. 구 `renew()`는 삭제됐지만 TTL 갱신을 다시 넣을 때도 같은 제약 (§12)
16. **멈춘 워커는 마이닝 토큰을 잡지 않는다** — `commitWork`의 `isRunning()` 가드를 `AcquireMiningToken` 앞에 유지 (§12)
17. **블록 크기 상한(EIP-7934) 수신·생성 양쪽 유지** — `ValidateBody`의 `ErrBlockOversized`, 패킹 루프의 `txFitsSize`. 생성 여유분 1,000,000 바이트를 없애지 말 것 (§12)
18. **`timeIt` 타임스탬프 하한은 `parent.Time()`** — `parent.Number()`와 비교하던 버그로 되돌리지 말 것 (§12)
19. **거버넌스 호출은 항상 Registry 경유** — 컨트랙트 주소 하드코딩 금지 (UUPS 업그레이드로 주소 보존, 구현만 변경)

### 운영
20. **`etcdAutoJoin`의 `gap == 0` 가드 유지** — 빼면 0 나눗셈 panic으로 프로세스가 죽는다 (§13)
21. **`wemix/admin.go`는 약 42KB 단일 파일** — 함수 단위로 신중하게 수정, 무관한 영역 동시 편집 금지
22. **wemixminer 함수 변수 주입은 `wemix/admin.go` 초기화 시점에 1회만** — 런타임 재설정 금지

### 빌드/배포
23. **PR 전 로컬 확인** — `make lint && make test-short && make gwemix`
24. **Go 버전 1.19 고정** — `go.mod` 변경 시 의존성 호환성 확인
25. **RocksDB 통합은 Linux 빌드에서만 활성** — darwin/Windows 빌드 시 `USE_ROCKSDB=NO` 자동 적용
26. **`logrot` 동작 변경은 이 저장소가 아님** — `cmd/logrot/main.go`는 wrapper, 본체는 외부 모듈 `github.com/charlanxcc/logrot`
