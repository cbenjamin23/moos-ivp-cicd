#include <gtest/gtest.h>

#include "AOF_OpRegion.h"
#include "IvPBuildTestUtils.h"
#include "PlatModel.h"
#include "XYGenPolygon.h"
#include "XYPolygon.h"
#include "XYSegList.h"

namespace {

IvPBox courseSpeedBox(unsigned int course, unsigned int speed)
{
  return makePointBox(2, {static_cast<int>(course), static_cast<int>(speed)});
}

XYGenPolygon makeSquareGenPoly(double low, double high)
{
  XYSegList border;
  border.add_vertex(low, low);
  border.add_vertex(high, low);
  border.add_vertex(high, high);
  border.add_vertex(low, high);

  XYPolygon cover;
  cover.add_vertex(low, low, false);
  cover.add_vertex(high, low, false);
  cover.add_vertex(high, high, false);
  cover.add_vertex(low, high, false);
  cover.determine_convexity();

  XYGenPolygon gpoly;
  EXPECT_TRUE(gpoly.setGenPoly(border, {cover}));
  return gpoly;
}

}  // namespace

// Covers AOF op region behavior: validates required geometry, platform model,
// ETA bounds, and the stopped-vehicle safety edge case.
TEST(AOFOpRegionTest, ValidatesInputsAndScoresImmediateExitBelowLongExit)
{
  AOF_OpRegion missing_config(makeCourseSpeedDomain());
  EXPECT_FALSE(missing_config.initialize());

  PlatModel near_boundary(49, 0, 90, 2);
  near_boundary.setModelType("holo");

  AOF_OpRegion near_exit(makeCourseSpeedDomain());
  near_exit.setGenPoly(makeSquareGenPoly(-50, 50));
  near_exit.setPlatModel(near_boundary);
  EXPECT_TRUE(near_exit.setParam("min_util_eta", 5));
  EXPECT_TRUE(near_exit.setParam("max_util_eta", 25));
  EXPECT_FALSE(near_exit.setParam("min_util_eta", 0));
  EXPECT_FALSE(near_exit.setParam("unknown", 10));
  ASSERT_TRUE(near_exit.initialize());

  IvPBox stopped = courseSpeedBox(90, 0);
  IvPBox exiting_east = courseSpeedBox(90, 2);
  IvPBox staying_west = courseSpeedBox(270, 2);
  EXPECT_DOUBLE_EQ(near_exit.evalBox(&stopped), 100);
  EXPECT_DOUBLE_EQ(near_exit.evalBox(&exiting_east), 0);
  EXPECT_GT(near_exit.evalBox(&staying_west), near_exit.evalBox(&exiting_east));

  AOF_OpRegion reversed_eta(makeCourseSpeedDomain());
  reversed_eta.setGenPoly(makeSquareGenPoly(-50, 50));
  reversed_eta.setPlatModel(near_boundary);
  EXPECT_TRUE(reversed_eta.setParam("min_util_eta", 25));
  EXPECT_TRUE(reversed_eta.setParam("max_util_eta", 5));
  EXPECT_FALSE(reversed_eta.initialize());
}

// Covers AOF op region behavior: an exit ETA between the configured endpoints
// receives interpolated utility rather than jumping directly to full utility.
TEST(AOFOpRegionTest, InterpolatesUtilityBetweenEtaThresholds)
{
  PlatModel mid_range(20, 0, 90, 2);
  mid_range.setModelType("holo");

  AOF_OpRegion aof(makeCourseSpeedDomain());
  aof.setGenPoly(makeSquareGenPoly(-50, 50));
  aof.setPlatModel(mid_range);
  ASSERT_TRUE(aof.setParam("min_util_eta", 5));
  ASSERT_TRUE(aof.setParam("max_util_eta", 25));
  // This contract isolates ETA interpolation; combined scoring may legitimately
  // reject the same course because it crosses the CPA projection window.
  ASSERT_TRUE(aof.setParam("cpa_factored", "false"));
  ASSERT_TRUE(aof.initialize());

  IvPBox exits_east = courseSpeedBox(90, 2);
  double utility = aof.evalBox(&exits_east);
  EXPECT_GT(utility, 0);
  EXPECT_LT(utility, 100);
  EXPECT_NEAR(utility, 50, 1e-9);
}

struct ScoringMode {
  const char* name;
  bool eta;
  bool cpa;
};

class OpRegionScoringModeTest : public testing::TestWithParam<ScoringMode> {};

// Each supported scoring mode should preserve transit away from a nearby
// boundary and penalize a course that exits within the configured horizon.
TEST_P(OpRegionScoringModeTest, SafeMovingCourseMatchesStoppedAndBeatsCrossing)
{
  PlatModel model(45, 0, 90, 2);
  model.setModelType("holo");
  AOF_OpRegion aof(makeCourseSpeedDomain());
  aof.setGenPoly(makeSquareGenPoly(-50, 50));
  aof.setPlatModel(model);
  ASSERT_TRUE(aof.setParam("min_util_eta", 5));
  ASSERT_TRUE(aof.setParam("max_util_eta", 25));
  ASSERT_TRUE(aof.setParam("min_util_cpa", 4));
  ASSERT_TRUE(aof.setParam("max_util_cpa", 10));
  ASSERT_TRUE(aof.setParam("cpa_window", 10));
  ASSERT_TRUE(aof.setParam("eta_factored", GetParam().eta ? "true" : "false"));
  ASSERT_TRUE(aof.setParam("cpa_factored", GetParam().cpa ? "true" : "false"));
  ASSERT_TRUE(aof.initialize());

  IvPBox stopped = courseSpeedBox(90, 0);
  IvPBox safe = courseSpeedBox(270, 2);
  IvPBox crossing = courseSpeedBox(90, 2);
  EXPECT_DOUBLE_EQ(aof.evalBox(&safe), aof.evalBox(&stopped));
  EXPECT_GT(aof.evalBox(&safe), aof.evalBox(&crossing));
}

INSTANTIATE_TEST_SUITE_P(Modes, OpRegionScoringModeTest,
  testing::Values(ScoringMode{"EtaOnly", true, false},
                  ScoringMode{"CPAOnly", false, true},
                  ScoringMode{"Combined", true, true}),
  [](const testing::TestParamInfo<ScoringMode>& info) { return info.param.name; });
