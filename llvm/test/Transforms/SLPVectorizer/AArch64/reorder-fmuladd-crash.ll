; NOTE: Assertions have been autogenerated by utils/update_test_checks.py
; RUN: opt < %s -passes=slp-vectorizer -S -mtriple=aarch64-w32-windows-gnu | FileCheck %s

define i32 @foo(i32 %v1, double %v2, i1 %arg, i32 %arg2) {
; CHECK-LABEL: @foo(
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[TMP0:%.*]] = insertelement <2 x i32> <i32 poison, i32 undef>, i32 [[V1:%.*]], i32 0
; CHECK-NEXT:    [[TMP1:%.*]] = sitofp <2 x i32> [[TMP0]] to <2 x double>
; CHECK-NEXT:    [[TMP2:%.*]] = shufflevector <2 x double> [[TMP1]], <2 x double> poison, <4 x i32> <i32 0, i32 0, i32 1, i32 1>
; CHECK-NEXT:    br label [[FOR_COND15_PREHEADER:%.*]]
; CHECK:       for.cond15.preheader:
; CHECK-NEXT:    br label [[IF_END:%.*]]
; CHECK:       for.cond15:
; CHECK-NEXT:    br label [[IF_END_1:%.*]]
; CHECK:       if.end:
; CHECK-NEXT:    br label [[FOR_COND15:%.*]]
; CHECK:       for.end39:
; CHECK-NEXT:    switch i32 [[ARG2:%.*]], label [[DO_BODY:%.*]] [
; CHECK-NEXT:      i32 0, label [[SW_BB:%.*]]
; CHECK-NEXT:      i32 1, label [[SW_BB195:%.*]]
; CHECK-NEXT:    ]
; CHECK:       sw.bb:
; CHECK-NEXT:    [[ARRAYIDX43:%.*]] = getelementptr inbounds [4 x [2 x double]], ptr undef, i32 0, i64 1, i64 0
; CHECK-NEXT:    [[TMP3:%.*]] = insertelement <2 x double> <double poison, double undef>, double [[V2:%.*]], i32 0
; CHECK-NEXT:    [[TMP4:%.*]] = fmul <2 x double> [[TMP3]], [[TMP1]]
; CHECK-NEXT:    [[TMP5:%.*]] = shufflevector <2 x double> [[TMP4]], <2 x double> poison, <4 x i32> <i32 0, i32 0, i32 1, i32 1>
; CHECK-NEXT:    [[TMP6:%.*]] = load <4 x double>, ptr [[ARRAYIDX43]], align 8
; CHECK-NEXT:    [[TMP7:%.*]] = fmul <4 x double> [[TMP6]], [[TMP5]]
; CHECK-NEXT:    [[TMP9:%.*]] = call <4 x double> @llvm.fmuladd.v4f64(<4 x double> undef, <4 x double> [[TMP2]], <4 x double> [[TMP7]])
; CHECK-NEXT:    br label [[SW_EPILOG:%.*]]
; CHECK:       sw.bb195:
; CHECK-NEXT:    br label [[SW_EPILOG]]
; CHECK:       do.body:
; CHECK-NEXT:    unreachable
; CHECK:       sw.epilog:
; CHECK-NEXT:    [[TMP10:%.*]] = phi <4 x double> [ undef, [[SW_BB195]] ], [ [[TMP9]], [[SW_BB]] ]
; CHECK-NEXT:    ret i32 undef
; CHECK:       if.end.1:
; CHECK-NEXT:    br label [[FOR_COND15_1:%.*]]
; CHECK:       for.cond15.1:
; CHECK-NEXT:    br i1 [[ARG:%.*]], label [[FOR_END39:%.*]], label [[FOR_COND15_PREHEADER]]
;
entry:
  %conv = sitofp i32 undef to double
  %conv2 = sitofp i32 %v1 to double
  br label %for.cond15.preheader

for.cond15.preheader:                             ; preds = %for.cond15.1, %entry
  br label %if.end

for.cond15:                                       ; preds = %if.end
  br label %if.end.1

if.end:                                           ; preds = %for.cond15.preheader
  br label %for.cond15

for.end39:                                        ; preds = %for.cond15.1
  switch i32 %arg2, label %do.body [
  i32 0, label %sw.bb
  i32 1, label %sw.bb195
  ]

sw.bb:                                            ; preds = %for.end39
  %arrayidx43 = getelementptr inbounds [4 x [2 x double]], ptr undef, i32 0, i64 1, i64 0
  %0 = load double, ptr %arrayidx43, align 8
  %arrayidx45 = getelementptr inbounds [4 x [2 x double]], ptr undef, i32 0, i64 2, i64 0
  %1 = load double, ptr %arrayidx45, align 8
  %arrayidx51 = getelementptr inbounds [4 x [2 x double]], ptr undef, i32 0, i64 2, i64 1
  %2 = load double, ptr %arrayidx51, align 8
  %arrayidx58 = getelementptr inbounds [4 x [2 x double]], ptr undef, i32 0, i64 1, i64 1
  %3 = load double, ptr %arrayidx58, align 8
  %mul = fmul double %v2, %conv2
  %mul109 = fmul double undef, %conv
  %mul143 = fmul double %0, %mul
  %4 = call double @llvm.fmuladd.f64(double undef, double %conv2, double %mul143)
  %mul154 = fmul double %1, %mul109
  %5 = call double @llvm.fmuladd.f64(double undef, double %conv, double %mul154)
  %mul172 = fmul double %3, %mul
  %6 = call double @llvm.fmuladd.f64(double undef, double %conv2, double %mul172)
  %mul183 = fmul double %2, %mul109
  %7 = call double @llvm.fmuladd.f64(double undef, double %conv, double %mul183)
  br label %sw.epilog

sw.bb195:                                         ; preds = %for.end39
  br label %sw.epilog

do.body:                                          ; preds = %for.end39
  unreachable

sw.epilog:                                        ; preds = %sw.bb195, %sw.bb
  %x4.0 = phi double [ undef, %sw.bb195 ], [ %7, %sw.bb ]
  %x3.0 = phi double [ undef, %sw.bb195 ], [ %6, %sw.bb ]
  %x1.0 = phi double [ undef, %sw.bb195 ], [ %5, %sw.bb ]
  %x0.0 = phi double [ undef, %sw.bb195 ], [ %4, %sw.bb ]
  ret i32 undef

if.end.1:                                         ; preds = %for.cond15
  br label %for.cond15.1

for.cond15.1:                                     ; preds = %if.end.1
  br i1 %arg, label %for.end39, label %for.cond15.preheader
}

declare double @llvm.fmuladd.f64(double, double, double)
