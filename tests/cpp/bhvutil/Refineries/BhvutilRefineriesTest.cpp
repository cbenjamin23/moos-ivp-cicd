#include <gtest/gtest.h>

#include <vector>

#include "CPXEngineOG.h"
#include "IvPBuildTestUtils.h"
#include "NumericAssertions.h"
#include "ObShipModelV24.h"
#include "RefineryCPA.h"
#include "RefineryObAvoidV24.h"
#include "XYFormatUtilsPoly.h"

namespace {

IvPDomain makeCourseSpeedOnlyDomain()
{
  return makeCourseSpeedDomain();
}

class TestableRefineryCPA : public RefineryCPA {
 public:
  using RefineryCPA::getHdgDiscPts;
  using RefineryCPA::getHdgSnappedHgh;
  using RefineryCPA::getHdgSnappedLow;
  using RefineryCPA::getMaxFirstSatHdgAtSpd;
  using RefineryCPA::getMaxLastSatHdgAtSpd;
  using RefineryCPA::getMaxSpdAtHdg;
  using RefineryCPA::getMinFirstSatHdgAtSpd;
  using RefineryCPA::getMinLastSatHdgAtSpd;
  using RefineryCPA::getMinSpdAtHdg;
  using RefineryCPA::getMinSpdClockwise;
  using RefineryCPA::getMinSpdCounterClock;
  using RefineryCPA::getPassHdgClockwise;
  using RefineryCPA::getPassHdgCounterClock;
  using RefineryCPA::getSpdSnappedHgh;
  using RefineryCPA::getSpdSnappedLow;
  using RefineryCPA::validHdg;
  using RefineryCPA::validSpd;
};

class TestableRefineryObAvoidV24 : public RefineryObAvoidV24 {
 public:
  explicit TestableRefineryObAvoidV24(IvPDomain domain)
    : RefineryObAvoidV24(domain)
  {
  }

  using RefineryObAvoidV24::getHdgSnappedHigh;
  using RefineryObAvoidV24::getHdgSnappedLow;
  using RefineryObAvoidV24::getHdgSnappedProx;
  using RefineryObAvoidV24::getSpdSnappedHigh;
  using RefineryObAvoidV24::getSpdSnappedLow;
  using RefineryObAvoidV24::getSpdSnappedProx;
};

ObShipModelV24 makeObstacleModel(double osx = 0,
                                 double osy = 0,
                                 double osh = 90,
                                 double osv = 2)
{
  ObShipModelV24 model;
  model.setPose(osx, osy, osh, osv);
  EXPECT_EQ(model.setGutPoly(
                string2Poly("pts={40,-10:60,-10:60,10:40,10},label=ob_0")),
      "");
  EXPECT_EQ(model.setMinUtilCPA(5), "");
  EXPECT_EQ(model.setMaxUtilCPA(20), "");
  EXPECT_EQ(model.setAllowableTTC(20), "");
  EXPECT_EQ(model.setPwtInnerDist(5), "");
  EXPECT_EQ(model.setPwtOuterDist(25), "");
  model.setCachedVals(true);
  return model;
}

void expectRegionsAreValid(const std::vector<IvPBox>& regions)
{
  ASSERT_FALSE(regions.empty());
  for(const IvPBox& region : regions) {
    EXPECT_EQ(region.getDim(), 2);
    EXPECT_LE(region.pt(0, 0), region.pt(0, 1));
    EXPECT_LE(region.pt(1, 0), region.pt(1, 1));
  }
}

void expectRegionsStayWithinCourseSpeedDomain(const std::vector<IvPBox>& regions)
{
  for(const IvPBox& region : regions) {
    EXPECT_GE(region.pt(0, 0), 0);
    EXPECT_LE(region.pt(0, 1), 359);
    EXPECT_GE(region.pt(1, 0), 0);
    EXPECT_LE(region.pt(1, 1), 5);
  }
}

bool hasPlateau(const std::vector<IvPBox>& regions, int value)
{
  for(const IvPBox& region : regions) {
    if(region.getPlat() == value)
      return true;
  }
  return false;
}

}  // namespace

