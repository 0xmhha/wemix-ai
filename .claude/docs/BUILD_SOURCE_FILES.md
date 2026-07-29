# go-wemix Build Source Files

> `make gwemix` / `make logrot` 실행 시 실제 바이너리에 참여하는 내부 패키지·소스 파일 목록과, 그 패키지들에 딸린 테스트 코드 목록.
>
> - 추출 방법: `go list -deps ./cmd/gwemix`, `go list -deps ./cmd/logrot` (Go 의존성 트리 기반)
> - 빌드 파일 = `GoFiles` + `CgoFiles`, 테스트 파일 = `TestGoFiles` + `XTestGoFiles`
> - 플랫폼: darwin/arm64 (`USE_ROCKSDB=NO`). Linux/amd64 차이는 §7 참조
> - 분석 기준일: **2026-07-29**
> - 기준 브랜치: `dev` (commit `4e0005fbe`, `params/version.go` = **v0.10.14-stable**)
> - Go 모듈 선언 버전 1.19 (`go.mod`) / 검증에 사용한 툴체인 go1.25.11

---

## 요약

| 항목 | 수치 |
|------|------|
| 빌드 대상 바이너리 | **`gwemix`**, **`logrot`** |
| `gwemix` 내부 패키지 (go-ethereum/) | **120개** |
| `gwemix` 빌드 참여 Go 소스 (darwin/arm64) | **630개** |
| `gwemix` 의존 패키지에 딸린 테스트 파일 | **302개** (85개 패키지) |
| `logrot` 내부 패키지 | **1개** (`cmd/logrot`, 1 파일 — 본체는 외부 모듈) |
| Wemix 고유 패키지 | **5개** (`wemix/`, `wemix/api`, `wemix/bind`, `wemix/metclient`, `wemix/miner`) + `cmd/gwemix` |
| Wemix 고유 파일 (기존 패키지 내) | **6종** (§4.2) |

> **참고**: `cmd/`에는 `gwemix`·`logrot` 외에도 `geth`, `evm`, `abigen`, `bootnode`, `clef`, `devp2p`, `dbbench`, `ethkey`, `faucet`, `p2psim`, `puppeth`, `rlpdump`, `checkpoint-admin`, `abidump` 등의 보조 바이너리가 있으나, 본 문서는 **`gwemix`와 `logrot`의 의존성만** 추적한다. `make all`, `make dbbench`, `make geth`는 별도 의존성 셋을 가진다.

---

## 1. 빌드 진입점

### 1.1 `make gwemix`

| 항목 | 값 |
|------|-----|
| 진입 파일 | `cmd/gwemix/main.go` |
| 빌드 명령 | `make gwemix` → `env GO111MODULE=on go run build/ci.go install ./cmd/gwemix` |
| 선행 타겟 | `rocksdb` (Linux + `USE_ROCKSDB=YES`일 때만 실동작, 그 외 no-op) |
| 출력 경로 | `build/bin/gwemix` |
| 패키징 | `make gwemix.tar.gz` → `build/gwemix.tar.gz` (`bin/` + `conf/`) |
| RocksDB | Linux: `USE_ROCKSDB=YES` (정적 링크, `-tags rocksdb`), 그 외: `NO` (`norocksdb.go` 스텁) |

`cmd/gwemix/`에 포함된 파일 (12개):
`accountcmd.go`, `chaincmd.go`, `config.go`, `consolecmd.go`, `dbcmd.go`, **`governancedeploy.go`**, `main.go`, `misccmd.go`, `snapshot.go`, `usage.go`, `version_check.go`, **`wemixcmd.go`**

### 1.2 `make logrot`

| 항목 | 값 |
|------|-----|
| 진입 파일 | `cmd/logrot/main.go` (110 bytes — `logrot.Main()` 호출 wrapper) |
| 빌드 명령 | `make logrot` → `env GO111MODULE=on go run build/ci.go install ./cmd/logrot` |
| 선행 타겟 | 없음 (rocksdb 비의존, CGO 불필요) |
| 출력 경로 | `build/bin/logrot` |
| 내부 의존 패키지 | `cmd/logrot` **단 1개** |
| 외부 의존 모듈 | `github.com/charlanxcc/logrot` — 로테이션 본체 로직 전부 |

```go
// cmd/logrot/main.go 전문
package main

import "github.com/charlanxcc/logrot"

func main() {
	logrot.Main()
}
```

> **분석 시 유의**: `logrot`은 go-ethereum 트리 안의 어떤 패키지도 import하지 않는다. 로그 로테이션 동작을 바꾸려면 이 저장소가 아니라 외부 모듈 `github.com/charlanxcc/logrot`(go.mod 참조)을 봐야 한다. 저장소 안에서 잡을 수 있는 것은 진입점뿐이다.
>
> `make gwemix.tar.gz`가 `gwemix`와 `logrot` 두 바이너리를 함께 묶으므로, 배포 tarball 관점에서는 두 타겟이 한 세트다.

---

## 2. `gwemix` 빌드 참여 패키지 및 소스 파일 (120 패키지, 630 파일)

> **굵게** 표시된 파일/패키지는 geth 원본에 없는 Wemix 고유 코드다. `Partial`은 geth 원본 파일에 Wemix 분기가 들어간 패키지를 의미한다.

#### Root (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `(root)` | `interfaces.go` |

#### accounts/ (9 패키지, 50 파일)

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

#### cmd/ (2 패키지, 18 파일) — Wemix 고유 포함

