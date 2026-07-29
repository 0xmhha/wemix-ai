# Wemix Governance Contract Flow

거버넌스 컨트랙트가 어떻게 배포되고, 초기화되며, 런타임에 호출·업그레이드되는지 정리.

---

## 1. Core Data Structures

### ChainConfig (`params/config.go`)

```go
type ChainConfig struct {
    ChainID *big.Int
    // ... 이더리움 표준 포크 ...

    // Wemix 하드포크
    PangyoBlock    *big.Int  // 거버넌스 활성화 임계
    ApplepieBlock  *big.Int  // Fee Delegation 활성
    BriocheBlock   *big.Int  // 보상 곡선 변경
    CroissantBlock *big.Int  // WBFT 전환 (Mainnet/Testnet 모두 아직 nil)

    Brioche *BriocheConfig    // halving 파라미터
    // ...
}
```

### BriocheConfig (`params/config.go:433~`)

```go
type BriocheConfig struct {
    BlockReward       *big.Int  // 초기 블록 보상 (설정 시 defaultReward를 덮어씀)
    FirstHalvingBlock *big.Int  // 첫 halving 시작 블록 (nil → halving 비활성)
    HalvingPeriod     *big.Int  // 반감 주기 (블록 수)
    FinishRewardBlock *big.Int  // 이 블록 이후 보상 0 (nil → 무한 지속)
    HalvingTimes      uint64    // 최대 반감 횟수 (0 → halving 없음)
    HalvingRate       uint32    // 반감율 (% — 100이면 무반감, >100이면 증가)
}
```

> `HalvingTimes`/`HalvingRate`는 `*big.Int`가 아니라 `uint64`/`uint32`다. 반감 횟수는 `min(1 + elapsed/HalvingPeriod, HalvingTimes)`로 **1부터** 센다.

### Registry Domain Keys (`wemix/bind/const.go`)

```go
const (
    REGISTRY          = "Registry"
    GOV               = "Gov"
    GOV_IMP           = "GovImp"
    STAKING           = "Staking"
    STAKING_IMP       = "StakingImp"
    BALLOTSTORAGE     = "BallotStorage"
    BALLOTSTORAGE_IMP = "BallotStorageImp"
    ENVSTORAGE        = "EnvStorage"
    ENVSTORAGE_IMP    = "EnvStorageImp"
    NCPEXIT           = "NCPExit"
    NCPEXIT_IMP       = "NCPExitImp"

    DOMAIN_Gov           = "GovernanceContract"
    DOMAIN_Staking       = "Staking"
    DOMAIN_BallotStorage = "BallotStorage"
    DOMAIN_EnvStorage    = "EnvStorage"
    DOMAIN_NCPExit       = "NCPExit"

    // 분배 풀
    DOMAIN_StakingReward = "StakingReward"
    DOMAIN_Ecosystem     = "Ecosystem"
    DOMAIN_Maintenance   = "Maintenance"
    DOMAIN_FeeCollector  = "FeeCollector"
)
```

---

## 2. Path A — Genesis Initialization (Block 0)

운영 중인 Mainnet/Testnet 노드가 신규 datadir에서 시작할 때.

### 호출 흐름

```
gwemix init <genesis.json>
  │
  ├─ genesis.json 파싱 (또는 core/wemix_genesis.go 임베디드)
  │     → ChainConfig + Alloc (대규모: 초기 EOA + 컨트랙트 알록)
  │
  ├─ SetupGenesisBlockWithOverride()        core/genesis.go
  │     │
  │     ├─ Alloc 검증 (잔액·코드 일관성)
  │     │
  │     └─ ToBlock() / Commit()
  │           → stateDB에 컨트랙트 코드 + 스토리지 슬롯 기록
  │           → stateRoot 계산 → genesis header에 포함
  │
  └─ blockchain.go: WriteHeadBlock(0)
```

### Genesis Alloc 핵심 구성

운영 네트워크의 제네시스에는 다음이 사전 배포되어 있다:

| 도메인 | 프록시 알록 | 구현 알록 | 비고 |
|--------|-----------|----------|------|
| Registry | 단일 컨트랙트 | (없음) | Ownable, 도메인↔주소 매핑 |
| Gov | 프록시 | GovImp | UUPS — `upgradeTo`로 구현 교체 |
| Staking | 프록시 | StakingImp | UUPS |
| BallotStorage | 프록시 | BallotStorageImp | UUPS |
| EnvStorage | 프록시 | EnvStorageImp | UUPS |
| NCPExit | 프록시 | NCPExitImp | Pangyo 이후 |

