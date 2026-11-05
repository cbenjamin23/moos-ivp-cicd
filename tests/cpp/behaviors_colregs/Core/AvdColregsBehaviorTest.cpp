#include <gtest/gtest.h>

#include <memory>
#include <vector>

#include "BHV_AvdColregsV17.h"
#include "BHV_AvdColregsV19.h"
#include "BHV_AvdColregsV22.h"
#include "ColregsTestUtils.h"
#include "IvPFunction.h"

// Covers avd colregs behavior behavior: versions accept expected configuration and reject bad values.
TEST(AvdColregsBehaviorTest, VersionsAcceptExpectedConfigurationAndRejectBadValues)
{
  BHV_AvdColregsV17 v17(makeColregsDomain());
  EXPECT_TRUE(v17.isConstraint());
  EXPECT_TRUE(v17.setParam("pwt_inner_dist", "40"));
  EXPECT_TRUE(v17.setParam("pwt_outer_dist", "80"));
  EXPECT_TRUE(v17.setParam("pwt_grade", "quadratic"));
  EXPECT_FALSE(v17.setParam("pwt_grade", "stepped"));

  BHV_AvdColregsV19 v19(makeColregsDomain());
  EXPECT_TRUE(v19.setParam("giveway_bow_dist", "30"));
  EXPECT_TRUE(v19.setParam("use_refinery", "true"));
  EXPECT_TRUE(v19.setParam("can_disable", "true"));
  EXPECT_FALSE(v19.setParam("pcheck_thresh", "-1"));

  BHV_AvdColregsV22 v22(makeColregsDomain());
  EXPECT_TRUE(v22.setParam("velocity_filter", "min_spd=1,max_spd=5,pct=25"));
  EXPECT_TRUE(v22.setParam("headon_only", "true"));
  EXPECT_TRUE(v22.setParam("eval_tol", "120"));
  EXPECT_FALSE(v22.setParam("eval_tol", "3"));
  // Bounds are normalized by the new filter setters; invalid discounts still
  // fail validation instead of producing a multiplier outside [0,1].
  EXPECT_TRUE(v22.setParam("velocity_filter", "min_spd=5,max_spd=1,max_discount=25"));
  EXPECT_FALSE(v22.setParam("velocity_filter", "min_spd=1,max_spd=5,max_discount=125"));
  EXPECT_FALSE(v22.setParam("velocity_filter", "min_spd=1,max_spd=5,max_discount=-25"));
}

// Covers avd colregs behavior behavior: helm start posts contact manager alert for spawnable template.
TEST(AvdColregsBehaviorTest, HelmStartPostsContactManagerAlertForSpawnableTemplate)
{
  BHV_AvdColregsV22 behavior(makeColregsDomain());
  ASSERT_TRUE(behavior.setParam("updates", "COLREGS_UPDATES"));
  ASSERT_TRUE(behavior.setParam("match_group", "blue"));
  behavior.setDynamicallySpawnable(true);

  behavior.onHelmStart();

  const std::vector<VarDataPair> messages = behavior.getMessages();
  const VarDataPair* alert = findPosted(messages, "BCM_ALERT_REQUEST");
  ASSERT_NE(alert, nullptr);
  EXPECT_TRUE(textContains(alert->get_sdata(), "on_flag=COLREGS_UPDATES=name=$[VNAME] # contact=$[VNAME]"));
  EXPECT_TRUE(textContains(alert->get_sdata(), "match_group=blue"));
}

// Covers avd colregs behavior behavior: no alert request suppresses spawnable template alert.
TEST(AvdColregsBehaviorTest, NoAlertRequestSuppressesSpawnableTemplateAlert)
{
  BHV_AvdColregsV22 behavior(makeColregsDomain());
  ASSERT_TRUE(behavior.setParam("updates", "COLREGS_UPDATES"));
  ASSERT_TRUE(behavior.setParam("match_group", "blue"));
  ASSERT_TRUE(behavior.setParam("no_alert_request", "true"));
  behavior.setDynamicallySpawnable(true);

  behavior.onHelmStart();

  EXPECT_EQ(findPosted(behavior.getMessages(), "BCM_ALERT_REQUEST"), nullptr);
}

