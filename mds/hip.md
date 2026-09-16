# Clang 前端为支持 HIP 所做的工作

> 基于 `/data/home/bennshi/llvm-project` 仓库（LLVM monorepo，clang 部分）梳理。
> 核心思路：**HIP 基本复用 CUDA 的前端基础设施，用 `LangOpts.HIP` 这个开关在不同环节区分行为。**

## 总览

| 层次 | 主要工作 | 关键文件 |
| --- | --- | --- |
| 语言/选项 | `.hip` 输入类型、`Language::HIP`、LangOptions 开关、驱动选项 | `Driver/Types.cpp`、`Basic/LangOptions.def`、`Options/Options.td` |
| 预处理/头文件 | HIP 宏、自动 `-include` wrapper、数学/libdevice 头 | `Frontend/InitPreprocessor.cpp`、`lib/Headers/__clang_hip_*` |
| 属性/语义 | `HIPManaged`、内核启动与 host/device 检查、诊断 | `Basic/Attr.td`、`Sema/SemaCUDA.cpp`、`DiagnosticSemaKinds.td` |
| 内建/原子 | `__hip_atomic_*` 内建与 lowering | `Basic/Builtins.td`、`CodeGen/CGAtomic.cpp` |
| 代码生成 | 设备桩、fatbin 嵌入、模块注册、managed 变量、CUID、ABI | `CodeGen/CGCUDANV.cpp`、`CodeGen/CodeGenModule.cpp`、`CodeGen/Targets/AMDGPU.cpp` |
| 驱动/工具链 | ROCm 探测、AMDGCN/HIPSPV 工具链、llvm-link+opt+lld、bundler 打包 | `Driver/Driver.cpp`、`ToolChains/AMDGPU.cpp`、`HIPAMD.cpp`、`HIPSPV.cpp`、`HIPUtility.cpp` |
| 附加特性 | hipstdpar、hipRTC、REPL/增量编译 | 多处 |

---

## 1. 语言模式识别与编译选项

- **输入类型**：新增 `TY_HIP` / `TY_PP_HIP` / `TY_HIP_DEVICE` / `TY_HIP_FATBIN`，`.hip` 后缀与 `-x hip` 都能识别并判定 `types::isHIP()`
  - `clang/lib/Driver/Types.cpp:315`、`clang/lib/Driver/Types.cpp:386`
- **语言选项**：`clang/include/clang/Basic/LangOptions.def`
  - `LANGOPT(HIP)` — `:227`
  - `HIPUseNewLaunchAPI` — `:274`
  - `GPUMaxThreadsPerBlock` — `:264`
  - `GPUAllowDeviceInit` — `:263`
  - `GPUDeferDiag` — `:265`
  - `GPUExcludeWrongSideOverloads` — `:266`
  - `OffloadImplicitHostDeviceTemplates` — `:262`
  - `HIPStdPar` / `HIPStdParInterposeAlloc` — `:276-277`
- **驱动选项**：集中在 `clang/include/clang/Options/Options.td` 的 `hip_Group`（`:1487` 起）
  - `--hip-link`(1488)、`--hip-path=`(1495)、`--hip-device-lib=`(1526)、`--hip-version=`(1528)
  - `--hipstdpar`(1497)、`--hipstdpar-interpose-alloc`(1502)、`--hipstdpar-path=` 等
  - `-fhip-new-launch-api`(1530)、`-fhip-kernel-arg-name`(1542)、`-fhip-fp32-correctly-rounded-divide-sqrt`(1535)
  - `-fhip-emit-relocatable`(1569)、`--no-hip-rt`(1490)、`--no-hip-wrapper-include`
  - 与 CUDA 共用的 `--offload-arch=`(1278)、`-fgpu-rdc`(1320)
- **选项校验**：`-fgpu-allow-device-init`、`--gpu-max-threads-per-block` 在非 HIP 输入下告警
  - `clang/lib/Frontend/CompilerInvocation.cpp:638`
- **语言名映射**：`clang/lib/Frontend/CompilerInvocation.cpp:3004`、`:3241`、`:3728`

## 2. 预处理器与头文件（HIP 前端很重的一块）

