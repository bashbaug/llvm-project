//=- SystemZCallingConv.td - Calling conventions for SystemZ -*- tablegen -*-=//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
// This describes the calling conventions for the SystemZ ABI.
//===----------------------------------------------------------------------===//

class CCIfExtend<CCAction A>
  : CCIf<"ArgFlags.isSExt() || ArgFlags.isZExt()", A>;

class CCIfSubtarget<string F, CCAction A>
  : CCIf<!strconcat("static_cast<const SystemZSubtarget&>"
                    "(State.getMachineFunction().getSubtarget()).", F),
         A>;

// Match if this specific argument is a fixed (i.e. named) argument.
class CCIfFixed<CCAction A>
    : CCIf<"static_cast<SystemZCCState *>(&State)->IsFixed(ValNo)", A>;

// Match if this specific argument was widened from a short vector type.
class CCIfShortVector<CCAction A>
    : CCIf<"static_cast<SystemZCCState *>(&State)->IsShortVector(ValNo)", A>;


//===----------------------------------------------------------------------===//
// z/Linux return value calling convention
//===----------------------------------------------------------------------===//
def RetCC_SystemZ : CallingConv<[
  // Promote i32 to i64 if it has an explicit extension type.
  CCIfType<[i32], CCIfExtend<CCPromoteToType<i64>>>,

  // A SwiftError is returned in R9.
  CCIfSwiftError<CCIfType<[i64], CCAssignToReg<[R9D]>>>,

  // ABI-compliant code returns 64-bit integers in R2.  Make the other
  // call-clobbered argument registers available for code that doesn't
  // care about the ABI.  (R6 is an argument register too, but is
  // call-saved and therefore not suitable for return values.)
  CCIfType<[i32], CCAssignToReg<[R2L, R3L, R4L, R5L]>>,
  CCIfType<[i64], CCAssignToReg<[R2D, R3D, R4D, R5D]>>,

  // ABI-complaint code returns float and double in F0.  Make the
  // other floating-point argument registers available for code that
  // doesn't care about the ABI.  All floating-point argument registers
  // are call-clobbered, so we can use all of them here.
  CCIfType<[f32], CCAssignToReg<[F0S, F2S, F4S, F6S]>>,
  CCIfType<[f64], CCAssignToReg<[F0D, F2D, F4D, F6D]>>,

  // Similarly for vectors, with V24 being the ABI-compliant choice.
  // Sub-128 vectors are returned in the same way, but they're widened
  // to one of these types during type legalization.
  CCIfSubtarget<"hasVector()",
    CCIfType<[v16i8, v8i16, v4i32, v2i64, v4f32, v2f64],
             CCAssignToReg<[V24, V26, V28, V30, V25, V27, V29, V31]>>>
]>;

//===----------------------------------------------------------------------===//
// z/Linux argument calling conventions for GHC
//===----------------------------------------------------------------------===//
def CC_SystemZ_GHC : CallingConv<[
  // Pass in STG registers: Base, Sp, Hp, R1, R2, R3, R4, R5, R6, R7, R8, SpLim
  CCIfType<[i64], CCAssignToReg<[R7D, R8D, R10D, R11D, R12D, R13D,
                                 R6D, R2D, R3D, R4D, R5D, R9D]>>,

  // Pass in STG registers: F1, ..., F6
  CCIfType<[f32], CCAssignToReg<[F8S, F9S, F10S, F11S, F0S, F1S]>>,

  // Pass in STG registers: D1, ..., D6
  CCIfType<[f64], CCAssignToReg<[F12D, F13D, F14D, F15D, F2D, F3D]>>,

  // Pass in STG registers: XMM1, ..., XMM6
  CCIfSubtarget<"hasVector()",
    CCIfType<[v16i8, v8i16, v4i32, v2i64, v4f32, v2f64],
             CCIfFixed<CCAssignToReg<[V16, V17, V18, V19, V20, V21]>>>>,

  // Fail otherwise
  CCCustom<"CC_SystemZ_GHC_Error">
]>;

