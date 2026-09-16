# Clang 前端为支持 CUDA 所做的工作

> 基于 LLVM 主线仓库（`/data/home/bennshi/llvm-project`）的实际代码梳理。

按编译流水线分层：Driver → Frontend/预处理器 → Lexer/Parser → Sema → CodeGen → 头文件兼容层。

---

## 1. 语言模式与编译选项（`Basic`）

**文件类型**：`.cu` 映射为 `TY_CUDA` / `TY_CUDA_DEVICE`（`clang/include/clang/Driver/Types.def:45-46`），最终产物类型 `TY_CUDA_FATBIN`（`Types.def:123`）。

**LangOptions**（`clang/include/clang/Basic/LangOptions.def`）：

```226:226:clang/include/clang/Basic/LangOptions.def
LANGOPT(CUDA              , 1, 0, NotCompatible, "CUDA")
```

- `CUDA:226` — 是否处于 CUDA 语言模式
- `CUDAIsDevice:258` — 当前是设备侧还是主机侧编译，是整个前端的"总开关"
- `CUDAHostDeviceConstexpr:259` — 未标注的 `constexpr` 函数视为 `__host__ __device__`
- `CUDANVCCABI:268` — 生成 NVCC 兼容的主机注册 ABI
- `OffloadImplicitHostDeviceTemplates:262`
- `GPUDeferDiag:265` / `GPUExcludeWrongSideOverloads:266`
- `OffloadUniformBlock:275`

**版本与架构知识表**（`clang/include/clang/Basic/Cuda.h`、`clang/lib/Basic/Cuda.cpp`）：

- `CudaVersion` 枚举覆盖 7.0 ~ 13.4，`FULLY_SUPPORTED = CUDA_133`、`PARTIALLY_SUPPORTED = CUDA_134`（`Cuda.h:22-60`）
- `MinVersionForOffloadArch` / `MaxVersionForOffloadArch`（`Cuda.cpp:83-117`）：每个 `sm_XX` 支持的 CUDA 版本区间
- `CudaFeature`（`Cuda.h:80-85`）：
  - `CUDA_USES_NEW_LAUNCH`（≥ 9.2，走 `cudaLaunchKernel`）
  - `CUDA_USES_FATBIN_REGISTER_END`（≥ 10.1，需要 `__cudaRegisterFatBinaryEnd`）
  - 这两项直接决定 CodeGen 生成哪一套启动/注册代码

**驱动选项**（`clang/include/clang/Options/Options.td:1401-1443`）：

`--cuda-gpu-arch=` / `--no-cuda-gpu-arch=`、`--cuda-path=`、`--cuda-device-only` / `--cuda-host-only`、`--cuda-include-ptx=`、`--no-cuda-version-check`、`-Xcuda-ptxas`、`-Xcuda-fatbinary`、`-fcuda-rdc`（等价于 `-fgpu-rdc`）、`--cuda-emit-nvcc-abi`、`-fcuda-flush-denormals-to-zero`。

---

## 2. Driver：SDK 探测 + 主机/设备双编译编排

### 2.1 CUDA 安装探测

`CudaInstallationDetector`（`clang/lib/Driver/ToolChains/Cuda.cpp:150-302`）：

1. 候选路径依次来自 `--cuda-path=`、PATH 中 `ptxas` 反推（其父目录的父目录）、`/usr/local/cuda`、`/usr/local/cuda-{7.0,7.5,8.0}`、Debian 特例 `/usr/lib/cuda`
2. 读 `include/cuda.h` 中的 `CUDA_VERSION` 判定版本（解析函数 `parseCudaHFile`）
3. 构建 `LibDeviceMap`：`nvvm/libdevice/libdevice.10.bc`（CUDA 9+ 单文件），或旧版 `libdevice.compute_XX.YY.bc` → `sm_XX` 的映射表（`Cuda.cpp:238-292`）
4. 版本过新/部分支持时告警：`WarnIfUnsupportedVersion`（`Cuda.cpp:136`）

