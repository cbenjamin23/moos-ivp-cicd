#include <gtest/gtest.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <limits>
#include <set>
#include <string>
#include <vector>

#include "ArtifactUtils.h"
#include "CurrentField.h"
#include "GeometryTestUtils.h"
#include "NumericAssertions.h"
#include "OpField.h"
#include "TestFileUtils.h"
#include "XYPolygon.h"
#include "XYSegList.h"
#include "XYVector.h"

namespace {

void expectVertex(const XYSegList& segl, unsigned int ix, double x, double y)
{
  ASSERT_LT(ix, segl.size());
  EXPECT_NEAR(segl.get_vx(ix), x, kLooseGeomTol);
  EXPECT_NEAR(segl.get_vy(ix), y, kLooseGeomTol);
}

XYPolygon makeSurveyBox()
{
  return makeSquarePoly(0, 0, 100, 100);
}

double parseArtifactValue(const std::string& artifact, char key)
{
  const std::string prefix(1, key);
  std::size_t pos = artifact.find(prefix + "=");
  if(pos == std::string::npos)
    return std::numeric_limits<double>::quiet_NaN();

  pos += 2;
  std::size_t end = artifact.find(',', pos);
  return std::atof(artifact.substr(pos, end - pos).c_str());
}

TempFile makeTempFieldFile(const std::string& contents)
{
  return TempFile("current_field", contents);
}

std::vector<std::string> sortedAliases(const OpField& field)
{
  std::vector<std::string> aliases = field.getPtAliases();
  std::sort(aliases.begin(), aliases.end());
  return aliases;
}

}  // namespace

// Covers artifact utils lawnmower behavior: rejects starting point outside polygon.
TEST(ArtifactUtilsLawnmowerTest, RejectsStartingPointOutsidePolygon)
{
  XYSegList path = generateLawnmower(makeSurveyBox(), 150, 50, 0, 10, true);

  EXPECT_EQ(path.size(), 0u);
  EXPECT_FALSE(path.valid());
}

// Covers artifact utils lawnmower behavior: generates clockwise north south survey swaths inside box.
TEST(ArtifactUtilsLawnmowerTest, GeneratesClockwiseNorthSouthSurveySwathsInsideBox)
{
  XYSegList path = generateLawnmower(makeSurveyBox(), 50, 50, 0, 10, true);

  ASSERT_EQ(path.size(), 6u);
  // The current rectangular boundary projection emits duplicate top-edge
  // vertices instead of alternating to the lower edge.
  expectVertex(path, 0, 50, 50);
  expectVertex(path, 1, 50, 100);
  expectVertex(path, 2, 70, 100);
  expectVertex(path, 3, 70, 100);
  expectVertex(path, 4, 90, 100);
  expectVertex(path, 5, 90, 100);
}

// Covers artifact utils lawnmower behavior: counter clockwise first turn sweeps opposite side.
TEST(ArtifactUtilsLawnmowerTest, CounterClockwiseFirstTurnSweepsOppositeSide)
{
  XYSegList path = generateLawnmower(makeSurveyBox(), 50, 50, 0, 10, false);

  ASSERT_EQ(path.size(), 6u);
  // Counter-clockwise follows the same top-edge duplicate behavior on the
  // opposite side of the starting swath.
  expectVertex(path, 0, 50, 50);
  expectVertex(path, 1, 50, 100);
  expectVertex(path, 2, 30, 100);
  expectVertex(path, 3, 30, 100);
  expectVertex(path, 4, 10, 100);
  expectVertex(path, 5, 10, 100);
}

// Covers artifact utils lawnmower behavior: oblique lawnmower keeps all vertices in polygon.
TEST(ArtifactUtilsLawnmowerTest, ObliqueLawnmowerKeepsAllVerticesInPolygon)
{
  XYSegList path = generateLawnmower(makeSurveyBox(), 50, 50, 45, 15, true);
  XYPolygon box = makeSurveyBox();

  ASSERT_GT(path.size(), 2u);
  for(unsigned int i = 0; i < path.size(); ++i) {
    const double x = path.get_vx(i);
    const double y = path.get_vy(i);
    ASSERT_TRUE(std::isfinite(x) && std::isfinite(y));
    // Rotated intersections can land a few rounding units beyond an edge.
    // Preserve containment with the shared geometry tolerance, not exact zero.
    EXPECT_TRUE(box.contains(x, y) || box.dist_to_poly(x, y) <= kGeomTol)
        << "vertex=" << i << " x=" << x << " y=" << y
        << " distance_to_boundary=" << box.dist_to_poly(x, y);
  }
}

