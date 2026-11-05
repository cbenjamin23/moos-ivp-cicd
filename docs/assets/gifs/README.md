# Visual Asset Manifest

Source render scripts produce GIFs using the filenames below.
Run `python3 docs/tools/convert_gifs_to_mp4.py --delete-source-gifs` after
regenerating visuals so the published GitHub Pages assets are CRF-18 MP4s.
Each harness page references the `.mp4` filename derived from the listed GIF.

Maintainer note: use the harness wrapper command for capture because it applies
case overlays before delegating to shared `xlaunch.sh`. Calling `xlaunch.sh`
directly is useful inside those wrappers, but it is not the case-selection
entry point for the harness pages.

Generated visual standard: app-level unit, classification, and variable-heavy motion pages may use 16:9,
map-style explanatory animations when a raw `pMarineViewer` capture would not make
the pass condition legible. Keep the look close to the PMV captures: dark chart
background, simple ownship/contact/obstacle geometry, compact labels, and one
small pass-condition callout. The callout should name the MOOS publication being
graded, because that is the evidence the harness is actually testing.

Generated unit visuals live in `docs/tools/render_unit_harness_gifs.py`.
Generated COLREGS classification visuals live in
`docs/tools/render_colregs_classification_gifs.py`.
Generated COLREGS threshold overlay visuals live in
`docs/tools/render_colregs_threshold_gifs.py`.
Generated COLREGS parameter comparison visuals live in
`docs/tools/render_colregs_parameter_gifs.py`.
Generated PID motion visuals live in `docs/tools/render_pid_motion_gifs.py`.
Generated Timer behavior visuals live in `docs/tools/render_timer_behavior_gifs.py`.
Generated PeriodicSpeed behavior visuals live in `docs/tools/render_periodic_speed_behavior_gifs.py`.
Generated MemoryTurnLimit behavior visuals live in `docs/tools/render_memoryturnlimit_behavior_gifs.py`.
Generated utility infrastructure visuals live in `docs/tools/render_utility_watch_gifs.py`.
Generated simulator infrastructure visuals live in `docs/tools/render_simulator_infrastructure_gifs.py`.
Generated mission utility visuals live in `docs/tools/render_mission_utility_gifs.py`.
Generated uFldObstacleSim visuals live in `docs/tools/render_ufld_obstacle_sim_gifs.py`.
Generated uField app visuals live in `docs/tools/render_ufield_app_gifs.py`.
Headless harness runs remain the source of truth for the case behavior; the
generated visuals are documentation views of that same geometry and variable-level
evidence.

## H01 Contact Manager Unit

Capture from: `harnesses/cmgr_harnesses/H01-cmgr_unit`
Typical capture launch: `./zlaunch.sh --case=detect_baseline_pass 10`

- source `cmgr-unit-runtime-alert.gif` -> published `cmgr-unit-runtime-alert.mp4` - Runtime Alert Path; representative case `runtime_alert_add_pass`
- source `cmgr-unit-cpa-detection.gif` -> published `cmgr-unit-cpa-detection.mp4` - CPA-only Detection; representative case `detect_cpa_only_pass`

## H02 Contact Manager Motion

Capture from: `harnesses/cmgr_harnesses/H02-cmgr_motion`
Typical capture launch: `./zlaunch.sh --case=baseline_crossing_pass --gui 10`

- source `cmgr-motion-baseline-crossing.gif` -> published `cmgr-motion-baseline-crossing.mp4` - Baseline Crossing Pass; representative case `baseline_crossing_pass`
- source `cmgr-motion-head-on-pass.gif` -> published `cmgr-motion-head-on-pass.mp4` - Head-on Pass; representative case `head_on_pass`
- source `cmgr-motion-two-contact-pmarineviewer.gif` -> published `cmgr-motion-two-contact-pmarineviewer.mp4` - Two Contact Pass; representative case `two_contact_pass`

## H01 Obstacle Manager Unit

Capture from: `harnesses/obmgr_harnesses/H01-obmgr_unit`
Typical capture launch: `./zlaunch.sh --case=given_baseline_pass 10`

- source `obmgr-unit-given-baseline.gif` -> published `obmgr-unit-given-baseline.mp4` - Given Obstacle Alert; representative case `given_baseline_pass`
- source `obmgr-unit-point-cluster.gif` -> published `obmgr-unit-point-cluster.mp4` - Point Cluster Hull; representative case `points_cluster_dist_pass`

## H02 Obstacle Manager Motion

Capture from: `harnesses/obmgr_harnesses/H02-obmgr_motion`
Typical capture launch: `./zlaunch.sh --case=baseline_center_pass --gui 10`

- source `obmgr-motion-baseline-center.gif` -> published `obmgr-motion-baseline-center.mp4` - Baseline Center Pass; representative case `baseline_center_pass`
- source `obmgr-motion-offset-clear.gif` -> published `obmgr-motion-offset-clear.mp4` - Offset Clear Pass; representative case `offset_clear_pass`
- source `obmgr-motion-two-sequential.gif` -> published `obmgr-motion-two-sequential.mp4` - Two Sequential Fail; representative case `two_sequential_fail`

## H01 Marine PID Unit

Capture from: `harnesses/pid_harnesses/H01-pid_unit`
Typical capture launch: `./zlaunch.sh --case=rudder_starboard_pass 10`

