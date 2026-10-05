#include <gtest/gtest.h>

#include <algorithm>
#include <cmath>

#include "AOF_AttractorCPA.h"
#include "AOF_AvoidCollision.h"
#include "AOF_AvoidCollisionDepth.h"
#include "AOF_AvoidObstacleV24.h"
#include "AOF_AvoidWalls.h"
#include "AOF_ContactX.h"
#include "AOF_CutRangeCPA.h"
#include "AOF_Shadow.h"
#include "AOF_Waypoint.h"
#include "CPXEngineOG.h"
#include "IvPBuildTestUtils.h"
#include "NumericAssertions.h"
#include "ObShipModelV24.h"
#include "XYFormatUtilsPoly.h"
#include "XYSegList.h"

namespace {

IvPBox courseSpeedBox(unsigned int course, unsigned int speed)
{
  return makePointBox(2, {static_cast<int>(course), static_cast<int>(speed)});
}

IvPDomain makeCourseSpeedDepthDomain()
{
  IvPDomain domain;
  domain.addDomain("course", 0, 359, 360);
  domain.addDomain("speed", 0, 5, 6);
  domain.addDomain("depth", 0, 20, 21);
  return domain;
}

IvPDomain makeSpeedOnlyDomain()
{
  IvPDomain domain;
  domain.addDomain("speed", 0, 5, 6);
  return domain;
}

IvPBox courseSpeedDepthBox(unsigned int course, unsigned int speed, unsigned int depth)
{
  return makePointBox(3, {static_cast<int>(course),
                          static_cast<int>(speed),
                          static_cast<int>(depth)});
}

void configureContactAOF(AOF_ContactX& aof)
{
  EXPECT_TRUE(aof.setParam("collision_distance", 10));
  EXPECT_TRUE(aof.setParam("all_clear_distance", 40));
  EXPECT_TRUE(aof.setParam("tol", 60));
}

void configureLatLonContactAOF(AOF_CutRangeCPA& aof)
{
  EXPECT_TRUE(aof.setParam("oslon", 0));
  EXPECT_TRUE(aof.setParam("oslat", 0));
  EXPECT_TRUE(aof.setParam("cnlon", 100));
  EXPECT_TRUE(aof.setParam("cnlat", 0));
  EXPECT_TRUE(aof.setParam("cncrs", 90));
  EXPECT_TRUE(aof.setParam("cnspd", 1));
  EXPECT_TRUE(aof.setParam("tol", 60));
}

void configureAttractorAOF(AOF_AttractorCPA& aof)
{
  EXPECT_TRUE(aof.setParam("oslon", 0));
  EXPECT_TRUE(aof.setParam("oslat", 0));
  EXPECT_TRUE(aof.setParam("cnlon", 100));
  EXPECT_TRUE(aof.setParam("cnlat", 0));
  EXPECT_TRUE(aof.setParam("cncrs", 90));
  EXPECT_TRUE(aof.setParam("cnspd", 1));
  EXPECT_TRUE(aof.setParam("tol", 60));
  EXPECT_TRUE(aof.setParam("min_util_cpa_dist", 80));
  EXPECT_TRUE(aof.setParam("max_util_cpa_dist", 20));
}

ObShipModelV24 makeAvoidObstacleModel()
{
  ObShipModelV24 model;
  model.setPose(0, 0, 90, 2);
  EXPECT_EQ(model.setGutPoly(string2Poly("pts={40,-10:60,-10:60,10:40,10},label=ob_0")), "");
  EXPECT_EQ(model.setMinUtilCPA(5), "");
  EXPECT_EQ(model.setMaxUtilCPA(20), "");
  EXPECT_EQ(model.setAllowableTTC(20), "");
  model.setCachedVals(true);
  return model;
}

XYSegList makeWallAhead()
{
  XYSegList wall;
  wall.add_vertex(10, -25);
  wall.add_vertex(10, 25);
  return wall;
}

XYSegList makeCrossingWall()
{
  XYSegList wall;
  wall.add_vertex(0, 0);
  wall.add_vertex(10, 10);
  wall.add_vertex(0, 10);
  wall.add_vertex(10, 0);
  return wall;
}

void configureAvoidWalls(AOF_AvoidWalls& aof)
{
  EXPECT_TRUE(aof.setParam("osx", 0));
  EXPECT_TRUE(aof.setParam("osy", 0));
  EXPECT_TRUE(aof.setParam("osh", 90));
  EXPECT_TRUE(aof.setParam("turn_radius", 10));
  EXPECT_TRUE(aof.setParam("nogo_ttcpa", 5));
  EXPECT_TRUE(aof.setParam("safe_ttcpa", 20));
  EXPECT_TRUE(aof.setParam("collision_distance", 5));
  EXPECT_TRUE(aof.setParam("all_clear_distance", 20));
  EXPECT_TRUE(aof.setParam("tol", 60));
}

}  // namespace

