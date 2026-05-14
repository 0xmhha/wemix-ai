# go-wemix Build Source Files

> `make gwemix` (`go run build/ci.go install ./cmd/gwemix`) 실행 시 바이너리 빌드에 참여하는 모든 내부 패키지 및 Go 소스 파일 목록.
>
> - 추출 방법: `go list -deps ./cmd/gwemix/...` (Go 의존성 트리 기반)
> - 테스트 파일(`_test.go`)은 제외
> - 플랫폼: darwin/arm64 (USE_ROCKSDB=NO). Linux/amd64에서는 빌드 태그 `rocksdb`에 의해 `ethdb/rocksdb/rocksdb.go`가 추가로 포함됨
> - 분석 기준일: 2026-05-13
> - 기준 브랜치: `dev` (commit: `ed259a47e`)

---

## 요약

| 항목 | 수치 |
|------|------|
| 빌드 대상 바이너리 | **`gwemix` (단일 메인)** |
| 내부 패키지 (go-ethereum/) | **120개** |
| Go 소스 파일 (darwin/arm64) | **626개** |
| Wemix 고유 패키지 | **5개** (`wemix/`, `wemix/api`, `wemix/bind`, `wemix/metclient`, `wemix/miner`) |
| Wemix 고유 파일 (기존 패키지 내) | **6개** (아래 §3.2) |

> **참고**: `cmd/`에는 `gwemix` 외에도 `geth`, `evm`, `abigen`, `bootnode`, `clef`, `devp2p`, `dbbench`, `ethkey`, `faucet`, `p2psim`, `puppeth`, `rlpdump`, `checkpoint-admin`, `abidump`, `logrot` 등의 보조 바이너리가 있으나 본 문서는 **`gwemix` 의존성만** 추적한다. `make gwemix-linux`, `make all`, `make dbbench`, `make logrot` 등은 별도 의존성 셋을 가짐.

---

## 1. 빌드 진입점

| 항목 | 값 |
|------|-----|
| 진입 파일 | `cmd/gwemix/main.go` |
| 빌드 명령 | `make gwemix` → `build/ci.go install ./cmd/gwemix` |
| 출력 경로 | `build/bin/gwemix` |
| 패키징 | `make gwemix.tar.gz` → `build/gwemix.tar.gz` (gwemix + logrot + conf) |
| RocksDB | Linux: `USE_ROCKSDB=YES` (정적 링크), 그 외: `NO` (norocksdb.go 스텁) |

`cmd/gwemix/`에 포함된 파일 (12개):
`accountcmd.go`, `chaincmd.go`, `config.go`, `consolecmd.go`, `dbcmd.go`, **`governancedeploy.go`**, `main.go`, `misccmd.go`, `snapshot.go`, `usage.go`, `version_check.go`, **`wemixcmd.go`**

---

## 2. 빌드 참여 패키지 및 소스 파일 전체 목록 (120 패키지, 626 파일)

### 2.1 Root (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `github.com/ethereum/go-ethereum` | `interfaces.go` |

### 2.2 accounts/ (9 패키지, 50 파일)

| 패키지 | 파일 |
|--------|------|
| `accounts` | `accounts.go`, `errors.go`, `hd.go`, `manager.go`, `sort.go`, `url.go` |
| `accounts/abi` | `abi.go`, `argument.go`, `doc.go`, `error.go`, `error_handling.go`, `event.go`, `method.go`, `pack.go`, `reflect.go`, `selector_parser.go`, `topics.go`, `type.go`, `unpack.go` |
| `accounts/abi/bind` | `auth.go`, `backend.go`, `base.go`, `bind.go`, `template.go`, `util.go` |
| `accounts/abi/bind/backends` | `simulated.go` |
| `accounts/external` | `backend.go` |
| `accounts/keystore` | `account_cache.go`, `file_cache.go`, `key.go`, `keystore.go`, `passphrase.go`, `plain.go`, `presale.go`, `wallet.go`, `watch.go` |
| `accounts/scwallet` | `apdu.go`, `hub.go`, `securechannel.go`, `wallet.go` |
| `accounts/usbwallet` | `hub.go`, `ledger.go`, `offline.go`, `trezor.go`, `wallet.go` |
| `accounts/usbwallet/trezor` | `messages-common.pb.go`, `messages-ethereum.pb.go`, `messages-management.pb.go`, `messages.pb.go`, `trezor.go` |

