#include <gtest/gtest.h>

#include <cmath>
#include <list>

#include "AngleUtils.h"
#include "GeometryTestUtils.h"
#include "NumericAssertions.h"

// Covers angle utils heading conventions behavior: computes MOOS relative bearings from cartesian points.
TEST(AngleUtilsHeadingConventionsTest, ComputesMoosRelativeBearingsFromCartesianPoints)
{
  EXPECT_NEAR(relAng(0, 0, 0, 10), 0.0, kGeomTol);
  EXPECT_NEAR(relAng(0, 0, 10, 0), 90.0, kGeomTol);
  EXPECT_NEAR(relAng(0, 0, 0, -10), 180.0, kGeomTol);
  EXPECT_NEAR(relAng(0, 0, -10, 0), 270.0, kGeomTol);
  EXPECT_NEAR(relAng(0, 0, 10, 10), 45.0, kGeomTol);
  EXPECT_NEAR(relAng(0, 0, -10, 10), 315.0, kGeomTol);
  EXPECT_NEAR(relAng(0, 0, 0, 0), 0.0, kGeomTol);

  XYPoint ownship(0, 0);
  XYPoint waypoint(10, 0);
  EXPECT_NEAR(relAng(ownship, waypoint), 90.0, kGeomTol);
}

// Covers angle utils heading conventions behavior: wraps angles for helm heading calculations.
TEST(AngleUtilsHeadingConventionsTest, WrapsAnglesForHelmHeadingCalculations)
{
  EXPECT_NEAR(angle360(-10), 350.0, kGeomTol);
  EXPECT_NEAR(angle360(370), 10.0, kGeomTol);
  EXPECT_NEAR(angle360(720), 0.0, kGeomTol);
  EXPECT_NEAR(angle180(190), -170.0, kGeomTol);
  EXPECT_NEAR(angle180(-180), 180.0, kGeomTol);
  EXPECT_NEAR(angle180(540), 180.0, kGeomTol);
  EXPECT_NEAR(angleDiff(5, 355), 10.0, kGeomTol);
  EXPECT_NEAR(angleDiff(90, 270), 180.0, kGeomTol);
  EXPECT_NEAR(aspectDiff(10, 190), 0.0, kGeomTol);
  EXPECT_NEAR(aspectDiff(45, 135), 90.0, kGeomTol);
}

// Covers angle utils heading conventions behavior: converts between true heading and cartesian radians.
TEST(AngleUtilsHeadingConventionsTest, ConvertsBetweenTrueHeadingAndCartesianRadians)
{
  constexpr double pi = 3.14159265358979323846;

  EXPECT_NEAR(degToRadians(180), pi, kLooseGeomTol);
  EXPECT_NEAR(degToRadians(-90), -pi / 2.0, kLooseGeomTol);
  EXPECT_NEAR(radToDegrees(pi / 2.0), 90.0, kLooseGeomTol);
  EXPECT_NEAR(radToDegrees(-pi), -180.0, kLooseGeomTol);
  EXPECT_NEAR(headingToRadians(0), pi / 2.0, kLooseGeomTol);
  EXPECT_NEAR(headingToRadians(90), 0.0, kGeomTol);
  EXPECT_NEAR(headingToRadians(180), -pi / 2.0, kLooseGeomTol);
  EXPECT_NEAR(std::abs(headingToRadians(270)), pi, kLooseGeomTol);
  EXPECT_NEAR(radToHeading(0), 90.0, kGeomTol);
  EXPECT_NEAR(radToHeading(pi / 2.0), 0.0, kLooseGeomTol);
  EXPECT_NEAR(radToHeading(-pi / 2.0), 180.0, kLooseGeomTol);
  EXPECT_NEAR(radAngleWrap(3.0 * pi), pi, kLooseGeomTol);
  EXPECT_NEAR(radAngleWrap(-3.0 * pi), -pi, kLooseGeomTol);
}

// Covers angle utils heading conventions behavior: projects speed onto requested heading.
TEST(AngleUtilsHeadingConventionsTest, ProjectsSpeedOntoRequestedHeading)
{
  EXPECT_NEAR(speedInHeading(0, 4, 0), 4.0, kGeomTol);
  EXPECT_NEAR(speedInHeading(0, 4, 180), -4.0, kGeomTol);
  EXPECT_NEAR(speedInHeading(0, 4, 90), 0.0, kGeomTol);
  EXPECT_NEAR(speedInHeading(0, 4, 45), 2.8284271247, kLooseGeomTol);
  EXPECT_NEAR(speedInHeading(350, 5, -10), 5.0, kGeomTol);
  EXPECT_NEAR(speedInHeading(90, 0, 90), 0.0, kGeomTol);
}

