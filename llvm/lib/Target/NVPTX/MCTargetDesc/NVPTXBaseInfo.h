//===-- NVPTXBaseInfo.h - Top-level definitions for NVPTX -------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains small standalone helper functions and enum definitions for
// the NVPTX target useful for the compiler back-end and the MC libraries.
// As such, it deliberately does not include references to LLVM core
// code gen types, passes, etc..
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_NVPTX_MCTARGETDESC_NVPTXBASEINFO_H
#define LLVM_LIB_TARGET_NVPTX_MCTARGETDESC_NVPTXBASEINFO_H

#include "llvm/Support/NVPTXAddrSpace.h"
namespace llvm {

using namespace NVPTXAS;

namespace NVPTXII {
enum {
  // These must be kept in sync with TSFlags in NVPTXInstrFormats.td
  // clang-format off
  IsTexFlag            =  0x40,
  IsSuldMask           = 0x180,
  IsSuldShift          =   0x7,
  IsSustFlag           = 0x200,
  IsSurfTexQueryFlag   = 0x400,
  IsTexModeUnifiedFlag = 0x800,
  // clang-format on
};
} // namespace NVPTXII

} // namespace llvm
#endif
