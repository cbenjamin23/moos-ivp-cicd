#include <cmath>

#include <gtest/gtest.h>

#include "CPAEngine.h"
#include "CPAEngineRoot.h"
#include "CPAEngineThin.h"
#include "CPAEngineV15.h"
#include "NumericAssertions.h"

namespace {

struct Encounter {
  double cny;
  double cnx;
  double cnh;
  double cnv;
  double osy;
  double osx;
  double osh;
  double osv;
  double ostol;
};

CPAEngine makeEngine(const Encounter& enc)
{
  return CPAEngine(enc.cny, enc.cnx, enc.cnh, enc.cnv, enc.osy, enc.osx);
}

CPAEngineThin makeThin(const Encounter& enc)
{
  return CPAEngineThin(enc.cny, enc.cnx, enc.cnh, enc.cnv, enc.osy, enc.osx);
}

CPAEngineV15 makeV15(const Encounter& enc)
{
  return CPAEngineV15(enc.cny, enc.cnx, enc.cnh, enc.cnv, enc.osy, enc.osx);
}

void expectModernAndThinMatch(const Encounter& enc)
{
  CPAEngine engine = makeEngine(enc);
  CPAEngineThin thin = makeThin(enc);

  EXPECT_NEAR(thin.getRange(), engine.getRange(), kGeomTol);
  EXPECT_NEAR(thin.evalCPA(enc.osh, enc.osv, enc.ostol),
              engine.evalCPA(enc.osh, enc.osv, enc.ostol), kGeomTol);
  EXPECT_NEAR(thin.evalTimeCPA(enc.osh, enc.osv, enc.ostol),
              engine.evalTimeCPA(enc.osh, enc.osv, enc.ostol), kGeomTol);
  EXPECT_NEAR(thin.evalROC(enc.osh, enc.osv), engine.evalROC(enc.osh, enc.osv),
              kGeomTol);
  double thin_bearing_rate = thin.bearingRate(enc.osh, enc.osv);
  double engine_bearing_rate = engine.bearingRate(enc.osh, enc.osv);
  if(std::isinf(thin_bearing_rate) || std::isinf(engine_bearing_rate)) {
    EXPECT_TRUE(std::isinf(thin_bearing_rate));
    EXPECT_TRUE(std::isinf(engine_bearing_rate));
    EXPECT_EQ(std::signbit(thin_bearing_rate), std::signbit(engine_bearing_rate));
  }
  else {
    EXPECT_NEAR(thin_bearing_rate, engine_bearing_rate, kGeomTol);
  }

  EXPECT_EQ(thin.foreOfContact(), engine.foreOfContact());
  EXPECT_EQ(thin.aftOfContact(), engine.aftOfContact());
  EXPECT_EQ(thin.portOfContact(), engine.portOfContact());
  EXPECT_EQ(thin.starboardOfContact(), engine.starOfContact());
  EXPECT_EQ(thin.crossesBow(enc.osh, enc.osv),
            engine.crossesBow(enc.osh, enc.osv));
  EXPECT_EQ(thin.crossesStern(enc.osh, enc.osv),
            engine.crossesStern(enc.osh, enc.osv));
  EXPECT_EQ(thin.crossesBowOrStern(enc.osh, enc.osv),
            engine.crossesBowOrStern(enc.osh, enc.osv));
  EXPECT_EQ(thin.passesPortOrStar(enc.osh, enc.osv),
            engine.passesPortOrStar(enc.osh, enc.osv));
  EXPECT_EQ(thin.passesPort(enc.osh, enc.osv),
            engine.passesPort(enc.osh, enc.osv));
  EXPECT_EQ(thin.passesStar(enc.osh, enc.osv),
            engine.passesStar(enc.osh, enc.osv));
}

void expectV15CpaNearModern(const Encounter& enc)
{
  CPAEngine engine = makeEngine(enc);
  CPAEngineV15 v15 = makeV15(enc);

  EXPECT_NEAR(v15.evalCPA(enc.osh, enc.osv, enc.ostol),
              engine.evalCPA(enc.osh, enc.osv, enc.ostol), kLooseGeomTol);
}

}  // namespace