// Covers AOF waypoint behavior: scores course and speed toward next waypoint.
TEST(AOFWaypointTest, ScoresCourseAndSpeedTowardNextWaypoint)
{
  AOF_Waypoint aof(makeCourseSpeedDomain());
  EXPECT_FALSE(aof.initialize());
  EXPECT_TRUE(aof.setParam("osx", 0));
  EXPECT_TRUE(aof.setParam("osy", 0));
  EXPECT_TRUE(aof.setParam("ptx", 100));
  EXPECT_TRUE(aof.setParam("pty", 0));
  EXPECT_TRUE(aof.setParam("desired_speed", 2));
  EXPECT_FALSE(aof.setParam("unknown", 1));
  ASSERT_TRUE(aof.initialize());

  IvPBox ideal = courseSpeedBox(90, 2);
  IvPBox opposite = courseSpeedBox(270, 2);
  IvPBox stopped = courseSpeedBox(90, 0);
  IvPBox overspeed = courseSpeedBox(90, 5);

  EXPECT_GT(aof.evalBox(&ideal), aof.evalBox(&opposite));
  EXPECT_GT(aof.evalBox(&ideal), aof.evalBox(&stopped));
  EXPECT_GT(aof.evalBox(&overspeed), aof.evalBox(&stopped));
  EXPECT_NEAR(aof.evalBox(&ideal), 100.0, kGeomTol);
}

// Covers AOF waypoint behavior: rejects missing domain variables and required parameters.
TEST(AOFWaypointTest, RejectsMissingDomainVariablesAndRequiredParameters)
{
  AOF_Waypoint missing_course(makeSpeedOnlyDomain());
  EXPECT_TRUE(missing_course.setParam("osx", 0));
  EXPECT_TRUE(missing_course.setParam("osy", 0));
  EXPECT_TRUE(missing_course.setParam("ptx", 100));
  EXPECT_TRUE(missing_course.setParam("pty", 0));
  EXPECT_TRUE(missing_course.setParam("desired_speed", 2));
  EXPECT_FALSE(missing_course.initialize());

  AOF_Waypoint missing_speed{IvPDomain()};
  EXPECT_FALSE(missing_speed.initialize());

  AOF_Waypoint missing_desired_speed(makeCourseSpeedDomain());
  EXPECT_TRUE(missing_desired_speed.setParam("osx", 0));
  EXPECT_TRUE(missing_desired_speed.setParam("osy", 0));
  EXPECT_TRUE(missing_desired_speed.setParam("ptx", 100));
  EXPECT_TRUE(missing_desired_speed.setParam("pty", 0));
  EXPECT_FALSE(missing_desired_speed.initialize());
}

// Covers the replacement contact AOF: validates an externally owned CPX engine
// and utility parameters. Relative contact geometry now belongs to that engine.
TEST(AOFContactXTest, ValidatesExternalEngineAndReportsRelativeContactGeometry)
{
  CPXEngineOG engine(0, 100, 270, 1, 0, 0, 90, 2);
  AOF_ContactX aof(makeCourseSpeedDomain(), &engine);
  EXPECT_FALSE(aof.initialize());
  configureContactAOF(aof);
  ASSERT_TRUE(aof.initialize());

  EXPECT_GT(engine.cnSpdInOSPos(), 0.0);
  EXPECT_NEAR(engine.getRangeGamma(), 0.0, kGeomTol);
  EXPECT_FALSE(engine.aftOfContact());
  // The legacy port assertion used a point exactly on the bowline; CPX has
  // different tie handling. Verify port/starboard with off-axis points instead.
  engine.reset(0, 100, 270, 1, -1, 0, 90, 2);
  EXPECT_TRUE(engine.portOfContact());
  EXPECT_FALSE(engine.starOfContact());
  engine.reset(0, 100, 270, 1, 1, 0, 90, 2);
  EXPECT_TRUE(engine.starOfContact());
  EXPECT_FALSE(engine.portOfContact());
  EXPECT_FALSE(aof.setParam("bogus", 5));

  AOF_ContactX invalid(makeCourseSpeedDomain(), nullptr);
  configureContactAOF(invalid);
  EXPECT_FALSE(invalid.initialize());
}