### 2.3 cmd/ (2 패키지, 18 파일) — Wemix 고유

| 패키지 | 파일 | Wemix 고유 |
|--------|------|:---------:|
| **`cmd/gwemix`** | `accountcmd.go`, `chaincmd.go`, `config.go`, `consolecmd.go`, `dbcmd.go`, **`governancedeploy.go`**, `main.go`, `misccmd.go`, `snapshot.go`, `usage.go`, `version_check.go`, **`wemixcmd.go`** | **Yes** |
| `cmd/utils` | `cmd.go`, `customflags.go`, `diskusage.go`, `flags.go`, `flags_legacy.go`, `prompt.go` | Partial |

### 2.4 common/ (8 패키지, 21 파일)

| 패키지 | 파일 |
|--------|------|
| `common` | `big.go`, `bytes.go`, `debug.go`, `format.go`, `path.go`, `size.go`, `test_utils.go`, `types.go` |
| `common/bitutil` | `bitutil.go`, `compress.go` |
| `common/fdlimit` | `fdlimit_darwin.go` (darwin) — Linux에서는 `fdlimit_unix.go` |
| `common/hexutil` | `hexutil.go`, `json.go` |
| `common/lru` | `lrucache.go` |
| `common/math` | `big.go`, `integer.go` |
| `common/mclock` | `mclock.go`, `simclock.go` |
| `common/prque` | `lazyqueue.go`, `prque.go`, `sstack.go` |

### 2.5 consensus/ (5 패키지, 18 파일)

| 패키지 | 파일 |
|--------|------|
| `consensus` | `consensus.go`, `errors.go`, `merger.go` |
| `consensus/beacon` | `consensus.go` |
| `consensus/clique` | `api.go`, `clique.go`, `snapshot.go` |
| `consensus/ethash` | `algorithm.go`, `api.go`, `consensus.go`, `difficulty.go`, `ethash.go`, `mmap_help_other.go`, `sealer.go` |
| `consensus/misc` | `dao.go`, `eip1559.go`, `forks.go`, `gaslimit.go` |

> **참고**: Wemix는 별도의 `consensus/wemix` 패키지를 두지 않고, `consensus/clique` 위에 `wemix/admin.go` + `wemix/etcdutil.go` (etcd 기반 마이닝 토큰 락) + Solidity 거버넌스 컨트랙트(Registry/Gov/Staking/EnvStorage 등)를 조합해 합의·운영 레이어를 구현한다. `wemix/miner/miner.go`가 PoA 풀에 wemix 보상 분배를 주입한다.

### 2.6 console/ (2 패키지, 3 파일)

| 패키지 | 파일 |
|--------|------|
| `console` | `bridge.go`, `console.go` |
| `console/prompt` | `prompter.go` |

### 2.7 contracts/ (2 패키지, 2 파일)

| 패키지 | 파일 |
|--------|------|
| `contracts/checkpointoracle` | `oracle.go` |
| `contracts/checkpointoracle/contract` | `oracle.go` |

### 2.8 core/ (10 패키지, 124 파일) — Wemix 고유 포함