| 패키지 | 파일 | Wemix |
|--------|------|:-----:|
| `cmd/gwemix` | `accountcmd.go`, `chaincmd.go`, `config.go`, `consolecmd.go`, `dbcmd.go`, **`governancedeploy.go`**, `main.go`, `misccmd.go`, `snapshot.go`, `usage.go`, `version_check.go`, **`wemixcmd.go`** | Partial |
| `cmd/utils` | `cmd.go`, `customflags.go`, `diskusage.go`, `flags.go`, `flags_legacy.go`, `prompt.go` | Partial |

#### common/ (8 패키지, 21 파일)

| 패키지 | 파일 |
|--------|------|
| `common` | `big.go`, `bytes.go`, `debug.go`, `format.go`, `path.go`, `size.go`, `test_utils.go`, `types.go` |
| `common/bitutil` | `bitutil.go`, `compress.go` |
| `common/fdlimit` | `fdlimit_darwin.go` |
| `common/hexutil` | `hexutil.go`, `json.go` |
| `common/lru` | `lrucache.go` |
| `common/math` | `big.go`, `integer.go` |
| `common/mclock` | `mclock.go`, `simclock.go` |
| `common/prque` | `lazyqueue.go`, `prque.go`, `sstack.go` |

#### consensus/ (5 패키지, 18 파일)

| 패키지 | 파일 |
|--------|------|
| `consensus` | `consensus.go`, `errors.go`, `merger.go` |
| `consensus/beacon` | `consensus.go` |
| `consensus/clique` | `api.go`, `clique.go`, `snapshot.go` |
| `consensus/ethash` | `algorithm.go`, `api.go`, `consensus.go`, `difficulty.go`, `ethash.go`, `mmap_help_other.go`, `sealer.go` |
| `consensus/misc` | `dao.go`, `eip1559.go`, `forks.go`, `gaslimit.go` |

#### console/ (2 패키지, 3 파일)

| 패키지 | 파일 |
|--------|------|
| `console` | `bridge.go`, `console.go` |
| `console/prompt` | `prompter.go` |

#### contracts/ (2 패키지, 2 파일)

| 패키지 | 파일 |
|--------|------|
| `contracts/checkpointoracle` | `oracle.go` |
| `contracts/checkpointoracle/contract` | `oracle.go` |

#### core/ (10 패키지, 124 파일) — Wemix 고유 포함

| 패키지 | 파일 | Wemix |
|--------|------|:-----:|
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

#### crypto/ (8 패키지, 40 파일)

| 패키지 | 파일 |
|--------|------|
| `crypto` | `crypto.go`, `signature_cgo.go` |
| `crypto/blake2b` | `blake2b.go`, `blake2b_generic.go`, `blake2b_ref.go`, `blake2x.go`, `register.go` |
| `crypto/bls12381` | `arithmetic_fallback.go`, `bls12_381.go`, `field_element.go`, `fp.go`, `fp12.go`, `fp2.go`, `fp6.go`, `g1.go`, `g2.go`, `gt.go`, `isogeny.go`, `pairing.go`, `swu.go`, `utils.go` |
| `crypto/bn256` | `bn256_fast.go` |
| `crypto/bn256/cloudflare` | `bn256.go`, `constants.go`, `curve.go`, `gfp.go`, `gfp12.go`, `gfp2.go`, `gfp6.go`, `gfp_decl.go`, `lattice.go`, `optate.go`, `twist.go` |
| `crypto/ecies` | `ecies.go`, `params.go` |
| `crypto/secp256k1` | `curve.go`, `panic_cb.go`, `scalar_mult_cgo.go`, `secp256.go` |
| `crypto/vrf` | `vrf.go` |

#### eth/ (14 패키지, 71 파일) — Wemix 고유 포함

| 패키지 | 파일 | Wemix |
|--------|------|:-----:|
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

#### ethclient/ (1 패키지, 2 파일)

| 패키지 | 파일 |
|--------|------|
| `ethclient` | `ethclient.go`, `signer.go` |

#### ethdb/ (5 패키지, 8 파일) — Wemix 고유 포함

| 패키지 | 파일 | Wemix |
|--------|------|:-----:|
| `ethdb` | `batch.go`, `database.go`, `iterator.go`, `snapshot.go` |  |
| `ethdb/leveldb` | `leveldb.go` |  |
| `ethdb/memorydb` | `memorydb.go` |  |
| `ethdb/remotedb` | `remotedb.go` |  |
| **`ethdb/rocksdb`** | **`norocksdb.go`** | **Yes** |

#### ethstats/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `ethstats` | `ethstats.go` |

#### event/ (1 패키지, 3 파일)

| 패키지 | 파일 |
|--------|------|
| `event` | `event.go`, `feed.go`, `subscription.go` |

#### graphql/ (1 패키지, 4 파일)

| 패키지 | 파일 |
|--------|------|
| `graphql` | `graphiql.go`, `graphql.go`, `schema.go`, `service.go` |

#### internal/ (8 패키지, 20 파일)

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

#### les/ (10 패키지, 65 파일)

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

#### light/ (1 패키지, 7 파일)

| 패키지 | 파일 |
|--------|------|
| `light` | `lightchain.go`, `nodeset.go`, `odr.go`, `odr_util.go`, `postprocess.go`, `trie.go`, `txpool.go` |

#### log/ (1 패키지, 8 파일)

| 패키지 | 파일 |
|--------|------|
| `log` | `doc.go`, `format.go`, `handler.go`, `handler_glog.go`, `handler_go14.go`, `logger.go`, `root.go`, `syslog.go` |