// Covers refinery CPA behavior: rejects invalid initialization contracts.
TEST(RefineryCPATest, RejectsInvalidInitializationContracts)
{
  CPXEngineOG engine(100, 0, 180, 2, 0, 0);
  RefineryCPA refinery;

  EXPECT_FALSE(refinery.init(0, 0, 0, 100, 180, 2, 60,
                             -1, 40, makeCourseSpeedOnlyDomain(), &engine));
  EXPECT_FALSE(refinery.init(0, 0, 0, 100, 180, 2, 60,
                             50, 40, makeCourseSpeedOnlyDomain(), &engine));
  EXPECT_FALSE(refinery.init(0, 0, 0, 100, 180, 2, 60,
                             10, 40, makeCourseSpeedOnlyDomain(), nullptr));

  IvPDomain course_only;
  course_only.addDomain("course", 0, 359, 360);
  EXPECT_FALSE(refinery.init(0, 0, 0, 100, 180, 2, 60,
                             10, 40, course_only, &engine));
  EXPECT_TRUE(refinery.getRefineRegions().empty());
}

// Covers refinery CPA behavior: builds aft contact regions for avoid collision IvP functions.
TEST(RefineryCPATest, BuildsAftContactRegionsForAvoidCollisionIvPFunctions)
{
  IvPDomain domain = makeCourseSpeedOnlyDomain();
  CPXEngineOG engine(100, 0, 0, 1, 0, 0);
  RefineryCPA refinery;
  ASSERT_TRUE(refinery.init(0, 0, 0, 100, 0, 1, 60,
                            10, 40, domain, &engine));

  std::vector<IvPBox> regions = refinery.getRefineRegions();
  expectRegionsAreValid(regions);
  expectRegionsStayWithinCourseSpeedDomain(regions);
  EXPECT_EQ(refinery.getLogicCase(), "aft");
  EXPECT_GT(refinery.getTotalQueriesCPA(), 0u);
}

// Covers refinery CPA behavior: builds fore contact regions for cut range geometry.
TEST(RefineryCPATest, BuildsForeContactRegionsForCutRangeGeometry)
{
  IvPDomain domain = makeCourseSpeedOnlyDomain();
  CPXEngineOG engine(100, 100, 270, 2, 0, 0);
  RefineryCPA refinery;
  ASSERT_TRUE(refinery.init(0, 0, 100, 100, 270, 2, 120,
                            10, 40, domain, &engine));

  std::vector<IvPBox> regions = refinery.getRefineRegions();
  expectRegionsAreValid(regions);
  expectRegionsStayWithinCourseSpeedDomain(regions);
  EXPECT_NE(refinery.getLogicCase(), "");
}

// Covers refinery CPA behavior: pins fore out velocity cone regions for BHV avoid collision.
TEST(RefineryCPATest, PinsForeOutVelocityConeRegionsForBhvAvoidCollision)
{
  IvPDomain domain = makeCourseSpeedOnlyDomain();
  CPXEngineOG engine(0, 100, 0, 2, 0, 0);
  RefineryCPA refinery;
  ASSERT_TRUE(refinery.init(0, 0, 100, 0, 0, 2, 60,
                            10, 40, domain, &engine));

  std::vector<IvPBox> regions = refinery.getRefineRegions();
  ASSERT_EQ(regions.size(), 5u);
  expectRegionsAreValid(regions);
  expectRegionsStayWithinCourseSpeedDomain(regions);
  EXPECT_EQ(refinery.getLogicCase(), "fore_out_rgam");
  EXPECT_EQ(regions[0].pt(0, 0), 0);
  EXPECT_EQ(regions[0].pt(0, 1), 359);
  EXPECT_EQ(regions[0].pt(1, 0), 0);
  EXPECT_EQ(regions[0].pt(1, 1), 1);
  EXPECT_GT(refinery.getTotalQueriesCPA(), 150u);
}