// Covers avd colregs behavior behavior: V22 runs against ledger contact and posts relevance.
TEST(AvdColregsBehaviorTest, V22RunsAgainstLedgerContactAndPostsRelevance)
{
  InfoBuffer buffer;
  buffer.setCurrTime(100);
  seedColregsOwnship(buffer, 0, 0, 0, 2);

  LedgerSnap ledger;
  seedColregsContact(ledger, "alpha", 0, 70, 180, 2, 99);
  ledger.setType("alpha", "kayak");
  ledger.setVSource("alpha", "ais");

  BHV_AvdColregsV22 behavior(makeColregsDomain());
  behavior.setInfoBuffer(&buffer);
  behavior.setLedgerSnap(&ledger);
  ASSERT_TRUE(behavior.setParam("contact", "alpha"));
  ASSERT_TRUE(behavior.setParam("pwt_outer_dist", "100"));
  ASSERT_TRUE(behavior.setParam("completed_dist", "100"));
  ASSERT_TRUE(behavior.setParam("min_util_cpa_dist", "10"));
  ASSERT_TRUE(behavior.setParam("max_util_cpa_dist", "70"));
  ASSERT_TRUE(behavior.setParam("post_status_info_on_idle", "true"));
  ASSERT_TRUE(behavior.setParam("post_per_contact_info", "true"));

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  ASSERT_NE(ipf, nullptr);
  EXPECT_EQ(behavior.getMode(), "headon");
  EXPECT_EQ(behavior.getSubMode(), "none");
  EXPECT_DOUBLE_EQ(ipf->getPWT(), 100);

  const std::vector<VarDataPair> messages = behavior.getMessages();
  const VarDataPair* relevance = findPosted(messages, "COL22_RELEVANCE_ALPHA");
  ASSERT_NE(relevance, nullptr);
  EXPECT_GE(relevance->get_ddata(), 0);
  EXPECT_LE(relevance->get_ddata(), 1);
  EXPECT_NE(behavior.getMode(), "complete");

  const VarDataPair* summary = findPosted(messages, "COLREGS_SUMMARY_ALPHA");
  ASSERT_NE(summary, nullptr);
  EXPECT_TRUE(textContains(summary->get_sdata(), "mode=headon:none"));

  EXPECT_EQ(behavior.expandMacros("mode=$[AVD_MODE],smode=$[AVD_SMODE],full=$[FULL_MODE]"),
            "mode=headon,smode=none,full=headon:none");
}

// Covers avd colregs behavior behavior: V22 headon only falls back to CPA for crossing encounter.
TEST(AvdColregsBehaviorTest, V22HeadonOnlyFallsBackToCpaForCrossingEncounter)
{
  InfoBuffer buffer;
  buffer.setCurrTime(200);
  seedColregsOwnship(buffer, 0, 0, 0, 2);

  LedgerSnap ledger;
  seedColregsContact(ledger, "bravo", 70, 0, 270, 2, 199);

  BHV_AvdColregsV22 behavior(makeColregsDomain());
  behavior.setInfoBuffer(&buffer);
  behavior.setLedgerSnap(&ledger);
  ASSERT_TRUE(behavior.setParam("contact", "bravo"));
  ASSERT_TRUE(behavior.setParam("pwt_inner_dist", "40"));
  ASSERT_TRUE(behavior.setParam("pwt_outer_dist", "100"));
  ASSERT_TRUE(behavior.setParam("completed_dist", "120"));
  ASSERT_TRUE(behavior.setParam("post_per_contact_info", "true"));
  ASSERT_TRUE(behavior.setParam("headon_only", "true"));

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  ASSERT_NE(ipf, nullptr);
  EXPECT_EQ(behavior.getMode(), "cpa");

  const VarDataPair* mode =
      findPosted(behavior.getMessages(), "COL22_AVOID_MODE_BRAVO");
  ASSERT_NE(mode, nullptr);
}

// Covers avd colregs behavior behavior: V22 filter exit completes when contact type no longer matches.
TEST(AvdColregsBehaviorTest, V22FilterExitCompletesWhenContactTypeNoLongerMatches)
{
  InfoBuffer buffer;
  buffer.setCurrTime(300);
  seedColregsOwnship(buffer, 0, 0, 0, 2);

  LedgerSnap ledger;
  seedColregsContact(ledger, "charlie", 0, 80, 180, 2, 299);
  ledger.setType("charlie", "kayak");

  BHV_AvdColregsV22 behavior(makeColregsDomain());
  behavior.setInfoBuffer(&buffer);
  behavior.setLedgerSnap(&ledger);
  ASSERT_TRUE(behavior.setParam("contact", "charlie"));
  ASSERT_TRUE(behavior.setParam("match_type", "ship"));
  ASSERT_TRUE(behavior.setParam("exit_on_filter_vtype", "true"));

  std::unique_ptr<IvPFunction> ipf(behavior.onRunState());
  EXPECT_EQ(ipf, nullptr);
  EXPECT_EQ(behavior.getMode(), "none");
}
