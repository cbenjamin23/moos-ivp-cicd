#include <gtest/gtest.h>

#include <cmath>

#include "GeometryTestUtils.h"
#include "NumericAssertions.h"
#include "XYFormatUtilsSegl.h"

// Covers XY format utils segl behavior: parses waypoint style pts spec with label.
TEST(XYFormatUtilsSeglTest, ParsesWaypointStylePtsSpecWithLabel)
{
  XYSegList segl = stringStandard2SegList("pts={0,0:50,0:100,25},label=survey_line,edge_color=yellow");

  ASSERT_TRUE(segl.valid());
  ASSERT_EQ(segl.size(), 3u);
  EXPECT_EQ(segl.get_label(), "survey_line");
  EXPECT_NEAR(segl.length(), 50.0 + std::hypot(50.0, 25.0), kGeomTol);
  EXPECT_EQ(segl.get_color_str("edge"), "yellow");
}

// Covers XY format utils segl behavior: parses classic BHV waypoint mission point list.
TEST(XYFormatUtilsSeglTest, ParsesClassicBHVWaypointMissionPointList)
{
  XYSegList segl = string2SegList("60,-40 : 60,-160 : 150,-160 : 180,-100 : 150,-40");

  ASSERT_TRUE(segl.valid());
  ASSERT_EQ(segl.size(), 5u);
  EXPECT_NEAR(segl.get_vx(0), 60.0, kGeomTol);
  EXPECT_NEAR(segl.get_vy(0), -40.0, kGeomTol);
  EXPECT_NEAR(segl.get_vx(2), 150.0, kGeomTol);
  EXPECT_NEAR(segl.get_vy(2), -160.0, kGeomTol);
  EXPECT_NEAR(segl.get_vx(4), 150.0, kGeomTol);
  EXPECT_NEAR(segl.get_vy(4), -40.0, kGeomTol);
  EXPECT_NEAR(segl.length(),
              120.0 + 90.0 + std::hypot(30.0, 60.0) + std::hypot(30.0, 60.0),
              kLooseGeomTol);
}

// Covers XY format utils segl behavior: parses mission transit label and wall payloads.
TEST(XYFormatUtilsSeglTest, ParsesMissionTransitLabelAndWallPayloads)
{
  XYSegList transit = string2SegList("label,transit:190,25:155,-20:45,-85:-40,-100");

  ASSERT_TRUE(transit.valid());
  ASSERT_EQ(transit.size(), 4u);
  EXPECT_EQ(transit.get_label(), "transit");
  EXPECT_NEAR(transit.get_vx(0), 190.0, kGeomTol);
  EXPECT_NEAR(transit.get_vy(3), -100.0, kGeomTol);
  EXPECT_GT(transit.length(), 260.0);

  XYSegList wall = string2SegList("pts={0,-72:47,-72:43,-89:40,-100},label=west");
  ASSERT_TRUE(wall.valid());
  ASSERT_EQ(wall.size(), 4u);
  EXPECT_EQ(wall.get_label(), "west");
  EXPECT_NEAR(wall.length(), 47.0 + std::hypot(4.0, 17.0) + std::hypot(3.0, 11.0), kLooseGeomTol);
}

// Covers XY format utils segl behavior: parses single point return and station keeping routes.
TEST(XYFormatUtilsSeglTest, ParsesSinglePointReturnAndStationKeepingRoutes)
{
  XYSegList return_point = string2SegList("0,-20");

  ASSERT_TRUE(return_point.valid());
  ASSERT_EQ(return_point.size(), 1u);
  EXPECT_NEAR(return_point.length(), 0.0, kGeomTol);
  EXPECT_NEAR(return_point.get_dist_point(50).x(), 0.0, kGeomTol);
  EXPECT_NEAR(return_point.get_dist_point(50).y(), -20.0, kGeomTol);
  EXPECT_EQ(return_point.closest_vertex(100, 100), 0u);
  EXPECT_EQ(return_point.closest_segment(100, 100), 0u);

  XYSegList view = string2SegList("pts={0,-20},label=return_point,edge_color=yellow,vertex_size=4");
  ASSERT_TRUE(view.valid());
  EXPECT_EQ(view.get_label(), "return_point");
  EXPECT_EQ(view.get_color_str("edge"), "yellow");
  EXPECT_NEAR(view.get_vertex_size(), 4.0, kGeomTol);
}