// Covers artifact utils lawnmower behavior: full pattern combines opposite sweeps around center.
TEST(ArtifactUtilsLawnmowerTest, FullPatternCombinesOppositeSweepsAroundCenter)
{
  XYSegList path = generateLawnmowerFull(makeSurveyBox(), 0, 20);

  ASSERT_EQ(path.size(), 6u);
  // Full patterns splice the reversed opposite sweep with the forward sweep,
  // preserving duplicate edge vertices from both halves.
  expectVertex(path, 0, 10, 0);
  expectVertex(path, 1, 10, 0);
  expectVertex(path, 2, 50, 0);
  expectVertex(path, 3, 50, 100);
  expectVertex(path, 4, 90, 100);
  expectVertex(path, 5, 90, 100);
}

// Covers artifact utils artifacts behavior: generate artifacts returns unique snapped interior specs.
TEST(ArtifactUtilsArtifactsTest, GenerateArtifactsReturnsUniqueSnappedInteriorSpecs)
{
  XYPolygon box = makeSquarePoly(0, 0, 10, 10);

  std::vector<std::string> artifacts = generateArtifacts(0, 10, 0, 10, 1, 5, box);

  ASSERT_EQ(artifacts.size(), 5u);
  std::set<std::string> unique(artifacts.begin(), artifacts.end());
  EXPECT_EQ(unique.size(), artifacts.size());

  for(const std::string& artifact : artifacts) {
    EXPECT_TRUE(stringContains(artifact, "X="));
    EXPECT_TRUE(stringContains(artifact, "Y="));
    double x = parseArtifactValue(artifact, 'X');
    double y = parseArtifactValue(artifact, 'Y');
    EXPECT_TRUE(box.contains(x, y));
    EXPECT_NEAR(std::round(x), x, kGeomTol);
    EXPECT_NEAR(std::round(y), y, kGeomTol);
  }
}

// Covers current field behavior: defaults to generic inactive field.
TEST(CurrentFieldTest, DefaultsToGenericInactiveField)
{
  CurrentField field;

  EXPECT_TRUE(field.initGeodesy(42.3584, -71.08745));
  EXPECT_EQ(field.getName(), "generic_cfield");
  EXPECT_NEAR(field.getRadius(), 20.0, kGeomTol);
  EXPECT_EQ(field.size(), 0u);
  EXPECT_FALSE(field.hasActiveVertex());
  EXPECT_FALSE(field.getVector(0).valid());
  EXPECT_FALSE(field.getVMarked(0));
  EXPECT_NEAR(field.getXPos(0), 0.0, kGeomTol);
  EXPECT_NEAR(field.getYPos(0), 0.0, kGeomTol);
  EXPECT_NEAR(field.getForce(0), 0.0, kGeomTol);
  EXPECT_NEAR(field.getDirection(0), 0.0, kGeomTol);

  testing::internal::CaptureStdout();
  field.print();
  std::string out = testing::internal::GetCapturedStdout();
  EXPECT_TRUE(stringContains(out, "Current Field [generic_cfield]:"));
}

// Covers current field behavior: set radius clamps below one.
TEST(CurrentFieldTest, SetRadiusClampsBelowOne)
{
  CurrentField field;

  field.setRadius(0);
  EXPECT_NEAR(field.getRadius(), 1.0, kGeomTol);

  field.setRadius(-5);
  EXPECT_NEAR(field.getRadius(), 1.0, kGeomTol);

  field.setRadius(7.5);
  EXPECT_NEAR(field.getRadius(), 7.5, kGeomTol);
}

