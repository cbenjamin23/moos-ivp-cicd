#include <gtest/gtest.h>

#include <cstdio>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#include "ALogEntry.h"
#include "LogUtils.h"
#include "TestFileUtils.h"

namespace {

std::string writeTempALog(const std::string& name, const std::vector<std::string>& lines)
{
  std::string contents;
  for(const std::string& line : lines)
    contents += line + "\n";
  // Keep the .alog temp files alive because several helpers return raw FILE*
  // handles and paths that are consumed after this helper returns.
  static std::vector<std::unique_ptr<TempFile>> files;
  files.emplace_back(new TempFile(name, contents, ".alog"));
  return files.back()->path();
}

FILE* openRead(const std::string& path)
{
  return std::fopen(path.c_str(), "r");
}

}  // namespace

// Covers a log entry behavior: stores numeric and string posts with source aux and skew.
TEST(ALogEntryTest, StoresNumericAndStringPostsWithSourceAuxAndSkew)
{
  ALogEntry numeric;
  numeric.set(12.5, "NAV_SPEED", "pMarinePID", "helm", 2.75);
  numeric.setNode("abe");
  numeric.setRawLine("12.5 NAV_SPEED pMarinePID:helm 2.75");

  EXPECT_DOUBLE_EQ(numeric.time(), 12.5);
  EXPECT_EQ(numeric.getVarName(), "NAV_SPEED");
  EXPECT_EQ(numeric.getSource(), "pMarinePID");
  EXPECT_EQ(numeric.getSrcAux(), "helm");
  EXPECT_TRUE(numeric.isNumerical());
  EXPECT_DOUBLE_EQ(numeric.getDoubleVal(), 2.75);
  EXPECT_EQ(numeric.getStringVal(), "");
  EXPECT_EQ(numeric.getNode(), "abe");
  EXPECT_EQ(numeric.getRawLine(), "12.5 NAV_SPEED pMarinePID:helm 2.75");

  numeric.skewBackward(2.0);
  EXPECT_DOUBLE_EQ(numeric.time(), 10.5);
  numeric.skewForward(1.25);
  EXPECT_DOUBLE_EQ(numeric.time(), 11.75);

  ALogEntry text;
  text.set(18.0, "MODE", "pHelmIvP", "iter=22", "SURVEYING");
  EXPECT_FALSE(text.isNumerical());
  EXPECT_EQ(text.getStringVal(), "SURVEYING");
  EXPECT_DOUBLE_EQ(text.getDoubleVal(), 0.0);
}

// Covers a log entry behavior: compares all fields and reports null status.
TEST(ALogEntryTest, ComparesAllFieldsAndReportsNullStatus)
{
  ALogEntry lhs;
  lhs.set(5, "DESIRED_HEADING", "pHelmIvP", "", 270.0);
  lhs.setNode("alpha");
  lhs.setRawLine("5 DESIRED_HEADING pHelmIvP 270");

  ALogEntry rhs = lhs;
  EXPECT_EQ(lhs, rhs);
  EXPECT_FALSE(lhs != rhs);

  rhs.setStatus("null");
  EXPECT_NE(lhs, rhs);
  EXPECT_TRUE(rhs.isNull());

  ALogEntry later = lhs;
  later.setTimeStamp(6);
  EXPECT_LT(lhs, later);
}

// Covers a log entry behavior: extracts token fields from comma separated NODE_REPORT style payloads.
TEST(ALogEntryTest, ExtractsTokenFieldsFromCommaSeparatedNodeReportStylePayloads)
{
  ALogEntry report;
  report.set(22.4, "NODE_REPORT", "pNodeReporter", "",
             "NAME=abe,X=17.5,Y=-3.25,SPD=1.8,HDG=91.2,MODE=SURVEY");

  double value = 0;
  EXPECT_TRUE(report.tokenField("X", value));
  EXPECT_DOUBLE_EQ(value, 17.5);
  EXPECT_TRUE(report.tokenField("Y", value));
  EXPECT_DOUBLE_EQ(value, -3.25);
  EXPECT_TRUE(report.tokenField("SPD", value));
  EXPECT_DOUBLE_EQ(value, 1.8);
  EXPECT_FALSE(report.tokenField("MODE", value));
  EXPECT_FALSE(report.tokenField("MISSING", value));
}