// Covers CPA engine root variant behavior: base class pins stub evaluation and counters.
TEST(CPAEngineRootVariantTest, BaseClassPinsStubEvaluationAndCounters)
{
  // CPAEngineRoot is a stub base: it preserves construction/reset data but
  // returns neutral CPA values until a concrete engine implements evaluation.
  CPAEngineRoot root(5, 6, 725, -2, 1, 2);

  EXPECT_NEAR(root.evalCPA(0, 1, 2), 0.0, kGeomTol);
  EXPECT_NEAR(root.evalCPAX(0, 1, 2), 0.0, kGeomTol);
  EXPECT_EQ(root.getOpenings(), 0u);
  EXPECT_EQ(root.getOpeningsEarly(), 0u);

  root.reset(10, 20, -90, -5, 3, 4);
  EXPECT_NEAR(root.evalCPA(180, 3, 20), 0.0, kGeomTol);
  EXPECT_NEAR(root.evalCPAX(180, 3, 20), 0.0, kGeomTol);
}

// Covers CPA modern thin equivalence behavior: head on contact matches and clips at time on leg.
TEST(CPAModernThinEquivalenceTest, HeadOnContactMatchesAndClipsAtTimeOnLeg)
{
  Encounter head_on = {100, 0, 180, 2, 0, 0, 0, 2, 60};
  expectModernAndThinMatch(head_on);
  expectV15CpaNearModern(head_on);

  CPAEngine engine = makeEngine(head_on);
  EXPECT_NEAR(engine.evalCPA(head_on.osh, head_on.osv, head_on.ostol), 0.0,
              kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(head_on.osh, head_on.osv, head_on.ostol),
              25.0, kGeomTol);

  head_on.ostol = 10;
  expectModernAndThinMatch(head_on);
  expectV15CpaNearModern(head_on);
  EXPECT_NEAR(makeEngine(head_on).evalCPA(head_on.osh, head_on.osv,
                                          head_on.ostol),
              60.0, kGeomTol);
}

// Covers CPA modern thin equivalence behavior: modern thin and V15 pin literal negative time on leg.
TEST(CPAModernThinEquivalenceTest, ModernThinAndV15PinLiteralNegativeTimeOnLeg)
{
  // Negative time-on-leg is passed through literally rather than clipped to
  // zero, so CPA can increase beyond the current range in a head-on case.
  Encounter head_on = {100, 0, 180, 2, 0, 0, 0, 2, 0};
  CPAEngine engine = makeEngine(head_on);
  CPAEngineThin thin = makeThin(head_on);
  CPAEngineV15 v15 = makeV15(head_on);

  EXPECT_NEAR(engine.evalCPA(head_on.osh, head_on.osv, 0), 100.0,
              kGeomTol);
  EXPECT_NEAR(thin.evalCPA(head_on.osh, head_on.osv, 0), 100.0,
              kGeomTol);
  EXPECT_NEAR(v15.evalCPA(head_on.osh, head_on.osv, 0), 100.0,
              kGeomTol);

  EXPECT_NEAR(engine.evalCPA(head_on.osh, head_on.osv, -1), 104.0,
              kGeomTol);
  EXPECT_NEAR(thin.evalCPA(head_on.osh, head_on.osv, -1), 104.0,
              kGeomTol);
  EXPECT_NEAR(v15.evalCPA(head_on.osh, head_on.osv, -1), 104.0,
              kGeomTol);
}

// Covers CPA modern thin equivalence behavior: crossing contact reaches zero CPA.
TEST(CPAModernThinEquivalenceTest, CrossingContactReachesZeroCpa)
{
  Encounter crossing = {100, 100, 270, 2, 0, 0, 0, 2, 120};
  expectModernAndThinMatch(crossing);
  expectV15CpaNearModern(crossing);

  CPAEngine engine = makeEngine(crossing);
  EXPECT_NEAR(engine.getRange(), 141.4213562373, kLooseGeomTol);
  EXPECT_NEAR(engine.evalCPA(crossing.osh, crossing.osv, crossing.ostol), 0.0,
              kLooseGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(crossing.osh, crossing.osv, crossing.ostol),
              50.0, kGeomTol);
  EXPECT_TRUE(engine.crossesBow(crossing.osh, crossing.osv));
  EXPECT_TRUE(engine.crossesStern(crossing.osh, crossing.osv));
  EXPECT_TRUE(engine.passesStar(crossing.osh, crossing.osv));
}

