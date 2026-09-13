//===--- SHC.h - SHC ToolChain Implementations ------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_SHC_H
#define LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_SHC_H

#include "clang/Driver/Action.h"
#include "clang/Driver/Tool.h"
#include "clang/Driver/ToolChain.h"
#include "Gnu.h"

namespace clang {
namespace driver {

namespace tools {
namespace SHC {

// Links the device objects into a single relocatable ELF, or bundles them
// into an SHC fat binary.
class LLVM_LIBRARY_VISIBILITY Linker final : public Tool {
public:
  Linker(const ToolChain &TC) : Tool("SHC::Linker", "shc-link", TC) {}

  bool isLinkJob() const override { return true; }
  bool hasIntegratedCPP() const override { return false; }

  void ConstructJob(Compilation &C, const JobAction &JA,
                    const InputInfo &Output, const InputInfoList &Inputs,
                    const llvm::opt::ArgList &TCArgs,
                    const char *LinkingOutput) const override;

private:
  void constructLldCommand(Compilation &C, const JobAction &JA,
                           const InputInfoList &Inputs, const InputInfo &Output,
                           const llvm::opt::ArgList &Args) const;
};

} // end namespace SHC
} // end namespace tools

namespace toolchains {

class LLVM_LIBRARY_VISIBILITY SHCToolChain final : public Generic_ELF {
public:
  SHCToolChain(const Driver &D, const llvm::Triple &Triple,
               const llvm::opt::ArgList &Args, const ToolChain *HostTC = nullptr,
               Action::OffloadKind Kind = Action::OFK_None);

  unsigned GetDefaultDwarfVersion() const override { return 5; }

  bool isCrossCompiling() const override { return true; }
  bool isPICDefault() const override { return false; }
  bool isPIEDefault(const llvm::opt::ArgList &Args) const override {
    return false;
  }
  bool isPICDefaultForced() const override { return true; }
  bool SupportsProfiling() const override { return false; }

  /// Needed for using LTO.
  bool HasNativeLLVMSupport() const override { return true; }

  const char *getDefaultLinker() const override { return "ld.lld"; }

  void addClangTargetOptions(
      const llvm::opt::ArgList &DriverArgs, llvm::opt::ArgStringList &CC1Args,
      BoundArch BA, Action::OffloadKind DeviceOffloadingKind) const override;

  const llvm::Triple *getAuxTriple() const override {
    return HostTC ? &HostTC->getTriple() : nullptr;
  }

protected:
  Tool *buildLinker() const override;

private:
  /// Optional host toolchain for offloading modes.
  const ToolChain *HostTC = nullptr;
  Action::OffloadKind Kind = Action::OFK_None;
};

} // end namespace toolchains
} // end namespace driver
} // end namespace clang

#endif // LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_SHC_H
