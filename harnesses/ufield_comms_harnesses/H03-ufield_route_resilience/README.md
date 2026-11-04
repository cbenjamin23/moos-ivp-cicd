# H03 uField Route Resilience

This harness reuses the `ufield_comms_unit` stem to test route recovery paths in
`uFldNodeBroker`, `uFldShoreBroker`, and pShare rather than static bridge
configuration. Recovery cases require the base two-node communications mission
to pass; expected-negative cases require mission-owned blocked-route evidence
and still report `grade=pass` when that evidence is observed. All cases add
alog checks for the specific route mechanism under test.

Logging defaults to `--log=minimal`, retaining only the broker-ack, pShare,
and try-host variables required by those supplemental checks. Use
`--log=full` to restore the original wildcard shore and vehicle loggers.
Live supplemental log checks require `ripgrep` (`rg`) on PATH. Missing `rg`
fails preflight before creating a run; `--just_make` does not require it.

On merged upstream revisions from October 2026 onward, runtime shore routes
are opt-in. Fixtures that intentionally use `TRY_SHORE_HOST`, including shore
vnode discovery, set `accept_try_shore_host = true` in `uFldNodeBroker`.
The default-rejection fixture deliberately omits this setting; startup-only
route cases retain the safe default.

Typical runs:

```bash
./zlaunch.sh --jobs=2 --port_base=4000
./zlaunch.sh --case=shore_vnode_discovery_recover_pass --port_base=4000 --gui 10
./zlaunch.sh --log=full --case=shore_vnode_discovery_recover_pass --port_base=4000 10
```

## Cases

