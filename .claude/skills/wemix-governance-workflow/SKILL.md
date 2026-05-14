---
name: wemix-governance-workflow
description: |
  go-wemix에서 거버넌스 컨트랙트(Registry/Gov/Staking/BallotStorage/EnvStorage/NCPExit)를
  추가·수정·배포하는 엔드-투-엔드 워크플로우.

  Solidity 소스 작성 (wemix/governance-contract/contracts/) →
  solc 0.8.14 컴파일 →
  abigen으로 wemix/bind/gen_*_abi.go 갱신 →
  필요 시 제네시스 alloc 동기화 → params/config.go 하드포크 등록 →
  cmd/gwemix governancedeploy로 배포 흐름까지 안내한다.

  /wemix-review-code 와 함께 사용하면 wemix/governance-contract/, wemix/bind/,
  cmd/gwemix/governancedeploy.go 수정 작업을 효율화한다.

  트리거 키워드: 거버넌스 컨트랙트, Gov, GovImp, Staking, EnvStorage, BallotStorage, NCPExit,
  Registry, governance-contract, governancedeploy, UUPSUpgradeable, 거버넌스 업그레이드,
  새 거버넌스 함수, abigen, gen_*_abi.go, 거버넌스 배포.
trigger-keywords: wemix-governance-workflow, wemix governance, GovImp, EnvStorage, Registry, governancedeploy
user-invocable: true
---

## Instructions

go-wemix 거버넌스 컨트랙트의 추가·수정·배포 작업을 안내한다. 이 스킬은 **레이어별 절차와 불변식**을 명시하여, 한 레이어의 변경이 다른 레이어에 미치는 영향을 누락 없이 추적하게 한다.

### Layer 0 — 사전 점검

작업 시작 전 다음을 확인:

```bash
# 1. solc 0.8.14가 설치되어 있는지
ls ~/.gsolc-select/artifacts/solc-0.8.14/ 2>/dev/null \
  || go run ./wemix/governance-contract/solcdownloader

# 2. 변경 의도 분류
#    [A] 신규 함수 추가 (UUPS 업그레이드 가능)
#    [B] 기존 함수 시그니처 변경 (호환성 깨짐 — 새 함수로 추가 권장)
#    [C] 신규 컨트랙트 도입 (Registry 도메인 추가 필요)
#    [D] 제네시스 초기값 변경 (운영 네트워크 영향)
#    [E] 하드포크와 함께 변경 (게이팅 필요)
```

### Layer 1 — Solidity 소스 변경

위치: `wemix/governance-contract/contracts/`

```
contracts/
├── Registry.sol              ← 도메인↔주소 매핑 (Ownable, 비-UUPS)
├── Gov.sol                   ← 프록시 (ERC1967)
├── GovImp.sol                ← 구현 (UUPSUpgradeable)
├── Staking.sol / StakingImp.sol
├── BallotStorage.sol
├── storage/
│   └── EnvStorageImp.sol     ← 체인 파라미터 (UUPS)
├── NCPExit.sol / NCPExitImp.sol
├── abstract/                 ← 공통 추상 컨트랙트
├── interface/                ← 인터페이스 정의
└── openzeppelin/             ← OZ 의존성 (remappings.txt 참조)
```

#### 변경 유형별 절차

**유형 A: 신규 함수 추가**

```solidity
// GovImpV2.sol (또는 GovImp.sol에 직접 추가)
contract GovImp is AGov, ReentrancyGuardUpgradeable, BallotEnums, EnvConstants, UUPSUpgradeable {
    // 기존 함수들 ...

    // 신규 함수 추가
    function newGovernanceMethod(...) external onlyOwner {
        // ...
    }
}
```

**불변식**:
- 기존 함수 시그니처 / 스토리지 슬롯 레이아웃을 변경하지 않는다 (UUPS 호환성)
- `EnvConstants` 등 공통 상수는 항상 동일 순서로 유지
- 새 스토리지 변수는 **항상 맨 뒤에** 추가 (`__gap` 슬롯 활용 권장)

**유형 B: 기존 함수 시그니처 변경 (지양)**

기존 함수를 변경하면 Go 바인딩과 운영 측 호출 코드가 깨진다. **새 함수로 추가**한 후, 기존 함수를 deprecate 처리할 것.

**유형 C: 신규 컨트랙트 도입**

1. `wemix/governance-contract/contracts/NewContract.sol` 작성 (UUPS 권장)
2. `wemix/bind/const.go`에 도메인/이름 상수 추가:
   ```go
   const (
       NEW_CONTRACT     = "NewContract"
       NEW_CONTRACT_IMP = "NewContractImp"
       DOMAIN_NewContract = "NewContract"
   )
   ```
3. 제네시스 alloc에 새 프록시+구현 주소 추가 (운영 네트워크는 거버넌스 배포로 해결)
4. `cmd/gwemix/governancedeploy.go`에 신규 컨트랙트 배포 흐름 추가

### Layer 2 — Solidity 컴파일

```bash
# wemix/governance-contract/ 디렉토리에서 실행
go run ./compiler.go  # 또는 compile/main.go가 있다면 그것

# 산출물 확인 (bin-runtime / abi)
ls wemix/governance-contract/contracts/*.bin 2>/dev/null
```

**불변식**: solc 버전은 **0.8.14 고정**. `wemix/governance-contract/compiler.go`의 `solcVersion` 상수와 일치해야 한다. 다른 버전 사용 시 바이트코드 해시가 변동되어 제네시스와 어긋난다.

### Layer 3 — Go 바인딩 재생성 (abigen)

위치: `wemix/bind/gen_*_abi.go`