// Covers CPA modern thin equivalence behavior: overtaking contact closes from aft.
TEST(CPAModernThinEquivalenceTest, OvertakingContactClosesFromAft)
{
  Encounter overtaking = {100, 0, 0, 1, 0, 0, 0, 3, 120};
  expectModernAndThinMatch(overtaking);
  expectV15CpaNearModern(overtaking);

  CPAEngine engine = makeEngine(overtaking);
  EXPECT_TRUE(engine.aftOfContact());
  EXPECT_TRUE(engine.crossesStern(overtaking.osh, overtaking.osv));
  EXPECT_NEAR(engine.crossesSternDist(overtaking.osh, overtaking.osv), 100.0,
              kGeomTol);
  EXPECT_NEAR(engine.evalCPA(overtaking.osh, overtaking.osv, overtaking.ostol),
              0.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(overtaking.osh, overtaking.osv,
                                 overtaking.ostol),
              50.0, kGeomTol);
}

// Covers CPA modern thin equivalence behavior: parallel same speed contact is opening.
TEST(CPAModernThinEquivalenceTest, ParallelSameSpeedContactIsOpening)
{
  Encounter opening = {100, 0, 0, 2, 0, 0, 0, 2, 60};
  expectModernAndThinMatch(opening);
  expectV15CpaNearModern(opening);

  CPAEngine engine = makeEngine(opening);
  EXPECT_NEAR(engine.evalCPA(opening.osh, opening.osv, opening.ostol), 100.0,
              kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(opening.osh, opening.osv, opening.ostol), 0.0,
              kGeomTol);
  EXPECT_FALSE(engine.passesPortOrStar(opening.osh, opening.osv));
}

// Covers CPA modern thin equivalence behavior: stationary contact intercept matches.
TEST(CPAModernThinEquivalenceTest, StationaryContactInterceptMatches)
{
  Encounter stationary = {50, 50, 90, 0, 0, 0, 45, 1, 120};
  expectModernAndThinMatch(stationary);
  expectV15CpaNearModern(stationary);

  CPAEngine engine = makeEngine(stationary);
  EXPECT_NEAR(engine.evalCPA(stationary.osh, stationary.osv, stationary.ostol),
              0.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(stationary.osh, stationary.osv,
                                 stationary.ostol),
              70.7106781187, kLooseGeomTol);
  EXPECT_TRUE(engine.crossesBowOrStern(stationary.osh, stationary.osv));
  EXPECT_TRUE(engine.passesPortOrStar(stationary.osh, stationary.osv));
}

// Covers CPA modern thin equivalence behavior: negative contact speed is treated as stationary.
TEST(CPAModernThinEquivalenceTest, NegativeContactSpeedIsTreatedAsStationary)
{
  Encounter negative_speed = {50, 0, 90, -5, 0, 0, 0, 1, 120};
  expectModernAndThinMatch(negative_speed);
  expectV15CpaNearModern(negative_speed);

  CPAEngine engine = makeEngine(negative_speed);
  EXPECT_NEAR(engine.evalCPA(negative_speed.osh, negative_speed.osv,
                             negative_speed.ostol),
              0.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(negative_speed.osh, negative_speed.osv,
                                 negative_speed.ostol),
              50.0, kGeomTol);
  EXPECT_NEAR(engine.evalROC(negative_speed.osh, negative_speed.osv), 1.0,
              kGeomTol);
}

// Covers CPA modern thin equivalence behavior: reset recomputes cached geometry.
TEST(CPAModernThinEquivalenceTest, ResetRecomputesCachedGeometry)
{
  CPAEngine engine(100, 0, 180, 2, 0, 0);
  CPAEngineThin thin(100, 0, 180, 2, 0, 0);

  engine.reset(0, 100, 270, 1, 0, 0);
  thin.reset(0, 100, 270, 1, 0, 0);

  EXPECT_NEAR(thin.getRange(), engine.getRange(), kGeomTol);
  EXPECT_NEAR(engine.osToCNAbsBng(), 90.0, kGeomTol);
  EXPECT_TRUE(engine.foreOfContact());
  EXPECT_TRUE(engine.portOfContact());
  EXPECT_NEAR(engine.evalCPA(90, 2, 120), 0.0, kGeomTol);
  EXPECT_NEAR(engine.evalTimeCPA(90, 2, 120), 33.3333333333,
              kLooseGeomTol);
  EXPECT_NEAR(thin.evalCPA(90, 2, 120), engine.evalCPA(90, 2, 120),
              kGeomTol);
  EXPECT_TRUE(thin.crossesBowOrStern(90, 2));
  EXPECT_TRUE(thin.passesStar(90, 2));
}

