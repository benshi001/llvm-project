/*===---- __clang_shc_runtime_wrapper.h - SHC runtime support ---------------===
 *
 * Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
 * See https://llvm.org/LICENSE.txt for license information.
 * SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
 *
 *===-----------------------------------------------------------------------===
 */

/*
 * WARNING: This header is intended to be directly -include'd by
 * the compiler and is not supposed to be included by users.
 *
 */

#ifndef __CLANG_SHC_RUNTIME_WRAPPER_H__
#define __CLANG_SHC_RUNTIME_WRAPPER_H__

#if __SHC__

#define __host__ __attribute__((host))
#define __device__ __attribute__((device))
#define __global__ __attribute__((global))
#define __shared__ __attribute__((shared))
#define __constant__ __attribute__((constant))
#define __managed__ __attribute__((managed))

// SHC has no vendor runtime header yet, so the launch configuration type and
// the kernel launch API are declared here instead of being pulled in from
// a device runtime.
typedef __SIZE_TYPE__ __shc_size_t;

// CodeGen reads the type of the second parameter of shc_launch_kernel and
// uses it as the type of the grid/block dimensions, so this must stay the
// second parameter of the launch API below.
typedef struct dim3 {
  unsigned int x, y, z;
#if defined(__cplusplus)
  dim3(unsigned int x = 1, unsigned int y = 1, unsigned int z = 1)
      : x(x), y(y), z(z) {}
#endif
} dim3;

#ifdef __cplusplus
extern "C" {
#endif

// int shc_launch_kernel(const void *func, dim3 gridDim, dim3 blockDim,
//                       void **args, size_t sharedMem, void *stream);
//
// This is the symbol called by the kernel stubs clang generates for SHC
// (see clang/lib/CodeGen/CGCUDANV.cpp). It must be declared in every
// translation unit that launches a kernel, otherwise CodeGen fails with
// "Can't find declaration for shc_launch_kernel".
int shc_launch_kernel(const void *func, dim3 gridDim, dim3 blockDim,
                      void **args, __shc_size_t sharedMem, void *stream);

#ifdef __cplusplus
} // extern "C"
#endif

#define __CLANG_SHC_RUNTIME_WRAPPER_INCLUDED__ 1

#endif // __SHC__
#endif // __CLANG_SHC_RUNTIME_WRAPPER_H__