- source `pid-unit-heading-wrap.gif` -> published `pid-unit-heading-wrap.mp4` - Heading Wrap; representative case `heading_wrap_pass`
- source `pid-unit-manual-override.gif` -> published `pid-unit-manual-override.mp4` - Manual Override; representative case `manual_override_zero_pass`

## H02 Marine PID Motion

Capture from: `harnesses/pid_harnesses/H02-pid_motion`
Typical capture launch: `./zlaunch.sh --case=baseline_transit_pass --gui 10`

- source `pid-motion-hard-turn-recover.gif` -> published `pid-motion-hard-turn-recover.mp4` - Hard Turn Recovery; representative case `hard_turn_recover_pass`
- source `pid-motion-depth-step.gif` -> published `pid-motion-depth-step.mp4` - Depth Step Response; representative case `depth_step_pass`

## H01 uSimMarineV22 Motion

Capture from: `harnesses/usim_marine_harnesses/H01-usim_marine_motion`
Typical capture launch: `./zlaunch.sh --case=thrust_forward_pass --port_base=30000 10`

- source `usim-marine-forward-thrust.gif` -> published `usim-marine-forward-thrust.mp4` - Forward Thrust; representative case `thrust_forward_pass`
- source `usim-marine-runtime-drift.gif` -> published `usim-marine-runtime-drift.mp4` - Runtime Drift; representative case `drift_x_pass`

## H01 pNodeReporter Unit

Capture from: `harnesses/pnodereporter_harnesses/H01-pnodereporter_unit`
Typical capture launch: `./zlaunch.sh --case=nav_report_baseline_pass --port_base=12400 10`

- source `pnodereporter-baseline-report.gif` -> published `pnodereporter-baseline-report.mp4` - Baseline Node Report; representative case `nav_report_baseline_pass`
- source `pnodereporter-alt-nav-report.gif` -> published `pnodereporter-alt-nav-report.mp4` - Alternate Nav Report; representative case `alt_nav_report_pass`

## H01 uPokeDB Unit

Capture from: `harnesses/upokedb_harnesses/H01-upokedb_unit`
Typical capture launch: `./zlaunch.sh --case=numeric_direct_pass --port_base=15000 10`

- source `upokedb-direct-numeric.gif` -> published `upokedb-direct-numeric.mp4` - Direct Numeric Poke; representative case `numeric_direct_pass`
- source `upokedb-cached-pokes.gif` -> published `upokedb-cached-pokes.mp4` - Cached Pokes; representative case `cache_string_numeric_pass`

## H01 uXMS Unit

Capture from: `harnesses/uxms_harnesses/H01-uxms_unit`
Typical capture launch: `./zlaunch.sh --case=scoped_var_pass --port_base=15200 10`

- source `uxms-scoped-variable.gif` -> published `uxms-scoped-variable.mp4` - Scoped Variable; representative case `scoped_var_pass`
- source `uxms-history-view.gif` -> published `uxms-history-view.mp4` - History View; representative case `history_var_pass`

## H01 uQueryDB Unit

Capture from: `harnesses/uquerydb_harnesses/H01-uquerydb_unit`
Typical capture launch: `./zlaunch.sh --case=cli_numeric_pass --port_base=15600 10`

- source `uquerydb-numeric-condition.gif` -> published `uquerydb-numeric-condition.mp4` - Numeric Condition; representative case `cli_numeric_pass`
- source `uquerydb-checkvar-formats.gif` -> published `uquerydb-checkvar-formats.mp4` - Checkvar Formats; representative case `checkvar_csv_pass`

## H01 pEchoVar Unit

Capture from: `harnesses/pechovar_harnesses/H01-pechovar_unit`
Typical capture launch: `./zlaunch.sh --case=numeric_echo_pass --port_base=17600 10`

- source `pechovar-echo-mapping.gif` -> published `pechovar-echo-mapping.mp4` - Echo Mapping; representative case `numeric_echo_pass`
- source `pechovar-filtered-flip.gif` -> published `pechovar-filtered-flip.mp4` - Filtered Flip; representative case `flip_filter_suppresses_pass`

## H01 uTimerScript Unit

Capture from: `harnesses/utimerscript_harnesses/H01-utimerscript_unit`
Typical capture launch: `./zlaunch.sh --case=timed_numeric_string_pass --port_base=7300 10`

- source `utimerscript-timed-numeric-string.gif` -> published `utimerscript-timed-numeric-string.mp4` - Timed Numeric/String; representative case `timed_numeric_string_pass`
- source `utimerscript-pause-unpause.gif` -> published `utimerscript-pause-unpause.mp4` - Pause/Unpause; representative case `pause_unpause_external_pass`

## H01 pDeadManPost Unit

Capture from: `harnesses/pdeadmanpost_harnesses/H01-pdeadmanpost_unit`
Typical capture launch: `./zlaunch.sh --case=active_start_once_posts_pass --port_base=15800 10`

- source `pdeadmanpost-deadman-trip.gif` -> published `pdeadmanpost-deadman-trip.mp4` - Deadman Trip; representative case `active_start_once_posts_pass`
- source `pdeadmanpost-heartbeat-suppression.gif` -> published `pdeadmanpost-heartbeat-suppression.mp4` - Heartbeat Suppression; representative case `heartbeat_before_dead_suppresses_pass`

## H01 pSpoofNode Unit

Capture from: `harnesses/pspoofnode_harnesses/H01-pspoofnode_unit`
Typical capture launch: `./zlaunch.sh --case=config_static_report_pass --port_base=16000 10`

