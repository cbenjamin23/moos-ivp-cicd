#include <gtest/gtest.h>

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "BFactoryStatic.h"
#include "BFactoryDynamic.h"
#include "BHV_OpRegionV26.h"
#include "BehaviorSet.h"
#include "BehaviorSpec.h"
#include "InfoBuffer.h"
#include "IvPBehavior.h"
#include "IvPBuildTestUtils.h"
#include "LedgerSnap.h"
#include "PMGen_Dubins.h"
#include "PMGen_Holonomic.h"
#include "PlatModelGenerator.h"
#include "Populator_BehaviorSet.h"
#include "SpecBuild.h"
#include "TestFileUtils.h"
#include "VarDataPair.h"
#include "XYPoint.h"
#include "XYSeglr.h"

namespace {

BehaviorSpec waypointSpec(const std::string& name, unsigned int line = 10)
{
  BehaviorSpec spec;
  spec.setFileName("meta_vehicle.bhv");
  spec.setBehaviorKind("BHV_Waypoint", line);
  spec.addBehaviorConfig("name=" + name, line + 1);
  spec.addBehaviorConfig("pwt=100", line + 2);
  spec.addBehaviorConfig("points=pts={0,0:100,0}", line + 3);
  spec.addBehaviorConfig("speed=2.0", line + 4);
  spec.addBehaviorConfig("radius=5", line + 5);
  return spec;
}

bool containsText(const std::vector<std::string>& values,
                  const std::string& needle)
{
  return std::any_of(values.begin(), values.end(),
                     [&](const std::string& value) {
                       return value.find(needle) != std::string::npos;
                     });
}

class HelmStartBehavior : public IvPBehavior {
 public:
  HelmStartBehavior() : IvPBehavior(makeCourseSpeedDomain()) {}

  bool setName(const std::string& name) { return setBehaviorName(name); }

  void postStartupMessage()
  {
    postMessage("HELM_START_TEST", "ready");
  }
};

}  // namespace

// Covers b factory static behavior: builds known static behaviors only after domain is configured.
TEST(BFactoryStaticTest, BuildsKnownStaticBehaviorsOnlyAfterDomainIsConfigured)
{
  BFactoryStatic factory;
  EXPECT_TRUE(factory.isKnownBehavior("BHV_Waypoint"));
  EXPECT_TRUE(factory.isKnownBehavior("BHV_AvdColregsV22"));
  EXPECT_TRUE(factory.isKnownBehavior("BHV_OpRegionV26"));
  EXPECT_FALSE(factory.isKnownBehavior("BHV_NotARealBehavior"));
  EXPECT_EQ(factory.newBehavior("BHV_Waypoint"), nullptr);

  factory.setDomain(makeCourseSpeedDomain());
  std::unique_ptr<IvPBehavior> waypoint(factory.newBehavior("BHV_Waypoint"));
  ASSERT_NE(waypoint, nullptr);
  EXPECT_EQ(waypoint->getBehaviorType(), "");
  EXPECT_EQ(waypoint->getDescriptor(), "bhv_waypoint");

  std::unique_ptr<IvPBehavior> colregs(factory.newBehavior("BHV_AvdColregsV22"));
  ASSERT_NE(colregs, nullptr);
  EXPECT_TRUE(colregs->isConstraint());

  // Keep both probes: pHelmIvP gates behavior loading with isKnownBehavior(),
  // while newBehavior() exercises construction and the lib_gen_poly link.
  std::unique_ptr<IvPBehavior> opregion_v26(factory.newBehavior("BHV_OpRegionV26"));
  ASSERT_NE(opregion_v26, nullptr);
  EXPECT_NE(dynamic_cast<BHV_OpRegionV26*>(opregion_v26.get()), nullptr);
}