// Covers CPA modern thin equivalence behavior: wrapped and fractional headings use current integer cache behavior.
TEST(CPAModernThinEquivalenceTest, WrappedAndFractionalHeadingsUseCurrentIntegerCacheBehavior)
{
  // These cases pin the integer heading cache used by the modern/thin engines:
  // wrapped headings normalize, while fractional headings are effectively binned.
  Encounter wrapped = {100, 0, 540, 2, 0, 0, 360, 2, 60};
  expectModernAndThinMatch(wrapped);
  expectV15CpaNearModern(wrapped);

  CPAEngine wrapped_engine = makeEngine(wrapped);
  EXPECT_NEAR(wrapped_engine.evalCPA(wrapped.osh, wrapped.osv, wrapped.ostol),
              0.0, kGeomTol);
  EXPECT_NEAR(wrapped_engine.evalTimeCPA(wrapped.osh, wrapped.osv,
                                         wrapped.ostol),
              25.0, kGeomTol);

  Encounter fractional = {10, 10, 225, 1.5, 0, 0, 44.9, 1.25, 50};
  expectModernAndThinMatch(fractional);
  CPAEngine fractional_engine = makeEngine(fractional);
  EXPECT_NEAR(fractional_engine.evalCPA(fractional.osh, fractional.osv,
                                        fractional.ostol),
              0.112193, kLooseGeomTol);
  EXPECT_NEAR(fractional_engine.evalTimeCPA(fractional.osh, fractional.osv,
                                            fractional.ostol),
              5.14263, kLooseGeomTol);
}

// Covers CPA bow stern geometry behavior: modern and thin pin bowline and sternline sentinels.
TEST(CPABowSternGeometryTest, ModernAndThinPinBowlineAndSternlineSentinels)
{
  Encounter bowline = {100, 0, 0, 1, 0, 0, 0, 2, 120};
  expectModernAndThinMatch(bowline);
  CPAEngine bow = makeEngine(bowline);
  EXPECT_TRUE(bow.crossesBow(bowline.osh, bowline.osv));
  EXPECT_NEAR(bow.crossesBowDist(bowline.osh, bowline.osv), -1.0,
              kGeomTol);
  EXPECT_TRUE(bow.crossesStern(bowline.osh, bowline.osv));
  EXPECT_NEAR(bow.crossesSternDist(bowline.osh, bowline.osv), 100.0,
              kGeomTol);

  Encounter sternline = {-100, 0, 0, 1, 0, 0, 0, 2, 120};
  expectModernAndThinMatch(sternline);
  CPAEngine stern = makeEngine(sternline);
  EXPECT_FALSE(stern.crossesBow(sternline.osh, sternline.osv));
  EXPECT_NEAR(stern.crossesBowDist(sternline.osh, sternline.osv), 100.0,
              kGeomTol);
  EXPECT_FALSE(stern.crossesStern(sternline.osh, sternline.osv));
  EXPECT_NEAR(stern.crossesSternDist(sternline.osh, sternline.osv), -1.0,
              kGeomTol);
}

// Covers CPA bow stern geometry behavior: beam transit reports stern crossing distance.
TEST(CPABowSternGeometryTest, BeamTransitReportsSternCrossingDistance)
{
  Encounter beam = {100, 50, 0, 1, 0, 0, 90, 2, 120};
  expectModernAndThinMatch(beam);
  expectV15CpaNearModern(beam);

  CPAEngine engine = makeEngine(beam);
  EXPECT_FALSE(engine.crossesBow(beam.osh, beam.osv));
  EXPECT_TRUE(engine.crossesStern(beam.osh, beam.osv));
  EXPECT_NEAR(engine.crossesSternDist(beam.osh, beam.osv), 125.0, kGeomTol);
  EXPECT_NEAR(engine.evalCPA(beam.osh, beam.osv, beam.ostol),
              engine.getRange(), kGeomTol);
}

