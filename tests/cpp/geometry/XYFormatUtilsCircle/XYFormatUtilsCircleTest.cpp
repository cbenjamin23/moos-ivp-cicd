#include <gtest/gtest.h>

#include <cmath>
#include <string>
#include <vector>

#include "GeometryTestUtils.h"
#include "NumericAssertions.h"
#include "XYCircle.h"
#include "XYFormatUtilsCircle.h"
#include "XYPoint.h"

// Covers XY format utils circle behavior: parses view circle style spec used by viewer apps.
TEST(XYFormatUtilsCircleTest, ParsesViewCircleStyleSpecUsedByViewerApps)
{
  XYCircle circle = string2Circle(
      "x=20,y=-30,radius=40,label=alert_in,msg=contact_gilda,"
      "edge_color=yellow,fill_color=white,fill_transparency=0.25,"
      "edge_size=2,vertex_color=green,vertex_size=3,label_color=gray50,"
      "time=10,duration=5,active=false,vertices=32");

  ASSERT_TRUE(circle.valid());
  EXPECT_NEAR(circle.getX(), 20.0, kGeomTol);
  EXPECT_NEAR(circle.getY(), -30.0, kGeomTol);
  EXPECT_NEAR(circle.getRad(), 40.0, kGeomTol);
  EXPECT_EQ(circle.get_label(), "alert_in");
  EXPECT_EQ(circle.get_msg(), "contact_gilda");
  EXPECT_EQ(circle.get_color_str("edge"), "yellow");
  EXPECT_EQ(circle.get_color_str("fill"), "white");
  EXPECT_EQ(circle.get_color_str("vertex"), "green");
  EXPECT_EQ(circle.get_color_str("label"), "gray50");
  EXPECT_TRUE(circle.transparency_set());
  EXPECT_NEAR(circle.get_transparency(), 0.25, kGeomTol);
  EXPECT_TRUE(circle.edge_size_set());
  EXPECT_NEAR(circle.get_edge_size(), 2.0, kGeomTol);
  EXPECT_TRUE(circle.vertex_size_set());
  EXPECT_NEAR(circle.get_vertex_size(), 3.0, kGeomTol);
  EXPECT_TRUE(circle.time_set());
  EXPECT_NEAR(circle.get_time(), 10.0, kGeomTol);
  EXPECT_TRUE(circle.duration_set());
  EXPECT_NEAR(circle.get_duration(), 5.0, kGeomTol);
  EXPECT_FALSE(circle.active());
  EXPECT_EQ(circle.getDrawVertices(), 32u);
}

// Covers XY format utils circle behavior: parses contact manager alert radii payload.
TEST(XYFormatUtilsCircleTest, ParsesContactManagerAlertRadiiPayload)
{
  XYCircle circle = string2Circle(
      "x=-150.3,y=-117.5,radius=80,label=avd_in,edge_color=white,"
      "vertex_size=0,edge_size=1,active=true");

  ASSERT_TRUE(circle.valid());
  EXPECT_NEAR(circle.getX(), -150.3, kGeomTol);
  EXPECT_NEAR(circle.getY(), -117.5, kGeomTol);
  EXPECT_NEAR(circle.getRad(), 80.0, kGeomTol);
  EXPECT_EQ(circle.get_label(), "avd_in");
  EXPECT_EQ(circle.get_color_str("edge"), "white");
  EXPECT_TRUE(circle.vertex_size_set());
  EXPECT_NEAR(circle.get_vertex_size(), 0.0, kGeomTol);
  EXPECT_TRUE(circle.edge_size_set());
  EXPECT_NEAR(circle.get_edge_size(), 1.0, kGeomTol);
  EXPECT_TRUE(circle.active());
}