- source `pspoofnode-static-spoof.gif` -> published `pspoofnode-static-spoof.mp4` - Static Spoof; representative case `config_static_report_pass`
- source `pspoofnode-cancel-by-name.gif` -> published `pspoofnode-cancel-by-name.mp4` - Cancel By Name; representative case `cancel_vname_pass`

## H01 uTermCommand Unit

Capture from: `harnesses/utermcommand_harnesses/H01-utermcommand_unit`
Typical capture launch: `./zlaunch.sh --case=numeric_command_pass --port_base=16200 10`

- source `utermcommand-numeric-command.gif` -> published `utermcommand-numeric-command.mp4` - Numeric Command; representative case `numeric_command_pass`
- source `utermcommand-arrow-syntax.gif` -> published `utermcommand-arrow-syntax.mp4` - Arrow Syntax; representative case `arrow_syntax_command_pass`

## H01 pSearchGrid Unit

Capture from: `harnesses/psearchgrid_harnesses/H01-psearchgrid_unit`
Typical capture launch: `./zlaunch.sh --case=node_local_delta_pass --port_base=16400 10`

- source `psearchgrid-grid-delta.gif` -> published `psearchgrid-grid-delta.mp4` - Grid Delta; representative case `node_local_delta_pass`
- source `psearchgrid-full-grid-report.gif` -> published `psearchgrid-full-grid-report.mp4` - Full Grid Report; representative case `full_grid_report_pass`

## H01 uField Comms Unit

Capture from: `harnesses/ufield_comms_harnesses/H01-ufield_comms_unit`
Typical capture launch: `./zlaunch.sh --case=baseline_broker_comms_pass --port_base=4000 10`

- source `ufield-comms-baseline-broker.gif` -> published `ufield-comms-baseline-broker.mp4` - Baseline Broker Comms; representative case `baseline_broker_comms_pass`
- source `ufield-comms-runtime-range.gif` -> published `ufield-comms-runtime-range.mp4` - Runtime Range Extend; representative case `runtime_range_extend_pass`

## H02 uField Broker Bridge

Capture from: `harnesses/ufield_comms_harnesses/H02-ufield_broker_bridge`
Typical capture launch: `./zlaunch.sh --case=broker_handshake_pass --port_base=4000 10`

- source `ufield-broker-handshake.gif` -> published `ufield-broker-handshake.mp4` - Broker Handshake; representative case `broker_handshake_pass`
- source `ufield-broker-bridge-tokens.gif` -> published `ufield-broker-bridge-tokens.mp4` - Bridge Tokens; representative case `shore_bridge_tokens_pass`

## H03 uField Route Resilience

Capture from: `harnesses/ufield_comms_harnesses/H03-ufield_route_resilience`
Typical capture launch: `./zlaunch.sh --case=runtime_tryhost_recover_pass --port_base=4000 10`

- source `ufield-route-runtime-recovery.gif` -> published `ufield-route-runtime-recovery.mp4` - Runtime Route Recovery; representative case `runtime_tryhost_recover_pass`
- source `ufield-route-vnode-discovery.gif` -> published `ufield-route-vnode-discovery.mp4` - Shore VNode Discovery; representative case `shore_vnode_discovery_recover_pass`

## H01 uFldObstacleSim Unit

Capture from: `harnesses/ufld_obstacle_sim_harnesses/H01-ufld_obstacle_sim_unit`
Typical capture launch: `./zlaunch.sh --case=fixed_field_publish_pass --port_base=7600 10`

- source `ufld-obstacle-sim-fixed-field.gif` -> published `ufld-obstacle-sim-fixed-field.mp4` - Fixed Field Publish; representative case `fixed_field_publish_pass`
- source `ufld-obstacle-sim-point-sensor.gif` -> published `ufld-obstacle-sim-point-sensor.mp4` - Point Sensor Mode; representative case `post_points_inside_pass`

## H01 uFldPathCheck Unit

Capture from: `harnesses/ufld_pathcheck_harnesses/H01-ufld_pathcheck_unit`
Typical capture launch: `./zlaunch.sh --case=odometry_baseline_pass --port_base=4300 10`

- source `ufld-pathcheck-baseline-odometry.gif` -> published `ufld-pathcheck-baseline-odometry.mp4` - Baseline Odometry; representative case `odometry_baseline_pass`
- source `ufld-pathcheck-trip-reset.gif` -> published `ufld-pathcheck-trip-reset.mp4` - Trip Reset; representative case `trip_reset_pass`

## H01 uFldMessageHandler Unit

Capture from: `harnesses/ufld_message_handler_harnesses/H01-ufld_message_handler_unit`
Typical capture launch: `./zlaunch.sh --case=dest_specific_self_pass --port_base=4400 10`

- source `ufld-message-handler-accepted.gif` -> published `ufld-message-handler-accepted.mp4` - Accepted Message; representative case `dest_specific_self_pass`
- source `ufld-message-handler-strict-reject.gif` -> published `ufld-message-handler-strict-reject.mp4` - Strict Reject; representative case `strict_all_reject_pass`

## H01 uFldContactRangeSensor Unit

Capture from: `harnesses/ufld_contact_range_sensor_harnesses/H01-ufld_contact_range_sensor_unit`
Typical capture launch: `./zlaunch.sh --case=baseline_short_report_pass --port_base=4500 10`

