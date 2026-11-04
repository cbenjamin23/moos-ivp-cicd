#include <gtest/gtest.h>

#include <algorithm>
#include <fstream>
#include <set>
#include <string>
#include <sys/stat.h>
#include <vector>

#include "SplitHandler.h"
#include "TestFileUtils.h"

namespace {

class TestableSplitHandler : public SplitHandler {
 public:
  explicit TestableSplitHandler(const std::string& alog_file)
      : SplitHandler(alog_file)
  {
  }

  using SplitHandler::detached;
  using SplitHandler::detachedSet;
  using SplitHandler::handlePreCheckSplitDir;
  using SplitHandler::nodeRecordToViewVessel;

  unsigned int maxCache() const { return m_max_cache; }
  bool splitDirPrior() const { return m_split_dir_prior; }
};

std::string WithNewlines(const std::vector<std::string>& lines)
{
  std::string contents;
  for(const std::string& line : lines)
    contents += line + "\n";
  return contents;
}

std::string ReadText(const std::string& path)
{
  std::ifstream in(path.c_str());
  return std::string((std::istreambuf_iterator<char>(in)),
                     std::istreambuf_iterator<char>());
}

bool Contains(const std::string& haystack, const std::string& needle)
{
  return haystack.find(needle) != std::string::npos;
}

}  // namespace

// Duplicate suppression is per variable and only removes identical raw rows:
// another variable in between does not reset it, but a new timestamp does.
TEST(AlogSplitHandlerTest, SuppressesIdenticalRowsButPreservesTimeAndValueChanges)
{
  TempDir temp("alogsplit_duplicates");
  const std::string alog = temp.writeFile(
      "input.alog", WithNewlines({
          "%% LOGSTART 123.000",
          "0.000 NAV_X pExampleApp 1", "0.000 NAV_X pExampleApp 1",
          "0.000 NAV_Y pExampleApp 2", "0.000 NAV_X pExampleApp 1",
          "1.000 NAV_X pExampleApp 1", "1.000 NAV_X pExampleApp 1",
          "2.000 NAV_X pExampleApp 2"}));
  const std::string out_dir = temp.filePath("split_out");
  SplitHandler handler(alog);
  handler.setDirectory(out_dir);
  ASSERT_TRUE(handler.handle());
  const std::string rows = ReadText(out_dir + "/NAV_X.klog");
  EXPECT_EQ(std::count(rows.begin(), rows.end(), '\n'), 3);
  EXPECT_TRUE(Contains(rows, "0.000"));
  EXPECT_TRUE(Contains(rows, "1.000"));
  EXPECT_TRUE(Contains(rows, "2.000"));
}

// Source audit note: app_alogsplit has only a thin main.cpp parser and delegates
// the real splitting work to lib_logutils SplitHandler. This family therefore
// pins alogsplit's direct component surface through SplitHandler configuration,
// detached-field parsing, prior-cache behavior, and NODE_REPORT visual
// conversion. CLI argument parsing and process exit paths are intentionally out
// of scope for these direct C++ CTests.

// Covers app_alogsplit's max_fptrs clamp path through SplitHandler.
TEST(AlogSplitHandlerTest, ClampsMaxFilePointerCache)
{
  TestableSplitHandler handler("input.alog");
  EXPECT_EQ(handler.maxCache(), 125u);

  handler.setMaxFilePtrCache(0);
  EXPECT_EQ(handler.maxCache(), 10u);
  handler.setMaxFilePtrCache(9);
  EXPECT_EQ(handler.maxCache(), 10u);
  handler.setMaxFilePtrCache(10);
  EXPECT_EQ(handler.maxCache(), 10u);
  handler.setMaxFilePtrCache(2001);
  EXPECT_EQ(handler.maxCache(), 2000u);
}

// Covers detached pair forms used by alogsplit --detached=VAR[:KEY...].
TEST(AlogSplitHandlerTest, ParsesDetachedAllAndMultipleKeys)
{
  TestableSplitHandler handler("input.alog");

  EXPECT_FALSE(handler.addDetachedPair(""));
  EXPECT_TRUE(handler.addDetachedPair("APP_OVERVIEW"));
  EXPECT_EQ(handler.detached("APP_OVERVIEW"), "");
  EXPECT_EQ(handler.detachedSet("APP_OVERVIEW"), std::set<std::string>({"all"}));

  EXPECT_TRUE(handler.addDetachedPair("REPORT:x:y"));
  EXPECT_EQ(handler.detached("REPORT"), "y");
  EXPECT_EQ(handler.detachedSet("REPORT"), (std::set<std::string>({"x", "y"})));

  EXPECT_FALSE(handler.addDetachedPair("BAD VAR", "x"));
  EXPECT_FALSE(handler.addDetachedPair("REPORT", "bad key"));
}