// Covers XY format utils circle behavior: parses quoted viewer message payloads with commas.
TEST(XYFormatUtilsCircleTest, ParsesQuotedViewerMessagePayloadsWithCommas)
{
  XYCircle circle = string2Circle(
      "x=-25,y=-85,radius=40,msg=\"turn_rate=12,avg_rad=40\","
      "label=fixed_turn_preview,edge_color=cyan,fill_color=blue,"
      "fill_transparency=0.4,active=true");

  ASSERT_TRUE(circle.valid());
  EXPECT_NEAR(circle.getX(), -25.0, kGeomTol);
  EXPECT_NEAR(circle.getY(), -85.0, kGeomTol);
  EXPECT_NEAR(circle.getRad(), 40.0, kGeomTol);
  EXPECT_EQ(circle.get_label(), "fixed_turn_preview");
  EXPECT_EQ(circle.get_msg(), "\"turn_rate=12,avg_rad=40\"");
  EXPECT_EQ(circle.get_color_str("edge"), "cyan");
  EXPECT_EQ(circle.get_color_str("fill"), "blue");
  EXPECT_TRUE(circle.transparency_set());
  EXPECT_NEAR(circle.get_transparency(), 0.4, kGeomTol);
  EXPECT_TRUE(circle.active());
}

// Covers XY format utils circle behavior: requires coordinate and radius fields.
TEST(XYFormatUtilsCircleTest, RequiresCoordinateAndRadiusFields)
{
  EXPECT_FALSE(string2Circle("y=2,radius=3,label=missing_x").valid());
  EXPECT_FALSE(string2Circle("x=1,radius=3,label=missing_y").valid());
  EXPECT_FALSE(string2Circle("x=1,y=2,label=missing_radius").valid());
  EXPECT_FALSE(string2Circle("x=1,y=2,radius=not-a-number").valid());
  EXPECT_FALSE(string2Circle("x=1,y=2,rad=3,label=rad_alias_not_supported").valid());
}

// Covers XY format utils circle behavior: preserves parser treatment of unknown and loose fields.
TEST(XYFormatUtilsCircleTest, PreservesParserTreatmentOfUnknownAndLooseFields)
{
  XYCircle circle = string2Circle(
      "x=1,y=2,radius=-5,source=pContactMgr,type=alert,id=abc,"
      "duration=-7,fill_transparency=2,active=maybe,vertices=0,"
      // Invalid color construction is isolated in colorpack-known-issues.
      "edge_size=-1,vertex_size=-2");

  ASSERT_TRUE(circle.valid());
  EXPECT_NEAR(circle.getRad(), 0.0, kGeomTol);
  EXPECT_EQ(circle.get_source(), "");
  EXPECT_EQ(circle.get_type(), "");
  EXPECT_EQ(circle.get_id(), "");
  EXPECT_FALSE(circle.active());
  EXPECT_TRUE(circle.duration_set());
  EXPECT_NEAR(circle.get_duration(), -1.0, kGeomTol);
  EXPECT_TRUE(circle.transparency_set());
  EXPECT_NEAR(circle.get_transparency(), 1.0, kGeomTol);
  EXPECT_EQ(circle.getDrawVertices(), 0u);
  EXPECT_FALSE(circle.edge_size_set());
  EXPECT_FALSE(circle.vertex_size_set());
  EXPECT_FALSE(circle.color_set("edge"));
}

// Covers XY circle behavior: initializes simple io geom utils circle format.
TEST(XYCircleTest, InitializesSimpleIoGeomUtilsCircleFormat)
{
  XYCircle circle;
  ASSERT_TRUE(circle.initialize("10, -20, 30, patrol_radius"));
  EXPECT_TRUE(circle.valid());
  EXPECT_NEAR(circle.getX(), 10.0, kGeomTol);
  EXPECT_NEAR(circle.getY(), -20.0, kGeomTol);
  EXPECT_NEAR(circle.getRad(), 30.0, kGeomTol);
  EXPECT_EQ(circle.get_label(), "patrol_radius");

  EXPECT_FALSE(circle.initialize("10,-20"));
  EXPECT_FALSE(circle.initialize("10,-20,not-a-radius"));
  EXPECT_FALSE(circle.initialize("10,-20,-3"));
}