// Covers b factory dynamic behavior: handles empty and non behavior directories without registration.
TEST(BFactoryDynamicTest, HandlesEmptyAndNonBehaviorDirectoriesWithoutRegistration)
{
  TempDir dir("dynamic_behavior_factory");
  // These intentionally avoid real libBHV_*.so/.dylib names; the test is about
  // ignoring non-behavior files, not invoking platform dynamic loading.
  dir.writeFile("notes.txt", "not a behavior library\n");
  dir.writeFile("BHV_NoSharedLibrary.txt", "wrong suffix\n");

  BFactoryDynamic factory;
  EXPECT_FALSE(factory.loadDirectory(dir.filePath("missing")));
  EXPECT_TRUE(factory.loadDirectory(dir.path()));
  EXPECT_TRUE(factory.loadDirectory(dir.path() + "/"));
  EXPECT_FALSE(factory.isKnownBehavior("BHV_NoSharedLibrary"));
  EXPECT_EQ(factory.newBehavior("BHV_NoSharedLibrary"), nullptr);

  factory.setDomain(makeCourseSpeedDomain());
  EXPECT_EQ(factory.newBehavior("BHV_NoSharedLibrary"), nullptr);
}

// Covers b factory dynamic behavior: loads only directories listed by environment variable.
TEST(BFactoryDynamicTest, LoadsOnlyDirectoriesListedByEnvironmentVariable)
{
  TempDir dir("dynamic_behavior_env");
  dir.writeFile("README", "empty dynamic behavior directory\n");
  // Use a test-only environment variable so local IVP_BEHAVIOR_DIRS settings
  // cannot affect the factory contents.
  ScopedEnv env("MOOS_IVP_TEST_DYNAMIC_BEHAVIORS",
                dir.path() + ":/definitely/not/a/moos/behavior/dir");

  BFactoryDynamic factory;
  factory.setDomain(makeCourseSpeedDomain());
  testing::internal::CaptureStdout();
  testing::internal::CaptureStderr();
  factory.loadEnvVarDirectories("MOOS_IVP_TEST_DYNAMIC_BEHAVIORS");
  std::string stderr_text = testing::internal::GetCapturedStderr();
  std::string stdout_text = testing::internal::GetCapturedStdout();

  EXPECT_NE(stdout_text.find("Loading directory"), std::string::npos);
  EXPECT_NE(stderr_text.find("Skipping"), std::string::npos);
  EXPECT_FALSE(factory.isKnownBehavior("BHV_Waypoint"));
}

// Covers spec build behavior: tracks behavior kind bad config lines and drains helm start messages.
TEST(SpecBuildTest, TracksBehaviorKindBadConfigLinesAndDrainsHelmStartMessages)
{
  SpecBuild build;
  build.setBehaviorKind("BHV_Waypoint", 42);
  build.setKindResult("static");
  build.addBadConfig("speed=fast", 47);
  build.addBadConfig("points=bad", 48);

  EXPECT_FALSE(build.valid());
  EXPECT_EQ(build.getBehaviorKind(), "BHV_Waypoint");
  EXPECT_EQ(build.getKindLine(), 42u);
  EXPECT_EQ(build.getKindResult(), "static");
  EXPECT_EQ(build.numBadConfigs(), 2u);
  EXPECT_EQ(build.getBadConfigLine(0), "speed=fast");
  EXPECT_EQ(build.getBadConfigLineNum(1), 48u);
  EXPECT_EQ(build.getBadConfigLine(99), "");
  EXPECT_EQ(build.getBadConfigLineNum(99), 0u);

  HelmStartBehavior* behavior = new HelmStartBehavior();
  ASSERT_TRUE(behavior->setName("startup_probe"));
  behavior->postStartupMessage();
  build.setIvPBehavior(behavior);
  ASSERT_TRUE(build.valid());
  EXPECT_EQ(build.getBehaviorName(), "startup_probe");

  std::vector<VarDataPair> messages = build.getHelmStartMessages();
  ASSERT_EQ(messages.size(), 1u);
  EXPECT_EQ(messages[0].get_var(), "HELM_START_TEST");
  EXPECT_EQ(messages[0].get_sdata(), "ready");
  // getHelmStartMessages() drains the pending-start queue.
  EXPECT_TRUE(build.getHelmStartMessages().empty());

  build.deleteBehavior();
  EXPECT_FALSE(build.valid());
}