// Covers log utils field parsing behavior: splits canonical alog line with whitespace and source aux.
TEST(LogUtilsFieldParsingTest, SplitsCanonicalAlogLineWithWhitespaceAndSourceAux)
{
  const std::string line =
      "  148.250   VIEW_SEGLIST   pHelmIvP:loiter   pts={0,0:50,0:50,50},label=track";

  // Leading whitespace is not treated as a harmless prefix by the low-level
  // token helpers; this pins the current field-shift behavior.
  EXPECT_EQ(getTimeStamp(line), "");
  EXPECT_EQ(getVarName(line), "148.250");
  EXPECT_EQ(getSourceName(line), "VIEW_SEGLIST");
  EXPECT_EQ(getSourceNameNoAux(line), "VIEW_SEGLIST");

  const std::string canonical =
      "148.250   VIEW_SEGLIST   pHelmIvP:loiter   pts={0,0:50,0:50,50},label=track";
  EXPECT_EQ(getTimeStamp(canonical), "148.250");
  EXPECT_EQ(getVarName(canonical), "VIEW_SEGLIST");
  EXPECT_EQ(getSourceName(canonical), "pHelmIvP:loiter");
  EXPECT_EQ(getSourceNameNoAux(canonical), "pHelmIvP");
  EXPECT_EQ(getDataEntry(canonical), "pts={0,0:50,0:50,50},label=track");
}

// Covers log utils field parsing behavior: preserves complex data payloads and replaces only data field.
TEST(LogUtilsFieldParsingTest, PreservesComplexDataPayloadsAndReplacesOnlyDataField)
{
  const std::string line =
      "45.000 NODE_MESSAGE uFldNodeComms src_node=abe,dest_node=ben,"
      "var_name=MISSION_TASK,string_val=\"survey,alpha\"";

  EXPECT_EQ(getDataEntry(line),
            "src_node=abe,dest_node=ben,var_name=MISSION_TASK,string_val=\"survey,alpha\"");
  EXPECT_EQ(rplDataEntry(line, "status=ok,reason=finished"),
            "45.000 NODE_MESSAGE uFldNodeComms status=ok,reason=finished");

  const std::string with_tabs =
      "45.000\tAPP_LOG\tpHelmIvP\titer=12,log=decision made!@#objective posted";
  EXPECT_EQ(getVarName(with_tabs), "APP_LOG");
  EXPECT_EQ(getSourceName(with_tabs), "pHelmIvP");
  EXPECT_EQ(getDataEntry(with_tabs), "iter=12,log=decision made!@#objective posted");
}

// Covers log utils time behavior: shifts timestamps relative to log start and strips trailing zeros.
TEST(LogUtilsTimeTest, ShiftsTimestampsRelativeToLogStartAndStripsTrailingZeros)
{
  std::string line = "1689355502.750 NAV_X pNodeReporter 42.0";
  shiftTimeStamp(line, 1689355500.0);
  EXPECT_EQ(line, "2.750 NAV_X pNodeReporter 42.0");

  std::string already_local = "12.345 NAV_Y pNodeReporter -7.0";
  shiftTimeStamp(already_local, 1689355500.0);
  EXPECT_EQ(already_local, "12.345 NAV_Y pNodeReporter -7.0");

  std::string comment = "%% LOGSTART 1689355500.000";
  shiftTimeStamp(comment, 1689355500.0);
  EXPECT_EQ(comment, "%% LOGSTART 1689355500.000");

  std::string decimal = "NAV_SPEED=2.5000";
  stripInsigDigits(decimal);
  EXPECT_EQ(decimal.c_str(), std::string("NAV_SPEED=2.5"));

  std::string whole = "NAV_SPEED=2.0000";
  stripInsigDigits(whole);
  EXPECT_EQ(whole.c_str(), std::string("NAV_SPEED=2"));
}

