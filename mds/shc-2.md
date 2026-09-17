# SHC 语言支持：落地步骤全记录

分支：`shc`（基于 LLVM 主干）。所有代码改动已提交为 6 个 commit，工作区仅剩未跟踪的 `cmake.sh`。

提交顺序即实际执行顺序：

| # | Commit | 主题 |
|---|---|---|
| 1 | `1e99a6cdf9fb` | SHC: implement a new language type |
| 2 | `c24400e505ca` | SHC: implement macros and header files |
| 3 | `39ddc39df13b` | SHC: implement fatbin related stuff |
| 4 | `001d3052fa5d` | SHC: implement SHC offload kind |
| 5 | `3f6db08929a4` | SHC: initial support in the driver（含方案 C） |
| 6 | `f95662b15298` | shc: supplement some documents |

目标形态：`-x shc` 的源文件分别编译出 host（x86_64）与 device（riscv32-unknown-elf），device 侧产物打成 SHC fatbin，再由 host 编译嵌入 `.shc_fatbin` 段，运行时经 `__shcRegisterFatBinary` / `__shcLaunchKernel` 完成 kernel 启动。

---

## 步骤 1：新增 SHC 语言类型（可选 `-x shc`）

**Commit** `1e99a6cdf9fb`

### 修改文件与内容

| 文件 | 修改 |
|---|---|
| `clang/include/clang/Driver/Types.def` | 增加 4 个类型：`shc-cpp-output`(PP_SHC, 扩展名 `shci`)、`shc`(SHC, `shc`)、device 变体 `shc`(SHC_DEVICE)、`shc-fatbin`(SHC_FATBIN, `shcfb`) |
| `clang/include/clang/Driver/Types.h` | 声明 `bool isSHC(ID Id)` |
| `clang/lib/Driver/Types.cpp` | 实现 `isSHC()`、`lookupTypeForExtension(".shc")`、预处理输出类型映射、 `-x shc` / `-x shc-cpp-output` 解析 |
| `clang/include/clang/Basic/LangStandard.h` | `Language` 枚举加 `SHC` |
| `clang/lib/Basic/LangStandards.cpp` | `getNameForLanguage()` 返回 `"SHC"`；默认标准取 `lang_gnucxx17`（与 CUDA/HIP 对齐） |
| `clang/include/clang/Basic/LangOptions.def` | `LANGOPT(SHC, 1, 0, NotCompatible, "SHC")` |
| `clang/lib/Basic/LangOptions.cpp` | SHC 参与 `LangOptions` 序列化/哈希 |
| `clang/lib/Frontend/CompilerInvocation.cpp` | `-x shc` → `LangOpts.SHC`；与 CUDA/HIP 互斥处理 |
| `clang/lib/Frontend/FrontendActions.cpp`<br>`clang/lib/Frontend/FrontendOptions.cpp` | 输入类型 → 语言选项的映射，让 cc1 认识 shc 输入 |
| `clang/lib/Frontend/InitPreprocessor.cpp` | 定义 `__SHC__`、`__SHCC__`（device 侧 `__SHC_DEVICE_COMPILE__`） |
| `clang/lib/ExtractAPI/Serialization/SymbolGraphSerializer.cpp` | 语言名映射补齐，避免 switch 漏项告警 |
| `clang/test/lit.cfg.py`<br>`clang/test/Driver/lit.local.cfg` | 让 `.shc` 后缀的测试文件被 lit 识别为 clang 输入 |
| `clang/unittests/Basic/LangOptionsTest.cpp`<br>`clang/unittests/Tooling/ToolingTest.cpp` | 语言选项单测补齐 |
| 新增测试 | `clang/test/Driver/shc-phases.shc`、`shc-std.shc`；更新 `unknown-std.cpp` |

Types.def 中的关键定义：