// Covers behavior set behavior: builds static waypoint specs and records startup life events.
TEST(BehaviorSetTest, BuildsStaticWaypointSpecsAndRecordsStartupLifeEvents)
{
  BehaviorSet set;
  set.setDomain(makeCourseSpeedDomain());
  set.setOwnship("abe");
  set.addBehaviorSpec(waypointSpec("survey"));

  testing::internal::CaptureStdout();
  ASSERT_TRUE(set.buildBehaviorsFromSpecs());
  testing::internal::GetCapturedStdout();

  ASSERT_EQ(set.size(), 1u);
  ASSERT_NE(set.getBehavior(0), nullptr);
  EXPECT_EQ(set.getDescriptor(0), "survey");
  EXPECT_EQ(set.getBehavior(0)->getBehaviorType(), "BHV_Waypoint");
  EXPECT_EQ(set.getTCount(), 1u);

  std::vector<LifeEvent> events = set.getLifeEvents();
  ASSERT_EQ(events.size(), 1u);
  EXPECT_EQ(events[0].getBehaviorName(), "survey");
  EXPECT_EQ(events[0].getBehaviorType(), "BHV_Waypoint");
  EXPECT_EQ(events[0].getEventType(), "spawn");
  EXPECT_EQ(events[0].getSpawnString(), "helm_startup");
}

// Covers behavior set behavior: rejects duplicate behavior names before partially adding specs.
TEST(BehaviorSetTest, RejectsDuplicateBehaviorNamesBeforePartiallyAddingSpecs)
{
  BehaviorSet set;
  set.setDomain(makeCourseSpeedDomain());
  set.addBehaviorSpec(waypointSpec("dup", 20));
  set.addBehaviorSpec(waypointSpec("dup", 40));

  testing::internal::CaptureStdout();
  EXPECT_FALSE(set.buildBehaviorsFromSpecs());
  testing::internal::GetCapturedStdout();

  EXPECT_EQ(set.size(), 0u);
  EXPECT_TRUE(containsText(set.getWarnings(), "Duplicate behavior name found: dup"));
}

// Covers populator behavior set behavior: parses mission style behavior file modes and initial vars.
TEST(PopulatorBehaviorSetTest, ParsesMissionStyleBehaviorFileModesAndInitialVars)
{
  // This fixture mirrors a real .bhv file: initialize posts immediately,
  // initialize_ defers the post, and the mode block sets the behavior condition.
  TempFile bhv_file("helm_behavior_file",
                    "initialize DEPLOY=true, RETURN=false\n"
                    "initialize_ MISSION_MODE=SURVEY\n"
                    "\n"
                    "set MODE = SURVEY\n"
                    "{\n"
                    "  NAV_X > 10\n"
                    "}\n"
                    "TRANSIT\n"
                    "\n"
                    "Behavior = BHV_Waypoint\n"
                    "{\n"
                    "  name = survey\n"
                    "  pwt = 100\n"
                    "  points = pts={0,0:100,0}\n"
                    "  speed = 2.0\n"
                    "  radius = 5\n"
                    "  condition = MODE=SURVEY\n"
                    "}\n");

  InfoBuffer info;
  info.setValue("NAV_X", 12);
  LedgerSnap ledger;
  Populator_BehaviorSet populator(makeCourseSpeedDomain(), &info, &ledger);
  populator.setOwnship("abe");

  testing::internal::CaptureStdout();
  std::unique_ptr<BehaviorSet> set(populator.populate(bhv_file.path()));
  testing::internal::GetCapturedStdout();

  ASSERT_NE(set, nullptr);
  ASSERT_EQ(set->size(), 1u);
  EXPECT_EQ(set->getDescriptor(0), "survey");
  EXPECT_TRUE(populator.getConfigWarnings().empty());

  std::vector<VarDataPair> initial = set->getInitialVariables();
  ASSERT_EQ(initial.size(), 3u);
  EXPECT_EQ(initial[0].get_var(), "DEPLOY");
  EXPECT_EQ(initial[0].get_sdata(), "true");
  EXPECT_EQ(initial[0].get_key(), "post");
  EXPECT_EQ(initial[2].get_var(), "MISSION_MODE");
  EXPECT_EQ(initial[2].get_key(), "defer");

  set->consultModeSet();
  EXPECT_EQ(set->getModeSummary(), "MODE@SURVEY");
  bool ok = false;
  EXPECT_EQ(info.sQuery("MODE", ok), "SURVEY");
  EXPECT_TRUE(ok);
}

