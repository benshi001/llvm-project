// Verify that "shc" is accepted as an offload kind by the bundler and that it
// round-trips through bundle/unbundle.

// RUN: echo 'host' > %t.host.o
// RUN: echo 'device' > %t.shc.o
// RUN: clang-offload-bundler -type=o \
// RUN:   -targets=host-x86_64-unknown-linux-gnu,shc-riscv32-unknown-elf- \
// RUN:   -input=%t.host.o -input=%t.shc.o -output=%t.bundle.o

// RUN: clang-offload-bundler -type=o -list -input=%t.bundle.o | FileCheck %s
// CHECK: shc-riscv32-unknown-unknown-elf-
// CHECK: host-x86_64-unknown-linux-gnu-

// RUN: rm -rf %t.dir && mkdir -p %t.dir
// RUN: clang-offload-bundler -type=o -unbundle -input=%t.bundle.o \
// RUN:   -targets=host-x86_64-unknown-linux-gnu,shc-riscv32-unknown-elf- \
// RUN:   -output=%t.dir/host.o -output=%t.dir/shc.o
// RUN: FileCheck --input-file=%t.dir/shc.o %s -check-prefix=SHC-IMG
// RUN: FileCheck --input-file=%t.dir/host.o %s -check-prefix=HOST-IMG
// SHC-IMG: device
// HOST-IMG: host

// An unknown kind is still rejected.
// RUN: not clang-offload-bundler -type=o \
// RUN:   -targets=host-x86_64-unknown-linux-gnu,shcx-riscv32-unknown-elf- \
// RUN:   -input=%t.host.o -input=%t.shc.o -output=%t.bad.o 2>&1 \
// RUN:   | FileCheck %s -check-prefix=ERR
// ERR: unknown offloading kind 'shcx'