```bash
# wemix/governance-contract/contracts/abigen.go에 generate 디렉티브가 있다면
go generate ./wemix/governance-contract/contracts/...

# 또는 직접 abigen 호출
abigen --abi=GovImp.abi --bin=GovImp.bin --pkg=gov --type=GovImp --out=wemix/bind/gen_gov_abi.go
```

**불변식**:
- `wemix/bind/gen_*_abi.go`는 **수동 편집 금지** — 항상 abigen으로 재생성
- 산출 직후 `goimports -w` / `gofmt -s` 적용 (린트 통과)
- 변경된 ABI를 Go 측에서 사용하려면 `wemix/admin.go` 등 호출 코드도 함께 갱신

### Layer 4 — Go 호출 코드 추가

위치: `wemix/admin.go` (43KB 단일 파일 — 신중하게 수정)

```go
// 새 거버넌스 메서드 호출 예시
func (ma *wemixAdmin) callNewMethod(opts *bind.CallOpts) (*big.Int, error) {
    if ma == nil || ma.contracts == nil || ma.contracts.GovImp == nil {
        return nil, fmt.Errorf("governance contracts not initialized")
    }
    return ma.contracts.GovImp.NewGovernanceMethod(opts)
}
```

**불변식**:
- 컨트랙트 주소는 항상 `Registry.GetContractAddress(opts, keccak256(domainName))` 경유
- 컨트랙트 주소를 하드코딩하지 않는다 (UUPS 업그레이드 시 구현 주소가 바뀌어도 프록시는 불변이라 Registry 매핑이 SSoT)
- `nil` 체크: `ma.contracts` 또는 `ma.contracts.<Field>`가 `nil`일 수 있음 (노드 초기화 순서)

### Layer 5 — 제네시스 / 배포 동기화

#### 신규 네트워크 (개발/테스트)

```bash
# 1. 키 / 비밀번호 / config.js 준비
# 2. gwemix init <genesis.json>
# 3. gwemix governancedeploy --config <config.json>
#    → Registry / Staking / BallotStorage / EnvStorage / Gov 배포
#    → EnvStorage 초기값 주입
#    → 최초 멤버 등록 (Staking 락업 → Gov addMember)
```

#### 운영 네트워크 (Mainnet/Testnet)

신규 컨트랙트나 EnvStorage 신규 키는 **거버넌스 투표로 배포·등록**해야 한다 (제네시스 직접 수정 금지).

```
1. 새 구현 컨트랙트를 EOA로 배포 → newImpl 주소 획득
2. Gov.proposeUpgrade(<targetProxy>, newImpl) 발의
3. 멤버 정족수 vote(agree=true)
4. executeBallot(ballotId) → 내부 upgradeTo(newImpl)
5. Registry에 새 도메인 등록 (신규 컨트랙트인 경우)
```

### Layer 6 — 하드포크 게이팅 (Optional)

거버넌스 변경이 특정 블록 이후에만 활성되어야 하면:

1. `params/config.go`에 새 하드포크 블록 추가 (예: `BriocheBlock`, `CroissantBlock`)
2. `IsCroissant(num)` 메서드 + `Rules.IsCroissant` 필드
3. `CheckConfigForkOrder`, `CheckCompatible`에 등록
4. Go 호출 분기:
   ```go
   if !config.IsCroissant(num) {
       // 기존 동작
   } else {
       contracts.GovImp.NewMethod(opts, ...)
   }
   ```

상세는 `.claude/docs/CLAUDE_DEV_GUIDE.md §9 하드포크 추가 방법` 참조.

### Layer 7 — 검증

```bash
# 1. 빌드
make gwemix

# 2. 린트
make lint
golangci-lint run ./wemix/... ./cmd/gwemix/...

# 3. 단위 테스트 (특히 거버넌스 관련)
go test -short -count=1 ./wemix/...
go test -short -count=1 ./cmd/gwemix/...

# 4. 시뮬레이션 백엔드 테스트 (전체 거버넌스 흐름)
go test -count=1 ./wemix/bind/backends/...

# 5. 거버넌스 컨트랙트 자체 테스트 (hardhat/foundry)
cd wemix/governance-contract/test && <테스트 명령>
```

### 검증 항목 체크리스트

- [ ] Solidity 소스 변경 — UUPS 호환성 유지 (스토리지 레이아웃 보존)
- [ ] solc 0.8.14로 컴파일 성공
- [ ] abigen으로 `wemix/bind/gen_*_abi.go` 재생성 (수동 편집 흔적 없음)
- [ ] `wemix/admin.go`의 신규 호출이 `Registry` 경유 (주소 하드코딩 없음)
- [ ] 신규 EnvStorage 키 도입 시 거버넌스 투표 시나리오 문서화
- [ ] 하드포크 게이팅 필요 시 `params/config.go` 4종 갱신 (필드/Is*/CheckConfigForkOrder/CheckCompatible)
- [ ] `make gwemix` 빌드 통과
- [ ] `make lint` 통과
- [ ] `make test-short` 통과
- [ ] 거버넌스 시뮬레이션 테스트 통과 (`wemix/bind/backends/wemix_simulated_test.go`)
- [ ] 운영 네트워크 영향 시 배포 절차서 작성 (거버넌스 투표 / 업그레이드 순서)

### 상세 참조

- 거버넌스 컨트랙트 흐름: `.claude/docs/GOVERNANCE_FLOW.md`
- 개발 가이드 (하드포크/Fee Delegation/Brioche 등): `.claude/docs/CLAUDE_DEV_GUIDE.md`
- 빌드 파일 목록: `.claude/docs/BUILD_SOURCE_FILES.md`
- 리뷰 가이드: `.claude/docs/REVIEW_GUIDE.md`