// Covers populator behavior set behavior: reports malformed behavior files without returning set.
TEST(PopulatorBehaviorSetTest, ReportsMalformedBehaviorFilesWithoutReturningSet)
{
  TempFile bhv_file("bad_helm_behavior_file",
                    "Behavior = BHV_NotARealBehavior\n"
                    "{\n"
                    "  name = bad\n"
                    "  speed = 2\n"
                    "}\n");

  InfoBuffer info;
  LedgerSnap ledger;
  Populator_BehaviorSet populator(makeCourseSpeedDomain(), &info, &ledger);

  testing::internal::CaptureStdout();
  std::unique_ptr<BehaviorSet> set(populator.populate(bhv_file.path()));
  testing::internal::GetCapturedStdout();

  EXPECT_EQ(set, nullptr);
  EXPECT_FALSE(populator.getConfigWarnings().empty());
}

// Covers platform model generator behavior: generates holonomic and dubins models for helm contact reasoning.
TEST(PlatformModelGeneratorTest, GeneratesHolonomicAndDubinsModelsForHelmContactReasoning)
{
  PMGen_Holonomic holonomic;
  PlatModel holo = holonomic.generate(10, -5, 450, -2);
  EXPECT_TRUE(holo.valid());
  EXPECT_TRUE(holo.isHolonomic());
  EXPECT_DOUBLE_EQ(holo.getOSX(), 10);
  EXPECT_DOUBLE_EQ(holo.getOSY(), -5);
  EXPECT_DOUBLE_EQ(holo.getOSH(), 90);
  EXPECT_DOUBLE_EQ(holo.getOSV(), 0);
  EXPECT_TRUE(holo.getPoints("star_spoke").empty());

  PMGen_Dubins dubins(30, 30);
  EXPECT_TRUE(dubins.setParam("rad", "20"));
  EXPECT_TRUE(dubins.setParam("degs", "45"));
  EXPECT_FALSE(dubins.setParam("radius", "-1"));
  EXPECT_DOUBLE_EQ(dubins.getParamDbl("radius"), 20);
  EXPECT_DOUBLE_EQ(dubins.getParamDbl("spoke_degs"), 45);

  PlatModel model = dubins.generate(0, 0, 0, 2);
  EXPECT_TRUE(model.valid());
  EXPECT_EQ(model.getModelType(), "dubins");
  EXPECT_FALSE(model.isHolonomic());
  EXPECT_EQ(model.getPoints("star_spoke").size(), 4u);
  EXPECT_EQ(model.getPoints("port_spoke").size(), 4u);
  XYSeglr star_turn = model.getTurnSeglr(90);
  EXPECT_GT(star_turn.size(), 1u);
  EXPECT_NEAR(star_turn.getRayAngle(), 90.0, 1e-9);
}

// Covers platform model generator behavior: switches algorithms and averages recent heading changes.
TEST(PlatformModelGeneratorTest, SwitchesAlgorithmsAndAveragesRecentHeadingChanges)
{
  PlatModelGenerator generator;
  PlatModel first = generator.generate(0, 0, 0, 1);
  EXPECT_TRUE(first.isHolonomic());
  EXPECT_EQ(first.getID(), 0u);
  EXPECT_FALSE(generator.setParams("alg=unknown"));
  ASSERT_TRUE(generator.setParams("alg=dubins#radius=25#spoke_degs=30"));
  EXPECT_DOUBLE_EQ(generator.getParamDbl("radius"), 25);

  PlatModel dubins = generator.generate(0, 0, 90, 1);
  EXPECT_EQ(dubins.getModelType(), "dubins");
  EXPECT_EQ(dubins.getID(), 1u);

  generator.setCurrTime(10);
  generator.generate(0, 0, 10, 1);
  generator.setCurrTime(11);
  generator.generate(0, 0, 20, 1);
  generator.setCurrTime(12);
  generator.generate(0, 0, 40, 1);
  EXPECT_GT(generator.getTurnRate(), 0);

  EXPECT_FALSE(generator.setParams("alg=dubins#radius=not_a_number"));
  PlatModel still_dubins = generator.generate(0, 0, 45, 1);
  EXPECT_EQ(still_dubins.getModelType(), "dubins");
  ASSERT_TRUE(generator.setParams("alg=holo"));
  EXPECT_TRUE(generator.generate(0, 0, 45, 1).isHolonomic());
}