// Covers CPA pass geometry behavior: port and starboard pass distances mirror.
TEST(CPAPassGeometryTest, PortAndStarboardPassDistancesMirror)
{
  Encounter port = {100, 50, 0, 1, 0, 0, 0, 3, 120};
  expectModernAndThinMatch(port);
  CPAEngine port_engine = makeEngine(port);
  EXPECT_TRUE(port_engine.passesPort(port.osh, port.osv));
  EXPECT_FALSE(port_engine.passesStar(port.osh, port.osv));
  EXPECT_NEAR(port_engine.passesPortDist(port.osh, port.osv), 50.0,
              kGeomTol);
  EXPECT_NEAR(port_engine.passesStarDist(port.osh, port.osv), -1.0,
              kGeomTol);

  Encounter starboard = {100, -50, 0, 1, 0, 0, 0, 3, 120};
  expectModernAndThinMatch(starboard);
  CPAEngine star_engine = makeEngine(starboard);
  EXPECT_FALSE(star_engine.passesPort(starboard.osh, starboard.osv));
  EXPECT_TRUE(star_engine.passesStar(starboard.osh, starboard.osv));
  EXPECT_NEAR(star_engine.passesPortDist(starboard.osh, starboard.osv), -1.0,
              kGeomTol);
  EXPECT_NEAR(star_engine.passesStarDist(starboard.osh, starboard.osv), 50.0,
              kGeomTol);
}

// Covers CPA engine thin variant behavior: min max ROC pins legacy zero accumulator quirk.
TEST(CPAEngineThinVariantTest, MinMaxROCPinsLegacyZeroAccumulatorQuirk)
{
  CPAEngine engine(100, 100, 270, 2, 0, 0);
  CPAEngineThin thin(100, 100, 270, 2, 0, 0);

  double engine_min = 0;
  double engine_max = 0;
  double thin_min = 0;
  double thin_max = 0;

  EXPECT_NEAR(engine.minMaxROC(2, 8, engine_min, engine_max), 45.0,
              kGeomTol);
  EXPECT_NEAR(engine_min, -0.5857864376, kLooseGeomTol);
  EXPECT_NEAR(engine_max, 3.4142135624, kLooseGeomTol);

  // CPAEngineThin calls evalROC while scanning headings but never stores the
  // result in its accumulator, so the legacy return and output extrema stay 0.
  EXPECT_NEAR(thin.minMaxROC(2, 8, thin_min, thin_max), 0.0, kGeomTol);
  EXPECT_NEAR(thin_min, 0.0, kGeomTol);
  EXPECT_NEAR(thin_max, 0.0, kGeomTol);
}

// Covers CPA engine V15 variant behavior: CPA matches modern but ROC is unnormalized polynomial rate.
TEST(CPAEngineV15VariantTest, CpaMatchesModernButRocIsUnnormalizedPolynomialRate)
{
  Encounter head_on = {100, 0, 180, 2, 0, 0, 0, 2, 60};
  CPAEngine engine = makeEngine(head_on);
  CPAEngineV15 v15 = makeV15(head_on);

  double calc_roc = 0;
  EXPECT_NEAR(v15.evalCPA(head_on.osh, head_on.osv, head_on.ostol, &calc_roc),
              engine.evalCPA(head_on.osh, head_on.osv, head_on.ostol),
              kGeomTol);
  EXPECT_NEAR(engine.evalROC(head_on.osh, head_on.osv), 4.0, kGeomTol);
  EXPECT_NEAR(calc_roc, 800.0, kGeomTol);
  EXPECT_NEAR(v15.evalROC(head_on.osh, head_on.osv), 800.0, kGeomTol);
}