// Covers angle utils contact bearing behavior: computes contact relative bearings used by IvP contact behavior.
TEST(AngleUtilsContactBearingTest, ComputesContactRelativeBearingsUsedByIvPContactBehavior)
{
  EXPECT_NEAR(relBearing(0, 0, 350, 10, 10), 55.0, kGeomTol);
  EXPECT_NEAR(absRelBearing(0, 0, 350, 10, 10), 55.0, kGeomTol);
  EXPECT_NEAR(relBearing(0, 0, 0, -10, 0), 270.0, kGeomTol);
  EXPECT_NEAR(absRelBearing(0, 0, 0, -10, 0), 90.0, kGeomTol);
  EXPECT_NEAR(totAbsRelBearing(0, 0, 350, 10, 10, 225), 55.0, kGeomTol);
  EXPECT_NEAR(totAbsRelBearing(0, 0, 0, 10, 0, 270), 90.0, kGeomTol);
}

// Covers angle utils angle range behavior: classifies angles inside acute wrap intervals.
TEST(AngleUtilsAngleRangeTest, ClassifiesAnglesInsideAcuteWrapIntervals)
{
  EXPECT_TRUE(containsAngle(350, 10, 0));
  EXPECT_TRUE(containsAngle(10, 350, 0));
  EXPECT_FALSE(containsAngle(350, 10, 180));
  EXPECT_TRUE(containsAngle(100, 280, 99));
  EXPECT_TRUE(containsAngle(100, 280, 101));
  EXPECT_TRUE(containsAngle(-10, 10, 0));
  EXPECT_FALSE(containsAngle(45, 45, 46));
  EXPECT_TRUE(containsAngle(45, 45, 45));
}

// Covers angle utils angle range behavior: selects acute and reflex arc bounds.
TEST(AngleUtilsAngleRangeTest, SelectsAcuteAndReflexArcBounds)
{
  EXPECT_NEAR(angleMinAcute(10, 20), 10.0, kGeomTol);
  EXPECT_NEAR(angleMaxAcute(10, 20), 20.0, kGeomTol);
  EXPECT_NEAR(angleMinAcute(10, 350), 350.0, kGeomTol);
  EXPECT_NEAR(angleMaxAcute(10, 350), 10.0, kGeomTol);
  EXPECT_NEAR(angleMinReflex(10, 20), 20.0, kGeomTol);
  EXPECT_NEAR(angleMaxReflex(10, 20), 10.0, kGeomTol);
  EXPECT_NEAR(angleMinReflex(89, 271), 89.0, kGeomTol);
  EXPECT_NEAR(angleMaxReflex(89, 271), 271.0, kGeomTol);
}

// Covers angle utils angle range behavior: selects arc bounds that contain or exclude query heading.
TEST(AngleUtilsAngleRangeTest, SelectsArcBoundsThatContainOrExcludeQueryHeading)
{
  EXPECT_NEAR(angleMinContains(10, 20, 5), 20.0, kGeomTol);
  EXPECT_NEAR(angleMaxContains(10, 20, 5), 10.0, kGeomTol);
  EXPECT_NEAR(angleMinContains(10, 350, 2), 350.0, kGeomTol);
  EXPECT_NEAR(angleMaxContains(10, 350, 2), 10.0, kGeomTol);
  EXPECT_NEAR(angleMinContains(89, 271, 180), 89.0, kGeomTol);
  EXPECT_NEAR(angleMaxContains(89, 271, 180), 271.0, kGeomTol);
  EXPECT_NEAR(angleMinExcludes(10, 20, 5), 10.0, kGeomTol);
  EXPECT_NEAR(angleMaxExcludes(10, 20, 5), 20.0, kGeomTol);
  EXPECT_NEAR(angleMinExcludes(10, 350, 2), 10.0, kGeomTol);
  EXPECT_NEAR(angleMaxExcludes(10, 350, 2), 350.0, kGeomTol);
}

// Covers angle utils heading average behavior: averages headings across north for hysteresis style windows.
TEST(AngleUtilsHeadingAverageTest, AveragesHeadingsAcrossNorthForHysteresisStyleWindows)
{
  EXPECT_NEAR(angleDiff(headingAvg(350, 10), 0), 0.0, kGeomTol);
  EXPECT_NEAR(headingAvg(90, 180), 135.0, kGeomTol);
  EXPECT_NEAR(headingAvg(0, 180), 90.0, kGeomTol);

  std::list<double> headings;
  headings.push_back(350);
  headings.push_back(0);
  headings.push_back(10);
  EXPECT_NEAR(angleDiff(headingAvg(headings), 0), 0.0, kGeomTol);

  std::list<double> empty_headings;
  EXPECT_NEAR(headingAvg(empty_headings), 0.0, kGeomTol);
}

