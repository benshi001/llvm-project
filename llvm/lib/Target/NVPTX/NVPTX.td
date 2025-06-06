//===- NVPTX.td - Describe the NVPTX Target Machine -----------*- tblgen -*-==//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
// This is the top level entry point for the NVPTX target.
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Target-independent interfaces
//===----------------------------------------------------------------------===//

include "llvm/Target/Target.td"

include "NVPTXRegisterInfo.td"
include "NVPTXInstrInfo.td"

//===----------------------------------------------------------------------===//
// Subtarget Features.
// - We use the SM version number instead of explicit feature table.
// - Need at least one feature to avoid generating zero sized array by
//   TableGen in NVPTXGenSubtarget.inc.
//===----------------------------------------------------------------------===//

class FeatureSM<string sm, int value>:
   SubtargetFeature<"sm_"# sm, "FullSmVersion",
                    "" # value,
                    "Target SM " # sm>;

class FeaturePTX<int version>:
   SubtargetFeature<"ptx"# version, "PTXVersion",
                    "" # version,
                    "Use PTX version " # version>;

foreach sm = [20, 21, 30, 32, 35, 37, 50, 52, 53,
              60, 61, 62, 70, 72, 75, 80, 86, 87,
              89, 90, 100, 101, 103, 120, 121] in
  def SM#sm: FeatureSM<""#sm, !mul(sm, 10)>;

// Arch-specific targets. PTX for these is not compatible with any other
// architectures.
def SM90a : FeatureSM<"90a", 901>;
def SM100a: FeatureSM<"100a", 1001>;
def SM101a: FeatureSM<"101a", 1011>;
def SM103a: FeatureSM<"103a", 1031>;
def SM120a: FeatureSM<"120a", 1201>;
def SM121a: FeatureSM<"121a", 1211>;

foreach version = [32, 40, 41, 42, 43, 50, 60, 61, 62, 63, 64, 65,
                   70, 71, 72, 73, 74, 75, 76, 77, 78,
                   80, 81, 82, 83, 84, 85, 86, 87, 88] in
  def PTX#version: FeaturePTX<version>;

//===----------------------------------------------------------------------===//
// NVPTX supported processors.
//===----------------------------------------------------------------------===//

class Proc<string Name, list<SubtargetFeature> Features>
 : Processor<Name, NoItineraries, Features>;

def : Proc<"sm_20",   [SM20, PTX32]>;
def : Proc<"sm_21",   [SM21, PTX32]>;
def : Proc<"sm_30",   [SM30]>;
def : Proc<"sm_32",   [SM32, PTX40]>;
def : Proc<"sm_35",   [SM35, PTX32]>;
def : Proc<"sm_37",   [SM37, PTX41]>;
def : Proc<"sm_50",   [SM50, PTX40]>;
def : Proc<"sm_52",   [SM52, PTX41]>;
def : Proc<"sm_53",   [SM53, PTX42]>;
def : Proc<"sm_60",   [SM60, PTX50]>;
def : Proc<"sm_61",   [SM61, PTX50]>;
def : Proc<"sm_62",   [SM62, PTX50]>;
def : Proc<"sm_70",   [SM70, PTX60]>;
def : Proc<"sm_72",   [SM72, PTX61]>;
def : Proc<"sm_75",   [SM75, PTX63]>;
def : Proc<"sm_80",   [SM80, PTX70]>;
def : Proc<"sm_86",   [SM86, PTX71]>;
def : Proc<"sm_87",   [SM87, PTX74]>;
def : Proc<"sm_89",   [SM89, PTX78]>;
def : Proc<"sm_90",   [SM90, PTX78]>;
def : Proc<"sm_90a",  [SM90a, PTX80]>;
def : Proc<"sm_100",  [SM100, PTX86]>;
def : Proc<"sm_100a", [SM100a, PTX86]>;
def : Proc<"sm_101",  [SM101, PTX86]>;
def : Proc<"sm_101a", [SM101a, PTX86]>;
def : Proc<"sm_103",  [SM103, PTX88]>;
def : Proc<"sm_103a", [SM103a, PTX88]>;
def : Proc<"sm_120",  [SM120, PTX87]>;
def : Proc<"sm_120a", [SM120a, PTX87]>;
def : Proc<"sm_121",  [SM121, PTX88]>;
def : Proc<"sm_121a", [SM121a, PTX88]>;

def NVPTXInstrInfo : InstrInfo {
}

def NVPTX : Target {
  let InstructionSet = NVPTXInstrInfo;
}
