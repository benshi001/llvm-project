//===--- SHC.cpp - SHC Tool and ToolChain Implementations -------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "SHC.h"
#include "SHCUtility.h"
#include "clang/Driver/CommonArgs.h"
#include "clang/Driver/Compilation.h"
#include "clang/Driver/Driver.h"
#include "clang/Driver/InputInfo.h"
#include "clang/Driver/Types.h"
#include "clang/Options/Options.h"

using namespace clang::driver;
using namespace clang::driver::toolchains;
using namespace clang::driver::tools;
using namespace clang;
using namespace llvm::opt;

void SHC::Linker::ConstructJob(Compilation &C, const JobAction &JA,
                               const InputInfo &Output,
                               const InputInfoList &Inputs,
                               const ArgList &Args,
                               const char *LinkingOutput) const {
  if (JA.getType() == types::TY_SHC_FATBIN)
    return SHC::constructSHCFatbinCommand(C, JA, Output.getFilename(), Inputs,
                                          Args, *this);

  return constructLldCommand(C, JA, Inputs, Output, Args);
}

void SHC::Linker::constructLldCommand(Compilation &C, const JobAction &JA,
                                      const InputInfoList &Inputs,
                                      const InputInfo &Output,
                                      const ArgList &Args) const {
  // The device objects are linked into a single relocatable ELF which is then
  // embedded into the fat binary, so this is always a `-r` link.
  ArgStringList LldArgs{"-r", "-o", Output.getFilename()};

  for (const InputInfo &II : Inputs)
    if (II.isFilename())
      LldArgs.push_back(II.getFilename());

  const char *Lld =
      Args.MakeArgString(getToolChain().GetProgramPath("ld.lld"));
  C.addCommand(std::make_unique<Command>(JA, *this,
                                         ResponseFileSupport::AtFileCurCP(), Lld,
                                         LldArgs, Inputs, Output));
}

/// SHC Toolchain
SHCToolChain::SHCToolChain(const Driver &D, const llvm::Triple &Triple,
                           const llvm::opt::ArgList &Args,
                           const ToolChain *HostTC_,
                           Action::OffloadKind Kind_)
    : Generic_ELF(D, Triple, Args), HostTC(HostTC_), Kind(Kind_) {
  if (HostTC)
    getProgramPaths().push_back(getDriver().Dir);
}

Tool *SHCToolChain::buildLinker() const {
  return new tools::SHC::Linker(*this);
}

void SHCToolChain::addClangTargetOptions(
    const llvm::opt::ArgList &DriverArgs, llvm::opt::ArgStringList &CC1Args,
    BoundArch BA, Action::OffloadKind DeviceOffloadingKind) const {
  if (DeviceOffloadingKind == Action::OFK_SHC)
    CC1Args.append({"-fcuda-is-device", "-fno-threadsafe-statics"});

  // SHC device code is always relocatable: the device objects are linked into
  // a single relocatable ELF before being embedded into the fat binary.
  CC1Args.push_back("-fgpu-rdc");

  DriverArgs.AddLastArg(CC1Args, options::OPT_gpu_max_threads_per_block_EQ);
}