#### metrics/ (4 패키지, 35 파일)

| 패키지 | 파일 |
|--------|------|
| `metrics` | `config.go`, `counter.go`, `cpu.go`, `cpu_enabled.go`, `cputime_unix.go`, `debug.go`, `disk.go`, `disk_nop.go`, `doc.go`, `ewma.go`, `gauge.go`, `gauge_float64.go`, `graphite.go`, `healthcheck.go`, `histogram.go`, `json.go`, `log.go`, `meter.go`, `metrics.go`, `opentsdb.go`, `registry.go`, `resetting_sample.go`, `resetting_timer.go`, `runtime.go`, `runtime_cgo.go`, `runtime_gccpufraction.go`, `sample.go`, `syslog.go`, `timer.go`, `writer.go` |
| `metrics/exp` | `exp.go` |
| `metrics/influxdb` | `influxdb.go`, `influxdbv2.go` |
| `metrics/prometheus` | `collector.go`, `prometheus.go` |

#### miner/ (1 패키지, 5 파일)

| 패키지 | 파일 |
|--------|------|
| `miner` | `miner.go`, `tx_orderer.go`, `tx_prefetch.go`, `unconfirmed.go`, `worker.go` |

#### node/ (1 패키지, 10 파일)

| 패키지 | 파일 |
|--------|------|
| `node` | `api.go`, `config.go`, `defaults.go`, `doc.go`, `endpoints.go`, `errors.go`, `jwt_handler.go`, `lifecycle.go`, `node.go`, `rpcstack.go` |

#### p2p/ (13 패키지, 47 파일)

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

#### params/ (1 패키지, 8 파일) — Wemix 고유 포함

| 패키지 | 파일 | Wemix |
|--------|------|:-----:|
| `params` | `bootnodes.go`, **`config.go`**, `dao.go`, `denomination.go`, `network_params.go`, `protocol_params.go`, `version.go`, **`wemix_config.go`** | Partial |

#### rlp/ (2 패키지, 9 파일)

| 패키지 | 파일 |
|--------|------|
| `rlp` | `decode.go`, `doc.go`, `encbuffer.go`, `encode.go`, `iterator.go`, `raw.go`, `typecache.go`, `unsafe.go` |
| `rlp/internal/rlpstruct` | `rlpstruct.go` |

#### rpc/ (1 패키지, 18 파일)

| 패키지 | 파일 |
|--------|------|
| `rpc` | `client.go`, `constants_unix.go`, `doc.go`, `endpoints.go`, `errors.go`, `handler.go`, `http.go`, `inproc.go`, `ipc.go`, `ipc_unix.go`, `json.go`, `metrics.go`, `server.go`, `service.go`, `stdio.go`, `subscription.go`, `types.go`, `websocket.go` |

#### signer/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `signer/core/apitypes` | `types.go` |

#### trie/ (1 패키지, 14 파일)

| 패키지 | 파일 |
|--------|------|
| `trie` | `committer.go`, `database.go`, `encoding.go`, `errors.go`, `hasher.go`, `iterator.go`, `node.go`, `node_enc.go`, `proof.go`, `secure_trie.go`, `stacktrie.go`, `sync.go`, `trie.go`, `utils.go` |

#### wemix/ (5 패키지, 17 파일) — Wemix 고유 포함

| 패키지 | 파일 | Wemix |
|--------|------|:-----:|
| **`wemix`** | **`admin.go`**, **`etcdutil.go`**, **`miner_limit.go`**, **`spinlock.go`**, **`sync.go`** | **Yes** |
| **`wemix/api`** | **`api.go`** | **Yes** |
| **`wemix/bind`** | **`const.go`**, **`gen_ballotStorage_abi.go`**, **`gen_envStorage_abi.go`**, **`gen_gov_abi.go`**, **`gen_ncpExit_abi.go`**, **`gen_registry_abi.go`**, **`gen_staking_abi.go`**, **`structs.go`** | **Yes** |
| **`wemix/metclient`** | **`tx_params.go`**, **`util.go`** | **Yes** |
| **`wemix/miner`** | **`miner.go`** | **Yes** |
> **`consensus/` 참고**: Wemix는 별도의 `consensus/wemix` 패키지를 두지 않는다. `consensus/clique` 위에 `wemix/admin.go` + `wemix/etcdutil.go`(etcd 기반 마이닝 토큰 락) + Solidity 거버넌스 컨트랙트(Registry/Gov/Staking/EnvStorage 등)를 조합해 합의·운영 레이어를 구현하고, `wemix/miner/miner.go`가 함수 변수 IoC로 PoA 풀에 wemix 보상 분배를 주입한다.

> **`ethdb/rocksdb` 참고**: darwin에서는 `norocksdb.go`(build tag `!rocksdb`) 하나만 잡힌다. Linux + `USE_ROCKSDB=YES`에서는 `-tags rocksdb`가 켜지면서 `rocksdb.go`로 교체된다.

> **빌드에 포함되지 않는 wemix 하위 디렉토리** (존재해도 바이너리에 들어가지 않음):
> - `wemix/bind/backends/` — `wemix_simulated.go`, `options.go` (테스트 전용 시뮬레이션 백엔드)
> - `wemix/governance-contract/` — Solidity 소스 + `compiler.go` + `solcdownloader/` + `test/`
> - `wemix/scripts/` — `gwemix.sh`, `config.json.example`, `genesis-template.json` (런타임 자산, tarball에 동봉)
> - `wemix/etcdutil.go.new` — `.go.new` 확장자라 Go 빌드 대상이 아닌 보관 파일. **운영 코드는 `etcdutil.go`**

