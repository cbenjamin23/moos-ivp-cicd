#include <gtest/gtest.h>

#include "AOF_CPA.h"
#include "AOF_R13.h"
#include "AOF_R14.h"
#include "AOF_R16.h"
#include "AOF_R17.h"
#include "ColregsTestUtils.h"
#include "CPXEngineOG.h"

namespace {

template <typename AOF>
void configureContactAOF(AOF& aof, CPXEngineOG& engine,
                         double cnx = 80,
                         double cny = 0,
                         double cnh = 270,
                         double cnv = 0)
{
  engine.reset(cny, cnx, cnh, cnv, 0, 0);
  ASSERT_TRUE(aof.setParam("collision_distance", 10.0));
  ASSERT_TRUE(aof.setParam("all_clear_distance", 60.0));
  ASSERT_TRUE(aof.setParam("tol", 120.0));
}

void setOwnshipMotion(CPXEngineOG& engine, double heading, double speed = 0)
{
  engine.reset(engine.cny(), engine.cnx(), engine.cnh(), engine.cnv(),
               engine.osy(), engine.osx(), heading, speed);
}

}  // namespace

// Covers colregs AOF behavior: CPA utility increases with safer initial separation.
TEST(ColregsAOFTest, CPAUtilityIncreasesWithSaferInitialSeparation)
{
  CPXEngineOG near_aof_engine;
  AOF_CPA near_aof(makeColregsDomain(), &near_aof_engine);
  configureContactAOF(near_aof, near_aof_engine, 12, 0, 270, 0);
  ASSERT_TRUE(near_aof.initialize());

  CPXEngineOG far_aof_engine;
  AOF_CPA far_aof(makeColregsDomain(), &far_aof_engine);
  configureContactAOF(far_aof, far_aof_engine, 90, 0, 270, 0);
  ASSERT_TRUE(far_aof.initialize());

  IvPBox stopped = makeCourseSpeedBox(90, 0);
  EXPECT_LT(near_aof.evalBox(&stopped), far_aof.evalBox(&stopped));
  EXPECT_GE(far_aof.evalBox(&stopped), 100);
}

// Covers colregs AOF behavior: rule ao fs require rule specific parameters.
TEST(ColregsAOFTest, RuleAOFsRequireRuleSpecificParameters)
{
  CPXEngineOG overtaking_engine;
  AOF_R13 overtaking(makeColregsDomain(), &overtaking_engine);
  configureContactAOF(overtaking, overtaking_engine);
  EXPECT_FALSE(overtaking.initialize());
  EXPECT_TRUE(overtaking.setParam("passing_side", "port"));
  EXPECT_FALSE(overtaking.setParam("passing_side", "middle"));
  EXPECT_TRUE(overtaking.initialize());

  CPXEngineOG giveway_engine;
  AOF_R16 giveway(makeColregsDomain(), &giveway_engine);
  configureContactAOF(giveway, giveway_engine);
  setOwnshipMotion(giveway_engine, 0.0);
  EXPECT_FALSE(giveway.initialize());
  EXPECT_TRUE(giveway.setParam("passing_side", "stern"));
  EXPECT_TRUE(giveway.setParam("pts_port_turns_ok", "false"));
  EXPECT_TRUE(giveway.initialize());

  CPXEngineOG standon_engine;
  AOF_R17 standon(makeColregsDomain(), &standon_engine);
  configureContactAOF(standon, standon_engine);
  setOwnshipMotion(standon_engine, 0.0);
  standon.setParam("original_course", 90.0);
  EXPECT_FALSE(standon.initialize());
  standon.setParam("original_speed", 2.0);
  EXPECT_TRUE(standon.setParam("passing_side", "neither"));
  EXPECT_TRUE(standon.initialize());
}