```50:52:clang/include/clang/Driver/Types.def
TYPE("shc-cpp-output",           PP_SHC,       INVALID,         "shci",   phases::Compile, phases::Backend, phases::Assemble, phases::Link)
TYPE("shc",                      SHC,          PP_SHC,          "shc",    phases::Preprocess, phases::Compile, phases::Backend, phases::Assemble, phases::Link)
TYPE("shc",                      SHC,          PP_SHC,          "shc",    phases::Preprocess, phases::Compile, phases::Backend, phases::Assemble, phases::Link)
```

### 为什么

SHC 语义上是一个新的**源语言**（有 `__global__`/`<<<>>>` 语法），而不是既有语言的 dialect。走"新语言类型"可以让 driver 从 `-x shc` 或 `.shc` 后缀自动进入 host/device 双编译，而不需要用户额外传 `--offload-arch=` 之类的开关；同时 `LangOptions.SHC` 给 Sema/CodeGen 提供统一的判断入口，避免到处判断"CUDADevice 且不是 HIP"。

---

## 步骤 2：宏与运行时包装头

**Commit** `c24400e505ca`

### 修改文件与内容

| 文件 | 修改 |
|---|---|
| `clang/lib/Headers/__clang_shc_runtime_wrapper.h`（新增，65 行） | 定义 `__host__`/`__device__`/`__global__`/`__shared__`/`__constant__`/`__managed__` 到相应 attribute；声明 `dim3`、`__shcLaunchKernel(const void*, dim3, dim3, void**, size_t, void*)`、`__shcPushCallConfiguration` |
| `clang/lib/Headers/CMakeLists.txt` | 安装该头文件 |
| `llvm/utils/gn/secondary/clang/lib/Headers/BUILD.gn` | GN 构建同步 |
| `clang/lib/Driver/ToolChains/Clang.cpp` | 按输入类型强制 `-include __clang_shc_runtime_wrapper.h` |
| `clang/lib/Frontend/InitPreprocessor.cpp` | 预定义宏逻辑补齐 |
| 新增测试 | `test/Driver/shc-wrapper-include.shc`、`test/Headers/shc-header.shc`、`test/Preprocessor/shc-macros.shc` |

强制 include 的挂点（按输入类型而非 offload toolchain，因为该头与是否有 device 工具链无关）：

```990:992:clang/lib/Driver/ToolChains/Clang.cpp
  if (!NoBuiltinInc && !Inputs.empty() &&
      types::isSHC(Inputs[0].getType()))
    CmdArgs.append({"-include", "__clang_shc_runtime_wrapper.h"});
```

宏测试结果（`-dM`）：

```sh
CHECK-NOT: #define __CUDA__ 1
CHECK-NOT: #define __HIP__ 1
CHECK: #define __SHCC__ 1
CHECK: #define __SHC__ 1
CHECK-NOT: __SHC_DEVICE_COMPILE__     # host 侧不定义
```

### 为什么

SHC 没有厂商 runtime 头文件（CUDA 有 `cuda_runtime.h`，HIP 有 `hip_runtime.h`），而 CodeGen 生成 kernel stub 时要求 `__shcLaunchKernel` 必须在 TU 中已声明，否则直接报 `Can't find declaration for __shcLaunchKernel`。因此做一个编译器私有的 `-include` 头，把 attribute 宏和 launch API 声明补齐，让"裸 SHC 源码"无需 include 任何东西即可编译。

`__shcLaunchKernel` 的**第二个参数必须是 `dim3`**：CodeGen 直接读取该形参类型作为 grid/block 维度类型。

---

## 步骤 3：fatbin 相关代码生成

**Commit** `39ddc39df13b`

### 修改文件与内容

