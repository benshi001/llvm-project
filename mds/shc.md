# 在 clang 中新增 SHC 语言（参考 HIP 实现）

## 0. 总体策略

> **把 SHC 做成 CUDA 家族的第三个成员**——`LangOpts.CUDA` 在 HIP 下也为 true（`clang/lib/Basic/LangOptions.cpp:217-218`），SHC 照抄这一点，就能白嫖 Sema/CodeGen 里所有 `getLangOpts().CUDA` 的既有逻辑（属性、kernel call、`<<<>>>`、device stub 等），改动量最小。

### 需要新增的 6 样东西

| 新增 | 值 | 对应 HIP |
| --- | --- | --- |
| 语言枚举 | `Language::SHC` | `Language::HIP` |
| 语言选项 | `LangOpts.SHC` + `LangOpts.CUDA=true` | `LangOpts.HIP` |
| 输入类型 | `TY_SHC` / `TY_PP_SHC` / `TY_SHC_DEVICE` / `TY_SHC_FATBIN` | `TY_HIP*` |
| 卸载种类 | `Action::OFK_SHC`、`OffloadKind::OFK_SHC`、bundle kind `"shc"` | `OFK_HIP` / `"hip"` |
| 工具链 | `SHCToolChain`（device triple `riscv32-unknown-elf`，链接用 `ld.lld -r`） | `HIPAMDToolChain` / `AMDGCN::Linker` |
| CodeGen | Prefix `shc`，magic `"SHCF"`，section `.shc_fatbin`，launch `shc_launch_kernel` | `hip` / `HIPF` / `.hip_fatbin` / `hipLaunchKernel` |

---

## 1. Basic / LangOptions（语言开关）

| 文件:行 | 改动 |
| --- | --- |
| `clang/include/clang/Basic/LangStandard.h:23` | `enum class Language` 加 `SHC` |
| `clang/include/clang/Basic/LangOptions.def:227` 附近 | 加 `LANGOPT(SHC, 1, 0, NotCompatible, "SHC")` |
| **`clang/lib/Basic/LangOptions.cpp:217-218`** | **最关键**：<br>`Opts.SHC = Lang == Language::SHC;`<br>`Opts.CUDA = Lang == Language::CUDA \|\| Opts.HIP \|\| Opts.SHC;` |
| `clang/lib/Basic/LangOptions.cpp:219-228` | SHC 的 FP contract 默认值（照 HIP 用 `FPM_FastHonorPragmas`） |
| `clang/include/clang/Basic/LangOptions.def` | 复用 `GPURelocatableDeviceCode`（`-fgpu-rdc`），SHC 因为要 relocatable ELF，**应强制 RDC** |

`LangOpts.CUDA=true` 之后，以下既有逻辑自动生效，基本不用改：

- `ParseExpr.cpp:1826` 对 `tok::lesslessless` 的解析（`<<<grid, block>>>`）——它**不检查语言**，无需改 Parser
- `SemaCUDA.cpp` 的 `ActOnExecConfigExpr` / kernel call 基础设施
- `CGExpr.cpp:6524` → `CGExprCXX.cpp:514` → `CGCUDANV.cpp` 的 device stub 生成链

---

## 2. 输入类型与语言名映射

| 文件:行 | 改动 |
| --- | --- |
| `clang/include/clang/Driver/Types.def:47-49` | 仿 HIP 加 3 行：`TYPE("shc-cpp-output", PP_SHC, INVALID, "shci", …)`、`TYPE("shc", SHC, PP_SHC, "shc", …)`、`TYPE("shc", SHC_DEVICE, PP_SHC, "shc", …)` |
| `clang/include/clang/Driver/Types.def:124` 附近 | `TYPE("shc-fatbin", SHC_FATBIN, INVALID, "shcfb", …)` |
| `clang/include/clang/Driver/Types.h:89` | 加 `bool isSHC(ID Id);` |
| `clang/lib/Driver/Types.cpp` | `:106`、`:153`、`:210`、`:283`、`:315`（仿 `isHIP` 写 `isSHC`）、`:386 .Case("shc", TY_SHC)` / `.Case("shci", TY_PP_SHC)` |
| `clang/lib/Frontend/FrontendOptions.cpp:35` | `.Case("shc", Language::SHC)`（支持 `-x shc`） |
| `clang/lib/Frontend/CompilerInvocation.cpp` | `:3004` `case Language::SHC: Lang = "shc";`；`:3241 .Case("shc", Language::SHC)`；`:3695`（`-std=` 校验，允许 CXX）；`:3728` 返回 `"SHC"` |
| `clang/lib/Frontend/FrontendActions.cpp:885` | `case Language::SHC:`（允许 CodeGen action） |

---

## 3. Offload Kind（Driver 动作图 + LLVM 侧）

