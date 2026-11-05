#include <gtest/gtest.h>

#include <cmath>
#include <string>

#include "GeomUtils.h"
#include "GeometryTestUtils.h"
#include "NumericAssertions.h"
#include "SeglrUtils.h"
#include "XYFormatUtilsSeglr.h"
#include "XYPoint.h"
#include "XYPolygon.h"
#include "XYSegList.h"
#include "XYSeglr.h"

namespace {

XYSeglr makeTurnRay()
{
  XYSeglr seglr;
  seglr.addVertex(0, 0);
  seglr.addVertex(10, 0);
  seglr.setRayAngle(0);
  return seglr;
}

XYPolygon makeBox(double low_x, double low_y, double high_x, double high_y)
{
  XYPolygon poly;
  poly.add_vertex(low_x, low_y);
  poly.add_vertex(high_x, low_y);
  poly.add_vertex(high_x, high_y);
  poly.add_vertex(low_x, high_y);
  return poly;
}

}  // namespace

// Covers XY seglr behavior: defaults and constructors expose ray specific state.
TEST(XYSeglrTest, DefaultsAndConstructorsExposeRaySpecificState)
{
  XYSeglr empty;
  EXPECT_FALSE(empty.valid());
  EXPECT_EQ(empty.size(), 0u);
  EXPECT_NEAR(empty.getRayAngle(), 0.0, kGeomTol);
  EXPECT_NEAR(empty.getRayLen(), 5.0, kGeomTol);
  EXPECT_NEAR(empty.getHeadSize(), 3.0, kGeomTol);
  EXPECT_NEAR(empty.getCacheCPA(), -1.0, kGeomTol);
  EXPECT_NEAR(empty.getCacheStemCPA(), -1.0, kGeomTol);
  EXPECT_FALSE(empty.getCacheCPAPoint().valid());
  EXPECT_NEAR(empty.getRayBaseX(), 0.0, kGeomTol);
  EXPECT_NEAR(empty.getRayBaseY(), 0.0, kGeomTol);

  XYSeglr angle_only(123);
  EXPECT_FALSE(angle_only.valid());
  EXPECT_NEAR(angle_only.getRayAngle(), 123.0, kGeomTol);

  XYSeglr single_vertex(7, -3, 270);
  ASSERT_TRUE(single_vertex.valid());
  EXPECT_EQ(single_vertex.size(), 1u);
  EXPECT_NEAR(single_vertex.getRayBaseX(), 7.0, kGeomTol);
  EXPECT_NEAR(single_vertex.getRayBaseY(), -3.0, kGeomTol);
  EXPECT_NEAR(single_vertex.getRayAngle(), 270.0, kGeomTol);

  XYSeglr two_vertices(1, 2, 3, 4);
  ASSERT_TRUE(two_vertices.valid());
  EXPECT_EQ(two_vertices.size(), 2u);
  EXPECT_NEAR(two_vertices.getRayAngle(), 0.0, kGeomTol);
  EXPECT_NEAR(two_vertices.getRayBaseX(), 3.0, kGeomTol);
  EXPECT_NEAR(two_vertices.getRayBaseY(), 4.0, kGeomTol);
}

// Covers XY seglr behavior: edits vertices and reports stem only extents.
TEST(XYSeglrTest, EditsVerticesAndReportsStemOnlyExtents)
{
  XYSeglr seglr;
  seglr.addVertex(10, -5);
  seglr.addVertex(20, 5);
  seglr.setVertex(15, 0, 1);
  seglr.setVertex(99, 99, 9);

  ASSERT_EQ(seglr.size(), 2u);
  EXPECT_NEAR(seglr.getVX(0), 10.0, kGeomTol);
  EXPECT_NEAR(seglr.getVY(0), -5.0, kGeomTol);
  EXPECT_NEAR(seglr.getVX(1), 15.0, kGeomTol);
  EXPECT_NEAR(seglr.getVY(1), 0.0, kGeomTol);
  EXPECT_NEAR(seglr.getVX(99), 0.0, kGeomTol);
  EXPECT_NEAR(seglr.getVY(99), 0.0, kGeomTol);

  EXPECT_NEAR(seglr.getMinX(), 10.0, kGeomTol);
  EXPECT_NEAR(seglr.getMaxX(), 15.0, kGeomTol);
  EXPECT_NEAR(seglr.getMinY(), -5.0, kGeomTol);
  EXPECT_NEAR(seglr.getMaxY(), 0.0, kGeomTol);
  EXPECT_NEAR(seglr.getAvgX(), 2.5, kGeomTol);
  EXPECT_NEAR(seglr.getAvgY(), 2.5, kGeomTol);

  XYSegList base = seglr.getBaseSegList();
  ASSERT_EQ(base.size(), 2u);
  EXPECT_NEAR(base.get_vx(0), 10.0, kGeomTol);
  EXPECT_NEAR(base.get_vy(1), 0.0, kGeomTol);
}