// Covers split-directory precheck behavior for unconfirmed and prior-cache dirs.
TEST(AlogSplitHandlerTest, SplitDirPrecheckRequiresConfirmedAlogAndAcceptsPriorCache)
{
  TempDir temp("alogsplit_precheck");
  const std::string alog =
      temp.writeFile("input.alog", "0.000 NAV_X pNodeReporter 1\n");
  const std::string prior_dir = temp.filePath("prior_cache");
  ASSERT_EQ(mkdir(prior_dir.c_str(), 0700), 0);

  TestableSplitHandler unconfirmed(alog);
  unconfirmed.setDirectory(temp.filePath("new_cache"));
  testing::internal::CaptureStdout();
  EXPECT_FALSE(unconfirmed.handlePreCheckSplitDir());
  EXPECT_TRUE(Contains(testing::internal::GetCapturedStdout(),
                       "Unconfirmed alog_file"));

  TestableSplitHandler prior(alog);
  ASSERT_TRUE(prior.handlePreCheckALogFile());
  prior.setDirectory(prior_dir);
  testing::internal::CaptureStdout();
  EXPECT_FALSE(prior.handlePreCheckSplitDir());
  EXPECT_TRUE(prior.splitDirPrior());
  EXPECT_TRUE(Contains(testing::internal::GetCapturedStdout(), "confirmed"));

  TestableSplitHandler handled_prior(alog);
  handled_prior.setDirectory(prior_dir);
  EXPECT_TRUE(handled_prior.handle());
}

// Covers NODE_REPORT to VIEW_VESSEL conversion used for alogview visuals.
TEST(AlogSplitHandlerTest, ConvertsValidNodeReportToViewVessel)
{
  TestableSplitHandler handler("input.alog");

  const std::string vessel = handler.nodeRecordToViewVessel(
      "NAME=alpha,TYPE=kayak,COLOR=red,LENGTH=4.2,X=1,Y=2,SPD=1.5,HDG=90,UTC_TIME=1000");

  EXPECT_TRUE(Contains(vessel, "label=alpha"));
  EXPECT_TRUE(Contains(vessel, "x=1"));
  EXPECT_TRUE(Contains(vessel, "y=2"));
  EXPECT_TRUE(Contains(vessel, "hdg=90"));
  EXPECT_TRUE(Contains(vessel, "len=4.2"));
  EXPECT_TRUE(Contains(vessel, "type=kayak"));
  EXPECT_TRUE(Contains(vessel, "color=red"));
  EXPECT_TRUE(Contains(vessel, "time=1000"));
  EXPECT_TRUE(Contains(vessel, "dur=3"));

  EXPECT_EQ(handler.nodeRecordToViewVessel("X=1,Y=2"), "");
}

// Covers detached-all extraction from CSP and JSON payloads in a small split.
TEST(AlogSplitHandlerTest, SplitsDetachedAllPayloadFields)
{
  TempDir temp("alogsplit_detached_all");
  const std::string alog = temp.writeFile(
      "input.alog",
      WithNewlines({"%% LOGSTART 123.000",
                    "0.000 APP_OVERVIEW pExampleApp temp=98.5,fuel=14.5,label=hot",
                    "0.100 JSON_REPORT pExampleApp {\"temp\":12.5,\"fuel\":3,\"name\":\"abe\"}"}));
  const std::string out_dir = temp.filePath("split_out");

  SplitHandler handler(alog);
  handler.setDirectory(out_dir);
  ASSERT_TRUE(handler.addDetachedPair("APP_OVERVIEW"));
  ASSERT_TRUE(handler.addDetachedPair("JSON_REPORT"));
  ASSERT_TRUE(handler.handle());

  EXPECT_EQ(ReadText(out_dir + "/APP_OVERVIEW:TEMP.klog"),
            "0.000  APP_OVERVIEW:TEMP  pExampleApp  98.5\n");
  EXPECT_EQ(ReadText(out_dir + "/APP_OVERVIEW:FUEL.klog"),
            "0.000  APP_OVERVIEW:FUEL  pExampleApp  14.5\n");
  EXPECT_EQ(ReadText(out_dir + "/JSON_REPORT:TEMP.klog"),
            "0.100  JSON_REPORT:TEMP  pExampleApp  12.5\n");
  EXPECT_EQ(ReadText(out_dir + "/JSON_REPORT:FUEL.klog"),
            "0.100  JSON_REPORT:FUEL  pExampleApp  3\n");
  EXPECT_EQ(ReadText(out_dir + "/APP_OVERVIEW:LABEL.klog"), "");
  EXPECT_EQ(ReadText(out_dir + "/JSON_REPORT:NAME.klog"), "");
}
