# H01-uquerydb_unit

Live `uQueryDB` harness for validating query conditions and `.checkvars`
output formats against a deterministic MOOSDB publisher mission.

The harness copies the mission stem for every case, assigns isolated port
blocks, runs one bounded `uQueryDB` invocation, and validates the command return
code, mission readiness grade, and expected `.checkvars` tokens. Cases use a
Bash 5.1 rolling scheduler when `--jobs` is greater than one.

This is a documented CLI-result exception to ordinary mission-only grading.
`pMissionEval` owns the deterministic publisher-readiness grade. The harness
then treats the configured `uQueryDB` return code and `.checkvars` output as the
subject contract, including cases where return code 1 is the expected result.
No shell check replaces the mission readiness verdict.

```sh
./zlaunch.sh --jobs=2 --port_base=15600 10
./zlaunch.sh --case=cli_numeric_pass --port_base=15600 10
./zlaunch.sh --keep_workdirs --jobs=2 --port_base=22000 10
```

The harness defaults to `--log=minimal`, which omits `pLogger` because the
mission result, command status, and `.checkvars` output are the grading inputs.
Use `--log=full` for the complete matrix, or combine it with `--case=<name>`
for one fully logged case.

After the high-confidence coverage review, the current 32-case matrix passed
32/32 with four jobs in 53 seconds. Mutation checks rejected an early timeout,
an already-present "late" variable, an extra `.checkvars` row, and removal of
`--unique`; paired true/false cases also verify both separate and compound AND
conditions.

## Cases

