; RUN: llc -mtriple=x86_64-unknown-linux -o - %s | FileCheck %s

@vtable = constant [5 x i32] [i32 0,
    i32 trunc (i64 sub (i64 ptrtoint (ptr @fn1 to i64), i64 ptrtoint (ptr getelementptr ([5 x i32], ptr @vtable, i32 0, i32 1) to i64)) to i32),
    i32 trunc (i64 sub (i64 ptrtoint (ptr @fn2 to i64), i64 ptrtoint (ptr getelementptr ([5 x i32], ptr @vtable, i32 0, i32 1) to i64)) to i32),
    i32 trunc (i64 sub (i64 ptrtoint (ptr @fn3 to i64), i64 ptrtoint (ptr getelementptr ([5 x i32], ptr @vtable, i32 0, i32 1) to i64)) to i32),
    i32 trunc (i64 sub (i64 ptrtoint (ptr @global4 to i64), i64 ptrtoint (ptr getelementptr ([5 x i32], ptr @vtable, i32 0, i32 1) to i64)) to i32)
]

declare void @fn1() unnamed_addr
declare void @fn2() unnamed_addr
declare void @fn3()
@global4 = external unnamed_addr global i8

;; Create a PC-relative relocation that the linker might decline if the addend symbol is preemptible.
; CHECK: .long 0
; CHECK-NEXT: .long fn1-vtable-4
; CHECK-NEXT: .long fn2-vtable-4
; CHECK-NEXT: .long fn3-vtable-4
; CHECK-NEXT: .long global4-vtable-4
