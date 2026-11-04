#include <cmath>
#include <string>
#include <vector>

#include <gtest/gtest.h>

#include "BNGEngine.h"
#include "CPA_Utils.h"
#include "GeomUtils.h"
#include "GeometryTestUtils.h"
#include "NumericAssertions.h"
#include "PlatModel.h"

namespace {

XYSeglr makeSeglr(double x0, double y0, double x1, double y1,
                  double ray_angle)
{
  XYSeglr seglr(x0, y0, x1, y1);
  seglr.setRayAngle(ray_angle);
  return seglr;
}

void expectPointNear(const XYPoint& point, double x, double y)
{
  ASSERT_TRUE(point.valid());
  EXPECT_NEAR(point.x(), x, kGeomTol);
  EXPECT_NEAR(point.y(), y, kGeomTol);
}

}  // namespace

// Covers bng engine behavior: default engine returns zero for bearing and rate.
TEST(BNGEngineTest, DefaultEngineReturnsZeroForBearingAndRate)
{
  BNGEngine engine;

  EXPECT_NEAR(engine.evalBNG(0, 0), 0.0, kGeomTol);
  EXPECT_NEAR(engine.evalBNG(45, 2.5), 0.0, kGeomTol);
  EXPECT_NEAR(engine.evalBNGRate(0, 0), 0.0, kGeomTol);
  EXPECT_NEAR(engine.evalBNGRate(270, 4), 0.0, kGeomTol);
}

// Covers bng engine behavior: configured engine currently ignores encounter geometry.
TEST(BNGEngineTest, ConfiguredEngineCurrentlyIgnoresEncounterGeometry)
{
  BNGEngine crossing(100, 50, 270, 3, -20, 10);
  BNGEngine head_on(0, 100, 180, 2, 0, 0);

  // BNGEngine is presently a stub: all evaluated bearings/rates are zero.
  EXPECT_NEAR(crossing.evalBNG(90, 4), 0.0, kGeomTol);
  EXPECT_NEAR(crossing.evalBNGRate(90, 4), 0.0, kGeomTol);
  EXPECT_NEAR(head_on.evalBNG(0, 2), 0.0, kGeomTol);
  EXPECT_NEAR(head_on.evalBNGRate(0, 2), 0.0, kGeomTol);
}

// Covers CPA utils eval CPA behavior: computes head on collision and clips to time on leg.
TEST(CPAUtilsEvalCPATest, ComputesHeadOnCollisionAndClipsToTimeOnLeg)
{
  EXPECT_NEAR(evalCPA(0, 100, 2, 180, 0, 0, 2, 0, 120), 0.0,
              kGeomTol);
  EXPECT_NEAR(evalCPA(0, 100, 2, 180, 0, 0, 2, 0, -1), 0.0,
              kGeomTol);

  EXPECT_NEAR(evalCPA(0, 100, 2, 180, 0, 0, 2, 0, 10), 60.0,
              kGeomTol);
}

// Covers CPA utils eval CPA behavior: minus one time on leg is unlimited sentinel.
TEST(CPAUtilsEvalCPATest, MinusOneTimeOnLegIsUnlimitedSentinel)
{
  EXPECT_NEAR(evalCPA(0, 100, 2, 180, 0, 0, 2, 0, -1), 0.0,
              kGeomTol);
  EXPECT_NEAR(evalCPA(0, 100, 2, 180, 0, 0, 2, 0, 0), 100.0,
              kGeomTol);
  EXPECT_NEAR(evalCPA(0, 100, 2, 180, 0, 0, 2, 0, -0.5), 102.0,
              kGeomTol);
}

// Covers CPA utils eval CPA behavior: handles parallel and opening encounters.
TEST(CPAUtilsEvalCPATest, HandlesParallelAndOpeningEncounters)
{
  EXPECT_NEAR(evalCPA(0, 100, 2, 0, 0, 0, 2, 0, 120), 100.0,
              kGeomTol);
  EXPECT_NEAR(evalCPA(0, 100, 1, 0, 0, 0, 1, 180, 120), 100.0,
              kGeomTol);
}