| 文件 | 修改 |
|---|---|
| `clang/lib/CodeGen/CGCUDANV.cpp` | 把 CUDA/HIP 的 fatbin 注册路径参数化给 SHC（+91/-35） |
| `clang/lib/CodeGen/CodeGenModule.cpp` | SHC 参与 module ctor/dtor 与 fatbin 符号处理 |
| `clang/lib/Sema/SemaCUDA.cpp` | launch 配置函数名选择加 SHC 分支 |
| `clang/lib/Headers/__clang_shc_runtime_wrapper.h` | 补 `dim3` 的 C++ 构造、`__shcPushCallConfiguration` 的默认值 |
| 新增测试 | `clang/test/CodeGenSHC/kernel-launch.shc`（46 行）、`clang/test/CodeGenSHC/lit.local.cfg` |

关键实现点：

- 符号前缀按语言选择，SHC 取 `"shc"`：

```259:265:clang/lib/CodeGen/CGCUDANV.cpp
    Prefix = "llvm";
  else if (CGM.getLangOpts().HIP)
    Prefix = "hip";
  else if (CGM.getLangOpts().SHC)
    Prefix = "shc";
  else
    Prefix = "cuda";
```

- launch API 用扁平 C 名（不走 `<prefix>LaunchKernel` 约定）：

```454:457:clang/lib/CodeGen/CGCUDANV.cpp
  if (CGF.getLangOpts().SHC)
    LaunchKernelName = "__shcLaunchKernel";
```

- fatbin 布局沿用 HIP 方案，仅换段名/符号名：`.shc_fatbin`、`__shc_fatbin`、`__shc_fatbin_wrapper`、`__shc_gpubin_handle`、`__shc_module_ctor/dtor`、`__shc_register_globals`、`__shc_cuid_<hash>`。RDC（SHC 恒 RDC）下 host 对象只留 offloading entries，`.shc_fatbin` 与注册 ctor（`.shc.fatbin_reg`）由 `clang-linker-wrapper` 在链接期生成，不再依赖外部符号 `__shc_fatbin`。
- Sema 侧 launch 序列固定用 new launch：

```1236:1239:clang/lib/Sema/SemaCUDA.cpp
  // SHC always uses the new launch sequence, whose pop side is emitted by
  // CodeGen as __shcPopCallConfiguration.
  if (getLangOpts().SHC)
    return "__shcPushCallConfiguration";
```

### 为什么

`<<<>>>` 语法、`__global__` 语义、fatbin 注册与 module ctor 机制在 CUDA/HIP 里已经完整实现，重写一套代价极高且容易与上游分叉。因此做法是**复用 CGCUDANV 的整条代码路径，只把前缀/段名/符号名参数化**，SHC 得到一份与 HIP 同构但命名独立的 fatbin 协议，后续 runtime 只需实现 6 个 `__shc*` 入口。

---

## 步骤 4：SHC offload kind

**Commit** `001d3052fa5d`

### 修改文件与内容

| 文件 | 修改 |
|---|---|
| `clang/include/clang/Driver/Action.h` | `OFK_SHC = 0x20`，并把 `OFK_DeviceLast` 改为 `OFK_SHC` |
| `clang/lib/Driver/Action.cpp` | offload kind 名/前缀映射（`"shc"`、`(device-shc ...)`） |
| `clang/lib/Driver/Driver.cpp` | SHC 由 SHC 输入激活；默认 device triple 为 `riscv32-unknown-elf`；`OffloadKinds` 数组加入；输入类型过滤；CUID 初始化 |
| `clang/lib/Driver/OffloadBundler.cpp` | bundler 识别 `shc` kind |
| `llvm/include/llvm/Object/OffloadBinary.h`<br>`llvm/lib/Object/OffloadBinary.cpp` | LLVM 侧新增 `OFK_SHC`（含 `getOffloadKindName`） |
| `llvm/lib/ObjectYAML/OffloadYAML.cpp` | YAML 映射补齐 |
| `clang/lib/CodeGen/CGCUDANV.cpp` | 少量命名/前缀修正以匹配新 kind |
| 新增测试 | `clang/test/OffloadTools/clang-offload-bundler/shc-kind.c` |

driver 侧激活与默认 device triple：

