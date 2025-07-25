; NOTE: Assertions have been autogenerated by utils/update_llc_test_checks.py UTC_ARGS: --version 3
; RUN: llc -global-isel -mtriple=amdgcn-amd-amdpal -mcpu=gfx1010 < %s | FileCheck -check-prefix=GFX10 %s

; This file contains various tests that have divergent i1s used outside of
; the loop. These are lane masks is sgpr and need to have correct value in
; corresponding bit at the iteration lane exits the loop.
; Achieved by merging lane mask with same lane mask from previous iteration
; and using that merged lane mask outside of the loop.

; Phi used outside of the loop directly (loopfinder will figure out that it
; needs to merge lane mask across all iterations)
define void @divergent_i1_phi_used_outside_loop(float %val, float %pre.cond.val, ptr %addr) {
; GFX10-LABEL: divergent_i1_phi_used_outside_loop:
; GFX10:       ; %bb.0: ; %entry
; GFX10-NEXT:    s_waitcnt vmcnt(0) expcnt(0) lgkmcnt(0)
; GFX10-NEXT:    s_mov_b32 s4, 0
; GFX10-NEXT:    v_cmp_lt_f32_e64 s5, 1.0, v1
; GFX10-NEXT:    v_mov_b32_e32 v1, s4
; GFX10-NEXT:    ; implicit-def: $sgpr6
; GFX10-NEXT:    ; implicit-def: $sgpr7
; GFX10-NEXT:  .LBB0_1: ; %loop
; GFX10-NEXT:    ; =>This Inner Loop Header: Depth=1
; GFX10-NEXT:    v_cvt_f32_u32_e32 v4, v1
; GFX10-NEXT:    s_xor_b32 s8, s5, -1
; GFX10-NEXT:    v_add_nc_u32_e32 v1, 1, v1
; GFX10-NEXT:    v_cmp_gt_f32_e32 vcc_lo, v4, v0
; GFX10-NEXT:    s_or_b32 s4, vcc_lo, s4
; GFX10-NEXT:    s_andn2_b32 s7, s7, exec_lo
; GFX10-NEXT:    s_and_b32 s5, exec_lo, s5
; GFX10-NEXT:    s_andn2_b32 s6, s6, exec_lo
; GFX10-NEXT:    s_or_b32 s7, s7, s5
; GFX10-NEXT:    s_mov_b32 s5, s8
; GFX10-NEXT:    s_and_b32 s9, exec_lo, s7
; GFX10-NEXT:    s_or_b32 s6, s6, s9
; GFX10-NEXT:    s_andn2_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    s_cbranch_execnz .LBB0_1
; GFX10-NEXT:  ; %bb.2: ; %exit
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    v_cndmask_b32_e64 v0, 0, 1.0, s6
; GFX10-NEXT:    flat_store_dword v[2:3], v0
; GFX10-NEXT:    s_waitcnt lgkmcnt(0)
; GFX10-NEXT:    s_setpc_b64 s[30:31]
entry:
  %pre.cond = fcmp ogt float %pre.cond.val, 1.0
  br label %loop

loop:
  %counter = phi i32 [ 0, %entry ], [ %counter.plus.1, %loop ]
  %bool.counter = phi i1 [ %pre.cond, %entry ], [ %neg.bool.counter, %loop ]
  %neg.bool.counter = xor i1 %bool.counter, true
  %f.counter = uitofp i32 %counter to float
  %cond = fcmp ogt float %f.counter, %val
  %counter.plus.1 = add i32 %counter, 1
  br i1 %cond, label %exit, label %loop

exit:
  %select = select i1 %bool.counter, float 1.000000e+00, float 0.000000e+00
  store float %select, ptr %addr
  ret void
}

