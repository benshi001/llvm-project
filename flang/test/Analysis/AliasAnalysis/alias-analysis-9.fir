// RUN: fir-opt %s -pass-pipeline='builtin.module(func.func(test-fir-alias-analysis))' -split-input-file 2>&1 | FileCheck %s

// -----

// module m
// type t
//  type(t), pointer :: next
//  integer :: i
// end type
// contains
// subroutine foo(x, y)
//   type(t) :: x, y
//   integer :: i1, i2
//   i1 = x%next%i
//   x = y
//   i2 = x%next%i
// end subroutine
// end module

// CHECK-LABEL: Testing : "_QMmPfoo"
// TODO: x and y are non pointer, non target argument and therefore do not alias.
// CHECK-DAG: x#0 <-> y#0: MayAlias

// TODO: y is not a pointer object and therefore does not alias with the x%next component. 
//       Also assigning x to y would not modify x.next
// CHECK-DAG: y#0 <-> xnext1#0: MayAlias
// CHECK-DAG: y#0 <-> xnext2#0: MayAlias

// We need to catch the fact that assigning y to x will modify xnext. 
// The only side-effect between the 2 loads of x.next is the assignment to x, 
// therefore x needs to alias with x.next to prevent the loads from being merged.
// CHECK-DAG: x#0 <-> xnext1#0: MayAlias
// CHECK-DAG: x#0 <-> xnext2#0: MayAlias

// TODO: xnext1#0 <-> xnext2#0 are the same and therefore MustAlias but 
//       we are currently not comparing operands involved in offset computations
// CHECK-DAG: xnext1#0 <-> xnext2#0: MayAlias

func.func @_QMmPfoo(%arg0: !fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>> {fir.bindc_name = "x"}, %arg1: !fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>> {fir.bindc_name = "y"}) {
  %0 = fir.alloca i32 {bindc_name = "i1", uniq_name = "_QMmFfooEi1"}
  %1:2 = hlfir.declare %0 {uniq_name = "_QMmFfooEi1"} : (!fir.ref<i32>) -> (!fir.ref<i32>, !fir.ref<i32>)
  %2 = fir.alloca i32 {bindc_name = "i2", uniq_name = "_QMmFfooEi2"}
  %3:2 = hlfir.declare %2 {uniq_name = "_QMmFfooEi2"} : (!fir.ref<i32>) -> (!fir.ref<i32>, !fir.ref<i32>)
  %4:2 = hlfir.declare %arg0 {uniq_name = "_QMmFfooEx", test.ptr = "x"} : (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>) -> (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>, !fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>)
  %5:2 = hlfir.declare %arg1 {uniq_name = "_QMmFfooEy", test.ptr = "y"} : (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>) -> (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>, !fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>)
  %6 = hlfir.designate %4#0{"next"}   {fortran_attrs = #fir.var_attrs<pointer>, test.ptr = "xnext1"} : (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>) -> !fir.ref<!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>>
  %7 = fir.load %6 : !fir.ref<!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>>
  %8 = fir.box_addr %7 : (!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>) -> !fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>
  %9 = hlfir.designate %8{"i"} : (!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>) -> !fir.ref<i32>
  %10 = fir.load %9 : !fir.ref<i32>
  hlfir.assign %10 to %1#0 : i32, !fir.ref<i32>
  hlfir.assign %5#0 to %4#0 : !fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>, !fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>
  %11 = hlfir.designate %4#0{"next"}   {fortran_attrs = #fir.var_attrs<pointer>, test.ptr = "xnext2"} : (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>) -> !fir.ref<!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>>
  %12 = fir.load %11 : !fir.ref<!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>>
  %13 = fir.box_addr %12 : (!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>) -> !fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>
  %14 = hlfir.designate %13{"i"} : (!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>) -> !fir.ref<i32>
  %15 = fir.load %14 : !fir.ref<i32>
  hlfir.assign %15 to %3#0 : i32, !fir.ref<i32>
  return
}

// -----

// Same test as above focusing on aliasing between x%next and y%next data
// CHECK-LABEL: Testing : "_QMmPfoo2"
// CHECK-DAG: xnext#0 <-> ynext#0: MayAlias