// Covers log utils time behavior: converts epoch like date fields used in a log headers.
TEST(LogUtilsTimeTest, ConvertsEpochLikeDateFieldsUsedInALogHeaders)
{
  EXPECT_DOUBLE_EQ(getEpochSecsFromTimeOfDay(11, 50, 4), 42604);
  EXPECT_DOUBLE_EQ(getEpochSecsFromTimeOfDay(23, 50, 4), 85804);
  EXPECT_DOUBLE_EQ(getEpochSecsFromTimeOfDay(1, 2, 3), 3723);

  EXPECT_DOUBLE_EQ(getEpochSecsFromDayOfYear("1/1/1970"), 0);
  EXPECT_DOUBLE_EQ(getEpochSecsFromDayOfYear("1/2/1970"), 86400);
  EXPECT_DOUBLE_EQ(getEpochSecsFromDayOfYear("3/1/1972"),
                   (365 * 2 + 31 + 28 + 1) * 86400.0);
  EXPECT_DOUBLE_EQ(getEpochSecsFromDayOfYear(15, 7, 2009),
                   getEpochSecsFromDayOfYear("7/15/2009"));
  EXPECT_DOUBLE_EQ(getEpochSecsFromDayOfYear("12/31/1969"), 0);
}

// Covers log utils index behavior: finds last entry at or before requested time.
TEST(LogUtilsIndexTest, FindsLastEntryAtOrBeforeRequestedTime)
{
  const std::vector<double> times = {2, 5, 9, 13, 14, 19, 23, 28, 31, 35, 43, 57};

  EXPECT_EQ(getIndexByTime({}, 10), 0u);
  EXPECT_EQ(getIndexByTime(times, 0), 0u);
  EXPECT_EQ(getIndexByTime(times, 2), 0u);
  EXPECT_EQ(getIndexByTime(times, 25), 6u);
  EXPECT_EQ(getIndexByTime(times, 56), 10u);
  EXPECT_EQ(getIndexByTime(times, 57), 11u);
  EXPECT_EQ(getIndexByTime(times, 100), 11u);
}

// Covers log utils vector key behavior: adds exact and prefix match keys without duplicate rows.
TEST(LogUtilsVectorKeyTest, AddsExactAndPrefixMatchKeysWithoutDuplicateRows)
{
  std::vector<std::string> keys;
  std::vector<bool> pmatch;

  addVectorKey(keys, pmatch, "NAV_*");
  addVectorKey(keys, pmatch, "APP_LOG");
  addVectorKey(keys, pmatch, "NAV_*");
  addVectorKey(keys, pmatch, "APP_LOG*");

  ASSERT_EQ(keys.size(), 2u);
  EXPECT_EQ(keys[0], "NAV_");
  EXPECT_TRUE(pmatch[0]);
  EXPECT_EQ(keys[1], "APP_LOG");
  EXPECT_TRUE(pmatch[1]);
}

// Covers log utils file parsing behavior: reads raw lines and reports eof sentinel.
TEST(LogUtilsFileParsingTest, ReadsRawLinesAndReportsEofSentinel)
{
  const std::string path = writeTempALog("raw_lines.alog", {
      "%% LOGSTART 1689355500.000",
      "0.000 NAV_X pNodeReporter 10.0",
      "1.000 NODE_REPORT pNodeReporter NAME=abe,X=10,Y=20"});

  FILE* file = openRead(path);
  ASSERT_NE(file, nullptr);
  EXPECT_EQ(getNextRawLine(file), "%% LOGSTART 1689355500.000");
  EXPECT_EQ(getNextRawLine(file), "0.000 NAV_X pNodeReporter 10.0");
  EXPECT_EQ(getNextRawLine(file), "1.000 NODE_REPORT pNodeReporter NAME=abe,X=10,Y=20");
  EXPECT_EQ(getNextRawLine(file), "eof");
  std::fclose(file);

  EXPECT_EQ(getFileLineCount(path), 3u);
}