- **宏定义** — `clang/lib/Frontend/InitPreprocessor.cpp:597-627`
  - `__HIP__`、`__HIPCC__`、`__HIP_DEVICE_COMPILE__`、`__HIP_LLVM__`
  - `__HIP_MEMORY_SCOPE_*`（SINGLETHREAD/WAVEFRONT/WORKGROUP/AGENT/SYSTEM/CLUSTER = 1~6）
  - `__HIP_NO_IMAGE_SUPPORT`、`__HIPSTDPAR__`、`__HIPSTDPAR_INTERPOSE_ALLOC__`
  - `HIP_API_PER_THREAD_DEFAULT_STREAM` / `__HIP_API_PER_THREAD_DEFAULT_STREAM__`
  - `:1493` 处只有 **非 HIP** 的 CUDA 设备编译才定义 `__CUDA_ARCH__`
- **强制 include wrapper**
  - `clang/lib/Driver/ToolChains/AMDGPU.cpp:626`：`CC1Args.append({"-include", "__clang_hip_runtime_wrapper.h"})`，可用 `--no-hip-wrapper-include` 关闭
  - `clang/lib/Driver/ToolChains/Clang.cpp:947-961`：再叠加 `-include hip/hip_runtime.h` 并加入 HIP include 路径
- **头文件（`clang/lib/Headers/`）**
  - `__clang_hip_runtime_wrapper.h`
    - 21-29 行：把 `__host__/__device__/__global__/__shared__/__constant__/__managed__/__cluster_dims__/__no_cluster__` 映射到对应 attribute
    - 35-50 行：设备端 `__cxa_pure_virtual` / `__cxa_deleted_virtual` 弱符号（trap 实现）
    - 64-107 行：设备端 `malloc/free`（`__ockl_dm_alloc/dealloc`，ASan 下走 `__asan_malloc_impl/free_impl`）
    - 113-158 行：串联 libdevice 声明、math、cmath、stdlib、complex、algorithm、new
  - `__clang_hip_libdevice_declares.h`：ROCm device library 内建声明
  - `__clang_hip_math.h`、`__clang_hip_cmath.h`、`__clang_hip_stdlib.h`
  - `hip_wrappers/hip/hip_runtime.h`：hermetic 场景下的 shadow 头（`#include_next`）

## 3. 属性、语义分析与诊断

- **属性** — `clang/include/clang/Basic/Attr.td`
  - `def HIP : LangOpt<"HIP">` — `:440`
  - `HIPManaged`（`__managed__`）仅 HIP 可用 — `:1612`
  - 与 `CUDAConstant` / `CUDAShared` 互斥 — `:1658`
  - 其余 `__global__/__device__/launch_bounds/cluster_dims` 复用 CUDA 属性
- **语义** — 主要在 `clang/lib/Sema/SemaCUDA.cpp` 按 `getLangOpts().HIP` 分支
  - 内核启动检查：HIP 暂不支持设备端启动 — `:72-86`
  - 启动配置函数名：新旧 API 选 `hipConfigureCall` / `__hipPushCallConfiguration` — `:1208`
  - managed 变量检查 — `:250`、`:804`
  - lambda wrong-side 捕获检查 — `:1080-1115`
  - HipStdPar 特例 — `:351`、`:354`、`:1115`
- **诊断** — `clang/include/clang/Basic/DiagnosticSemaKinds.td`
  - `err_hip_invalid_args_builtin_mangled_name` — `:9849`
  - `warn_hip_omp_target_directives`（HIP 不支持 OpenMP target，默认 error）— `:9852`
  - `warn_hip_deprecated_builtin` — `:6401`
  - "HIP device code" 零长数组 — `:6753`

## 4. 内建函数与原子操作

- **HIP 原子内建** — `clang/include/clang/Basic/Builtins.td:2730-2798`
  - `__hip_atomic_load/store/exchange/compare_exchange_weak/compare_exchange_strong/fetch_{add,sub,and,or,xor,min,max}`
- **语义检查与发射** — `clang/lib/CodeGen/CGAtomic.cpp`，大量 `AO__hip_atomic_*` 分支（`:576-1392`），负责 memory scope / semantics 校验与 lowering
- 设备端数学、位操作等通过 libdevice 声明头暴露，最终落到 AMDGPU 后端内建

## 5. 代码生成（CodeGen）

HIP 没有独立的 `CGHIPRuntime.cpp`，逻辑都在与 CUDA 共用的 `clang/lib/CodeGen/CGCUDANV.cpp` 里按 `IsHIP` 分支：