// Covers refinery CPA behavior: pins fore in velocity cone regions for closing contact.
TEST(RefineryCPATest, PinsForeInVelocityConeRegionsForClosingContact)
{
  IvPDomain domain = makeCourseSpeedOnlyDomain();
  CPXEngineOG engine(0, 100, 270, 2, 0, 0);
  RefineryCPA refinery;
  ASSERT_TRUE(refinery.init(0, 0, 100, 0, 270, 2, 60,
                            10, 40, domain, &engine));

  std::vector<IvPBox> regions = refinery.getRefineRegions();
  ASSERT_EQ(regions.size(), 2u);
  expectRegionsAreValid(regions);
  expectRegionsStayWithinCourseSpeedDomain(regions);
  EXPECT_EQ(refinery.getLogicCase(), "fore_in_rgam");
  EXPECT_EQ(regions[0].pt(1, 0), 3);
  EXPECT_EQ(regions[0].pt(1, 1), 5);
  EXPECT_EQ(regions[1].pt(1, 0), 3);
  EXPECT_EQ(regions[1].pt(1, 1), 5);
  EXPECT_GT(refinery.getTotalQueriesCPA(), 700u);
}

// Covers refinery CPA behavior: exposes snapping and heading sweep boundaries used by refineries.
TEST(RefineryCPATest, ExposesSnappingAndHeadingSweepBoundariesUsedByRefineries)
{
  IvPDomain domain = makeCourseSpeedOnlyDomain();
  CPXEngineOG engine(0, 100, 270, 2, 0, 0);
  TestableRefineryCPA refinery;
  ASSERT_TRUE(refinery.init(0, 0, 100, 0, 270, 2, 60,
                            10, 40, domain, &engine));

  EXPECT_FALSE(refinery.validHdg(-1));
  EXPECT_TRUE(refinery.validHdg(0));
  EXPECT_TRUE(refinery.validHdg(359));
  EXPECT_FALSE(refinery.validHdg(359.1));
  EXPECT_FALSE(refinery.validHdg(360));

  EXPECT_FALSE(refinery.validSpd(-0.1));
  EXPECT_TRUE(refinery.validSpd(0));
  EXPECT_TRUE(refinery.validSpd(5));
  EXPECT_FALSE(refinery.validSpd(5.1));

  EXPECT_NEAR(refinery.getHdgSnappedLow(10.7), 10.0, kGeomTol);
  EXPECT_NEAR(refinery.getHdgSnappedHgh(10.7), 11.0, kGeomTol);
  EXPECT_NEAR(refinery.getHdgSnappedHgh(359.1), 0.0, kGeomTol);
  EXPECT_NEAR(refinery.getSpdSnappedLow(2.6), 2.0, kGeomTol);
  EXPECT_NEAR(refinery.getSpdSnappedHgh(2.6), 3.0, kGeomTol);

  EXPECT_EQ(refinery.getHdgDiscPts(10, 20, 0), 11u);
  EXPECT_EQ(refinery.getHdgDiscPts(10, 20, 1), 11u);
  EXPECT_EQ(refinery.getHdgDiscPts(10, 20, 2), 11u);
  EXPECT_EQ(refinery.getHdgDiscPts(350, 10, 0), 21u);
  EXPECT_EQ(refinery.getHdgDiscPts(350, 10, 1), 21u);
  EXPECT_EQ(refinery.getHdgDiscPts(350, 10, 2), 21u);
}

