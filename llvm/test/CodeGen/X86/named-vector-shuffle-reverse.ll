; NOTE: Assertions have been autogenerated by utils/update_llc_test_checks.py
; RUN: llc -verify-machineinstrs  < %s | FileCheck %s

target triple = "x86_64-unknown-unknown"

;
; VECTOR_REVERSE
;

define <16 x i8> @reverse_v16i8(<16 x i8> %a) #0 {
; CHECK-LABEL: reverse_v16i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    pxor %xmm1, %xmm1
; CHECK-NEXT:    movdqa %xmm0, %xmm2
; CHECK-NEXT:    punpcklbw {{.*#+}} xmm2 = xmm2[0],xmm1[0],xmm2[1],xmm1[1],xmm2[2],xmm1[2],xmm2[3],xmm1[3],xmm2[4],xmm1[4],xmm2[5],xmm1[5],xmm2[6],xmm1[6],xmm2[7],xmm1[7]
; CHECK-NEXT:    pshufd {{.*#+}} xmm2 = xmm2[2,3,0,1]
; CHECK-NEXT:    pshuflw {{.*#+}} xmm2 = xmm2[3,2,1,0,4,5,6,7]
; CHECK-NEXT:    pshufhw {{.*#+}} xmm2 = xmm2[0,1,2,3,7,6,5,4]
; CHECK-NEXT:    punpckhbw {{.*#+}} xmm0 = xmm0[8],xmm1[8],xmm0[9],xmm1[9],xmm0[10],xmm1[10],xmm0[11],xmm1[11],xmm0[12],xmm1[12],xmm0[13],xmm1[13],xmm0[14],xmm1[14],xmm0[15],xmm1[15]
; CHECK-NEXT:    pshufd {{.*#+}} xmm0 = xmm0[2,3,0,1]
; CHECK-NEXT:    pshuflw {{.*#+}} xmm0 = xmm0[3,2,1,0,4,5,6,7]
; CHECK-NEXT:    pshufhw {{.*#+}} xmm0 = xmm0[0,1,2,3,7,6,5,4]
; CHECK-NEXT:    packuswb %xmm2, %xmm0
; CHECK-NEXT:    retq

  %res = call <16 x i8> @llvm.vector.reverse.v16i8(<16 x i8> %a)
  ret <16 x i8> %res
}

define <8 x i16> @reverse_v8i16(<8 x i16> %a) #0 {
; CHECK-LABEL: reverse_v8i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    pshufd {{.*#+}} xmm0 = xmm0[2,3,0,1]
; CHECK-NEXT:    pshuflw {{.*#+}} xmm0 = xmm0[3,2,1,0,4,5,6,7]
; CHECK-NEXT:    pshufhw {{.*#+}} xmm0 = xmm0[0,1,2,3,7,6,5,4]
; CHECK-NEXT:    retq
  %res = call <8 x i16> @llvm.vector.reverse.v8i16(<8 x i16> %a)
  ret <8 x i16> %res
}

define <4 x i32> @reverse_v4i32(<4 x i32> %a) #0 {
; CHECK-LABEL: reverse_v4i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    pshufd {{.*#+}} xmm0 = xmm0[3,2,1,0]
; CHECK-NEXT:    retq
  %res = call <4 x i32> @llvm.vector.reverse.v4i32(<4 x i32> %a)
  ret <4 x i32> %res
}

define <2 x i64> @reverse_v2i64(<2 x i64> %a) #0 {
; CHECK-LABEL: reverse_v2i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    pshufd {{.*#+}} xmm0 = xmm0[2,3,0,1]
; CHECK-NEXT:    retq
  %res = call <2 x i64> @llvm.vector.reverse.v2i64(<2 x i64> %a)
  ret <2 x i64> %res
}

define <4 x float> @reverse_v4f32(<4 x float> %a) #0 {
; CHECK-LABEL: reverse_v4f32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    shufps {{.*#+}} xmm0 = xmm0[3,2,1,0]
; CHECK-NEXT:    retq
  %res = call <4 x float> @llvm.vector.reverse.v4f32(<4 x float> %a)
  ret <4 x float> %res
}

define <2 x double> @reverse_v2f64(<2 x double> %a) #0 {
; CHECK-LABEL: reverse_v2f64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    shufps {{.*#+}} xmm0 = xmm0[2,3,0,1]
; CHECK-NEXT:    retq
  %res = call <2 x double> @llvm.vector.reverse.v2f64(<2 x double> %a)
  ret <2 x double> %res
}

; Verify promote type legalisation works as expected.
define <2 x i8> @reverse_v2i8(<2 x i8> %a) #0 {
; CHECK-LABEL: reverse_v2i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    movdqa %xmm0, %xmm1
; CHECK-NEXT:    psrlw $8, %xmm1
; CHECK-NEXT:    psllw $8, %xmm0
; CHECK-NEXT:    por %xmm1, %xmm0
; CHECK-NEXT:    retq
  %res = call <2 x i8> @llvm.vector.reverse.v2i8(<2 x i8> %a)
  ret <2 x i8> %res
}

; Verify splitvec type legalisation works as expected.
define <8 x i32> @reverse_v8i32(<8 x i32> %a) #0 {
; CHECK-LABEL: reverse_v8i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    pshufd {{.*#+}} xmm2 = xmm1[3,2,1,0]
; CHECK-NEXT:    pshufd {{.*#+}} xmm1 = xmm0[3,2,1,0]
; CHECK-NEXT:    movdqa %xmm2, %xmm0
; CHECK-NEXT:    retq
  %res = call <8 x i32> @llvm.vector.reverse.v8i32(<8 x i32> %a)
  ret <8 x i32> %res
}

; Verify splitvec type legalisation works as expected.
define <16 x float> @reverse_v16f32(<16 x float> %a) #0 {
; CHECK-LABEL: reverse_v16f32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    movaps %xmm1, %xmm4
; CHECK-NEXT:    movaps %xmm0, %xmm5
; CHECK-NEXT:    shufps {{.*#+}} xmm3 = xmm3[3,2,1,0]
; CHECK-NEXT:    shufps {{.*#+}} xmm2 = xmm2[3,2,1,0]
; CHECK-NEXT:    shufps {{.*#+}} xmm4 = xmm4[3,2],xmm1[1,0]
; CHECK-NEXT:    shufps {{.*#+}} xmm5 = xmm5[3,2],xmm0[1,0]
; CHECK-NEXT:    movaps %xmm3, %xmm0
; CHECK-NEXT:    movaps %xmm2, %xmm1
; CHECK-NEXT:    movaps %xmm4, %xmm2
; CHECK-NEXT:    movaps %xmm5, %xmm3
; CHECK-NEXT:    retq

  %res = call <16 x float> @llvm.vector.reverse.v16f32(<16 x float> %a)
  ret <16 x float> %res
}


declare <2 x i8> @llvm.vector.reverse.v2i8(<2 x i8>)
declare <16 x i8> @llvm.vector.reverse.v16i8(<16 x i8>)
declare <8 x i16> @llvm.vector.reverse.v8i16(<8 x i16>)
declare <4 x i32> @llvm.vector.reverse.v4i32(<4 x i32>)
declare <8 x i32> @llvm.vector.reverse.v8i32(<8 x i32>)
declare <2 x i64> @llvm.vector.reverse.v2i64(<2 x i64>)
declare <8 x half> @llvm.vector.reverse.v8f16(<8 x half>)
declare <4 x float> @llvm.vector.reverse.v4f32(<4 x float>)
declare <16 x float> @llvm.vector.reverse.v16f32(<16 x float>)
declare <2 x double> @llvm.vector.reverse.v2f64(<2 x double>)

attributes #0 = { nounwind }