// Covers current field behavior: add vector tracks marked and unmarked vectors.
TEST(CurrentFieldTest, AddVectorTracksMarkedAndUnmarkedVectors)
{
  CurrentField field;
  field.addVector(XYVector(1, 2, 3, 90));
  field.addVector(XYVector(3, 4, 5, 180), true);

  ASSERT_EQ(field.size(), 2u);
  EXPECT_FALSE(field.getVMarked(0));
  EXPECT_TRUE(field.getVMarked(1));
  EXPECT_EQ(field.getVectors().size(), 2u);
  EXPECT_EQ(field.getVectorsMarked().size(), 1u);
  EXPECT_EQ(field.getVectorsUnMarked().size(), 1u);
  EXPECT_NEAR(field.getXPos(1), 3.0, kGeomTol);
  EXPECT_NEAR(field.getYPos(1), 4.0, kGeomTol);
  EXPECT_NEAR(field.getForce(1), 5.0, kGeomTol);
  EXPECT_NEAR(field.getDirection(1), 180.0, kGeomTol);
}

// Covers current field behavior: local force uses squared distance weight and averages nearby vectors.
TEST(CurrentFieldTest, LocalForceUsesSquaredDistanceWeightAndAveragesNearbyVectors)
{
  CurrentField field;
  field.setRadius(10);
  field.addVector(XYVector(0, 0, 10, 90));
  field.addVector(XYVector(5, 0, 10, 0));
  field.addVector(XYVector(20, 0, 100, 90));

  double fx = -1;
  double fy = -1;
  field.getLocalForce(0, 0, fx, fy);

  EXPECT_NEAR(fx, 5.0, kGeomTol);
  EXPECT_NEAR(fy, 1.25, kGeomTol);
}

// Covers current field behavior: local force ignores vectors at or beyond radius.
TEST(CurrentFieldTest, LocalForceIgnoresVectorsAtOrBeyondRadius)
{
  CurrentField field;
  field.setRadius(10);
  field.addVector(XYVector(10, 0, 10, 90));

  double fx = -1;
  double fy = -1;
  field.getLocalForce(0, 0, fx, fy);

  EXPECT_NEAR(fx, 0.0, kGeomTol);
  EXPECT_NEAR(fy, 0.0, kGeomTol);
}

// Covers current field behavior: mark unmark and active index apis follow source semantics.
TEST(CurrentFieldTest, MarkUnmarkAndActiveIndexApisFollowSourceSemantics)
{
  CurrentField field;
  field.addVector(XYVector(0, 0, 1, 0));
  field.addVector(XYVector(1, 0, 1, 0));
  field.addVector(XYVector(2, 0, 1, 0));

  field.markVector(1);
  EXPECT_FALSE(field.isMarked(0));
  EXPECT_TRUE(field.isMarked(1));
  EXPECT_FALSE(field.isMarked(2));
  EXPECT_TRUE(field.hasActiveVertex());
  EXPECT_EQ(field.getActiveIX(), 1u);

  field.markupVector(2);
  EXPECT_TRUE(field.isMarked(1));
  EXPECT_TRUE(field.isMarked(2));
  EXPECT_EQ(field.getActiveIX(), 2u);

  EXPECT_TRUE(field.unmarkVector(2));
  EXPECT_FALSE(field.isMarked(2));
  EXPECT_TRUE(field.hasActiveVertex());
  EXPECT_EQ(field.getActiveIX(), 1u);
  EXPECT_FALSE(field.unmarkVector(99));
  EXPECT_FALSE(field.isMarked(99));
}

// Covers current field behavior: mark all and unmark all report whether anything changed.
TEST(CurrentFieldTest, MarkAllAndUnmarkAllReportWhetherAnythingChanged)
{
  CurrentField field;
  field.addVector(XYVector(0, 0, 1, 0));
  field.addVector(XYVector(1, 0, 1, 0));

  EXPECT_TRUE(field.markAllVectors());
  EXPECT_FALSE(field.markAllVectors());
  EXPECT_TRUE(field.isMarked(0));
  EXPECT_TRUE(field.isMarked(1));

  EXPECT_TRUE(field.unmarkAllVectors());
  EXPECT_FALSE(field.unmarkAllVectors());
  EXPECT_FALSE(field.isMarked(0));
  EXPECT_FALSE(field.isMarked(1));
}