define void @divergent_i1_phi_used_outside_loop_larger_loop_body(float %val, ptr addrspace(1) %a, ptr %addr) {
; GFX10-LABEL: divergent_i1_phi_used_outside_loop_larger_loop_body:
; GFX10:       ; %bb.0: ; %entry
; GFX10-NEXT:    s_waitcnt vmcnt(0) expcnt(0) lgkmcnt(0)
; GFX10-NEXT:    s_mov_b32 s4, -1
; GFX10-NEXT:    ; implicit-def: $sgpr6
; GFX10-NEXT:    v_mov_b32_e32 v0, s4
; GFX10-NEXT:    s_andn2_b32 s5, s4, exec_lo
; GFX10-NEXT:    s_and_b32 s4, exec_lo, -1
; GFX10-NEXT:    s_or_b32 s4, s5, s4
; GFX10-NEXT:    s_branch .LBB1_2
; GFX10-NEXT:  .LBB1_1: ; %loop.cond
; GFX10-NEXT:    ; in Loop: Header=BB1_2 Depth=1
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    v_add_co_u32 v1, s4, v1, 4
; GFX10-NEXT:    v_add_nc_u32_e32 v0, 1, v0
; GFX10-NEXT:    v_add_co_ci_u32_e64 v2, s4, 0, v2, s4
; GFX10-NEXT:    s_andn2_b32 s7, s5, exec_lo
; GFX10-NEXT:    s_and_b32 s8, exec_lo, s6
; GFX10-NEXT:    v_cmp_le_i32_e32 vcc_lo, 10, v0
; GFX10-NEXT:    s_or_b32 s4, s7, s8
; GFX10-NEXT:    s_cbranch_vccz .LBB1_4
; GFX10-NEXT:  .LBB1_2: ; %loop.start
; GFX10-NEXT:    ; =>This Inner Loop Header: Depth=1
; GFX10-NEXT:    s_mov_b32 s5, s4
; GFX10-NEXT:    s_andn2_b32 s4, s6, exec_lo
; GFX10-NEXT:    s_and_b32 s6, exec_lo, s5
; GFX10-NEXT:    s_or_b32 s6, s4, s6
; GFX10-NEXT:    s_and_saveexec_b32 s4, s5
; GFX10-NEXT:    s_cbranch_execz .LBB1_1
; GFX10-NEXT:  ; %bb.3: ; %is.eq.zero
; GFX10-NEXT:    ; in Loop: Header=BB1_2 Depth=1
; GFX10-NEXT:    global_load_dword v5, v[1:2], off
; GFX10-NEXT:    s_andn2_b32 s6, s6, exec_lo
; GFX10-NEXT:    s_waitcnt vmcnt(0)
; GFX10-NEXT:    v_cmp_eq_u32_e32 vcc_lo, 0, v5
; GFX10-NEXT:    s_and_b32 s7, exec_lo, vcc_lo
; GFX10-NEXT:    s_or_b32 s6, s6, s7
; GFX10-NEXT:    s_branch .LBB1_1
; GFX10-NEXT:  .LBB1_4: ; %exit
; GFX10-NEXT:    v_cndmask_b32_e64 v0, 0, 1.0, s5
; GFX10-NEXT:    flat_store_dword v[3:4], v0
; GFX10-NEXT:    s_waitcnt lgkmcnt(0)
; GFX10-NEXT:    s_setpc_b64 s[30:31]
entry:
  br label %loop.start

loop.start:
  %i = phi i32 [ 0, %entry ], [ %i.plus.1, %loop.cond ]
  %all.eq.zero = phi i1 [ true, %entry ], [ %eq.zero, %loop.cond ]
  br i1 %all.eq.zero, label %is.eq.zero, label %loop.cond

is.eq.zero:
  %a.plus.i = getelementptr i32, ptr addrspace(1) %a, i32 %i
  %elt.i = load i32, ptr addrspace(1) %a.plus.i
  %elt.i.eq.zero = icmp eq i32 %elt.i, 0
  br label %loop.cond

loop.cond:
  %eq.zero = phi i1 [ %all.eq.zero, %loop.start ], [ %elt.i.eq.zero, %is.eq.zero ]
  %cond = icmp slt i32 %i, 10
  %i.plus.1 = add i32 %i, 1
  br i1 %cond, label %exit, label %loop.start

exit:
  %select = select i1 %all.eq.zero, float 1.000000e+00, float 0.000000e+00
  store float %select, ptr %addr
  ret void
}

; Non-phi used outside of the loop

define void @divergent_i1_xor_used_outside_loop(float %val, float %pre.cond.val, ptr %addr) {
; GFX10-LABEL: divergent_i1_xor_used_outside_loop:
; GFX10:       ; %bb.0: ; %entry
; GFX10-NEXT:    s_waitcnt vmcnt(0) expcnt(0) lgkmcnt(0)
; GFX10-NEXT:    s_mov_b32 s4, 0
; GFX10-NEXT:    v_cmp_lt_f32_e64 s5, 1.0, v1
; GFX10-NEXT:    v_mov_b32_e32 v1, s4
; GFX10-NEXT:    ; implicit-def: $sgpr6
; GFX10-NEXT:    ; implicit-def: $sgpr7
; GFX10-NEXT:  .LBB2_1: ; %loop
; GFX10-NEXT:    ; =>This Inner Loop Header: Depth=1
; GFX10-NEXT:    v_cvt_f32_u32_e32 v4, v1
; GFX10-NEXT:    s_xor_b32 s5, s5, -1
; GFX10-NEXT:    v_add_nc_u32_e32 v1, 1, v1
; GFX10-NEXT:    v_cmp_gt_f32_e32 vcc_lo, v4, v0
; GFX10-NEXT:    s_or_b32 s4, vcc_lo, s4
; GFX10-NEXT:    s_andn2_b32 s7, s7, exec_lo
; GFX10-NEXT:    s_and_b32 s8, exec_lo, s5
; GFX10-NEXT:    s_andn2_b32 s6, s6, exec_lo
; GFX10-NEXT:    s_or_b32 s7, s7, s8
; GFX10-NEXT:    s_and_b32 s8, exec_lo, s7
; GFX10-NEXT:    s_or_b32 s6, s6, s8
; GFX10-NEXT:    s_andn2_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    s_cbranch_execnz .LBB2_1
; GFX10-NEXT:  ; %bb.2: ; %exit
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    v_cndmask_b32_e64 v0, 0, 1.0, s6
; GFX10-NEXT:    flat_store_dword v[2:3], v0
; GFX10-NEXT:    s_waitcnt lgkmcnt(0)
; GFX10-NEXT:    s_setpc_b64 s[30:31]
entry:
  %pre.cond = fcmp ogt float %pre.cond.val, 1.0
  br label %loop

loop:
  %counter = phi i32 [ 0, %entry ], [ %counter.plus.1, %loop ]
  %bool.counter = phi i1 [ %pre.cond, %entry ], [ %neg.bool.counter, %loop ]
  %neg.bool.counter = xor i1 %bool.counter, true
  %f.counter = uitofp i32 %counter to float
  %cond = fcmp ogt float %f.counter, %val
  %counter.plus.1 = add i32 %counter, 1
  br i1 %cond, label %exit, label %loop

exit:
  %select = select i1 %neg.bool.counter, float 1.000000e+00, float 0.000000e+00
  store float %select, ptr %addr
  ret void
}