// Covers AOF avoid collision behavior: rewards courses that avoid head on CPA.
TEST(AOFAvoidCollisionTest, RewardsCoursesThatAvoidHeadOnCPA)
{
  CPXEngineOG engine(0, 100, 270, 1, 0, 0, 90, 2);
  AOF_AvoidCollision aof(makeCourseSpeedDomain(), &engine);
  configureContactAOF(aof);
  ASSERT_TRUE(aof.initialize());

  IvPBox head_on = courseSpeedBox(90, 5);
  IvPBox turn_away = courseSpeedBox(0, 5);
  IvPBox stopped = courseSpeedBox(90, 0);

  EXPECT_TRUE(aof.minMaxKnown());
  EXPECT_DOUBLE_EQ(aof.getKnownMin(), 0);
  EXPECT_GT(aof.getKnownMax(), 0);
  EXPECT_LT(aof.evalBox(&head_on), aof.evalBox(&turn_away));
  EXPECT_GT(aof.evalBox(&stopped), aof.evalBox(&head_on));
}

// Covers AOF avoid collision depth behavior: rewards diving below collision depth when CPA is poor.
TEST(AOFAvoidCollisionDepthTest, RewardsDivingBelowCollisionDepthWhenCPAIsPoor)
{
  AOF_AvoidCollisionDepth aof(makeCourseSpeedDepthDomain());
  EXPECT_FALSE(aof.initialize());
  EXPECT_TRUE(aof.setParam("osx", 0));
  EXPECT_TRUE(aof.setParam("osy", 0));
  EXPECT_TRUE(aof.setParam("osh", 90));
  EXPECT_TRUE(aof.setParam("osv", 2));
  EXPECT_TRUE(aof.setParam("cnx", 100));
  EXPECT_TRUE(aof.setParam("cny", 0));
  EXPECT_TRUE(aof.setParam("cnh", 270));
  EXPECT_TRUE(aof.setParam("cnv", 2));
  EXPECT_TRUE(aof.setParam("collision_distance", 10));
  EXPECT_TRUE(aof.setParam("all_clear_distance", 40));
  EXPECT_TRUE(aof.setParam("collision_depth", 10));
  EXPECT_TRUE(aof.setParam("tol", 60));
  EXPECT_FALSE(aof.setParam("collision_depth", -1));
  EXPECT_FALSE(aof.setParam("unknown", 1));
  ASSERT_TRUE(aof.initialize());

  IvPBox surface_head_on = courseSpeedDepthBox(90, 2, 0);
  IvPBox dive_head_on = courseSpeedDepthBox(90, 2, 10);
  IvPBox deep_head_on = courseSpeedDepthBox(90, 2, 20);
  IvPBox surface_clear = courseSpeedDepthBox(0, 2, 0);

  EXPECT_GT(aof.getROC(), 0.0);
  EXPECT_LT(aof.evalBox(&surface_head_on), aof.evalBox(&surface_clear));
  EXPECT_GT(aof.evalBox(&dive_head_on), aof.evalBox(&surface_head_on));
  EXPECT_GT(aof.evalBox(&dive_head_on), aof.evalBox(&deep_head_on));

  AOF_AvoidCollisionDepth missing_depth(makeCourseSpeedDomain());
  EXPECT_FALSE(missing_depth.initialize());
}