// Covers current field behavior: delete vector and delete marked vectors preserve unmarked order.
TEST(CurrentFieldTest, DeleteVectorAndDeleteMarkedVectorsPreserveUnmarkedOrder)
{
  CurrentField field;
  field.addVector(XYVector(0, 0, 1, 0));
  field.addVector(XYVector(1, 0, 1, 0), true);
  field.addVector(XYVector(2, 0, 1, 0));
  field.addVector(XYVector(3, 0, 1, 0), true);

  field.deleteMarkedVectors();
  ASSERT_EQ(field.size(), 2u);
  EXPECT_NEAR(field.getXPos(0), 0.0, kGeomTol);
  EXPECT_NEAR(field.getXPos(1), 2.0, kGeomTol);
  EXPECT_FALSE(field.getVMarked(0));
  EXPECT_FALSE(field.getVMarked(1));

  EXPECT_TRUE(field.deleteVector(0));
  ASSERT_EQ(field.size(), 1u);
  EXPECT_NEAR(field.getXPos(0), 2.0, kGeomTol);
  EXPECT_FALSE(field.deleteVector(5));
}

// Covers current field behavior: modify and snap apis update selected vectors.
TEST(CurrentFieldTest, ModifyAndSnapApisUpdateSelectedVectors)
{
  CurrentField field;
  field.addVector(XYVector(1.24, -2.76, 4, 350));
  field.addVector(XYVector(3.26, 4.24, 2, 0), true);

  field.modVector(0, "aug_mag", 2);
  field.modVector(0, "aug_ang", 25);
  EXPECT_NEAR(field.getForce(0), 6.0, kGeomTol);
  EXPECT_NEAR(field.getDirection(0), 15.0, kGeomTol);

  field.modMarkedVectors("aug_x", 2);
  field.modMarkedVectors("aug_y", -3);
  EXPECT_NEAR(field.getXPos(1), 5.26, kGeomTol);
  EXPECT_NEAR(field.getYPos(1), 1.24, kGeomTol);

  field.applySnap(0.5);
  EXPECT_NEAR(field.getXPos(0), 1.0, kGeomTol);
  EXPECT_NEAR(field.getYPos(0), -3.0, kGeomTol);
  EXPECT_NEAR(field.getXPos(1), 5.5, kGeomTol);
  EXPECT_NEAR(field.getYPos(1), 1.0, kGeomTol);
}

// Covers current field behavior: select vector returns closest and signals empty field.
TEST(CurrentFieldTest, SelectVectorReturnsClosestAndSignalsEmptyField)
{
  CurrentField empty;
  double dist = 0;
  EXPECT_EQ(empty.selectVector(1, 1, dist), 0u);
  EXPECT_NEAR(dist, -1.0, kGeomTol);

  CurrentField field;
  field.addVector(XYVector(0, 0, 1, 0));
  field.addVector(XYVector(10, 0, 1, 0));
  field.addVector(XYVector(10, 10, 1, 0));

  EXPECT_EQ(field.selectVector(8, 1, dist), 1u);
  EXPECT_NEAR(dist, std::sqrt(5.0), kGeomTol);
}

// Covers current field behavior: listing serializes field metadata and vector rows.
TEST(CurrentFieldTest, ListingSerializesFieldMetadataAndVectorRows)
{
  CurrentField field;
  field.setRadius(12.5);
  field.addVector(XYVector(1.23456, 2.34567, 3.45678, 45.125));

  std::vector<std::string> listing = field.getListing();

  ASSERT_EQ(listing.size(), 4u);
  EXPECT_EQ(listing[0], "FieldName: generic_cfield");
  EXPECT_EQ(listing[1], "Radius:12.5");
  EXPECT_EQ(listing[2], "");
  EXPECT_TRUE(stringContains(listing[3], "1.235,2.346,3.457,45.12"));
}