### 2.2 两个工具链

| 工具链 | 位置 | 关键方法 |
|---|---|---|
| `CudaToolChain` | `Cuda.cpp:901` | `TranslateArgs:1009`、`getDefaultDenormalModeForType:968`、`AddCudaIncludeArgs:982` |
| `NVPTXToolChain` | `Cuda.cpp:761` | `TranslateArgs:781`、`addClangTargetOptions:818`（注入 libdevice bitcode，见 `Cuda.cpp:935-942`）、`getSystemGPUArchs:873`（`-march=native` 时探测本机 GPU）、`AddClangSystemIncludeArgs:822` |

### 2.3 头文件注入

`CudaInstallationDetector::AddCudaIncludeArgs`（`Cuda.cpp:304-331`）：

- 把 `ResourceDir/include/cuda_wrappers` 加入 `-internal-isystem`（用于包装 STL 头）
- 强制 `-include __clang_cuda_runtime_wrapper.h`

### 2.4 外部工具封装

- `NVPTX::Assembler` → **ptxas**（`Cuda.cpp:398`）：`-O` 等级映射、`--gpu-name`、`-lineinfo`、`-v`
- `NVPTX::FatBinary` → **fatbinary**（`Cuda.cpp:545`）：`--image3=kind=ptx|elf,sm=XX,file=...`
- `NVPTX::Linker` → **nvlink**（`Cuda.cpp:593`）

### 2.5 Offload Action 图

`clang/lib/Driver/Driver.cpp`：

- `OFK_Cuda` 与 OpenMP/HIP/SYCL 并列参与 offloading（`4164-4184`，用 `types::isCuda` 过滤输入类型）
- 每个绑定的 GPU arch 展开成一条独立设备编译链（`4186-4248`）
- 非 RDC 或 nvcc ABI 时，把各设备产物用 `LinkJobAction` 打成 `TY_CUDA_FATBIN` 再喂给主机编译（`4313-4321`）
- 未指定 arch 时回退到 `nvptx64-nvidia-cuda` 默认三元组（`1076-1082`）
- CUDA 版本告警（`1202-1207`）
- 工具链选择（`6113-6157`）
- 新版 `-foffload-via-llvm` 走 `clang-linker-wrapper` 而非 fatbinary（`4158`、`4280`）

---

## 3. Frontend / 预处理器

- **头文件搜索使用 aux triple**：设备编译时必须用**主机**三元组去找系统头 —— `clang/lib/Frontend/CompilerInstance.cpp:498-507`
- **`__CUDA_ARCH__` 由 Target 定义**：`clang/lib/Basic/Targets/NVPTX.cpp:194-205` 定义 `__CUDA_ARCH__`、`__CUDA_ARCH_SPECIFIC__`、`__CUDA_ARCH_FEAT_SMxx_ALL`、`__CUDA_ARCH_FAMILY_SPECIFIC__`
- **`__CUDACC__` 不在编译器里硬编码**，而是由包装头 `clang/lib/Headers/__clang_cuda_runtime_wrapper.h` 在精确时机 `#define` / `#undef`（第 37、46、106、123、269、415 行），以控制 libstdc++ 与 CUDA 头的行为
- **CUDA 地址空间**：`LangAS::cuda_device` / `cuda_constant` / `cuda_shared`（`clang/include/clang/Basic/AddressSpaces.h:45-48`）；NVPTX 映射为 1 / 4 / 3（`Targets/NVPTX.h:35-37`），AMDGPU 与 SPIR 复用同一套（HIP / HIPSPV）
- `CompilerInvocation.cpp:5170-5173`：CUDA 设备编译时 aux triple 设为主机三元组

---

## 4. Lexer / Parser / 属性 / AST

**词法**：`LangOpts.CUDA` 时把 `<<<` 和 `>>>` 合并为单个 token，避免被解析成三个 `<` —— `clang/lib/Lex/Lexer.cpp:4372, 4449`