// Covers log utils file parsing behavior: reads raw alog entries with numeric string aux and invalid lines.
TEST(LogUtilsFileParsingTest, ReadsRawAlogEntriesWithNumericStringAuxAndInvalidLines)
{
  const std::string path = writeTempALog("raw_entries.alog", {
      "0.000 NAV_X pNodeReporter 10.5",
      "0.250 HELM_MODE pHelmIvP:iter=12 SURVEYING",
      "line continuation from DB_VARSUMMARY",
      "0.500 APP_LOG pHelmIvP iter=12,log=bhv active!@#course ok"});

  FILE* file = openRead(path);
  ASSERT_NE(file, nullptr);

  ALogEntry numeric = getNextRawALogEntry(file);
  EXPECT_EQ(numeric.getStatus(), "");
  EXPECT_DOUBLE_EQ(numeric.getTimeStamp(), 0.0);
  EXPECT_EQ(numeric.getVarName(), "NAV_X");
  EXPECT_EQ(numeric.getSource(), "pNodeReporter");
  EXPECT_EQ(numeric.getSrcAux(), "");
  EXPECT_TRUE(numeric.isNumerical());
  EXPECT_DOUBLE_EQ(numeric.getDoubleVal(), 10.5);

  ALogEntry text = getNextRawALogEntry(file);
  EXPECT_EQ(text.getStatus(), "");
  EXPECT_DOUBLE_EQ(text.getTimeStamp(), 0.25);
  EXPECT_EQ(text.getVarName(), "HELM_MODE");
  EXPECT_EQ(text.getSource(), "pHelmIvP");
  EXPECT_EQ(text.getSrcAux(), "iter=12");
  EXPECT_FALSE(text.isNumerical());
  EXPECT_EQ(text.getStringVal(), "SURVEYING");

  // Continuation-like lines without timestamp/var/source fields are surfaced
  // as invalid entries, unless a caller explicitly asks to skip bad lines.
  ALogEntry invalid = getNextRawALogEntry(file);
  EXPECT_EQ(invalid.getStatus(), "invalid");

  ALogEntry app_log = getNextRawALogEntry(file, true);
  EXPECT_EQ(app_log.getStatus(), "");
  EXPECT_EQ(app_log.getVarName(), "APP_LOG");
  EXPECT_FALSE(app_log.isNumerical());
  EXPECT_EQ(app_log.getStringVal(), "iter=12,log=bhv active!@#course ok");

  ALogEntry eof = getNextRawALogEntry(file);
  EXPECT_EQ(eof.getStatus(), "eof");
  std::fclose(file);
}

// Covers log utils file parsing behavior: finds log start and data time bounds in synthetic mission log.
TEST(LogUtilsFileParsingTest, FindsLogStartAndDataTimeBoundsInSyntheticMissionLog)
{
  // Real alogs may be sorted after collection; data bounds come from all valid
  // data lines, not from the first and last physical line after LOGSTART.
  const std::string path = writeTempALog("mission_bounds.alog", {
      // Keep file-bounds checks independent of the known unterminated
      // end-of-line timestamp defect, covered by logstart-known-issues.
      "%% LOGSTART 1689355500.000 ",
      "%% FILEOPEN 07/14/2023 11:10:00 AM",
      "4.500 NAV_X pNodeReporter 100",
      "2.000 NAV_Y pNodeReporter 20",
      "3.000 HELM_MODE pHelmIvP SURVEY",
      "20.000 NAV_SPEED pNodeReporter 1.8",
      "1.000 LATE_SORTED_BACKFILL pLogger replay"});

  EXPECT_DOUBLE_EQ(getLogStart("%% LOGSTART 1689355500.000 "), 1689355500.0);
  EXPECT_DOUBLE_EQ(getLogStartFromFile(path), 1689355500.0);
  EXPECT_DOUBLE_EQ(getDataStartTimeFromFile(path), 2.0);
  EXPECT_DOUBLE_EQ(getDataEndTimeFromFile(path), 20.0);
  EXPECT_DOUBLE_EQ(getLogStartFromFile("/definitely/not/a/file.alog"), 0.0);
  EXPECT_DOUBLE_EQ(getDataStartTimeFromFile("/definitely/not/a/file.alog"), 0.0);
  EXPECT_DOUBLE_EQ(getDataEndTimeFromFile("/definitely/not/a/file.alog"), 0.0);
}