// Covers refinery CPA behavior: pins protected search helpers across course and speed domain.
TEST(RefineryCPATest, PinsProtectedSearchHelpersAcrossCourseAndSpeedDomain)
{
  IvPDomain domain = makeCourseSpeedOnlyDomain();
  CPXEngineOG engine(0, 100, 270, 2, 0, 0);
  TestableRefineryCPA refinery;
  ASSERT_TRUE(refinery.init(0, 0, 100, 0, 270, 2, 60,
                            10, 40, domain, &engine));

  EXPECT_NEAR(refinery.getMinSpdAtHdg(0), -1.0, kGeomTol);
  EXPECT_NEAR(refinery.getMaxSpdAtHdg(0), 1.0, kGeomTol);
  EXPECT_NEAR(refinery.getMinSpdAtHdg(90), -1.0, kGeomTol);
  EXPECT_NEAR(refinery.getMaxSpdAtHdg(90), -1.0, kGeomTol);

  EXPECT_NEAR(refinery.getMinFirstSatHdgAtSpd(3, 0), 0.0, kGeomTol);
  EXPECT_NEAR(refinery.getMaxFirstSatHdgAtSpd(3, 359), 359.0, kGeomTol);
  EXPECT_NEAR(refinery.getMinLastSatHdgAtSpd(3, 359), 130.0, kGeomTol);
  EXPECT_NEAR(refinery.getMaxLastSatHdgAtSpd(3, 0), 50.0, kGeomTol);

  EXPECT_NEAR(refinery.getMinSpdClockwise(350, 20, 5), 5.0, kGeomTol);
  EXPECT_NEAR(refinery.getMinSpdCounterClock(350, 20, 5), 5.0, kGeomTol);
  EXPECT_NEAR(refinery.getPassHdgClockwise(270, 5, 2), 50.0, kGeomTol);
  EXPECT_NEAR(refinery.getPassHdgCounterClock(270, 5, 2), 130.0, kGeomTol);

  EXPECT_NEAR(refinery.getMinFirstSatHdgAtSpd(0, 10), -1.0, kGeomTol);
  EXPECT_NEAR(refinery.getMaxFirstSatHdgAtSpd(3, 360), -1.0, kGeomTol);
  EXPECT_NEAR(refinery.getMinSpdClockwise(-1, 20, 5), -1.0, kGeomTol);
  EXPECT_NEAR(refinery.getMinSpdCounterClock(350, 20, 6), -1.0, kGeomTol);
}

// Covers refinery ob avoid V24 behavior: builds plateaus and basins from obstacle bearing extremes.
TEST(RefineryObAvoidV24Test, BuildsPlateausAndBasinsFromObstacleBearingExtremes)
{
  RefineryObAvoidV24 refinery(makeCourseSpeedOnlyDomain());
  refinery.setRefineRegions(makeObstacleModel());

  std::vector<IvPBox> plateaus = refinery.getPlateaus();
  std::vector<IvPBox> basins = refinery.getBasins();
  expectRegionsAreValid(plateaus);
  expectRegionsAreValid(basins);
  expectRegionsStayWithinCourseSpeedDomain(plateaus);
  expectRegionsStayWithinCourseSpeedDomain(basins);
  for(const IvPBox& region : plateaus)
    EXPECT_GT(region.getPlat(), 0);
  for(const IvPBox& region : basins)
    EXPECT_LT(region.getPlat(), 0);
}

// Covers refinery ob avoid V24 behavior: side lock adds major basin regions for passing side choice.
TEST(RefineryObAvoidV24Test, SideLockAddsMajorBasinRegionsForPassingSideChoice)
{
  RefineryObAvoidV24 unrestricted(makeCourseSpeedOnlyDomain());
  unrestricted.setRefineRegions(makeObstacleModel());
  const std::size_t unrestricted_basins = unrestricted.getBasins().size();

  RefineryObAvoidV24 port_locked(makeCourseSpeedOnlyDomain());
  port_locked.setSideLock("port");
  port_locked.setRefineRegions(makeObstacleModel());

  expectRegionsAreValid(port_locked.getBasins());
  expectRegionsStayWithinCourseSpeedDomain(port_locked.getBasins());
  EXPECT_GE(port_locked.getBasins().size(), unrestricted_basins);
  EXPECT_TRUE(hasPlateau(port_locked.getBasins(), -3));
}

// Covers refinery ob avoid V24 behavior: starboard side lock also produces negative utility basins.
TEST(RefineryObAvoidV24Test, StarboardSideLockAlsoProducesNegativeUtilityBasins)
{
  RefineryObAvoidV24 starboard_locked(makeCourseSpeedOnlyDomain());
  starboard_locked.setSideLock("starboard");
  starboard_locked.setRefineRegions(makeObstacleModel());

  std::vector<IvPBox> basins = starboard_locked.getBasins();
  expectRegionsAreValid(basins);
  expectRegionsStayWithinCourseSpeedDomain(basins);
  EXPECT_TRUE(hasPlateau(basins, -3));
}