- source `ufld-contact-range-sensor-baseline.gif` -> published `ufld-contact-range-sensor-baseline.mp4` - Baseline Range; representative case `baseline_short_report_pass`
- source `ufld-contact-range-sensor-arc-block.gif` -> published `ufld-contact-range-sensor-arc-block.mp4` - Arc Block; representative case `sensor_arc_aft_block_pass`

## H01 uFldBeaconRangeSensor Unit

Capture from: `harnesses/ufld_beacon_range_sensor_harnesses/H01-ufld_beacon_range_sensor_unit`
Typical capture launch: `./zlaunch.sh --case=request_short_report_pass --port_base=4000 10`

- source `ufld-beacon-range-sensor-baseline.gif` -> published `ufld-beacon-range-sensor-baseline.mp4` - Baseline Beacon Range; representative case `request_short_report_pass`
- source `ufld-beacon-range-sensor-ground-truth.gif` -> published `ufld-beacon-range-sensor-ground-truth.mp4` - Ground Truth Report; representative case `brs_ground_truth_uniform_zero_pass`

## H01 uFldCollisionDetect Unit

Capture from: `harnesses/ufld_collision_detect_harnesses/H01-ufld_collision_detect_unit`
Typical capture launch: `./zlaunch.sh --case=collision_event_pass --port_base=4000 10`

- source `ufld-collision-detect-collision-event.gif` -> published `ufld-collision-detect-collision-event.mp4` - Collision Event; representative case `collision_event_pass`
- source `ufld-collision-detect-condition-gate.gif` -> published `ufld-collision-detect-condition-gate.mp4` - Condition Gate; representative case `condition_allows_pass`

## H01 uFldCollObDetect Unit

Capture from: `harnesses/ufld_collob_detect_harnesses/H01-ufld_collob_detect_unit`
Typical capture launch: `./zlaunch.sh --case=collision_flag_pass --port_base=4000 10`

- source `ufld-collob-detect-obstacle-collision.gif` -> published `ufld-collob-detect-obstacle-collision.mp4` - Obstacle Collision; representative case `collision_flag_pass`
- source `ufld-collob-detect-encounter-only.gif` -> published `ufld-collob-detect-encounter-only.mp4` - Encounter Only; representative case `encounter_only_flag_pass`

## H01 uFldScope Unit

Capture from: `harnesses/ufld_scope_harnesses/H01-ufld_scope_unit`
Typical capture launch: `./zlaunch.sh --case=appcast_table_pass --port_base=4000 10`

- source `ufld-scope-table.gif` -> published `ufld-scope-table.mp4` - Scope Table; representative case `appcast_table_pass`
- source `ufld-scope-row-replacement.gif` -> published `ufld-scope-row-replacement.mp4` - Row Replacement; representative case `update_replaces_same_key_pass`

## H01 Constant Depth Motion

Capture from: `harnesses/depth_behavior_harnesses/H01-constant_depth_motion`
Typical capture launch: `./zlaunch.sh --case=constant_depth_hold_pass --gui 10`

- source `constant-depth-hold.gif` -> published `constant-depth-hold.mp4` - Held Depth; representative case `constant_depth_hold_pass`
- source `constant-depth-update.gif` -> published `constant-depth-update.mp4` - Runtime Update; representative case `constant_depth_update_pass`

## H02 GoToDepth Motion

Capture from: `harnesses/depth_behavior_harnesses/H02-goto_depth_motion`
Typical capture launch: `./zlaunch.sh --case=goto_depth_sequence_pass --gui 10`

- source `goto-depth-sequence.gif` -> published `goto-depth-sequence.mp4` - Depth Sequence; representative case `goto_depth_sequence_pass`
- source `goto-depth-crossing.gif` -> published `goto-depth-crossing.mp4` - Crossing Arrivals; representative case `goto_depth_crossing_pass`

## H03 Periodic Surface Motion

Capture from: `harnesses/depth_behavior_harnesses/H03-periodic_surface_motion`
Typical capture launch: `./zlaunch.sh --case=periodic_surface_pass --gui 10`

- source `periodic-surface-cycle.gif` -> published `periodic-surface-cycle.mp4` - Surfacing Cycle; representative case `periodic_surface_pass`
- source `periodic-surface-wait-window.gif` -> published `periodic-surface-wait-window.mp4` - Wait Window; representative case `periodic_surface_wait_window_pass`

## H04 Max Depth Motion

Capture from: `harnesses/depth_behavior_harnesses/H04-max_depth_motion`
Typical capture launch: `./zlaunch.sh --case=max_depth_guard_pass --gui 10`

- source `max-depth-guard.gif` -> published `max-depth-guard.mp4` - Max Depth Guard; representative case `max_depth_guard_pass`
- source `max-depth-unconstrained.gif` -> published `max-depth-unconstrained.mp4` - Unconstrained Shallow; representative case `max_depth_unconstrained_shallow_pass`

## H05 Min Altitude Motion

Capture from: `harnesses/depth_behavior_harnesses/H05-min_altitude_motion`
Typical capture launch: `./zlaunch.sh --case=min_altitude_guard_pass --gui 10`

- source `min-altitude-guard.gif` -> published `min-altitude-guard.mp4` - Min Altitude Guard; representative case `min_altitude_guard_pass`
- source `min-altitude-unconstrained.gif` -> published `min-altitude-unconstrained.mp4` - Deep Bottom; representative case `min_altitude_unconstrained_deep_bottom_pass`