각 알록 항목은 `{code, balance, storage}` 형태로 `core/wemix_genesis.go`의 JSON 안에 들어 있다.

### 초기 스토리지 슬롯 (예시)

```
Registry.contracts[keccak256("GovernanceContract")] = <Gov proxy addr>
Registry.contracts[keccak256("Staking")]            = <Staking proxy addr>
Registry.contracts[keccak256("EnvStorage")]         = <EnvStorage proxy addr>
...
EnvStorageImp._uintStorage[keccak256("blockRewardAmount")] = 1e18
EnvStorageImp._uintStorage[keccak256("blocksPer")]         = 100
...
Staking._lockedBalanceOf[member1] = 1e23
Gov._memberList[1] = member1
...
```

---

## 3. Path B — Runtime Deployment via gwemix

신규 네트워크 부트스트랩 시 (Mainnet/Testnet은 이미 완료된 단계, 개발/QA 환경에서만 사용).

### `cmd/gwemix governancedeploy` 흐름

파일: `cmd/gwemix/governancedeploy.go:66 deployGovernanceContracts(ctx)`

```
deployGovernanceContracts(ctx)
  │
  ├─ ctx에서 키 파일·비밀번호·config.js 경로 파싱
  │
  ├─ lockAmount = gov.DefaultInitEnvStorage.STAKING_MIN
  │
  └─ deployGovernance(client, opts, lockAmount, configFile)
       │
       ├─ Registry 배포 → registry.address
       │
       ├─ EnvStorageImp 배포 → setReg(registry)
       │     → registry.setContractDomain("EnvStorage",    envStorageProxy)
       │     → registry.setContractDomain("EnvStorageImp", envStorageImpl)
       │
       ├─ BallotStorageImp 배포 → 동일 패턴
       │
       ├─ StakingImp 배포 → 동일 패턴 (Staking 프록시 별도)
       │
       ├─ GovImp 배포 → Gov 프록시 → registry 등록
       │     → 초기 owner 권한 grant
       │
       ├─ env gov.InitEnvStorage 호출 → EnvStorage 초기값 설정 일괄
       │     blocksPer, blockReward, distribution, gasLimit, baseFee 등
       │
       ├─ 분배 풀 주소 등록 (옵션)
       │     domains[gov.DOMAIN_StakingReward] = cfg.StakingReward
       │     domains[gov.DOMAIN_Maintenance]   = cfg.Maintenance
       │     domains[gov.DOMAIN_FeeCollector]  = cfg.FeeCollector
       │     domains[gov.DOMAIN_Ecosystem]     = cfg.Ecosystem
       │
       ├─ 최초 멤버 등록
       │     staking.deposit{value: lockAmount}
       │     gov.addMember(member1, name1, enode1)
       │
       └─ 출력
           Registry      0x...
           Staking       0x... (proxy)
           EnvStorage    0x... (proxy)
           BallotStorage 0x... (proxy)
           Gov           0x... (proxy)
```

### configFile 형식 (`wemix/scripts/config.json.example` 참조)

```json
{
  "members": [
    {"addr": "0x...", "name": "validator-1", "stake": "1000000000000000000"}
  ],
  "stakingReward": "0x...",
  "maintenance":   "0x...",
  "feeCollector":  "0x...",
  "ecosystem":     "0x..."
}
```

---

## 4. Runtime Call Flow

### 노드 시작 시 거버넌스 핸들 획득

```
node start
  │
  ▼
wemix.NewWemixAdmin(stack, registryAddr, ...)
  │
  ├─ ethclient.Dial() → client
  │
  ├─ bind.NewRegistry(registryAddr, client) → contracts.Registry
  │
  ├─ governance := contracts.Registry.GetContractAddress(opts, keccak("GovernanceContract"))
  │     → bind.NewGovImp(governance, client) → contracts.GovImp
  │
  ├─ staking := contracts.Registry.GetContractAddress(opts, keccak("Staking"))
  │     → bind.NewStakingImp(staking, client) → contracts.StakingImp
  │
  ├─ envStorage := contracts.Registry.GetContractAddress(opts, keccak("EnvStorage"))
  │     → bind.NewEnvStorageImp(envStorage, client) → contracts.EnvStorageImp
  │
  └─ ballotStorage := contracts.Registry.GetContractAddress(opts, keccak("BallotStorage"))
        → bind.NewBallotStorageImp(ballotStorage, client) → contracts.BallotStorageImp
```