| 文件:行 | 改动 |
| --- | --- |
| `clang/include/clang/Driver/Action.h:88-102` | 加 `OFK_SHC = 0x20`，`OFK_DeviceLast = OFK_SHC` |
| `clang/lib/Driver/Action.cpp:159` | `GetOffloadKindName` 加 `case OFK_SHC: return "shc";` |
| `llvm/include/llvm/Object/OffloadBinary.h:38` | 加 `OFK_SHC = (1 << 5)` |
| `llvm/lib/Object/OffloadBinary.cpp` | `getOffloadKindName` / `getOffloadKind` 字符串映射加 `"shc"` |
| **`clang/lib/Driver/OffloadBundler.cpp:102-104`** | `isOffloadKindValid()` 加 `OffloadKind == "shc"`，否则 bundler 直接拒绝 |
| `clang/lib/Driver/Driver.cpp:1102-1123` | 加 `bool IsSHC = any_of(Inputs, isSHC) \|\| Args.hasArg(OPT_shc_link)`，并插入 `{IsSHC, Action::OFK_SHC}` |
| `clang/lib/Driver/Driver.cpp:1137` | CUID 初始化条件加 `\|\| IsSHC`（RDC 下符号去重必须） |
| `clang/lib/Driver/Driver.cpp:961/1028/1073/4062` | 架构校验与默认 arch：HIP 限定 AMDGPU(`:1028`)，SHC 需放行 RISCV——建议仿 SYCL 走空/固定 arch（`Archs.insert(StringRef())`，`:4066`），或在 `OffloadArch::TargetArch`（`OffloadArch.h:39`）加 `RISCV` 并提供 `SHCDefault()`（仿 `OffloadArch.h:79`） |
| `clang/lib/Driver/Driver.cpp:3597/3639/4121-4300` | 所有 `Kind == Action::OFK_HIP` 的分支改为包含 `OFK_SHC`（建议抽 `static bool isSHCOffload(Action::OffloadKind)`） |
| `clang/lib/Driver/ToolChains/Clang.cpp` | `:4670`（`!isHIP(InputType)`）、`:5219-5234`、`7413-7428`、`8373-8400`、`9783` 的 `IsHIP` 判定同步加 `IsSHC` |

---

## 4. 工具链（device = riscv32，产物 = relocatable ELF）

新建 `clang/lib/Driver/ToolChains/SHC.{h,cpp}`：

```cpp
SHCToolChain : public ToolChain   // 可继承 BareMetal，device triple = riscv32-unknown-elf
  - addClangTargetOptions()       // 传 -fcuda-is-device, -fshc-*, -fgpu-rdc
  - buildLinker()                 // 返回 tools::SHC::Linker
  - AddSHCIncludeArgs()           // -include __clang_shc_runtime_wrapper.h（仿 AMDGPU.cpp:626）

tools::SHC::Linker::ConstructJob()
  - JA.getType() == TY_SHC_FATBIN → SHC::constructSHCFatbinCommand()
  - 否则 → ld.lld -r（relocatable）把 device .o 链成单个 relocatable ELF
```

新建 `clang/lib/Driver/ToolChains/SHCUtility.{h,cpp}`，照抄 `HIPUtility.cpp:53-111` 的 `constructHIPFatbinCommand`：

```bash
clang-offload-bundler -type=o -bundle-align=4096 \
  -targets=host-x86_64-unknown-linux-gnu,shc-riscv32-unknown-elf-<arch> \
  -input=/dev/null -input=<device.o> -output=<out.shcfb>
```

（HIP 里那段 `amdgcn-amd-amdhsa--` 的兼容 hack，`HIPUtility.cpp:31-49`，SHC 不需要）

再在 `Driver::getToolChain` 里按 triple/offload kind 创建 `SHCToolChain`，并把新文件加进 `clang/lib/Driver/CMakeLists.txt`。

---

## 5. 头文件与预定义宏

| 文件 | 改动 |
| --- | --- |
| 新建 `clang/lib/Headers/__clang_shc_runtime_wrapper.h` | 照 `__clang_hip_runtime_wrapper.h:19-29`，在 `#if __SHC__` 下定义 `__host__/__device__/__global__/__shared__/__constant__/__managed__`；**必须声明 `shc_launch_kernel`**（见 §6） |
| `clang/lib/Headers/CMakeLists.txt:88` 区域 | 注册该头 |
| `clang/lib/Frontend/InitPreprocessor.cpp:597-627` | 定义 `__SHC__`、`__SHCC__`、`__SHC_DEVICE_COMPILE__` 等 |