## H01 COLREGS Classification

Capture from: `harnesses/colregs_harnesses/H01-colregs_classification`
Typical capture launch: `./zlaunch.sh --case=head_on_colregs_pass --gui 10`

- source `colregs-classification-head-on.gif` -> published `colregs-classification-head-on.mp4` - Head-on Classification; representative case `head_on_colregs_pass`
- source `colregs-classification-crossing.gif` -> published `colregs-classification-crossing.mp4` - Crossing Give-way; representative case `crossing_starboard_giveway_pass`

## H02 COLREGS Thresholds

Capture from: `harnesses/colregs_harnesses/H02-colregs_thresholds`
Typical capture launch: `./zlaunch.sh --group=headon --gui 10`

- source `colregs-thresholds-giveway-bowdist.gif` -> published `colregs-thresholds-giveway-bowdist.mp4` - Give-way Bow Distance; representative case `giveway_bowdist_edge_pass`
- source `colregs-thresholds-overtaking-triplet.gif` -> published `colregs-thresholds-overtaking-triplet.mp4` - Overtaking Threshold; representative case `overtaking_thresh_edge_pass`

## H03 COLREGS Execution

Capture from: `harnesses/colregs_harnesses/H03-colregs_execution`
Typical capture launch: `./zlaunch.sh --case=head_on_execution_pass --gui 10`

- source `colregs-execution-head-on.gif` -> published `colregs-execution-head-on.mp4` - Head-on Resolution; representative case `head_on_execution_pass`
- source `colregs-execution-overtaken-midrange.gif` -> published `colregs-execution-overtaken-midrange.mp4` - Overtaken Midrange; representative case `overtaken_starboard_standon_midrange_execution_pass`
- source `colregs-execution-crossing-giveway.gif` -> published `colregs-execution-crossing-giveway.mp4` - Crossing Give-way; representative case `crossing_starboard_giveway_execution_pass`

## H04 COLREGS Parameters

Capture from: `harnesses/colregs_harnesses/H04-colregs_parameters`
Typical capture launch: `./zlaunch.sh --group=min_util_cpa_dist --gui 10`

- source `colregs-parameters-bow-distance.gif` -> published `colregs-parameters-bow-distance.mp4` - Bow Distance Threshold; representative case `giveway_bow_dist_high_pass`
- source `colregs-parameters-turn-radius.gif` -> published `colregs-parameters-turn-radius.mp4` - Turn Radius Branch; representative case `turn_radius_high_pass`

## H01 Avoid-Collision Behavior

Capture from: `harnesses/collision_behavior_harnesses/H01-collision_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=head_on_resolve_pass --gui 10`

- source `collision-behavior-head-on-resolve.gif` -> published `collision-behavior-head-on-resolve.mp4` - Head-on Resolve; representative case `head_on_resolve_pass`
- source `collision-behavior-no-alert-fail.gif` -> published `collision-behavior-no-alert-fail.mp4` - No Alert Request Fail; representative case `no_alert_request_fail`
- source `collision-behavior-default-resolve.gif` -> published `collision-behavior-default-resolve.mp4` - Baseline Resolve; representative case `default_resolve_pass`

## H01 Avoid-Obstacle Behavior

Capture from: `harnesses/obstacle_behavior_harnesses/H01-obstacle_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=two_obstacles_clean_pass --gui 10`

- source `obstacle-behavior-default-auto-request.gif` -> published `obstacle-behavior-default-auto-request.mp4` - Default Auto Request; representative case `default_auto_request_pass`
- source `obstacle-behavior-two-obstacles.gif` -> published `obstacle-behavior-two-obstacles.mp4` - Sequential Obstacle Alerts; representative case `two_obstacles_clean_pass`
- source `obstacle-behavior-avoid-disabled.gif` -> published `obstacle-behavior-avoid-disabled.mp4` - Avoid Disabled Fail; representative case `avoid_disabled_fail`

## H01 OpRegion Safety

Capture from: `harnesses/opregion_harnesses/H01-opregion_safety`
Typical capture launch: `./zlaunch.sh --case=save_recover_pass --gui 10`

- source `opregion-safety-save-recover.gif` -> published `opregion-safety-save-recover.mp4` - Save Recovery; representative case `save_recover_pass`
- source `opregion-safety-dynamic-update.gif` -> published `opregion-safety-dynamic-update.mp4` - Dynamic Region Update; representative case `dynamic_region_update_pass`
- source `opregion-safety-entry-gate.gif` -> published `opregion-safety-entry-gate.mp4` - Entry Gate; representative case `entry_gate_start_outside_pass`

## H02 OpRegion V26

Capture from: `harnesses/opregion_harnesses/H02-opregion_v26`
Typical capture launch: `./zlaunch.sh --jobs=2 --port_base=22000 10`

- Visual pending - Convex Keep-In; representative case `convex_contained_keepin_pass`
- Visual pending - Non-Convex Keep-In; representative case `nonconvex_contained_keepin_pass`
- Visual pending - Lapsed Recovery; representative case `lapsed_recovery_pass`

## H01 Waypoint Behavior

Capture from: `harnesses/waypoint_behavior_harnesses/H01-waypoint_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=multi_point_sequence_pass --gui 10`