// Covers XY circle behavior: setters clamp or reject negative radius by entry point.
TEST(XYCircleTest, SettersClampOrRejectNegativeRadiusByEntryPoint)
{
  XYCircle circle;
  EXPECT_FALSE(circle.set(0, 0, -1));
  EXPECT_FALSE(circle.valid());

  circle.setRad(-5);
  EXPECT_FALSE(circle.valid());
  circle.setX(0);
  circle.setY(0);
  EXPECT_TRUE(circle.valid());
  EXPECT_NEAR(circle.getRad(), 0.0, kGeomTol);

  circle.alterRad(10);
  EXPECT_NEAR(circle.getRad(), 10.0, kGeomTol);
  circle.alterRad(-20);
  EXPECT_NEAR(circle.getRad(), 0.0, kGeomTol);
  circle.alterRad(10);
  circle.alterRadPct(-2);
  EXPECT_NEAR(circle.getRad(), 0.0, kGeomTol);

  circle.set(10, -20, 5);
  circle.alterX(2);
  circle.alterY(-3);
  EXPECT_NEAR(circle.getX(), 12.0, kGeomTol);
  EXPECT_NEAR(circle.getY(), -23.0, kGeomTol);
}

// Covers XY circle behavior: computes bounds containment and perimeter distance.
TEST(XYCircleTest, ComputesBoundsContainmentAndPerimeterDistance)
{
  XYCircle circle(10, -5, 7);

  EXPECT_NEAR(circle.get_min_x(), 3.0, kGeomTol);
  EXPECT_NEAR(circle.get_max_x(), 17.0, kGeomTol);
  EXPECT_NEAR(circle.get_min_y(), -12.0, kGeomTol);
  EXPECT_NEAR(circle.get_max_y(), 2.0, kGeomTol);
  EXPECT_TRUE(circle.containsPoint(10, -5));
  EXPECT_TRUE(circle.containsPoint(17, -5));
  EXPECT_FALSE(circle.containsPoint(17.1, -5));
  EXPECT_TRUE(circle.containsPoint(XYPoint(10, 2)));
  EXPECT_FALSE(circle.containsPoint(XYPoint(10, 2.1)));

  EXPECT_NEAR(circle.ptDistToCircle(10, -5), 7.0, kGeomTol);
  EXPECT_NEAR(circle.ptDistToCircle(17, -5), 0.0, kGeomTol);
  EXPECT_NEAR(circle.ptDistToCircle(20, -5), 3.0, kGeomTol);
}

// Covers XY circle behavior: distinguishes contained segments from strict perimeter crossings.
TEST(XYCircleTest, DistinguishesContainedSegmentsFromStrictPerimeterCrossings)
{
  XYCircle circle(0, 0, 10);

  EXPECT_TRUE(circle.segIntersect(-1, 0, 1, 0));
  EXPECT_FALSE(circle.segIntersectStrict(-1, 0, 1, 0));

  EXPECT_TRUE(circle.segIntersect(-20, 0, 20, 0));
  EXPECT_TRUE(circle.segIntersectStrict(-20, 0, 20, 0));

  EXPECT_TRUE(circle.segIntersect(-10, 0, 10, 0));
  EXPECT_TRUE(circle.segIntersectStrict(-10, 0, 10, 0));

  EXPECT_FALSE(circle.segIntersect(20, 20, 30, 20));
  EXPECT_FALSE(circle.segIntersectStrict(20, 20, 30, 20));
}

