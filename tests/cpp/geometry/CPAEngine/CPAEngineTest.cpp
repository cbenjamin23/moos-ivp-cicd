#include <gtest/gtest.h>

#include <cmath>

#include "CPAEngine.h"
#include "NumericAssertions.h"

// Covers CPA engine encounter behavior: computes head on closing contact CPA.
TEST(CPAEngineEncounterTest, ComputesHeadOnClosingContactCpa)
{
  CPAEngine engine(100, 0, 180, 2, 0, 0);

  EXPECT_NEAR(engine.getRange(), 100.0, kGeomTol);
  EXPECT_NEAR(engine.evalCPA(0, 2, 60), 0.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(0, 2, 60), 25.0, kGeomTol);
  EXPECT_GT(engine.evalROC(0, 2), 0.0);
}

// Covers CPA engine encounter behavior: clips CPA distance to ownship time on leg.
TEST(CPAEngineEncounterTest, ClipsCpaDistanceToOwnshipTimeOnLeg)
{
  CPAEngine engine(100, 0, 180, 2, 0, 0);

  EXPECT_NEAR(engine.evalTimeCPA(0, 2, 10), 25.0, kGeomTol);
  EXPECT_NEAR(engine.evalCPA(0, 2, 10), 60.0, kGeomTol);
  EXPECT_NEAR(engine.getARange(0, 2, 10), 60.0, kGeomTol);
}

// Covers CPA engine encounter behavior: pins zero and negative time on leg literal behavior.
TEST(CPAEngineEncounterTest, PinsZeroAndNegativeTimeOnLegLiteralBehavior)
{
  CPAEngine engine(100, 0, 180, 2, 0, 0);

  EXPECT_NEAR(engine.evalCPA(0, 2, 0), 100.0, kGeomTol);
  EXPECT_NEAR(engine.evalCPA(0, 2, -1), 104.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(0, 2, 0), 25.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(0, 2, -1), 25.0, kGeomTol);
  EXPECT_NEAR(engine.evalRangeRateOverRange(0, 2, 10), 0.0, kGeomTol);
}

// Covers CPA engine encounter behavior: computes crossing geometry used by contact avoidance.
TEST(CPAEngineEncounterTest, ComputesCrossingGeometryUsedByContactAvoidance)
{
  CPAEngine engine(100, 100, 270, 2, 0, 0);

  EXPECT_GT(engine.getRange(), 140.0);
  EXPECT_NEAR(engine.evalCPA(0, 2, 120), 0.0, kLooseGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(0, 2, 120), 50.0, kGeomTol);
  EXPECT_NEAR(engine.evalROC(0, 2), 2.8284271247, kLooseGeomTol);
  EXPECT_NEAR(engine.bearingRate(0, 2), 0.0, kGeomTol);
  EXPECT_NEAR(engine.osToCNAbsBng(), 45.0, kGeomTol);
  EXPECT_NEAR(engine.ownshipContactRelBearing(0), 45.0, kGeomTol);
  EXPECT_NEAR(engine.contactOwnshipRelBearing(), 315.0, kGeomTol);
  EXPECT_TRUE(engine.foreOfContact());
  EXPECT_TRUE(engine.portOfContact());
  EXPECT_FALSE(engine.aftOfContact());
  EXPECT_FALSE(engine.starOfContact());
  EXPECT_TRUE(engine.crossesBowOrStern(0, 2));
  EXPECT_TRUE(engine.crossesBow(0, 2));
  EXPECT_TRUE(engine.crossesStern(0, 2));
  EXPECT_TRUE(engine.passesPortOrStar(0, 2));
  EXPECT_FALSE(engine.passesPort(0, 2));
  EXPECT_TRUE(engine.passesStar(0, 2));
  EXPECT_NEAR(engine.passesStarDist(0, 2), 0.0, kGeomTol);
}