- source `waypoint-behavior-multipoint.gif` -> published `waypoint-behavior-multipoint.mp4` - Multi-point Sequence; representative case `multi_point_sequence_pass`
- source `waypoint-behavior-dynamic-update.gif` -> published `waypoint-behavior-dynamic-update.mp4` - Dynamic Route Update; representative case `xpoints_update_pass`
- source `waypoint-behavior-repeat-forever.gif` -> published `waypoint-behavior-repeat-forever.mp4` - Repeat Forever Cycle; representative case `repeat_forever_cycle_pass`

## H01 Loiter Behavior

Capture from: `harnesses/loiter_behavior_harnesses/H01-loiter_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=radial_clockwise_pass --gui 10`

- source `loiter-behavior-radial.gif` -> published `loiter-behavior-radial.mp4` - Radial Clockwise; representative case `radial_clockwise_pass`
- source `loiter-behavior-radius-expand.gif` -> published `loiter-behavior-radius-expand.mp4` - Runtime Radius Expand; representative case `mod_poly_rad_expand_pass`
- source `loiter-behavior-center-assign-pair.gif` -> published `loiter-behavior-center-assign-pair.mp4` - Center Assign Pair; representative case `center_assign_pair_pass`

## H01 StationKeep Behavior

Capture from: `harnesses/stationkeep_behavior_harnesses/H01-stationkeep_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=static_station_pass --gui 10`

- source `stationkeep-behavior-static.gif` -> published `stationkeep-behavior-static.mp4` - Static Station; representative case `static_station_pass`
- source `stationkeep-behavior-hibernation.gif` -> published `stationkeep-behavior-hibernation.mp4` - Hibernation Settle; representative case `hibernation_settle_pass`
- source `stationkeep-behavior-radius-expand.gif` -> published `stationkeep-behavior-radius-expand.mp4` - Runtime Radius Expand; representative case `radius_update_expand_pass`

## H01 Trail Behavior

Capture from: `harnesses/trail_behavior_harnesses/H01-trail_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=static_trail_pass --gui 10`

- source `trail-behavior-relative-port.gif` -> published `trail-behavior-relative-port.mp4` - Relative Port Trail; representative case `relative_port_pass`
- source `trail-behavior-lead-turn-angle-update.gif` -> published `trail-behavior-lead-turn-angle-update.mp4` - Lead Turn Angle Update; representative case `lead_turn_angle_update_pass`
- source `trail-behavior-runtime-range-extend.gif` -> published `trail-behavior-runtime-range-extend.mp4` - Runtime Range Extend; representative case `runtime_range_extend_pass`

## H01 Convoy Behavior

Capture from: `harnesses/convoy_behavior_harnesses/H01-convoy_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=static_convoy_pass --gui 10`

- source `convoy-behavior-static.gif` -> published `convoy-behavior-static.mp4` - Static Convoy; representative case `static_convoy_pass`
- source `convoy-behavior-angled-entry.gif` -> published `convoy-behavior-angled-entry.mp4` - Angled Entry; representative case `angled_entry_pass`
- source `convoy-behavior-lead-s-turn.gif` -> published `convoy-behavior-lead-s-turn.mp4` - Lead S-turn; representative case `lead_s_turn_pass`

## H01 CutRange Behavior

Capture from: `harnesses/cutrange_behavior_harnesses/H01-cutrange_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=static_cutrange_pass --gui 10`

- source `cutrange-behavior-headon.gif` -> published `cutrange-behavior-headon.mp4` - Head-on Closure; representative case `headon_cutrange_pass`
- source `cutrange-behavior-crossing.gif` -> published `cutrange-behavior-crossing.mp4` - Crossing Closure; representative case `crossing_cutrange_pass`
- source `cutrange-behavior-s-turn.gif` -> published `cutrange-behavior-s-turn.mp4` - S-turn Target; representative case `s_turn_target_pass`

## H01 FixedTurn Behavior

Capture from: `harnesses/fixedturn_behavior_harnesses/H01-fixedturn_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=starboard_90_pass --gui 10`

- source `fixedturn-behavior-starboard-90.gif` -> published `fixedturn-behavior-starboard-90.mp4` - Starboard 90; representative case `starboard_90_pass`
- source `fixedturn-behavior-port-360.gif` -> published `fixedturn-behavior-port-360.mp4` - Port 360; representative case `port_360_pass`
- source `fixedturn-behavior-turn-spec-sequence.gif` -> published `fixedturn-behavior-turn-spec-sequence.mp4` - Turn Spec Sequence; representative case `turn_spec_sequence_pass`

## H01 PeriodicSpeed Behavior

Capture from: `harnesses/periodic_speed_behavior_harnesses/H01-periodic_speed_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=baseline_cycle_pass --gui --port_base=15000 10`

- source `periodic-speed-baseline-cycle.gif` -> published `periodic-speed-baseline-cycle.mp4` - Baseline Lazy/Busy Cycle; representative case `baseline_cycle_pass`
- source `periodic-speed-reset-false-reenable.gif` -> published `periodic-speed-reset-false-reenable.mp4` - Reset False Re-Enable; representative case `reset_false_visual_pass`

## H01 MemoryTurnLimit Behavior

Capture from: `harnesses/memoryturnlimit_behavior_harnesses/H01-memoryturnlimit_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=baseline_memory_pass --gui --port_base=15000 10`