- `dead_first_tryhost_blocks_fail` Configures live and dead startup routes so the dead endpoint becomes effective key `0`; the expected-negative case passes when both vehicles emit key `0` and key `1` broker-ping pShare commands, neither receives any `status=ok` acknowledgement, shoreside node count stays zero, and all direct, acknowledgement, and report delivery remains absent.
- `secondary_dead_tryhost_ignored_pass` Configures the same two startup endpoints with the live shore route as effective key `0`; passes when both vehicles emit key `0` and key `1` commands, receive `status=ok,key=0`, and complete the ordinary message, acknowledgement, bidirectional-report, and pulse checks.
- `startup_invalid_bad_port_valid_route_pass` Adds `pshare_route=localhost:notaport` beside a valid startup route; passes when neither vehicle emits a pShare command containing `notaport`, both receive `status=ok,key=0`, and the ordinary communications mission succeeds.
- `startup_invalid_bad_param_valid_route_pass` Adds `shore_route=localhost:<reserved-dead-port>` before a valid startup `pshare_route`; passes when each vehicle creates only the live route as key 0, creates no key 1, receives `status=ok,key=0`, and completes ordinary communications.
- `startup_ip_route_recover_pass` Uses only startup `pshare_route=127.0.0.1:<shore-port>`; passes when both vehicle logs contain numeric-loopback pShare routes and `status=ok,key=0`, followed by the ordinary communications evidence.
- `runtime_tryhost_recover_pass` Removes startup routing and posts a valid `TRY_SHORE_HOST` at mission time 220 to both vehicles; passes when each logs the runtime mail, creates a key `0` broker-ping route, receives `status=ok,key=0`, and completes ordinary communications.
- `runtime_tryhost_default_rejected_pass` Posts the same valid runtime route without opting in; passes when the mission reports zero connected nodes and no message, acknowledgement, or cross-node report delivery, while supplemental logs prove both vehicles received the request but emitted no broker-ping route.
- `runtime_dead_then_valid_blocks_fail` Posts a dead runtime route at time 80 and the live route at 220; the expected-negative case passes when both key `0` and key `1` broker-ping routes are emitted but neither vehicle receives an `ok` acknowledgement, shoreside node count stays zero, and direct, acknowledgement, and report traffic remains absent.
- `runtime_valid_then_dead_stays_pass` Posts the live route at time 120 and a dead route at 620; passes when the later key `1` route is emitted, both vehicles retain `status=ok,key=0`, and the full ordinary communications mission succeeds.
- `runtime_duplicate_tryhost_ignored_pass` Posts the same valid route at times 220 and 260 with no startup route; passes when each vehicle creates only key `0`, no key `1` broker-ping command appears, both receive `status=ok,key=0`, and ordinary communications succeed.
- `startup_duplicate_runtime_ignored_pass` Keeps the valid startup route and reposts it through `TRY_SHORE_HOST` at time 160; passes when the runtime mail is observed but neither vehicle creates a key `1` broker-ping command, both retain `status=ok,key=0`, and ordinary communications succeed.
- `delayed_runtime_tryhost_recover_pass` Removes startup routing and waits until time 700 to post the first valid route; passes when both vehicles log the route, receive `status=ok,key=0`, and later scripted traffic still satisfies the full communications evaluator.
- `late_runtime_tryhost_blocks_delivery_fail` Sends Abe's one-shot message before any route, then establishes the first valid route at time 1700; the expected-negative case passes when the message is not replayed while both brokers later reach `status=ok,key=0` and node count two.
- `runtime_one_node_missing_route_fail` Removes startup routes and posts a valid route only to Abe at time 220; the expected-negative case passes when Abe receives `status=ok,key=0`, Ben never receives an `ok` acknowledgement, shoreside node count is exactly one, and the direct message is absent.
- `runtime_staggered_nodes_recover_pass` Posts Abe's valid route at time 220 and Ben's at 620; passes when both independently receive `status=ok,key=0` and the later ordinary message, acknowledgement, reports, and pulse all arrive.
- `invalid_runtime_tryhost_recover_pass` Posts `pshare_route=not_a_route` at time 300, then the valid route at 600 and repeats it at 800; passes when both logs contain the invalid mail but no pShare command containing `not_a_route`, both receive `status=ok,key=0`, and ordinary communications recover.
- `invalid_runtime_bad_port_recover_pass` Posts `pshare_route=localhost:notaport` before the valid runtime route; passes when the malformed mail is logged, no pShare command contains `notaport`, both brokers receive `status=ok,key=0`, and ordinary communications recover.
- `invalid_runtime_bad_param_recover_pass` Posts `shore_route=localhost:<reserved-dead-port>` before the valid runtime `pshare_route`; passes when the malformed mail consumes no route key, each vehicle creates only the live route as key 0, receives `status=ok,key=0`, and ordinary communications recover.
- `runtime_ip_route_recover_pass` Removes startup routing and posts `pshare_route=127.0.0.1:<shore-port>` at time 220; passes when both vehicles log the numeric-loopback mail and pShare route, receive `status=ok,key=0`, and complete ordinary communications.
- `shore_vnode_discovery_recover_pass` Removes vehicle startup routes and configures shoreside `try_vnode` entries for both vehicle pShare ports; passes when shoreside emits `TRY_SHORE_HOST` route commands, both vehicles receive the discovery mail and `status=ok,key=0`, and the ordinary communications evaluator succeeds.
- `shore_vnode_one_node_only_fail` Configures shoreside discovery for Abe's pShare listener only; the expected-negative case passes when Abe receives the discovery route and `status=ok,key=0`, Ben never receives an `ok` acknowledgement, node count is one, and the direct message is absent.
- `shore_vnode_extra_dead_ignored_pass` Configures valid discovery routes for Abe and Ben followed by an unused numeric port; passes when shoreside emits discovery routing, both live vehicles receive `status=ok,key=0`, and ordinary communications succeed despite the extra endpoint.
- `shore_vnode_default_port_no_listener_fail` Configures `try_vnode=route=127.0.0.1` with no port; the expected-negative case passes when shoreside emits the default `127.0.0.1:9200` route, neither vehicle receives an `ok` acknowledgement, node count remains zero, and direct, acknowledgement, and report delivery is absent.
- `shore_vnode_invalid_host_ignored_pass` Configures `badhost:<Abe-port>` before the two valid numeric-loopback vnode routes; passes when no shoreside pShare command contains `badhost`, both brokers receive `status=ok,key=0`, and ordinary communications succeed.
- `shore_vnode_bad_port_ignored_pass` Configures `127.0.0.1:notaport` before the two valid vnode routes; passes when no shoreside pShare command contains `notaport`, both brokers receive `status=ok,key=0`, and ordinary communications succeed.
- `shore_vnode_duplicate_ignored_pass` Configures Abe's vnode route twice before Ben's route; passes when only the two unique endpoints are emitted, minimal-log route counts stay balanced or the full log contains uFldShoreBroker's duplicate-route rejection warning, both vehicles receive `status=ok,key=0`, and ordinary communications succeed.

## Evaluation

`pMissionEval` owns the mission grade. Recovery cases require two brokered
nodes, direct message delivery, ack delivery, cross-node report delivery, pulse
evidence, and no shared-report leakage. Expected-negative cases replace those
criteria with the corresponding blocked-route evidence and include an
`expected=<scenario>` result field. The harness supplements the mission grade
with targeted alog metrics: exact pShare command routes, broker ack keys,
runtime `TRY_SHORE_HOST` mail, and absence of pShare output for invalid route
strings.