// Covers XY format utils segl behavior: parses standard pts with XY fields z and vertex properties.
TEST(XYFormatUtilsSeglTest, ParsesStandardPtsWithXYFieldsZAndVertexProperties)
{
  XYSegList segl = string2SegList(
      "pts={x=0,y=0,z=2,entry_gate:x=50,y=0,z=3,exit_gate},label=tagged_lane,source=helm");

  ASSERT_TRUE(segl.valid());
  ASSERT_EQ(segl.size(), 2u);
  EXPECT_EQ(segl.get_label(), "tagged_lane");
  EXPECT_EQ(segl.get_source(), "helm");
  EXPECT_NEAR(segl.get_vx(0), 0.0, kGeomTol);
  EXPECT_NEAR(segl.get_vy(0), 0.0, kGeomTol);
  EXPECT_NEAR(segl.get_vz(0), 2.0, kGeomTol);
  EXPECT_EQ(segl.get_vprop(0), "entry_gate");
  EXPECT_NEAR(segl.get_vz(1), 3.0, kGeomTol);
  EXPECT_EQ(segl.get_vprop(1), "exit_gate");
}

// Covers XY format utils segl behavior: parses abbreviated and deprecated point list syntax.
TEST(XYFormatUtilsSeglTest, ParsesAbbreviatedAndDeprecatedPointListSyntax)
{
  XYSegList abbreviated = stringAbbreviated2SegList("label,abbr_route:0,0:10,0,3:20,5");

  ASSERT_TRUE(abbreviated.valid());
  ASSERT_EQ(abbreviated.size(), 3u);
  EXPECT_EQ(abbreviated.get_label(), "abbr_route");
  EXPECT_NEAR(abbreviated.get_vz(1), 3.0, kGeomTol);

  XYSegList deprecated = string2SegList("points:0,0:10,0:20,5");
  ASSERT_TRUE(deprecated.valid());
  EXPECT_EQ(deprecated.size(), 3u);
}

// Covers XY format utils segl behavior: parses inactive deletion payload without vertices.
TEST(XYFormatUtilsSeglTest, ParsesInactiveDeletionPayloadWithoutVertices)
{
  XYSegList segl = string2SegList("label=erase_me,active=false");

  EXPECT_TRUE(segl.valid());
  EXPECT_FALSE(segl.active());
  EXPECT_EQ(segl.size(), 0u);
  EXPECT_EQ(segl.get_spec(), "active=false,label=erase_me");
  EXPECT_EQ(segl.get_spec_inactive(), "pts={0,0:9,0:0,9},active=false,label=erase_me");
  EXPECT_EQ(getSeglSpecInactive("erase_me"), "pts={0,0:9,0:0,9},active=false,label=erase_me");
}

// Covers XY format utils segl behavior: parses lawnmower pattern used by survey missions.
TEST(XYFormatUtilsSeglTest, ParsesLawnmowerPatternUsedBySurveyMissions)
{
  XYSegList segl = stringLawnmower2SegList(
      "x=0,y=0,width=40,height=20,degs=0,lane_width=10,"
      "startx=-20,starty=10,rows=north-south,label=survey,source=pSearchGrid,"
      "edge_color=white,vertex_color=green,edge_size=2,vertex_size=3,active=true");

  ASSERT_TRUE(segl.valid());
  EXPECT_GT(segl.size(), 2u);
  EXPECT_GT(segl.length(), 40.0);
  EXPECT_EQ(segl.get_label(), "survey");
  EXPECT_EQ(segl.get_source(), "");
  EXPECT_TRUE(segl.active());
  EXPECT_EQ(segl.get_color_str("edge"), "white");
  EXPECT_EQ(segl.get_color_str("vertex"), "green");
  EXPECT_NEAR(segl.get_edge_size(), 2.0, kGeomTol);
  EXPECT_NEAR(segl.get_vertex_size(), 3.0, kGeomTol);
}