// Covers current field behavior: populate applies metadata hints and current duplicate vector behavior.
TEST(CurrentFieldTest, PopulateAppliesMetadataHintsAndCurrentDuplicateVectorBehavior)
{
  TempFile file = makeTempFieldFile(
      "FieldName: TestField\n"
      "Radius: 8\n"
      "Render_Hint: vector_edge_color=yellow\n"
      "x=1,y=2,mag=3,ang=90\n");

  CurrentField field;
  testing::internal::CaptureStdout();
  bool ok = field.populate(file.path());
  std::string output = testing::internal::GetCapturedStdout();

  EXPECT_TRUE(ok);
  EXPECT_TRUE(stringContains(output, "Done Populating Current Field."));
  EXPECT_EQ(field.getName(), "testfield");
  EXPECT_NEAR(field.getRadius(), 8.0, kGeomTol);
  ASSERT_EQ(field.size(), 2u);
  EXPECT_EQ(field.getVector(0).get_color_str("edge"), "yellow");
  EXPECT_EQ(field.getVector(1).get_color_str("edge"), "yellow");
}

// Covers current field behavior: populates uSim current mission file shape from bravo example.
TEST(CurrentFieldTest, PopulatesUSimCurrentMissionFileShapeFromBravoExample)
{
  TempFile file = makeTempFieldFile(
      "\n"
      "FieldName: Alpha\n"
      "Radius: 15\n"
      "\n"
      "// xpos, ypos, force, direction\n"
      "x=45, y=-95,  mag=2.4, ang=130\n"
      "x=55, y=-95,  mag=2.4, ang=115\n"
      "x=65, y=-95,  mag=2.4, ang=100\n"
      "x=80, y=-95,  mag=2.4, ang=85\n"
      "\n"
      "x=45, y=-110, mag=2.4, ang=190\n"
      "x=55, y=-110, mag=2.4, ang=180\n"
      "x=65, y=-110, mag=2.4, ang=165\n"
      "x=80, y=-110, mag=2.4, ang=150\n"
      "\n"
      "x=45, y=-125, mag=2.4, ang=255\n"
      "x=55, y=-125, mag=2.4, ang=240\n"
      "x=65, y=-125, mag=2.4, ang=225\n"
      "x=80, y=-125, mag=2.4, ang=210\n"
      "\n"
      "x=45, y=-140, mag=2.4, ang=300\n"
      "x=55, y=-140, mag=2.4, ang=290\n"
      "x=65, y=-140, mag=2.4, ang=280\n"
      "x=80, y=-140, mag=2.4, ang=270\n");

  CurrentField field;
  testing::internal::CaptureStdout();
  bool ok = field.populate(file.path());
  std::string output = testing::internal::GetCapturedStdout();

  EXPECT_TRUE(ok);
  EXPECT_TRUE(stringContains(output, "OK Entries:"));
  EXPECT_TRUE(stringContains(output, "Bad Entries: 0"));
  EXPECT_EQ(field.getName(), "alpha");
  EXPECT_NEAR(field.getRadius(), 15.0, kGeomTol);
  // The current parser stores each valid vector twice: once immediately after
  // string2Vector succeeds and once at the end of handleLine().
  ASSERT_EQ(field.size(), 32u);
  EXPECT_NEAR(field.getXPos(0), 45.0, kGeomTol);
  EXPECT_NEAR(field.getYPos(0), -95.0, kGeomTol);
  EXPECT_NEAR(field.getForce(0), 2.4, kGeomTol);
  EXPECT_NEAR(field.getDirection(0), 130.0, kGeomTol);
  EXPECT_NEAR(field.getXPos(31), 80.0, kGeomTol);
  EXPECT_NEAR(field.getYPos(31), -140.0, kGeomTol);
  EXPECT_NEAR(field.getDirection(31), 270.0, kGeomTol);

  double fx = 0;
  double fy = 0;
  field.getLocalForce(45, -95, fx, fy);
  EXPECT_NEAR(fx, 1.040, kLooseGeomTol);
  EXPECT_NEAR(fy, -0.828, kLooseGeomTol);
}