define void @divergent_i1_xor_used_outside_loop_twice(float %val, float %pre.cond.val, ptr %addr, ptr %addr2) {
; GFX10-LABEL: divergent_i1_xor_used_outside_loop_twice:
; GFX10:       ; %bb.0: ; %entry
; GFX10-NEXT:    s_waitcnt vmcnt(0) expcnt(0) lgkmcnt(0)
; GFX10-NEXT:    s_mov_b32 s4, 0
; GFX10-NEXT:    v_cmp_lt_f32_e64 s5, 1.0, v1
; GFX10-NEXT:    v_mov_b32_e32 v1, s4
; GFX10-NEXT:    ; implicit-def: $sgpr6
; GFX10-NEXT:    ; implicit-def: $sgpr7
; GFX10-NEXT:  .LBB3_1: ; %loop
; GFX10-NEXT:    ; =>This Inner Loop Header: Depth=1
; GFX10-NEXT:    v_cvt_f32_u32_e32 v6, v1
; GFX10-NEXT:    s_xor_b32 s5, s5, -1
; GFX10-NEXT:    v_add_nc_u32_e32 v1, 1, v1
; GFX10-NEXT:    v_cmp_gt_f32_e32 vcc_lo, v6, v0
; GFX10-NEXT:    s_or_b32 s4, vcc_lo, s4
; GFX10-NEXT:    s_andn2_b32 s7, s7, exec_lo
; GFX10-NEXT:    s_and_b32 s8, exec_lo, s5
; GFX10-NEXT:    s_andn2_b32 s6, s6, exec_lo
; GFX10-NEXT:    s_or_b32 s7, s7, s8
; GFX10-NEXT:    s_and_b32 s8, exec_lo, s7
; GFX10-NEXT:    s_or_b32 s6, s6, s8
; GFX10-NEXT:    s_andn2_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    s_cbranch_execnz .LBB3_1
; GFX10-NEXT:  ; %bb.2: ; %exit
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    v_cndmask_b32_e64 v0, 0, 1.0, s6
; GFX10-NEXT:    v_cndmask_b32_e64 v1, -1.0, 2.0, s6
; GFX10-NEXT:    flat_store_dword v[2:3], v0
; GFX10-NEXT:    flat_store_dword v[4:5], v1
; GFX10-NEXT:    s_waitcnt lgkmcnt(0)
; GFX10-NEXT:    s_setpc_b64 s[30:31]
entry:
  %pre.cond = fcmp ogt float %pre.cond.val, 1.0
  br label %loop

loop:
  %counter = phi i32 [ 0, %entry ], [ %counter.plus.1, %loop ]
  %bool.counter = phi i1 [ %pre.cond, %entry ], [ %neg.bool.counter, %loop ]
  %neg.bool.counter = xor i1 %bool.counter, true
  %f.counter = uitofp i32 %counter to float
  %cond = fcmp ogt float %f.counter, %val
  %counter.plus.1 = add i32 %counter, 1
  br i1 %cond, label %exit, label %loop

exit:
  %select = select i1 %neg.bool.counter, float 1.000000e+00, float 0.000000e+00
  store float %select, ptr %addr
  %select2 = select i1 %neg.bool.counter, float 2.000000e+00, float -1.000000e+00
  store float %select2, ptr %addr2
  ret void
}

;void xor(int num_elts, int* a, int* addr) {
;for(int i=0; i<num_elts; ++i) {
;  if(a[i]==0)
;    return;
;}
;addr[0] = 5
;return;
;}