// Covers XY format utils segl behavior: filters inactive generated lawnmower payload at top level.
TEST(XYFormatUtilsSeglTest, FiltersInactiveGeneratedLawnmowerPayloadAtTopLevel)
{
  XYSegList segl = string2SegList(
      "format=lawnmower,x=0,y=0,width=40,height=20,swath=10,active=false,label=inactive_survey");

  EXPECT_EQ(segl.size(), 0u);
}

// Covers XY format utils segl behavior: parses zig zag pattern for maneuver test routes.
TEST(XYFormatUtilsSeglTest, ParsesZigZagPatternForManeuverTestRoutes)
{
  XYSegList segl = stringZigZag2SegList("0,0,90,100,20,10,0.1");

  ASSERT_TRUE(segl.valid());
  EXPECT_GT(segl.size(), 4u);
  EXPECT_NEAR(segl.get_vx(0), 0.0, kGeomTol);
  EXPECT_NEAR(segl.get_vy(0), 0.0, kGeomTol);
  EXPECT_GT(segl.length(), 100.0);
}

// Covers XY format utils segl behavior: parses bow tie pattern for survey coverage routes.
TEST(XYFormatUtilsSeglTest, ParsesBowTiePatternForSurveyCoverageRoutes)
{
  XYSegList segl = stringBowTie2SegList("x=0,y=0,height=80,wid1=10,wid2=20,wid3=30,startx=40,starty=40,label=bowtie");

  ASSERT_TRUE(segl.valid());
  ASSERT_EQ(segl.size(), 10u);
  EXPECT_EQ(segl.get_label(), "bowtie");
  EXPECT_NEAR(segl.get_vy(0), -40.0, kGeomTol);
  EXPECT_GT(segl.length(), 200.0);
}

// Covers XY format utils segl behavior: rejects malformed generated patterns and point lists.
TEST(XYFormatUtilsSeglTest, RejectsMalformedGeneratedPatternsAndPointLists)
{
  EXPECT_EQ(string2SegList("format=zigzag,startx=0").size(), 0u);
  EXPECT_EQ(string2SegList("zigzag:0,0,90,100,-20,10").size(), 0u);
  EXPECT_EQ(string2SegList("format=lawnmower,x=0,y=0,width=40,height=20").size(), 0u);
  EXPECT_EQ(string2SegList("format=bowtie,x=0,y=0,height=80,wid1=10,wid2=20").size(), 0u);
  EXPECT_EQ(string2SegList("pts={0,0:bad,5},label=bad").size(), 0u);
  EXPECT_EQ(string2SegList("pts=0,0:1,1},label=missing_open_brace").size(), 0u);
  EXPECT_EQ(string2SegList("pts={},label=empty").size(), 0u);
  EXPECT_EQ(string2SegList("0,0:bad_token").size(), 0u);
}

// Covers XY format utils segl behavior: serializes transit lane as pts payload.
TEST(XYFormatUtilsSeglTest, SerializesTransitLaneAsPtsPayload)
{
  XYSegList lane = makeTransitLane();
  lane.set_label("transit");

  std::string spec = lane.get_spec();
  EXPECT_TRUE(stringContains(spec, "pts={"));
  EXPECT_TRUE(stringContains(spec, "0,0"));
  EXPECT_TRUE(stringContains(spec, "100,25"));
  EXPECT_TRUE(stringContains(spec, "label=transit"));
}

