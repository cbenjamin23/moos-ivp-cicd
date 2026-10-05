#include <gtest/gtest.h>

#include <string>

#include "XYGenPolygon.h"

namespace {

const std::string kLShape =
  "border={0,0:20,0:20,10:10,10:10,20:0,20},label=l_border # "
  "poly={0,0:20,0:20,10:0,10},label=l_lower # "
  "poly={0,10:10,10:10,20:0,20},label=l_upper";

const std::string kSquare =
  "border={0,0:20,0:20,20:0,20},label=square_border # "
  "poly={0,0:20,0:20,20:0,20},label=square_cover";

}  // namespace

// Covers generalized polygon behavior: parses a non-convex border with a
// convex cover and preserves its geometry through serialization.
TEST(XYGenPolygonTest, ParsesNonConvexBorderAndConvexCover)
{
  testing::internal::CaptureStdout();
  XYGenPolygon gpoly = stringToGenPoly(kLShape);
  testing::internal::GetCapturedStdout();

  ASSERT_TRUE(gpoly.valid());
  EXPECT_EQ(gpoly.getBorderPtsSize(), 6u);
  EXPECT_EQ(gpoly.getCoverPolyCount(), 2u);
  EXPECT_TRUE(gpoly.contains(5, 15));
  EXPECT_TRUE(gpoly.contains(15, 5));
  EXPECT_FALSE(gpoly.contains(15, 15));
  EXPECT_DOUBLE_EQ(gpoly.area(), 300);

  const std::string spec = gpoly.get_spec();
  EXPECT_NE(spec.find("border={"), std::string::npos);
  EXPECT_NE(spec.find("poly={"), std::string::npos);
}

// Covers generalized polygon behavior: rejects malformed or incomplete
// specifications rather than creating a superficially valid region.
TEST(XYGenPolygonTest, RejectsMalformedAndIncompleteSpecifications)
{
  testing::internal::CaptureStdout();
  XYGenPolygon missing_cover =
    stringToGenPoly("border={0,0:20,0:20,20:0,20}");
  XYGenPolygon wrong_prefix =
    stringToGenPoly("pts={0,0:20,0:20,20:0,20} # poly={0,0:20,0:20,20:0,20}");
  XYGenPolygon bad_vertex =
    stringToGenPoly("border={0,0:bad,0:20,20} # poly={0,0:20,0:20,20}");
  testing::internal::GetCapturedStdout();

  EXPECT_FALSE(missing_cover.valid());
  EXPECT_FALSE(wrong_prefix.valid());
  EXPECT_FALSE(bad_vertex.valid());
}

// Covers generalized polygon behavior: ray exit distances follow the actual
// concave border for points in different cover polygons.
TEST(XYGenPolygonTest, ComputesRayExitDistanceAcrossConcaveRegion)
{
  testing::internal::CaptureStdout();
  XYGenPolygon gpoly = stringToGenPoly(kLShape);
  testing::internal::GetCapturedStdout();
  ASSERT_TRUE(gpoly.valid());

  EXPECT_NEAR(gpoly.distRayToExitGP(15, 5, 0), 5, 1e-9);
  EXPECT_NEAR(gpoly.distRayToExitGP(5, 5, 0), 15, 1e-9);
  EXPECT_NEAR(gpoly.distRayToEnterGP(15, 15, 270), 5, 1e-9);
}

// Covers generalized polygon behavior: point distance retains metric units
// instead of being collapsed to a Boolean 0/1 value.
TEST(XYGenPolygonTest, ComputesMetricPointDistanceToExit)
{
  testing::internal::CaptureStdout();
  XYGenPolygon gpoly = stringToGenPoly(kSquare);
  testing::internal::GetCapturedStdout();
  ASSERT_TRUE(gpoly.valid());

  EXPECT_NEAR(gpoly.distPtToExitGP(5, 5), 5, 1e-9);
  EXPECT_NEAR(gpoly.distPtToExitGP(10, 10), 10, 1e-9);
}

// Covers generalized polygon behavior: segment validation uses the actual
// starting point (x1,y1) before measuring to the first border crossing.
TEST(XYGenPolygonTest, ComputesSegmentDistanceFromContainedStart)
{
  testing::internal::CaptureStdout();
  XYGenPolygon gpoly = stringToGenPoly(kSquare);
  testing::internal::GetCapturedStdout();
  ASSERT_TRUE(gpoly.valid());

  bool exited = false;
  EXPECT_NEAR(gpoly.distSegToExitGP(5, 5, 5, 25, exited), 15, 1e-9);
  EXPECT_TRUE(exited);
}

// A crossing or a touch must retain CPA zero; contained and disjoint paths
// retain metric clearance instead of being confused with an intersection.
TEST(XYGenPolygonTest, ComputesCPAForCrossingTouchingContainedAndDisjointSegments)
{
  XYGenPolygon gpoly = stringToGenPoly(kSquare);
  ASSERT_TRUE(gpoly.valid());
  EXPECT_DOUBLE_EQ(gpoly.cpaSegToGP(10, 10, 30, 10), 0);
  EXPECT_DOUBLE_EQ(gpoly.cpaSegToGP(10, 10, 20, 10), 0);
  EXPECT_DOUBLE_EQ(gpoly.cpaSegToGP(10, 10, 15, 10), 5);
  EXPECT_DOUBLE_EQ(gpoly.cpaSegToGP(25, 10, 30, 10), 5);

  XYSegList path;
  path.add_vertex(10, 10);
  path.add_vertex(15, 10);
  path.add_vertex(30, 10);
  EXPECT_DOUBLE_EQ(gpoly.cpaSeglToGP(path), 0);
}