// Covers CPA utils eval CPA behavior: handles crossing contact avoidance geometry.
TEST(CPAUtilsEvalCPATest, HandlesCrossingContactAvoidanceGeometry)
{
  EXPECT_NEAR(evalCPA(100, 100, 2, 270, 0, 0, 2, 0, 120), 0.0,
              kLooseGeomTol);
  EXPECT_NEAR(evalCPA(100, 100, 2, 270, 0, 0, 2, 0, 20), 84.8528137424,
              kLooseGeomTol);
}

// Covers CPA utils crosses bow behavior: detects ownship arriving at intersection first.
TEST(CPAUtilsCrossesBowTest, DetectsOwnshipArrivingAtIntersectionFirst)
{
  EXPECT_TRUE(crossesBow(-20, 0, 1, 90, -10, -10, 2, 0));
  EXPECT_FALSE(crossesBow(-20, 0, 1, 90, -10, -10, 2, 0, 4));
  EXPECT_FALSE(crossesBow(-20, 0, 1, 90, -10, -10, 0.5, 0));
}

// Covers CPA utils crosses bow behavior: rejects parallel or diverging tracks.
TEST(CPAUtilsCrossesBowTest, RejectsParallelOrDivergingTracks)
{
  EXPECT_FALSE(crossesBow(0, 0, 1, 0, 10, 0, 1, 0));
  EXPECT_FALSE(crossesBow(0, 0, 1, 90, -10, -10, 2, 0));
}

// Covers CPA utils crosses bow behavior: pins zero contact speed division behavior.
TEST(CPAUtilsCrossesBowTest, PinsZeroContactSpeedDivisionBehavior)
{
  EXPECT_TRUE(crossesBow(0, 0, 0, 0, -10, -10, 2, 45));
  EXPECT_FALSE(crossesBow(0, 0, 1, 0, -10, -10, 0, 45));
}

// Covers CPA utils closing speed behavior: computes closing rate against stationary point.
TEST(CPAUtilsClosingSpeedTest, ComputesClosingRateAgainstStationaryPoint)
{
  EXPECT_NEAR(closingSpeed(0, 0, 2, 0, 0, 10), 2.0, kGeomTol);
  EXPECT_NEAR(closingSpeed(0, 0, 2, 180, 0, 10), -2.0, kGeomTol);
  EXPECT_NEAR(closingSpeed(0, 0, 2, 90, 0, 10), 0.0, kLooseGeomTol);
  EXPECT_NEAR(closingSpeed(0, 0, 2, 45, 0, 0), 0.0, kGeomTol);
}

// Covers CPA utils closing speed behavior: computes relative closing rate for moving contact.
TEST(CPAUtilsClosingSpeedTest, ComputesRelativeClosingRateForMovingContact)
{
  EXPECT_NEAR(closingSpeed(0, 0, 2, 0, 0, 10, 3, 180), 5.0,
              kGeomTol);
  EXPECT_NEAR(closingSpeed(0, 0, 3, 0, 0, 10, 1, 0), 2.0,
              kGeomTol);
  EXPECT_NEAR(closingSpeed(0, 0, 1, 0, 0, 10, 3, 0), -2.0,
              kGeomTol);
  EXPECT_NEAR(closingSpeed(0, 0, -2, 0, 0, 10, 0, 0), -2.0,
              kGeomTol);
  EXPECT_NEAR(closingSpeed(0, 0, 5, 123, 0, 0, 2, 45), 0.0,
              kGeomTol);
}