// Covers CPA engine V15 variant behavior: legacy bowline and sternline classifications differ from modern.
TEST(CPAEngineV15VariantTest, LegacyBowlineAndSternlineClassificationsDifferFromModern)
{
  // V15 keeps legacy bow/stern line classification rules even when CPA values
  // are close to the modern engine.
  Encounter bowline = {100, 0, 0, 1, 0, 0, 0, 2, 120};
  CPAEngine modern_bow = makeEngine(bowline);
  CPAEngineV15 v15_bow = makeV15(bowline);
  EXPECT_NEAR(v15_bow.evalCPA(bowline.osh, bowline.osv, bowline.ostol),
              modern_bow.evalCPA(bowline.osh, bowline.osv, bowline.ostol),
              kGeomTol);
  EXPECT_TRUE(modern_bow.crossesBow(bowline.osh, bowline.osv));
  EXPECT_TRUE(modern_bow.crossesStern(bowline.osh, bowline.osv));
  EXPECT_FALSE(v15_bow.crossesBow(bowline.osh, bowline.osv));
  EXPECT_TRUE(v15_bow.crossesStern(bowline.osh, bowline.osv));
  EXPECT_TRUE(v15_bow.passesContactPort(bowline.osh, bowline.osv));
  EXPECT_FALSE(v15_bow.passesContactStarboard(bowline.osh, bowline.osv));

  Encounter sternline = {-100, 0, 0, 1, 0, 0, 0, 2, 120};
  CPAEngine modern_stern = makeEngine(sternline);
  CPAEngineV15 v15_stern = makeV15(sternline);
  EXPECT_NEAR(v15_stern.evalCPA(sternline.osh, sternline.osv,
                                sternline.ostol),
              modern_stern.evalCPA(sternline.osh, sternline.osv,
                                   sternline.ostol),
              kGeomTol);
  EXPECT_FALSE(modern_stern.crossesBow(sternline.osh, sternline.osv));
  EXPECT_FALSE(modern_stern.crossesStern(sternline.osh, sternline.osv));
  EXPECT_TRUE(v15_stern.crossesBow(sternline.osh, sternline.osv));
  EXPECT_FALSE(v15_stern.crossesStern(sternline.osh, sternline.osv));
}

// Covers CPA engine V15 variant behavior: crossing and stationary pass side differs from modern.
TEST(CPAEngineV15VariantTest, CrossingAndStationaryPassSideDiffersFromModern)
{
  Encounter crossing = {100, 100, 270, 2, 0, 0, 0, 2, 120};
  CPAEngine modern_crossing = makeEngine(crossing);
  CPAEngineV15 v15_crossing = makeV15(crossing);
  EXPECT_TRUE(modern_crossing.crossesBow(crossing.osh, crossing.osv));
  EXPECT_TRUE(modern_crossing.crossesStern(crossing.osh, crossing.osv));
  EXPECT_NEAR(v15_crossing.crossesBowDist(crossing.osh, crossing.osv), 0.0,
              kLooseGeomTol);
  EXPECT_NEAR(v15_crossing.crossesSternDist(crossing.osh, crossing.osv), 0.0,
              kLooseGeomTol);
  EXPECT_FALSE(v15_crossing.passesContactPort(crossing.osh, crossing.osv));
  EXPECT_TRUE(v15_crossing.passesContactStarboard(crossing.osh, crossing.osv));

  Encounter stationary = {50, 50, 90, 0, 0, 0, 45, 1, 120};
  CPAEngine modern_stationary = makeEngine(stationary);
  CPAEngineV15 v15_stationary = makeV15(stationary);
  EXPECT_FALSE(modern_stationary.passesPort(stationary.osh, stationary.osv));
  EXPECT_TRUE(modern_stationary.passesStar(stationary.osh, stationary.osv));
  EXPECT_TRUE(v15_stationary.passesContactPort(stationary.osh, stationary.osv));
  EXPECT_FALSE(v15_stationary.passesContactStarboard(stationary.osh,
                                                     stationary.osv));
}

// Covers CPA engine V15 variant behavior: exposes contact state and accepts cache configuration.
TEST(CPAEngineV15VariantTest, ExposesContactStateAndAcceptsCacheConfiguration)
{
  Encounter encounter = {100, 50, 270, 2, 0, 0, 0, 2, 120};
  CPAEngineV15 v15 = makeV15(encounter);

  EXPECT_NEAR(v15.getcnLAT(), 100.0, kGeomTol);
  EXPECT_NEAR(v15.getcnLON(), 50.0, kGeomTol);
  EXPECT_NEAR(v15.getcnCRS(), 270.0, kGeomTol);
  EXPECT_NEAR(v15.getcnSPD(), 2.0, kGeomTol);
  EXPECT_NEAR(v15.getK0(), 12500.0, kGeomTol);

  double baseline = v15.evalCPA(encounter.osh, encounter.osv, encounter.ostol);
  v15.setContactCacheTimeDelta(0.05);
  v15.setContactCache(-1);
  EXPECT_NEAR(v15.evalCPA(encounter.osh, encounter.osv, encounter.ostol),
              baseline, kGeomTol);

  v15.setContactCacheTimeDelta(0.5);
  v15.setContactCache(5);
  EXPECT_NEAR(v15.evalCPA(encounter.osh, encounter.osv, encounter.ostol),
              baseline, kGeomTol);
}