func.func @_QMmPfoo2(%arg0: !fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>> {fir.bindc_name = "x"}, %arg1: !fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>> {fir.bindc_name = "y"}) {
  %4:2 = hlfir.declare %arg0 {uniq_name = "_QMmFfooEx"} : (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>) -> (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>, !fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>)
  %5:2 = hlfir.declare %arg1 {uniq_name = "_QMmFfooEy"} : (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>) -> (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>, !fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>)
  %6 = hlfir.designate %4#0{"next"}   {fortran_attrs = #fir.var_attrs<pointer>} : (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>) -> !fir.ref<!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>>
  %7 = fir.load %6 : !fir.ref<!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>>
  %8 = fir.box_addr %7 {test.ptr = "xnext"} : (!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>) -> !fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>

  %9 = hlfir.designate %5#0{"next"}   {fortran_attrs = #fir.var_attrs<pointer>} : (!fir.ref<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>) -> !fir.ref<!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>>
  %10 = fir.load %9 : !fir.ref<!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>>
  %11 = fir.box_addr %10 {test.ptr = "ynext"} : (!fir.box<!fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>>) -> !fir.ptr<!fir.type<_QMmTt{next:!fir.box<!fir.ptr<!fir.type<_QMmTt>>>,i:i32}>>
  return
}

// -----

// module m
// type ta
//  integer, pointer :: array(:)
// end type
// contains
// subroutine foo3(x, y)
//   type(t) :: x, y
//   x%array(1) = y%array(1)
// end subroutine
// end module

// CHECK-LABEL: Testing : "_QMmPfoo3"
// CHECK-DAG: yarray#0 <-> xarray#0: MayAlias

func.func @_QMmPfoo3(%arg0: !fir.ref<!fir.type<_QMmTta{array:!fir.box<!fir.ptr<!fir.array<?xi32>>>}>> {fir.bindc_name = "x"}, %arg1: !fir.ref<!fir.type<_QMmTta{array:!fir.box<!fir.ptr<!fir.array<?xi32>>>}>> {fir.bindc_name = "y"}) {
  %0:2 = hlfir.declare %arg0 {uniq_name = "_QMmFfooEx"} : (!fir.ref<!fir.type<_QMmTta{array:!fir.box<!fir.ptr<!fir.array<?xi32>>>}>>) -> (!fir.ref<!fir.type<_QMmTta{array:!fir.box<!fir.ptr<!fir.array<?xi32>>>}>>, !fir.ref<!fir.type<_QMmTta{array:!fir.box<!fir.ptr<!fir.array<?xi32>>>}>>)
  %1:2 = hlfir.declare %arg1 {uniq_name = "_QMmFfooEy"} : (!fir.ref<!fir.type<_QMmTta{array:!fir.box<!fir.ptr<!fir.array<?xi32>>>}>>) -> (!fir.ref<!fir.type<_QMmTta{array:!fir.box<!fir.ptr<!fir.array<?xi32>>>}>>, !fir.ref<!fir.type<_QMmTta{array:!fir.box<!fir.ptr<!fir.array<?xi32>>>}>>)
  %2 = hlfir.designate %1#0{"array"}   {fortran_attrs = #fir.var_attrs<pointer>} : (!fir.ref<!fir.type<_QMmTta{array:!fir.box<!fir.ptr<!fir.array<?xi32>>>}>>) -> !fir.ref<!fir.box<!fir.ptr<!fir.array<?xi32>>>>
  %3 = fir.load %2 : !fir.ref<!fir.box<!fir.ptr<!fir.array<?xi32>>>>
  %c1 = arith.constant 1 : index
  %4 = hlfir.designate %3 (%c1) {test.ptr = "yarray"} : (!fir.box<!fir.ptr<!fir.array<?xi32>>>, index) -> !fir.ref<i32>
  %5 = fir.load %4 : !fir.ref<i32>
  %6 = hlfir.designate %0#0{"array"}   {fortran_attrs = #fir.var_attrs<pointer>} : (!fir.ref<!fir.type<_QMmTta{array:!fir.box<!fir.ptr<!fir.array<?xi32>>>}>>) -> !fir.ref<!fir.box<!fir.ptr<!fir.array<?xi32>>>>
  %7 = fir.load %6 : !fir.ref<!fir.box<!fir.ptr<!fir.array<?xi32>>>>
  %c1_0 = arith.constant 1 : index
  %8 = hlfir.designate %7 (%c1_0)  {test.ptr = "xarray"} : (!fir.box<!fir.ptr<!fir.array<?xi32>>>, index) -> !fir.ref<i32>
  hlfir.assign %5 to %8 : i32, !fir.ref<i32>
  return
}