// Covers XY seg list behavior: round trips contact behavior bearing line payloads.
TEST(XYSegListTest, RoundTripsContactBehaviorBearingLinePayloads)
{
  // IvPContactBehavior posts a two-point bearing line from ownship to contact
  // on VIEW_SEGLIST, with duration/time metadata for pMarineViewer expiry.
  XYSegList bearing_line;
  bearing_line.set_active(true);
  bearing_line.add_vertex(-12.5, 40.25);
  bearing_line.add_vertex(80.75, -30.5);
  bearing_line.set_label("abe_avdcolregs");
  bearing_line.set_color("label", "off");
  bearing_line.set_color("edge", "red");
  bearing_line.set_duration(100);
  bearing_line.set_time(77.25);

  XYSegList parsed = string2SegList(bearing_line.get_spec());

  ASSERT_TRUE(parsed.valid());
  ASSERT_EQ(parsed.size(), 2u);
  EXPECT_NEAR(parsed.get_vx(0), -12.5, kGeomTol);
  EXPECT_NEAR(parsed.get_vy(0), 40.2, kGeomTol);
  EXPECT_NEAR(parsed.get_vx(1), 80.8, kGeomTol);
  EXPECT_NEAR(parsed.get_vy(1), -30.5, kGeomTol);
  EXPECT_EQ(parsed.get_label(), "abe_avdcolregs");
  EXPECT_EQ(parsed.get_color_str("label"), "invisible");
  EXPECT_EQ(parsed.get_color_str("edge"), "red");
  EXPECT_TRUE(parsed.duration_set());
  EXPECT_NEAR(parsed.get_duration(), 100.0, kGeomTol);
  EXPECT_TRUE(parsed.time_set());
  EXPECT_NEAR(parsed.get_time(), 77.25, kGeomTol);
  EXPECT_TRUE(parsed.active());

  XYSegList inactive = string2SegList(bearing_line.get_spec_inactive());
  ASSERT_TRUE(inactive.valid());
  EXPECT_EQ(inactive.get_label(), "abe_avdcolregs");
  EXPECT_FALSE(inactive.active());
}

// Covers XY seg list behavior: round trips fix turn radial visualization payload.
TEST(XYSegListTest, RoundTripsFixTurnRadialVisualizationPayload)
{
  // BHV_FixTurn posts radial diameter segments with labels like abeft7 and
  // later clears those labels through getSeglSpecInactive.
  XYSegList radial;
  radial.add_vertex(-20, -10);
  radial.add_vertex(30, 15);
  radial.set_label("abeft7");
  radial.set_label_color("off");
  radial.set_edge_color("gray70");
  radial.set_vertex_color("light_green");
  radial.set_vertex_size(5);
  radial.set_duration(60);

  XYSegList parsed = string2SegList(radial.get_spec());

  ASSERT_TRUE(parsed.valid());
  ASSERT_EQ(parsed.size(), 2u);
  EXPECT_EQ(parsed.get_label(), "abeft7");
  EXPECT_EQ(parsed.get_color_str("label"), "invisible");
  EXPECT_EQ(parsed.get_color_str("edge"), "gray70");
  EXPECT_EQ(parsed.get_color_str("vertex"), "light_green");
  EXPECT_TRUE(parsed.vertex_size_set());
  EXPECT_NEAR(parsed.get_vertex_size(), 5.0, kGeomTol);
  EXPECT_TRUE(parsed.duration_set());
  EXPECT_NEAR(parsed.get_duration(), 60.0, kGeomTol);

  XYSegList erased = string2SegList(getSeglSpecInactive("abeft7"));
  ASSERT_TRUE(erased.valid());
  EXPECT_EQ(erased.get_label(), "abeft7");
  EXPECT_FALSE(erased.active());
}