// Covers AOF avoid obstacle V24 behavior: evaluates heading utility against configured ObShipModel.
TEST(AOFAvoidObstacleV24Test, EvaluatesHeadingUtilityAgainstConfiguredObShipModel)
{
  AOF_AvoidObstacleV24 aof(makeCourseSpeedDomain());
  EXPECT_FALSE(aof.initialize());
  aof.setObShipModel(makeAvoidObstacleModel());
  EXPECT_FALSE(aof.setParam("unused", 1));
  EXPECT_FALSE(aof.setParam("unused", "value"));
  ASSERT_TRUE(aof.initialize());
  EXPECT_TRUE(aof.minMaxKnown());
  EXPECT_DOUBLE_EQ(aof.getKnownMin(), 0);
  EXPECT_DOUBLE_EQ(aof.getKnownMax(), 100);

  IvPBox into_obstacle = courseSpeedBox(90, 2);
  IvPBox clear_north = courseSpeedBox(0, 2);
  EXPECT_LT(aof.evalBox(&into_obstacle), aof.evalBox(&clear_north));

  ObShipModelV24 inside_model;
  inside_model.setPose(50, 0, 90, 2);
  EXPECT_EQ(inside_model.setGutPoly(string2Poly("pts={40,-10:60,-10:60,10:40,10}")), "");
  EXPECT_EQ(inside_model.setMinUtilCPA(5), "");
  EXPECT_EQ(inside_model.setMaxUtilCPA(20), "");
  EXPECT_EQ(inside_model.setAllowableTTC(20), "");
  AOF_AvoidObstacleV24 invalid(makeCourseSpeedDomain());
  invalid.setObShipModel(inside_model);
  EXPECT_FALSE(invalid.initialize());
}

// Covers AOF avoid walls behavior: penalizes candidate turns that intersect a configured wall.
TEST(AOFAvoidWallsTest, PenalizesCandidateTurnsThatIntersectAConfiguredWall)
{
  AOF_AvoidWalls aof(makeCourseSpeedDomain());
  EXPECT_FALSE(aof.setWalls({}));
  EXPECT_TRUE(aof.setWalls({makeWallAhead()}));
  configureAvoidWalls(aof);
  EXPECT_TRUE(aof.setParam("ttc_base", 10));
  EXPECT_TRUE(aof.setParam("ttc_rate", 0.1));
  EXPECT_FALSE(aof.setParam("turn_radius", 0));
  ASSERT_TRUE(aof.initialize());

  IvPBox continue_toward_wall = courseSpeedBox(90, 2);
  IvPBox hard_turn_across_wall = courseSpeedBox(0, 2);
  EXPECT_TRUE(aof.minMaxKnown());
  EXPECT_DOUBLE_EQ(aof.getKnownMin(), 0);
  EXPECT_DOUBLE_EQ(aof.getKnownMax(), 100);
  EXPECT_LT(aof.evalBox(&continue_toward_wall), aof.getKnownMax());
  EXPECT_LT(aof.evalBox(&hard_turn_across_wall),
            aof.evalBox(&continue_toward_wall));

  AOF_AvoidWalls invalid(makeCourseSpeedDomain());
  invalid.setWalls({makeWallAhead()});
  invalid.setParam("osx", 0);
  invalid.setParam("osy", 0);
  invalid.setParam("osh", 90);
  invalid.setParam("turn_radius", 10);
  invalid.setParam("nogo_ttcpa", 20);
  invalid.setParam("safe_ttcpa", 20);
  invalid.setParam("collision_distance", 5);
  invalid.setParam("all_clear_distance", 20);
  invalid.setParam("tol", 60);
  EXPECT_FALSE(invalid.initialize());
}

// Covers AOF avoid walls behavior: rejects invalid domains distances and crossing walls.
TEST(AOFAvoidWallsTest, RejectsInvalidDomainsDistancesAndCrossingWalls)
{
  AOF_AvoidWalls missing_course(makeSpeedOnlyDomain());
  missing_course.setWalls({makeWallAhead()});
  configureAvoidWalls(missing_course);
  EXPECT_FALSE(missing_course.initialize());

  AOF_AvoidWalls invalid_distances(makeCourseSpeedDomain());
  invalid_distances.setWalls({makeWallAhead()});
  configureAvoidWalls(invalid_distances);
  EXPECT_TRUE(invalid_distances.setParam("collision_distance", 30));
  EXPECT_FALSE(invalid_distances.initialize());

  AOF_AvoidWalls crossing_wall(makeCourseSpeedDomain());
  EXPECT_TRUE(crossing_wall.setWalls({makeCrossingWall()}));
  configureAvoidWalls(crossing_wall);
  EXPECT_FALSE(crossing_wall.initialize());
}

