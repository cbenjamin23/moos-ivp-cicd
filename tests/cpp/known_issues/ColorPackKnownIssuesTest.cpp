#include <gtest/gtest.h>

#include <cstring>
#include <new>

#include "ColorPack.h"

// Invalid construction must initialize status flags regardless of prior storage.
// Seeding the storage makes the missing initialization visible on both compilers.
TEST(ColorPackKnownIssuesTest, InvalidColorInitializesUnsetState)
{
  alignas(ColorPack) unsigned char storage[sizeof(ColorPack)];
  std::memset(storage, 1, sizeof(storage));
  ColorPack* color = new (storage) ColorPack("notacolor");
  EXPECT_FALSE(color->set());
  color->~ColorPack();
}
