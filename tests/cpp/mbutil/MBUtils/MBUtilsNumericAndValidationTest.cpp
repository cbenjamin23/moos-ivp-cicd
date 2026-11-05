#include <gtest/gtest.h>

#include <string>
#include <vector>

#include "MBUtils.h"

// Covers mb utils validation behavior: classifies numbers booleans and delimited wrappers.
TEST(MBUtilsValidationTest, ClassifiesNumbersBooleansAndDelimitedWrappers)
{
  EXPECT_TRUE(isNumber("12.5"));
  EXPECT_TRUE(isNumber(" -0.25 "));
  EXPECT_TRUE(isNumber("+42"));
  EXPECT_FALSE(isNumber("1e3"));
  EXPECT_FALSE(isNumber(""));
  EXPECT_FALSE(isNumber("12A"));

  EXPECT_TRUE(isBoolean("true"));
  EXPECT_TRUE(isBoolean("false"));
  EXPECT_TRUE(isBoolean("TRUE"));
  EXPECT_FALSE(isBoolean("yes"));

  EXPECT_TRUE(isAlphaNum("abe_27", "_"));
  EXPECT_FALSE(isAlphaNum("abe-27"));
  EXPECT_TRUE(isQuoted("\"hello\""));
  EXPECT_TRUE(isQuoted(" \"hello\" "));
  EXPECT_TRUE(isBraced("{x=1}"));
  EXPECT_TRUE(isBraced(" {x=1} "));
  EXPECT_TRUE(isChevroned("<mode>"));
  EXPECT_TRUE(isChevroned(" <mode> "));
}

// Covers mb utils validation behavior: validates IP addresses and turns.
TEST(MBUtilsValidationTest, ValidatesIpAddressesAndTurns)
{
  EXPECT_TRUE(isValidIPAddress("192.168.1.10"));
  EXPECT_TRUE(isValidIPAddress("0.0.0.0"));
  EXPECT_FALSE(isValidIPAddress("192.168.1"));
  EXPECT_FALSE(isValidIPAddress("192.168.1.999"));
  EXPECT_FALSE(isValidIPAddress("host.local"));

  EXPECT_TRUE(isValidTurn("port"));
  EXPECT_TRUE(isValidTurn("starboard"));
  EXPECT_TRUE(isValidTurn("star"));
  EXPECT_FALSE(isValidTurn("left"));
}

// Covers mb utils setter behavior: sets boolean and turn values from strings.
TEST(MBUtilsSetterTest, SetsBooleanAndTurnValuesFromStrings)
{
  bool flag = false;
  EXPECT_TRUE(setBooleanOnString(flag, "true"));
  EXPECT_TRUE(flag);
  EXPECT_TRUE(setBooleanOnString(flag, "toggle"));
  EXPECT_FALSE(flag);
  EXPECT_TRUE(setBooleanOnString(flag, "YES"));
  EXPECT_TRUE(flag);
  EXPECT_FALSE(setBooleanOnString(flag, "maybe"));
  EXPECT_TRUE(flag);

  bool port_turn = false;
  EXPECT_TRUE(setPortTurnOnString(port_turn, "port"));
  EXPECT_TRUE(port_turn);
  EXPECT_TRUE(setPortTurnOnString(port_turn, "star"));
  EXPECT_FALSE(port_turn);
  EXPECT_TRUE(setPortTurnOnString(port_turn, "toggle"));
  EXPECT_TRUE(port_turn);

  std::string side = "star";
  EXPECT_TRUE(setPortStarOnString(side, "port"));
  EXPECT_EQ(side, "port");
  EXPECT_TRUE(setPortStarOnString(side, "toggle"));
  EXPECT_EQ(side, "start");
}

// Covers mb utils setter behavior: sets numbers with strict positive and range semantics.
TEST(MBUtilsSetterTest, SetsNumbersWithStrictPositiveAndRangeSemantics)
{
  double dval = 1;
  EXPECT_TRUE(setDoubleOnString(dval, "-2.5"));
  EXPECT_DOUBLE_EQ(dval, -2.5);
  EXPECT_FALSE(setDoubleOnString(dval, "two"));
  EXPECT_DOUBLE_EQ(dval, -2.5);

  EXPECT_FALSE(setPosDoubleOnString(dval, "0"));
  EXPECT_FALSE(setPosDoubleOnString(dval, "-1"));
  EXPECT_TRUE(setPosDoubleOnString(dval, "0.1"));
  EXPECT_DOUBLE_EQ(dval, 0.1);

  EXPECT_TRUE(setNonNegDoubleOnString(dval, "0"));
  EXPECT_DOUBLE_EQ(dval, 0);

  dval = 5;
  EXPECT_FALSE(setDoubleRngOnString(dval, "20", 0, 10));
  EXPECT_DOUBLE_EQ(dval, 10);
  EXPECT_TRUE(setDoubleClipRngOnString(dval, "-5", 0, 10));
  EXPECT_DOUBLE_EQ(dval, 0);
  EXPECT_FALSE(setDoubleStrictRngOnString(dval, "20", 0, 10));
  EXPECT_DOUBLE_EQ(dval, 0);
  EXPECT_TRUE(setDoubleStrictRngOnString(dval, "7", 0, 10));
  EXPECT_DOUBLE_EQ(dval, 7);
}

// Covers mb utils setter behavior: sets integer and variable values.
TEST(MBUtilsSetterTest, SetsIntegerAndVariableValues)
{
  unsigned int uval = 9;
  EXPECT_TRUE(setUIntOnString(uval, "3.9"));
  EXPECT_EQ(uval, 3u);
  EXPECT_FALSE(setUIntOnString(uval, "-1"));
  EXPECT_EQ(uval, 3u);
  EXPECT_FALSE(setPosUIntOnString(uval, "0"));
  EXPECT_TRUE(setPosUIntOnString(uval, "5"));
  EXPECT_EQ(uval, 5u);

  int ival = 0;
  EXPECT_TRUE(setIntOnString(ival, "-12"));
  EXPECT_EQ(ival, -12);

  std::string var = "OLD";
  EXPECT_TRUE(setNonWhiteVarOnString(var, "NAV_X"));
  EXPECT_EQ(var, "NAV_X");
  EXPECT_FALSE(setNonWhiteVarOnString(var, "NAV X"));
  EXPECT_EQ(var, "NAV_X");

  EXPECT_TRUE(setStatusVarOnString(var, "silent"));
  EXPECT_EQ(var, "");
}

// Covers mb utils math and formatting behavior: clips snaps and formats values.
TEST(MBUtilsMathAndFormattingTest, ClipsSnapsAndFormatsValues)
{
  EXPECT_DOUBLE_EQ(vclip(12, 0, 10), 10);
  EXPECT_DOUBLE_EQ(vclip(-1, 0, 10), 0);
  EXPECT_DOUBLE_EQ(vclip(5, 0, 10), 5);
  EXPECT_DOUBLE_EQ(snapToStep(6.18, 0.05), 6.2);
  EXPECT_DOUBLE_EQ(snapDownToStep(9.98, 0.5), 9.5);

  EXPECT_EQ(uintToString(7, 3), "007");
  EXPECT_EQ(intToCommaString(1234567), "1,234,567");
  EXPECT_EQ(dstringCompact("12.34000"), "12.34");
  EXPECT_EQ(doubleToHex(0), "00");
  EXPECT_EQ(doubleToHex(1), "FF");
  EXPECT_EQ(findReplace("a,b,c", ',', ':'), "a:b:c");
}
