; NOTE: Assertions have been autogenerated by utils/update_test_checks.py UTC_ARGS: --version 5
; RUN: opt -passes=loop-vectorize -force-vector-interleave=1 -force-vector-width=4 -S < %s | FileCheck %s --check-prefix=CHECK

define i64 @select_icmp_nuw_nsw(ptr %a, ptr %b, i64 %ii, i64 %n) {
; CHECK-LABEL: define i64 @select_icmp_nuw_nsw(
; CHECK-SAME: ptr [[A:%.*]], ptr [[B:%.*]], i64 [[II:%.*]], i64 [[N:%.*]]) {
; CHECK-NEXT:  [[ENTRY:.*]]:
; CHECK-NEXT:    [[MIN_ITERS_CHECK:%.*]] = icmp ult i64 [[N]], 4
; CHECK-NEXT:    br i1 [[MIN_ITERS_CHECK]], label %[[SCALAR_PH:.*]], label %[[VECTOR_PH:.*]]
; CHECK:       [[VECTOR_PH]]:
; CHECK-NEXT:    [[N_MOD_VF:%.*]] = urem i64 [[N]], 4
; CHECK-NEXT:    [[N_VEC:%.*]] = sub i64 [[N]], [[N_MOD_VF]]
; CHECK-NEXT:    br label %[[VECTOR_BODY:.*]]
; CHECK:       [[VECTOR_BODY]]:
; CHECK-NEXT:    [[TMP9:%.*]] = phi i64 [ 0, %[[VECTOR_PH]] ], [ [[INDEX_NEXT:%.*]], %[[VECTOR_BODY]] ]
; CHECK-NEXT:    [[VEC_IND:%.*]] = phi <4 x i64> [ <i64 0, i64 1, i64 2, i64 3>, %[[VECTOR_PH]] ], [ [[VEC_IND_NEXT:%.*]], %[[VECTOR_BODY]] ]
; CHECK-NEXT:    [[VEC_PHI:%.*]] = phi <4 x i64> [ splat (i64 -9223372036854775808), %[[VECTOR_PH]] ], [ [[TMP6:%.*]], %[[VECTOR_BODY]] ]
; CHECK-NEXT:    [[TMP10:%.*]] = getelementptr inbounds i64, ptr [[A]], i64 [[TMP9]]
; CHECK-NEXT:    [[WIDE_LOAD:%.*]] = load <4 x i64>, ptr [[TMP10]], align 8
; CHECK-NEXT:    [[TMP3:%.*]] = getelementptr inbounds i64, ptr [[B]], i64 [[TMP9]]
; CHECK-NEXT:    [[WIDE_LOAD1:%.*]] = load <4 x i64>, ptr [[TMP3]], align 8
; CHECK-NEXT:    [[TMP5:%.*]] = icmp sgt <4 x i64> [[WIDE_LOAD]], [[WIDE_LOAD1]]
; CHECK-NEXT:    [[TMP6]] = select <4 x i1> [[TMP5]], <4 x i64> [[VEC_IND]], <4 x i64> [[VEC_PHI]]
; CHECK-NEXT:    [[INDEX_NEXT]] = add nuw i64 [[TMP9]], 4
; CHECK-NEXT:    [[VEC_IND_NEXT]] = add <4 x i64> [[VEC_IND]], splat (i64 4)
; CHECK-NEXT:    [[TMP7:%.*]] = icmp eq i64 [[INDEX_NEXT]], [[N_VEC]]
; CHECK-NEXT:    br i1 [[TMP7]], label %[[MIDDLE_BLOCK:.*]], label %[[VECTOR_BODY]], !llvm.loop [[LOOP0:![0-9]+]]
; CHECK:       [[MIDDLE_BLOCK]]:
; CHECK-NEXT:    [[TMP8:%.*]] = call i64 @llvm.vector.reduce.smax.v4i64(<4 x i64> [[TMP6]])
; CHECK-NEXT:    [[RDX_SELECT_CMP:%.*]] = icmp ne i64 [[TMP8]], -9223372036854775808
; CHECK-NEXT:    [[RDX_SELECT:%.*]] = select i1 [[RDX_SELECT_CMP]], i64 [[TMP8]], i64 [[II]]
; CHECK-NEXT:    [[CMP_N:%.*]] = icmp eq i64 [[N]], [[N_VEC]]
; CHECK-NEXT:    br i1 [[CMP_N]], label %[[EXIT:.*]], label %[[SCALAR_PH]]
; CHECK:       [[SCALAR_PH]]:
; CHECK-NEXT:    [[BC_RESUME_VAL:%.*]] = phi i64 [ [[N_VEC]], %[[MIDDLE_BLOCK]] ], [ 0, %[[ENTRY]] ]
; CHECK-NEXT:    [[BC_MERGE_RDX:%.*]] = phi i64 [ [[RDX_SELECT]], %[[MIDDLE_BLOCK]] ], [ [[II]], %[[ENTRY]] ]
; CHECK-NEXT:    br label %[[FOR_BODY:.*]]
; CHECK:       [[FOR_BODY]]:
; CHECK-NEXT:    [[IV:%.*]] = phi i64 [ [[INC:%.*]], %[[FOR_BODY]] ], [ [[BC_RESUME_VAL]], %[[SCALAR_PH]] ]
; CHECK-NEXT:    [[RDX:%.*]] = phi i64 [ [[COND:%.*]], %[[FOR_BODY]] ], [ [[BC_MERGE_RDX]], %[[SCALAR_PH]] ]
; CHECK-NEXT:    [[ARRAYIDX:%.*]] = getelementptr inbounds i64, ptr [[A]], i64 [[IV]]
; CHECK-NEXT:    [[TMP0:%.*]] = load i64, ptr [[ARRAYIDX]], align 8
; CHECK-NEXT:    [[ARRAYIDX1:%.*]] = getelementptr inbounds i64, ptr [[B]], i64 [[IV]]
; CHECK-NEXT:    [[TMP1:%.*]] = load i64, ptr [[ARRAYIDX1]], align 8
; CHECK-NEXT:    [[CMP2:%.*]] = icmp sgt i64 [[TMP0]], [[TMP1]]
; CHECK-NEXT:    [[COND]] = select i1 [[CMP2]], i64 [[IV]], i64 [[RDX]]
; CHECK-NEXT:    [[INC]] = add nuw nsw i64 [[IV]], 1
; CHECK-NEXT:    [[EXITCOND_NOT:%.*]] = icmp eq i64 [[INC]], [[N]]
; CHECK-NEXT:    br i1 [[EXITCOND_NOT]], label %[[EXIT]], label %[[FOR_BODY]], !llvm.loop [[LOOP3:![0-9]+]]
; CHECK:       [[EXIT]]:
; CHECK-NEXT:    [[COND_LCSSA:%.*]] = phi i64 [ [[COND]], %[[FOR_BODY]] ], [ [[RDX_SELECT]], %[[MIDDLE_BLOCK]] ]
; CHECK-NEXT:    ret i64 [[COND_LCSSA]]
;
entry:
  br label %for.body

for.body:                                         ; preds = %entry, %for.body
  %iv = phi i64 [ %inc, %for.body ], [ 0, %entry ]
  %rdx = phi i64 [ %cond, %for.body ], [ %ii, %entry ]
  %arrayidx = getelementptr inbounds i64, ptr %a, i64 %iv
  %0 = load i64, ptr %arrayidx, align 8
  %arrayidx1 = getelementptr inbounds i64, ptr %b, i64 %iv
  %1 = load i64, ptr %arrayidx1, align 8
  %cmp2 = icmp sgt i64 %0, %1
  %cond = select i1 %cmp2, i64 %iv, i64 %rdx
  %inc = add nuw nsw i64 %iv, 1
  %exitcond.not = icmp eq i64 %inc, %n
  br i1 %exitcond.not, label %exit, label %for.body

exit:                                             ; preds = %for.body
  ret i64 %cond
}

define i64 @select_icmp_nsw(ptr %a, ptr %b, i64 %ii, i64 %n) {
; CHECK-LABEL: define i64 @select_icmp_nsw(
; CHECK-SAME: ptr [[A:%.*]], ptr [[B:%.*]], i64 [[II:%.*]], i64 [[N:%.*]]) {
; CHECK-NEXT:  [[ENTRY:.*]]:
; CHECK-NEXT:    [[MIN_ITERS_CHECK:%.*]] = icmp ult i64 [[N]], 4
; CHECK-NEXT:    br i1 [[MIN_ITERS_CHECK]], label %[[SCALAR_PH:.*]], label %[[VECTOR_PH:.*]]
; CHECK:       [[VECTOR_PH]]:
; CHECK-NEXT:    [[N_MOD_VF:%.*]] = urem i64 [[N]], 4
; CHECK-NEXT:    [[N_VEC:%.*]] = sub i64 [[N]], [[N_MOD_VF]]
; CHECK-NEXT:    br label %[[VECTOR_BODY:.*]]
; CHECK:       [[VECTOR_BODY]]:
; CHECK-NEXT:    [[TMP9:%.*]] = phi i64 [ 0, %[[VECTOR_PH]] ], [ [[INDEX_NEXT:%.*]], %[[VECTOR_BODY]] ]
; CHECK-NEXT:    [[VEC_IND:%.*]] = phi <4 x i64> [ <i64 0, i64 1, i64 2, i64 3>, %[[VECTOR_PH]] ], [ [[VEC_IND_NEXT:%.*]], %[[VECTOR_BODY]] ]
; CHECK-NEXT:    [[VEC_PHI:%.*]] = phi <4 x i64> [ splat (i64 -9223372036854775808), %[[VECTOR_PH]] ], [ [[TMP6:%.*]], %[[VECTOR_BODY]] ]
; CHECK-NEXT:    [[TMP10:%.*]] = getelementptr inbounds i64, ptr [[A]], i64 [[TMP9]]
; CHECK-NEXT:    [[WIDE_LOAD:%.*]] = load <4 x i64>, ptr [[TMP10]], align 8
; CHECK-NEXT:    [[TMP3:%.*]] = getelementptr inbounds i64, ptr [[B]], i64 [[TMP9]]
; CHECK-NEXT:    [[WIDE_LOAD1:%.*]] = load <4 x i64>, ptr [[TMP3]], align 8
; CHECK-NEXT:    [[TMP5:%.*]] = icmp sgt <4 x i64> [[WIDE_LOAD]], [[WIDE_LOAD1]]
; CHECK-NEXT:    [[TMP6]] = select <4 x i1> [[TMP5]], <4 x i64> [[VEC_IND]], <4 x i64> [[VEC_PHI]]
; CHECK-NEXT:    [[INDEX_NEXT]] = add nuw i64 [[TMP9]], 4
; CHECK-NEXT:    [[VEC_IND_NEXT]] = add <4 x i64> [[VEC_IND]], splat (i64 4)
; CHECK-NEXT:    [[TMP7:%.*]] = icmp eq i64 [[INDEX_NEXT]], [[N_VEC]]
; CHECK-NEXT:    br i1 [[TMP7]], label %[[MIDDLE_BLOCK:.*]], label %[[VECTOR_BODY]], !llvm.loop [[LOOP4:![0-9]+]]
; CHECK:       [[MIDDLE_BLOCK]]:
; CHECK-NEXT:    [[TMP8:%.*]] = call i64 @llvm.vector.reduce.smax.v4i64(<4 x i64> [[TMP6]])
; CHECK-NEXT:    [[RDX_SELECT_CMP:%.*]] = icmp ne i64 [[TMP8]], -9223372036854775808
; CHECK-NEXT:    [[RDX_SELECT:%.*]] = select i1 [[RDX_SELECT_CMP]], i64 [[TMP8]], i64 [[II]]
; CHECK-NEXT:    [[CMP_N:%.*]] = icmp eq i64 [[N]], [[N_VEC]]
; CHECK-NEXT:    br i1 [[CMP_N]], label %[[EXIT:.*]], label %[[SCALAR_PH]]
; CHECK:       [[SCALAR_PH]]:
; CHECK-NEXT:    [[BC_RESUME_VAL:%.*]] = phi i64 [ [[N_VEC]], %[[MIDDLE_BLOCK]] ], [ 0, %[[ENTRY]] ]
; CHECK-NEXT:    [[BC_MERGE_RDX:%.*]] = phi i64 [ [[RDX_SELECT]], %[[MIDDLE_BLOCK]] ], [ [[II]], %[[ENTRY]] ]
; CHECK-NEXT:    br label %[[FOR_BODY:.*]]
; CHECK:       [[FOR_BODY]]:
; CHECK-NEXT:    [[IV:%.*]] = phi i64 [ [[INC:%.*]], %[[FOR_BODY]] ], [ [[BC_RESUME_VAL]], %[[SCALAR_PH]] ]
; CHECK-NEXT:    [[RDX:%.*]] = phi i64 [ [[COND:%.*]], %[[FOR_BODY]] ], [ [[BC_MERGE_RDX]], %[[SCALAR_PH]] ]
; CHECK-NEXT:    [[ARRAYIDX:%.*]] = getelementptr inbounds i64, ptr [[A]], i64 [[IV]]
; CHECK-NEXT:    [[TMP0:%.*]] = load i64, ptr [[ARRAYIDX]], align 8
; CHECK-NEXT:    [[ARRAYIDX1:%.*]] = getelementptr inbounds i64, ptr [[B]], i64 [[IV]]
; CHECK-NEXT:    [[TMP1:%.*]] = load i64, ptr [[ARRAYIDX1]], align 8
; CHECK-NEXT:    [[CMP2:%.*]] = icmp sgt i64 [[TMP0]], [[TMP1]]
; CHECK-NEXT:    [[COND]] = select i1 [[CMP2]], i64 [[IV]], i64 [[RDX]]
; CHECK-NEXT:    [[INC]] = add nsw i64 [[IV]], 1
; CHECK-NEXT:    [[EXITCOND_NOT:%.*]] = icmp eq i64 [[INC]], [[N]]
; CHECK-NEXT:    br i1 [[EXITCOND_NOT]], label %[[EXIT]], label %[[FOR_BODY]], !llvm.loop [[LOOP5:![0-9]+]]
; CHECK:       [[EXIT]]:
; CHECK-NEXT:    [[COND_LCSSA:%.*]] = phi i64 [ [[COND]], %[[FOR_BODY]] ], [ [[RDX_SELECT]], %[[MIDDLE_BLOCK]] ]
; CHECK-NEXT:    ret i64 [[COND_LCSSA]]
;
entry:
  br label %for.body

for.body:                                         ; preds = %entry, %for.body
  %iv = phi i64 [ %inc, %for.body ], [ 0, %entry ]
  %rdx = phi i64 [ %cond, %for.body ], [ %ii, %entry ]
  %arrayidx = getelementptr inbounds i64, ptr %a, i64 %iv
  %0 = load i64, ptr %arrayidx, align 8
  %arrayidx1 = getelementptr inbounds i64, ptr %b, i64 %iv
  %1 = load i64, ptr %arrayidx1, align 8
  %cmp2 = icmp sgt i64 %0, %1
  %cond = select i1 %cmp2, i64 %iv, i64 %rdx
  %inc = add nsw i64 %iv, 1
  %exitcond.not = icmp eq i64 %inc, %n
  br i1 %exitcond.not, label %exit, label %for.body

exit:                                             ; preds = %for.body
  ret i64 %cond
}

define i64 @select_icmp_nuw(ptr %a, ptr %b, i64 %ii, i64 %n) {
; CHECK-LABEL: define i64 @select_icmp_nuw(
; CHECK-SAME: ptr [[A:%.*]], ptr [[B:%.*]], i64 [[II:%.*]], i64 [[N:%.*]]) {
; CHECK-NEXT:  [[ENTRY:.*]]:
; CHECK-NEXT:    br label %[[FOR_BODY:.*]]
; CHECK:       [[FOR_BODY]]:
; CHECK-NEXT:    [[IV:%.*]] = phi i64 [ [[INC:%.*]], %[[FOR_BODY]] ], [ 0, %[[ENTRY]] ]
; CHECK-NEXT:    [[RDX:%.*]] = phi i64 [ [[COND:%.*]], %[[FOR_BODY]] ], [ [[II]], %[[ENTRY]] ]
; CHECK-NEXT:    [[ARRAYIDX:%.*]] = getelementptr inbounds i64, ptr [[A]], i64 [[IV]]
; CHECK-NEXT:    [[TMP0:%.*]] = load i64, ptr [[ARRAYIDX]], align 8
; CHECK-NEXT:    [[ARRAYIDX1:%.*]] = getelementptr inbounds i64, ptr [[B]], i64 [[IV]]
; CHECK-NEXT:    [[TMP1:%.*]] = load i64, ptr [[ARRAYIDX1]], align 8
; CHECK-NEXT:    [[CMP2:%.*]] = icmp sgt i64 [[TMP0]], [[TMP1]]
; CHECK-NEXT:    [[COND]] = select i1 [[CMP2]], i64 [[IV]], i64 [[RDX]]
; CHECK-NEXT:    [[INC]] = add nuw i64 [[IV]], 1
; CHECK-NEXT:    [[EXITCOND_NOT:%.*]] = icmp eq i64 [[INC]], [[N]]
; CHECK-NEXT:    br i1 [[EXITCOND_NOT]], label %[[EXIT:.*]], label %[[FOR_BODY]]
; CHECK:       [[EXIT]]:
; CHECK-NEXT:    [[COND_LCSSA:%.*]] = phi i64 [ [[COND]], %[[FOR_BODY]] ]
; CHECK-NEXT:    ret i64 [[COND_LCSSA]]
;
entry:
  br label %for.body

for.body:                                         ; preds = %entry, %for.body
  %iv = phi i64 [ %inc, %for.body ], [ 0, %entry ]
  %rdx = phi i64 [ %cond, %for.body ], [ %ii, %entry ]
  %arrayidx = getelementptr inbounds i64, ptr %a, i64 %iv
  %0 = load i64, ptr %arrayidx, align 8
  %arrayidx1 = getelementptr inbounds i64, ptr %b, i64 %iv
  %1 = load i64, ptr %arrayidx1, align 8
  %cmp2 = icmp sgt i64 %0, %1
  %cond = select i1 %cmp2, i64 %iv, i64 %rdx
  %inc = add nuw i64 %iv, 1
  %exitcond.not = icmp eq i64 %inc, %n
  br i1 %exitcond.not, label %exit, label %for.body

exit:                                             ; preds = %for.body
  ret i64 %cond
}

define i64 @select_icmp_noflag(ptr %a, ptr %b, i64 %ii, i64 %n) {
; CHECK-LABEL: define i64 @select_icmp_noflag(
; CHECK-SAME: ptr [[A:%.*]], ptr [[B:%.*]], i64 [[II:%.*]], i64 [[N:%.*]]) {
; CHECK-NEXT:  [[ENTRY:.*]]:
; CHECK-NEXT:    br label %[[FOR_BODY:.*]]
; CHECK:       [[FOR_BODY]]:
; CHECK-NEXT:    [[IV:%.*]] = phi i64 [ [[INC:%.*]], %[[FOR_BODY]] ], [ 0, %[[ENTRY]] ]
; CHECK-NEXT:    [[RDX:%.*]] = phi i64 [ [[COND:%.*]], %[[FOR_BODY]] ], [ [[II]], %[[ENTRY]] ]
; CHECK-NEXT:    [[ARRAYIDX:%.*]] = getelementptr inbounds i64, ptr [[A]], i64 [[IV]]
; CHECK-NEXT:    [[TMP0:%.*]] = load i64, ptr [[ARRAYIDX]], align 8
; CHECK-NEXT:    [[ARRAYIDX1:%.*]] = getelementptr inbounds i64, ptr [[B]], i64 [[IV]]
; CHECK-NEXT:    [[TMP1:%.*]] = load i64, ptr [[ARRAYIDX1]], align 8
; CHECK-NEXT:    [[CMP2:%.*]] = icmp sgt i64 [[TMP0]], [[TMP1]]
; CHECK-NEXT:    [[COND]] = select i1 [[CMP2]], i64 [[IV]], i64 [[RDX]]
; CHECK-NEXT:    [[INC]] = add i64 [[IV]], 1
; CHECK-NEXT:    [[EXITCOND_NOT:%.*]] = icmp eq i64 [[INC]], [[N]]
; CHECK-NEXT:    br i1 [[EXITCOND_NOT]], label %[[EXIT:.*]], label %[[FOR_BODY]]
; CHECK:       [[EXIT]]:
; CHECK-NEXT:    [[COND_LCSSA:%.*]] = phi i64 [ [[COND]], %[[FOR_BODY]] ]
; CHECK-NEXT:    ret i64 [[COND_LCSSA]]
;
entry:
  br label %for.body

for.body:                                         ; preds = %entry, %for.body
  %iv = phi i64 [ %inc, %for.body ], [ 0, %entry ]
  %rdx = phi i64 [ %cond, %for.body ], [ %ii, %entry ]
  %arrayidx = getelementptr inbounds i64, ptr %a, i64 %iv
  %0 = load i64, ptr %arrayidx, align 8
  %arrayidx1 = getelementptr inbounds i64, ptr %b, i64 %iv
  %1 = load i64, ptr %arrayidx1, align 8
  %cmp2 = icmp sgt i64 %0, %1
  %cond = select i1 %cmp2, i64 %iv, i64 %rdx
  %inc = add i64 %iv, 1
  %exitcond.not = icmp eq i64 %inc, %n
  br i1 %exitcond.not, label %exit, label %for.body

exit:                                             ; preds = %for.body
  ret i64 %cond
}
;.
; CHECK: [[LOOP0]] = distinct !{[[LOOP0]], [[META1:![0-9]+]], [[META2:![0-9]+]]}
; CHECK: [[META1]] = !{!"llvm.loop.isvectorized", i32 1}
; CHECK: [[META2]] = !{!"llvm.loop.unroll.runtime.disable"}
; CHECK: [[LOOP3]] = distinct !{[[LOOP3]], [[META2]], [[META1]]}
; CHECK: [[LOOP4]] = distinct !{[[LOOP4]], [[META1]], [[META2]]}
; CHECK: [[LOOP5]] = distinct !{[[LOOP5]], [[META2]], [[META1]]}
;.
