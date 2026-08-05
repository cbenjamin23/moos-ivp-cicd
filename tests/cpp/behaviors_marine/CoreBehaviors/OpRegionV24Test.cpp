#include <gtest/gtest.h>

#include <memory>
#include <string>
#include <vector>

#include "BHV_OpRegionV24.h"
#include "BehaviorMarineTestUtils.h"
#include "InfoBuffer.h"
#include "XYFormatUtilsPoly.h"

namespace {

bool findViewPolygonWithLabel(const std::vector<VarDataPair>& messages,
                              const std::string& label,
                              XYPolygon& found)
{
  for(const VarDataPair& message : messages) {
    if(message.get_var() != "VIEW_POLYGON")
      continue;

    XYPolygon polygon = string2Poly(message.get_sdata());
    if(polygon.get_label() == label) {
      found = polygon;
      return true;
    }
  }
  return false;
}

}  // namespace

// Covers BHV op region V24 behavior: builds core save halt polygons and stays idle inside save region.
TEST(BHVOpRegionV24Test, BuildsCoreSaveHaltPolygonsAndStaysIdleInsideSaveRegion)
{
  InfoBuffer info;
  info.setCurrTime(10);
  info.setValue("NAV_X", 0);
  info.setValue("NAV_Y", 0);
  info.setValue("NAV_HEADING", 0);
  info.setValue("NAV_SPEED", 2);

  BHV_OpRegionV24 behavior(makeCourseSpeedDomain());
  behavior.setInfoBuffer(&info);

  ASSERT_TRUE(behavior.setParam("us", "abe"));
  ASSERT_TRUE(behavior.setParam("core_poly", "pts={-50,-50:50,-50:50,50:-50,50}"));
  ASSERT_TRUE(behavior.setParam("save_dist", "10"));
  ASSERT_TRUE(behavior.setParam("halt_dist", "20"));
  ASSERT_TRUE(behavior.setParam("recover_speed", "1"));
  ASSERT_TRUE(behavior.setParam("trigger_on_poly_entry", "false"));
  EXPECT_FALSE(behavior.setParam("save_dist", "-1"));
  EXPECT_FALSE(behavior.setParam("recover_speed", "0"));

  behavior.onSetParamComplete();
  XYPolygon core;
  ASSERT_TRUE(findViewPolygonWithLabel(behavior.getMessages(), "coreabe", core));
  EXPECT_EQ(core.size(), 4u);
  EXPECT_TRUE(core.contains(0, 0));
  EXPECT_FALSE(core.contains(55, 0));

  XYPolygon save;
  ASSERT_TRUE(findViewPolygonWithLabel(behavior.getMessages(), "opreg_save_abe", save));
  EXPECT_TRUE(save.contains(55, 0));
  EXPECT_FALSE(save.contains(61, 0));

  XYPolygon halt;
  ASSERT_TRUE(findViewPolygonWithLabel(behavior.getMessages(), "opreg_halt_abe", halt));
  EXPECT_TRUE(halt.contains(65, 0));
  EXPECT_FALSE(halt.contains(71, 0));

  behavior.clearMessages();
  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  EXPECT_EQ(ipf, nullptr);
  EXPECT_TRUE(behavior.stateOK());
}

// Covers BHV op region V24 behavior: save polygon exit builds recovery objective and posts mission flags.
TEST(BHVOpRegionV24Test, SavePolygonExitBuildsRecoveryObjectiveAndPostsMissionFlags)
{
  InfoBuffer info;
  info.setCurrTime(10);
  info.setValue("NAV_X", 0);
  info.setValue("NAV_Y", 0);
  info.setValue("NAV_HEADING", 90);
  info.setValue("NAV_SPEED", 2);

  BHV_OpRegionV24 behavior(makeCourseSpeedDomain());
  behavior.setInfoBuffer(&info);

  ASSERT_TRUE(behavior.setParam("us", "abe"));
  ASSERT_TRUE(behavior.setParam("core_poly", "pts={-50,-50:50,-50:50,50:-50,50}"));
  ASSERT_TRUE(behavior.setParam("save_dist", "10"));
  ASSERT_TRUE(behavior.setParam("halt_dist", "100"));
  ASSERT_TRUE(behavior.setParam("recover_speed", "1"));
  ASSERT_TRUE(behavior.setParam("trigger_on_poly_entry", "false"));
  ASSERT_TRUE(behavior.setParam("save_flag", "OPREG_SAVE_EXIT=true"));
  ASSERT_TRUE(behavior.setParam("savex_flag", "OPREG_SAVE_OUT=true"));

  behavior.onSetParamComplete();
  behavior.clearMessages();

  std::unique_ptr<IvPFunction> inside_ipf(behavior.onRunState());
  EXPECT_EQ(inside_ipf, nullptr);

  behavior.clearMessages();
  info.setCurrTime(20);
  info.setValue("NAV_X", 70);
  info.setValue("NAV_Y", 0);
  info.setValue("NAV_HEADING", 90);

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  ASSERT_NE(ipf, nullptr);
  EXPECT_DOUBLE_EQ(ipf->getPWT(), 100);
  EXPECT_TRUE(behavior.stateOK());

  VarDataPair save_flag;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_SAVE_EXIT", save_flag));
  EXPECT_EQ(save_flag.get_sdata(), "true");

  VarDataPair savex_flag;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_SAVE_OUT", savex_flag));
  EXPECT_EQ(savex_flag.get_sdata(), "true");

  VarDataPair turn;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "COMMITTED", turn));
  EXPECT_TRUE(turn.get_sdata() == "left" || turn.get_sdata() == "right" ||
              turn.get_sdata() == "none");
}