---

## 3. `gwemix` 의존 패키지의 테스트 코드 (85 패키지, 302 파일)

`go list -deps ./cmd/gwemix`가 잡아낸 120개 패키지 중 테스트 파일을 가진 85개 패키지의 목록이다. 테스트 파일 자체는 바이너리에 포함되지 않지만, **`make test` / `make test-short`가 이 파일들을 실행**하므로 빌드 참여 코드를 수정할 때 함께 확인해야 할 대상이다.

### 3.1 Wemix 고유 코드의 테스트 (수정 시 필수 확인)

| 패키지 | 테스트 파일 | 커버 대상 |
|--------|------------|-----------|
| `wemix` | `rewards_test.go` | `distributeRewards` 4-way 분배, 보상 검증, Brioche halving 곡선 — `TestDistributeRewards`, `TestRewardValidation`, `TestBriocheHardFork` |
| `wemix` | `etcd_test.go` | 임베디드 etcd 위에서 `etcdResetWork` CAS 동작 — `TestEtcdResetWork_{TokenHeld,TokenMismatch,TokenAbsent,ExpiredThenSuperseded,NotReady}` |
| `wemix` | `sync_regression_test.go` | StatusEx 위조 / `wemixWorkKey` 오염 회귀 방어 (32KB). `TestRegression_SpoofedStatusExPoisonsWorkKey`, `TestNodeNameRebind_PreventsQuorumForgery`, `TestRegression_NilLatestBlockTdPanicsHandler`, `TestRegression_NilLatestBlockHeightPanicsElectNextMiner`, `TestRegression_StaleConsensusHeightBlocked`, `TestRegression_EndToEndAttackChain` |
| `wemix/api` | `api_test.go` | `WemixMinerStatus.Clone()` nil-safe 복사 — `TestWemixMinerStatus_Clone_NilSafe`, `..._DeepCopiesBigInts` |
| `cmd/gwemix` | `governancedeploy_test.go` | 거버넌스 배포 커맨드 |
| `cmd/gwemix` | `genesis_test.go`, `dao_test.go`, `les_test.go`, `accountcmd_test.go`, `consolecmd_test.go`, `run_test.go`, `version_check_test.go` | CLI/제네시스/콘솔 통합 |
| `core/types` | `transaction_test.go` | Fee Delegation 서명·조립 — `TestRecoverFeePayer`, `TestAsMessageFeeDelegation`, `TestSetSenderTxAccessListPreserved` |
| `core/types` | `transaction_signing_test.go` | Sender/FeePayer 서명자 분리 |
| `eth/protocols/eth` | `handler_test.go`, `handshake_test.go`, `peer_test.go`, `protocol_test.go` | `wemix_handlers.go`가 얹히는 프로토콜 레이어 |
| `p2p/rlpx` | `rlpx_oracle_poc_test.go` | RLPx 핸드셰이크 오라클 PoC (업스트림 보안 동기화) |
| `params` | `config_test.go` | 하드포크 순서/호환성 (`CheckConfigForkOrder`, `CheckCompatible`) |

### 3.2 빌드 의존성 밖에 있는 Wemix 테스트

`go list -deps ./cmd/gwemix`에 잡히지 않으므로 위 표에는 없지만, Wemix 기능 검증의 핵심이다:

| 위치 | 파일 | 내용 |
|------|------|------|
| `wemix/bind/backends/` | `wemix_simulated_test.go` | 거버넌스 컨트랙트 시뮬레이션 백엔드 |
| `wemix/governance-contract/test/` | `gov_test.go` | GovImp 거버넌스 시나리오 — 멤버 추가/제거, 투표, 실행, 레거시 업그레이드. `TestGov`, `TestGov_IndexCorruptionAfterRemoveMember`, `TestW1G01`~`TestW1G04` 계열(CertiK W1G 대응), `TestW1G_LegacyUpgrade_FullLifecycle` |
| `wemix/governance-contract/test/` | `gov_bind_test.go` | abigen 바인딩 정합성 |
| `wemix/governance-contract/contracts/mock/` | `GovImpLegacy.sol`, `GovImpPreMarker.sol` | red→green 회귀 검증용 구(舊) 구현 픽스처. 수정 금지 — 취약했던 시점의 동작을 그대로 보존해야 테스트가 성립한다 |

### 3.3 전체 테스트 파일 목록 (패키지별)

#### accounts/ (5 패키지, 21 파일)

| 패키지 | 파일 |
|--------|------|
| `accounts` | `accounts_test.go`, `hd_test.go`, `url_test.go` |
| `accounts/abi` | `abi_test.go`, `event_test.go`, `method_test.go`, `pack_test.go`, `packing_test.go`, `reflect_test.go`, `selector_parser_test.go`, `topics_test.go`, `type_test.go`, `unpack_test.go` |
| `accounts/abi/bind` | `base_test.go`, `bind_test.go`, `util_test.go` |
| `accounts/abi/bind/backends` | `simulated_test.go` |
| `accounts/keystore` | `account_cache_test.go`, `keystore_test.go`, `passphrase_test.go`, `plain_test.go` |

#### cmd/ (2 패키지, 12 파일)

| 패키지 | 파일 |
|--------|------|
| `cmd/gwemix` | `accountcmd_test.go`, `consolecmd_test.go`, `dao_test.go`, `genesis_test.go`, `governancedeploy_test.go`, `les_test.go`, `run_test.go`, `version_check_test.go` |
| `cmd/utils` | `customflags_test.go`, `export_test.go`, `flags_test.go`, `prompt_test.go` |