// Covers CPA engine V15 variant behavior: crosses lines uses unnormalized ownship heading.
TEST(CPAEngineV15VariantTest, CrossesLinesUsesUnnormalizedOwnshipHeading)
{
  Encounter wrapped = {100, 0, 540, 2, 0, 0, 360, 2, 60};
  CPAEngine engine = makeEngine(wrapped);
  CPAEngineV15 v15 = makeV15(wrapped);

  EXPECT_NEAR(v15.evalCPA(wrapped.osh, wrapped.osv, wrapped.ostol),
              engine.evalCPA(wrapped.osh, wrapped.osv, wrapped.ostol),
              kGeomTol);
  EXPECT_TRUE(v15.crossesLines(0));
  // The line-crossing helper compares the raw ownship heading in one branch,
  // so 360 behaves differently from the equivalent normalized heading 0.
  EXPECT_FALSE(v15.crossesLines(360));
}

// Covers CPA engine V15 variant behavior: bearing rate finite difference tracks modern sign.
TEST(CPAEngineV15VariantTest, BearingRateFiniteDifferenceTracksModernSign)
{
  Encounter port_pass = {100, 50, 0, 1, 0, 0, 0, 3, 120};
  CPAEngine engine = makeEngine(port_pass);
  CPAEngineThin thin = makeThin(port_pass);
  CPAEngineV15 v15 = makeV15(port_pass);

  EXPECT_NEAR(engine.bearingRate(port_pass.osh, port_pass.osv),
              engine.bearingRateOld(port_pass.osh, port_pass.osv),
              kLooseGeomTol);
  EXPECT_NEAR(thin.bearingRate(port_pass.osh, port_pass.osv),
              engine.bearingRate(port_pass.osh, port_pass.osv),
              kLooseGeomTol);
  EXPECT_NEAR(v15.bearingRateOSCN(port_pass.osh, port_pass.osv, 1),
              0.4584738148, kLooseGeomTol);
  EXPECT_NEAR(v15.bearingRateCNOS(port_pass.osh, port_pass.osv, 1),
              0.4584738148, kLooseGeomTol);
  EXPECT_GT(v15.bearingRateOSCN(port_pass.osh, port_pass.osv, 1),
            engine.bearingRate(port_pass.osh, port_pass.osv));
  EXPECT_NEAR(v15.bearingRateOSCN(port_pass.osh, port_pass.osv, 0), 0.0,
              kGeomTol);
  EXPECT_NEAR(v15.bearingRateCNOS(port_pass.osh, port_pass.osv, 0), 0.0,
              kGeomTol);
}

// Covers CPA engine variant edge case behavior: same point pins zero range special cases.
TEST(CPAEngineVariantEdgeCaseTest, SamePointPinsZeroRangeSpecialCases)
{
  // Same-position encounters are singular for bearing-rate and pass-side logic;
  // this test documents current zero-range behavior across engine variants.
  Encounter same_point = {0, 0, 90, 1, 0, 0, 45, 2, 120};
  expectModernAndThinMatch(same_point);
  expectV15CpaNearModern(same_point);

  CPAEngine engine = makeEngine(same_point);
  CPAEngineV15 v15 = makeV15(same_point);

  EXPECT_NEAR(engine.getRange(), 0.0, kGeomTol);
  EXPECT_TRUE(std::isinf(engine.bearingRate(same_point.osh, same_point.osv)));
  EXPECT_TRUE(engine.crossesBow(same_point.osh, same_point.osv));
  EXPECT_FALSE(engine.crossesStern(same_point.osh, same_point.osv));
  EXPECT_TRUE(engine.passesPortOrStar(same_point.osh, same_point.osv));
  EXPECT_FALSE(engine.passesPort(same_point.osh, same_point.osv));
  EXPECT_FALSE(engine.passesStar(same_point.osh, same_point.osv));

  EXPECT_TRUE(v15.crossesBow(same_point.osh, same_point.osv));
  EXPECT_TRUE(v15.crossesStern(same_point.osh, same_point.osv));
  EXPECT_FALSE(v15.passesContact(same_point.osh, same_point.osv));
}