// Covers BHV op region V24 behavior: explicit save and halt polygons are used
// when distance-generated buffers are not configured.
TEST(BHVOpRegionV24Test, ExplicitSavePolygonExitBuildsRecoveryObjective)
{
  InfoBuffer info;
  info.setCurrTime(10);
  info.setValue("NAV_X", 0);
  info.setValue("NAV_Y", 0);
  info.setValue("NAV_HEADING", 90);
  info.setValue("NAV_SPEED", 2);

  BHV_OpRegionV24 behavior(makeCourseSpeedDomain());
  behavior.setInfoBuffer(&info);

  ASSERT_TRUE(behavior.setParam("us", "abe"));
  ASSERT_TRUE(behavior.setParam("core_poly", "pts={-50,-50:50,-50:50,50:-50,50}"));
  ASSERT_TRUE(behavior.setParam("save_poly", "pts={-50,-50:20,-50:20,50:-50,50}"));
  ASSERT_TRUE(behavior.setParam("halt_poly", "pts={-40,-40:40,-40:40,40:-40,40}"));
  ASSERT_TRUE(behavior.setParam("trigger_on_poly_entry", "false"));
  ASSERT_TRUE(behavior.setParam("trigger_exit_time", "0"));
  ASSERT_TRUE(behavior.setParam("save_flag", "OPREG_SAVE_EXIT=true"));
  ASSERT_TRUE(behavior.setParam("savex_flag", "OPREG_SAVE_OUT=true"));

  behavior.onSetParamComplete();
  behavior.clearMessages();

  std::unique_ptr<IvPFunction> inside_ipf(behavior.onRunState());
  EXPECT_EQ(inside_ipf, nullptr);

  behavior.clearMessages();
  info.setCurrTime(20);
  info.setValue("NAV_X", 30);

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  ASSERT_NE(ipf, nullptr);
  EXPECT_DOUBLE_EQ(ipf->getPWT(), 100);
  EXPECT_TRUE(behavior.stateOK());

  VarDataPair save_flag;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_SAVE_EXIT", save_flag));
  EXPECT_EQ(save_flag.get_sdata(), "true");

  VarDataPair savex_flag;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_SAVE_OUT", savex_flag));
  EXPECT_EQ(savex_flag.get_sdata(), "true");
}

// Covers BHV op region V24 behavior: an explicit halt polygon, rather than a
// distance-generated buffer, is the boundary used for the halt decision.
TEST(BHVOpRegionV24Test, ExplicitHaltPolygonBreachUsesConfiguredBoundary)
{
  InfoBuffer info;
  info.setCurrTime(10);
  info.setValue("NAV_X", 0);
  info.setValue("NAV_Y", 0);
  info.setValue("NAV_HEADING", 90);
  info.setValue("NAV_SPEED", 2);

  BHV_OpRegionV24 behavior(makeCourseSpeedDomain());
  behavior.setInfoBuffer(&info);

  ASSERT_TRUE(behavior.setParam("us", "abe"));
  ASSERT_TRUE(behavior.setParam("core_poly", "pts={-50,-50:50,-50:50,50:-50,50}"));
  ASSERT_TRUE(behavior.setParam("save_poly", "pts={-50,-50:50,-50:50,50:-50,50}"));
  ASSERT_TRUE(behavior.setParam("halt_poly", "pts={-25,-25:25,-25:25,25:-25,25}"));
  ASSERT_TRUE(behavior.setParam("trigger_on_poly_entry", "false"));
  ASSERT_TRUE(behavior.setParam("trigger_exit_time", "0"));
  ASSERT_TRUE(behavior.setParam("breached_poly_flag", "OPREG_HALT_BREACH=true"));

  behavior.onSetParamComplete();
  behavior.clearMessages();
  info.setValue("NAV_X", 30);

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  EXPECT_EQ(ipf, nullptr);
  EXPECT_FALSE(behavior.stateOK());

  VarDataPair flag;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_HALT_BREACH", flag));
  EXPECT_EQ(flag.get_sdata(), "true");

  VarDataPair error;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "BHV_ERROR", error));
  EXPECT_NE(error.get_sdata().find("HaltPoly"), std::string::npos);
}