// Covers refinery ob avoid V24 behavior: side lock basins are clipped against major obstacle regions.
TEST(RefineryObAvoidV24Test, SideLockBasinsAreClippedAgainstMajorObstacleRegions)
{
  RefineryObAvoidV24 port_locked(makeCourseSpeedOnlyDomain());
  port_locked.setSideLock("port");
  port_locked.setRefineRegions(makeObstacleModel(0, -40, 350, 2));

  std::vector<IvPBox> basins = port_locked.getBasins();
  expectRegionsAreValid(basins);
  expectRegionsStayWithinCourseSpeedDomain(basins);
  EXPECT_TRUE(hasPlateau(basins, -3));

  bool has_clipped_side_lock_basin = false;
  for(const IvPBox& region : basins) {
    if(region.getPlat() == -3 && region.pt(0, 0) == 21 &&
       region.pt(0, 1) == 80 && region.pt(1, 0) == 0 &&
       region.pt(1, 1) == 5) {
      has_clipped_side_lock_basin = true;
    }
  }
  EXPECT_TRUE(has_clipped_side_lock_basin);
}

// Covers refinery ob avoid V24 behavior: snaps course and speed like BHV avoid obstacle domain.
TEST(RefineryObAvoidV24Test, SnapsCourseAndSpeedLikeBhvAvoidObstacleDomain)
{
  TestableRefineryObAvoidV24 refinery(makeCourseSpeedOnlyDomain());

  EXPECT_NEAR(refinery.getHdgSnappedLow(-1), 359.0, kGeomTol);
  EXPECT_NEAR(refinery.getHdgSnappedHigh(-1), 359.0, kGeomTol);
  EXPECT_NEAR(refinery.getHdgSnappedProx(-1), 359.0, kGeomTol);

  EXPECT_NEAR(refinery.getHdgSnappedLow(10.7), 10.0, kGeomTol);
  EXPECT_NEAR(refinery.getHdgSnappedHigh(10.7), 11.0, kGeomTol);
  EXPECT_NEAR(refinery.getHdgSnappedProx(10.7), 11.0, kGeomTol);

  EXPECT_NEAR(refinery.getHdgSnappedLow(359.2), 359.0, kGeomTol);
  EXPECT_NEAR(refinery.getHdgSnappedHigh(359.2), 0.0, kGeomTol);
  EXPECT_NEAR(refinery.getHdgSnappedProx(359.2), 359.0, kGeomTol);
  EXPECT_NEAR(refinery.getHdgSnappedProx(360), 0.0, kGeomTol);
  EXPECT_NEAR(refinery.getHdgSnappedProx(361), 1.0, kGeomTol);

  EXPECT_NEAR(refinery.getSpdSnappedLow(0.2), 0.0, kGeomTol);
  EXPECT_NEAR(refinery.getSpdSnappedHigh(0.2), 1.0, kGeomTol);
  EXPECT_NEAR(refinery.getSpdSnappedProx(0.2), 0.0, kGeomTol);
  EXPECT_NEAR(refinery.getSpdSnappedLow(2.6), 2.0, kGeomTol);
  EXPECT_NEAR(refinery.getSpdSnappedHigh(2.6), 3.0, kGeomTol);
  EXPECT_NEAR(refinery.getSpdSnappedProx(2.6), 3.0, kGeomTol);
  EXPECT_NEAR(refinery.getSpdSnappedLow(5.1), 5.0, kGeomTol);
  EXPECT_NEAR(refinery.getSpdSnappedHigh(5.1), 5.0, kGeomTol);
  EXPECT_NEAR(refinery.getSpdSnappedProx(5.1), 5.0, kGeomTol);
}

// Covers refinery ob avoid V24 behavior: invalid domains produce no regions.
TEST(RefineryObAvoidV24Test, InvalidDomainsProduceNoRegions)
{
  IvPDomain speed_only;
  speed_only.addDomain("speed", 0, 5, 6);
  RefineryObAvoidV24 refinery(speed_only);
  refinery.setRefineRegions(makeObstacleModel());

  EXPECT_TRUE(refinery.getPlateaus().empty());
  EXPECT_TRUE(refinery.getBasins().empty());
}