// Covers XY seg list behavior: computes route metrics and points along waypoint track.
TEST(XYSegListTest, ComputesRouteMetricsAndPointsAlongWaypointTrack)
{
  XYSegList lane = makeTransitLane();

  ASSERT_EQ(lane.size(), 3u);
  EXPECT_TRUE(lane.valid());
  EXPECT_NEAR(lane.length(), 50.0 + std::hypot(50.0, 25.0), kGeomTol);
  EXPECT_NEAR(lane.length(1), std::hypot(50.0, 25.0), kGeomTol);
  EXPECT_NEAR(lane.get_min_x(), 0.0, kGeomTol);
  EXPECT_NEAR(lane.get_max_x(), 100.0, kGeomTol);
  EXPECT_NEAR(lane.get_min_y(), 0.0, kGeomTol);
  EXPECT_NEAR(lane.get_max_y(), 25.0, kGeomTol);
  EXPECT_NEAR(lane.get_center_x(), 50.0, kGeomTol);
  EXPECT_NEAR(lane.get_center_y(), 12.5, kGeomTol);
  EXPECT_NEAR(lane.get_avg_x(), 50.0, kGeomTol);
  EXPECT_NEAR(lane.get_avg_y(), 25.0 / 3.0, kGeomTol);

  XYPoint first = lane.get_first_point();
  EXPECT_TRUE(first.valid());
  EXPECT_NEAR(first.x(), 0.0, kGeomTol);
  EXPECT_NEAR(first.y(), 0.0, kGeomTol);

  XYPoint middle = lane.get_point(1);
  EXPECT_TRUE(middle.valid());
  EXPECT_NEAR(middle.x(), 50.0, kGeomTol);
  EXPECT_NEAR(middle.y(), 0.0, kGeomTol);

  XYPoint last = lane.get_last_point();
  EXPECT_TRUE(last.valid());
  EXPECT_NEAR(last.x(), 100.0, kGeomTol);
  EXPECT_NEAR(last.y(), 25.0, kGeomTol);

  XYPoint center = lane.get_center_pt();
  EXPECT_NEAR(center.x(), 50.0, kGeomTol);
  EXPECT_NEAR(center.y(), 12.5, kGeomTol);

  XYPoint centroid = lane.get_centroid_pt();
  EXPECT_NEAR(centroid.x(), 50.0, kGeomTol);
  EXPECT_NEAR(centroid.y(), 25.0 / 3.0, kGeomTol);

  EXPECT_FALSE(lane.get_point(99).valid());
  EXPECT_FALSE(XYSegList().get_first_point().valid());
  EXPECT_FALSE(XYSegList().get_last_point().valid());

  XYPoint start = lane.get_dist_point(-1);
  EXPECT_NEAR(start.x(), 0.0, kGeomTol);
  EXPECT_NEAR(start.y(), 0.0, kGeomTol);

  XYPoint turn = lane.get_dist_point(50);
  EXPECT_NEAR(turn.x(), 50.0, kGeomTol);
  EXPECT_NEAR(turn.y(), 0.0, kGeomTol);
  EXPECT_NEAR(turn.z(), 90.0, kGeomTol);

  XYPoint after_turn = lane.get_dist_point(50.0 + std::hypot(10.0, 5.0));
  EXPECT_NEAR(after_turn.x(), 60.0, kLooseGeomTol);
  EXPECT_NEAR(after_turn.y(), 5.0, kLooseGeomTol);
  EXPECT_NEAR(after_turn.z(), 63.4349488229, kLooseGeomTol);

  XYPoint end = lane.get_dist_point(999);
  EXPECT_NEAR(end.x(), 100.0, kGeomTol);
  EXPECT_NEAR(end.y(), 25.0, kGeomTol);
}

// Covers XY seg list behavior: finds closest vertices segments and distances for route monitoring.
TEST(XYSegListTest, FindsClosestVerticesSegmentsAndDistancesForRouteMonitoring)
{
  XYSegList lane = makeTransitLane();

  EXPECT_EQ(lane.closest_vertex(48, 2), 1u);
  EXPECT_EQ(lane.closest_segment(25, 10, false), 0u);
  EXPECT_EQ(lane.closest_segment(90, 20, false), 1u);
  EXPECT_NEAR(lane.dist_to_point(25, 10), 10.0, kGeomTol);
  EXPECT_NEAR(lane.dist_to_point(75, 12.5), 0.0, kGeomTol);
  EXPECT_NEAR(lane.dist_to_ctr(50, 12.5), 0.0, kGeomTol);
  EXPECT_GT(lane.max_dist_to_ctr(), 50.0);

  XYSegList empty;
  EXPECT_FALSE(empty.valid());
  EXPECT_NEAR(empty.length(), 0.0, kGeomTol);
  EXPECT_NEAR(empty.dist_to_point(10, 10), 0.0, kGeomTol);
  EXPECT_EQ(empty.closest_vertex(10, 10), 0u);
  EXPECT_EQ(empty.closest_segment(10, 10), 0u);
}