- source `memoryturnlimit-behavior-tight-window.gif` -> published `memoryturnlimit-behavior-tight-window.mp4` - Tight Turn Window; representative case `tight_window_pass`
- source `memoryturnlimit-behavior-runtime-widen.gif` -> published `memoryturnlimit-behavior-runtime-widen.mp4` - Runtime Range Widen; representative case `runtime_widen_range_pass`

## H01 Timer Behavior

Capture from: `harnesses/timer_behavior_harnesses/H01-timer_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=baseline_idle_running_pass --gui --port_base=15000 10`

- source `timer-behavior-pause-resume.gif` -> published `timer-behavior-pause-resume.mp4` - Pause/Resume Counters; representative case `pause_resume_pass`
- source `timer-behavior-runtime-update.gif` -> published `timer-behavior-runtime-update.mp4` - Runtime Status Update; representative case `runtime_update_pass`

## H01 TestFailure Behavior

Capture from: `harnesses/testfailure_behavior_harnesses/H01-testfailure_behavior_unit`
Typical capture launch: `./zlaunch.sh --case=burn_gap_detected_pass --port_base=15000 10`

- source `testfailure-burn-gap.gif` -> published `testfailure-burn-gap.mp4` - Burn Gap Detection; representative case `burn_gap_detected_pass`
- source `testfailure-crash-process-loss.gif` -> published `testfailure-crash-process-loss.mp4` - Crash Process Loss; representative case `crash_on_complete_fail`

## H01 pHostInfo Unit

Capture from: `harnesses/hostinfo_harnesses/H01-hostinfo_unit`
Typical capture launch: `./zlaunch.sh --jobs=3 --port_base=11000 10`

- source `hostinfo-pshare-route-payload.gif` -> published `hostinfo-pshare-route-payload.mp4` - pShare Route Payload; representative case `hostinfo_pshare_route_pass`
- source `hostinfo-invalid-route-omitted.gif` -> published `hostinfo-invalid-route-omitted.mp4` - Invalid Route Omitted; representative case `hostinfo_invalid_pshare_route_pass`

## H01 uLoadWatch Unit

Capture from: `harnesses/loadwatch_harnesses/H01-loadwatch_unit`
Typical capture launch: `./zlaunch.sh --jobs=3 --port_base=11200 10`

- source `loadwatch-near-breach-band.gif` -> published `loadwatch-near-breach-band.mp4` - Near-Breach Band; representative case `loadwatch_near_breach_pass`
- source `loadwatch-trigger-holdoff.gif` -> published `loadwatch-trigger-holdoff.mp4` - Trigger Holdoff; representative case `loadwatch_trigger_second_breaches_pass`

## H01 uProcessWatch Unit

Capture from: `harnesses/processwatch_harnesses/H01-processwatch_unit`
Typical capture launch: `./zlaunch.sh --jobs=3 --port_base=11600 10`

- source `processwatch-mapped-summary.gif` -> published `processwatch-mapped-summary.mp4` - Mapped Summary; representative case `processwatch_post_mapping_pass`
- source `processwatch-awol-detection.gif` -> published `processwatch-awol-detection.mp4` - AWOL Detection; representative case `processwatch_missing_awol_fail`

## H01 pShare Unit

Capture from: `harnesses/pshare_harnesses/H01-pshare_unit`
Typical capture launch: `./zlaunch.sh --jobs=2 --port_base=11000 10`

- source `pshare-direct-route.gif` -> published `pshare-direct-route.mp4` - Direct Route; representative case `pshare_direct_route_pass`
- source `pshare-wildcard-route.gif` -> published `pshare-wildcard-route.mp4` - Wildcard Route; representative case `pshare_wildcard_route_pass`

## H02 pShare Topology

Capture from: `harnesses/pshare_harnesses/H02-pshare_topology`
Typical capture launch: `./zlaunch.sh --jobs=2 --port_base=11000 --max_time=65 10`

- source `pshare-topology-fanin.gif` -> published `pshare-topology-fanin.mp4` - Fan-in; representative case `pshare_topology_fanin_pass`
- source `pshare-topology-multicast-relay-proof.gif` -> published `pshare-topology-multicast-relay-proof.mp4` - Multicast Relay Proof; representative case `pshare_topology_multicast_multi_listener_pass`

## H01 pLogger Unit

Capture from: `harnesses/plogger_harnesses/H01-plogger_unit`
Typical capture launch: `./zlaunch.sh --jobs=2 --port_base=12000 10`

- source `plogger-explicit-log-capture.gif` -> published `plogger-explicit-log-capture.mp4` - Explicit Log Capture; representative case `plogger_explicit_log_pass`
- source `plogger-wildcard-omit.gif` -> published `plogger-wildcard-omit.mp4` - Wildcard Omit; representative case `plogger_wildcard_omit_pass`

## H01 pAntler Unit

Capture from: `harnesses/pantler_harnesses/H01-pantler_unit`
Typical capture launch: `./zlaunch.sh --jobs=2 --port_base=12200 10`

- source `pantler-alias-launch.gif` -> published `pantler-alias-launch.mp4` - Alias Launch; representative case `pantler_alias_launch_pass`
- source `pantler-multi-alias-launch.gif` -> published `pantler-multi-alias-launch.mp4` - Multi-alias Launch; representative case `pantler_multi_alias_launch_pass`

## H01 pMissionEval Unit

Capture from: `harnesses/mission_utility_harnesses/H01-pmissioneval_unit`
Typical capture launch: `./zlaunch.sh --jobs=3 --port_base=7100 10`