```1113:1118:clang/lib/Driver/Driver.cpp
  // SHC is activated by SHC inputs only. A --shc-link flag will be added
  // together with the device tool chain.
  bool IsSHC =
      llvm::any_of(Inputs, [](std::pair<types::ID, const llvm::opt::Arg *> &I) {
        return types::isSHC(I.first);
      });
```

```1089:1091:clang/lib/Driver/Driver.cpp
  else if (Archs.empty() && Kind == Action::OFK_SHC)
    Triples.insert(
        llvm::Triple(llvm::Triple::normalize("riscv32-unknown-elf")));
```

bundler 侧行为由测试锁定（含未知 kind 仍报错）：

```6:12:clang/test/OffloadTools/clang-offload-bundler/shc-kind.c
// RUN: clang-offload-bundler -type=o \
// RUN:   -targets=host-x86_64-unknown-linux-gnu,shc-riscv32-unknown-elf- \
// RUN:   -input=%t.host.o -input=%t.shc.o -output=%t.bundle.o
// CHECK: shc-riscv32-unknown-unknown-elf-
// CHECK: host-x86_64-unknown-linux-gnu-
```

### 为什么

前 3 步只解决了"能编出 fatbin"，但没有 offload kind 就不会产生 device 编译分支（`-ccc-print-phases` 里没有 `(device-shc)`），也拿不到独立的 device toolchain。新增 `OFK_SHC` 才能：
1. 让 driver 建立 host/device 双 action 链；
2. 让 `llvm-offload-binary` / `clang-offload-bundler` / `clang-linker-wrapper` 这条标准 offload 链路认识 SHC 的 bundle 条目（`shc-<triple>-`）；
3. 使 `OFK_DeviceLast = OFK_SHC`，保证 device kind 区间遍历覆盖 SHC。

---

## 步骤 5：driver 支持（含方案演进与方案 C）

**Commit** `3f6db08929a4` —— 最大的一步，也是本轮会话的主体工作。

### 5.1 新增 SHC toolchain（方案 A：driver 侧直接打 fatbin）

| 文件 | 修改 |
|---|---|
| `clang/lib/Driver/ToolChains/SHC.h`（新增，90 行） | `toolchains::SHCToolChain : Generic_ELF`（默认 linker `ld.lld`、`isCrossCompiling`、`PIC/PIE` 关闭、`HasNativeLLVMSupport`）；`tools::SHC::Linker` |
| `clang/lib/Driver/ToolChains/SHC.cpp`（新增，80 行） | `SHC::Linker::ConstructJob`：`TY_SHC_FATBIN` 走 `constructSHCFatbinCommand`，否则做 `-r` 可重定位链接；`addClangTargetOptions` 下传 `-fcuda-is-device`、`-fno-threadsafe-statics`、强制 `-fgpu-rdc` |
| `clang/lib/Driver/ToolChains/SHCUtility.h/.cpp`（新增，32/93 行） | `constructSHCFatbinCommand()`：拼出 `clang-offload-bundler -type=o -bundle-align=4096 -targets=host-<host>,shc-<device> -input=/dev/null -input=<objs> -output=<fatbin>`；`getTempFile()` |
| `clang/lib/Driver/CMakeLists.txt` | 加入 `SHC.cpp`、`SHCUtility.cpp` |
| `clang/lib/Driver/Driver.cpp` | `#include "ToolChains/SHC.h"`；riscv32/riscv64 且 `OFK_SHC` 时构造 `SHCToolChain` |
| `clang/lib/Driver/ToolChains/Clang.cpp` | 多处挂点加 SHC（见下） |

toolchain 构造：

```6194:6199:clang/lib/Driver/Driver.cpp
    case llvm::Triple::riscv32:
    case llvm::Triple::riscv64:
      if (Kind == Action::OFK_SHC)
        TC = std::make_unique<toolchains::SHCToolChain>(*this, Target, Args,
                                                        HostTC.get(), Kind);
      break;
```

