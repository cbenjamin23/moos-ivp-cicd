#include <gtest/gtest.h>

#include <memory>

#include "AOF_OpRegion.h"
#include "BHV_OpRegionV26.h"
#include "InfoBuffer.h"
#include "IvPBuildTestUtils.h"
#include "PlatModel.h"
#include "XYGenPolygon.h"

namespace {

const char* kSquare =
  "border={-50,-50:50,-50:50,50:-50,50},label=border # "
  "poly={-50,-50:50,-50:50,50:-50,50},label=cover";

void configureAOF(AOF_OpRegion& aof, double x = 0)
{
  PlatModel model(x, 0, 90, 2);
  model.setModelType("holo");
  aof.setPlatModel(model);
  aof.setGenPoly(stringToGenPoly(kSquare));
  ASSERT_TRUE(aof.setParam("min_util_eta", 5));
  ASSERT_TRUE(aof.setParam("max_util_eta", 25));
  ASSERT_TRUE(aof.setParam("min_util_cpa", 4));
  ASSERT_TRUE(aof.setParam("max_util_cpa", 10));
  ASSERT_TRUE(aof.setParam("cpa_window", 10));
}

}  // namespace

// These are desired-state contracts, not expected-failure assertions. An
// upstream fix must turn them green, at which point they can join the main gate.
TEST(OpRegionKnownIssuesTest, RejectsReversedCPAThresholds)
{
  AOF_OpRegion aof(makeCourseSpeedDomain());
  configureAOF(aof);
  ASSERT_TRUE(aof.setParam("min_util_cpa", 30));
  EXPECT_FALSE(aof.initialize());
}

TEST(OpRegionKnownIssuesTest, RejectsDisablingBothScoringFactors)
{
  AOF_OpRegion aof(makeCourseSpeedDomain());
  configureAOF(aof);
  ASSERT_TRUE(aof.setParam("eta_factored", "false"));
  ASSERT_TRUE(aof.setParam("cpa_factored", "false"));
  EXPECT_FALSE(aof.initialize());
}

TEST(OpRegionKnownIssuesTest, CPAOnlyPenalizesCrossingOneMeterFromBoundary)
{
  AOF_OpRegion aof(makeCourseSpeedDomain());
  configureAOF(aof, 49);
  ASSERT_TRUE(aof.setParam("eta_factored", "false"));
  ASSERT_TRUE(aof.initialize());
  IvPBox safe = makePointBox(2, {270, 2});
  IvPBox crossing = makePointBox(2, {90, 2});
  EXPECT_GT(aof.evalBox(&safe), aof.evalBox(&crossing));
}

TEST(OpRegionKnownIssuesTest, ZeroCPAWindowDoesNotSilentlyUseDefaults)
{
  InfoBuffer info;
  info.setCurrTime(10);
  info.setValue("NAV_X", 0);
  info.setValue("NAV_Y", 0);
  info.setValue("NAV_HEADING", 90);
  info.setValue("NAV_SPEED", 2);
  PlatModel model(0, 0, 90, 2);
  model.setModelType("holo");
  BHV_OpRegionV26 behavior(makeCourseSpeedDomain());
  behavior.setInfoBuffer(&info);
  behavior.setPlatModel(model);
  ASSERT_TRUE(behavior.setParam("core_poly", kSquare));
  ASSERT_TRUE(behavior.setParam("trigger_on_poly_entry", "false"));
  ASSERT_TRUE(behavior.setParam("min_util_eta", "5"));
  ASSERT_TRUE(behavior.setParam("max_util_eta", "25"));
  // A parser rejection is also a valid fix; otherwise initialization must
  // report an error instead of replacing the rejected value with AOF defaults.
  if(!behavior.setParam("cpa_window", "0"))
    return;
  behavior.onSetParamComplete();
  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  EXPECT_EQ(ipf, nullptr);
  EXPECT_FALSE(behavior.stateOK());
}