- **设备桩与内核句柄**
  - HIP 下 host 桩函数与 device 函数名不同 — `CGCUDANV.cpp:65`
  - kernel handle 生成 — `CodeGenModule.cpp:5803`
- **启动 API** — `CGCUDANV.cpp:274-445`
  - 按 `-fgpu-default-stream` 选 `hipLaunchKernel` / `hipLaunchKernel_spt` / `hipLaunchByPtr`
- **模块注册 / fatbin 嵌入** — `CGCUDANV.cpp:834-1155`
  - magic `"HIPF"` — `:41`
  - section `.hip_fatbin`（macOS：`__HIP,__hip_fatbin`）、`__hip_module_id`、`__hip_gpubin_handle` — `:903-935`
  - 构造 `__hip_module_ctor` / `__hip_module_dtor`：调用 `__hipRegisterFatBinary` → `__hip_register_globals` → `__hipUnregisterFatBinary`
- **managed 变量** — `__hipRegisterManagedVar`，`:694-725`、`:1217-1224`
- **CUID 唯一化** — `__hip_cuid_<hash>` 全局：`CodeGenModule.cpp:1308-1314`；PGO sections 也按 CUID 命名：`CGCUDANV.cpp:193`
- **其他特化**
  - `-mprintf-kind` 仅 HIP 生效 — `CodeGenModule.cpp:1248`
  - kernel 参数名保存（`HIPSaveKernelArgName`）— `CodeGenModule.cpp:3074`
  - HIP 允许符号名含 `.` — `CodeGenModule.cpp:8885`
  - HIPSPV 下常量地址空间映射到 `cuda_device`，以适配 flat 指针 — `CodeGenModule.cpp:6351-6357`
- **ABI** — `clang/lib/CodeGen/Targets/AMDGPU.cpp`
  - HIP kernel 的 launch bounds → max threads（`--gpu-max-threads-per-block`），第二参数被 HIP 重解释为 min waves per EU — `:347-389`
  - generic 指针参数强制为 global — `:35`
  - OpenCL 与老式 HIP 原子对 thread-private 的处理 — `:556`
- **TargetInfo** — `clang/lib/Basic/Targets/AMDGPU.cpp:294-309`
  - HIP **host** 端（`Opts.HIP && !Opts.CUDAIsDevice`）需保留 legacy 默认 target attributes

## 6. Driver：工具链、动作图与打包

- **卸载种类 `Action::OFK_HIP`** — `clang/lib/Driver/Driver.cpp`
  - 架构合法性校验（只允许 AMDGPU / AMDGCNSPIRV）— `:1028`
  - 默认架构 `OffloadArch::HIPDefault` — `:4065`
  - 编译 ID / CUID 初始化 — `:1137`
  - device-only 链接直接消费打包 bitcode — `:3639-3667`
  - 非 RDC 的 `-S` 把 host/device 汇编打包 — `:3597`、`:3740-3744`
  - `-fhip-emit-relocatable` 校验 — `:4139-4149`
- **ROCm/HIP 安装探测** — `clang/lib/Driver/ToolChains/AMDGPU.cpp`、`AMDGPU.h`
  - `RocmInstallationDetector`：路径优先级 `--hip-path` > `HIP_PATH` > `--rocm-path` > `ROCM_PATH` > 自动探测 — `:319-372`、`detectHIPRuntime` `:438`
  - `.hipVersion` 解析 — `:159`
  - `AddHIPIncludeArgs`（含 hipstdpar 处理）— `:531-607`
  - 设备库以 bitcode 链接：ocml / ockl / oclc_* / asan / wavefrontsize64 等 — `:1140-1164` (`AddBCLib`)
- **AMDGCN 工具链** — `clang/lib/Driver/ToolChains/HIPAMD.cpp`
  - `AMDGCN::Linker::constructLldCommand`：`llvm-link` + `lld -flavor gnu -m elf64_amdgpu -shared`，产出 HSA code object — `:50-138`
  - AMDGPU SPIR-V 路径：`constructLinkAndEmitSpirvCommand`（SPIR-V BE 或 `llvm-spirv`）— `:145-189`