// Covers AOF cut range CPA behavior: balances range closure CPA and low speed discouragement.
TEST(AOFCutRangeCPATest, BalancesRangeClosureCPAAndLowSpeedDiscouragement)
{
  AOF_CutRangeCPA aof(makeCourseSpeedDomain());
  configureLatLonContactAOF(aof);
  EXPECT_TRUE(aof.setParam("patience", 80));
  EXPECT_FALSE(aof.setParam("patience", 120));
  EXPECT_TRUE(aof.setParam("min_util_cpa_dist", 10));
  EXPECT_TRUE(aof.setParam("max_util_cpa_dist", 50));
  ASSERT_TRUE(aof.initialize());

  IvPBox chase = courseSpeedBox(90, 5);
  IvPBox away = courseSpeedBox(270, 5);
  IvPBox stopped = courseSpeedBox(90, 0);
  EXPECT_GT(aof.evalBox(&chase), aof.evalBox(&away));

  aof.discourageLowSpeeds(0, 7);
  EXPECT_NEAR(aof.evalBox(&stopped), 7.0, kGeomTol);
  aof.okLowSpeeds();
  EXPECT_NE(aof.evalBox(&stopped), 7.0);
}

// Covers AOF cut range CPA behavior: time on leg changes the projected CPA
// utility for an otherwise identical closing maneuver.
TEST(AOFCutRangeCPATest, TimeOnLegChangesProjectedCPAUtility)
{
  AOF_CutRangeCPA short_horizon(makeCourseSpeedDomain());
  configureLatLonContactAOF(short_horizon);
  EXPECT_TRUE(short_horizon.setParam("tol", 5));
  EXPECT_TRUE(short_horizon.setParam("patience", 100));
  ASSERT_TRUE(short_horizon.initialize());

  AOF_CutRangeCPA long_horizon(makeCourseSpeedDomain());
  configureLatLonContactAOF(long_horizon);
  EXPECT_TRUE(long_horizon.setParam("tol", 45));
  EXPECT_TRUE(long_horizon.setParam("patience", 100));
  ASSERT_TRUE(long_horizon.initialize());

  IvPBox closing = courseSpeedBox(90, 5);
  EXPECT_GT(long_horizon.evalBox(&closing),
            short_horizon.evalBox(&closing));
}

// Covers AOF cut range CPA behavior: patience changes the blend between rate
// of closure and projected CPA utility at fixed geometry.
TEST(AOFCutRangeCPATest, PatienceChangesROCCPABlend)
{
  AOF_CutRangeCPA low_patience(makeCourseSpeedDomain());
  configureLatLonContactAOF(low_patience);
  EXPECT_TRUE(low_patience.setParam("patience", 5));
  ASSERT_TRUE(low_patience.initialize());

  AOF_CutRangeCPA high_patience(makeCourseSpeedDomain());
  configureLatLonContactAOF(high_patience);
  EXPECT_TRUE(high_patience.setParam("patience", 100));
  ASSERT_TRUE(high_patience.initialize());

  double max_difference = 0;
  for(unsigned int course = 0; course < 360; ++course) {
    for(unsigned int speed = 0; speed < 6; ++speed) {
      IvPBox sample = courseSpeedBox(course, speed);
      max_difference = std::max(
        max_difference,
        std::fabs(low_patience.evalBox(&sample) -
                  high_patience.evalBox(&sample)));
    }
  }
  EXPECT_GT(max_difference, 1.0);
}

// Covers AOF cut range CPA behavior: rejects degenerate contact geometry and time on leg.
TEST(AOFCutRangeCPATest, RejectsDegenerateContactGeometryAndTimeOnLeg)
{
  AOF_CutRangeCPA zero_tol(makeCourseSpeedDomain());
  configureLatLonContactAOF(zero_tol);
  EXPECT_TRUE(zero_tol.setParam("tol", 0));
  EXPECT_FALSE(zero_tol.initialize());

  AOF_CutRangeCPA same_position(makeCourseSpeedDomain());
  EXPECT_TRUE(same_position.setParam("oslon", 0));
  EXPECT_TRUE(same_position.setParam("oslat", 0));
  EXPECT_TRUE(same_position.setParam("cnlon", 0));
  EXPECT_TRUE(same_position.setParam("cnlat", 0));
  EXPECT_TRUE(same_position.setParam("cncrs", 90));
  EXPECT_TRUE(same_position.setParam("cnspd", 1));
  EXPECT_TRUE(same_position.setParam("tol", 60));
  EXPECT_FALSE(same_position.initialize());

  AOF_CutRangeCPA missing_domain(makeSpeedOnlyDomain());
  configureLatLonContactAOF(missing_domain);
  EXPECT_FALSE(missing_domain.initialize());
}