// Covers CPA utils velocity vector sum behavior: sums orthogonal and opposing velocity vectors.
TEST(CPAUtilsVelocityVectorSumTest, SumsOrthogonalAndOpposingVelocityVectors)
{
  double hdg = -1;
  double spd = -1;

  velocityVectorSum(0, 2, 90, 2, hdg, spd);
  EXPECT_NEAR(hdg, 45.0, kGeomTol);
  EXPECT_NEAR(spd, std::sqrt(8.0), kGeomTol);

  velocityVectorSum(0, 2, 180, 2, hdg, spd);
  // The opposing vectors leave a tiny floating-point x component, so the
  // current implementation reports an eastward heading instead of using the
  // exact zero-speed heading fallback.
  EXPECT_NEAR(hdg, 90.0, kGeomTol);
  EXPECT_NEAR(spd, 0.0, kGeomTol);
}

// Covers CPA utils velocity vector sum behavior: handles unequal opposing vectors.
TEST(CPAUtilsVelocityVectorSumTest, HandlesUnequalOpposingVectors)
{
  double hdg = -1;
  double spd = -1;

  velocityVectorSum(0, 5, 180, 2, hdg, spd);
  EXPECT_NEAR(hdg, 0.0, kGeomTol);
  EXPECT_NEAR(spd, 3.0, kGeomTol);

  velocityVectorSum(90, 1, 270, 4, hdg, spd);
  EXPECT_NEAR(hdg, 270.0, kGeomTol);
  EXPECT_NEAR(spd, 3.0, kGeomTol);
}

// Covers CPA utils rel ang rate behavior: computes signed bearing rate with wraparound.
TEST(CPAUtilsRelAngRateTest, ComputesSignedBearingRateWithWraparound)
{
  double x_350 = 0;
  double y_350 = 0;
  double x_010 = 0;
  double y_010 = 0;
  projectPoint(350, 10, 0, 0, x_350, y_350);
  projectPoint(10, 10, 0, 0, x_010, y_010);

  EXPECT_NEAR(relAngRate(0, 0, x_350, y_350, 0, 0, x_010, y_010, 5),
              4.0, kGeomTol);
  EXPECT_NEAR(relAngRate(0, 0, x_010, y_010, 0, 0, x_350, y_350, 5),
              -4.0, kGeomTol);
}

// Covers CPA utils rel ang rate behavior: pins zero time and one eighty degree tie behavior.
TEST(CPAUtilsRelAngRateTest, PinsZeroTimeAndOneEightyDegreeTieBehavior)
{
  EXPECT_NEAR(relAngRate(0, 0, 0, 10, 0, 0, 10, 0, 0), 0.0, kGeomTol);

  // A 180-degree change is kept positive by the current wrap logic.
  EXPECT_NEAR(relAngRate(0, 0, 0, 10, 0, 0, 0, -10, 10), 18.0,
              kGeomTol);
}

// Covers plat model pose behavior: default model is invalid until all pose fields are set.
TEST(PlatModelPoseTest, DefaultModelIsInvalidUntilAllPoseFieldsAreSet)
{
  PlatModel model("holo");

  model.setID(42);
  model.setModelType("holo");
  EXPECT_FALSE(model.valid());
  EXPECT_TRUE(model.isHolonomic());
  EXPECT_EQ(model.getModelType(), "holo");
  EXPECT_EQ(model.getID(), 42u);

  model.setOSX(1.5);
  model.setOSY(-2.5);
  model.setOSH(725);
  EXPECT_FALSE(model.valid());
  model.setOSV(3.25);
  EXPECT_TRUE(model.valid());

  model.setPose(1.5, -2.5, 725, 3.25);
  EXPECT_TRUE(model.valid());
  EXPECT_NEAR(model.getOSX(), 1.5, kGeomTol);
  EXPECT_NEAR(model.getOSY(), -2.5, kGeomTol);
  EXPECT_NEAR(model.getOSH(), 5.0, kGeomTol);
  EXPECT_NEAR(model.getOSV(), 3.25, kGeomTol);

  testing::internal::CaptureStdout();
  model.print();
  std::string out = testing::internal::GetCapturedStdout();
  EXPECT_TRUE(stringContains(out, " type: holo"));
}