### 매 블록 합의 파라미터 조회 (`wemix/admin.go:getBlockBuildParameters`)

```
height ──┐
         ▼
EnvStorageImp.GetBlockCreationTime(opts)    → blockInterval
EnvStorageImp.GetBlocksPer(opts)            → blocksPer (보상 분배 주기)
EnvStorageImp.GetMaxIdleBlockInterval(opts) → maxIdle
EnvStorageImp.GetBlockRewardAmount(opts)    → blockReward
EnvStorageImp.GetMaxPriorityFeePerGas(opts) → maxPriorityFee
EnvStorageImp.GetGasLimitAndBaseFee(opts)   → (gasLimit, baseFeeMaxChangeRate, gasTarget%)
EnvStorageImp.GetMaxBaseFee(opts)           → maxBaseFee
```

### 매 블록 보상 분배 (`wemix/admin.go:distributeRewards`)

```
distributeRewards(height, rp, blockReward, fees)
  │
  ├─ 1. Brioche 이전: blockReward = EnvStorageImp.GetBlockRewardAmount()
  │     Brioche 이후: blockReward = BriocheConfig.GetBriocheBlockReward(defaultReward, height)
  │
  ├─ 2. EnvStorageImp.GetBlockRewardDistributionMethod() → (mB, mS, mE, mM)
  │     기본: (40, 10, 10, 40)  // %  — 거버넌스 투표로 변경 가능
  │
  ├─ 3. 분배 계산
  │     blockProducer: blockReward * mB / 100 + fees  // 수수료는 BP에게
  │     stakingReward: blockReward * mS / 100
  │     ecosystem:     blockReward * mE / 100
  │     maintenance:   blockReward * mM / 100
  │
  └─ 4. []reward{} 반환 → state_processor에서 잔액 가산
```

> **수수료 전액 BP**: `fees`는 트랜잭션 수수료 합계로, 블록 프로듀서에게 전부 귀속 (FeeCollector 사용 시 별도 정책 가능).

### 멤버십 동기화 (`wemix/sync.go`)

```
loadMiningToken()
  │
  ├─ etcd에서 mining-token 키 조회
  │     → 현재 토큰 보유자 / 만료 시간 확인
  │
  ├─ 자기 자신이 토큰 보유자 && 미만료
  │     → 그대로 진행, 블록 생성 가능
  │
  ├─ 만료되었거나 다른 멤버 보유 중
  │     → findConsensusBlock(): 다수 멤버가 동의하는 블록까지 동기화 후 토큰 획득 시도
  │
  └─ acquireTokenSync(ctx, height, hash, parentHash, ttl)
        → 다음 블록 권한 획득
```

---

## 5. Contract Upgrade (UUPS)

### 업그레이드 모델

```
Proxy contract (e.g. Gov)            Implementation (e.g. GovImp v1)
─────────────────                     ─────────────────────
storage [...]            ────────►   logic functions (delegatecall)
implementation: GovImp v1            upgradeTo(GovImp v2)
```

`Gov.sol`은 ERC1967 프록시이며, `GovImp.sol`은 `UUPSUpgradeable`을 상속한다. `upgradeTo(newImpl)`는 거버넌스 투표를 통과해야만 실행된다.

### 업그레이드 시나리오

1. 새 구현 컨트랙트 작성 (`GovImpV2.sol` 등)
2. 컴파일 + 배포 → `newImpl` 주소
3. `Gov` 인스턴스에서 `proposeUpgrade(newImpl)` 또는 동등 발의 함수 호출
4. 멤버들이 `vote(ballotId, agree=true)` 호출
5. 정족수 도달 시 `executeBallot(ballotId)` → 내부적으로 `upgradeTo(newImpl)` 호출
6. 이후 `Gov` 프록시 호출이 새 구현으로 위임됨 (스토리지 보존, 로직만 교체)

### Go 측 영향

- 프록시 주소는 불변 → `wemix/admin.go`의 핸들은 그대로 사용 가능
- ABI에 새 함수가 추가되면 `wemix/bind/gen_gov_abi.go`를 재생성해야 Go에서 호출 가능
- 기존 함수 시그니처는 변경 금지 (Go 바인딩과 운영 코드 깨짐) — 새 함수로 추가만