**解析**：

- `Parser::ParseCUDAFunctionAttributes`（`clang/lib/Parse/ParseDecl.cpp:1079`）：处理 `__host__` / `__device__` / `__global__`
- 内核启动配置 `<<<...>>>` → `SemaCUDA::ActOnExecConfigExpr`（`ParseExpr.cpp:1863`）
- CUDA 下 GNU 属性可紧跟 `<<<`（`ParseExprCXX.cpp:1230`）；lambda 上属性位置告警（`1453-1460`）
- `#pragma clang force_cuda_host_device` → `PragmaForceCUDAHostDeviceHandler`（`Parse/ParsePragma.cpp:367, 4026`）

**属性**（`clang/include/clang/Basic/Attr.td:1540-1658`，均带 `let LangOpts = [CUDA]`）：

`CUDADevice`、`CUDAHost`、`CUDAGlobal`、`CUDAInvalidTarget`、`CUDAConstant`、`CUDAShared`、`CUDALaunchBounds`、`CUDAGridConstant`、`CUDAClusterDims` / `CUDANoCluster`、`CUDADeviceBuiltinSurfaceType` / `CUDADeviceBuiltinTextureType`、`CUDACudartBuiltin`；并声明互斥关系（`CUDADevice`↔`CUDAGlobal`、`CUDAHost`↔`CUDAGlobal`、`CUDAConstant`↔`CUDAShared`）。语言选项 `def CUDA : LangOpt<"CUDA">`（`Attr.td:439`）。

**AST 节点**：`CUDAKernelCallExpr`（`clang/lib/AST/ExprCXX.cpp:1995`），继承 `CallExpr` 并把 `<<<>>>` 配置存为 PreArg（`END_PREARG`）。配套改动分布在 `StmtPrinter`、`StmtProfile`、`ExprClassification`、`ItaniumMangle`、`ExprConstant`、`Serialization`、`StaticAnalyzer`、`ASTMatchers`、`CodeGen` 等。

---

## 5. Sema：CUDA 语义的核心

`SemaCUDA` 是 Sema 的一个子对象（通过 `Actions.CUDA()` 访问），声明在 `clang/include/clang/Sema/SemaCUDA.h`，实现在 `clang/lib/Sema/SemaCUDA.cpp`。

### 5.1 目标识别

- `IdentifyTarget(const FunctionDecl*)`、`IdentifyTarget(const ParsedAttributesView&)`（`SemaCUDA.cpp:146, 211`）
- `IdentifyTarget(const VarDecl*)`：变量目标 `CVT_Device` / `CVT_Host` / `CVT_Both` / `CVT_Unified`（`SemaCUDA.h:119-124`）
- `isImplicitHostDeviceFunction`、`CurrentTarget()`

### 5.2 调用合法性 + 延迟诊断（最难的部分）

- `IdentifyPreference`（`SemaCUDA.cpp:311`）返回 `CFP_Never` / `CFP_WrongSide` / `CFP_HostDevice` / `CFP_SameSide` / `CFP_Native`（`SemaCUDA.h:161-170`）
- `CheckCall`（`:994`）：
  - `CFP_Never` → 立即报错
  - `CFP_WrongSide` → 只登记**延迟诊断**，等确认该函数真的会被 codegen 时才报
- 延迟诊断由 `SemaDiagnosticBuilder` 实现（`clang/include/clang/Sema/SemaBase.h:200-221`，内部 `ImmediateDiag` / `PartialDiagId` 二选一）
- 入口：`DiagIfDeviceCode`（`:929`）/ `DiagIfHostCode`（`:963`）
- 去重靠 `LocsWithCUDACallDiags`，调用栈追踪靠 `DeviceKnownEmittedFns`（`SemaCUDA.h:73-83`）

### 5.3 隐式属性推断