> ⚠️ `clang/lib/CodeGen/CGCUDANV.cpp:459-463` 会在 TU 里 **lookup** launch 函数名，找不到就报错 `"Can't find declaration for …"`。所以 `shc_launch_kernel` 必须由 wrapper 头声明，签名建议对齐 HIP：
>
> ```cpp
> int shc_launch_kernel(const void *func, dim3 gridDim, dim3 blockDim,
>                       void **args, size_t sharedMem, void *stream);
> ```
>
> （`dim3` 类型是从该声明的第 2 个参数取的，`CGCUDANV.cpp:465-466`）

---

## 6. CodeGen（核心，全在 `CGCUDANV.cpp`）

| 位置 | 改动 |
| --- | --- |
| `:41` | 加 `constexpr unsigned SHCFatMagic = 0x53484346; // "SHCF"` |
| `:257-262` | `else if (CGM.getLangOpts().SHC) Prefix = "shc";` → 自动得到 `__shc_module_ctor`、`__shcRegisterFatBinary`、`__shc_register_globals`、`__shc_fatbin_wrapper` |
| **`:442-450`（launch API）** | **关键**：SHC 不走 `addPrefixToName`，直接 `LaunchKernelName = "shc_launch_kernel"` |
| `:341` | `emitDeviceStub` 中加 `\|\| CGF.getLangOpts().SHC`，走 `emitDeviceStubBodyNew`（打包 `void** args`） |
| `:843-958` `makeModuleCtorFunction` | 把 `bool IsHIP` 扩成 `IsHIP \|\| IsSHC`（建议改名 `IsHIPOrSHC`）：<br>• `:849` `if (CudaGpuBinaryFileName.empty() && !IsHIPOrSHC) return nullptr;`<br>• `:903` 分支：section `.shc_fatbin` / `.shcFatBinSegment` / `__shc_module_id`；外部符号 `__shc_fatbin[_CUID]`（`:925-932` 那条 RDC 路径正是"在 x86 obj 里留 section，内容由链接期填充"）<br>• `FatMagic = SHCFatMagic` |
| `:984-1000` | `__shc_gpubin_handle[_CUID]`（HIP ABI 里"每个链接模块只有一个 fatbin，但有多个 ctor"的判重逻辑，SHC 同样需要） |
| `:1295-1380` `createOffloadingEntries()` | RDC 下用 `llvm::offloading::emitOffloadingEntry` 把 kernel / device global 登记进 offloading entry 段（relocatable ELF 里靠符号名查表） |
| `:1190` | RDC 模式下生成 `__shc_register_globals` |

`clang/lib/CodeGen/CodeGenModule.cpp`：

- `:732 createCUDARuntime()` 目前无条件 `CreateNVCUDARuntime(*this)`，**无需改**（SHC 复用同一个 runtime 类）
- `:1308` 的 `__hip_cuid_<hash>` 全局加 SHC 分支（RDC 下 device 静态变量需要唯一化）
- `:8885` HIP 允许符号名含 `.` 的逻辑按需要同步

---

## 7. 端到端流水线与目标产物

```bash
clang++ -x shc --offload-arch=<shc-arch> --offload-targets=riscv32-unknown-elf -fgpu-rdc a.shc
```

| 步骤 | 命令 | 产物 |
| --- | --- | --- |
| ① device 编译 | `cc1 -triple riscv32-unknown-elf -fcuda-is-device -fgpu-rdc` | device `.o`（relocatable） |
| ② device 链接 | `ld.lld -r` | 单个 relocatable ELF |
| ③ 打包 fatbin | `clang-offload-bundler -type=o … -targets=host-x86_64-…,shc-riscv32-…` | `TY_SHC_FATBIN`（`.shcfb`） |
| ④ host 编译 | `cc1 -triple x86_64 … -foffload-include-binary <fatbin>`（`Options.td:1857`）或 RDC 下留外部符号 | host `.o` |

x86 host `.o` 中最终生成的 section / 符号：

```
.shc_fatbin          <- fatbin 本体（或外部符号 __shc_fatbin[_CUID] 占位）
.shcFatBinSegment    <- __shc_fatbin_wrapper { magic "SHCF", version, data, null }
__shc_gpubin_handle[_CUID]
__shc_module_ctor    -> __shcRegisterFatBinary(__shc_fatbin_wrapper)
                        __shc_register_globals(handle)
.llvm.offloading     <- offloading entries（kernel 符号表，RDC 必需）
kernel stub body     -> shc_launch_kernel(&stub, gridDim, blockDim, args, shmem, stream)
```

---

## 8. 虽不属于"语义分析"但必须打通的最小点