define void @divergent_i1_xor_used_outside_loop_larger_loop_body(i32 %num.elts, ptr addrspace(1) %a, ptr %addr) {
; GFX10-LABEL: divergent_i1_xor_used_outside_loop_larger_loop_body:
; GFX10:       ; %bb.0: ; %entry
; GFX10-NEXT:    s_waitcnt vmcnt(0) expcnt(0) lgkmcnt(0)
; GFX10-NEXT:    v_cmp_eq_u32_e32 vcc_lo, 0, v0
; GFX10-NEXT:    s_mov_b32 s5, 0
; GFX10-NEXT:    s_mov_b32 s6, -1
; GFX10-NEXT:    s_and_saveexec_b32 s4, vcc_lo
; GFX10-NEXT:    s_cbranch_execz .LBB4_6
; GFX10-NEXT:  ; %bb.1: ; %loop.start.preheader
; GFX10-NEXT:    v_mov_b32_e32 v5, s5
; GFX10-NEXT:    ; implicit-def: $sgpr6
; GFX10-NEXT:    ; implicit-def: $sgpr8
; GFX10-NEXT:    ; implicit-def: $sgpr9
; GFX10-NEXT:    ; implicit-def: $sgpr7
; GFX10-NEXT:    s_branch .LBB4_3
; GFX10-NEXT:  .LBB4_2: ; %Flow
; GFX10-NEXT:    ; in Loop: Header=BB4_3 Depth=1
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s10
; GFX10-NEXT:    s_xor_b32 s10, s9, -1
; GFX10-NEXT:    s_and_b32 s11, exec_lo, s8
; GFX10-NEXT:    s_or_b32 s5, s11, s5
; GFX10-NEXT:    s_andn2_b32 s7, s7, exec_lo
; GFX10-NEXT:    s_and_b32 s10, exec_lo, s10
; GFX10-NEXT:    s_andn2_b32 s6, s6, exec_lo
; GFX10-NEXT:    s_or_b32 s7, s7, s10
; GFX10-NEXT:    s_and_b32 s10, exec_lo, s7
; GFX10-NEXT:    s_or_b32 s6, s6, s10
; GFX10-NEXT:    s_andn2_b32 exec_lo, exec_lo, s5
; GFX10-NEXT:    s_cbranch_execz .LBB4_5
; GFX10-NEXT:  .LBB4_3: ; %loop.start
; GFX10-NEXT:    ; =>This Inner Loop Header: Depth=1
; GFX10-NEXT:    v_ashrrev_i32_e32 v6, 31, v5
; GFX10-NEXT:    s_andn2_b32 s9, s9, exec_lo
; GFX10-NEXT:    s_and_b32 s10, exec_lo, -1
; GFX10-NEXT:    s_andn2_b32 s8, s8, exec_lo
; GFX10-NEXT:    s_or_b32 s9, s9, s10
; GFX10-NEXT:    v_lshlrev_b64 v[6:7], 2, v[5:6]
; GFX10-NEXT:    s_or_b32 s8, s8, s10
; GFX10-NEXT:    v_add_co_u32 v6, vcc_lo, v1, v6
; GFX10-NEXT:    v_add_co_ci_u32_e32 v7, vcc_lo, v2, v7, vcc_lo
; GFX10-NEXT:    global_load_dword v6, v[6:7], off
; GFX10-NEXT:    s_waitcnt vmcnt(0)
; GFX10-NEXT:    v_cmp_ne_u32_e32 vcc_lo, 0, v6
; GFX10-NEXT:    s_and_saveexec_b32 s10, vcc_lo
; GFX10-NEXT:    s_cbranch_execz .LBB4_2
; GFX10-NEXT:  ; %bb.4: ; %loop.cond
; GFX10-NEXT:    ; in Loop: Header=BB4_3 Depth=1
; GFX10-NEXT:    v_add_nc_u32_e32 v6, 1, v5
; GFX10-NEXT:    v_cmp_lt_i32_e32 vcc_lo, v5, v0
; GFX10-NEXT:    s_andn2_b32 s9, s9, exec_lo
; GFX10-NEXT:    s_and_b32 s11, exec_lo, 0
; GFX10-NEXT:    s_andn2_b32 s8, s8, exec_lo
; GFX10-NEXT:    v_mov_b32_e32 v5, v6
; GFX10-NEXT:    s_and_b32 s12, exec_lo, vcc_lo
; GFX10-NEXT:    s_or_b32 s9, s9, s11
; GFX10-NEXT:    s_or_b32 s8, s8, s12
; GFX10-NEXT:    s_branch .LBB4_2
; GFX10-NEXT:  .LBB4_5: ; %loop.exit.guard
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s5
; GFX10-NEXT:    s_andn2_b32 s5, -1, exec_lo
; GFX10-NEXT:    s_and_b32 s6, exec_lo, s6
; GFX10-NEXT:    s_or_b32 s6, s5, s6
; GFX10-NEXT:  .LBB4_6: ; %Flow1
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    s_and_saveexec_b32 s4, s6
; GFX10-NEXT:    s_cbranch_execz .LBB4_8
; GFX10-NEXT:  ; %bb.7: ; %block.after.loop
; GFX10-NEXT:    v_mov_b32_e32 v0, 5
; GFX10-NEXT:    flat_store_dword v[3:4], v0
; GFX10-NEXT:  .LBB4_8: ; %exit
; GFX10-NEXT:    s_waitcnt_depctr 0xffe3
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    s_waitcnt lgkmcnt(0)
; GFX10-NEXT:    s_setpc_b64 s[30:31]
entry:
  %start.cond = icmp eq i32 %num.elts, 0
  br i1 %start.cond, label %loop.start, label %block.after.loop

loop.start:
  %i = phi i32 [ 0, %entry ], [ %i.plus.1, %loop.cond ]
  %a.plus.i = getelementptr i32, ptr addrspace(1) %a, i32 %i
  %elt.i = load i32, ptr addrspace(1) %a.plus.i
  %elt.i.eq.zero = icmp eq i32 %elt.i, 0
  br i1 %elt.i.eq.zero, label %exit, label %loop.cond

loop.cond:
  %cond = icmp slt i32 %i, %num.elts
  %i.plus.1 = add i32 %i, 1
  br i1 %cond, label %block.after.loop, label %loop.start

block.after.loop:
  store i32 5, ptr %addr
  br label %exit

exit:
  ret void
}


