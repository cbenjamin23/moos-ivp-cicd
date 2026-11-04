# H02 uField Broker Bridge Harness

This harness exercises broker-level setup for `uFldNodeBroker` and
`uFldShoreBroker` using the shared `ufield_comms_unit` mission stem.

The evaluated surface is node broker ping publication, shore broker ack
publication, node-count registration, shoreside qbridge expansion, shoreside
custom bridge expansion, node-side user bridge registration, `NODE_PSHARE_VARS`
publication, keyword mismatch rejection, shoreside bridge token
expansion, mediated node-message bridge selection, vnode shore discovery
publication, shoreside and node-side auto-bridge suppression, and default
alias/default vnode-port handling.

Logging defaults to `--log=minimal`. Because the supplemental route checks
grade selected `.alog` evidence, minimal keeps one asynchronous logger per
community with only the required broker/pShare variables. `--log=full`
restores the original wildcard loggers for every selected case.

Run one case:

```sh
./zlaunch.sh --case=broker_handshake_pass --port_base=4000
./zlaunch.sh --log=full --case=broker_handshake_pass --port_base=4000
```

Run the 11 core cases:

```sh
./zlaunch.sh --core_only --jobs=2 --port_base=4000
```

The full 12-case matrix includes `node_mediated_bridge_pass`, which requires
the separately built `pMediator` app from `moos-ivp-swarm` on PATH. Add that
repository's `bin/` directory to PATH, then run without `--core_only`.
A live run selecting that case fails before creating workdirs or starting
MOOS apps when the dependency is missing. `--just_make` can generate targets
without the extension. Combining `--core_only` with an explicit mediation
case is rejected rather than silently omitting the requested case.

Live supplemental log checks also require `ripgrep` (`rg`) on PATH. Missing
`rg` fails preflight before creating a run; `--just_make` does not require it.

## Current Matrix

- `broker_handshake_pass` Runs the ordinary Abe and Ben brokers; passes when each vehicle independently logs the exact normal `NODE_PSHARE_VARS` alias set and its `status=ok,key=0` acknowledgement, while shoreside logs both named pings, acknowledgements, and vacks and the ordinary bridged traffic still flows.
- `shore_qbridge_expansion_pass` Configures the normal `NODE_REPORT`, `NODE_MESSAGE`, and `ACK_MESSAGE` qbridge set; passes when the exact qbridge summary includes those core and automatic request variables and shoreside logs the expected all/Abe/Ben report, Ben message, and Abe acknowledgement `PSHARE_CMD` expansions.
- `shore_custom_bridge_pass` Adds `bridge=src=DEPLOY_$V,alias=DEPLOY`; passes when the exact bridge summary contains the template plus `DEPLOY_ABE` and `DEPLOY_BEN`, and shoreside logs both corresponding `src_name=DEPLOY_<V>,dest_name=DEPLOY` commands.
- `node_custom_bridge_pass` Adds `src=CUSTOM_LOCAL,alias=CUSTOM_SHARED` to both node brokers; passes when the exact node alias summary begins with `CUSTOM_SHARED` and each vehicle log contains its `CUSTOM_LOCAL` to `CUSTOM_SHARED` pShare command.
- `keyword_mismatch_status_pass` Gives the shore broker keyword `shoreside_only` while the node brokers use their normal handshake; passes when the mission observes an incoming broker ping but no broker acknowledgement, no enrolled nodes, and no delivered traffic. The legacy case token is retained; an invalid keyword is a refusal rather than an acknowledgement status.
- `shore_bridge_tokens_pass` Adds `STATUS_$v -> STATUS` and `INDEX_$N -> INDEXED_STATUS`; passes when the exact bridge summary contains the templates and expansions and shoreside logs commands for `STATUS_abe`, `STATUS_ben`, `INDEX_1`, and `INDEX_2` with their expected aliases.
- `node_mediated_bridge_pass` Replaces each node broker's `NODE_MESSAGE_LOCAL` bridge with `MEDIATED_MESSAGE_LOCAL` and runs `pMediator`; passes when both vehicle logs contain the mediated command and lack the unmediated command, the exact node alias summary names `MEDIATED_MESSAGE`, and a mediated Abe-to-Ben message is delivered with ordinary reports and acknowledgement.
- `shore_try_vnode_pass` Configures `try_vnode=route=127.0.0.1:4999`; passes when shoreside logs the exact `TRY_SHORE_HOST` pShare route to that endpoint and the mission summary also contains the ordinary local `TRY_SHORE_HOST=pshare_route=localhost:<vehicle-port>` advertisement.
- `shore_minimal_autobridge_pass` Disables automatic realmcast, appcast, and mission-hash bridges at shoreside; passes when the exact qbridge summary is only `ACK_MESSAGE,NODE_MESSAGE,NODE_REPORT` and the exact expanded bridge summary contains only broker-ack, message, report, and all/Abe/Ben variants while ordinary traffic still flows.
- `node_minimal_autobridge_pass` Disables node-side realmcast, appcast, and `NODE_PSHARE_VARS` auto bridges; passes when both vehicle logs advertise exactly `ACK_MESSAGE,NODE_MESSAGE,NODE_REPORT`, neither emits a `NODE_PSHARE_VARS` pShare command, and the core traffic remains intact.
- `shore_default_alias_pass` Adds `bridge=src=FLEET_ALERT` without an alias; passes when `FLEET_ALERT` appears in the exact bridge summary and shoreside logs a command with both `src_name` and `dest_name` equal to `FLEET_ALERT`.
- `shore_try_vnode_default_port_pass` Configures `try_vnode=route=127.0.0.1` without a port; passes when shoreside logs `TRY_SHORE_HOST` routed to `127.0.0.1:9200` and the ordinary broker/bridge summary and local shore-host advertisement remain valid.
