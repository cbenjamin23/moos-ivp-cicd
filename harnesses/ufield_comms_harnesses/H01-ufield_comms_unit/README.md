# H01 uField Comms Unit Harness

This harness exercises the core `uFldNodeBroker`, `uFldShoreBroker`, and
`uFldNodeComms` process interaction with a headless shoreside community and two
vehicle communities.

Logging defaults to `--log=minimal`, which launches no pLogger because the
matrix grades from mission-owned results. Use `--log=full` for the original
wildcard shore and vehicle logs; it composes with `--case=<name>`.

The current evaluated surface is broker registration, direct `NODE_MESSAGE`
delivery, mediated-message routing, `ACK_MESSAGE` delivery, destination resolution, bidirectional
`NODE_REPORT_<VNAME>` distribution, communication pulse posting, range
blocking, critical-range override, group filtering, stealth, enhanced acoustic
range, runtime updates, message/report rate limiting, drop percentage, invalid
message/ack rejection, `stale_time=-1`, `max_msg_length=0`, and
`NODE_REPORT_UNC` sharing.

Run one case:

```sh
./zlaunch.sh --case=baseline_broker_comms_pass --port_base=4000
./zlaunch.sh --log=full --case=baseline_broker_comms_pass --port_base=4000
```

Run the group:

```sh
./zlaunch.sh --jobs=2 --port_base=4000
```

## Current Matrix