;void icmp(int num_elts, int* a, int* addr) {
;for(;;) {
;  if(a[i]==0)
;    return;
;}
;addr[0] = 5
;return;
;}

define void @divergent_i1_icmp_used_outside_loop(i32 %v0, i32 %v1, ptr addrspace(1) %a, ptr addrspace(1) %b, ptr addrspace(1) %c, ptr %addr) {
; GFX10-LABEL: divergent_i1_icmp_used_outside_loop:
; GFX10:       ; %bb.0: ; %entry
; GFX10-NEXT:    s_waitcnt vmcnt(0) expcnt(0) lgkmcnt(0)
; GFX10-NEXT:    s_mov_b32 s4, 0
; GFX10-NEXT:    ; implicit-def: $sgpr5
; GFX10-NEXT:    ; implicit-def: $sgpr6
; GFX10-NEXT:    v_mov_b32_e32 v5, s4
; GFX10-NEXT:    s_branch .LBB5_2
; GFX10-NEXT:  .LBB5_1: ; %Flow
; GFX10-NEXT:    ; in Loop: Header=BB5_2 Depth=1
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s8
; GFX10-NEXT:    s_and_b32 s7, exec_lo, s7
; GFX10-NEXT:    s_or_b32 s4, s7, s4
; GFX10-NEXT:    s_andn2_b32 s5, s5, exec_lo
; GFX10-NEXT:    s_and_b32 s7, exec_lo, s6
; GFX10-NEXT:    s_or_b32 s5, s5, s7
; GFX10-NEXT:    s_andn2_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    s_cbranch_execz .LBB5_6
; GFX10-NEXT:  .LBB5_2: ; %cond.block.0
; GFX10-NEXT:    ; =>This Inner Loop Header: Depth=1
; GFX10-NEXT:    v_mov_b32_e32 v4, v5
; GFX10-NEXT:    s_andn2_b32 s6, s6, exec_lo
; GFX10-NEXT:    v_cmp_eq_u32_e32 vcc_lo, v0, v4
; GFX10-NEXT:    s_and_b32 s7, exec_lo, vcc_lo
; GFX10-NEXT:    s_or_b32 s6, s6, s7
; GFX10-NEXT:    s_and_saveexec_b32 s7, vcc_lo
; GFX10-NEXT:    s_cbranch_execz .LBB5_4
; GFX10-NEXT:  ; %bb.3: ; %if.block.0
; GFX10-NEXT:    ; in Loop: Header=BB5_2 Depth=1
; GFX10-NEXT:    v_ashrrev_i32_e32 v5, 31, v4
; GFX10-NEXT:    v_lshlrev_b64 v[8:9], 2, v[4:5]
; GFX10-NEXT:    v_add_co_u32 v8, vcc_lo, v2, v8
; GFX10-NEXT:    v_add_co_ci_u32_e32 v9, vcc_lo, v3, v9, vcc_lo
; GFX10-NEXT:    global_store_dword v[8:9], v4, off
; GFX10-NEXT:  .LBB5_4: ; %loop.break.block
; GFX10-NEXT:    ; in Loop: Header=BB5_2 Depth=1
; GFX10-NEXT:    s_waitcnt_depctr 0xffe3
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s7
; GFX10-NEXT:    v_cmp_ne_u32_e32 vcc_lo, v1, v4
; GFX10-NEXT:    s_mov_b32 s7, -1
; GFX10-NEXT:    ; implicit-def: $vgpr5
; GFX10-NEXT:    s_and_saveexec_b32 s8, vcc_lo
; GFX10-NEXT:    s_cbranch_execz .LBB5_1
; GFX10-NEXT:  ; %bb.5: ; %loop.cond
; GFX10-NEXT:    ; in Loop: Header=BB5_2 Depth=1
; GFX10-NEXT:    v_add_nc_u32_e32 v5, 1, v4
; GFX10-NEXT:    s_andn2_b32 s7, -1, exec_lo
; GFX10-NEXT:    s_and_b32 s9, exec_lo, 0
; GFX10-NEXT:    s_or_b32 s7, s7, s9
; GFX10-NEXT:    s_branch .LBB5_1
; GFX10-NEXT:  .LBB5_6: ; %cond.block.1
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    s_and_saveexec_b32 s4, s5
; GFX10-NEXT:    s_cbranch_execz .LBB5_8
; GFX10-NEXT:  ; %bb.7: ; %if.block.1
; GFX10-NEXT:    global_store_dword v[6:7], v4, off
; GFX10-NEXT:  .LBB5_8: ; %exit
; GFX10-NEXT:    s_waitcnt_depctr 0xffe3
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s4
; GFX10-NEXT:    s_setpc_b64 s[30:31]
entry:
  br label %loop.start

loop.start:
  %i = phi i32 [ 0, %entry ], [ %i.plus.1, %loop.cond ]
  br label %cond.block.0

cond.block.0:
  %cond.0 = icmp eq i32 %v0, %i
  br i1 %cond.0, label %if.block.0, label %loop.break.block

if.block.0:
  %a.plus.i = getelementptr i32, ptr addrspace(1) %a, i32 %i
  store i32 %i, ptr addrspace(1) %a.plus.i
  br label %loop.break.block

loop.break.block:
  %cond.1 = icmp eq i32 %v1, %i
  br i1 %cond.1, label %cond.block.1, label %loop.cond

loop.cond:
  ; no cond, infinite loop with one break
  %i.plus.1 = add i32 %i, 1
  br label %loop.start

cond.block.1:
  %cond.2 = icmp eq i32 %v0, %i
  br i1 %cond.2, label %if.block.1, label %exit

if.block.1:
  store i32 %i, ptr addrspace(1) %c
  br label %exit

exit:
  ret void
}