- `maybeAddHostDeviceAttrs`（`:850`）：给未标注的函数/模板加隐式 H/D 属性
- `inferTargetForImplicitSpecialMember`（`:462`）：隐式构造/析构/拷贝从基类与成员的 target 反推
- `inheritTargetAttrs`（`:1196`）、`SetLambdaAttrs`（`:1130`，lambda 默认 host-device）、`MaybeAddConstantAttr`（`:915`）

### 5.4 重载决议

- `EraseUnwantedMatches`（`:409`）：按 `CFP` 剔除次优候选
- `checkTargetOverload`（`:1138`）

### 5.5 初始化限制

- `checkAllowedInitializer`（`:744`）+ `isEmptyConstructor`（`:598`）/`isEmptyDestructor`：CUDA 只允许 empty ctor 初始化全局变量与 `__shared__` 变量

### 5.6 Kernel launch

- `ActOnExecConfigExpr`（`:53`）：根据当前上下文构造
  - 主机侧 → `cudaConfigureCall`
  - 设备侧（动态并行）→ `cudaGetParameterBuffer` + `cudaLaunchDevice`
- 名字由 `getConfigureFuncName`（`:1204`）/ `getGetParameterBufferFuncName` / `getLaunchDeviceFuncName` 提供

### 5.7 其他

`PushForceHostDevice`（`:40`）/ `PopForceHostDevice`（`:45`）配合 `ForceHostDeviceDepth` 支持 `#pragma clang force_cuda_host_device`；`CheckLambdaCapture`（`:1085`）；`RecordImplicitHostDeviceFuncUsedByDevice`（`:816`）；`recordPotentialODRUsedVariable`（`:1231`）。

---

## 6. CodeGen

### 6.1 抽象层

`CGCUDARuntime`（`clang/lib/CodeGen/CGCUDARuntime.h:43-121`）：

- `EmitCUDAKernelCallExpr` / `EmitCUDADeviceKernelCallExpr`
- `emitDeviceStub` — 生成内核启动 stub
- `handleVarRegistration` — 设备变量注册
- `finalizeModule` — 返回模块构造函数
- `getDeviceSideName`、`getKernelHandle` / `getKernelStub`、`internalizeDeviceSideVar`
- `DeviceVarFlags`（`CGCUDARuntime.h:49-81`）：Variable / Surface / Texture，Extern / Constant / Managed / Normalized

唯一实现 `CreateNVCUDARuntime`，由 `CodeGenModule::createCUDARuntime` 创建（`CodeGenModule.cpp:732`）。

### 6.2 实现 `CGNVCUDARuntime`（`clang/lib/CodeGen/CGCUDANV.cpp:43`）

| 工作 | 位置 |
|---|---|
| 主机侧 kernel stub：CUDA 9.0+ 参数打包 + `cudaLaunchKernel`；旧版 `cudaSetupArgument` + `cudaLaunch` | `emitDeviceStub:331` → `emitDeviceStubBodyNew:420` / `emitDeviceStubBodyLegacy:547`；`prepareKernelArgs:399`、`prepareKernelArgsLLVMOffload:353` |
| 模块构造函数：`__cudaRegisterFatBinary` → `__cudaRegisterFunction` / `__cudaRegisterVar` →（10.1+）`__cudaRegisterFatBinaryEnd` →（RDC）`__cudaRegisterLinkedBinary<ID>` | `makeModuleCtorFunction:843`；650、687、1054、1079 |
| fatbin 段名：Linux `.nv_fatbin`，macOS `__NV_CUDA,__nv_fatbin` | `:943` |
| 模块析构：`__cudaUnregisterFatBinary` | `makeModuleDtorFunction:1128` |
| 收尾：device 侧给 ODR-used 设备变量加 `compiler.used`；host 侧按 RDC / OffloadViaLLVM 走 `createOffloadingEntries()` 或 module ctor | `finalizeModule:1466` |
| 设备变量注册、managed 变量变换、影子变量 linkage 处理 | `handleVarRegistration:1206`、`transformManagedVars`、`internalizeDeviceSideVar:1181` |
| kernel handle ↔ stub 映射（CUDA 同名，HIP 不同） | `getDeviceSideName:298`、`getKernelHandle:1502` |