| 패키지 | 파일 | Wemix 고유 |
|--------|------|:---------:|
| `core` | `block_validator.go`, `blockchain.go`, `blockchain_insert.go`, `blockchain_reader.go`, `blocks.go`, `bloom_indexer.go`, `chain_indexer.go`, `chain_makers.go`, `error.go`, `events.go`, `evm.go`, `forkchoice.go`, `gaspool.go`, `gen_genesis.go`, `gen_genesis_account.go`, `genesis.go`, `genesis_alloc.go`, `headerchain.go`, `state_prefetcher.go`, `state_processor.go`, `state_transition.go`, `tx_cacher.go`, `tx_journal.go`, `tx_list.go`, `tx_noncer.go`, `tx_pool.go`, `tx_sender_resolver.go`, `types.go`, **`wemix_genesis.go`** | Partial |
| `core/beacon` | `errors.go`, `gen_blockparams.go`, `gen_ed.go`, `types.go` |  |
| `core/bloombits` | `doc.go`, `generator.go`, `matcher.go`, `scheduler.go` |  |
| `core/forkid` | `forkid.go` |  |
| `core/rawdb` | `accessors_chain.go`, `accessors_indexes.go`, `accessors_metadata.go`, `accessors_snapshot.go`, `accessors_state.go`, `accessors_sync.go`, `chain_freezer.go`, `chain_iterator.go`, `database.go`, `freezer.go`, `freezer_batch.go`, `freezer_meta.go`, `freezer_table.go`, `freezer_utils.go`, `key_length_iterator.go`, `schema.go`, `table.go` |  |
| `core/state` | `access_list.go`, `database.go`, `dump.go`, `iterator.go`, `journal.go`, `metrics.go`, `state_object.go`, `statedb.go`, `sync.go`, `trie_prefetcher.go` |  |
| `core/state/pruner` | `bloom.go`, `pruner.go` |  |
| `core/state/snapshot` | `account.go`, `context.go`, `conversion.go`, `dangling.go`, `difflayer.go`, `disklayer.go`, `generate.go`, `holdable_iterator.go`, `iterator.go`, `iterator_binary.go`, `iterator_fast.go`, `journal.go`, `metrics.go`, `snapshot.go`, `sort.go` |  |
| `core/types` | `access_list_tx.go`, `block.go`, `bloom9.go`, `dynamic_fee_tx.go`, **`feedelegate_dynamic_fee_tx.go`**, `gen_access_tuple.go`, `gen_account_rlp.go`, `gen_header_json.go`, `gen_header_rlp.go`, `gen_log_json.go`, `gen_log_rlp.go`, `gen_receipt_json.go`, `hashing.go`, `legacy.go`, `legacy_tx.go`, `log.go`, `receipt.go`, `state_account.go`, `transaction.go`, `transaction_marshalling.go`, `transaction_signing.go` | Partial |
| `core/vm` | `analysis.go`, `common.go`, `contract.go`, `contracts.go`, `doc.go`, `eips.go`, `errors.go`, `evm.go`, `gas.go`, `gas_table.go`, `instructions.go`, `interface.go`, `interpreter.go`, `jump_table.go`, `logger.go`, `memory.go`, `memory_table.go`, `opcodes.go`, `operations_acl.go`, `stack.go`, `stack_table.go` |  |

### 2.9 crypto/ (8 패키지, 37 파일)

| 패키지 | 파일 |
|--------|------|
| `crypto` | `crypto.go`, `signature_cgo.go` |
| `crypto/blake2b` | `blake2b.go`, `blake2b_generic.go`, `blake2b_ref.go`, `blake2x.go`, `register.go` |
| `crypto/bls12381` | `arithmetic_fallback.go`, `bls12_381.go`, `field_element.go`, `fp.go`, `fp12.go`, `fp2.go`, `fp6.go`, `g1.go`, `g2.go`, `gt.go`, `isogeny.go`, `pairing.go`, `swu.go`, `utils.go` |
| `crypto/bn256` | `bn256_fast.go` |
| `crypto/bn256/cloudflare` | `bn256.go`, `constants.go`, `curve.go`, `gfp.go`, `gfp12.go`, `gfp2.go`, `gfp6.go`, `gfp_decl.go`, `lattice.go`, `optate.go`, `twist.go` |
| `crypto/ecies` | `ecies.go`, `params.go` |
| `crypto/secp256k1` | `curve.go` |
| `crypto/vrf` | `vrf.go` |