// Covers XY seg list behavior: closest segment can use implicit loop segment for closed viewer shapes.
TEST(XYSegListTest, ClosestSegmentCanUseImplicitLoopSegmentForClosedViewerShapes)
{
  XYSegList open_square = string2SegList("pts={0,0:10,0:10,10:0,10}");

  ASSERT_TRUE(open_square.valid());
  EXPECT_EQ(open_square.closest_segment(0, 5, true), 3u);
  EXPECT_EQ(open_square.closest_segment(0, 5, false), 0u);
  EXPECT_FALSE(open_square.segs_cross(true));
  EXPECT_FALSE(open_square.segs_cross(false));
  EXPECT_NEAR(open_square.dist_to_point(0, 5), 5.0, kGeomTol);
}

// Covers XY seg list behavior: degenerate repeated waypoints retain literal length and distance behavior.
TEST(XYSegListTest, DegenerateRepeatedWaypointsRetainLiteralLengthAndDistanceBehavior)
{
  XYSegList route;
  route.add_vertex(0, 0);
  route.add_vertex(0, 0);
  route.add_vertex(10, 0);

  ASSERT_TRUE(route.valid());
  EXPECT_NEAR(route.length(), 10.0, kGeomTol);
  EXPECT_NEAR(route.length(0), 10.0, kGeomTol);
  EXPECT_NEAR(route.length(1), 10.0, kGeomTol);
  EXPECT_NEAR(route.length(2), 0.0, kGeomTol);
  EXPECT_NEAR(route.dist_to_point(0, 5), 5.0, kGeomTol);
  EXPECT_EQ(route.closest_vertex(0, 0), 0u);
  EXPECT_EQ(route.closest_segment(0, 1, false), 0u);
}

// Covers XY seg list behavior: edits vertices using closest point and segment rules.
TEST(XYSegListTest, EditsVerticesUsingClosestPointAndSegmentRules)
{
  XYSegList route;
  route.add_vertex(0, 0);
  route.add_vertex(10, 0);
  route.insert_vertex(5, 2, 0, "mid");

  ASSERT_EQ(route.size(), 3u);
  EXPECT_NEAR(route.get_vx(1), 5.0, kGeomTol);
  EXPECT_NEAR(route.get_vy(1), 2.0, kGeomTol);
  EXPECT_EQ(route.get_vprop(1), "mid");

  route.alter_vertex(5, 1, 0, "alt");
  EXPECT_NEAR(route.get_vx(1), 5.0, kGeomTol);
  EXPECT_NEAR(route.get_vy(1), 1.0, kGeomTol);
  EXPECT_EQ(route.get_vprop(1), "alt");

  route.mod_vertex(1, 5, 0, 3, "gate");
  EXPECT_NEAR(route.get_vz(1), 3.0, kGeomTol);
  EXPECT_EQ(route.get_vprop(1), "gate");

  route.delete_vertex(5, 0);
  ASSERT_EQ(route.size(), 2u);
  EXPECT_NEAR(route.length(), 10.0, kGeomTol);

  route.pop_last_vertex();
  EXPECT_EQ(route.size(), 1u);
  route.delete_vertex(99);
  EXPECT_EQ(route.size(), 1u);
}

// Covers XY seg list behavior: applies route transforms for viewable waypoint lists.
TEST(XYSegListTest, AppliesRouteTransformsForViewableWaypointLists)
{
  XYSegList route;
  route.add_vertex(0, 0, 0, "start");
  route.add_vertex(10, 0);
  route.add_vertex(10, 10);

  route.shift_horz(5);
  route.shift_vert(-2);
  EXPECT_NEAR(route.get_vx(0), 5.0, kGeomTol);
  EXPECT_NEAR(route.get_vy(0), -2.0, kGeomTol);
  EXPECT_NEAR(route.get_center_x(), 10.0, kGeomTol);
  EXPECT_NEAR(route.get_center_y(), 3.0, kGeomTol);

  route.reverse();
  EXPECT_NEAR(route.get_vx(0), 15.0, kGeomTol);
  EXPECT_NEAR(route.get_vy(0), 8.0, kGeomTol);
  EXPECT_EQ(route.get_vprop(2), "start");
  EXPECT_TRUE(route.is_clockwise());

  route.new_center(0, 0);
  EXPECT_NEAR(route.get_center_x(), 0.0, kGeomTol);
  EXPECT_NEAR(route.get_center_y(), 0.0, kGeomTol);
  EXPECT_NEAR(route.get_vx(0), 5.0, kGeomTol);
  EXPECT_NEAR(route.get_vy(0), 5.0, kGeomTol);

  route.apply_snap(2);
  EXPECT_NEAR(route.get_vx(0), 6.0, kGeomTol);
  EXPECT_NEAR(route.get_vy(0), 6.0, kGeomTol);
}