// Covers plat model pose behavior: pose constructor normalizes heading and clamps speed.
TEST(PlatModelPoseTest, PoseConstructorNormalizesHeadingAndClampsSpeed)
{
  PlatModel model(12.345, -7.5, -90, -4);

  EXPECT_TRUE(model.valid());
  EXPECT_NEAR(model.getOSX(), 12.345, kGeomTol);
  EXPECT_NEAR(model.getOSY(), -7.5, kGeomTol);
  EXPECT_NEAR(model.getOSH(), 270.0, kGeomTol);
  EXPECT_NEAR(model.getOSV(), 0.0, kGeomTol);
  EXPECT_EQ(model.getSpec(), "id=0,type=,osx=12.3,osy=-7.5,osh=270,osv=0,spokes:0:0");
}

// Covers plat model parse behavior: parses compact MOOS-IvP style pose spec.
TEST(PlatModelParseTest, ParsesCompactMoosIvPStylePoseSpec)
{
  PlatModel model = stringToPlatModel("osx=1.25,osy=-2.5,osh=-90,osv=-3");

  EXPECT_TRUE(model.valid());
  EXPECT_NEAR(model.getOSX(), 1.25, kGeomTol);
  EXPECT_NEAR(model.getOSY(), -2.5, kGeomTol);
  EXPECT_NEAR(model.getOSH(), 270.0, kGeomTol);
  EXPECT_NEAR(model.getOSV(), 0.0, kGeomTol);
  EXPECT_EQ(model.getSpec(), "id=0,type=,osx=1.2,osy=-2.5,osh=270,osv=0,spokes:0:0");
}

// Covers plat model parse behavior: rejects unknown or non numeric parameters.
TEST(PlatModelParseTest, RejectsUnknownOrNonNumericParameters)
{
  EXPECT_FALSE(stringToPlatModel("osx=1,osy=2,osh=3,osv=4,color=red")
                 .valid());
  EXPECT_FALSE(stringToPlatModel("osx=1,osy=north,osh=3,osv=4").valid());
  EXPECT_FALSE(stringToPlatModel("osx=1,osy=2,osh=3").valid());
}

// Covers plat model parse behavior: duplicate pose fields are accepted with last value winning.
TEST(PlatModelParseTest, DuplicatePoseFieldsAreAcceptedWithLastValueWinning)
{
  PlatModel model = stringToPlatModel("osx=1,osy=2,osx=9,osh=450,osv=4");

  ASSERT_TRUE(model.valid());
  EXPECT_NEAR(model.getOSX(), 9.0, kGeomTol);
  EXPECT_NEAR(model.getOSY(), 2.0, kGeomTol);
  EXPECT_NEAR(model.getOSH(), 90.0, kGeomTol);
  EXPECT_NEAR(model.getOSV(), 4.0, kGeomTol);
}

// Covers plat model spoke behavior: stores port and starboard spoke points with stable labels.
TEST(PlatModelSpokeTest, StoresPortAndStarboardSpokePointsWithStableLabels)
{
  PlatModel model;

  EXPECT_TRUE(model.setPortSpokes({1, 2}, {3, 4}));
  EXPECT_TRUE(model.setStarSpokes({-1, -2}, {-3, -4}));
  EXPECT_FALSE(model.setPortSpokes({10, 20}, {30}));

  std::vector<XYPoint> port_points = model.getPoints("port_spoke");
  ASSERT_EQ(port_points.size(), 2u);
  expectPointNear(port_points[0], 1, 3);
  expectPointNear(port_points[1], 2, 4);
  EXPECT_EQ(port_points[0].get_label(), "mp_0");
  EXPECT_EQ(port_points[1].get_label(), "mp_1");

  std::vector<XYPoint> star_points = model.getPoints("star_spoke");
  ASSERT_EQ(star_points.size(), 2u);
  expectPointNear(star_points[0], -1, -3);
  expectPointNear(star_points[1], -2, -4);
  EXPECT_EQ(star_points[0].get_label(), "ms_0");
  EXPECT_EQ(star_points[1].get_label(), "ms_1");

  EXPECT_TRUE(model.getPoints("bogus_spoke").empty());
}