### 6.3 CodeGenModule 集成（`clang/lib/CodeGen/CodeGenModule.cpp`）

- `LangOpts.CUDA` 时创建 runtime（`589-590`）
- `Release` 中把 module ctor 加入全局构造函数列表（`1193-1195`）
- **设备侧只发射** `__device__` / `__constant__` / `__shared__` / surface / texture 变量与 `__global__` 函数：`shouldEmitCUDAGlobalVar:4673`、`4709-4732`
- kernel 符号取 handle（`5804-5806`）
- `-fgpu-rdc` 下设备函数名 externalize（`2636`，`mayExternalize`）

### 6.4 平行实现（CIR）

`clang/lib/CIR/CodeGen/CIRGenCUDANV.cpp` + `CIRGenCUDARuntime.{h,cpp}`：CIR 管线的一套等价实现。

---

## 7. 头文件 / SDK 兼容层（`clang/lib/Headers/`）

CUDA 官方头是按 NVCC 双通编译流程写的，Clang 无法直接 include，因此有一整套包装：

| 头文件 | 作用 |
|---|---|
| `__clang_cuda_runtime_wrapper.h` | 被 driver 强制 `-include`；用宏技巧把 CUDA 头"掰成" Clang 可用形态（控制 `__CUDACC__` 定义时机、`__THROW`、`#pragma push_macro` / `pop_macro`、剔除 NVCC-only 分支） |
| `__clang_cuda_math_forward_declares.h`、`__clang_cuda_cmath.h`、`cuda_wrappers/cmath` | 把数学函数重新声明为 `constexpr` 且 host-device，使设备端可常量求值 |
| `cuda_wrappers/{algorithm, complex, new, __utility/, bits/}` | 包装 libstdc++ 头，为 STL 加上 `__host__ __device__` |
| `__clang_cuda_builtin_vars.h` | `threadIdx` / `blockIdx` / `blockDim` / `gridDim` / `warpSize` 等（用 `__declspec(property)` 实现，这也是 `Options.td:3684` 为 CUDA 开启 `__declspec` 的原因） |
| `__clang_cuda_device_functions.h` | 设备端 `malloc` / `free` / `printf` / `assert` / `synchronize` 等 |
| `__clang_cuda_intrinsics.h`、`__clang_cuda_texture_intrinsics.h` | warp、位操作、原子、纹理/表面 intrinsic |
| `__clang_cuda_libdevice_declares.h` | libdevice bitcode 中的函数声明，配合 driver 注入的 `-mlink-builtin-bitcode` |

---

## 8. 一句话总结

Clang 的 CUDA 支持 =

1. **Driver 侧的双编译编排**：SDK 探测 + ptxas / fatbinary / nvlink + offload action 图
2. **Frontend 侧的 `CUDAIsDevice` 双模编译**：CUDA 地址空间、`__CUDA_ARCH__`、aux triple 头文件搜索
3. **Parser / Sema 侧的语言扩展**：`<<<>>>` 语法、H/D/G 属性，以及 host/device 调用检查（含延迟诊断）
4. **CodeGen 侧**：kernel stub、fatbin 注册、设备变量注册
5. **一整套把 CUDA SDK 头改造成 Clang 可用的 wrapper 头**

---

## 附：相关测试目录

- `clang/test/Driver/cuda-*.cu` — 驱动与流水线
- `clang/test/SemaCUDA/` — 语义分析与诊断
- `clang/test/CodeGenCUDA/`、`clang/test/CodeGenCUDASPIRV/` — 代码生成
- `clang/test/Parser/cuda-*.cu`、`clang/test/Preprocessor/cuda-*.cu`、`clang/test/Headers/cuda_*.cu`
- `clang/test/CIR/CodeGenCUDA/`、`clang/test/Interpreter/CUDA/`