- `baseline_broker_comms_pass` Places Abe and Ben 60 meters apart with a 200-meter communication range; passes when both brokers register, Abe's broadcast message reaches Ben, Ben's acknowledgement reaches Abe, both directed node-report variables and a comms pulse appear, and no shared report is published.
- `critical_range_override_pass` Keeps the vehicles 60 meters apart but sets `comms_range=10` and `critical_range=100`; passes when both directed node reports and a pulse are delivered while the direct message and acknowledgement remain blocked by the nominal range.
- `shared_node_reports_pass` Sets `shared_node_reports=true` at the ordinary 60-meter geometry; passes when the baseline deliveries occur and at least one `NODE_REPORT_UNC` is published.
- `pulse_disabled_pass` Sets `view_node_rpt_pulses=false` and `pulse_duration=0`; passes when messages, acknowledgements, and both directed reports are delivered but no `VIEW_COMMS_PULSE` is published.
- `range_block_pass` Sets `comms_range=10` and `critical_range=5` for vehicles 60 meters apart; passes when neither message, acknowledgement, directed report, nor comms pulse is delivered despite both nodes registering.
- `zero_range_block_pass` Sets both ranges to zero at the same 60-meter separation; passes when all message, acknowledgement, directed-report, shared-report, and pulse latches remain false.
- `drop_all_reports_pass` Sets `drop_percentage=100` inside otherwise valid range; passes when all inter-vehicle messages, acknowledgements, reports, and report pulses are absent while both nodes remain registered.
- `far_range_block_pass` Places Abe and Ben 600 meters apart with `comms_range=200` and `critical_range=5`; passes when all range-gated message, acknowledgement, report, and pulse latches remain false.
- `no_limit_far_pass` Keeps the 600-meter geometry but sets `comms_range=nolimit`; passes when Abe's message, Ben's acknowledgement, both directed reports, and a comms pulse are delivered.
- `max_msg_length_block_pass` Sets `max_msg_length=4` while Abe sends the ordinary longer string payload; passes when no direct message reaches Ben but Ben's acknowledgement and both node reports still arrive.
- `dest_specific_message_pass` Sends `dest_node=ben` with `var_name=UFC_DEST` and `string_val=hello_ben`; passes when `NODE_MESSAGE_BEN` exactly preserves the destination, source, app, variable, value, and acknowledgement id, alongside the ordinary ack/report traffic.
- `dest_group_message_pass` Keeps both vehicles in group `red` and sends `dest_group=red`; passes when Ben receives the exact group-addressed `UFC_GROUP=hello_group` payload and the ordinary ack/report traffic remains available.
- `ack_requested_mediated_pass` Sends Abe's named message with `ack=true`; passes when the exact payload appears on `MEDIATED_MESSAGE_BEN`, no `NODE_MESSAGE_BEN` is posted, and the independent acknowledgement and report traffic still arrives.
- `double_val_message_pass` Sends `double_val=3.1415` instead of `string_val`; passes when `NODE_MESSAGE_BEN` exactly preserves the numeric field and all routing metadata.
- `unknown_dest_block_pass` Sends Abe's otherwise valid message to unregistered destination `zed`; passes when no message reaches Ben while the independent acknowledgement, both directed reports, and pulse still arrive.
- `ghost_source_block_pass` Sends an otherwise valid Ben-directed message with unregistered `src_node=ghost`; passes when no message reaches Ben while the independent acknowledgement, both directed reports, and pulse still arrive.
- `invalid_ack_block_pass` Sends Ben's acknowledgement without an `id` while Abe sends a valid broadcast; passes when no `ACK_MESSAGE_abe` appears but the direct message, both reports, and pulse do.
- `msg_group_filter_pass` Places Abe in `red` and Ben in `blue` with `msg_groups=true`; passes when Abe's message is blocked while Ben's acknowledgement, both directed reports, and pulse still arrive.
- `report_group_filter_pass` Places Abe in `red` and Ben in `blue` with `groups=true`; passes when both directed node reports are blocked while the direct message, acknowledgement, and a pulse still arrive.
- `stealth_range_block_pass` Sets `comms_range=100` and `stealth=0.4` for Abe at a 60-meter separation; passes when Abe's outbound message and report to Ben are blocked while Ben's acknowledgement and report to Abe still arrive.
- `earange_extend_pass` Sets `comms_range=40` and gives Ben `earange=2.0` at a 60-meter separation; passes when Abe's message and report reach Ben but Ben's acknowledgement and report cannot reach Abe.
- `stale_message_block_pass` Repeatedly receives node reports whose embedded `TIME=1` is stale under `stale_time=1`; passes when the exact stale Abe report is still fanned out to Ben and both report directions and a pulse appear, but the later message and acknowledgement are blocked.
- `min_msg_interval_filter_pass` Sets `min_msg_interval=5000` and sends two Abe messages five seconds apart in mission time; passes when exactly one `NODE_MESSAGE_BEN` is delivered and it exactly matches the first `UFC_DIRECT=hello_ben` payload.
- `runtime_range_extend_pass` Starts at a 60-meter separation with `comms_range=10`, posts `UNC_COMMS_RANGE=200` before the scripted traffic begins, and passes when the ordinary message, acknowledgement, bidirectional reports, and pulse are subsequently delivered.
- `runtime_stealth_block_pass` Starts with `comms_range=100`, delivers Abe's message and bidirectional reports, then posts `UNC_STEALTH=vname=abe,stealth=0.4` at a 60-meter separation; passes when Ben retains only Abe's exact pre-update message, Abe's later reports no longer reach Ben, and Ben's later reports and both acknowledgements still reach Abe.
- `runtime_earange_extend_pass` Starts at 60 meters with `comms_range=40`, posts `UNC_EARANGE=vname=ben,earange=2.0`, and sends messages before and after the update; passes when only the exact after-update Abe message reaches Ben, Abe's later report reaches Ben, and reverse acknowledgement/report traffic remains blocked.
- `runtime_drop_all_pass` Delivers one message and acknowledgement, posts `UNC_DROP_PCT=100`, and sends a second pair; passes when the final counts remain one each and Ben's only message is the exact before-update payload.
- `runtime_pulse_disabled_pass` Observes early report delivery and pulses, posts `UNC_VIEW_NODE_RPT_PULSES=false`, resets a late-pulse latch, and sends reports again; passes when report delivery remains present but no pulse is observed after the reset.
- `runtime_shared_reports_pass` Starts with sharing disabled, posts `UNC_SHARED_NODE_REPORTS=true` before the first vehicle reports, and passes when the baseline deliveries plus at least one `NODE_REPORT_UNC` appear.
- `shared_node_reports_numeric_pass` Configures `shared_node_reports=0.6` while each vehicle sends ten reports under the harness's default warp `20`; passes when the ordinary directed traffic remains available and exactly four `NODE_REPORT_UNC` posts are shared from the twenty inputs. The local source compares real elapsed time, and the logged default-warp cadence keeps each vehicle's first cluster below the 0.6-second threshold before one later report clears it, so two reports per vehicle are expected. This exact count is intentionally tied to the default warp.
- `min_rpt_interval_filter_pass` Sets `min_rpt_interval=1000` while each vehicle posts ten reports over 480 mission seconds; passes when exactly one report is delivered in each direction and the ordinary message, acknowledgement, and pulse still arrive.
- `stale_time_unlimited_pass` Uses the same `TIME=1` reports with `stale_time=-1`; passes when the exact Abe report reaches Ben and the message, acknowledgement, both report directions, and pulse all remain deliverable.
- `max_msg_length_unlimited_pass` Sets `max_msg_length=0` and sends a 119-character `UFC_LONG` value; passes when `NODE_MESSAGE_BEN` exactly preserves the entire long payload and routing metadata.
- `earrange_alias_extend_pass` Configures Ben's enhancement with the accepted `earrange=2.0` spelling under the `earange` record; passes at 60 meters with a 40-meter base range when Abe's message and report reach Ben but reverse acknowledgement/report traffic does not.
- `critical_group_override_pass` Places Abe and Ben in different groups with `groups=true`, `comms_range=10`, and `critical_range=100`; passes when the critical-range path delivers both directed reports and a pulse across the group boundary while the direct message and acknowledgement remain blocked.