- source `pmissioneval-baseline-evaluation.gif` -> published `pmissioneval-baseline-evaluation.mp4` - Baseline Evaluation; representative case `eval_baseline_pass`
- source `pmissioneval-two-stage-logic.gif` -> published `pmissioneval-two-stage-logic.mp4` - Two-stage Logic; representative case `eval_sequence_two_stage_pass`

## H02 pMissionHash Unit

Capture from: `harnesses/mission_utility_harnesses/H02-pmissionhash_unit`
Typical capture launch: `./zlaunch.sh --jobs=3 --port_base=7300 10`

- source `pmissionhash-custom-vars.gif` -> published `pmissionhash-custom-vars.mp4` - Custom Hash Vars; representative case `hash_custom_vars_pass`
- source `pmissionhash-reset.gif` -> published `pmissionhash-reset.mp4` - Hash Reset; representative case `hash_reset_changes_pass`

## H03 uMayFinish Unit

Capture from: `harnesses/mission_utility_harnesses/H03-umayfinish_unit`
Typical capture launch: `./zlaunch.sh --jobs=3 --port_base=7400 10`

- source `umayfinish-default-exit.gif` -> published `umayfinish-default-exit.mp4` - Default Finish Exit; representative case `mayfinish_default_exit_pass`
- source `umayfinish-custom-value-timeout.gif` -> published `umayfinish-custom-value-timeout.mp4` - Custom Value Timeout; representative case `mayfinish_custom_value_timeout_fail`

## H01 ZigZag Behavior

Capture from: `harnesses/zigzag_behavior_harnesses/H01-zigzag_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=baseline_port_first_pass --gui --port_base=15000 10`

- source `zigzag-behavior-baseline-port.gif` -> published `zigzag-behavior-baseline-port.mp4` - Baseline Port First; representative case `baseline_port_first_pass`
- source `zigzag-behavior-wide-angle.gif` -> published `zigzag-behavior-wide-angle.mp4` - Wide Angle; representative case `wide_angle_pass`
- source `zigzag-behavior-fierce-zigging.gif` -> published `zigzag-behavior-fierce-zigging.mp4` - Fierce Zigging; representative case `fierce_zigging_pass`

## H01 LegRun Behavior

Capture from: `harnesses/legrun_behavior_harnesses/H01-legrun_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=baseline_cycle_pass --gui --port_base=4000 10`

- Visual pending - Baseline Cycle; representative case `baseline_cycle_pass`
- Visual pending - Far Turn Init; representative case `init_far_turn_pass`
- Visual pending - Individual Turn Params; representative case `individual_turn_params_pass`

## H01 Shadow Behavior

Capture from: `harnesses/shadow_behavior_harnesses/H01-shadow_behavior_motion`
Typical capture launch: `./zlaunch.sh --case=static_shadow_pass --gui 10`

- source `shadow-behavior-static.gif` -> published `shadow-behavior-static.mp4` - Static Shadow; representative case `static_shadow_pass`
- source `shadow-behavior-turn-north.gif` -> published `shadow-behavior-turn-north.mp4` - Turn North Shadow; representative case `turn_north_shadow_pass`
- source `shadow-behavior-runtime-pwt-on.gif` -> published `shadow-behavior-runtime-pwt-on.mp4` - Runtime PWT On; representative case `runtime_pwt_outer_on_pass`

## P01 Obstacle Gauntlet

Capture from: `harnesses/performance_harnesses/P01-obstacle_gauntlet`
Typical capture launch: `./zlaunch.sh --case=baseline_field_pass --gui 10`

- source `performance-obstacle-gauntlet-baseline.gif` -> published `performance-obstacle-gauntlet-baseline.mp4` - Baseline Field; representative case `baseline_field_pass`
- source `performance-obstacle-gauntlet-dense.gif` -> published `performance-obstacle-gauntlet-dense.mp4` - Dense Field; representative case `dense_field_pass`
- source `performance-obstacle-gauntlet-endurance.gif` -> published `performance-obstacle-gauntlet-endurance.mp4` - Endurance Random; representative case `endurance_random_pass`

## P02 COLREGS Joust

Capture from: `harnesses/performance_harnesses/P02-colregs_joust`
Typical capture launch: `./zlaunch.sh --case=dense_colregs_pass --gui 10`

- source `performance-colregs-joust-baseline.gif` -> published `performance-colregs-joust-baseline.mp4` - Baseline Joust; representative case `baseline_colregs_pass`
- source `performance-colregs-joust-dense.gif` -> published `performance-colregs-joust-dense.mp4` - Dense Joust; representative case `dense_colregs_pass`

## P03 COLREGS Traffic Ring

Capture from: `harnesses/performance_harnesses/P03-colregs_traffic_ring`
Typical capture launch: `./zlaunch.sh --case=baseline_circle_pass --gui 10`

- source `performance-traffic-ring-baseline.gif` -> published `performance-traffic-ring-baseline.mp4` - Baseline Traffic Ring; representative case `baseline_circle_pass`
- source `performance-traffic-ring-mixed-speed.gif` -> published `performance-traffic-ring-mixed-speed.mp4` - Mixed-Speed Traffic Ring; representative case `mixed_speed_circle_pass`
- source `performance-traffic-ring-noncoop.gif` -> published `performance-traffic-ring-noncoop.mp4` - Non-Cooperative Traffic Ring; representative case `noncoop_circle_pass`