// Covers plat model turn seglr behavior: falls back to single ray without valid spoke cache.
TEST(PlatModelTurnSeglrTest, FallsBackToSingleRayWithoutValidSpokeCache)
{
  PlatModel model(10, 20, 0, 2);

  XYSeglr seglr = model.getTurnSeglr(45);

  EXPECT_TRUE(seglr.valid());
  EXPECT_EQ(seglr.size(), 1u);
  EXPECT_NEAR(seglr.getVX(0), 10.0, kGeomTol);
  EXPECT_NEAR(seglr.getVY(0), 20.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayBaseX(), 10.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayBaseY(), 20.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayAngle(), 45.0, kGeomTol);
}

// Covers plat model turn seglr behavior: selects cached port or starboard turn by heading.
TEST(PlatModelTurnSeglrTest, SelectsCachedPortOrStarboardTurnByHeading)
{
  PlatModel model(0, 0, 0, 2);
  model.setSpokeDegs(45);
  ASSERT_TRUE(model.setStarSpokes({0, 10, 20}, {0, 1, 2}));
  ASSERT_TRUE(model.setPortSpokes({0, -10, -20}, {0, -1, -2}));
  model.setStarSeglrs({makeSeglr(100, 0, 101, 0, 0),
                       makeSeglr(110, 0, 111, 0, 45),
                       makeSeglr(120, 0, 121, 0, 90)});
  model.setPortSeglrs({makeSeglr(-100, 0, -101, 0, 0),
                       makeSeglr(-110, 0, -111, 0, 315),
                       makeSeglr(-120, 0, -121, 0, 270)});

  XYSeglr star_turn = model.getTurnSeglr(90);
  ASSERT_TRUE(star_turn.valid());
  EXPECT_EQ(star_turn.size(), 2u);
  EXPECT_NEAR(star_turn.getVX(0), 120.0, kGeomTol);
  EXPECT_NEAR(star_turn.getRayAngle(), 90.0, kGeomTol);

  XYSeglr port_turn = model.getTurnSeglr(315);
  ASSERT_TRUE(port_turn.valid());
  EXPECT_EQ(port_turn.size(), 2u);
  EXPECT_NEAR(port_turn.getVX(0), -110.0, kGeomTol);
  EXPECT_NEAR(port_turn.getRayAngle(), 315.0, kGeomTol);
}

// Covers plat model turn seglr behavior: clamps turn cache index at largest available spoke.
TEST(PlatModelTurnSeglrTest, ClampsTurnCacheIndexAtLargestAvailableSpoke)
{
  PlatModel model(0, 0, 0, 2);
  model.setSpokeDegs(30);
  ASSERT_TRUE(model.setStarSpokes({0, 1}, {0, 1}));
  ASSERT_TRUE(model.setPortSpokes({0, -1}, {0, -1}));
  model.setStarSeglrs({makeSeglr(10, 0, 11, 0, 0),
                       makeSeglr(20, 0, 21, 0, 30)});
  model.setPortSeglrs({makeSeglr(-10, 0, -11, 0, 0),
                       makeSeglr(-20, 0, -21, 0, 330)});

  XYSeglr star_turn = model.getTurnSeglr(170);
  EXPECT_NEAR(star_turn.getVX(0), 20.0, kGeomTol);
  EXPECT_NEAR(star_turn.getRayAngle(), 170.0, kGeomTol);

  XYSeglr port_turn = model.getTurnSeglr(190);
  EXPECT_NEAR(port_turn.getVX(0), -20.0, kGeomTol);
  EXPECT_NEAR(port_turn.getRayAngle(), 190.0, kGeomTol);
}