### 2.10 eth/ (14 패키지, 71 파일) — Wemix 고유 포함

| 패키지 | 파일 | Wemix 고유 |
|--------|------|:---------:|
| `eth` | `api.go`, `api_backend.go`, `backend.go`, `bloombits.go`, `discovery.go`, `handler.go`, `handler_eth.go`, `handler_snap.go`, `peer.go`, `peerset.go`, `state_accessor.go`, `sync.go` | Partial |
| `eth/catalyst` | `api.go`, `queue.go` |  |
| `eth/downloader` | `api.go`, `beaconsync.go`, `downloader.go`, `events.go`, `fetchers.go`, `fetchers_concurrent.go`, `fetchers_concurrent_bodies.go`, `fetchers_concurrent_headers.go`, `fetchers_concurrent_receipts.go`, `metrics.go`, `modes.go`, `peer.go`, `queue.go`, `resultstore.go`, `skeleton.go`, `statesync.go` |  |
| `eth/ethconfig` | `config.go`, `gen_config.go` |  |
| `eth/fetcher` | `block_fetcher.go`, `tx_fetcher.go` |  |
| `eth/filters` | `api.go`, `filter.go`, `filter_system.go` |  |
| `eth/gasprice` | `feehistory.go`, `gasprice.go` | Partial |
| `eth/protocols/eth` | `broadcast.go`, `discovery.go`, `dispatcher.go`, `handler.go`, `handlers.go`, `handshake.go`, `peer.go`, `protocol.go`, `tracker.go`, **`wemix_handlers.go`** | Partial |
| `eth/protocols/snap` | `discovery.go`, `handler.go`, `peer.go`, `protocol.go`, `range.go`, `sync.go`, `tracker.go` |  |
| `eth/tracers` | `api.go`, `tracers.go` |  |
| `eth/tracers/js` | `bigint.go`, `goja.go` |  |
| `eth/tracers/js/internal/tracers` | `assets.go`, `tracers.go` |  |
| `eth/tracers/logger` | `access_list_tracer.go`, `gen_structlog.go`, `logger.go`, `logger_json.go` |  |
| `eth/tracers/native` | `4byte.go`, `call.go`, `noop.go`, `prestate.go`, `tracer.go` |  |

### 2.11 ethclient/ (1 패키지, 2 파일)

| 패키지 | 파일 |
|--------|------|
| `ethclient` | `ethclient.go`, `signer.go` |

### 2.12 ethdb/ (5 패키지, 8 파일)

| 패키지 | 파일 |
|--------|------|
| `ethdb` | `batch.go`, `database.go`, `iterator.go`, `snapshot.go` |
| `ethdb/leveldb` | `leveldb.go` |
| `ethdb/memorydb` | `memorydb.go` |
| `ethdb/remotedb` | `remotedb.go` |
| `ethdb/rocksdb` | `norocksdb.go` (build tag: `!rocksdb`) — Linux에서 `rocksdb` 태그가 켜지면 `rocksdb.go`로 교체 |

### 2.13 ethstats/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `ethstats` | `ethstats.go` |

### 2.14 event/ (1 패키지, 3 파일)

| 패키지 | 파일 |
|--------|------|
| `event` | `event.go`, `feed.go`, `subscription.go` |

### 2.15 graphql/ (1 패키지, 4 파일)

| 패키지 | 파일 |
|--------|------|
| `graphql` | `graphiql.go`, `graphql.go`, `schema.go`, `service.go` |

### 2.16 internal/ (8 패키지, 20 파일)