#### common/ (7 패키지, 15 파일)

| 패키지 | 파일 |
|--------|------|
| `common` | `bytes_test.go`, `size_test.go`, `types_test.go` |
| `common/bitutil` | `bitutil_test.go`, `compress_test.go` |
| `common/fdlimit` | `fdlimit_test.go` |
| `common/hexutil` | `hexutil_test.go`, `json_example_test.go`, `json_test.go` |
| `common/math` | `big_test.go`, `integer_test.go` |
| `common/mclock` | `simclock_test.go` |
| `common/prque` | `lazyqueue_test.go`, `prque_test.go`, `sstack_test.go` |

#### consensus/ (3 패키지, 7 파일)

| 패키지 | 파일 |
|--------|------|
| `consensus/clique` | `clique_test.go`, `snapshot_test.go` |
| `consensus/ethash` | `algorithm_test.go`, `consensus_test.go`, `ethash_test.go`, `sealer_test.go` |
| `consensus/misc` | `eip1559_test.go` |

#### console/ (1 패키지, 2 파일)

| 패키지 | 파일 |
|--------|------|
| `console` | `bridge_test.go`, `console_test.go` |

#### contracts/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `contracts/checkpointoracle` | `oracle_test.go` |

#### core/ (8 패키지, 54 파일)

| 패키지 | 파일 |
|--------|------|
| `core` | `bench_test.go`, `block_validator_test.go`, `blockchain_repair_test.go`, `blockchain_sethead_test.go`, `blockchain_snapshot_test.go`, `blockchain_test.go`, `chain_indexer_test.go`, `chain_makers_test.go`, `dao_test.go`, `genesis_test.go`, `headerchain_test.go`, `rlp_test.go`, `state_processor_test.go`, `tx_list_test.go`, `tx_pool_test.go` |
| `core/bloombits` | `generator_test.go`, `matcher_test.go`, `scheduler_test.go` |
| `core/forkid` | `forkid_test.go` |
| `core/rawdb` | `accessors_chain_test.go`, `accessors_indexes_test.go`, `chain_iterator_test.go`, `database_test.go`, `freezer_meta_test.go`, `freezer_table_test.go`, `freezer_test.go`, `freezer_utils_test.go`, `key_length_iterator_test.go`, `table_test.go` |
| `core/state` | `iterator_test.go`, `state_object_test.go`, `state_test.go`, `statedb_test.go`, `sync_test.go`, `trie_prefetcher_test.go` |
| `core/state/snapshot` | `difflayer_test.go`, `disklayer_test.go`, `generate_test.go`, `holdable_iterator_test.go`, `iterator_test.go`, `snapshot_test.go` |
| `core/types` | `block_test.go`, `bloom9_test.go`, `hashing_test.go`, `log_test.go`, `receipt_test.go`, `transaction_signing_test.go`, `transaction_test.go`, `types_test.go` |
| `core/vm` | `analysis_test.go`, `contracts_test.go`, `gas_table_test.go`, `instructions_test.go`, `interpreter_test.go` |

#### crypto/ (7 패키지, 18 파일)

| 패키지 | 파일 |
|--------|------|
| `crypto` | `crypto_test.go`, `signature_test.go` |
| `crypto/blake2b` | `blake2b_f_test.go`, `blake2b_test.go` |
| `crypto/bls12381` | `bls12_381_test.go`, `field_element_test.go`, `fp_test.go`, `g1_test.go`, `g2_test.go`, `pairing_test.go` |
| `crypto/bn256/cloudflare` | `bn256_test.go`, `example_test.go`, `gfp_test.go`, `lattice_test.go`, `main_test.go` |
| `crypto/ecies` | `ecies_test.go` |
| `crypto/secp256k1` | `secp256_test.go` |
| `crypto/vrf` | `vrf_test.go` |

#### eth/ (11 패키지, 28 파일)

| 패키지 | 파일 |
|--------|------|
| `eth` | `api_test.go`, `handler_eth_test.go`, `handler_test.go`, `sync_test.go` |
| `eth/catalyst` | `api_test.go` |
| `eth/downloader` | `downloader_test.go`, `queue_test.go`, `skeleton_test.go`, `testchain_test.go` |
| `eth/fetcher` | `block_fetcher_test.go`, `tx_fetcher_test.go` |
| `eth/filters` | `api_test.go`, `bench_test.go`, `filter_system_test.go`, `filter_test.go` |
| `eth/gasprice` | `feehistory_test.go`, `gasprice_test.go` |
| `eth/protocols/eth` | `handler_test.go`, `handshake_test.go`, `peer_test.go`, `protocol_test.go` |
| `eth/protocols/snap` | `range_test.go`, `sort_test.go`, `sync_test.go` |
| `eth/tracers` | `api_test.go`, `tracers_test.go` |
| `eth/tracers/js` | `tracer_test.go` |
| `eth/tracers/logger` | `logger_test.go` |

#### ethclient/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `ethclient` | `ethclient_test.go` |

#### ethdb/ (2 패키지, 2 파일)

| 패키지 | 파일 |
|--------|------|
| `ethdb/leveldb` | `leveldb_test.go` |
| `ethdb/memorydb` | `memorydb_test.go` |

#### ethstats/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `ethstats` | `ethstats_test.go` |

#### event/ (1 패키지, 7 파일)

