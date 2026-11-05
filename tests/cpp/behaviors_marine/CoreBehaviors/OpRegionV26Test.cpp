#include <gtest/gtest.h>

#include <memory>
#include <string>

#include "BHV_OpRegionV26.h"
#include "BehaviorMarineTestUtils.h"
#include "InfoBuffer.h"
#include "PlatModel.h"

namespace {

const std::string kSquareRegion =
  "border={-50,-50:50,-50:50,50:-50,50},label=opborder # "
  "poly={-50,-50:50,-50:50,50:-50,50},label=cover";

void seedPlatform(InfoBuffer& info,
                  BHV_OpRegionV26& behavior,
                  double x,
                  double y,
                  double heading = 90,
                  double speed = 2)
{
  info.setCurrTime(10);
  info.setValue("NAV_X", x);
  info.setValue("NAV_Y", y);
  info.setValue("NAV_HEADING", heading);
  info.setValue("NAV_SPEED", speed);
  behavior.setInfoBuffer(&info);

  PlatModel model(x, y, heading, speed);
  model.setModelType("holo");
  behavior.setPlatModel(model);
}

void configureRegion(BHV_OpRegionV26& behavior)
{
  ASSERT_TRUE(behavior.setParam("us", "abe"));
  ASSERT_TRUE(behavior.setParam("core_poly", kSquareRegion));
  ASSERT_TRUE(behavior.setParam("trigger_on_poly_entry", "false"));
  ASSERT_TRUE(behavior.setParam("trigger_breach_time", "0"));
  ASSERT_TRUE(behavior.setParam("lapse_dist", "5"));
  ASSERT_TRUE(behavior.setParam("breach_dist", "15"));
  ASSERT_TRUE(behavior.setParam("min_util_eta", "5"));
  ASSERT_TRUE(behavior.setParam("max_util_eta", "25"));
  ASSERT_TRUE(behavior.setParam("recover_spd", "1"));
}

}  // namespace

// Covers BHV op region V26 behavior: contained vehicles actively produce the
// new keep-in objective unless stay-in generation is disabled.
TEST(BHVOpRegionV26Test, ContainedStateBuildsOptionalKeepInObjective)
{
  InfoBuffer info;
  BHV_OpRegionV26 behavior(makeCourseSpeedDomain());
  seedPlatform(info, behavior, 0, 0);
  configureRegion(behavior);
  behavior.onSetParamComplete();
  behavior.clearMessages();

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  ASSERT_NE(ipf, nullptr);
  EXPECT_DOUBLE_EQ(ipf->getPWT(), 100);
  EXPECT_TRUE(behavior.stateOK());

  InfoBuffer disabled_info;
  BHV_OpRegionV26 disabled(makeCourseSpeedDomain());
  seedPlatform(disabled_info, disabled, 0, 0);
  configureRegion(disabled);
  ASSERT_TRUE(disabled.setParam("stay_in_enabled", "false"));
  disabled.onSetParamComplete();
  std::unique_ptr<IvPFunction> disabled_ipf(disabled.onRunState());
  EXPECT_EQ(disabled_ipf, nullptr);
  EXPECT_TRUE(disabled.stateOK());
}

// Covers BHV op region V26 behavior: leaving the generalized polygon within
// breach distance produces the recovery objective and transition flags.
TEST(BHVOpRegionV26Test, LapsedStateBuildsRecoveryObjectiveAndPostsFlags)
{
  InfoBuffer info;
  BHV_OpRegionV26 behavior(makeCourseSpeedDomain());
  seedPlatform(info, behavior, 0, 0, 90);
  configureRegion(behavior);
  ASSERT_TRUE(behavior.setParam("lapsed_flag", "OPREG_LAPSED=true"));
  ASSERT_TRUE(behavior.setParam("lapsedx_flag", "OPREG_ENTRY_DIST=$[ENTRY_DIST]"));
  behavior.onSetParamComplete();
  behavior.clearMessages();

  std::unique_ptr<IvPFunction> contained_ipf(behavior.onRunState());
  ASSERT_NE(contained_ipf, nullptr);
  behavior.clearMessages();

  info.setCurrTime(20);
  info.setValue("NAV_X", 55);
  PlatModel lapsed_model(55, 0, 90, 2);
  lapsed_model.setModelType("holo");
  behavior.setPlatModel(lapsed_model);

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  ASSERT_NE(ipf, nullptr);
  EXPECT_TRUE(behavior.stateOK());

  VarDataPair lapsed;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_LAPSED", lapsed));
  EXPECT_EQ(lapsed.get_sdata(), "true");
  VarDataPair entry_dist;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_ENTRY_DIST", entry_dist));
  EXPECT_DOUBLE_EQ(entry_dist.get_ddata(), 5);
}

// Covers BHV op region V26 behavior: an immediate breach posts its configured
// terminal flag and helm error instead of generating a recovery objective.
TEST(BHVOpRegionV26Test, ImmediateBreachPostsTerminalFlagAndError)
{
  InfoBuffer info;
  BHV_OpRegionV26 behavior(makeCourseSpeedDomain());
  seedPlatform(info, behavior, 70, 0, 90);
  configureRegion(behavior);
  ASSERT_TRUE(behavior.setParam("breached_flag", "OPREG_BREACHED=true"));
  behavior.onSetParamComplete();
  behavior.clearMessages();

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  EXPECT_EQ(ipf, nullptr);
  EXPECT_FALSE(behavior.stateOK());

  VarDataPair breached;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_BREACHED", breached));
  EXPECT_EQ(breached.get_sdata(), "true");
  VarDataPair error;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "BHV_ERROR", error));
  EXPECT_NE(error.get_sdata().find("OpRegion HaltPoly Failure"), std::string::npos);
}

// Covers BHV op region V26 behavior: a configured breach delay postpones the
// transition flag and error together, then posts both when the delay expires.
TEST(BHVOpRegionV26Test, DelayedBreachPostsTerminalFlagWhenDelayExpires)
{
  InfoBuffer info;
  BHV_OpRegionV26 behavior(makeCourseSpeedDomain());
  seedPlatform(info, behavior, 70, 0, 90);
  configureRegion(behavior);
  ASSERT_TRUE(behavior.setParam("trigger_breach_time", "2"));
  ASSERT_TRUE(behavior.setParam("breached_flag", "OPREG_BREACHED=true"));
  behavior.onSetParamComplete();
  behavior.clearMessages();

  std::unique_ptr<IvPFunction> initial_ipf(behavior.onRunState());
  EXPECT_EQ(initial_ipf, nullptr);
  EXPECT_TRUE(behavior.stateOK());
  VarDataPair early_flag;
  EXPECT_FALSE(findBehaviorMessage(behavior.getMessages(), "OPREG_BREACHED", early_flag));

  behavior.clearMessages();
  info.setCurrTime(13);
  std::unique_ptr<IvPFunction> delayed_ipf(behavior.onRunState());
  EXPECT_EQ(delayed_ipf, nullptr);
  EXPECT_FALSE(behavior.stateOK());

  VarDataPair breached;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_BREACHED", breached));
  EXPECT_EQ(breached.get_sdata(), "true");
  VarDataPair error;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "BHV_ERROR", error));
}