device 侧强制可重定位（device 目标最终要合并成一个 ELF 再进 fatbin）：

```75:79:clang/lib/Driver/ToolChains/SHC.cpp
  // SHC device code is always relocatable: the device objects are linked into
  // a single relocatable ELF before being embedded into the fat binary.
  CC1Args.push_back("-fgpu-rdc");
```

Clang.cpp 的 SHC 挂点：

- offload toolchain 遍历加入 `OFK_SHC`（`105-106`、`9831-9832`）
- `IsSHC` / `IsSHCDevice` 判定（`5232-5233`）
- `-fgpu-rdc` 传递（`7436`）
- device 侧不传播 PGO 选项（`7477`）
- fatbin 以 binary 形式嵌入 host（`8340`、`8360`）
- device 侧 GPU inline threshold（`8398`）

**为什么**：device 是 riscv32 裸机目标，既有 toolchain 都不合适（无 libc、无默认 GNU ld 支持），必须有一个自己的 toolchain 来固定 linker、关闭 PIC/PIE、下传 device 语义选项。

### 5.2 方案演进：A → C

- **方案 A**（driver 侧 `SHC::Linker` 调 `clang-offload-bundler`）：非 RDC 能跑通，但 device 对象只是简单打包，**无法跨 TU 合并**，因此不支持 `-fgpu-rdc`（device 侧函数调用跨文件会 undefined）。
- **方案 C**（最终采用）：把 fatbin 生成下沉到 `clang-linker-wrapper`，复用 LLVM 标准的 `OffloadPackagerJobAction` → `LinkerWrapperJobAction` 链路。好处是 device 代码在链接阶段由 linker-wrapper 统一 `linkDevice`（跨 TU 合并）+ 打包，RDC 天然可用。

Driver.cpp 的分流（非 RDC 走 packager + linker-wrapper；RDC 落到 else 分支，推迟到最终链接时合并）：

```4370:4383:clang/lib/Driver/Driver.cpp
  } else if (!UsesLLVMOffloading && C.isOffloadingHostKind(Action::OFK_SHC) &&
             !Args.hasFlag(options::OPT_fgpu_rdc, options::OPT_fno_gpu_rdc,
                           false)) {
    // SHC packages the device images and lets the linker wrapper bundle them
    // into a fat binary, which the host compilation embeds. In RDC mode we
    // fall through instead so the device code is linked at the final link.
    ActionList AL{PackagerAction};
    PackagerAction =
        C.MakeAction<LinkerWrapperJobAction>(AL, types::TY_SHC_FATBIN);
    DDep.add(*PackagerAction,
             *C.getOffloadToolChains(Action::OFK_SHC).first->second,
             /*BA=*/{}, Action::OFK_SHC);
  } else {
```

### 5.3 linker-wrapper 支持（`clang/tools/clang-linker-wrapper/ClangLinkerWrapper.cpp`，+100）

| 改动 | 内容 |
|---|---|
| `linkDevice` arch 白名单 | 加入 `riscv32` / `riscv64`（原来只有 GPU/NVPTX/AMDGPU 等，riscv 会直接报不支持） |
| 新增 `shc::fatbinary()`（518-560） | 照 `amdgcn::fatbinary` 的模式起 `clang-offload-bundler` 子进程，`-type=o -bundle-align=4096`，host 条目用 `/dev/null`，device 条目 id 为 `shc-<triple>`；支持 `-compress` / `-compression-level=` |
| 新增 `bundleSHC()`（1054-1080） | 把每个 `OffloadingImage` 的 identifier（即链接输出文件路径）与 triple 收集起来交给 `shc::fatbinary`，读回 buffer |
| `bundleLinkedOutput` 分派（1101） | `case OFK_SHC: return bundleSHC(Images, Args);` |
| device 链接参数（633） | 非 GPU 分支原本无条件 `-Wl,-Bsymbolic -shared` 并复制 host 库；SHC 是 freestanding 裸机目标，host 库既不必要也不兼容，改为 `if (!Triple.isGPU() && !(ActiveOffloadKindMask & OFK_SHC))` |