// Covers current field behavior: render hints fill missing vector style without overriding inline style.
TEST(CurrentFieldTest, RenderHintsFillMissingVectorStyleWithoutOverridingInlineStyle)
{
  TempFile file = makeTempFieldFile(
      "FieldName: Styled\n"
      "Radius: 10\n"
      "Render_Hint: vector_edge_color=yellow\n"
      "Render_Hint: vector_vertex_size=4\n"
      "x=1,y=2,mag=3,ang=90,edge_color=red\n"
      "x=4,y=5,mag=6,ang=180\n");

  CurrentField field;
  testing::internal::CaptureStdout();
  ASSERT_TRUE(field.populate(file.path()));
  testing::internal::GetCapturedStdout();

  ASSERT_EQ(field.size(), 4u);
  EXPECT_EQ(field.getVector(0).get_color_str("edge"), "red");
  EXPECT_EQ(field.getVector(1).get_color_str("edge"), "red");
  EXPECT_EQ(field.getVector(2).get_color_str("edge"), "yellow");
  EXPECT_EQ(field.getVector(3).get_color_str("edge"), "yellow");
  EXPECT_NEAR(field.getVector(0).get_vertex_size(), 4.0, kGeomTol);
  EXPECT_NEAR(field.getVector(2).get_vertex_size(), 4.0, kGeomTol);
}

// Covers op field behavior: config parses points and colors while tolerating stdout.
TEST(OpFieldTest, ConfigParsesPointsAndColorsWhileToleratingStdout)
{
  OpField field;

  testing::internal::CaptureStdout();
  bool ok = field.config("sw=0,0#ne=x=100,y=100#team_color=red");
  std::string output = testing::internal::GetCapturedStdout();

  EXPECT_TRUE(ok);
  EXPECT_TRUE(stringContains(output, "alias=sw"));
  EXPECT_EQ(field.ptSize(), 2u);
  EXPECT_EQ(field.size(), 2u);
  EXPECT_TRUE(field.hasKeyPt("sw"));
  EXPECT_TRUE(field.hasKeyPt("ne"));
  EXPECT_FALSE(field.hasKey("team_color"));
  EXPECT_EQ(field.getColor("team_color"), "red");
  EXPECT_NEAR(field.getPoint("sw").x(), 0.0, kGeomTol);
  EXPECT_NEAR(field.getPoint("sw").y(), 0.0, kGeomTol);
  EXPECT_NEAR(field.getPoint("ne").x(), 100.0, kGeomTol);
  EXPECT_NEAR(field.getPoint("ne").y(), 100.0, kGeomTol);
}

// Covers op field behavior: config strips outer quotes and reports invalid point entries.
TEST(OpFieldTest, ConfigStripsOuterQuotesAndReportsInvalidPointEntries)
{
  OpField field;

  testing::internal::CaptureStdout();
  bool ok = field.config("\"good=1,2#bad=not_a_point\"");
  testing::internal::GetCapturedStdout();

  EXPECT_FALSE(ok);
  EXPECT_EQ(field.ptSize(), 1u);
  EXPECT_TRUE(field.hasKeyPt("good"));
  EXPECT_FALSE(field.hasKeyPt("bad"));
}

// Covers op field behavior: add point rejects duplicate and set point overwrites existing alias.
TEST(OpFieldTest, AddPointRejectsDuplicateAndSetPointOverwritesExistingAlias)
{
  OpField field;

  EXPECT_TRUE(field.addPoint("alpha", "1,2"));
  EXPECT_FALSE(field.addPoint("alpha", "3,4"));
  EXPECT_TRUE(field.setPoint("alpha", "3,4"));
  EXPECT_FALSE(field.setPoint("bad", "malformed"));

  EXPECT_EQ(field.ptSize(), 1u);
  EXPECT_NEAR(field.getPoint("alpha").x(), 3.0, kGeomTol);
  EXPECT_NEAR(field.getPoint("alpha").y(), 4.0, kGeomTol);
  EXPECT_FALSE(field.getPoint("bad").valid());
}

// Covers op field behavior: add and set polygon maintain separate key space from points.
TEST(OpFieldTest, AddAndSetPolygonMaintainSeparateKeySpaceFromPoints)
{
  OpField field;
  XYPolygon box = makeSquarePoly(0, 0, 10, 10);
  XYPolygon larger = makeSquarePoly(0, 0, 20, 20);

  EXPECT_TRUE(field.addPoint("box", "5,5"));
  EXPECT_TRUE(field.addPoly("box", box));
  EXPECT_FALSE(field.addPoly("box", larger));
  EXPECT_TRUE(field.setPoly("box", larger));
  EXPECT_FALSE(field.setPoly("bad_poly", "pts={0,0:1,1}"));

  EXPECT_TRUE(field.hasKey("box"));
  EXPECT_TRUE(field.hasKeyPt("box"));
  EXPECT_TRUE(field.hasKeyPoly("box"));
  EXPECT_FALSE(field.hasKeySegl("box"));
  EXPECT_EQ(field.ptSize(), 1u);
  EXPECT_EQ(field.polySize(), 1u);
  EXPECT_EQ(field.seglSize(), 0u);
  EXPECT_EQ(field.size(), 2u);
}