// Covers XY seglr behavior: translates from first stem vertex and reflects ray angle.
TEST(XYSeglrTest, TranslatesFromFirstStemVertexAndReflectsRayAngle)
{
  XYSeglr seglr;
  seglr.addVertex(10, 10);
  seglr.addVertex(20, 15);
  seglr.setRayAngle(45);

  seglr.translateTo(-2, 3);
  EXPECT_NEAR(seglr.getVX(0), -2.0, kGeomTol);
  EXPECT_NEAR(seglr.getVY(0), 3.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayBaseX(), 8.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayBaseY(), 8.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayAngle(), 45.0, kGeomTol);

  seglr.reflect();
  EXPECT_NEAR(seglr.getVX(0), 2.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayBaseX(), -8.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayAngle(), 315.0, kGeomTol);

  seglr.setRayAngle(450);
  seglr.reflect();
  EXPECT_NEAR(seglr.getRayAngle(), -90.0, kGeomTol);
}

// Covers XY seglr behavior: clamps visual sizing and cache values.
TEST(XYSeglrTest, ClampsVisualSizingAndCacheValues)
{
  XYSeglr seglr(0, 0, 90);

  seglr.setRayLen(12.5);
  seglr.setHeadSize(4.5);
  EXPECT_NEAR(seglr.getRayLen(), 12.5, kGeomTol);
  EXPECT_NEAR(seglr.getHeadSize(), 4.5, kGeomTol);

  seglr.setRayLen(-10);
  seglr.setHeadSize(-2);
  EXPECT_NEAR(seglr.getRayLen(), 0.0, kGeomTol);
  EXPECT_NEAR(seglr.getHeadSize(), 0.0, kGeomTol);

  seglr.setCacheCPA(-4);
  seglr.setCacheStemCPA(-8);
  EXPECT_NEAR(seglr.getCacheCPA(), 0.0, kGeomTol);
  EXPECT_NEAR(seglr.getCacheStemCPA(), 0.0, kGeomTol);

  XYPoint invalid_point;
  seglr.setCacheCPAPoint(invalid_point);
  EXPECT_FALSE(seglr.getCacheCPAPoint().valid());

  XYPoint cpa_point(3, 4);
  seglr.setCacheCPAPoint(cpa_point);
  ASSERT_TRUE(seglr.getCacheCPAPoint().valid());
  EXPECT_NEAR(seglr.getCacheCPAPoint().x(), 3.0, kGeomTol);
  EXPECT_NEAR(seglr.getCacheCPAPoint().y(), 4.0, kGeomTol);
}

// Covers XY seglr behavior: serializes ray fields drawing hints and optional CPA.
TEST(XYSeglrTest, SerializesRayFieldsDrawingHintsAndOptionalCpa)
{
  XYSeglr seglr;
  seglr.addVertex(0.25, 1.75);
  seglr.addVertex(10.5, -2.25);
  seglr.setRayAngle(42.75);
  seglr.setRayLen(8.125);
  seglr.setHeadSize(2.25);
  seglr.setCacheCPA(4.625);
  seglr.setCacheStemCPA(9.5);
  seglr.setCacheCPAPoint(XYPoint(6.125, -1.375));
  seglr.set_label("turn_ray");
  seglr.set_color("edge", "yellow");
  seglr.set_color("vertex", "blue");
  seglr.set_edge_size(2);
  seglr.set_vertex_size(3);

  std::string spec = seglr.get_spec(2);
  EXPECT_TRUE(stringContains(spec, "pts={0.25,1.75:10.5,-2.25}"));
  EXPECT_TRUE(stringContains(spec, "ray=42.75"));
  EXPECT_TRUE(stringContains(spec, "label=turn_ray"));
  EXPECT_TRUE(stringContains(spec, "edge_color=yellow"));
  EXPECT_TRUE(stringContains(spec, "vertex_color=blue"));
  EXPECT_TRUE(stringContains(spec, "edge_size=2"));
  EXPECT_TRUE(stringContains(spec, "vertex_size=3"));
  EXPECT_TRUE(stringContains(spec, "ray_len=8.12"));
  EXPECT_TRUE(stringContains(spec, "head_size=2.2"));
  EXPECT_TRUE(stringContains(spec, "cpa=4.62"));
  EXPECT_TRUE(stringContains(spec, "cpax=6.12"));
  EXPECT_TRUE(stringContains(spec, "cpay=-1.38"));
  EXPECT_FALSE(stringContains(spec, "stem"));
}