| 패키지 | 파일 |
|--------|------|
| `event` | `event_test.go`, `example_feed_test.go`, `example_scope_test.go`, `example_subscription_test.go`, `example_test.go`, `feed_test.go`, `subscription_test.go` |

#### graphql/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `graphql` | `graphql_test.go` |

#### internal/ (1 패키지, 2 파일)

| 패키지 | 파일 |
|--------|------|
| `internal/jsre` | `completion_test.go`, `jsre_test.go` |

#### les/ (8 패키지, 32 파일)

| 패키지 | 파일 |
|--------|------|
| `les` | `api_test.go`, `distributor_test.go`, `fetcher_test.go`, `handler_test.go`, `odr_test.go`, `peer_test.go`, `pruner_test.go`, `request_test.go`, `sync_test.go`, `ulc_test.go` |
| `les/catalyst` | `api_test.go` |
| `les/downloader` | `downloader_test.go`, `queue_test.go`, `testchain_test.go` |
| `les/fetcher` | `block_fetcher_test.go` |
| `les/flowcontrol` | `manager_test.go` |
| `les/utils` | `exec_queue_test.go`, `expiredvalue_test.go`, `limiter_test.go`, `timeutils_test.go`, `weighted_select_test.go` |
| `les/vflux/client` | `fillset_test.go`, `queueiterator_test.go`, `requestbasket_test.go`, `serverpool_test.go`, `timestats_test.go`, `valuetracker_test.go`, `wrsiterator_test.go` |
| `les/vflux/server` | `balance_test.go`, `clientdb_test.go`, `clientpool_test.go`, `prioritypool_test.go` |

#### light/ (1 패키지, 4 파일)

| 패키지 | 파일 |
|--------|------|
| `light` | `lightchain_test.go`, `odr_test.go`, `trie_test.go`, `txpool_test.go` |

#### log/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `log` | `format_test.go` |

#### metrics/ (2 패키지, 19 파일)

| 패키지 | 파일 |
|--------|------|
| `metrics` | `counter_test.go`, `debug_test.go`, `ewma_test.go`, `gauge_float64_test.go`, `gauge_test.go`, `graphite_test.go`, `histogram_test.go`, `init_test.go`, `json_test.go`, `meter_test.go`, `metrics_test.go`, `opentsdb_test.go`, `registry_test.go`, `resetting_timer_test.go`, `runtime_test.go`, `sample_test.go`, `timer_test.go`, `writer_test.go` |
| `metrics/prometheus` | `collector_test.go` |

#### miner/ (1 패키지, 3 파일)

| 패키지 | 파일 |
|--------|------|
| `miner` | `miner_test.go`, `unconfirmed_test.go`, `worker_test.go` |

#### node/ (1 패키지, 6 파일)

| 패키지 | 파일 |
|--------|------|
| `node` | `api_test.go`, `config_test.go`, `node_example_test.go`, `node_test.go`, `rpcstack_test.go`, `utils_test.go` |

#### p2p/ (12 패키지, 34 파일)

| 패키지 | 파일 |
|--------|------|
| `p2p` | `dial_test.go`, `message_test.go`, `peer_test.go`, `server_test.go`, `transport_test.go`, `util_test.go` |
| `p2p/discover` | `table_test.go`, `table_util_test.go`, `v4_lookup_test.go`, `v4_udp_test.go`, `v5_udp_test.go` |
| `p2p/discover/v4wire` | `v4wire_test.go` |
| `p2p/discover/v5wire` | `crypto_test.go`, `encoding_test.go` |
| `p2p/dnsdisc` | `client_test.go`, `sync_test.go`, `tree_test.go` |
| `p2p/enode` | `idscheme_test.go`, `iter_test.go`, `localnode_test.go`, `node_test.go`, `nodedb_test.go`, `urlv4_test.go` |
| `p2p/enr` | `enr_test.go` |
| `p2p/msgrate` | `msgrate_test.go` |
| `p2p/nat` | `nat_test.go`, `natupnp_test.go` |
| `p2p/netutil` | `error_test.go`, `iptrack_test.go`, `net_test.go` |
| `p2p/nodestate` | `nodestate_test.go` |
| `p2p/rlpx` | `buffer_test.go`, `rlpx_oracle_poc_test.go`, `rlpx_test.go` |

#### params/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `params` | `config_test.go` |

#### rlp/ (1 패키지, 7 파일)

| 패키지 | 파일 |
|--------|------|
| `rlp` | `decode_tail_test.go`, `decode_test.go`, `encbuffer_example_test.go`, `encode_test.go`, `encoder_example_test.go`, `iterator_test.go`, `raw_test.go` |

#### rpc/ (1 패키지, 8 파일)

| 패키지 | 파일 |
|--------|------|
| `rpc` | `client_example_test.go`, `client_test.go`, `http_test.go`, `server_test.go`, `subscription_test.go`, `testservice_test.go`, `types_test.go`, `websocket_test.go` |

#### signer/ (1 패키지, 1 파일)

| 패키지 | 파일 |
|--------|------|
| `signer/core/apitypes` | `signed_data_internal_test.go` |

#### trie/ (1 패키지, 10 파일)

| 패키지 | 파일 |
|--------|------|
| `trie` | `database_test.go`, `encoding_test.go`, `iterator_test.go`, `node_test.go`, `proof_test.go`, `secure_trie_test.go`, `stacktrie_test.go`, `sync_test.go`, `trie_test.go`, `util_test.go` |

#### wemix/ (2 패키지, 4 파일)