//===----------------------------------------------------------------------===//
// z/Linux argument calling conventions
//===----------------------------------------------------------------------===//
def CC_SystemZ : CallingConv<[
  CCIfCC<"CallingConv::GHC", CCDelegateTo<CC_SystemZ_GHC>>,

  // Promote i32 to i64 if it has an explicit extension type.
  // The convention is that true integer arguments that are smaller
  // than 64 bits should be marked as extended, but structures that
  // are smaller than 64 bits shouldn't.
  CCIfType<[i32], CCIfExtend<CCPromoteToType<i64>>>,

  // A SwiftSelf is passed in callee-saved R10.
  CCIfSwiftSelf<CCIfType<[i64], CCAssignToReg<[R10D]>>>,

  // A SwiftError is passed in callee-saved R9.
  CCIfSwiftError<CCIfType<[i64], CCAssignToReg<[R9D]>>>,

  // Force long double values to the stack and pass i64 pointers to them.
  CCIfType<[f128], CCPassIndirect<i64>>,
  // Same for i128 values.  These are already split into two i64 here,
  // so we have to use a custom handler.
  CCIfType<[i64], CCCustom<"CC_SystemZ_I128Indirect">>,

  // The first 5 integer arguments are passed in R2-R6.  Note that R6
  // is call-saved.
  CCIfType<[i32], CCAssignToReg<[R2L, R3L, R4L, R5L, R6L]>>,
  CCIfType<[i64], CCAssignToReg<[R2D, R3D, R4D, R5D, R6D]>>,

  // The first 4 float and double arguments are passed in even registers F0-F6.
  CCIfType<[f32], CCAssignToReg<[F0S, F2S, F4S, F6S]>>,
  CCIfType<[f64], CCAssignToReg<[F0D, F2D, F4D, F6D]>>,

  // The first 8 named vector arguments are passed in V24-V31.  Sub-128 vectors
  // are passed in the same way, but they're widened to one of these types
  // during type legalization.
  CCIfSubtarget<"hasVector()",
    CCIfType<[v16i8, v8i16, v4i32, v2i64, v4f32, v2f64],
             CCIfFixed<CCAssignToReg<[V24, V26, V28, V30,
                                      V25, V27, V29, V31]>>>>,

  // However, sub-128 vectors which need to go on the stack occupy just a
  // single 8-byte-aligned 8-byte stack slot.  Pass as i64.
  CCIfSubtarget<"hasVector()",
    CCIfType<[v16i8, v8i16, v4i32, v2i64, v4f32, v2f64],
             CCIfShortVector<CCBitConvertToType<i64>>>>,

  // Other vector arguments are passed in 8-byte-aligned 16-byte stack slots.
  CCIfSubtarget<"hasVector()",
    CCIfType<[v16i8, v8i16, v4i32, v2i64, v4f32, v2f64],
             CCAssignToStack<16, 8>>>,

  // Other arguments are passed in 8-byte-aligned 8-byte stack slots.
  CCIfType<[i32, i64, f32, f64], CCAssignToStack<8, 8>>
]>;

//===----------------------------------------------------------------------===//
// z/Linux callee-saved registers
//===----------------------------------------------------------------------===//
def CSR_SystemZ : CalleeSavedRegs<(add (sequence "R%dD", 6, 15),
                                       (sequence "F%dD", 8, 15))>;

// R9 is used to return SwiftError; remove it from CSR.
def CSR_SystemZ_SwiftError : CalleeSavedRegs<(sub CSR_SystemZ, R9D)>;

// "All registers" as used by the AnyReg calling convention.
// Note that registers 0 and 1 are still defined as intra-call scratch
// registers that may be clobbered e.g. by PLT stubs.
def CSR_SystemZ_AllRegs : CalleeSavedRegs<(add (sequence "R%dD", 2, 15),
                                               (sequence "F%dD", 0, 15))>;
def CSR_SystemZ_AllRegs_Vector : CalleeSavedRegs<(add (sequence "R%dD", 2, 15),
                                                      (sequence "V%d", 0, 31))>;

def CSR_SystemZ_NoRegs : CalleeSavedRegs<(add)>;