// Covers XY format utils seglr behavior: parses standard seglr with object drawing fields.
TEST(XYFormatUtilsSeglrTest, ParsesStandardSeglrWithObjectDrawingFields)
{
  XYSeglr seglr = string2Seglr(
      "pts={0,0:5,5:20,5},ray=45,ray_len=10,head_size=3,label=turn_arc,"
      "edge_color=yellow,vertex_color=green,label_color=white,edge_size=2,"
      "vertex_size=4,active=false,fill_transparency=1.7,source=viewer");

  ASSERT_TRUE(seglr.valid());
  ASSERT_EQ(seglr.size(), 3u);
  EXPECT_FALSE(seglr.active());
  EXPECT_EQ(seglr.get_label(), "turn_arc");
  EXPECT_EQ(seglr.get_source(), "viewer");
  EXPECT_NEAR(seglr.getVX(0), 0.0, kGeomTol);
  EXPECT_NEAR(seglr.getVY(1), 5.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayBaseX(), 20.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayBaseY(), 5.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayAngle(), 45.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayLen(), 10.0, kGeomTol);
  EXPECT_NEAR(seglr.getHeadSize(), 3.0, kGeomTol);
  EXPECT_EQ(seglr.get_color_str("edge"), "yellow");
  EXPECT_EQ(seglr.get_color_str("vertex"), "green");
  EXPECT_EQ(seglr.get_color_str("label"), "white");
  EXPECT_NEAR(seglr.get_edge_size(), 2.0, kGeomTol);
  EXPECT_NEAR(seglr.get_vertex_size(), 4.0, kGeomTol);
  EXPECT_NEAR(seglr.get_transparency(), 1.0, kGeomTol);
}

// Covers XY format utils seglr behavior: parses marine viewer dubins style view seglr payload.
TEST(XYFormatUtilsSeglrTest, ParsesMarineViewerDubinsStyleViewSeglrPayload)
{
  XYSeglr seglr = string2Seglr(
      "pts={0,0:10,0:10,10},ray=90,label=port_turn_preview,"
      "ray_len=25,head_size=5,edge_color=cyan,vertex_color=white");

  ASSERT_TRUE(seglr.valid());
  ASSERT_EQ(seglr.size(), 3u);
  EXPECT_EQ(seglr.get_label(), "port_turn_preview");
  EXPECT_NEAR(seglr.getRayBaseX(), 10.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayBaseY(), 10.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayAngle(), 90.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayLen(), 25.0, kGeomTol);
  EXPECT_NEAR(seglr.getHeadSize(), 5.0, kGeomTol);
  EXPECT_EQ(seglr.get_color_str("edge"), "cyan");
  EXPECT_EQ(seglr.get_color_str("vertex"), "white");
}

// Covers XY format utils seglr behavior: parses minimal and out of order payloads.
TEST(XYFormatUtilsSeglrTest, ParsesMinimalAndOutOfOrderPayloads)
{
  XYSeglr minimal = string2Seglr("pts={1,2}");
  ASSERT_TRUE(minimal.valid());
  EXPECT_EQ(minimal.size(), 1u);
  EXPECT_NEAR(minimal.getRayAngle(), 0.0, kGeomTol);
  EXPECT_NEAR(minimal.getRayLen(), 5.0, kGeomTol);
  EXPECT_NEAR(minimal.getHeadSize(), 3.0, kGeomTol);

  XYSeglr out_of_order = string2Seglr(
      "label=late_pts,ray_len=6,pts={-1.5,2.25:3.5,-4.25},head_size=1.5,ray=270");
  ASSERT_TRUE(out_of_order.valid());
  EXPECT_EQ(out_of_order.get_label(), "late_pts");
  EXPECT_NEAR(out_of_order.getVX(0), -1.5, kGeomTol);
  EXPECT_NEAR(out_of_order.getVY(1), -4.25, kGeomTol);
  EXPECT_NEAR(out_of_order.getRayAngle(), 270.0, kGeomTol);
  EXPECT_NEAR(out_of_order.getRayLen(), 6.0, kGeomTol);
  EXPECT_NEAR(out_of_order.getHeadSize(), 1.5, kGeomTol);
}