| 패키지 | 파일 |
|--------|------|
| `internal/debug` | `api.go`, `flags.go`, `loudpanic.go`, `trace.go` |
| `internal/ethapi` | `addrlock.go`, `api.go`, `api_cache.go`, `backend.go`, `dbapi.go`, `transaction_args.go` |
| `internal/flags` | `helpers.go` |
| `internal/jsre` | `completion.go`, `jsre.go`, `offline_wallet.go`, `pretty.go` |
| `internal/jsre/deps` | `bindata.go`, `deps.go` |
| `internal/shutdowncheck` | `shutdown_tracker.go` |
| `internal/syncx` | `mutex.go` |
| `internal/web3ext` | `web3ext.go` |

### 2.17 les/ (10 패키지, 65 파일)

| 패키지 | 파일 |
|--------|------|
| `les` | `api.go`, `api_backend.go`, `benchmark.go`, `bloombits.go`, `client.go`, `client_handler.go`, `commons.go`, `costtracker.go`, `distributor.go`, `enr_entry.go`, `fetcher.go`, `metrics.go`, `odr.go`, `odr_requests.go`, `peer.go`, `protocol.go`, `pruner.go`, `retrieve.go`, `server.go`, `server_handler.go`, `server_requests.go`, `servingqueue.go`, `state_accessor.go`, `sync.go`, `test_helper.go`, `txrelay.go`, `ulc.go` |
| `les/catalyst` | `api.go` |
| `les/checkpointoracle` | `oracle.go` |
| `les/downloader` | `api.go`, `downloader.go`, `events.go`, `metrics.go`, `modes.go`, `peer.go`, `queue.go`, `resultstore.go`, `statesync.go`, `types.go` |
| `les/fetcher` | `block_fetcher.go` |
| `les/flowcontrol` | `control.go`, `logger.go`, `manager.go` |
| `les/utils` | `exec_queue.go`, `expiredvalue.go`, `limiter.go`, `timeutils.go`, `weighted_select.go` |
| `les/vflux` | `requests.go` |
| `les/vflux/client` | `api.go`, `fillset.go`, `queueiterator.go`, `requestbasket.go`, `serverpool.go`, `timestats.go`, `valuetracker.go`, `wrsiterator.go` |
| `les/vflux/server` | `balance.go`, `balance_tracker.go`, `clientdb.go`, `clientpool.go`, `metrics.go`, `prioritypool.go`, `service.go`, `status.go` |

### 2.18 light/ (1 패키지, 7 파일)

| 패키지 | 파일 |
|--------|------|
| `light` | `lightchain.go`, `nodeset.go`, `odr.go`, `odr_util.go`, `postprocess.go`, `trie.go`, `txpool.go` |

### 2.19 log/ (1 패키지, 8 파일)

| 패키지 | 파일 |
|--------|------|
| `log` | `doc.go`, `format.go`, `handler.go`, `handler_glog.go`, `handler_go14.go`, `logger.go`, `root.go`, `syslog.go` |

### 2.20 metrics/ (4 패키지, 35 파일)

| 패키지 | 파일 |
|--------|------|
| `metrics` | `config.go`, `counter.go`, `cpu.go`, `cpu_enabled.go`, `cputime_unix.go`, `debug.go`, `disk.go`, `disk_nop.go`, `doc.go`, `ewma.go`, `gauge.go`, `gauge_float64.go`, `graphite.go`, `healthcheck.go`, `histogram.go`, `json.go`, `log.go`, `meter.go`, `metrics.go`, `opentsdb.go`, `registry.go`, `resetting_sample.go`, `resetting_timer.go`, `runtime.go`, `runtime_cgo.go`, `runtime_gccpufraction.go`, `sample.go`, `syslog.go`, `timer.go`, `writer.go` |
| `metrics/exp` | `exp.go` |
| `metrics/influxdb` | `influxdb.go`, `influxdbv2.go` |
| `metrics/prometheus` | `collector.go`, `prometheus.go` |

### 2.21 miner/ (1 패키지, 5 파일)

| 패키지 | 파일 |
|--------|------|
| `miner` | `miner.go`, `tx_orderer.go`, `tx_prefetch.go`, `unconfirmed.go`, `worker.go` |

