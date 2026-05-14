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

### 운영
15. [CI/CD](#15-cicd)
16. [제네시스 생성](#16-제네시스-생성)
17. [주요 설정값 참조](#17-주요-설정값-참조)

---

## 1. 프로젝트 개요

| 항목 | 값 |
|------|-----|
| 바이너리 이름 | `gwemix` |
| Go 모듈 경로 | `github.com/ethereum/go-ethereum` *(geth fork — 모듈명 그대로 유지)* |
| Go 버전 | 1.19 (go.mod) |
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
  etcdutil.go        ← etcd 임베디드 운영 + 마이닝 토큰
  miner_limit.go     ← 마이너 상태 수집
  sync.go            ← 멤버십 동기화 (loadMiningToken, findConsensusBlock)
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

파일: `wemix/admin.go:1557~` (`init()` 또는 setup 시점에 함수 변수 주입)

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

- `core/blockchain_test.go`, `core/state_processor_test.go`
- `cmd/gwemix/*_test.go` (configuration / governance deploy 검증)
- `wemix/rewards_test.go` — Brioche 하드포크 보상 분배 검증
- `wemix/bind/backends/wemix_simulated_test.go` — 거버넌스 시뮬레이션 백엔드
- `wemix/governance-contract/test/` — Solidity 컨트랙트 hardhat/foundry 테스트

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
| `core/types/feedelegate_dynamic_fee_tx.go` | 트랜잭션 타입 정의 |
| `core/types/transaction.go:48` | `FeeDelegateDynamicFeeTxType = 22` 상수 |
| `core/types/transaction_signing.go` | Sender/FeePayer 서명 처리 |
| `core/state_transition.go` | FeePayer 잔액 차감 처리 |
| `internal/ethapi/api.go` | `SignRawFeeDelegateTransaction()` 등 RPC |
| `internal/ethapi/transaction_args.go` | `FeePayer`, `FV/FR/FS` JSON 필드 |
| `core/tx_pool.go` | Applepie 게이팅 |

---

## 11. Brioche 블록 보상 정책

### 개요

파일: `params/config.go` (`BriocheConfig`, `GetBriocheBlockReward`) — Wemix Brioche 하드포크에서 도입된 **반감(halving) 기반 보상 곡선**.

### BriocheConfig 구조

```go
type BriocheConfig struct {
    BlockReward       *big.Int  // 초기 블록 보상 (Wei)
    FirstHalvingBlock *big.Int  // nil → halving 비활성. 이 블록부터 halving 시작
    HalvingPeriod     *big.Int  // 반감 주기 (블록 수)
    FinishRewardBlock *big.Int  // 이 블록 이후 보상 0 (nil → 무한 지속)
    HalvingTimes      *big.Int  // 최대 반감 횟수
    HalvingRate       *big.Int  // 반감 비율 (% — 50이면 절반)
}
```

### 보상 계산 흐름 (`GetBriocheBlockReward`)

```
1. num >= FinishRewardBlock              → 0
2. FirstHalvingBlock 미설정 또는 num < FirstHalvingBlock
   → defaultReward (= EnvStorageImp.getBlockRewardAmount())
3. elapsed = num - FirstHalvingBlock
4. halvings = min(elapsed / HalvingPeriod, HalvingTimes)
5. reward = BlockReward * (HalvingRate / 100)^halvings
```

### Mainnet vs Testnet 활성 블록

| 항목 | Mainnet | Testnet |
|------|--------:|--------:|
| `BriocheBlock` | 53,525,500 | 59,414,700 |
| `FirstHalvingBlock` | 53,525,500 | 59,414,700 |
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
wemix/sync.go: loadMiningToken()
    ↓
wemix/etcdutil.go:
   ma.acquireToken(ctx, height, ttl)        — 토큰 획득 (CAS 기반)
   ma.acquireTokenSync(ctx, height, hash, parentHash, ttl)
   lck.renew(ctx, ttl)                       — TTL 갱신
   lck.release(ctx)                          — 토큰 반환
   lck.releaseTokenSync(ctx, height, hash, parentHash) — 동기 반환

wemix/spinlock.go: SpinLock — 토큰 임계 영역 보호
```

### 블록 빌드 파라미터

`wemix/admin.go:getBlockBuildParameters(height)`가 EnvStorage에서 다음을 가져와 마이너에 주입:

- `blockInterval` (밀리초)
- `maxBaseFee`, `gasLimit`
- `baseFeeMaxChangeRate`, `gasTargetPercentage`

### 수정 시 주의사항

- **etcd 임베디드**는 노드 프로세스 내부에서 실행 — 별도 클러스터 관리 불필요. `wemix/etcdutil.go` 참조
- **토큰 재진입 금지**: SpinLock 임계 영역 내부에서 etcd 호출은 짧게 (블록 검증 같은 무거운 작업 금지)
- **토큰 갱신 실패 처리**: TTL 만료 시 다른 노드가 토큰을 가져가도록 fail-fast — 무리한 재시도 금지
- **`findConsensusBlock`** (`wemix/sync.go:202`)이 멤버 다수가 동의하는 블록 높이를 찾아 동기화 지점 결정

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

### 임베디드 etcd 설정

```
etcdDir              ← 데이터 디렉토리 (gwemix datadir 하위)
etcdClusterName      ← initial-cluster-token
ListenClientUrls     ← 내부 RPC용
ListenPeerUrls       ← 멤버 간 통신용
```

### 수정 시 주의사항

- **`wemix/etcdutil.go.new`** 파일은 빌드 비참여 — 작업 보관용. **운영 코드는 `etcdutil.go`임에 주의**
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

## 15. CI/CD

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

## 16. 제네시스 생성

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

`cmd/gwemix/governancedeploy.go:66 deployGovernanceContracts(ctx)`:

```
1. 사용자가 제공한 config (StakingReward, Maintenance, FeeCollector 등) 파싱
2. EOA 키 로드 → bind.TransactOpts 생성
3. lockAmount = gov.DefaultInitEnvStorage.STAKING_MIN (기본 락업 금액)
4. deployGovernance(client, opts, lockAmount, configFile)
   ├─ Registry / Staking / BallotStorage / EnvStorage / Gov 프록시 + 구현 배포
   ├─ EnvStorage 초기값 주입 (gov.InitEnvStorage)
   ├─ Registry에 모든 도메인 등록
   └─ 최초 멤버 등록 (Staking에 lockAmount 락업 → Gov에 멤버로 add)
5. 최종 Registry/Staking/EnvStorage/BallotStorage/Gov 주소 출력
```

### 신규 네트워크 부트스트랩 절차

1. `wemix/scripts/config.json.example` 복사 → 운영용 config 작성 (validator 주소, 보상 풀 주소, 초기 staking 등)
2. `wemix/scripts/genesis-template.json` 기반으로 alloc/chainConfig 채우기
3. `gwemix init <genesis.json>` 으로 chaindata 초기화
4. `gwemix governancedeploy --config <config.json>`으로 거버넌스 컨트랙트 배포
5. 출력된 Registry 주소를 `WemixGenesisFile` 또는 환경변수에 고정

---

## 17. 주요 설정값 참조

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

### 하드포크/업그레이드
4. **하드포크 추가 시 블록 번호 순서 검증** — 이전 포크 블록보다 반드시 크거나 같아야 함 (`CheckConfigForkOrder`)
5. **거버넌스 컨트랙트 ABI 변경 시 4종 동반 갱신** — Solidity / Go 바인딩 / 제네시스 / 운영 절차 (§8)
6. **Brioche 하드포크 활성 후 보상 계산 경로 분기** — `BriocheConfig.GetBriocheBlockReward` 사용 (§11)

### 트랜잭션/보안
7. **Fee Delegation `setSignatureValues`는 FeePayer 서명** — Sender 서명이 아님 (§10)
8. **`Applepie` 이전 블록에서 Fee Delegation tx 금지** — txpool에서 거부되어야 함
9. **거버넌스 호출은 항상 Registry 경유** — 컨트랙트 주소 하드코딩 금지 (UUPS 업그레이드로 주소 보존, 구현만 변경)

### 운영
10. **etcd `etcdutil.go.new` 파일은 무시** — 빌드 비참여 (`etcdutil.go`만 운영) (§13)
11. **`wemix/admin.go`는 43KB 단일 파일** — 함수 단위로 신중하게 수정, 무관한 영역 동시 편집 금지
12. **wemixminer 함수 변수 주입은 `wemix/admin.go` 초기화 시점에 1회만** — 런타임 재설정 금지

### 빌드/배포
13. **PR 전 로컬 확인** — `make lint && make test-short && make gwemix`
14. **Go 버전 1.19 고정** — `go.mod` 변경 시 의존성 호환성 확인
15. **RocksDB 통합은 Linux 빌드에서만 활성** — darwin/Windows 빌드 시 `USE_ROCKSDB=NO` 자동 적용