// Covers CPA engine encounter behavior: mirrors IvP contact behavior forward and reciprocal state.
TEST(CPAEngineEncounterTest, MirrorsIvPContactBehaviorForwardAndReciprocalState)
{
  const double osx = 0;
  const double osy = 0;
  const double osh = 0;
  const double osv = 2;
  const double cnx = 100;
  const double cny = 100;
  const double cnh = 270;
  const double cnv = 2;

  CPAEngine os_to_contact(cny, cnx, cnh, cnv, osy, osx);
  CPAEngine contact_to_os(osy, osx, osh, osv, cny, cnx);

  EXPECT_NEAR(os_to_contact.getRange(), 141.4213562373, kLooseGeomTol);
  EXPECT_NEAR(contact_to_os.getRange(), os_to_contact.getRange(), kGeomTol);

  EXPECT_TRUE(os_to_contact.foreOfContact());
  EXPECT_TRUE(os_to_contact.portOfContact());
  EXPECT_FALSE(os_to_contact.aftOfContact());
  EXPECT_FALSE(os_to_contact.starOfContact());
  EXPECT_TRUE(contact_to_os.foreOfContact());
  EXPECT_FALSE(contact_to_os.portOfContact());
  EXPECT_TRUE(contact_to_os.starOfContact());

  EXPECT_NEAR(os_to_contact.osToCNAbsBng(), 45.0, kGeomTol);
  EXPECT_NEAR(os_to_contact.ownshipContactRelBearing(osh), 45.0, kGeomTol);
  EXPECT_NEAR(contact_to_os.osToCNAbsBng(), 225.0, kGeomTol);
  EXPECT_NEAR(contact_to_os.ownshipContactRelBearing(cnh), 315.0, kGeomTol);

  EXPECT_NEAR(os_to_contact.evalROC(osh, osv), 2.8284271247, kLooseGeomTol);
  EXPECT_NEAR(contact_to_os.evalROC(cnh, cnv),
              os_to_contact.evalROC(osh, osv), kGeomTol);
  EXPECT_NEAR(os_to_contact.evalCPA(osh, osv, 120), 0.0, kLooseGeomTol);
  EXPECT_NEAR(contact_to_os.evalCPA(cnh, cnv, 120), 0.0, kLooseGeomTol);
  EXPECT_NEAR(os_to_contact.evalTimeCPA(osh, osv, 120), 50.0, kGeomTol);
  EXPECT_NEAR(contact_to_os.evalTimeCPA(cnh, cnv, 120), 50.0, kGeomTol);

  EXPECT_TRUE(os_to_contact.passesPortOrStar(osh, osv));
  EXPECT_FALSE(os_to_contact.passesPort(osh, osv));
  EXPECT_TRUE(os_to_contact.passesStar(osh, osv));
  EXPECT_TRUE(contact_to_os.passesPortOrStar(cnh, cnv));
  EXPECT_FALSE(contact_to_os.passesPort(cnh, cnv));
  EXPECT_TRUE(contact_to_os.passesStar(cnh, cnv));

  EXPECT_TRUE(os_to_contact.crossesBowOrStern(osh, osv));
  EXPECT_TRUE(os_to_contact.crossesBow(osh, osv));
  EXPECT_TRUE(os_to_contact.crossesStern(osh, osv));
  EXPECT_TRUE(contact_to_os.crossesBowOrStern(cnh, cnv));
  EXPECT_TRUE(contact_to_os.crossesBow(cnh, cnv));
  EXPECT_TRUE(contact_to_os.crossesStern(cnh, cnv));
}

// Covers CPA engine encounter behavior: reports opening range for parallel same direction contact.
TEST(CPAEngineEncounterTest, ReportsOpeningRangeForParallelSameDirectionContact)
{
  CPAEngine engine(100, 0, 0, 2, 0, 0);

  EXPECT_NEAR(engine.evalCPA(0, 2, 60), 100.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(0, 2, 60), 0.0, kGeomTol);
  EXPECT_NEAR(engine.evalROC(0, 2), 0.0, kGeomTol);
}

// Covers CPA engine encounter behavior: classifies port side pass with distance from contact.
TEST(CPAEngineEncounterTest, ClassifiesPortSidePassWithDistanceFromContact)
{
  CPAEngine engine(100, 50, 0, 1, 0, 0);

  EXPECT_TRUE(engine.aftOfContact());
  EXPECT_TRUE(engine.portOfContact());
  EXPECT_FALSE(engine.foreOfContact());
  EXPECT_FALSE(engine.starOfContact());
  EXPECT_NEAR(engine.osToCNAbsBng(), 26.5650511771, kLooseGeomTol);
  EXPECT_NEAR(engine.contactOwnshipRelBearing(), 206.5650511771, kLooseGeomTol);
  EXPECT_NEAR(engine.evalCPA(0, 3, 120), 50.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(0, 3, 120), 50.0, kGeomTol);
  EXPECT_NEAR(engine.evalROC(0, 3), 1.7888543820, kLooseGeomTol);
  EXPECT_NEAR(engine.bearingRate(0, 3), 0.4583662361, kLooseGeomTol);
  EXPECT_TRUE(engine.passesPortOrStar(0, 3));
  EXPECT_TRUE(engine.passesPort(0, 3));
  EXPECT_FALSE(engine.passesStar(0, 3));
  EXPECT_NEAR(engine.passesPortDist(0, 3), 50.0, kGeomTol);
  EXPECT_NEAR(engine.passesStarDist(0, 3), -1.0, kGeomTol);
  EXPECT_FALSE(engine.crossesBowOrStern(0, 3));
}

