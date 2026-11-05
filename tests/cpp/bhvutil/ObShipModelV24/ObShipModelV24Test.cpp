#include <gtest/gtest.h>

#include "NumericAssertions.h"
#include "ObShipModelV24.h"
#include "XYFormatUtilsPoly.h"
#include "XYPolygon.h"

namespace {

XYPolygon obstacleAhead()
{
  XYPolygon poly = string2Poly("pts={40,-10:60,-10:60,10:40,10},label=ob_0,vsource=sim");
  EXPECT_TRUE(poly.is_convex());
  return poly;
}

}  // namespace

TEST(ObShipSpeedRegulationTest, ClampsDiscountOutsideSpeedBandAndHonorsDisable)
{
  ObShipModelV24 model;
  ASSERT_TRUE(model.setSpdRegulation(1, 5, 75));
  model.enableSpdRegulation(true);
  ASSERT_TRUE(model.isSpdRegulated());
  EXPECT_DOUBLE_EQ(model.spdRegulate(0), 0.25);
  EXPECT_DOUBLE_EQ(model.spdRegulate(1), 0.25);
  EXPECT_DOUBLE_EQ(model.spdRegulate(3), 0.625);
  EXPECT_DOUBLE_EQ(model.spdRegulate(5), 1);
  EXPECT_DOUBLE_EQ(model.spdRegulate(50), 1);
  EXPECT_FALSE(model.setSpdRegulation(5, 1, 75));
  EXPECT_DOUBLE_EQ(model.spdRegulate(0), 0.25);
  model.enableSpdRegulation(false);
  EXPECT_DOUBLE_EQ(model.spdRegulate(0), 1);
}

// Covers ObShipModel V24 behavior: stores pose utility and distance configuration with clamps.
TEST(ObShipModelV24Test, StoresPoseUtilityAndDistanceConfigurationWithClamps)
{
  ObShipModelV24 model;
  EXPECT_TRUE(model.setPose(0, 0, 90, 2));
  EXPECT_DOUBLE_EQ(model.getOSX(), 0);
  EXPECT_DOUBLE_EQ(model.getOSY(), 0);
  EXPECT_DOUBLE_EQ(model.getOSH(), 90);
  EXPECT_DOUBLE_EQ(model.getOSV(), 2);
  EXPECT_TRUE(model.paramIsSet("osx"));

  model.setMinMaxUtil(20, 80);
  model.setMinUtil(-5);
  model.setMaxUtil(10);
  model.setOBuffRDegs(0);
  EXPECT_DOUBLE_EQ(model.getOBuffRDegs(), 1);
  model.setOBuffRDegs(90);
  EXPECT_DOUBLE_EQ(model.getOBuffRDegs(), 45);

  EXPECT_EQ(model.setPwtInnerDist(12), "");
  EXPECT_EQ(model.setPwtOuterDist(40), "");
  EXPECT_EQ(model.setCompletedDist(70), "");
  EXPECT_DOUBLE_EQ(model.getPwtInnerDist(), 12);
  EXPECT_DOUBLE_EQ(model.getPwtOuterDist(), 40);
  EXPECT_DOUBLE_EQ(model.getCompletedDist(), 70);
}

// Covers ObShipModel V24 behavior: reports configuration conflicts and adjusts dependent distances.
TEST(ObShipModelV24Test, ReportsConfigurationConflictsAndAdjustsDependentDistances)
{
  ObShipModelV24 model;

  EXPECT_EQ(model.setPwtOuterDist(20), "");
  EXPECT_EQ(model.setPwtInnerDist(30), "pwt_inner_dist must be <= pwt_outer_dist");
  EXPECT_DOUBLE_EQ(model.getPwtOuterDist(), 30);

  EXPECT_EQ(model.setCompletedDist(25), "completed_dist must be >= pwt_inner_dist");
  EXPECT_DOUBLE_EQ(model.getPwtInnerDist(), 25);
  EXPECT_DOUBLE_EQ(model.getPwtOuterDist(), 30);

  EXPECT_EQ(model.setMinUtilCPA(15), "");
  EXPECT_EQ(model.setMaxUtilCPA(10), "max_util_cpa must be >= min_util_cpa");
  EXPECT_DOUBLE_EQ(model.getMinUtilCPA(), 10);
  EXPECT_DOUBLE_EQ(model.getMaxUtilCPA(), 10);

  EXPECT_EQ(model.setAllowableTTC(-1), "allowable_ttc cannot be a negative number");
}