// Covers colregs AOF behavior: rule17 hold mode rewards original course and speed.
TEST(ColregsAOFTest, Rule17HoldModeRewardsOriginalCourseAndSpeed)
{
  CPXEngineOG standon_engine;
  AOF_R17 standon(makeColregsDomain(), &standon_engine);
  configureContactAOF(standon, standon_engine);
  setOwnshipMotion(standon_engine, 90.0);
  standon.setParam("original_course", 90.0);
  standon.setParam("original_speed", 2.0);
  ASSERT_TRUE(standon.setParam("passing_side", "neither"));
  ASSERT_TRUE(standon.initialize());

  IvPBox hold = makeCourseSpeedBox(90, 2);
  IvPBox large_change = makeCourseSpeedBox(140, 5);

  EXPECT_DOUBLE_EQ(standon.evalBox(&hold), 100);
  EXPECT_DOUBLE_EQ(standon.evalBox(&large_change), 0);
}

// Covers colregs AOF behavior: rule14 and rule16 build evaluable utilities.
TEST(ColregsAOFTest, Rule14AndRule16BuildEvaluableUtilities)
{
  CPXEngineOG headon_engine;
  AOF_R14 headon(makeColregsDomain(), &headon_engine);
  configureContactAOF(headon, headon_engine, 0, 80, 180, 2);
  ASSERT_TRUE(headon.initialize());

  CPXEngineOG giveway_engine;
  AOF_R16 giveway(makeColregsDomain(), &giveway_engine);
  configureContactAOF(giveway, giveway_engine, 80, 0, 270, 2);
  setOwnshipMotion(giveway_engine, 0.0);
  ASSERT_TRUE(giveway.setParam("passing_side", "stern"));
  ASSERT_TRUE(giveway.initialize());

  IvPBox starboard_turn = makeCourseSpeedBox(45, 2);
  EXPECT_GE(headon.evalBox(&starboard_turn), 0);
  EXPECT_GE(giveway.evalBox(&starboard_turn), 0);
}

// Covers colregs AOF behavior: rule13 overtaking passing side is accepted and stopped course is neutral.
TEST(ColregsAOFTest, Rule13OvertakingPassingSideIsAcceptedAndStoppedCourseIsNeutral)
{
  CPXEngineOG pass_port_engine;
  AOF_R13 pass_port(makeColregsDomain(), &pass_port_engine);
  configureContactAOF(pass_port, pass_port_engine, 0, 80, 0, 1);
  ASSERT_TRUE(pass_port.setParam("passing_side", "port"));
  ASSERT_TRUE(pass_port.initialize());

  CPXEngineOG pass_starboard_engine;
  AOF_R13 pass_starboard(makeColregsDomain(), &pass_starboard_engine);
  configureContactAOF(pass_starboard, pass_starboard_engine, 0, 80, 0, 1);
  ASSERT_TRUE(pass_starboard.setParam("passing_side", "starboard"));
  ASSERT_TRUE(pass_starboard.initialize());

  IvPBox starboard_of_contact = makeCourseSpeedBox(30, 3);
  IvPBox port_of_contact = makeCourseSpeedBox(330, 3);
  IvPBox stopped = makeCourseSpeedBox(0, 0);

  EXPECT_GE(pass_port.evalBox(&port_of_contact), 0);
  EXPECT_GE(pass_port.evalBox(&starboard_of_contact), 0);
  EXPECT_GE(pass_starboard.evalBox(&starboard_of_contact), 0);
  EXPECT_GE(pass_starboard.evalBox(&port_of_contact), 0);
  EXPECT_GE(pass_port.evalBox(&stopped), pass_port.evalBox(&starboard_of_contact));
  EXPECT_GE(pass_starboard.evalBox(&stopped),
            pass_starboard.evalBox(&port_of_contact));
}