| 패키지 | 파일 |
|--------|------|
| **`wemix`** | **`etcd_test.go`**, **`rewards_test.go`**, **`sync_regression_test.go`** |
| **`wemix/api`** | **`api_test.go`** |
---

## 4. Wemix 고유 코드 식별

go-ethereum 원본에 없는 Wemix 전용 패키지 및 파일.

### 4.1 전용 패키지 (geth에 없는 패키지)

| 패키지 | 빌드 파일 수 | 설명 |
|--------|---------|------|
| `wemix` | 5 | wemixAdmin — 거버넌스 조회, etcd 마이닝 토큰, 보상 분배, 멤버십 동기화 |
| `wemix/api` | 1 | `WemixMinerStatus` 타입 + 마이너 상태 이벤트 구독 API |
| `wemix/bind` | 8 | abigen 생성 Go 바인딩 (Registry, Gov, Staking, BallotStorage, EnvStorage, NCPExit) — 수동 편집 금지 |
| `wemix/metclient` | 2 | 트랜잭션 파라미터/유틸 헬퍼 (거버넌스 호출용) |
| `wemix/miner` | 1 | 표준 miner ↔ wemix 정책의 함수 변수 IoC 경계 |
| `cmd/gwemix` | 12 | Wemix 메인 클라이언트 + 거버넌스 배포 커맨드 |
| `cmd/logrot` | 1 | 로그 로테이션 진입점 (외부 모듈 wrapper) |

### 4.2 기존 패키지 내 Wemix 고유 파일

| 파일 | 패키지 | 설명 |
|------|--------|------|
| `core/wemix_genesis.go` | `core` | Wemix Mainnet/Testnet 제네시스 JSON (대규모 alloc, 하드포크 블록 매핑) |
| `core/types/feedelegate_dynamic_fee_tx.go` | `core/types` | Fee Delegation EIP-1559 트랜잭션 (Sender + FeePayer 이중 서명, TxType `0x16`) |
| `eth/protocols/eth/wemix_handlers.go` | `eth/protocols/eth` | Wemix 전용 eth 프로토콜 메시지 핸들러 (`handleStatusEx` 등) |
| `params/wemix_config.go` | `params` | Wemix Mainnet/Testnet 부트노드 + `WemixGenesisFile` 전역 |
| `params/config.go` *(부분)* | `params` | `PangyoBlock`, `ApplepieBlock`, `BriocheBlock`, `CroissantBlock`, `BriocheConfig`, `IsPangyo/IsApplepie/IsBrioche/IsCroissant`, `Rules.IsPangyo/...` |
| `ethdb/rocksdb/*.go` | `ethdb/rocksdb` | RocksDB 백엔드 (Linux 빌드 시 정적 링크) |

### 4.3 geth 원본 파일 안의 Wemix 분기 (Partial)

| 파일 | Wemix 분기 |
|------|-----------|
| `cmd/utils/flags.go` | `WemixGenesisFile` 처리, `--miner.threads` 강제 1 등 |
| `core/tx_pool.go` | Fee Delegation 검증 (`types.RecoverFeePayer`) + Applepie 게이팅 |
| `core/types/transaction.go` | `FeeDelegateDynamicFeeTxType = 22`, `AsMessage`의 feePayer 검증 |
| `core/types/transaction_signing.go` | `NewFeeDelegateSigner`, `FeePayer`, `RecoverFeePayer`, `ErrFeePayerNotSet`, `ErrInvalidFeePayer` |
| `core/state_transition.go` | FeePayer 잔액 차감 |
| `light/txpool.go` | 라이트 클라이언트 측 Fee Delegation 검증 |
| `internal/ethapi/api.go` | `SignRawFeeDelegateTransaction` 등 RPC |
| `miner/worker.go` | wemixminer 함수 변수 경유 보상/서명 주입 |

---

## 5. 카테고리별 패키지/파일 수 집계

`gwemix` 기준. 테스트 열은 §3의 테스트 파일 수.

| 카테고리 | 빌드 패키지 | 빌드 파일 | 테스트 패키지 | 테스트 파일 |
|----------|----------:|--------:|------------:|----------:|
| Root | 1 | 1 | — | — |
| accounts/ | 9 | 50 | 5 | 21 |
| cmd/ | 2 | 18 | 2 | 12 |
| common/ | 8 | 21 | 7 | 15 |
| consensus/ | 5 | 18 | 3 | 7 |
| console/ | 2 | 3 | 1 | 2 |
| contracts/ | 2 | 2 | 1 | 1 |
| core/ | 10 | 124 | 8 | 54 |
| crypto/ | 8 | 40 | 7 | 18 |
| eth/ | 14 | 71 | 11 | 28 |
| ethclient/ | 1 | 2 | 1 | 1 |
| ethdb/ | 5 | 8 | 2 | 2 |
| ethstats/ | 1 | 1 | 1 | 1 |
| event/ | 1 | 3 | 1 | 7 |
| graphql/ | 1 | 4 | 1 | 1 |
| internal/ | 8 | 20 | 1 | 2 |
| les/ | 10 | 65 | 8 | 32 |
| light/ | 1 | 7 | 1 | 4 |
| log/ | 1 | 8 | 1 | 1 |
| metrics/ | 4 | 35 | 2 | 19 |
| miner/ | 1 | 5 | 1 | 3 |
| node/ | 1 | 10 | 1 | 6 |
| p2p/ | 13 | 47 | 12 | 34 |
| params/ | 1 | 8 | 1 | 1 |
| rlp/ | 2 | 9 | 1 | 7 |
| rpc/ | 1 | 18 | 1 | 8 |
| signer/ | 1 | 1 | 1 | 1 |
| trie/ | 1 | 14 | 1 | 10 |
| wemix/ | 5 | 17 | 2 | 4 |
| **합계** | **120** | **630** | **85** | **302** |