// Covers XY seg list behavior: rotates and grows routes around centers.
TEST(XYSegListTest, RotatesAndGrowsRoutesAroundCenters)
{
  XYSegList segment;
  segment.add_vertex(0, 0);
  segment.add_vertex(10, 0);
  segment.rotate(90, 0, 0);
  EXPECT_NEAR(segment.get_vx(0), 0.0, kGeomTol);
  EXPECT_NEAR(segment.get_vy(0), 0.0, kGeomTol);
  EXPECT_NEAR(segment.get_vx(1), 0.0, kLooseGeomTol);
  EXPECT_NEAR(segment.get_vy(1), -10.0, kLooseGeomTol);

  XYSegList box = string2SegList("pts={0,0:10,0:10,10:0,10}");
  box.grow_by_pct(0.5);
  EXPECT_NEAR(box.get_min_x(), -2.5, kGeomTol);
  EXPECT_NEAR(box.get_max_x(), 12.5, kGeomTol);
  EXPECT_NEAR(box.get_min_y(), -2.5, kGeomTol);
  EXPECT_NEAR(box.get_max_y(), 12.5, kGeomTol);

  box.new_centroid(0, 0);
  EXPECT_NEAR(box.get_centroid_x(), 0.0, kGeomTol);
  EXPECT_NEAR(box.get_centroid_y(), 0.0, kGeomTol);
}

// Covers XY seg list behavior: detects self crossing when interpreted as closed shape.
TEST(XYSegListTest, DetectsSelfCrossingWhenInterpretedAsClosedShape)
{
  XYSegList bowtie;
  bowtie.add_vertex(0, 0);
  bowtie.add_vertex(10, 10);
  bowtie.add_vertex(0, 10);
  bowtie.add_vertex(10, 0);

  EXPECT_TRUE(bowtie.segs_cross());
  EXPECT_TRUE(bowtie.segs_cross(false));
  // A self-intersecting, zero-signed-area bowtie has no unique winding.
  // Check orientation on the non-degenerate square below.

  XYSegList square = string2SegList("pts={0,0:10,0:10,10:0,10}");
  EXPECT_FALSE(square.segs_cross());
  EXPECT_FALSE(square.is_clockwise());
  square.reverse();
  EXPECT_TRUE(square.is_clockwise());
}

// Covers XY seg list behavior: serializes points labels and inactive duration payloads.
TEST(XYSegListTest, SerializesPointsLabelsAndInactiveDurationPayloads)
{
  XYSegList route;
  route.add_vertex(1.23456, 2.34567, 0, "entry");
  route.add_vertex(9.87654, 8.76543, 3, "exit");
  route.set_label("route");
  route.set_duration(0);

  EXPECT_EQ(route.get_spec_pts_label(2), "pts={1.23,2.35,0,entry:9.88,8.77,3,exit},label=route");
  EXPECT_EQ(route.get_spec_pts(2), "pts={1.23,2.35,0,entry:9.88,8.77,3,exit}");
  EXPECT_EQ(route.get_spec_inactive(), "pts={0,0:9,0:0,9},active=false,label=route,duration=0");

  std::string active_spec = route.get_spec(2, "active=true");
  EXPECT_TRUE(stringContains(active_spec, "active=true"));
  EXPECT_TRUE(stringContains(active_spec, "duration=0"));
}