### 2.22 node/ (1 패키지, 10 파일)

| 패키지 | 파일 |
|--------|------|
| `node` | `api.go`, `config.go`, `defaults.go`, `doc.go`, `endpoints.go`, `errors.go`, `jwt_handler.go`, `lifecycle.go`, `node.go`, `rpcstack.go` |

### 2.23 p2p/ (13 패키지, 47 파일)

| 패키지 | 파일 |
|--------|------|
| `p2p` | `dial.go`, `message.go`, `metrics.go`, `peer.go`, `peer_error.go`, `protocol.go`, `server.go`, `transport.go`, `util.go` |
| `p2p/discover` | `common.go`, `lookup.go`, `node.go`, `ntp.go`, `table.go`, `v4_udp.go`, `v5_udp.go` |
| `p2p/discover/v4wire` | `v4wire.go` |
| `p2p/discover/v5wire` | `crypto.go`, `encoding.go`, `msg.go`, `session.go` |
| `p2p/dnsdisc` | `client.go`, `doc.go`, `error.go`, `sync.go`, `tree.go` |
| `p2p/enode` | `idscheme.go`, `iter.go`, `localnode.go`, `node.go`, `nodedb.go`, `urlv4.go` |
| `p2p/enr` | `enr.go`, `entries.go` |
| `p2p/msgrate` | `msgrate.go` |
| `p2p/nat` | `nat.go`, `natpmp.go`, `natupnp.go` |
| `p2p/netutil` | `addrutil.go`, `error.go`, `iptrack.go`, `net.go`, `toobig_notwindows.go` |
| `p2p/nodestate` | `nodestate.go` |
| `p2p/rlpx` | `buffer.go`, `rlpx.go` |
| `p2p/tracker` | `tracker.go` |

### 2.24 params/ (1 패키지, 8 파일) — Wemix 고유 포함

| 패키지 | 파일 | Wemix 고유 |
|--------|------|:---------:|
| `params` | `bootnodes.go`, **`config.go`** *(부분: Pangyo/Applepie/Brioche/Croissant)*, `dao.go`, `denomination.go`, `network_params.go`, `protocol_params.go`, `version.go`, **`wemix_config.go`** | Partial |

### 2.25 rlp/ (2 패키지, 9 파일)

| 패키지 | 파일 |
|--------|------|
| `rlp` | `decode.go`, `doc.go`, `encbuffer.go`, `encode.go`, `iterator.go`, `raw.go`, `typecache.go`, `unsafe.go` |
| `rlp/internal/rlpstruct` | `rlpstruct.go` |

### 2.26 rpc/ (1 패키지, 17 파일)

| 패키지 | 파일 |
|--------|------|
| `rpc` | `client.go`, `doc.go`, `endpoints.go`, `errors.go`, `handler.go`, `http.go`, `inproc.go`, `ipc.go`, `ipc_unix.go`, `json.go`, `metrics.go`, `server.go`, `service.go`, `stdio.go`, `subscription.go`, `types.go`, `websocket.go` |

### 2.27 signer/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `signer/core/apitypes` | `types.go` |

### 2.28 trie/ (1 패키지, 14 파일)

| 패키지 | 파일 |
|--------|------|
| `trie` | `committer.go`, `database.go`, `encoding.go`, `errors.go`, `hasher.go`, `iterator.go`, `node.go`, `node_enc.go`, `proof.go`, `secure_trie.go`, `stacktrie.go`, `sync.go`, `trie.go`, `utils.go` |

### 2.29 wemix/ (5 패키지, 17 파일) — **Wemix 핵심**