- `cli_numeric_pass`: Queries `QUERY_NUM = 42` from the command line, testing numeric equality against the published value; passes when `uQueryDB` exits `0` within the three-second wait.
- `cli_string_pass`: Queries `QUERY_STR = ready`, testing string equality against the published value; passes when `uQueryDB` exits `0` within three seconds.
- `cli_boolean_pass`: Queries `QUERY_BOOL = true`, testing equality for the published boolean-looking string; passes when `uQueryDB` exits `0` within three seconds.
- `cli_negative_numeric_pass`: Queries `QUERY_NEG = -7.5`, testing parsing and equality for a negative decimal; passes when `uQueryDB` exits `0` within three seconds.
- `multiple_pass_conditions_pass`: Supplies separate `QUERY_NUM = 42` and `QUERY_STR = ready` pass conditions, testing the all-conditions contract; passes when `uQueryDB` exits `0` after both published values satisfy their conditions.
- `multiple_second_false_fail`: Keeps the first separate condition true but changes the second to `QUERY_STR = not_ready`, proving every separately supplied condition is required; the harness passes when `uQueryDB` exits `1`.
- `fail_condition_false_pass`: Requires `QUERY_NUM = 42` while declaring `QUERY_FAIL = true` as a fail condition, testing that a false fail condition does not veto a satisfied pass condition; passes when `uQueryDB` exits `0` with `QUERY_FAIL=false`.
- `fail_condition_true_fail`: Requires `QUERY_NUM = 42` while declaring the published `QUERY_FAIL = false` as a fail condition, testing fail-condition precedence over a satisfied pass condition; the harness passes when `uQueryDB` exits `1`.
- `missing_var_timeout_fail`: Waits one second for never-published `QUERY_MISSING = ready`, testing the CLI timeout path; the harness passes when `uQueryDB` exits `1` after at least 1.5 seconds of measured process time including connection and shutdown overhead, while the harness deadline remains the upper bound.
- `late_var_wait_pass`: Starts before `QUERY_LATE=arrived` is posted at mission time 15, testing that the query remains active for new mail rather than reading an existing DB value; passes when `uQueryDB` exits `0` after at least 1.5 seconds, while the harness deadline remains the upper bound.
- `mission_file_config_pass`: Runs the stem mission file's `pass_condition=QUERY_NUM = 42`, `check_var=QUERY_NUM`, and ESV format without CLI query arguments, testing `ProcessConfig` loading; passes when `uQueryDB` exits `0` and `.checkvars` is exactly one line, ` QUERY_NUM=42`.
- `checkvar_esv_pass`: Requests `QUERY_NUM` with `--check_var` and `--esv`, testing equals-separated output; passes when the numeric query exits `0` and `.checkvars` is exactly one line, ` QUERY_NUM=42`.
- `checkvar_csv_pass`: Requests `QUERY_STR` with `--check_var` and `--csv`, testing comma-separated output; passes when the string query exits `0` and `.checkvars` is exactly `QUERY_STR,ready`.
- `checkvar_wsv_pass`: Requests `QUERY_OTHER` with `--check_var` and `--wsv`, testing whitespace-separated output; passes when `QUERY_OTHER = bravo` exits `0` and `.checkvars` is exactly `QUERY_OTHER bravo`.
- `checkvar_value_only_pass`: Generates a config with `check_var_format=vo` for `QUERY_BOOL`, testing value-only output; passes when the query exits `0` and `.checkvars` is exactly the single line `true`.
- `unique_name_pass`: Starts a delayed query with `--unique` and writes `DB_CLIENTS` to `.checkvars`, testing randomized client-name registration while the process is connected; passes when the client list contains `uQueryDB_<digits>`.
- `compound_or_pass`: Queries `(QUERY_STR = not_ready) or (QUERY_OTHER = bravo)`, testing that a true right-hand branch satisfies an OR expression when the left branch is false; passes when `uQueryDB` exits `0`.
- `pass_condition_alias_pass`: Supplies `QUERY_STR = ready` through the CLI `--pass_condition` alias, testing equivalence with `--condition`; passes when `uQueryDB` exits `0`.
- `compound_and_pass`: Queries `(QUERY_NUM = 42) and (QUERY_STR = ready)`, testing a compound AND expression with both terms true; passes when `uQueryDB` exits `0`.
- `compound_and_second_false_fail`: Keeps the left side of the compound AND true but changes the right side to `QUERY_STR = not_ready`, proving both branches are required; the harness passes when `uQueryDB` exits `1`.
- `compound_or_fail`: Queries `(QUERY_STR = not_ready) or (QUERY_OTHER = not_bravo)`, testing an OR expression with both branches false; the harness passes when `uQueryDB` exits `1` after the one-second wait.
- `config_halt_max_time_timeout_fail`: Generates `halt_max_time=1` with the never-satisfied `QUERY_MISSING = ready` pass condition, testing the configuration alias for the timeout; the harness passes when `uQueryDB` exits `1` after the same 1.5-second measured minimum as CLI `--wait=1`, while the harness deadline remains the upper bound.
- `config_fail_condition_false_pass`: Generates a config requiring `QUERY_NUM = 42` and failing on `QUERY_FAIL = true`, testing a false config-file fail condition; passes when `uQueryDB` exits `0` with `QUERY_FAIL=false`.
- `config_fail_condition_true_fail`: Generates a config requiring `QUERY_NUM = 42` and failing on the published `QUERY_FAIL = false`, testing a true config-file fail condition; the harness passes when `uQueryDB` exits `1`.
- `checkvar_multi_csv_pass`: Requests `QUERY_NUM` and `QUERY_STR` in CSV format, testing multiple `.checkvars` rows from one successful query; passes when the file contains exactly `QUERY_NUM,42` followed by `QUERY_STR,ready` and no extra rows.
- `checkvar_timeout_esv_pass`: Waits one second on missing `QUERY_MISSING` while requesting published `QUERY_NUM` in ESV format, testing check-variable output on query failure; the harness passes when `uQueryDB` exits `1` and `.checkvars` is exactly ` QUERY_NUM=42`.
- `case_config_checkvar_csv_pass`: Generates a config requiring `QUERY_OTHER = bravo` and writing that variable as CSV, testing config-file check-variable and format settings together; passes when `uQueryDB` exits `0` and `.checkvars` is exactly `QUERY_OTHER,bravo`.
- `fail_only_false_pass`: Supplies only the fail condition `QUERY_FAIL = true`, testing a query with no pass conditions when the published value is false; passes when `uQueryDB` exits `0`.
- `fail_only_true_fail`: Supplies only the fail condition `QUERY_FAIL = false`, testing a query with no pass conditions when the published value satisfies the fail condition; the harness passes when `uQueryDB` exits `1`.
- `numeric_greater_than_pass`: Queries `QUERY_NUM > 41` against the published value `42`, testing a true numeric greater-than comparison; passes when `uQueryDB` exits `0`.
- `numeric_less_than_fail`: Queries `QUERY_NUM < 41` against the published value `42`, testing a false numeric less-than comparison; the harness passes when `uQueryDB` exits `1` after the one-second wait.
- `config_condition_alias_pass`: Generates `condition=QUERY_BOOL = true`, testing the config-file alias for `pass_condition`; passes when `uQueryDB` exits `0`.