// Covers op field behavior: point aliases are returned from map order.
TEST(OpFieldTest, PointAliasesAreReturnedFromMapOrder)
{
  OpField field;
  field.addPoint("bravo", "2,2");
  field.addPoint("alpha", "1,1");
  field.addPoint("charlie", "3,3");

  std::vector<std::string> aliases = field.getPtAliases();

  ASSERT_EQ(aliases.size(), 3u);
  EXPECT_EQ(aliases[0], "alpha");
  EXPECT_EQ(aliases[1], "bravo");
  EXPECT_EQ(aliases[2], "charlie");
}

// Covers op field behavior: simplify keeps shorter alias by default for duplicate locations.
TEST(OpFieldTest, SimplifyKeepsShorterAliasByDefaultForDuplicateLocations)
{
  OpField field;
  field.addPoint("AB", "10,20");
  field.addPoint("ABT", "10,20");
  field.addPoint("CD", "10.0005,20.0005");
  field.addPoint("EF", "30,40");

  field.simplify();

  std::vector<std::string> aliases = sortedAliases(field);
  ASSERT_EQ(aliases.size(), 3u);
  EXPECT_NE(std::find(aliases.begin(), aliases.end(), "AB"), aliases.end());
  EXPECT_EQ(std::find(aliases.begin(), aliases.end(), "ABT"), aliases.end());
  EXPECT_NE(std::find(aliases.begin(), aliases.end(), "CD"), aliases.end());
  EXPECT_NE(std::find(aliases.begin(), aliases.end(), "EF"), aliases.end());
}

// Covers op field behavior: simplify false removes unequal length duplicates and leaves equal length duplicates.
TEST(OpFieldTest, SimplifyFalseRemovesUnequalLengthDuplicatesAndLeavesEqualLengthDuplicates)
{
  OpField field;
  field.addPoint("A", "1,1");
  field.addPoint("ALONG", "1,1");
  field.addPoint("BX", "2,2");
  field.addPoint("CY", "2,2");

  field.simplify(false);

  // With keep_shorter=false, the pairwise pass removes both unequal-length
  // duplicate aliases; same-length duplicates are not candidates.
  std::vector<std::string> aliases = sortedAliases(field);
  ASSERT_EQ(aliases.size(), 2u);
  EXPECT_EQ(std::find(aliases.begin(), aliases.end(), "A"), aliases.end());
  EXPECT_EQ(std::find(aliases.begin(), aliases.end(), "ALONG"), aliases.end());
  EXPECT_NE(std::find(aliases.begin(), aliases.end(), "BX"), aliases.end());
  EXPECT_NE(std::find(aliases.begin(), aliases.end(), "CY"), aliases.end());
}

// Covers op field behavior: merge combines points and polygons but rejects duplicate point keys.
TEST(OpFieldTest, MergeCombinesPointsAndPolygonsButRejectsDuplicatePointKeys)
{
  OpField left;
  left.addPoint("alpha", "1,1");

  OpField right;
  right.addPoint("bravo", "2,2");
  right.addPoly("zone", makeSquarePoly(0, 0, 10, 10));

  EXPECT_TRUE(left.merge(right));
  EXPECT_TRUE(left.hasKeyPt("alpha"));
  EXPECT_TRUE(left.hasKeyPt("bravo"));
  EXPECT_TRUE(left.hasKeyPoly("zone"));
  EXPECT_EQ(left.size(), 3u);

  OpField conflict;
  conflict.addPoint("alpha", "9,9");
  EXPECT_FALSE(left.merge(conflict));
  EXPECT_NEAR(left.getPoint("alpha").x(), 1.0, kGeomTol);
  EXPECT_NEAR(left.getPoint("alpha").y(), 1.0, kGeomTol);
}