- **HIPSPV 工具链** — `clang/lib/Driver/ToolChains/HIPSPV.cpp`
  - 面向 CHIP-Star / chipStar，跑 `HipSpvPasses` 插件（`:29`、`:60`），再以 SPIR-V BE 或 `llvm-spirv` 翻译
- **cc1 参数传递** — `clang/lib/Driver/ToolChains/Clang.cpp`
  - `-fhip-new-launch-api`、`-fhip-kernel-arg-name`、`--hipstdpar`、`-fgpu-rdc` 等 — `:7413-7428`
  - HIP device 专属数学选项 — `:8373-8400`
  - HIP 多输入/依赖文件、fatbin 输出静默 — `:5210-5234`、`:9783`
- **打包** — `clang/lib/Driver/ToolChains/HIPUtility.cpp`
  - `constructHIPFatbinCommand` 调用 `clang-offload-bundler` — `:53`
  - bundle ID 的 offload kind 按 code object version 选 `hip` / `hipv4` — `:72-75`
  - 4096 字节对齐；插入 dummy host entry；`amdgcn-amd-amdhsa--` 兼容 hack — `:31-49`
- **`--offload-arch=native`** — `clang/tools/offload-arch/AMDGPUArchByHIP.cpp`，通过 HIP 运行时探测本机 GPU

## 7. 附加特性

- **hipstdpar**（标准并行算法加速）
  - 选项/LangOpt：`--hipstdpar`、`HIPStdPar`（`Options.td:1497`）
  - Sema 放宽 lambda 捕获与调用侧检查 — `SemaCUDA.cpp:351`、`:1115`
  - Driver 额外 `-include hipstdpar_lib.hpp`，校验 rocThrust/rocPrim — `AMDGPU.cpp:562-607`
  - lld 传 `-plugin-opt=-amdgpu-enable-hipstdpar` — `HIPAMD.cpp:63`
- **hipRTC**：wrapper 头中 `__HIPCC_RTC__` 分支避免依赖标准 C/C++ 头 — `__clang_hip_runtime_wrapper.h:126-168`
- **REPL / 增量编译**：`LangOpts.IncrementalExtensions` 下允许设备端内核调用 — `SemaCUDA.cpp:76`；跳过 `__hip_cuid_` — `CodeGenModule.cpp:1304`

---

## 一句话总结

要让 clang 支持 HIP，前端做了四类事：

1. **（a）把 HIP 变成一种一等语言模式** —— 输入类型、语言选项、宏定义、头文件自动注入；
2. **（b）把 HIP 的编程模型接进 Sema** —— 属性、内核启动与 host/device 语义检查、专用诊断；
3. **（c）复用并特化 CUDA 的 CodeGen** —— 设备桩、fatbin 嵌入、模块注册、managed 变量、kernel 参数名、CUID、原子内建、kernel ABI；
4. **（d）在 Driver 侧搭起完整的卸载编译流水线** —— ROCm/HIP 运行时与设备库探测、AMDGCN/HIPSPV 工具链、`llvm-link + opt + lld`、`clang-offload-bundler` 打包 fatbin。

## 修改 HIP 前端的常用入口

| 目标 | 文件 |
| --- | --- |
| 加语言/编译开关 | `clang/include/clang/Basic/LangOptions.def` |
| 加驱动选项 | `clang/include/clang/Options/Options.td` |
| 语义/诊断 | `clang/lib/Sema/SemaCUDA.cpp`、`clang/include/clang/Basic/DiagnosticSemaKinds.td` |
| 代码生成 | `clang/lib/CodeGen/CGCUDANV.cpp`、`clang/lib/CodeGen/CodeGenModule.cpp` |
| 头/宏 | `clang/lib/Headers/__clang_hip_*.h`、`clang/lib/Frontend/InitPreprocessor.cpp` |
| 工具链/打包 | `clang/lib/Driver/ToolChains/{AMDGPU,HIPAMD,HIPSPV,HIPUtility}.cpp` |

## 参考文档

- `clang/docs/HIPSupport.md` —— HIP 支持总览、用法、路径优先级与环境变量、预定义宏
- `clang/docs/AMDGPUSupport.md`、`clang/docs/OffloadingDesign.md`、`clang/docs/ClangOffloadBundler.md`
- 测试：`clang/test/Driver/hip-*.hip`、`clang/test/CodeGenHIP/`、`clang/test/SemaHIP/`、`clang/test/Headers/__clang_hip_*.hip`