// Covers XY circle behavior: handles tangent and diagonal perimeter intersections.
TEST(XYCircleTest, HandlesTangentAndDiagonalPerimeterIntersections)
{
  XYCircle circle(0, 0, 5);
  double rx1 = 0;
  double ry1 = 0;
  double rx2 = 0;
  double ry2 = 0;

  EXPECT_TRUE(circle.segIntersect(-10, 5, 10, 5));
  EXPECT_TRUE(circle.segIntersectStrict(-10, 5, 10, 5));
  EXPECT_EQ(circle.segIntersectPts(-10, 5, 10, 5, rx1, ry1, rx2, ry2), 2);
  EXPECT_NEAR(rx1, 0.0, kGeomTol);
  EXPECT_NEAR(ry1, 5.0, kGeomTol);
  EXPECT_NEAR(rx2, 0.0, kGeomTol);
  EXPECT_NEAR(ry2, 5.0, kGeomTol);
  EXPECT_NEAR(circle.segIntersectLen(-10, 5, 10, 5), 0.0, kGeomTol);

  EXPECT_EQ(circle.segIntersectPts(-10, -10, 10, 10, rx1, ry1, rx2, ry2), 2);
  EXPECT_NEAR(rx1, 5.0, kLooseGeomTol);
  EXPECT_NEAR(ry1, 0.0, kLooseGeomTol);
  EXPECT_NEAR(rx2, -5.0, kLooseGeomTol);
  EXPECT_NEAR(ry2, 0.0, kLooseGeomTol);
  EXPECT_NEAR(circle.segIntersectLen(-10, -10, 10, 10), 10.0, kLooseGeomTol);
}

// Covers XY circle behavior: treats zero radius as point circle for containment and segment checks.
TEST(XYCircleTest, TreatsZeroRadiusAsPointCircleForContainmentAndSegmentChecks)
{
  XYCircle circle(0, 0, 0);
  double rx1 = 99;
  double ry1 = 99;
  double rx2 = 99;
  double ry2 = 99;

  EXPECT_TRUE(circle.valid());
  EXPECT_TRUE(circle.containsPoint(0, 0));
  EXPECT_FALSE(circle.containsPoint(0.001, 0));
  EXPECT_NEAR(circle.ptDistToCircle(0, 0), 0.0, kGeomTol);
  EXPECT_NEAR(circle.ptDistToCircle(3, 4), 5.0, kGeomTol);
  EXPECT_TRUE(circle.segIntersect(-1, 0, 1, 0));
  EXPECT_TRUE(circle.segIntersectStrict(-1, 0, 1, 0));
  EXPECT_EQ(circle.segIntersectPts(-1, 0, 1, 0, rx1, ry1, rx2, ry2), 2);
  EXPECT_NEAR(rx1, 0.0, kGeomTol);
  EXPECT_NEAR(ry1, 0.0, kGeomTol);
  EXPECT_NEAR(rx2, 0.0, kGeomTol);
  EXPECT_NEAR(ry2, 0.0, kGeomTol);
  EXPECT_NEAR(circle.segIntersectLen(-1, 0, 1, 0), 0.0, kGeomTol);
}

// Covers XY circle behavior: reports horizontal and vertical segment intersection points.
TEST(XYCircleTest, ReportsHorizontalAndVerticalSegmentIntersectionPoints)
{
  XYCircle circle(0, 0, 5);
  double rx1 = 0;
  double ry1 = 0;
  double rx2 = 0;
  double ry2 = 0;

  EXPECT_EQ(circle.segIntersectPts(-10, 0, 10, 0, rx1, ry1, rx2, ry2), 2);
  EXPECT_NEAR(rx1, -5.0, kGeomTol);
  EXPECT_NEAR(ry1, 0.0, kGeomTol);
  EXPECT_NEAR(rx2, 5.0, kGeomTol);
  EXPECT_NEAR(ry2, 0.0, kGeomTol);

  EXPECT_EQ(circle.segIntersectPts(0, -10, 0, 10, rx1, ry1, rx2, ry2), 2);
  EXPECT_NEAR(rx1, 0.0, kGeomTol);
  EXPECT_NEAR(ry1, -5.0, kGeomTol);
  EXPECT_NEAR(rx2, 0.0, kGeomTol);
  EXPECT_NEAR(ry2, 5.0, kGeomTol);

  EXPECT_EQ(circle.segIntersectPts(-10, 0, 0, 0, rx1, ry1, rx2, ry2), 1);
  EXPECT_NEAR(rx1, -5.0, kGeomTol);
  EXPECT_NEAR(ry1, 0.0, kGeomTol);
}