// Covers BHV op region V24 behavior: halt polygon breach posts failure flag and status polygon.
TEST(BHVOpRegionV24Test, HaltPolygonBreachPostsFailureFlagAndStatusPolygon)
{
  InfoBuffer info;
  info.setCurrTime(10);
  info.setValue("NAV_X", 200);
  info.setValue("NAV_Y", 0);
  info.setValue("NAV_HEADING", 90);
  info.setValue("NAV_SPEED", 2);

  BHV_OpRegionV24 behavior(makeCourseSpeedDomain());
  behavior.setInfoBuffer(&info);

  ASSERT_TRUE(behavior.setParam("us", "abe"));
  ASSERT_TRUE(behavior.setParam("core_poly", "pts={-50,-50:50,-50:50,50:-50,50}"));
  ASSERT_TRUE(behavior.setParam("save_dist", "10"));
  ASSERT_TRUE(behavior.setParam("halt_dist", "20"));
  ASSERT_TRUE(behavior.setParam("trigger_on_poly_entry", "false"));
  ASSERT_TRUE(behavior.setParam("trigger_exit_time", "0"));
  ASSERT_TRUE(behavior.setParam("draw_halt_status", "true"));
  ASSERT_TRUE(behavior.setParam("breached_poly_flag", "OPREG_HALT_BREACH=true"));

  behavior.onSetParamComplete();
  behavior.clearMessages();

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  EXPECT_EQ(ipf, nullptr);
  EXPECT_FALSE(behavior.stateOK());

  VarDataPair flag;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_HALT_BREACH", flag));
  EXPECT_EQ(flag.get_sdata(), "true");

  VarDataPair error;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "BHV_ERROR", error));
  EXPECT_NE(error.get_sdata().find("HaltPoly"), std::string::npos);

  VarDataPair status;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "VIEW_POLYGON", status));
  EXPECT_NE(status.get_sdata().find("abe_stat"), std::string::npos);
}

// Covers BHV op region V24 behavior: depth altitude and timeout breaches use independent flags.
TEST(BHVOpRegionV24Test, DepthAltitudeAndTimeoutBreachesUseIndependentFlags)
{
  InfoBuffer info;
  info.setCurrTime(10);
  info.setValue("NAV_X", 0);
  info.setValue("NAV_Y", 0);
  info.setValue("NAV_HEADING", 0);
  info.setValue("NAV_SPEED", 1);
  info.setValue("NAV_DEPTH", 12);
  info.setValue("NAV_ALTITUDE", 2);

  BHV_OpRegionV24 behavior(makeCourseSpeedDomain());
  behavior.setInfoBuffer(&info);

  ASSERT_TRUE(behavior.setParam("us", "abe"));
  ASSERT_TRUE(behavior.setParam("core_poly", "pts={-50,-50:50,-50:50,50:-50,50}"));
  ASSERT_TRUE(behavior.setParam("save_dist", "10"));
  ASSERT_TRUE(behavior.setParam("halt_dist", "20"));
  ASSERT_TRUE(behavior.setParam("trigger_on_poly_entry", "false"));
  ASSERT_TRUE(behavior.setParam("max_depth", "10"));
  ASSERT_TRUE(behavior.setParam("min_altitude", "5"));
  ASSERT_TRUE(behavior.setParam("max_time", "5"));
  ASSERT_TRUE(behavior.setParam("breached_depth_flag", "OPREG_DEPTH_BREACH=true"));
  ASSERT_TRUE(behavior.setParam("breached_altitude_flag", "OPREG_ALT_BREACH=true"));
  ASSERT_TRUE(behavior.setParam("breached_time_flag", "OPREG_TIME_BREACH=true"));

  behavior.onSetParamComplete();
  behavior.clearMessages();
  info.setCurrTime(20);

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  EXPECT_EQ(ipf, nullptr);
  EXPECT_FALSE(behavior.stateOK());

  VarDataPair depth_flag;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_DEPTH_BREACH", depth_flag));
  EXPECT_EQ(depth_flag.get_sdata(), "true");

  VarDataPair altitude_flag;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_ALT_BREACH", altitude_flag));
  EXPECT_EQ(altitude_flag.get_sdata(), "true");

  VarDataPair time_flag;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_TIME_BREACH", time_flag));
  EXPECT_EQ(time_flag.get_sdata(), "true");
}