// Covers CPA engine encounter behavior: classifies starboard side pass with distance from contact.
TEST(CPAEngineEncounterTest, ClassifiesStarboardSidePassWithDistanceFromContact)
{
  CPAEngine engine(100, -50, 0, 1, 0, 0);

  EXPECT_TRUE(engine.aftOfContact());
  EXPECT_TRUE(engine.starOfContact());
  EXPECT_FALSE(engine.foreOfContact());
  EXPECT_FALSE(engine.portOfContact());
  EXPECT_NEAR(engine.osToCNAbsBng(), 333.4349488229, kLooseGeomTol);
  EXPECT_NEAR(engine.contactOwnshipRelBearing(), 153.4349488229, kLooseGeomTol);
  EXPECT_NEAR(engine.evalCPA(0, 3, 120), 50.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(0, 3, 120), 50.0, kGeomTol);
  EXPECT_NEAR(engine.evalROC(0, 3), 1.7888543820, kLooseGeomTol);
  EXPECT_NEAR(engine.bearingRate(0, 3), -0.4583662361, kLooseGeomTol);
  EXPECT_TRUE(engine.passesPortOrStar(0, 3));
  EXPECT_FALSE(engine.passesPort(0, 3));
  EXPECT_TRUE(engine.passesStar(0, 3));
  EXPECT_NEAR(engine.passesPortDist(0, 3), -1.0, kGeomTol);
  EXPECT_NEAR(engine.passesStarDist(0, 3), 50.0, kGeomTol);
  EXPECT_FALSE(engine.crossesBowOrStern(0, 3));
}

// Covers CPA engine encounter behavior: reports stern crossing distance for beam transit.
TEST(CPAEngineEncounterTest, ReportsSternCrossingDistanceForBeamTransit)
{
  CPAEngine engine(100, 50, 0, 1, 0, 0);

  EXPECT_FALSE(engine.crossesBow(90, 2));
  EXPECT_TRUE(engine.crossesStern(90, 2));
  EXPECT_TRUE(engine.crossesBowOrStern(90, 2));
  EXPECT_NEAR(engine.crossesBowDist(90, 2), -1.0, kGeomTol);
  EXPECT_NEAR(engine.crossesSternDist(90, 2), 125.0, kGeomTol);
  EXPECT_FALSE(engine.passesPortOrStar(90, 2));
  EXPECT_NEAR(engine.evalCPA(90, 2, 120), engine.getRange(), kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(90, 2, 120), 0.0, kGeomTol);
}

// Covers CPA engine encounter behavior: exposes beam transit gamma and epsilon components.
TEST(CPAEngineEncounterTest, ExposesBeamTransitGammaAndEpsilonComponents)
{
  CPAEngine engine(100, 50, 0, 1, 0, 0);

  EXPECT_TRUE(std::isfinite(engine.cnSpdToOS()));
  EXPECT_NEAR(engine.getCNSpeedInOSPos(), engine.cnSpdToOS(), kGeomTol);
  EXPECT_NEAR(engine.getRangeGamma(), 50.0, kLooseGeomTol);
  EXPECT_NEAR(engine.getRangeEpsilon(), 100.0, kLooseGeomTol);
  EXPECT_NEAR(engine.getThetaGamma(), 90.0, kGeomTol);
  EXPECT_NEAR(engine.getThetaEpsilon(), 0.0, kGeomTol);
  EXPECT_NEAR(engine.getOSSpeedInCNHeading(450, 2), 0.0, kGeomTol);
  EXPECT_NEAR(engine.getOSSpeedGamma(450, 2), 2.0, kGeomTol);
  EXPECT_NEAR(engine.getOSSpeedEpsilon(450, 2), -1.0, kGeomTol);
  EXPECT_NEAR(engine.getOSTimeGamma(450, 2), 25.0, kLooseGeomTol);
  EXPECT_NEAR(engine.getOSTimeEpsilon(450, 2), -100.0, kLooseGeomTol);
  EXPECT_NEAR(engine.getOSTimeGamma(90, 0), 0.0, kGeomTol);
  EXPECT_NEAR(engine.getOSTimeEpsilon(90, 0), -100.0, kLooseGeomTol);
}