---

## 6. GovImp 보안 불변식 (제거된 기능 & W1G 대응)

거버넌스 컨트랙트를 수정하거나 "예전에 있던 기능"을 복원하려 할 때 먼저 확인할 것. 회귀 테스트는 전부 `wemix/governance-contract/test/gov_test.go`에 있다.

### 6.1 제거된 기능 — 임의 실행 발의 (`Execute` ballot)

`addProposalToExecute`는 **검증 불가능한 calldata로 임의의 컨트랙트 호출을 실행**할 수 있어 통째로 제거되었다. 함께 사라진 것:

| 대상 | 파일 |
|------|------|
| `addProposalToExecute()` | `contracts/GovImp.sol` |
| `BallotTypes.Execute` enum 값 | `contracts/abstract/BallotEnums.sol` |
| `createBallotForExecute()`, `getBallotExecute()` | `contracts/interface/IBallotStorage.sol`, `contracts/storage/BallotStorageImp.sol` |

> **복원 금지.** 거버넌스로 실행해야 할 새 동작이 있으면, 임의 calldata 실행이 아니라 **전용 발의 타입 + 전용 실행 경로**로 추가한다. `BallotTypes`에 값을 되살리면 enum 순서가 바뀌어 기존 투표 저장소와도 어긋난다.

### 6.2 멤버 인덱스 무결성 (`removeMember`)

`removeMember`의 인덱스 해석은 staker 주소가 아니라 **실제 reward / voter 주소를 조회 키로** 사용해야 한다. staker 키로 조회하면 staker·voter·reward가 분리된 멤버에서 잘못된 인덱스가 나와 스토리지가 깨진다.

- 노드 스토리지 포인터 바인딩은 **실제 노드 인덱스가 확정된 뒤에** 수행 (앞당기면 데이터 손상)
- 제거 인덱스는 종류별로 별도 변수 사용, 각 인덱스에 명시적 검증 가드
- 회귀 테스트: `TestGov_IndexCorruptionAfterRemoveMember`

### 6.3 CertiK W1G 대응 불변식

| ID | 불변식 | 회귀 테스트 |
|----|--------|------------|
| W1G-01 | add-member 발의가 **실행되는 시점에** 노드 유일성을 재검증한다 (발의 시점 검사만으로는 그 사이 중복이 들어올 수 있음) | `TestW1G01_DuplicateNodeRejectedAtExecution`, `TestW1G01_Legacy_DuplicateNode_RedThenGreen` |
| W1G-02 | 오래된 제거 발의가 뒤늦게 실행되어도 **마지막 남은 멤버는 제거되지 않는다** (거버넌스 공백 방지) | `TestW1G02_StaleRemovalCannotEmptyGovernance`, `TestW1G02_Legacy_EmptyGovernance_RedThenGreen` |
| W1G-03 | 재초기화(reInit)·마이그레이션 시 **노드 유일성 마커를 보존**한다. 인덱스는 0이 아니라 `1..N` | `TestW1G03_MigrateFromLegacyIntegrity`, `TestW1G03_PreMarker_ReInitOffByOne_RedThenGreen`, `TestW1G03_Legacy_MigratePreservesSeparation` |
| W1G-04 | 멤버 변경·제거는 **실제 staker 키**를 요구한다 (voter 전용 주소로는 불가) | `TestW1G04_StakerVoterSeparationLifecycle`, `TestW1G04_VotedPathRejectsVoterOnlyTarget`, `TestW1G04_RewardSeparationLedger`, `TestW1G04_Legacy_Slot0Poison_RedThenGreen` |

외부 revert 메시지와 이벤트 문자열은 변경되지 않았다 — 운영 도구 호환성 유지를 위한 의도적 제약이다.

### 6.4 red→green 픽스처 (수정 금지)

| 파일 | 역할 |
|------|------|
| `contracts/mock/GovImpLegacy.sol` | 취약했던 시점의 GovImp. 이 위에 원장을 쌓아 문제를 재현한 뒤 프록시를 신구현으로 업그레이드해 해소를 확인한다 |
| `contracts/mock/GovImpPreMarker.sol` | 노드 유일성 마커가 비어 있는 상태 — W1G-03 off-by-one의 실제 검증력을 담당 |