| 패키지 | 파일 | 역할 |
|--------|------|------|
| **`wemix`** | `admin.go` (43KB), `etcdutil.go` (28KB), `miner_limit.go`, `spinlock.go`, `sync.go` | wemixAdmin: 거버넌스 컨트랙트 조회, etcd 기반 마이닝 토큰 락, 보상 분배, 멤버십 동기화 |
| **`wemix/api`** | `api.go` | `WemixMinerStatus` 타입 + 마이너 상태 이벤트 구독 API |
| **`wemix/bind`** | `const.go`, `gen_ballotStorage_abi.go`, `gen_envStorage_abi.go`, `gen_gov_abi.go`, `gen_ncpExit_abi.go`, `gen_registry_abi.go`, `gen_staking_abi.go`, `structs.go` | abigen으로 생성된 거버넌스 컨트랙트 Go 바인딩 (수동 편집 금지) |
| **`wemix/metclient`** | `tx_params.go`, `util.go` | 트랜잭션 파라미터/유틸리티 헬퍼 (Wemix 거버넌스 호출용) |
| **`wemix/miner`** | `miner.go` | wemix 보상 분배를 PoA 마이너 풀에 주입 |

> **빌드에 포함되지 않는 wemix 하위 디렉토리** (있어도 무방):
> - `wemix/bind/backends/` (테스트 백엔드, 빌드에 포함 안 됨)
> - `wemix/governance-contract/` (Solidity 소스 + abigen 도구, 별도 `go generate` 또는 수동 실행)
> - `wemix/scripts/` (`gwemix.sh`, `config.json.example`, `genesis-template.json` — 런타임 자산)

---

## 3. Wemix 고유 코드 식별

go-ethereum 원본에 없는 Wemix 전용 패키지 및 파일.

### 3.1 전용 패키지 (geth에 없는 패키지)

| 패키지 | 파일 수 | 설명 |
|--------|---------|------|
| `wemix` | 5 | wemixAdmin (거버넌스/etcd/보상 분배) |
| `wemix/api` | 1 | WemixMinerStatus 이벤트 API |
| `wemix/bind` | 8 | abigen 생성 Go 바인딩 (Registry, Gov, Staking, BallotStorage, EnvStorage, NCPExit) |
| `wemix/metclient` | 2 | 트랜잭션/유틸 헬퍼 |
| `wemix/miner` | 1 | PoA 마이너 보상 주입 |
| `cmd/gwemix` | 12 | Wemix 메인 클라이언트 + 거버넌스 배포 커맨드 |

### 3.2 기존 패키지 내 Wemix 고유 파일

| 파일 | 패키지 | 설명 |
|------|--------|------|
| `core/wemix_genesis.go` | `core` | Wemix Mainnet/Testnet 제네시스 JSON (대규모 alloc, 하드포크 블록 매핑) |
| `core/types/feedelegate_dynamic_fee_tx.go` | `core/types` | Fee Delegation EIP-1559 트랜잭션 (Sender + FeePayer 이중 서명) |
| `eth/protocols/eth/wemix_handlers.go` | `eth/protocols/eth` | Wemix 전용 eth 프로토콜 메시지 핸들러 (멤버십 동기화 등) |
| `params/wemix_config.go` | `params` | Wemix Mainnet/Testnet 부트노드 + `WemixGenesisFile` 전역 |
| `params/config.go` *(부분)* | `params` | `PangyoBlock`, `ApplepieBlock`, `BriocheBlock`, `CroissantBlock`, `BriocheConfig`, `IsPangyo/IsApplepie/IsBrioche/IsCroissant`, `Rules.IsPangyo/...` |
| `ethdb/rocksdb/*.go` | `ethdb/rocksdb` | RocksDB 백엔드 (Linux 빌드 시 정적 링크) |

### 3.3 cmd/utils 내 Wemix 영향

`cmd/utils/flags.go`에는 `WemixGenesisFile` 처리, `--miner.threads` 강제 1 등 Wemix 특화 분기가 일부 들어 있다 (Partial).

---

## 4. 카테고리별 패키지/파일 수 집계