// Covers BHV op region V24 behavior: dynamic region updates rebuild the core,
// save, and halt polygons and change the resulting enforcement boundary.
TEST(BHVOpRegionV24Test, DynamicRegionVarRebuildsCoreSaveAndHaltPolygons)
{
  InfoBuffer info;
  info.setCurrTime(10);
  info.setValue("NAV_X", 0);
  info.setValue("NAV_Y", 0);
  info.setValue("NAV_HEADING", 0);
  info.setValue("NAV_SPEED", 1);

  BHV_OpRegionV24 behavior(makeCourseSpeedDomain());
  behavior.setInfoBuffer(&info);

  ASSERT_TRUE(behavior.setParam("us", "abe"));
  ASSERT_TRUE(behavior.setParam("core_poly", "pts={-50,-50:50,-50:50,50:-50,50}"));
  ASSERT_TRUE(behavior.setParam("save_dist", "10"));
  ASSERT_TRUE(behavior.setParam("halt_dist", "20"));
  ASSERT_TRUE(behavior.setParam("trigger_on_poly_entry", "false"));
  ASSERT_TRUE(behavior.setParam("trigger_exit_time", "0"));
  ASSERT_TRUE(behavior.setParam("dynamic_region_var", "OPREG_DYNAMIC_POLY"));
  ASSERT_TRUE(behavior.setParam("save_flag", "OPREG_SAVE_EXIT=true"));
  ASSERT_TRUE(behavior.setParam("savex_flag", "OPREG_SAVE_OUT=true"));

  behavior.onSetParamComplete();
  behavior.clearMessages();

  std::unique_ptr<IvPFunction> initial_ipf(behavior.onRunState());
  EXPECT_EQ(initial_ipf, nullptr);
  EXPECT_TRUE(behavior.stateOK());

  behavior.clearMessages();
  info.setCurrTime(20);
  info.setValue("NAV_X", 35);
  info.setValue("OPREG_DYNAMIC_POLY",
                "pts={-20,-20:20,-20:20,20:-20,20},label=updated_core");

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  ASSERT_NE(ipf, nullptr);
  EXPECT_DOUBLE_EQ(ipf->getPWT(), 100);
  EXPECT_TRUE(behavior.stateOK());

  XYPolygon core;
  ASSERT_TRUE(findViewPolygonWithLabel(behavior.getMessages(), "coreabe", core));
  EXPECT_TRUE(core.contains(0, 0));
  EXPECT_FALSE(core.contains(35, 0));

  XYPolygon save;
  ASSERT_TRUE(findViewPolygonWithLabel(behavior.getMessages(), "opreg_save_abe", save));
  EXPECT_TRUE(save.contains(0, 0));
  EXPECT_FALSE(save.contains(35, 0));

  XYPolygon halt;
  ASSERT_TRUE(findViewPolygonWithLabel(behavior.getMessages(), "opreg_halt_abe", halt));
  EXPECT_TRUE(halt.contains(35, 0));

  VarDataPair save_flag;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "OPREG_SAVE_EXIT", save_flag));
  EXPECT_EQ(save_flag.get_sdata(), "true");
}

// Covers BHV op region V24 behavior: run to idle erases core save and halt polygons.
TEST(BHVOpRegionV24Test, RunToIdleErasesCoreSaveAndHaltPolygons)
{
  InfoBuffer info;
  info.setCurrTime(10);
  info.setValue("NAV_X", 0);
  info.setValue("NAV_Y", 0);
  info.setValue("NAV_HEADING", 0);
  info.setValue("NAV_SPEED", 1);

  BHV_OpRegionV24 behavior(makeCourseSpeedDomain());
  behavior.setInfoBuffer(&info);

  ASSERT_TRUE(behavior.setParam("us", "abe"));
  ASSERT_TRUE(behavior.setParam("core_poly", "pts={-50,-50:50,-50:50,50:-50,50}"));
  ASSERT_TRUE(behavior.setParam("save_dist", "10"));
  ASSERT_TRUE(behavior.setParam("halt_dist", "20"));

  behavior.onSetParamComplete();
  behavior.clearMessages();

  behavior.onRunToIdleState();

  VarDataPair polygon;
  ASSERT_TRUE(findBehaviorMessage(behavior.getMessages(), "VIEW_POLYGON", polygon));
  EXPECT_NE(polygon.get_sdata().find("active=false"), std::string::npos);
}