- `clang/lib/Sema/SemaCUDA.cpp` 里 `getLangOpts().HIP` 的若干分支（`:74`、`:86`、`:250`、`:804`、`:1208`）改成 `HIP || SHC`，否则 host/device 函数分流、managed 变量、`<<<>>>` 的 config 会走错分支
- `clang/lib/CodeGen/CGExpr.cpp:6524` / `CGExprCXX.cpp:514` 无需改（`CUDAKernelCallExpr` 由 `LangOpts.CUDA` 驱动）
- `clang/lib/Basic/Targets/RISCV.cpp`：device 侧 riscv32 的 TargetInfo 一般无需改；仅当 host(x86)+aux(riscv32) 组合需要特殊默认属性时才动（参考 AMDGPU 对 HIP host 的处理 `Targets/AMDGPU.cpp:294`）

---

## 9. 建议落地顺序

1. **§1 + §2**（语言开关 + 输入类型）→ 能跑 `clang++ -x shc -c a.shc`，host 侧单趟编译通
2. **§5**（宏 + wrapper 头）→ `__device__/__global__/__host__`、`shc_launch_kernel` 可用
3. **§6**（CodeGen：Prefix、magic、section、launch 名）→ host obj 里出现 `shc_launch_kernel` 调用与 `.shc_fatbin`
4. **§3**（OFK_SHC + bundler kind）→ 卸载动作图成立
5. **§4**（SHC ToolChain + `ld.lld -r` + fatbin 打包）→ 打通 device 侧
6. 补测试：`clang/test/Driver/shc-*.shc`、`clang/test/CodeGenSHC/kernel-launch.shc`（参考 `clang/test/CodeGenCUDA/kernel-stub-name.cu`）

## 10. 改动量估算

约 15~20 个文件的改动 + 5 个新文件：

- `clang/lib/Driver/ToolChains/SHC.h`
- `clang/lib/Driver/ToolChains/SHC.cpp`
- `clang/lib/Driver/ToolChains/SHCUtility.h`
- `clang/lib/Driver/ToolChains/SHCUtility.cpp`
- `clang/lib/Headers/__clang_shc_runtime_wrapper.h`

其中 `CGCUDANV.cpp` 的改动最密集，但有清晰的 HIP 分支可对照。

---

## 附：常用入口速查

| 目的 | 文件 |
| --- | --- |
| 加语言开关 | `clang/include/clang/Basic/LangOptions.def` + `clang/lib/Basic/LangOptions.cpp` |
| 加命令行选项 | `clang/include/clang/Options/Options.td` |
| 加输入类型 | `clang/include/clang/Driver/Types.def` + `clang/lib/Driver/Types.cpp` |
| 加卸载种类 | `clang/include/clang/Driver/Action.h` + `llvm/include/llvm/Object/OffloadBinary.h` |
| 内核启动 / fatbin 嵌入 | `clang/lib/CodeGen/CGCUDANV.cpp` |
| device 编译 / 链接、fatbin 打包 | `clang/lib/Driver/ToolChains/SHC.cpp`、`SHCUtility.cpp` |

---

## 11. 补充：SHC 恒 RDC 与 `-S` 行为

- **SHC 必须走 RDC**：device 代码始终可重定位，fatbin 只在最终链接时由 linker-wrapper 生成。driver 显式拒绝 `-fno-gpu-rdc`（`Driver.cpp` 的 `CreateOffloadingDeviceToolChains`，用 `err_drv_argument_not_allowed_with` 报 `-fno-gpu-rdc not allowed with SHC`），`Clang.cpp` 里 `IsRDCMode` 的默认值改为 `IsSYCL || IsSHC`。原先"每个 TU 编译期就产出 fatbin"的 `LinkerWrapperJobAction(TY_SHC_FATBIN)` 分支已删除，SHC 与 SYCL / CUDA-RDC 走同一条通用分支。
  - 后果：`-c` 的产物里只有 `.llvm.offloading` / `.llvm.rodata.offloading` 与 `.offloading.entry.<kernel>`，不再有 `.shc_fatbin`；`__shcRegisterFatBinary` 等注册符号也随之不在编译期出现。
  - `bundleSHC` / `shc::fatbinary` 保留，供最终链接使用。
- **`-S` 只影响 host**：device 侧不受 `-S` 影响，仍跑完整流程——`Driver.cpp` 里 device 的 phase 列表在 SHC + `-S` 时固定按 `phases::Assemble` 计算（`preprocessor → compiler → backend → assembler`），产出 object 后照常生成 offload image（`llvm-offload-binary ... kind=shc`）；host 则停在汇编、输出 `.s`。因 SHC 恒 RDC，该汇编里只有 `.llvm.offloading`（device image 数据），没有 `.shc_fatbin`。
- 测试：`clang/test/Driver/shc-rdc.shc`（新增：`-fno-gpu-rdc` 诊断；`-S` 下 device 仍完整编译并产出 offload image、host 只出汇编）、`clang/test/Driver/shc-phases.shc`、`clang/test/CodeGenSHC/kernel-launch.shc`（改为检查 RDC 产物）。