// Covers XY circle behavior: computes length of segment inside circle.
TEST(XYCircleTest, ComputesLengthOfSegmentInsideCircle)
{
  XYCircle circle(0, 0, 5);

  EXPECT_NEAR(circle.segIntersectLen(-10, 0, 10, 0), 10.0, kGeomTol);
  EXPECT_NEAR(circle.segIntersectLen(-3, 0, 3, 0), 6.0, kGeomTol);
  EXPECT_NEAR(circle.segIntersectLen(-10, 0, 0, 0), 5.0, kGeomTol);
  EXPECT_NEAR(circle.segIntersectLen(5, 0, 10, 0), 0.0, kGeomTol);
  EXPECT_NEAR(circle.segIntersectLen(10, 10, 20, 10), 0.0, kGeomTol);
}

// Covers XY circle behavior: serializes viewer circle specs with digits and metadata.
TEST(XYCircleTest, SerializesViewerCircleSpecsWithDigitsAndMetadata)
{
  XYCircle circle(1.234567, -2.345678, 9.876543);
  circle.set_spec_digits(3);
  circle.setDrawVertices(18);
  circle.set_label("alert_abe");
  circle.set_color("edge", "white");
  circle.set_vertex_size(0);
  circle.set_edge_size(1);
  circle.set_duration(3);
  circle.set_time(42.25);

  std::string spec = circle.get_spec("active=true");
  EXPECT_TRUE(stringContains(spec, "x=1.235"));
  EXPECT_TRUE(stringContains(spec, "y=-2.346"));
  EXPECT_TRUE(stringContains(spec, "radius=9.877"));
  EXPECT_TRUE(stringContains(spec, "vertices=18"));
  EXPECT_TRUE(stringContains(spec, "active=true"));
  EXPECT_TRUE(stringContains(spec, "label=alert_abe"));
  EXPECT_TRUE(stringContains(spec, "edge_color=white"));
  EXPECT_TRUE(stringContains(spec, "vertex_size=0"));
  EXPECT_TRUE(stringContains(spec, "edge_size=1"));
  EXPECT_TRUE(stringContains(spec, "time=42.25"));
  EXPECT_TRUE(stringContains(spec, "duration=3"));
}

// Covers XY circle behavior: round trips collision detector encounter ring payload.
TEST(XYCircleTest, RoundTripsCollisionDetectorEncounterRingPayload)
{
  // uFldCollisionDetect builds XYCircle rings from NodeRecord positions and
  // posts the generated spec on VIEW_CIRCLE.
  XYCircle ring(15.25, -43.5, 12.75);
  ring.set_edge_color("white");
  ring.set_label("abe_rng");
  ring.set_color("label", "off");

  XYCircle parsed = string2Circle(ring.get_spec());

  ASSERT_TRUE(parsed.valid());
  EXPECT_NEAR(parsed.getX(), 15.25, kGeomTol);
  EXPECT_NEAR(parsed.getY(), -43.5, kGeomTol);
  EXPECT_NEAR(parsed.getRad(), 12.75, kGeomTol);
  EXPECT_EQ(parsed.get_label(), "abe_rng");
  EXPECT_EQ(parsed.get_color_str("edge"), "white");
  EXPECT_EQ(parsed.get_color_str("label"), "invisible");
}