두 파일은 **버그를 그대로 보존하는 것이 존재 이유**다. 최신 GovImp에 맞춰 "고치면" 회귀 테스트가 무의미해진다. `TestW1G_LegacyUpgrade_FullLifecycle`이 레거시→신구현 업그레이드 전 과정을 검증한다.

---

## 7. Hardfork ↔ Governance Interaction

| 하드포크 | 거버넌스 영향 |
|----------|---------------|
| Pangyo | `Gov`/`Staking` 활성화. 이 블록 이전에는 거버넌스 컨트랙트가 있어도 마이닝 권한이 EOA 화이트리스트 기반 |
| Applepie | Fee Delegation tx 활성. 거버넌스 컨트랙트 자체는 변경 없음 |
| Brioche | 블록 보상 계산 경로 변경 (코드 분기). EnvStorage `getBlockRewardAmount`는 그대로 사용 가능하지만 `BriocheConfig`가 덮어씀. NCPExit 컨트랙트 도입도 이 즈음 |
| Croissant | TBD |

하드포크가 거버넌스 컨트랙트 자체를 교체하지는 않는다 (UUPS 업그레이드로 처리). 다만 **거버넌스가 노출하는 파라미터가 새로 추가되면**:

1. EnvStorageImp에 새 getter 추가 (Solidity)
2. abigen으로 Go 바인딩 재생성
3. `wemix/admin.go`에서 새 getter 호출 추가
4. 하드포크 블록 이후에만 호출 분기

---

## 8. File Reference

| 파일 | 역할 |
|------|------|
| `core/wemix_genesis.go` | Mainnet/Testnet 제네시스 JSON (alloc 포함) |
| `core/genesis.go` | 제네시스 블록 빌드, alloc → stateDB 반영 |
| `params/config.go` | ChainConfig, BriocheConfig, 하드포크 블록 |
| `params/wemix_config.go` | Wemix 부트노드, `WemixGenesisFile` 전역 |
| `cmd/gwemix/governancedeploy.go` | 신규 네트워크 거버넌스 배포 커맨드 |
| `wemix/bind/const.go` | 도메인/컨트랙트 이름 상수 |
| `wemix/bind/gen_*_abi.go` | abigen 산출 Go 바인딩 (수동 편집 금지) |
| `wemix/admin.go` | wemixAdmin 본체 — 거버넌스 조회·보상 분배·멤버십 |
| `wemix/sync.go` | 마이닝 토큰 로딩, 멤버십 동기화 |
| `wemix/etcdutil.go` | 임베디드 etcd 운영 |
| `wemix/miner/miner.go` | wemix 보상 분배를 표준 miner에 주입 |
| `wemix/governance-contract/contracts/Registry.sol` | 도메인 매핑 컨트랙트 |
| `wemix/governance-contract/contracts/GovImp.sol` | 거버넌스 구현 (UUPS) |
| `wemix/governance-contract/contracts/storage/EnvStorageImp.sol` | 체인 파라미터 저장소 (UUPS) |
| `wemix/governance-contract/contracts/StakingImp.sol` | 스테이킹 구현 (UUPS) |
| `wemix/governance-contract/contracts/storage/BallotStorageImp.sol` | 투표·발의 영구 저장 |
| `wemix/governance-contract/contracts/abstract/BallotEnums.sol` | 발의 종류 enum (`Execute` 제거됨 — §6.1) |
| `wemix/governance-contract/contracts/interface/IBallotStorage.sol` | BallotStorage 인터페이스 |
| `wemix/governance-contract/contracts/NCPExitImp.sol` | NCP 퇴출 처리 (UUPS) |
| `wemix/governance-contract/contracts/TestnetGovImp.sol` | Testnet 전용 GovImp 변형 |
| `wemix/governance-contract/contracts/mock/GovImpLegacy.sol` | red→green 회귀 픽스처 — **수정 금지** (§6.4) |
| `wemix/governance-contract/contracts/mock/GovImpPreMarker.sol` | 노드 마커 미설정 상태 픽스처 — **수정 금지** (§6.4) |
| `wemix/governance-contract/compiler.go` | solc 0.8.14 호출 헬퍼 |
| `wemix/governance-contract/test/gov_test.go` | 거버넌스 시나리오 + W1G 회귀 테스트 |
| `wemix/governance-contract/test/gov_bind_test.go` | abigen 바인딩 정합성 |
