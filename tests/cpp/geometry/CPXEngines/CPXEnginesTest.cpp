#include <gtest/gtest.h>

#include <cmath>

#include "CPXEnginePM.h"
#include "CPXEngineThin.h"
#include "PlatModel.h"
#include "NumericAssertions.h"

TEST(CPXEngineMergedTest, PlatformModelKeepsStationaryContactAtItsActualPosition)
{
  PlatModel platform(0, 0, 0, 2);
  platform.setModelType("holo");
  CPXEnginePM engine(50, 50, 90, 0, 0, 0, 0, 2);
  engine.setPlatModel(platform);
  EXPECT_NEAR(engine.evalCPA(45, 2, 60), 0, 1e-6);
  EXPECT_NEAR(engine.evalCPA(225, 2, 60), std::sqrt(5000.0), 1e-6);
}

TEST(CPXEngineMergedTest, ThinEngineReturnsFiniteNonNegativeCPAAtAnIntersection)
{
  CPXEngineThin engine(100, 100, 270, 2, 0, 0);
  const double distance = engine.evalCPA(0, 2, 120);
  EXPECT_TRUE(std::isfinite(distance));
  EXPECT_GE(distance, 0);
  EXPECT_NEAR(distance, 0, kLooseGeomTol);
}