// Covers XY circle behavior: round trips contact manager warning and alert radii payloads.
TEST(XYCircleTest, RoundTripsContactManagerWarningAndAlertRadiiPayloads)
{
  // pContactMgrV20 posts short-lived VIEW_CIRCLE objects for early-warning
  // contact radii and aggregate alert radii.
  XYCircle early_warning(-150.3, -117.5, 40);
  early_warning.set_label("xewarn_gus");
  early_warning.set_label_color("gray50");
  early_warning.set_color("edge", "yellow");
  early_warning.set_vertex_size(0);
  early_warning.set_edge_size(1);
  early_warning.set_active(true);
  early_warning.set_duration(3);
  early_warning.set_time(250.5);

  XYCircle parsed_warning = string2Circle(early_warning.get_spec());
  ASSERT_TRUE(parsed_warning.valid());
  EXPECT_EQ(parsed_warning.get_label(), "xewarn_gus");
  EXPECT_EQ(parsed_warning.get_color_str("label"), "gray50");
  EXPECT_EQ(parsed_warning.get_color_str("edge"), "yellow");
  EXPECT_TRUE(parsed_warning.active());
  EXPECT_TRUE(parsed_warning.vertex_size_set());
  EXPECT_NEAR(parsed_warning.get_vertex_size(), 0.0, kGeomTol);
  EXPECT_TRUE(parsed_warning.edge_size_set());
  EXPECT_NEAR(parsed_warning.get_edge_size(), 1.0, kGeomTol);
  EXPECT_TRUE(parsed_warning.duration_set());
  EXPECT_NEAR(parsed_warning.get_duration(), 3.0, kGeomTol);
  EXPECT_TRUE(parsed_warning.time_set());
  EXPECT_NEAR(parsed_warning.get_time(), 250.5, kGeomTol);

  XYCircle alert(-150.3, -117.5, 80);
  alert.set_label("alert_abe");
  alert.set_color("edge", "invisible");
  alert.set_vertex_size(0);
  alert.set_edge_size(1);
  alert.set_active(false);
  alert.set_duration(3);
  alert.set_time(251.0);

  XYCircle parsed_alert = string2Circle(alert.get_spec());
  ASSERT_TRUE(parsed_alert.valid());
  EXPECT_EQ(parsed_alert.get_label(), "alert_abe");
  EXPECT_EQ(parsed_alert.get_color_str("edge"), "invisible");
  EXPECT_FALSE(parsed_alert.active());
  EXPECT_NEAR(parsed_alert.getRad(), 80.0, kGeomTol);
}

// Covers XY circle behavior: clamps serialization digits to supported range.
TEST(XYCircleTest, ClampsSerializationDigitsToSupportedRange)
{
  XYCircle circle(1.234567, -2.345678, 9.876543);

  circle.set_spec_digits(6);
  EXPECT_TRUE(stringContains(circle.get_spec(), "x=1.234567"));
  EXPECT_TRUE(stringContains(circle.get_spec(), "y=-2.345678"));
  EXPECT_TRUE(stringContains(circle.get_spec(), "radius=9.876543"));

  circle.set_spec_digits(9);
  EXPECT_TRUE(stringContains(circle.get_spec(), "x=1.234567"));

  circle.set_spec_digits(0);
  EXPECT_TRUE(stringContains(circle.get_spec(), "x=1"));
  EXPECT_TRUE(stringContains(circle.get_spec(), "y=-2"));
  EXPECT_TRUE(stringContains(circle.get_spec(), "radius=10"));

  circle.set_spec_digits(-1);
  EXPECT_TRUE(stringContains(circle.get_spec(), "x=1"));
}

// Covers XY circle behavior: builds point cache using MOOS heading convention.
TEST(XYCircleTest, BuildsPointCacheUsingMoosHeadingConvention)
{
  XYCircle circle(0, 0, 10);
  circle.setPointCache(4);
  std::vector<double> cache = circle.getPointCache();

  ASSERT_EQ(cache.size(), 8u);
  const double root_two_over_two = std::sqrt(2.0) / 2.0;
  EXPECT_NEAR(cache[0], 10.0 * root_two_over_two, kGeomTol);
  EXPECT_NEAR(cache[1], 10.0 * root_two_over_two, kGeomTol);
  EXPECT_NEAR(cache[2], 10.0 * root_two_over_two, kGeomTol);
  EXPECT_NEAR(cache[3], -10.0 * root_two_over_two, kGeomTol);

  circle.setDrawVertices(3);
  circle.setPointCacheAuto(8);
  EXPECT_EQ(circle.getPointCache().size(), 6u);
}