// Covers colregs AOF behavior: rule16 stern passing conservative mode disallows port turns.
TEST(ColregsAOFTest, Rule16SternPassingConservativeModeDisallowsPortTurns)
{
  CPXEngineOG default_policy_engine;
  AOF_R16 default_policy(makeColregsDomain(), &default_policy_engine);
  configureContactAOF(default_policy, default_policy_engine, 80, 0, 270, 2);
  setOwnshipMotion(default_policy_engine, 0.0);
  ASSERT_TRUE(default_policy.setParam("passing_side", "stern"));
  ASSERT_TRUE(default_policy.initialize());

  CPXEngineOG conservative_policy_engine;
  AOF_R16 conservative_policy(makeColregsDomain(), &conservative_policy_engine);
  configureContactAOF(conservative_policy, conservative_policy_engine, 80, 0, 270, 2);
  setOwnshipMotion(conservative_policy_engine, 0.0);
  ASSERT_TRUE(conservative_policy.setParam("passing_side", "stern"));
  ASSERT_TRUE(conservative_policy.setParam("pts_port_turns_ok", "false"));
  ASSERT_TRUE(conservative_policy.initialize());

  IvPBox starboard_turn = makeCourseSpeedBox(45, 2);
  IvPBox port_turn = makeCourseSpeedBox(315, 2);

  EXPECT_GE(default_policy.evalBox(&starboard_turn), 0);
  EXPECT_DOUBLE_EQ(conservative_policy.evalBox(&port_turn), 0);
  EXPECT_GE(conservative_policy.evalBox(&starboard_turn),
            conservative_policy.evalBox(&port_turn));
}

// Covers colregs AOF behavior: rule16 bow passing can require minimum bow cross distance.
TEST(ColregsAOFTest, Rule16BowPassingCanRequireMinimumBowCrossDistance)
{
  CPXEngineOG bow_policy_engine;
  AOF_R16 bow_policy(makeColregsDomain(), &bow_policy_engine);
  configureContactAOF(bow_policy, bow_policy_engine, -10, 10, 90, 1);
  setOwnshipMotion(bow_policy_engine, 0.0);
  ASSERT_TRUE(bow_policy.setParam("passing_side", "bow"));
  ASSERT_TRUE(bow_policy.setParam("ok_cn_bow_cross_dist", "20"));
  ASSERT_FALSE(bow_policy.setParam("ok_cn_bow_cross_dist", "-1"));
  ASSERT_TRUE(bow_policy.initialize());

  IvPBox close_cross = makeCourseSpeedBox(45, 5);
  IvPBox no_right_turn = makeCourseSpeedBox(315, 2);

  // Prove this is an actual close bow crossing, not a collision or a
  // mislabeled distant crossing. The former fixture started 80m astern.
  const double cross_distance = bow_policy_engine.crossesBowDist(45, 5);
  ASSERT_GT(cross_distance, 0);
  ASSERT_LE(cross_distance, 20);
  ASSERT_GT(bow_policy_engine.evalCPA(45, 5, 120), 10);
  EXPECT_DOUBLE_EQ(bow_policy.evalBox(&close_cross), 0);
  EXPECT_GE(bow_policy.evalBox(&no_right_turn), 0);
}

// Covers colregs AOF behavior: rule17 in extremis rejects port turn for contact on port side.
TEST(ColregsAOFTest, Rule17InExtremisRejectsPortTurnForContactOnPortSide)
{
  CPXEngineOG standon_engine;
  AOF_R17 standon(makeColregsDomain(), &standon_engine);
  configureContactAOF(standon, standon_engine, -40, 80, 180, 2);
  setOwnshipMotion(standon_engine, 0.0, 2.0);
  standon.setParam("original_course", 0.0);
  standon.setParam("original_speed", 2.0);
  ASSERT_TRUE(standon.setParam("passing_side", "inextremis"));
  ASSERT_TRUE(standon.initialize());

  IvPBox port_turn = makeCourseSpeedBox(330, 2);
  IvPBox starboard_turn = makeCourseSpeedBox(30, 2);

  EXPECT_DOUBLE_EQ(standon.evalBox(&port_turn), 0);
  EXPECT_GT(standon.evalBox(&starboard_turn),
            standon.evalBox(&port_turn));
}