// Covers ObShipModel V24 behavior: rejects negative distance and CPA limits without changing state.
TEST(ObShipModelV24Test, RejectsNegativeDistanceAndCpaLimitsWithoutChangingState)
{
  ObShipModelV24 model;
  ASSERT_EQ(model.setPwtInnerDist(12), "");
  ASSERT_EQ(model.setPwtOuterDist(40), "");
  ASSERT_EQ(model.setCompletedDist(70), "");
  ASSERT_EQ(model.setMinUtilCPA(5), "");
  ASSERT_EQ(model.setMaxUtilCPA(25), "");

  EXPECT_EQ(model.setPwtInnerDist(-1), "pwt_inner_dist must be a positive number");
  EXPECT_EQ(model.setPwtOuterDist(-1), "pwt_outer_dist must be a positive number");
  EXPECT_EQ(model.setCompletedDist(-1), "completed_dist must be a positive number");
  EXPECT_EQ(model.setMinUtilCPA(-1), "min_util_cpa cannot be a negative number");
  EXPECT_EQ(model.setMaxUtilCPA(-1), "max_util_cpa cannot be a negative number");
  EXPECT_EQ(model.setAllowableTTC(-1), "allowable_ttc cannot be a negative number");

  EXPECT_DOUBLE_EQ(model.getPwtInnerDist(), 12);
  EXPECT_DOUBLE_EQ(model.getPwtOuterDist(), 40);
  EXPECT_DOUBLE_EQ(model.getCompletedDist(), 70);
  EXPECT_DOUBLE_EQ(model.getMinUtilCPA(), 5);
  EXPECT_DOUBLE_EQ(model.getMaxUtilCPA(), 25);
}

// Covers ObShipModel V24 behavior: rejects non convex obstacle and caches derived obstacle geometry.
TEST(ObShipModelV24Test, RejectsNonConvexObstacleAndCachesDerivedObstacleGeometry)
{
  ObShipModelV24 model;
  model.setPose(0, 0, 90, 2);
  EXPECT_EQ(model.setGutPoly("pts={0,0:10,10:0,10:10,0}"), "obstacle is not convex");

  ASSERT_EQ(model.setGutPoly(obstacleAhead()), "");
  EXPECT_TRUE(model.paramIsSet("gut_poly"));
  model.setCachedVals(true);

  EXPECT_TRUE(model.isValid());
  EXPECT_EQ(model.getObstacleLabel(), "ob_0");
  EXPECT_EQ(model.getVSource(), "sim");
  EXPECT_NEAR(model.getObcentX(), 50.0, kGeomTol);
  EXPECT_NEAR(model.getObcentY(), 0.0, kGeomTol);
  EXPECT_NEAR(model.getRange(), 40.0, kGeomTol);
  EXPECT_NEAR(model.getRangeInOSH(), 40.0, kGeomTol);
  EXPECT_NEAR(model.getObcentBng(), 90.0, kGeomTol);
  EXPECT_NEAR(model.getObcentRelBng(), 0.0, kGeomTol);
  EXPECT_EQ(model.getPassingSide(), "n/a");
  EXPECT_TRUE(model.getMidPoly().contains(model.getGutPoly()));
  EXPECT_TRUE(model.getRimPoly().contains(model.getMidPoly()));
  EXPECT_EQ(model.getFailedExpandPolyStr(false), "");
  EXPECT_EQ(model.getFailedExpandPolyStr(true), "");
}

// Covers ObShipModel V24 behavior: computes range relevance and aft classification.
TEST(ObShipModelV24Test, ComputesRangeRelevanceAndAftClassification)
{
  ObShipModelV24 model;
  model.setPose(0, 0, 90, 2);
  model.setPwtInnerDist(10);
  model.setPwtOuterDist(100);
  ASSERT_EQ(model.setGutPoly(obstacleAhead()), "");
  model.setCachedVals(true);

  double relevance = model.getRangeRelevance();
  EXPECT_GT(relevance, 0.0);
  EXPECT_LT(relevance, 1.0);
  EXPECT_FALSE(model.isObstacleAft());

  ObShipModelV24 aft_model;
  aft_model.setPose(100, 0, 90, 2);
  ASSERT_EQ(aft_model.setGutPoly(obstacleAhead()), "");
  aft_model.setCachedVals(true);
  EXPECT_TRUE(aft_model.isObstacleAft());
}