---

## 6. Wemix 하드포크 이력

| 하드포크 | Mainnet 블록 | Testnet 블록 | 주요 변경 |
|----------|------------:|------------:|-----------|
| (제네시스) | 0 | 0 | Wemix PoA + Governance Contract v1 (Registry, Gov, Staking, BallotStorage, EnvStorage) |
| Pangyo | 0 | 10,000,000 | 거버넌스 활성화 임계 / 멤버십 운영 정책 |
| Applepie | 20,476,911 | 26,240,268 | Fee Delegation 트랜잭션 활성화 (`feedelegate_dynamic_fee_tx.go`) |
| Brioche | 53,525,500 (≈24-07-01 KST) | 59,414,700 (≈24-06-04 KST) | 블록 보상 halving 곡선 (`BriocheConfig.GetBriocheBlockReward`)이 `EnvStorageImp.getBlockRewardAmount()`를 대체 |
| Croissant | **미설정 (nil)** | **미설정 (nil)** | WBFT 합의 전환 — 별도 빌드(go-wbft)에서 처리. `params/config.go`에 필드·`IsCroissant`·포크 순서 검사만 준비되어 있고 활성 블록은 아직 없음 |

`Brioche` halving 파라미터 (Mainnet/Testnet 동일): `BlockReward = 1e18`, `HalvingPeriod = 63,115,200`, `HalvingTimes = 16`, `HalvingRate = 50`.
`FinishRewardBlock`: Mainnet `2,467,714,000` (≈2101-01-01 KST) / Testnet `2,473,258,000` (≈2100-12-01 KST).

> **주의**: `CheckCompatible`의 Croissant 에러 문자열은 `"Mont Blanc fork block"`으로 남아 있다 (`params/config.go:770`). 개발 이력상의 잔재이므로 로그를 grep할 때 유의.

---

## 7. 플랫폼/빌드 태그 차이

본 목록은 `darwin/arm64` + `USE_ROCKSDB=NO` 기준이다. `linux/amd64` + `USE_ROCKSDB=YES`에서 달라지는 부분:

| 패키지 | darwin/arm64 | linux/amd64 (rocksdb) |
|--------|--------------|----------------------|
| `common/fdlimit` | `fdlimit_darwin.go` | `fdlimit_unix.go` |
| `ethdb/rocksdb` | `norocksdb.go` (`!rocksdb`) | `rocksdb.go` (`rocksdb` 태그, CGO 정적 링크) |
| `crypto/secp256k1` | `curve.go`, `panic_cb.go`, `scalar_mult_cgo.go`, `secp256.go` | 동일 + 어셈블리 변형 차이 |
| `rpc` | `constants_unix.go`, `ipc_unix.go` | 동일 (unix 계열 공통) |
| `metrics` | `cputime_unix.go`, `runtime_cgo.go` | 동일 |

`make gwemix-linux`는 `Dockerfile.wemix`로 빌더 이미지를 만들고 컨테이너 안에서 `make USE_ROCKSDB=YES`를 실행한다.

---

## 8. 참고 사항

- 외부 의존성(third-party 모듈)은 이 목록에 포함되지 않는다. 전체 외부 의존성은 `go.mod` 참조 (module path: `github.com/ethereum/go-ethereum`, 선언 Go 버전 1.19).
- `build/ci.go` 자체는 `//go:build none` 태그로 일반 빌드에서 제외되며 `go run`으로만 실행된다. Makefile은 이 파일의 wrapper다.
- `wemix/governance-contract/`의 Solidity 소스와 `compiler.go`는 `go generate` 또는 `cmd/gwemix governancedeploy` 워크플로우에서만 쓰이고, 일반 `make gwemix` 빌드에는 들어가지 않는다. 단, `wemix/bind/gen_*_abi.go`에 이미 컴파일된 ABI/바이트코드가 임베드되어 있다.
- `wemix/admin.go`는 약 43KB, `wemix/etcdutil.go`는 약 29KB, `wemix/sync.go`는 약 15KB의 단일 파일이다 — 수정 시 함수 단위로 신중하게 변경하고 무관한 영역 동시 편집을 피한다.
- `wemix/sync_regression_test.go`(32KB)는 StatusEx 위조·workKey 오염 공격 체인의 **pre-fix 재현 / post-fix 방어**를 쌍으로 검증한다. 관련 코드(`eth/protocols/eth/wemix_handlers.go`, `wemix/sync.go`, `wemix/api/api.go`, `wemix/miner_limit.go`)를 수정하면 반드시 함께 실행할 것.

### 이 문서 재생성 방법

```bash
# 빌드 참여 파일
go list -deps -f '{{.ImportPath}}|{{range .GoFiles}}{{.}} {{end}}{{range .CgoFiles}}{{.}} {{end}}' \
  ./cmd/gwemix | grep '^github.com/ethereum/go-ethereum'

# 테스트 파일
go list -deps -f '{{.ImportPath}}|{{range .TestGoFiles}}{{.}} {{end}}{{range .XTestGoFiles}}{{.}} {{end}}' \
  ./cmd/gwemix | grep '^github.com/ethereum/go-ethereum'

# logrot
go list -deps ./cmd/logrot
```