// Covers CPA engine encounter behavior: public init non cache clears cached geometry.
TEST(CPAEngineEncounterTest, PublicInitNonCacheClearsCachedGeometry)
{
  CPAEngine engine(100, 50, 0, 1, 0, 0);
  ASSERT_GT(engine.getRange(), 0.0);

  engine.initNonCache();

  EXPECT_NEAR(engine.getRange(), 0.0, kGeomTol);
  EXPECT_NEAR(engine.getRangeGamma(), 0.0, kGeomTol);
  EXPECT_NEAR(engine.getRangeEpsilon(), 0.0, kGeomTol);
  EXPECT_FALSE(engine.foreOfContact());
  EXPECT_FALSE(engine.aftOfContact());
  EXPECT_FALSE(engine.portOfContact());
  EXPECT_FALSE(engine.starOfContact());
}

// Covers CPA engine encounter behavior: handles stationary contact intercept.
TEST(CPAEngineEncounterTest, HandlesStationaryContactIntercept)
{
  CPAEngine engine(50, 50, 90, 0, 0, 0);

  EXPECT_NEAR(engine.getRange(), 70.7106781187, kLooseGeomTol);
  EXPECT_NEAR(engine.evalCPA(45, 1, 120), 0.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(45, 1, 120), 70.7106781187, kLooseGeomTol);
  EXPECT_NEAR(engine.evalROC(45, 1), 1.0, kGeomTol);
  EXPECT_TRUE(engine.crossesBowOrStern(45, 1));
  EXPECT_TRUE(engine.passesPortOrStar(45, 1));
  EXPECT_FALSE(engine.passesPort(45, 1));
  EXPECT_TRUE(engine.passesStar(45, 1));
}

// Covers CPA engine encounter behavior: resets geometry and cached classification.
TEST(CPAEngineEncounterTest, ResetsGeometryAndCachedClassification)
{
  CPAEngine engine(100, 0, 180, 2, 0, 0);
  engine.reset(0, 100, 270, 1, 0, 0);

  EXPECT_NEAR(engine.getRange(), 100.0, kGeomTol);
  EXPECT_NEAR(engine.osToCNAbsBng(), 90.0, kGeomTol);
  EXPECT_NEAR(engine.ownshipContactRelBearing(90), 0.0, kGeomTol);
  EXPECT_TRUE(engine.foreOfContact());
  EXPECT_TRUE(engine.portOfContact());
  EXPECT_NEAR(engine.evalCPA(90, 2, 120), 0.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(90, 2, 120), 33.3333333333, kLooseGeomTol);
  EXPECT_NEAR(engine.evalROC(90, 2), 3.0, kGeomTol);
  EXPECT_TRUE(engine.crossesBowOrStern(90, 2));
  EXPECT_TRUE(engine.passesPortOrStar(90, 2));
  EXPECT_TRUE(engine.passesStar(90, 2));
}

// Covers CPA engine turn behavior: turn direction pins wrap and one eighty tie behavior.
TEST(CPAEngineTurnTest, TurnDirectionPinsWrapAndOneEightyTieBehavior)
{
  CPAEngine engine;

  EXPECT_TRUE(engine.turnsRight(350, 10));
  EXPECT_FALSE(engine.turnsLeft(350, 10));
  EXPECT_FALSE(engine.turnsRight(10, 350));
  EXPECT_TRUE(engine.turnsLeft(10, 350));
  EXPECT_FALSE(engine.turnsRight(0, 180));
  EXPECT_FALSE(engine.turnsLeft(0, 180));
  EXPECT_FALSE(engine.turnsRight(90, 90));
  EXPECT_FALSE(engine.turnsLeft(90, 90));
}

// Covers CPA engine encounter behavior: samples min and max rate of closure by heading grid.
TEST(CPAEngineEncounterTest, SamplesMinAndMaxRateOfClosureByHeadingGrid)
{
  CPAEngine engine(100, 100, 270, 2, 0, 0);

  double min_roc = 0;
  double max_roc = 0;
  double max_heading = engine.minMaxROC(2, 8, min_roc, max_roc);

  EXPECT_NEAR(max_heading, 45.0, kGeomTol);
  EXPECT_NEAR(min_roc, -0.5857864376, kLooseGeomTol);
  EXPECT_NEAR(max_roc, 3.4142135624, kLooseGeomTol);
}