// Covers angle utils ownship side behavior: classifies port and starboard for northbound ownship.
TEST(AngleUtilsOwnshipSideTest, ClassifiesPortAndStarboardForNorthboundOwnship)
{
  EXPECT_TRUE(ptPortOfOwnship(0, 0, 0, -10, 0));
  EXPECT_TRUE(ptStarOfOwnship(0, 0, 0, 10, 0));
  EXPECT_FALSE(ptPortOfOwnship(0, 0, 0, 10, 0));
  EXPECT_FALSE(ptStarOfOwnship(0, 0, 0, -10, 0));
  EXPECT_FALSE(ptPortOfOwnship(0, 0, 0, 0, 0));
  EXPECT_FALSE(ptStarOfOwnship(0, 0, 0, 0, 0));
  EXPECT_FALSE(ptPortOfOwnship(0, 0, 0, 0, 10));
  // The helper includes the 180-degree boundary in the starboard half-plane.
  EXPECT_TRUE(ptStarOfOwnship(0, 0, 0, 0, -10));
}

// Covers angle utils ownship side behavior: classifies convex polygons relative to ownship heading.
TEST(AngleUtilsOwnshipSideTest, ClassifiesConvexPolygonsRelativeToOwnshipHeading)
{
  XYPolygon port_poly = makeSquarePoly(-20, -5, -10, 5);
  XYPolygon star_poly = makeSquarePoly(10, -5, 20, 5);
  XYPolygon crossing_poly = makeSquarePoly(-5, -5, 5, 5);
  XYPolygon aft_poly = makeSquarePoly(-2, -20, 2, -10);

  EXPECT_TRUE(polyPortOfOwnship(0, 0, 0, port_poly));
  EXPECT_FALSE(polyStarOfOwnship(0, 0, 0, port_poly));
  EXPECT_TRUE(polyStarOfOwnship(0, 0, 0, star_poly));
  EXPECT_FALSE(polyPortOfOwnship(0, 0, 0, star_poly));
  EXPECT_FALSE(polyPortOfOwnship(0, 0, 0, crossing_poly));
  EXPECT_FALSE(polyStarOfOwnship(0, 0, 0, crossing_poly));
  EXPECT_TRUE(polyAft(0, 0, 0, aft_poly));
  EXPECT_TRUE(polyAft(0, 0, 0, aft_poly, 20));
  EXPECT_FALSE(polyAft(0, 0, 0, aft_poly, 80));
  EXPECT_TRUE(polyAft(0, 0, 0, aft_poly, -200));
  EXPECT_FALSE(polyAft(0, 0, 0, aft_poly, 200));
}

// Covers angle utils turn behavior: classifies port and starboard turn direction.
TEST(AngleUtilsTurnTest, ClassifiesPortAndStarboardTurnDirection)
{
  EXPECT_TRUE(portTurn(0, 270));
  EXPECT_FALSE(portTurn(0, 90));
  EXPECT_FALSE(portTurn(350, 10));
  EXPECT_TRUE(portTurn(10, 350));
  // An exact half-turn is not classified as a port turn.
  EXPECT_FALSE(portTurn(0, 180));
}

// Covers angle utils turn behavior: computes turn gap from immediate turn circle to obstacle line.
TEST(AngleUtilsTurnTest, ComputesTurnGapFromImmediateTurnCircleToObstacleLine)
{
  EXPECT_NEAR(turnGap(0, 0, 0, 10, 10, -20, 10, 20, true), 0.0, kGeomTol);
  EXPECT_NEAR(turnGap(0, 0, 0, 10, -10, -20, -10, 20, false), 0.0, kGeomTol);
  EXPECT_NEAR(turnGap(0, 0, 0, 10, 30, -20, 30, 20, true), 10.0, kGeomTol);
  EXPECT_NEAR(turnGap(5, -5, 90, 4, -20, -9, 20, -9, true), 0.0, kGeomTol);
}

// Covers angle utils point geometry behavior: computes triangle angles and turn orientation.
TEST(AngleUtilsPointGeometryTest, ComputesTriangleAnglesAndTurnOrientation)
{
  EXPECT_NEAR(angleFromThreePoints(0, 0, 3, 0, 0, 4), 90.0, kGeomTol);
  EXPECT_NEAR(angleFromThreePoints(0, 0, 0, 0, 1, 0), 0.0, kGeomTol);
  EXPECT_NEAR(threePointXProduct(0, 0, 1, 0, 0, 1), -1.0, kGeomTol);
  EXPECT_TRUE(threePointTurnLeft(0, 0, 1, 0, 0, 1));
  EXPECT_FALSE(threePointTurnLeft(0, 0, 0, 1, 1, 0));
}