// Covers XY format utils seglr behavior: preserves current parser quirks for numeric ray fields.
TEST(XYFormatUtilsSeglrTest, PreservesCurrentParserQuirksForNumericRayFields)
{
  XYSeglr negative_visuals =
      string2Seglr("pts={0,0},ray=-45,ray_len=-9,head_size=-3");
  ASSERT_TRUE(negative_visuals.valid());
  EXPECT_NEAR(negative_visuals.getRayAngle(), -45.0, kGeomTol);
  EXPECT_NEAR(negative_visuals.getRayLen(), 5.0, kGeomTol);
  EXPECT_NEAR(negative_visuals.getHeadSize(), 3.0, kGeomTol);

  XYSeglr non_numeric_ray =
      string2Seglr("pts={0,0},ray=not_a_number,ray_len=bad,head_size=bad");
  ASSERT_TRUE(non_numeric_ray.valid());
  EXPECT_NEAR(non_numeric_ray.getRayAngle(), 0.0, kGeomTol);
  EXPECT_NEAR(non_numeric_ray.getRayLen(), 0.0, kGeomTol);
  EXPECT_NEAR(non_numeric_ray.getHeadSize(), 0.0, kGeomTol);

  XYSeglr extra_vertex_component = string2Seglr("pts={1,2,ignored},ray=90");
  ASSERT_TRUE(extra_vertex_component.valid());
  EXPECT_EQ(extra_vertex_component.size(), 1u);
  EXPECT_NEAR(extra_vertex_component.getVX(0), 1.0, kGeomTol);
  EXPECT_NEAR(extra_vertex_component.getVY(0), 2.0, kGeomTol);

  XYSeglr trailing_vertex_separator = string2Seglr("pts={0,0:},ray=90");
  ASSERT_TRUE(trailing_vertex_separator.valid());
  EXPECT_EQ(trailing_vertex_separator.size(), 1u);
  EXPECT_NEAR(trailing_vertex_separator.getRayAngle(), 90.0, kGeomTol);
}

// Covers XY format utils seglr behavior: rejects malformed point payloads.
TEST(XYFormatUtilsSeglrTest, RejectsMalformedPointPayloads)
{
  EXPECT_FALSE(string2Seglr("").valid());
  EXPECT_FALSE(string2Seglr("ray=90").valid());
  EXPECT_FALSE(string2Seglr("pts={}").valid());
  EXPECT_FALSE(string2Seglr("pts=0,0}").valid());
  EXPECT_FALSE(string2Seglr("pts={0,0}ray=90").valid());
  EXPECT_FALSE(string2Seglr("pts={0,0:bad,5},ray=90").valid());
  EXPECT_FALSE(string2Seglr("pts={0},ray=90").valid());
}

// Covers seglr behavior: maintains ray stem geometry and formats compact string.
TEST(SeglrTest, MaintainsRayStemGeometryAndFormatsCompactString)
{
  Seglr seglr;
  EXPECT_EQ(seglr.size(), 0u);
  EXPECT_NEAR(seglr.getVX(0), 0.0, kGeomTol);
  EXPECT_NEAR(seglr.getVY(0), 0.0, kGeomTol);

  seglr.addVertex(0, 0);
  seglr.addVertex(0, 10);
  seglr.setRayAngle(350);
  seglr.setVertex(1, 9, 1);
  seglr.setVertex(99, 99, 42);

  ASSERT_EQ(seglr.size(), 2u);
  EXPECT_NEAR(seglr.getVX(1), 1.0, kGeomTol);
  EXPECT_NEAR(seglr.getVY(1), 9.0, kGeomTol);
  EXPECT_NEAR(seglr.getRayAngle(), 350.0, kGeomTol);
  EXPECT_NEAR(seglr.getMinX(), 0.0, kGeomTol);
  EXPECT_NEAR(seglr.getMaxY(), 9.0, kGeomTol);
  EXPECT_EQ(seglr.getSpec(1), "pts={0.0,0.0:1.0,9.0},ray=350.0");
  EXPECT_EQ(seglrToString(seglr), "0.00,0.00:1.00,9.00#350.0");

  seglr.clear();
  EXPECT_EQ(seglr.size(), 0u);
  EXPECT_NEAR(seglr.getRayAngle(), 0.0, kGeomTol);
}