// Covers AOF attractor CPA behavior: rewards candidate maneuvers that close to target CPA.
TEST(AOFAttractorCPATest, RewardsCandidateManeuversThatCloseToTargetCPA)
{
  AOF_AttractorCPA aof(makeCourseSpeedDomain());
  configureAttractorAOF(aof);
  EXPECT_TRUE(aof.setParam("patience", 100));
  ASSERT_TRUE(aof.initialize());

  IvPBox toward = courseSpeedBox(90, 5);
  IvPBox away = courseSpeedBox(270, 5);
  EXPECT_GT(aof.evalBox(&toward), aof.evalBox(&away));

  AOF_AttractorCPA invalid(makeCourseSpeedDomain());
  configureAttractorAOF(invalid);
  EXPECT_TRUE(invalid.setParam("min_util_cpa_dist", 10));
  EXPECT_TRUE(invalid.setParam("max_util_cpa_dist", 20));
  EXPECT_FALSE(invalid.initialize());
}

// Covers AOF attractor CPA behavior: rejects missing CPA parameters and invalid patience.
TEST(AOFAttractorCPATest, RejectsMissingCPAParametersAndInvalidPatience)
{
  AOF_AttractorCPA missing_cpa_window(makeCourseSpeedDomain());
  EXPECT_TRUE(missing_cpa_window.setParam("oslon", 0));
  EXPECT_TRUE(missing_cpa_window.setParam("oslat", 0));
  EXPECT_TRUE(missing_cpa_window.setParam("cnlon", 100));
  EXPECT_TRUE(missing_cpa_window.setParam("cnlat", 0));
  EXPECT_TRUE(missing_cpa_window.setParam("cncrs", 90));
  EXPECT_TRUE(missing_cpa_window.setParam("cnspd", 1));
  EXPECT_TRUE(missing_cpa_window.setParam("tol", 60));
  EXPECT_FALSE(missing_cpa_window.initialize());

  AOF_AttractorCPA invalid_tol(makeCourseSpeedDomain());
  configureAttractorAOF(invalid_tol);
  EXPECT_TRUE(invalid_tol.setParam("tol", 0));
  EXPECT_FALSE(invalid_tol.initialize());
  EXPECT_FALSE(invalid_tol.setParam("patience", -1));
  EXPECT_FALSE(invalid_tol.setParam("patience", 101));
}

// Covers AOF shadow behavior: matches contact course and speed for shadowing.
TEST(AOFShadowTest, MatchesContactCourseAndSpeedForShadowing)
{
  AOF_Shadow aof(makeCourseSpeedDomain());
  EXPECT_FALSE(aof.initialize());
  EXPECT_TRUE(aof.setParam("cn_crs", 90));
  EXPECT_TRUE(aof.setParam("cn_spd", 2));
  EXPECT_FALSE(aof.setParam("unknown", 1));
  ASSERT_TRUE(aof.initialize());

  IvPBox match = courseSpeedBox(90, 2);
  IvPBox wrong_course = courseSpeedBox(270, 2);
  IvPBox wrong_speed = courseSpeedBox(90, 5);

  EXPECT_NEAR(aof.evalBox(&match), 100.0, kGeomTol);
  EXPECT_LT(aof.evalBox(&wrong_course), aof.evalBox(&match));
  EXPECT_LT(aof.evalBox(&wrong_speed), aof.evalBox(&match));
  EXPECT_NEAR(aof.metric(0, 0), 100.0, kGeomTol);
  EXPECT_LT(aof.metric(180, 12), 10.0);
}

// Covers AOF shadow behavior: rejects missing domain variables and contact motion.
TEST(AOFShadowTest, RejectsMissingDomainVariablesAndContactMotion)
{
  AOF_Shadow missing_course(makeSpeedOnlyDomain());
  EXPECT_TRUE(missing_course.setParam("cn_crs", 90));
  EXPECT_TRUE(missing_course.setParam("cn_spd", 2));
  EXPECT_FALSE(missing_course.initialize());

  AOF_Shadow missing_speed(makeCourseSpeedDomain());
  EXPECT_TRUE(missing_speed.setParam("cn_crs", 90));
  EXPECT_FALSE(missing_speed.initialize());
}
