//===-- Unittests for exp -------------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "hdr/math_macros.h"
#include "hdr/stdint_proxy.h"
#include "src/__support/FPUtil/FPBits.h"
#include "src/__support/libc_errno.h"
#include "src/math/exp.h"
#include "test/UnitTest/FPMatcher.h"
#include "test/UnitTest/Test.h"

using LlvmLibcExpTest = LIBC_NAMESPACE::testing::FPTest<double>;

TEST_F(LlvmLibcExpTest, SpecialNumbers) {
  EXPECT_FP_EQ_WITH_EXCEPTION(aNaN, LIBC_NAMESPACE::exp(sNaN), FE_INVALID);
  EXPECT_MATH_ERRNO(0);

  EXPECT_FP_EQ(aNaN, LIBC_NAMESPACE::exp(aNaN));
  EXPECT_FP_EQ(inf, LIBC_NAMESPACE::exp(inf));
  EXPECT_FP_EQ_ALL_ROUNDING(zero, LIBC_NAMESPACE::exp(neg_inf));
  EXPECT_FP_EQ_WITH_EXCEPTION(zero, LIBC_NAMESPACE::exp(-0x1.0p20),
                              FE_UNDERFLOW);
  EXPECT_FP_EQ_WITH_EXCEPTION(inf, LIBC_NAMESPACE::exp(0x1.0p20), FE_OVERFLOW);
  EXPECT_FP_EQ_ALL_ROUNDING(1.0, LIBC_NAMESPACE::exp(0.0));
  EXPECT_FP_EQ_ALL_ROUNDING(1.0, LIBC_NAMESPACE::exp(-0.0));
}

#ifdef LIBC_TEST_FTZ_DAZ

using namespace LIBC_NAMESPACE::testing;

TEST_F(LlvmLibcExpTest, FTZMode) {
  ModifyMXCSR mxcsr(FTZ);

  EXPECT_FP_EQ(1.0, LIBC_NAMESPACE::exp(min_denormal));
  EXPECT_FP_EQ(1.0, LIBC_NAMESPACE::exp(max_denormal));
}

TEST_F(LlvmLibcExpTest, DAZMode) {
  ModifyMXCSR mxcsr(DAZ);

  EXPECT_FP_EQ(1.0, LIBC_NAMESPACE::exp(min_denormal));
  EXPECT_FP_EQ(1.0, LIBC_NAMESPACE::exp(max_denormal));
}

TEST_F(LlvmLibcExpTest, FTZDAZMode) {
  ModifyMXCSR mxcsr(FTZ | DAZ);

  EXPECT_FP_EQ(1.0, LIBC_NAMESPACE::exp(min_denormal));
  EXPECT_FP_EQ(1.0, LIBC_NAMESPACE::exp(max_denormal));
}

#endif