; bool all_eq_zero = true;
; i32 i = 0;
; do {
;   if(all_eq_zero)
;     all_eq_zero = (a[i] == 0);
;
;   i += 1;
; } while ( i < n )

; *addr = all_eq_zero ? 1.0 : 0.0;

; check that all elements in an array of size n are zero, loop has divergent
; exit condition based on array size, but zero check does not break out of the
; loop but instead skips zero check in remaining iterations
; llpc "freezes" zero check since it is (via phi) used in a conditional branch
define amdgpu_ps void @divergent_i1_freeze_used_outside_loop(i32 %n, ptr addrspace(1) %a, ptr %addr) {
; GFX10-LABEL: divergent_i1_freeze_used_outside_loop:
; GFX10:       ; %bb.0: ; %entry
; GFX10-NEXT:    s_mov_b32 s0, 0
; GFX10-NEXT:    s_mov_b32 s4, -1
; GFX10-NEXT:    v_mov_b32_e32 v5, s0
; GFX10-NEXT:    ; implicit-def: $sgpr3
; GFX10-NEXT:    ; implicit-def: $sgpr1
; GFX10-NEXT:    ; implicit-def: $sgpr2
; GFX10-NEXT:    s_branch .LBB6_2
; GFX10-NEXT:  .LBB6_1: ; %loop.cond
; GFX10-NEXT:    ; in Loop: Header=BB6_2 Depth=1
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s5
; GFX10-NEXT:    v_cmp_lt_i32_e32 vcc_lo, v5, v0
; GFX10-NEXT:    v_add_nc_u32_e32 v5, 1, v5
; GFX10-NEXT:    s_or_b32 s0, vcc_lo, s0
; GFX10-NEXT:    s_andn2_b32 s2, s2, exec_lo
; GFX10-NEXT:    s_and_b32 s5, exec_lo, s1
; GFX10-NEXT:    s_andn2_b32 s4, s4, exec_lo
; GFX10-NEXT:    s_or_b32 s2, s2, s5
; GFX10-NEXT:    s_andn2_b32 s3, s3, exec_lo
; GFX10-NEXT:    s_and_b32 s6, exec_lo, s2
; GFX10-NEXT:    s_or_b32 s4, s4, s5
; GFX10-NEXT:    s_or_b32 s3, s3, s6
; GFX10-NEXT:    s_andn2_b32 exec_lo, exec_lo, s0
; GFX10-NEXT:    s_cbranch_execz .LBB6_4
; GFX10-NEXT:  .LBB6_2: ; %loop.start
; GFX10-NEXT:    ; =>This Inner Loop Header: Depth=1
; GFX10-NEXT:    s_andn2_b32 s1, s1, exec_lo
; GFX10-NEXT:    s_and_b32 s5, exec_lo, s4
; GFX10-NEXT:    s_or_b32 s1, s1, s5
; GFX10-NEXT:    s_and_saveexec_b32 s5, s4
; GFX10-NEXT:    s_cbranch_execz .LBB6_1
; GFX10-NEXT:  ; %bb.3: ; %is.eq.zero
; GFX10-NEXT:    ; in Loop: Header=BB6_2 Depth=1
; GFX10-NEXT:    v_ashrrev_i32_e32 v6, 31, v5
; GFX10-NEXT:    s_andn2_b32 s1, s1, exec_lo
; GFX10-NEXT:    v_lshlrev_b64 v[6:7], 2, v[5:6]
; GFX10-NEXT:    v_add_co_u32 v6, vcc_lo, v1, v6
; GFX10-NEXT:    v_add_co_ci_u32_e32 v7, vcc_lo, v2, v7, vcc_lo
; GFX10-NEXT:    global_load_dword v6, v[6:7], off
; GFX10-NEXT:    s_waitcnt vmcnt(0)
; GFX10-NEXT:    v_cmp_eq_u32_e32 vcc_lo, 0, v6
; GFX10-NEXT:    s_and_b32 s4, exec_lo, vcc_lo
; GFX10-NEXT:    s_or_b32 s1, s1, s4
; GFX10-NEXT:    ; implicit-def: $sgpr4
; GFX10-NEXT:    s_branch .LBB6_1
; GFX10-NEXT:  .LBB6_4: ; %exit
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s0
; GFX10-NEXT:    v_cndmask_b32_e64 v0, 0, 1.0, s3
; GFX10-NEXT:    flat_store_dword v[3:4], v0
; GFX10-NEXT:    s_endpgm
entry:
  br label %loop.start

loop.start:
  %i = phi i32 [ 0, %entry ], [ %i.plus.1, %loop.cond ]
  %all.eq.zero = phi i1 [ true, %entry ], [ %eq.zero.fr, %loop.cond ]
  br i1 %all.eq.zero, label %is.eq.zero, label %loop.cond

is.eq.zero:
  %a.plus.i = getelementptr i32, ptr addrspace(1) %a, i32 %i
  %elt.i = load i32, ptr addrspace(1) %a.plus.i
  %elt.i.eq.zero = icmp eq i32 %elt.i, 0
  br label %loop.cond

loop.cond:
  %eq.zero = phi i1 [ %all.eq.zero, %loop.start ], [ %elt.i.eq.zero, %is.eq.zero ]
  %eq.zero.fr = freeze i1 %eq.zero
  %cond = icmp slt i32 %i, %n
  %i.plus.1 = add i32 %i, 1
  br i1 %cond, label %exit, label %loop.start

exit:
  %select = select i1 %eq.zero.fr, float 1.000000e+00, float 0.000000e+00
  store float %select, ptr %addr
  ret void
}