| 카테고리 | 패키지 수 | 파일 수 |
|----------|----------:|--------:|
| Root | 1 | 1 |
| accounts/ | 9 | 50 |
| cmd/ | 2 | 18 |
| common/ | 8 | 21 |
| consensus/ | 5 | 18 |
| console/ | 2 | 3 |
| contracts/ | 2 | 2 |
| core/ | 10 | 124 |
| crypto/ | 8 | 37 |
| eth/ | 14 | 71 |
| ethclient/ | 1 | 2 |
| ethdb/ | 5 | 8 |
| ethstats/ | 1 | 1 |
| event/ | 1 | 3 |
| graphql/ | 1 | 4 |
| internal/ | 8 | 20 |
| les/ | 10 | 65 |
| light/ | 1 | 7 |
| log/ | 1 | 8 |
| metrics/ | 4 | 35 |
| miner/ | 1 | 5 |
| node/ | 1 | 10 |
| p2p/ | 13 | 47 |
| params/ | 1 | 8 |
| rlp/ | 2 | 9 |
| rpc/ | 1 | 17 |
| signer/ | 1 | 1 |
| trie/ | 1 | 14 |
| wemix/ | 5 | 17 |
| **합계** | **120** | **626** |

---

## 5. Wemix 하드포크 이력

| 하드포크 | Mainnet 블록 | Testnet 블록 | 주요 변경 |
|----------|------------:|------------:|-----------|
| (제네시스) | 0 | 0 | Wemix PoA + Governance Contract v1 (Registry, Gov, Staking, BallotStorage, EnvStorage) |
| Pangyo | 0 | 10,000,000 | 거버넌스 활성화 임계 / 멤버십 운영 정책 |
| Applepie | 20,476,911 | 26,240,268 | Fee Delegation 트랜잭션 활성화 (`feedelegate_dynamic_fee_tx`) |
| Brioche | 53,525,500 (≈24-07-01 KST) | 59,414,700 (≈24-06-04 KST) | 블록 보상 변경 로직 (`BriocheConfig.GetBriocheBlockReward`), `EnvStorageImp.getBlockRewardAmount()` 대체 |
| Croissant | TBD | TBD | 후속 거버넌스/네트워크 파라미터 변경 |

`params/config.go`에서 모두 정의되어 있으며, `Rules` 구조체에 `IsPangyo`, `IsApplepie`, `IsBrioche`, `IsCroissant` 필드가 노출된다.

---

## 6. 참고 사항

- 본 목록은 `darwin/arm64` + `USE_ROCKSDB=NO` 기준이다. `linux/amd64` + `USE_ROCKSDB=YES`에서는:
  - `common/fdlimit/fdlimit_darwin.go` → `fdlimit_unix.go`로 교체
  - `ethdb/rocksdb/norocksdb.go` → `ethdb/rocksdb/rocksdb.go`로 교체 (RocksDB CGO 정적 링크 활성)
  - `crypto/secp256k1/*.go`의 일부 어셈블리 변형 차이
- 외부 의존성(third-party 모듈)은 이 목록에 포함되지 않는다. 전체 외부 의존성은 `go.mod` 참조 (Go 1.19 / module path: `github.com/ethereum/go-ethereum`).
- `_test.go` 파일은 빌드에 포함되지 않으므로 제외했다.
- `build/ci.go` 자체는 `//go:build none` 태그로 일반 빌드에서 제외되며, `go run`으로만 실행된다.
- `wemix/governance-contract/`의 Solidity 소스 및 `compiler.go`는 `go generate` 또는 `cmd/gwemix governancedeploy` 워크플로우에서만 사용되며, 일반 `make gwemix` 빌드에는 포함되지 않는다 (단, `wemix/bind/gen_*_abi.go`에는 이미 컴파일된 ABI/바인딩이 임베드되어 있다).
- `wemix/etcdutil.go.new`는 빌드 대상이 아닌 보관 파일이다 (`.go.new` 확장자).
- `wemix/admin.go`는 약 43KB로 단일 파일에 wemixAdmin 컨텍스트 전반이 응집되어 있다 — 수정 시 함수 단위로 신중하게 변경한다.