**为什么不直接用 `OffloadBundler` API**：linker-wrapper 只链 `clangBasic`，没有 `clangDriver`；照 `amdgcn::fatbinary` 起进程可以零新增依赖。

### 5.4 device 链接的三次踩坑与修复（Clang.cpp）

1. `-fuse-ld` 放错位置：`--device-linker` 的值在 linker-wrapper 里被转成 `-Wl,<arg>` 透传给 ld，而 `-fuse-ld` 是 **clang 自己的选项**，必须走 `compiler_arg_EQ`（直接给 clang）。先写成 `LinkerArgs` 完全不生效，device 链接仍在用 `/usr/bin/ld`（不认 `elf32lriscv`）。
2. `freestanding`：改用 `ld.lld` 后又去找 `crt0.o` / `libc` / `libclang_rt.builtins`，需要 `-nostdlib`。（曾试 `-nobuiltinlib`，不是 clang 选项，去掉。）
3. assert 白名单：`Clang.cpp` 中 `LinkerWrapper` 的 assert 没有 `TY_SHC_FATBIN`，方案 C 会直接断言失败。

最终形态：

```9865:9874:clang/lib/Driver/ToolChains/Clang.cpp
      // The SHC device is a RISC-V target, and the default GNU linker does not
      // understand its emulation mode. Force lld for the device link. This has
      // to be a compiler argument: `-fuse-ld` is handled by clang itself, and
      // linker arguments are forwarded to the linker via `-Xlinker`.
      // The device is freestanding: no C runtime or compiler builtins library
      // is available for the bare metal target, so do not link them in.
      if (Kind == Action::OFK_SHC) {
        CompilerArgs.emplace_back("-fuse-ld=lld");
        CompilerArgs.emplace_back("-nostdlib");
      }
```

```10041:10044:clang/lib/Driver/ToolChains/Clang.cpp
  assert(JA.getType() == types::TY_HIP_FATBIN ||
         JA.getType() == types::TY_SYCL_FATBIN ||
         JA.getType() == types::TY_SHC_FATBIN ||
         JA.getType() == types::TY_Image);
```

### 5.5 测试更新

| 文件 | 修改 |
|---|---|
| `clang/test/Driver/shc-phases.shc` | phase 图改为 `llvm-offload-binary` → `clang-linker-wrapper` → `shc-fatbin`；保留 `.shc` 后缀自动识别、`-x shc` / `-x shc-cpp-output` 透传给 cc1 的检查 |
| `clang/test/CodeGenSHC/kernel-launch.shc` | 因方案 C 下 device 代码要经过真实链接，host 侧改为**目标文件级**检查（`llvm-objdump -h` 查 `.shc_fatbin`/`.shcFatBinSegment`，`llvm-nm` 查 `__shcRegisterFatBinary`、`_Z19__device_stub__kernPi`、`__shc_module_ctor` 等符号），不再是文本 IR |

---

## 步骤 6：文档补充

**Commit** `f95662b15298`

| 文件 | 内容 |
|---|---|
| `mds/cuda.md`（239 行） | CUDA offload 链路分析（driver action、fatbin、CodeGen） |
| `mds/hip.md`（182 行） | HIP offload 链路分析 |
| `mds/shc.md`（205 行） | SHC 设计与现状 |

**为什么**：SHC 的实现大量复用 CUDA/HIP 路径，把两份对照分析写下来，作为后续改造（wrap、runtime）的参考资料。

---

## 工作区遗留

- `cmake.sh`（未跟踪）：个人 cmake 配置脚本，按参数选择 Release/Debug 与 target 组合；SHC 需要 `LLVM_ENABLE_PROJECTS="clang;lld;"` + `LLVM_TARGETS_TO_BUILD="X86;NVPTX;AMDGPU;RISCV;"`（参数 `6`/`7`）。

