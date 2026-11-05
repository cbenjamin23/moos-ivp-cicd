#include <gtest/gtest.h>

#include <vector>

#include "GeometryTestUtils.h"
#include "LoiterEngine.h"
#include "NumericAssertions.h"
#include "XYFormatUtilsPoly.h"
#include "XYPolygon.h"

namespace {

XYPolygon loiterSquare()
{
  XYPolygon poly = string2Poly("pts={0,0:20,0:20,20:0,20},label=loiter_box");
  EXPECT_TRUE(poly.is_convex());
  return poly;
}

XYPolygon concaveLoiterPoly()
{
  XYPolygon poly;
  poly.add_vertex(0, 0);
  poly.add_vertex(20, 0);
  poly.add_vertex(10, 10);
  poly.add_vertex(20, 20);
  poly.add_vertex(0, 20);
  return poly;
}

}  // namespace

// Covers loiter engine behavior: initializes and mutates loiter polygon state.
TEST(LoiterEngineTest, InitializesAndMutatesLoiterPolygonState)
{
  LoiterEngine engine;
  EXPECT_TRUE(engine.getClockwise());
  EXPECT_DOUBLE_EQ(engine.getSpiralFactor(), -2);

  engine.setPoly(loiterSquare());
  EXPECT_EQ(engine.getPolyPts(), 4u);
  EXPECT_NEAR(engine.getCenterX(), 10.0, kGeomTol);
  EXPECT_NEAR(engine.getCenterY(), 10.0, kGeomTol);

  engine.setCenter(30, -5);
  EXPECT_NEAR(engine.getCenterX(), 30.0, kGeomTol);
  EXPECT_NEAR(engine.getCenterY(), -5.0, kGeomTol);
}

// Covers loiter engine behavior: set center translates MOOS loiter polygon without changing shape.
TEST(LoiterEngineTest, SetCenterTranslatesMoosLoiterPolygonWithoutChangingShape)
{
  LoiterEngine engine;
  engine.setPoly(loiterSquare());

  engine.setCenter(100, -50);
  XYPolygon shifted = engine.getPolygon();

  ASSERT_EQ(shifted.size(), 4u);
  EXPECT_NEAR(engine.getCenterX(), 100.0, kGeomTol);
  EXPECT_NEAR(engine.getCenterY(), -50.0, kGeomTol);
  EXPECT_NEAR(shifted.get_vx(0), 90.0, kGeomTol);
  EXPECT_NEAR(shifted.get_vy(0), -60.0, kGeomTol);
  EXPECT_NEAR(shifted.get_vx(1), 110.0, kGeomTol);
  EXPECT_NEAR(shifted.get_vy(1), -60.0, kGeomTol);
  EXPECT_NEAR(shifted.get_vx(2), 110.0, kGeomTol);
  EXPECT_NEAR(shifted.get_vy(2), -40.0, kGeomTol);
  EXPECT_NEAR(shifted.get_vx(3), 90.0, kGeomTol);
  EXPECT_NEAR(shifted.get_vy(3), -40.0, kGeomTol);
}

// Covers loiter engine behavior: set clockwise reorients polygon traversal.
TEST(LoiterEngineTest, SetClockwiseReorientsPolygonTraversal)
{
  LoiterEngine engine;
  engine.setPoly(loiterSquare());

  engine.setClockwise(true);
  EXPECT_TRUE(engine.getClockwise());
  EXPECT_TRUE(engine.getPolygon().is_clockwise());

  engine.setClockwise(false);
  EXPECT_FALSE(engine.getClockwise());
  EXPECT_FALSE(engine.getPolygon().is_clockwise());
}

// Covers loiter engine behavior: acquire vertex rejects invalid polygon.
TEST(LoiterEngineTest, AcquireVertexRejectsInvalidPolygon)
{
  LoiterEngine engine;

  EXPECT_EQ(engine.acquireVertex(90, 0, 0), -1);

  engine.setPoly(concaveLoiterPoly());
  EXPECT_EQ(engine.acquireVertex(90, 5, 5), -1);
  EXPECT_EQ(engine.acquireVertex(90, -10, 5), -1);
}

// Covers loiter engine behavior: acquires inside vertex nearest current heading.
TEST(LoiterEngineTest, AcquiresInsideVertexNearestCurrentHeading)
{
  LoiterEngine engine;
  engine.setPoly(loiterSquare());

  EXPECT_EQ(engine.acquireVertex(90, 10, 10), 1);
  EXPECT_EQ(engine.acquireVertex(270, 10, 10), 0);
}

// Covers loiter engine behavior: inside acquisition pins heading wrap and quadrants.
TEST(LoiterEngineTest, InsideAcquisitionPinsHeadingWrapAndQuadrants)
{
  LoiterEngine engine;
  engine.setPoly(loiterSquare());

  // When ownship is inside the loiter polygon, acquisition is driven by current
  // heading quadrant. The -1 and 360 cases pin the wrap behavior at north.
  const std::vector<std::pair<double, int>> cases = {
      {-1, 3}, {0, 2},   {45, 2},  {89, 2},  {90, 1},
      {91, 1}, {135, 1}, {180, 0}, {225, 0}, {270, 0},
      {315, 3}, {359, 3}, {360, 2}};

  for(const auto& test_case : cases) {
    EXPECT_EQ(engine.acquireVertex(test_case.first, 10, 10), test_case.second)
        << "heading=" << test_case.first;
  }
}