// Covers seglr behavior: crosses line can prefer ray or stem intersection.
TEST(SeglrTest, CrossesLineCanPreferRayOrStemIntersection)
{
  Seglr seglr;
  seglr.addVertex(0, 0);
  seglr.addVertex(10, 0);
  seglr.setRayAngle(0);

  double ix = 0;
  double iy = 0;
  ASSERT_TRUE(seglr.crossesLine(5, -1, 11, 5, ix, iy, true));
  EXPECT_NEAR(ix, 10.0, kGeomTol);
  EXPECT_NEAR(iy, 4.0, kGeomTol);

  ASSERT_TRUE(seglr.crossesLine(5, -1, 11, 5, ix, iy, false));
  EXPECT_NEAR(ix, 6.0, kGeomTol);
  EXPECT_NEAR(iy, 0.0, kGeomTol);

  EXPECT_FALSE(Seglr().crossesLine(0, 0, 1, 1));
}

// Covers seglr behavior: crosses line handles ray only and stem only boundary cases.
TEST(SeglrTest, CrossesLineHandlesRayOnlyAndStemOnlyBoundaryCases)
{
  Seglr seglr;
  seglr.addVertex(0, 0);
  seglr.addVertex(10, 0);
  seglr.setRayAngle(0);

  double ix = 0;
  double iy = 0;
  EXPECT_TRUE(seglr.crossesLine(11, -5, 11, 5, ix, iy, true));
  EXPECT_NEAR(ix, 11.0, kGeomTol);
  EXPECT_NEAR(iy, 0.0, kGeomTol);
  EXPECT_TRUE(seglr.crossesLine(11, -5, 11, 5, ix, iy, false));
  EXPECT_NEAR(ix, 11.0, kGeomTol);
  EXPECT_NEAR(iy, 0.0, kGeomTol);

  EXPECT_TRUE(seglr.crossesLine(5, -5, 5, 5, ix, iy, false));
  EXPECT_NEAR(ix, 5.0, kGeomTol);
  EXPECT_NEAR(iy, 0.0, kGeomTol);
  EXPECT_TRUE(seglr.crossesLine(5, -5, 5, 5, ix, iy, true));
  EXPECT_NEAR(ix, 5.0, kGeomTol);
  EXPECT_NEAR(iy, 0.0, kGeomTol);
}

// Covers seglr behavior: translates reflects and rotates around first stem vertex.
TEST(SeglrTest, TranslatesReflectsAndRotatesAroundFirstStemVertex)
{
  Seglr seglr;
  seglr.addVertex(0, 0);
  seglr.addVertex(0, 10);
  seglr.setRayAngle(350);

  Seglr rotated = rotateSeglr(seglr, 90);
  EXPECT_NEAR(rotated.getVX(0), 0.0, kGeomTol);
  EXPECT_NEAR(rotated.getVY(0), 0.0, kGeomTol);
  EXPECT_NEAR(rotated.getVX(1), 10.0, kLooseGeomTol);
  EXPECT_NEAR(rotated.getVY(1), 0.0, kLooseGeomTol);
  EXPECT_NEAR(rotated.getRayAngle(), 80.0, kGeomTol);

  rotated.translateTo(5, -5);
  EXPECT_NEAR(rotated.getVX(0), 5.0, kGeomTol);
  EXPECT_NEAR(rotated.getVY(0), -5.0, kGeomTol);
  EXPECT_NEAR(rotated.getVX(1), 15.0, kLooseGeomTol);
  EXPECT_NEAR(rotated.getVY(1), -5.0, kLooseGeomTol);

  rotated.reflect();
  EXPECT_NEAR(rotated.getVX(0), -5.0, kGeomTol);
  EXPECT_NEAR(rotated.getVX(1), -15.0, kLooseGeomTol);
  EXPECT_NEAR(rotated.getRayAngle(), 280.0, kGeomTol);
}