---

## 验证结果

- 非 RDC 端到端：`clang -x shc --target=x86_64-unknown-linux-gnu -c kern.shc -o kern.o` 成功，`.shc_fatbin` 段 5412 字节；unbundle 后确认是 `elf32-littleriscv`（`_Z4kernPi` + `__shc_cuid_*`）。
- RDC device 链接：两个 TU 合并进同一个 `elf32-littleriscv`（`_Z2k2v` + `_Z4kernPi` + 两个 cuid）—— 跨 TU 设备链接已验证。
- phase 图（`-ccc-print-phases`）：`9: llvm-offload-binary, {8}, image, (device-shc)` → `10: clang-linker-wrapper, {9}, shc-fatbin, (device-shc)`。
- 回归：`llvm-lit` 跑 `Driver` / `CodeGenSHC` / `CodeGenCUDA` / `CodeGenHIP` / `SemaCUDA` / `OffloadTools`，1819 用例仅剩 `darwin-ld-dedup.c` 失败（Linux 环境下必然失败，与 SHC 无关）。

构建方式：`cd build_new && make -j64 clang clang-linker-wrapper`。

---

## 已知限制与后续工作

1. ✅ **RDC 的链接期注册已完成**（方案 A：与 HIP RDC 同构，由 linker-wrapper 生成注册代码）：
   - `llvm/lib/Frontend/Offloading/OffloadWrapper.cpp`：新增 `FatbinKind {CUDA, HIP, SHC}` 三态及 `getFatbinPrefix` / `getFatbinMagic` / `getFatbinSections` / `getFatbinOffloadKind` 辅助函数，`createFatbinDesc` / `createRegisterGlobalsFunction` / `createRegisterFatbinFunction` 的 `bool IsHIP` 改为 `FatbinKind`（段名 `.shc_fatbin` / `.shcFatBinSegment`，函数 `.shc.fatbin_reg` / `.shc.fatbin_unreg` / `.shc.globals_reg`，句柄 `.shc.binary_handle`，入口 `__shcRegisterFatBinary` / `__shcRegisterFunction` / `__shcRegisterVar` 等）；
   - `OffloadWrapper.h` 的 `wrapSHCBinary` 改为与 `wrapHIPBinary` 相同的签名（`EntryArray` / `Suffix` / `EmitSurfacesAndTextures`），内部生成 fatbin 描述符 + 注册 ctor；
   - `ClangLinkerWrapper.cpp` 的 `wrapDeviceImages` 的 `case OFK_SHC` 传入 `offloading::getOffloadEntryArray(M)`；
   - `llvm-offload-wrapper` 支持 `-kind=shc`，使 `--save-temps` 的 verbose 路径可用。
2. **SHC runtime 缺失**：注册代码已就位，但最终链接仍会卡在 `__shcRegisterFatBinary` / `__shcRegisterFunction` / `__shcLaunchKernel` 等未定义符号，需要 runtime 库才能跑完整链接。
3. **`-emit-llvm -S` 在方案 C 下不可用**：`writeOffloadFile` 硬编码输出扩展名 `"o"`，IR 文本会被当目标文件喂给 `ld.lld`。HIP/CUDA 的 IR 测试都用 `-cc1` 绕过；要修需让扩展名随内容走（IR 文本没有 magic bytes，需按 `;` 开头等特征判断）。
4. **方案 A 残留**：`SHCUtility.cpp` 的 `constructSHCFatbinCommand` 与 `SHC::Linker` 的 `TY_SHC_FATBIN` 分支在方案 C 下已不再被触发（fatbin 改由 linker-wrapper 生成），保留作为备用路径。
5. **bundler 的 dummy host 条目**：`clang-offload-bundler` 要求至少一个 host 输入，SHC 用 `/dev/null`（Windows 下 `NUL`）占位，属已知妥协。