; Divergent i1 phi from structurize-cfg used outside of the loop
define amdgpu_cs void @loop_with_1break(ptr addrspace(1) %x, ptr addrspace(1) %a, ptr addrspace(1) %a.break) {
; GFX10-LABEL: loop_with_1break:
; GFX10:       ; %bb.0: ; %entry
; GFX10-NEXT:    s_mov_b32 s0, 0
; GFX10-NEXT:    ; implicit-def: $sgpr1
; GFX10-NEXT:    ; implicit-def: $sgpr3
; GFX10-NEXT:    ; implicit-def: $sgpr4
; GFX10-NEXT:    ; implicit-def: $sgpr2
; GFX10-NEXT:    v_mov_b32_e32 v6, s0
; GFX10-NEXT:    s_branch .LBB7_2
; GFX10-NEXT:  .LBB7_1: ; %Flow
; GFX10-NEXT:    ; in Loop: Header=BB7_2 Depth=1
; GFX10-NEXT:    s_waitcnt_depctr 0xffe3
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s5
; GFX10-NEXT:    s_and_b32 s5, exec_lo, s3
; GFX10-NEXT:    s_or_b32 s0, s5, s0
; GFX10-NEXT:    s_andn2_b32 s2, s2, exec_lo
; GFX10-NEXT:    s_and_b32 s5, exec_lo, s4
; GFX10-NEXT:    s_andn2_b32 s1, s1, exec_lo
; GFX10-NEXT:    s_or_b32 s2, s2, s5
; GFX10-NEXT:    s_and_b32 s5, exec_lo, s2
; GFX10-NEXT:    s_or_b32 s1, s1, s5
; GFX10-NEXT:    s_andn2_b32 exec_lo, exec_lo, s0
; GFX10-NEXT:    s_cbranch_execz .LBB7_4
; GFX10-NEXT:  .LBB7_2: ; %A
; GFX10-NEXT:    ; =>This Inner Loop Header: Depth=1
; GFX10-NEXT:    v_ashrrev_i32_e32 v7, 31, v6
; GFX10-NEXT:    s_andn2_b32 s4, s4, exec_lo
; GFX10-NEXT:    s_and_b32 s5, exec_lo, -1
; GFX10-NEXT:    s_andn2_b32 s3, s3, exec_lo
; GFX10-NEXT:    s_or_b32 s4, s4, s5
; GFX10-NEXT:    v_lshlrev_b64 v[7:8], 2, v[6:7]
; GFX10-NEXT:    s_or_b32 s3, s3, s5
; GFX10-NEXT:    v_add_co_u32 v9, vcc_lo, v2, v7
; GFX10-NEXT:    v_add_co_ci_u32_e32 v10, vcc_lo, v3, v8, vcc_lo
; GFX10-NEXT:    global_load_dword v9, v[9:10], off
; GFX10-NEXT:    s_waitcnt vmcnt(0)
; GFX10-NEXT:    v_cmp_ne_u32_e32 vcc_lo, 0, v9
; GFX10-NEXT:    s_and_saveexec_b32 s5, vcc_lo
; GFX10-NEXT:    s_cbranch_execz .LBB7_1
; GFX10-NEXT:  ; %bb.3: ; %loop.body
; GFX10-NEXT:    ; in Loop: Header=BB7_2 Depth=1
; GFX10-NEXT:    v_add_co_u32 v7, vcc_lo, v0, v7
; GFX10-NEXT:    v_add_co_ci_u32_e32 v8, vcc_lo, v1, v8, vcc_lo
; GFX10-NEXT:    v_add_nc_u32_e32 v10, 1, v6
; GFX10-NEXT:    v_cmp_gt_u32_e32 vcc_lo, 0x64, v6
; GFX10-NEXT:    s_andn2_b32 s4, s4, exec_lo
; GFX10-NEXT:    global_load_dword v9, v[7:8], off
; GFX10-NEXT:    s_and_b32 s6, exec_lo, 0
; GFX10-NEXT:    v_mov_b32_e32 v6, v10
; GFX10-NEXT:    s_andn2_b32 s3, s3, exec_lo
; GFX10-NEXT:    s_and_b32 s7, exec_lo, vcc_lo
; GFX10-NEXT:    s_or_b32 s4, s4, s6
; GFX10-NEXT:    s_or_b32 s3, s3, s7
; GFX10-NEXT:    s_waitcnt vmcnt(0)
; GFX10-NEXT:    v_add_nc_u32_e32 v9, 1, v9
; GFX10-NEXT:    global_store_dword v[7:8], v9, off
; GFX10-NEXT:    s_branch .LBB7_1
; GFX10-NEXT:  .LBB7_4: ; %loop.exit.guard
; GFX10-NEXT:    s_or_b32 exec_lo, exec_lo, s0
; GFX10-NEXT:    s_and_saveexec_b32 s0, s1
; GFX10-NEXT:    s_xor_b32 s0, exec_lo, s0
; GFX10-NEXT:    s_cbranch_execz .LBB7_6
; GFX10-NEXT:  ; %bb.5: ; %break.body
; GFX10-NEXT:    v_mov_b32_e32 v0, 10
; GFX10-NEXT:    global_store_dword v[4:5], v0, off
; GFX10-NEXT:  .LBB7_6: ; %exit
; GFX10-NEXT:    s_endpgm
entry:
  br label %A

A:
  %counter = phi i32 [ %counter.plus.1, %loop.body ], [ 0, %entry ]
  %a.plus.counter = getelementptr inbounds i32, ptr addrspace(1) %a, i32 %counter
  %a.val = load i32, ptr addrspace(1) %a.plus.counter
  %a.cond = icmp eq i32 %a.val, 0
  br i1 %a.cond, label %break.body, label %loop.body

break.body:
  store i32 10, ptr addrspace(1) %a.break
  br label %exit

loop.body:
  %x.plus.counter = getelementptr inbounds i32, ptr addrspace(1) %x, i32 %counter
  %x.val = load i32, ptr addrspace(1) %x.plus.counter
  %x.val.plus.1 = add i32 %x.val, 1
  store i32 %x.val.plus.1, ptr addrspace(1) %x.plus.counter
  %counter.plus.1 = add i32 %counter, 1
  %x.cond = icmp ult i32 %counter, 100
  br i1 %x.cond, label %exit, label %A

exit:
  ret void
}

