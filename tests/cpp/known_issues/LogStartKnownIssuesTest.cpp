#include <gtest/gtest.h>

#include "LogUtils.h"
#include "TestFileUtils.h"

// A shorter, valid timestamp must not retain digits from an earlier parse.
// Keep this desired-state assertion red until the upstream parser terminates
// and bounds its timestamp buffer; never invert it into an expected pass.
TEST(LogStartKnownIssuesTest, ParsesEndOfLineTimestampWithoutStaleDigits)
{
  EXPECT_DOUBLE_EQ(getLogStart("%% LOGSTART 1689355500.987654321 "),
                   1689355500.987654321);
  EXPECT_DOUBLE_EQ(getLogStart("%% LOGSTART 1689355500.0"), 1689355500.0);

  TempFile log("unterminated_logstart", "%% LOGSTART 1689355500.000\n", ".alog");
  EXPECT_DOUBLE_EQ(getLogStartFromFile(log.path()), 1689355500.0);
}
