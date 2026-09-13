//===--- SHCUtility.cpp - Common SHC Tool Chain Utilities -------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "SHCUtility.h"
#include "clang/Driver/CommonArgs.h"
#include "clang/Driver/Compilation.h"
#include "clang/Driver/Driver.h"
#include "clang/Options/Options.h"

using namespace clang;
using namespace clang::driver;
using namespace clang::driver::tools;
using namespace llvm::opt;

#if defined(_WIN32) || defined(_WIN64)
#define NULL_FILE "nul"
#else
#define NULL_FILE "/dev/null"
#endif

namespace {
const unsigned SHCCodeObjectAlign = 4096;
} // namespace

// Construct a clang-offload-bundler command to bundle the device objects into
// an SHC fat binary. Unlike HIP there is no legacy target-id prefix to
// preserve, so the bundle id is simply "shc-" followed by the device triple.
void SHC::constructSHCFatbinCommand(Compilation &C, const JobAction &JA,
                                    llvm::StringRef OutputFileName,
                                    const InputInfoList &Inputs,
                                    const llvm::opt::ArgList &Args,
                                    const Tool &T) {
  ArgStringList BundlerArgs;
  BundlerArgs.push_back(Args.MakeArgString("-type=o"));
  BundlerArgs.push_back(
      Args.MakeArgString("-bundle-align=" + Twine(SHCCodeObjectAlign)));

  // ToDo: Remove the dummy host binary entry which is required by
  // clang-offload-bundler.
  const llvm::Triple &HostTriple = C.getDefaultToolChain().getTriple();
  std::string BundlerTargetArg =
      "-targets=host-" +
      HostTriple.normalize(llvm::Triple::CanonicalForm::FOUR_IDENT);

  for (const auto &II : Inputs) {
    const auto *A = II.getAction();
    const llvm::Triple &InputTriple = A->getOffloadingToolChain()->getTriple();
    BundlerTargetArg +=
        ",shc-" +
        InputTriple.normalize(llvm::Triple::CanonicalForm::FOUR_IDENT);

    BoundArch BA = A->getOffloadingArch();
    if (BA)
      BundlerTargetArg += "-" + BA.ArchName.str();
  }
  BundlerArgs.push_back(Args.MakeArgString(BundlerTargetArg));

  // Use a NULL file as input for the dummy host binary entry.
  std::string BundlerInputArg = "-input=" NULL_FILE;
  BundlerArgs.push_back(Args.MakeArgString(BundlerInputArg));
  for (const auto &II : Inputs) {
    BundlerInputArg = std::string("-input=") + II.getFilename();
    BundlerArgs.push_back(Args.MakeArgString(BundlerInputArg));
  }

  std::string Output = std::string(OutputFileName);
  BundlerArgs.push_back(
      Args.MakeArgString(std::string("-output=").append(Output)));

  addOffloadCompressArgs(Args, BundlerArgs);

  const char *Bundler = Args.MakeArgString(
      T.getToolChain().GetProgramPath("clang-offload-bundler"));
  C.addCommand(std::make_unique<Command>(
      JA, T, ResponseFileSupport::None(), Bundler, BundlerArgs, Inputs,
      InputInfo(&JA, Args.MakeArgString(Output))));
}

// Convenience function for creating temporary file for both modes of
// isSaveTempsEnabled().
const char *SHC::getTempFile(Compilation &C, StringRef Prefix,
                             StringRef Extension) {
  if (C.getDriver().isSaveTempsEnabled())
    return C.getArgs().MakeArgString(Prefix + "." + Extension);

  auto TmpFile = C.getDriver().GetTemporaryPath(Prefix, Extension);
  return C.addTempFile(C.getArgs().MakeArgString(TmpFile));
}