// Covers ObShipModel V24 behavior: classifies ownship containment for gut and adjusted buffer polygons.
TEST(ObShipModelV24Test, ClassifiesOwnshipContainmentForGutAndAdjustedBufferPolygons)
{
  ObShipModelV24 gut_model;
  gut_model.setPose(50, 0, 90, 2);
  ASSERT_EQ(gut_model.setGutPoly(obstacleAhead()), "");
  gut_model.setCachedVals(true);
  EXPECT_TRUE(gut_model.ownshipInGutPoly());
  EXPECT_TRUE(gut_model.ownshipInMidPoly());
  EXPECT_TRUE(gut_model.ownshipInRimPoly());

  ObShipModelV24 clear_model;
  clear_model.setPose(35, 0, 90, 2);
  ASSERT_EQ(clear_model.setGutPoly(obstacleAhead()), "");
  clear_model.setCachedVals(true);
  EXPECT_FALSE(clear_model.ownshipInGutPoly());
  EXPECT_FALSE(clear_model.ownshipInMidPoly());
  EXPECT_FALSE(clear_model.ownshipInRimPoly());
}

// Covers ObShipModel V24 behavior: evaluates headings against obstacle CPA bands.
TEST(ObShipModelV24Test, EvaluatesHeadingsAgainstObstacleCpaBands)
{
  ObShipModelV24 model;
  model.setPose(0, 0, 90, 2);
  model.setMinMaxUtil(0, 100);
  ASSERT_EQ(model.setMinUtilCPA(5), "");
  ASSERT_EQ(model.setMaxUtilCPA(20), "");
  ASSERT_EQ(model.setGutPoly(obstacleAhead()), "");
  model.setCachedVals(true);

  double ix = 0;
  double iy = 0;
  EXPECT_NEAR(model.rayCPA(90, ix, iy), 0.0, kGeomTol);
  EXPECT_GT(model.rayCPA(0, ix, iy), 30.0);

  double stem_dist = -1;
  EXPECT_NEAR(model.seglrCPA(90, ix, iy, stem_dist), 0.0, kGeomTol);
  EXPECT_GT(stem_dist, 0.0);

  EXPECT_NEAR(model.evalHdgSpd(90, 2), 0.0, kGeomTol);
  EXPECT_GT(model.evalHdgSpd(0, 2), 90.0);
}

// Covers ObShipModel V24 behavior: computes bearing extremes used by obstacle refineries.
TEST(ObShipModelV24Test, ComputesBearingExtremesUsedByObstacleRefineries)
{
  ObShipModelV24 model;
  model.setPose(0, 0, 90, 2);
  ASSERT_EQ(model.setGutPoly(obstacleAhead()), "");
  model.setCachedVals(true);

  model.updateBngExtremes();

  EXPECT_GT(model.getGutBngHitCount(), 0u);
  EXPECT_GT(model.getGutBngUnhitCount(), 0u);
  EXPECT_GT(model.getRimBngHitCount(), 0u);
  EXPECT_GT(model.getRimBngUnhitCount(), 0u);
  EXPECT_GE(model.getGutBngMinToPoly(), 0.0);
  EXPECT_LT(model.getGutBngMinToPoly(), 360.0);
  EXPECT_GE(model.getGutBngMaxToPoly(), 0.0);
  EXPECT_LT(model.getGutBngMaxToPoly(), 360.0);
  EXPECT_GE(model.getRimBngMinToPoly(), 0.0);
  EXPECT_LT(model.getRimBngMinToPoly(), 360.0);
  EXPECT_GE(model.getRimBngMaxToPoly(), 0.0);
  EXPECT_LT(model.getRimBngMaxToPoly(), 360.0);
  EXPECT_GE(model.getGutBngMinDistToPoly(), 0.0);
  EXPECT_GE(model.getRimBngMinDistToPoly(), 0.0);
}

// Covers ObShipModel V24 behavior: turn cache can be disabled without changing evaluation results.
TEST(ObShipModelV24Test, TurnCacheCanBeDisabledWithoutChangingEvaluationResults)
{
  ObShipModelV24 model;
  model.setPose(0, 0, 90, 2);
  model.setMinMaxUtil(0, 100);
  ASSERT_EQ(model.setGutPoly(obstacleAhead()), "");
  model.setCachedVals(true);

  const double cached_eval = model.evalHdgSpd(0, 2);
  EXPECT_TRUE(model.isTurnCacheEnabled());
  model.useTurnCache(false);
  EXPECT_FALSE(model.isTurnCacheEnabled());
  EXPECT_NEAR(model.evalHdgSpd(0, 2), cached_eval, kGeomTol);
}
