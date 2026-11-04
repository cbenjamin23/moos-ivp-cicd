#include <gtest/gtest.h>

#include <string>

#include "VelocityFilter.h"

// The merged filter returns a multiplier in [0,1], not a mix of percentages
// and fractions. Evaluation speed is ownship plus the configured contact speed.
TEST(VelocityFilterTest, ParsesCanonicalConfigAndRegulatesCombinedSpeed)
{
  VelocityFilter filter =
      stringToVelocityFilter("min_spd=1,max_spd=5,max_discount=75");
  ASSERT_TRUE(filter.valid());
  EXPECT_DOUBLE_EQ(filter.getMinSpd(), 1);
  EXPECT_DOUBLE_EQ(filter.getMaxSpd(), 5);
  EXPECT_DOUBLE_EQ(filter.getMaxDiscount(), 75);

  ASSERT_TRUE(filter.setSpdCN(0));
  EXPECT_DOUBLE_EQ(filter.spdRegulate(0.5), 0.25);
  EXPECT_DOUBLE_EQ(filter.spdRegulate(3), 0.625);
  ASSERT_TRUE(filter.setSpdCN(3));
  EXPECT_DOUBLE_EQ(filter.spdRegulate(2), 1);
}

TEST(VelocityFilterTest, RejectsIncompleteMalformedAndOutOfRangeConfigs)
{
  for(const char* spec : {
      "", "max_spd=5,max_discount=50",
      "min_spd=fast,max_spd=5,max_discount=50",
      "min_spd=1,max_spd=5", "min_spd=1,max_spd=5,max_discount=much",
      "min_spd=1,max_spd=5,max_discount=-25",
      "min_spd=1,max_spd=5,max_discount=125"}) {
    EXPECT_FALSE(stringToVelocityFilter(spec).valid()) << spec;
  }
}

TEST(VelocityFilterTest, DefaultsInvalidAndRejectedInputsPreserveConfiguration)
{
  VelocityFilter filter;
  EXPECT_FALSE(filter.valid());
  EXPECT_DOUBLE_EQ(filter.getMinSpd(), -1);
  EXPECT_DOUBLE_EQ(filter.getMaxSpd(), -1);
  EXPECT_DOUBLE_EQ(filter.getMaxDiscount(), -1);
  EXPECT_DOUBLE_EQ(filter.getSpdCN(), 0);
  EXPECT_DOUBLE_EQ(filter.spdRegulate(0), 1);

  ASSERT_TRUE(filter.setMinSpd(0));
  ASSERT_TRUE(filter.setMaxSpd(4));
  ASSERT_TRUE(filter.setMaxDiscount(50));
  ASSERT_TRUE(filter.setSpdCN(1));
  EXPECT_TRUE(filter.valid());
  EXPECT_DOUBLE_EQ(filter.spdRegulate(2), 0.875);

  EXPECT_FALSE(filter.setMinSpd(-1));
  EXPECT_FALSE(filter.setMaxSpd(-1));
  EXPECT_FALSE(filter.setMaxDiscount(-1));
  EXPECT_FALSE(filter.setMaxDiscount(101));
  EXPECT_FALSE(filter.setSpdCN(-1));
  EXPECT_DOUBLE_EQ(filter.getMinSpd(), 0);
  EXPECT_DOUBLE_EQ(filter.getMaxSpd(), 4);
  EXPECT_DOUBLE_EQ(filter.getMaxDiscount(), 50);
  EXPECT_DOUBLE_EQ(filter.getSpdCN(), 1);
}

TEST(VelocityFilterTest, ClampsBoundarySpeedsAndKeepsDiscountInUnitInterval)
{
  VelocityFilter filter =
      stringToVelocityFilter("min_spd=2,max_spd=6,max_discount=60");
  ASSERT_TRUE(filter.valid());

  EXPECT_DOUBLE_EQ(filter.spdRegulate(1.99), 0.4);
  EXPECT_DOUBLE_EQ(filter.spdRegulate(2), 0.4);
  EXPECT_DOUBLE_EQ(filter.spdRegulate(6), 1);
  EXPECT_DOUBLE_EQ(filter.spdRegulate(20), 1);
  EXPECT_NEAR(filter.spdRegulate(3), 0.55, 1e-12);
  for(double speed : {0.0, 1.0, 2.0, 4.0, 6.0, 20.0}) {
    EXPECT_GE(filter.spdRegulate(speed), 0);
    EXPECT_LE(filter.spdRegulate(speed), 1);
  }
}

TEST(VelocityFilterTest, EqualSpeedBoundsAreValidAndApplyNoDiscount)
{
  VelocityFilter filter =
      stringToVelocityFilter("min_spd=3,max_spd=3,max_discount=75");
  ASSERT_TRUE(filter.valid());
  EXPECT_DOUBLE_EQ(filter.spdRegulate(0), 1);
  EXPECT_DOUBLE_EQ(filter.spdRegulate(3), 1);
  EXPECT_DOUBLE_EQ(filter.spdRegulate(9), 1);
}

TEST(VelocityFilterTest, DeprecatedPctAliasMatchesCanonicalDiscount)
{
  VelocityFilter filter =
      stringToVelocityFilter("min_spd=1,ignored=9,max_spd=5,pct=20,pct=60");
  ASSERT_TRUE(filter.valid());
  EXPECT_DOUBLE_EQ(filter.getMaxDiscount(), 60);
  EXPECT_DOUBLE_EQ(filter.spdRegulate(3), 0.7);
  EXPECT_NE(filter.getSpec().find("max_discount=60"), std::string::npos);
  EXPECT_NE(filter.getSpec().find("enabled=true"), std::string::npos);
}

TEST(VelocityFilterTest, DisablingRegulationKeepsConfigurationAndCanBeReversed)
{
  VelocityFilter filter =
      stringToVelocityFilter("min_spd=1,max_spd=5,max_discount=75");
  ASSERT_TRUE(filter.isSpdRegulated());
  filter.setEnabled(false);
  EXPECT_TRUE(filter.valid());
  EXPECT_FALSE(filter.isSpdRegulated());
  EXPECT_DOUBLE_EQ(filter.spdRegulate(0), 1);
  EXPECT_NE(filter.getSpec().find("enabled=false"), std::string::npos);
  filter.setEnabled(true);
  EXPECT_TRUE(filter.isSpdRegulated());
  EXPECT_DOUBLE_EQ(filter.spdRegulate(0), 0.25);
}

TEST(VelocityFilterTest, BoundSettersNormalizePairedRangeAndDiscountEndpoints)
{
  VelocityFilter filter;
  ASSERT_TRUE(filter.setMinSpd(5));
  EXPECT_DOUBLE_EQ(filter.getMaxSpd(), 5);
  ASSERT_TRUE(filter.setMaxSpd(1));
  EXPECT_DOUBLE_EQ(filter.getMinSpd(), 1);
  ASSERT_TRUE(filter.setMaxSpd(5));
  ASSERT_TRUE(filter.setMaxDiscount(0));
  EXPECT_DOUBLE_EQ(filter.spdRegulate(1), 1);
  ASSERT_TRUE(filter.setMaxDiscount(100));
  EXPECT_DOUBLE_EQ(filter.spdRegulate(1), 0);
  EXPECT_DOUBLE_EQ(filter.spdRegulate(5), 1);
}