// Covers loiter engine behavior: outside acquisition depends on traversal direction.
TEST(LoiterEngineTest, OutsideAcquisitionDependsOnTraversalDirection)
{
  LoiterEngine engine;
  engine.setPoly(loiterSquare());

  engine.setClockwise(true);
  int clockwise_entry = engine.acquireVertex(0, 10, -20);
  engine.setClockwise(false);
  int counter_entry = engine.acquireVertex(0, 10, -20);

  EXPECT_GE(clockwise_entry, 0);
  EXPECT_GE(counter_entry, 0);
  EXPECT_LT(clockwise_entry, static_cast<int>(engine.getPolyPts()));
  EXPECT_LT(counter_entry, static_cast<int>(engine.getPolyPts()));
  EXPECT_NE(clockwise_entry, counter_entry);
}

// Covers loiter engine behavior: outside acquisition pins visible vertices around loiter polygon.
TEST(LoiterEngineTest, OutsideAcquisitionPinsVisibleVerticesAroundLoiterPolygon)
{
  LoiterEngine engine;
  engine.setPoly(loiterSquare());

  struct Case {
    double osx;
    double osy;
    int clockwise_vertex;
    int counterclockwise_vertex;
  };

  const std::vector<Case> cases = {
      {10, -20, 3, 1}, {30, 10, 2, 2},  {10, 40, 1, 3},
      {-20, 10, 0, 0}, {-20, -20, 0, 1}, {40, -20, 3, 2},
      {40, 40, 2, 3}, {-20, 40, 1, 0}};

  for(const Case& test_case : cases) {
    engine.setClockwise(true);
    EXPECT_EQ(engine.acquireVertex(0, test_case.osx, test_case.osy),
              test_case.clockwise_vertex)
        << "clockwise approach from " << test_case.osx << "," << test_case.osy;

    engine.setClockwise(false);
    EXPECT_EQ(engine.acquireVertex(0, test_case.osx, test_case.osy),
              test_case.counterclockwise_vertex)
        << "counterclockwise approach from " << test_case.osx << ","
        << test_case.osy;
  }
}

// Covers loiter engine behavior: reset clockwise best keeps clockwise for south approach current behavior.
TEST(LoiterEngineTest, ResetClockwiseBestKeepsClockwiseForSouthApproachCurrentBehavior)
{
  LoiterEngine engine;
  engine.setPoly(loiterSquare());
  engine.setClockwise(true);

  // Current resetClockwiseBest behavior keeps clockwise here even though nearby
  // headings can choose counterclockwise in the broader approach table below.
  engine.resetClockwiseBest(270, 10, -20);
  EXPECT_TRUE(engine.getClockwise());
}

// Covers loiter engine behavior: reset clockwise best leaves invalid or inside cases unchanged.
TEST(LoiterEngineTest, ResetClockwiseBestLeavesInvalidOrInsideCasesUnchanged)
{
  LoiterEngine invalid_engine;
  invalid_engine.setClockwise(false);
  invalid_engine.resetClockwiseBest(90, 10, -20);
  EXPECT_FALSE(invalid_engine.getClockwise());

  LoiterEngine inside_engine;
  inside_engine.setPoly(loiterSquare());
  inside_engine.setClockwise(false);
  inside_engine.resetClockwiseBest(90, 10, 10);
  EXPECT_FALSE(inside_engine.getClockwise());
}

// Covers loiter engine behavior: reset clockwise best chooses traversal by approach heading.
TEST(LoiterEngineTest, ResetClockwiseBestChoosesTraversalByApproachHeading)
{
  LoiterEngine engine;
  engine.setPoly(loiterSquare());

  struct Case {
    double osx;
    double osy;
    double osh;
    bool expected_clockwise;
  };

  const std::vector<Case> cases = {
      {10, -20, 225, true},
      {30, 10, 90, false},  {30, 10, 180, true},
      {10, 40, 45, true},   {10, 40, 180, false},
      {-20, 10, 0, true},   {-20, 10, 90, false},
      // Test both sides of the symmetric 45-degree approach. An exact tie
      // depends on libm rounding rather than a strictly better traversal.
      {-20, -20, 40, true}, {-20, -20, 50, false}, {40, -20, 180, true},
      {40, 40, 90, true},   {-20, 40, 315, false}};

  for(const Case& test_case : cases) {
    engine.setClockwise(true);
    engine.resetClockwiseBest(test_case.osh, test_case.osx, test_case.osy);
    EXPECT_EQ(engine.getClockwise(), test_case.expected_clockwise)
        << "heading=" << test_case.osh << " approach=" << test_case.osx << ","
        << test_case.osy;
  }
}

// Covers loiter engine behavior: mod poly radius honors minimum and spiral factor range.
TEST(LoiterEngineTest, ModPolyRadiusHonorsMinimumAndSpiralFactorRange)
{
  LoiterEngine engine;
  engine.setPoly(loiterSquare());
  const double original_radius = engine.getRadius();

  engine.modPolyRad(10);
  EXPECT_GT(engine.getRadius(), original_radius);

  engine.modPolyRad(-1000);
  EXPECT_GE(engine.getRadius(), 5.0);

  engine.setSpiralFactor(0);
  EXPECT_NEAR(engine.getSpiralFactor(), -75.0, kGeomTol);
  engine.setSpiralFactor(100);
  EXPECT_NEAR(engine.getSpiralFactor(), -1.0, kGeomTol);
}

// Covers loiter engine behavior: pins current unbounded spiral factor input behavior.
TEST(LoiterEngineTest, PinsCurrentUnboundedSpiralFactorInputBehavior)
{
  LoiterEngine engine;

  // Direct setSpiralFactor() currently transforms out-of-range input instead
  // of clamping it like modPolyRad() does.
  engine.setSpiralFactor(200);
  EXPECT_NEAR(engine.getSpiralFactor(), 73.0, kGeomTol);

  engine.setSpiralFactor(-10);
  EXPECT_NEAR(engine.getSpiralFactor(), -82.4, kGeomTol);
}