// Covers XY seglr geom utils behavior: uses cached stem CPA when valid and ray is farther.
TEST(XYSeglrGeomUtilsTest, UsesCachedStemCpaWhenValidAndRayIsFarther)
{
  XYSeglr seglr = makeTurnRay();
  seglr.setCacheCPA(1.25);
  seglr.setCacheStemCPA(7.5);
  seglr.setCacheCPAPoint(XYPoint(3, 4));

  double ix = 0;
  double iy = 0;
  double stemdist = 0;
  double cpa = distSeglrToPoly(seglr, makeBox(100, 100, 110, 110), ix, iy, stemdist);

  EXPECT_NEAR(cpa, 1.25, kGeomTol);
  EXPECT_NEAR(ix, 3.0, kGeomTol);
  EXPECT_NEAR(iy, 4.0, kGeomTol);
  EXPECT_NEAR(stemdist, 7.5, kGeomTol);
}

// Covers XY seglr geom utils behavior: ignores incomplete cache and computes stem CPA.
TEST(XYSeglrGeomUtilsTest, IgnoresIncompleteCacheAndComputesStemCpa)
{
  XYSeglr seglr = makeTurnRay();
  seglr.setCacheCPA(0.1);
  seglr.setCacheStemCPA(99);

  double ix = 0;
  double iy = 0;
  double stemdist = 0;
  double cpa = distSeglrToPoly(seglr, makeBox(4, 4, 6, 6), ix, iy, stemdist);

  EXPECT_NEAR(cpa, 4.0, kGeomTol);
  EXPECT_NEAR(ix, 6.0, kGeomTol);
  EXPECT_NEAR(iy, 0.0, kGeomTol);
  EXPECT_NEAR(stemdist, 6.0, kGeomTol);
}

// Covers XY seglr geom utils behavior: ray CPA beats cached stem CPA and extends stem distance.
TEST(XYSeglrGeomUtilsTest, RayCpaBeatsCachedStemCpaAndExtendsStemDistance)
{
  XYSeglr seglr = makeTurnRay();
  seglr.setCacheCPA(50);
  seglr.setCacheStemCPA(7);
  seglr.setCacheCPAPoint(XYPoint(7, 0));

  double ix = 0;
  double iy = 0;
  double stemdist = 0;
  double cpa = distSeglrToPoly(seglr, makeBox(8, 19, 12, 21), ix, iy, stemdist);

  EXPECT_NEAR(cpa, 0.0, kGeomTol);
  EXPECT_NEAR(ix, 10.0, kGeomTol);
  EXPECT_NEAR(iy, 19.0, kGeomTol);
  EXPECT_NEAR(stemdist, 29.0, kGeomTol);
}

// Covers XY seglr geom utils behavior: dist to point uses ray projection for single vertex seglr.
TEST(XYSeglrGeomUtilsTest, DistToPointUsesRayProjectionForSingleVertexSeglr)
{
  XYSeglr seglr(10, 0, 0);

  double ix = 0;
  double iy = 0;
  double stemdist = 0;
  double cpa = distSeglrToPoint(seglr, XYPoint(13, 20), ix, iy, stemdist);

  EXPECT_NEAR(cpa, 3.0, kGeomTol);
  EXPECT_NEAR(ix, 10.0, kGeomTol);
  EXPECT_NEAR(iy, 20.0, kGeomTol);
  EXPECT_NEAR(stemdist, 3.0, kGeomTol);
}

// Covers XY seglr geom utils behavior: dist to point falls back to ray base for point behind ray.
TEST(XYSeglrGeomUtilsTest, DistToPointFallsBackToRayBaseForPointBehindRay)
{
  XYSeglr seglr(10, 0, 0);

  double ix = 0;
  double iy = 0;
  double stemdist = 0;
  double cpa = distSeglrToPoint(seglr, XYPoint(10, -4), ix, iy, stemdist);

  EXPECT_NEAR(cpa, 4.0, kGeomTol);
  EXPECT_NEAR(ix, 10.0, kGeomTol);
  EXPECT_NEAR(iy, 0.0, kGeomTol);
  EXPECT_NEAR(stemdist, 4.0, kGeomTol);
}
