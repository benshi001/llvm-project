//===--- SHCUtility.h - Common SHC Tool Chain Utilities ---------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_SHCUTILITY_H
#define LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_SHCUTILITY_H

#include "clang/Driver/Tool.h"

namespace clang {
namespace driver {
namespace tools {
namespace SHC {

const char *getTempFile(Compilation &C, StringRef Prefix, StringRef Extension);

// Construct command for creating an SHC fatbin.
void constructSHCFatbinCommand(Compilation &C, const JobAction &JA,
                               StringRef OutputFileName,
                               const InputInfoList &Inputs,
                               const llvm::opt::ArgList &TCArgs, const Tool &T);

} // namespace SHC
} // namespace tools
} // namespace driver
} // namespace clang

#endif // LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_SHCUTILITY_H