// Covers plat model cache behavior: exposes cached CPA distance stem distance and point.
TEST(PlatModelCacheTest, ExposesCachedCpaDistanceStemDistanceAndPoint)
{
  PlatModel model(0, 0, 0, 2);
  model.setSpokeDegs(45);
  ASSERT_TRUE(model.setStarSpokes({0, 10, 20}, {0, 1, 2}));
  ASSERT_TRUE(model.setPortSpokes({0, -10, -20}, {0, -1, -2}));
  model.setStarSeglrs({makeSeglr(100, 0, 101, 0, 0),
                       makeSeglr(110, 0, 111, 0, 45),
                       makeSeglr(120, 0, 121, 0, 90)});
  model.setPortSeglrs({makeSeglr(-100, 0, -101, 0, 0),
                       makeSeglr(-110, 0, -111, 0, 315),
                       makeSeglr(-120, 0, -121, 0, 270)});

  model.setCacheDistCPA(true, 1, -7);
  model.setCacheStemCPA(true, 1, 12.5);
  model.setCachePtCPA(true, 1, XYPoint(4, 5));
  model.setCacheDistCPA(false, 2, 33.25);

  XYSeglr port_turn = model.getTurnSeglr(315);
  EXPECT_NEAR(port_turn.getCacheCPA(), 0.0, kGeomTol);
  EXPECT_NEAR(port_turn.getCacheStemCPA(), 12.5, kGeomTol);
  expectPointNear(port_turn.getCacheCPAPoint(), 4, 5);

  XYSeglr star_turn = model.getTurnSeglr(90);
  EXPECT_NEAR(star_turn.getCacheCPA(), 33.25, kGeomTol);
  EXPECT_NEAR(star_turn.getCacheStemCPA(), -1.0, kGeomTol);
  EXPECT_FALSE(star_turn.getCacheCPAPoint().valid());
}

// Covers plat model cache behavior: out of range port cache update falls through to starboard.
TEST(PlatModelCacheTest, OutOfRangePortCacheUpdateFallsThroughToStarboard)
{
  PlatModel model(0, 0, 0, 2);
  model.setSpokeDegs(45);
  ASSERT_TRUE(model.setStarSpokes({0, 10}, {0, 1}));
  ASSERT_TRUE(model.setPortSpokes({0}, {0}));
  model.setStarSeglrs({makeSeglr(100, 0, 101, 0, 0),
                       makeSeglr(110, 0, 111, 0, 45)});
  model.setPortSeglrs({makeSeglr(-100, 0, -101, 0, 0)});

  // Current setter logic falls through to starboard when port=true but the
  // requested port index is out of range and that index exists starboard.
  model.setCacheDistCPA(true, 1, 8.5);

  XYSeglr star_turn = model.getTurnSeglr(45);
  EXPECT_NEAR(star_turn.getCacheCPA(), 8.5, kGeomTol);
}

// Covers plat model cache behavior: out of range port point and stem updates fall through to starboard.
TEST(PlatModelCacheTest, OutOfRangePortPointAndStemUpdatesFallThroughToStarboard)
{
  PlatModel model(0, 0, 0, 2);
  model.setSpokeDegs(45);
  ASSERT_TRUE(model.setStarSpokes({0, 10}, {0, 1}));
  ASSERT_TRUE(model.setPortSpokes({0}, {0}));
  model.setStarSeglrs({makeSeglr(100, 0, 101, 0, 0),
                       makeSeglr(110, 0, 111, 0, 45)});
  model.setPortSeglrs({makeSeglr(-100, 0, -101, 0, 0)});

  model.setCacheStemCPA(true, 1, 12.25);
  model.setCachePtCPA(true, 1, XYPoint(8, 9));

  XYSeglr star_turn = model.getTurnSeglr(45);
  EXPECT_NEAR(star_turn.getCacheStemCPA(), 12.25, kGeomTol);
  expectPointNear(star_turn.getCacheCPAPoint(), 8, 9);

  XYSeglr port_turn = model.getTurnSeglr(315);
  EXPECT_NEAR(port_turn.getCacheStemCPA(), -1.0, kGeomTol);
  EXPECT_FALSE(port_turn.getCacheCPAPoint().valid());
}
