/-
Copyright (c) 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
Author(s): Yan Peng
-/
-- PMULL and PMULL2
-- Polynomial arithmetic over {0,1}: https://tiny.amazon.com/5h01fjm6/devearmdocuddi0cApplApplPoly

import Arm.Decode
import Arm.Memory
import Arm.Insts.Common

----------------------------------------------------------------------

namespace DPSFP

open Std.BitVec

def polynomial_mult_aux (i : Nat) (result : BitVec (m+n))
  (op1 : BitVec m) (op2 : BitVec (m+n)) : BitVec (m+n) :=
  if h₀ : i ≥ m then
    result
  else
    let new_res := if extractLsb i i op1 == 1 then result ^^^ (op2 <<< i) else result
    have h : m - (i + 1) < m - i := by omega
    polynomial_mult_aux (i+1) new_res op1 op2
  termination_by polynomial_mult_aux i new_res op1 op2 => (m - i)

def polynomial_mult (op1 : BitVec m) (op2 : BitVec n) : BitVec (m+n) :=
  let result := Std.BitVec.zero (m+n)
  let extended_op2 := zeroExtend (m+n) op2
  polynomial_mult_aux 0 result op1 extended_op2

theorem pmull_op_helper_lemma (x y : Nat) (h : 0 < y):
  x + y - 1 - x + 1 + (x + y - 1 - x + 1) = 2 * x + 2 * y - 1 - 2 * x + 1 := by
  omega

def pmull_op (e : Nat) (esize : Nat) (elements : Nat) (x : BitVec n)
  (y : BitVec n) (result : BitVec (n*2)) (H : esize > 0) : BitVec (n*2) :=
  if h₀ : e ≥ elements then
    result
  else
    let lo := e * esize
    let hi := lo + esize - 1
    let element1 := extractLsb hi lo x
    let element2 := extractLsb hi lo y
    let elem_result := polynomial_mult element1 element2
    let lo2 := 2 * (e * esize)
    let hi2 := lo2 + 2 * esize - 1
    have h₁ : hi - lo + 1 + (hi - lo + 1) = hi2 - lo2 + 1 := by
      simp; apply pmull_op_helper_lemma; simp [*] at *
    let result := BitVec.partInstall hi2 lo2 (h₁ ▸ elem_result) result
    have h₂ : elements - (e + 1) < elements - e := by omega
    pmull_op (e + 1) esize elements x y result H
  termination_by pmull_op e esize elements op x y result => (elements - e)

@[simp]
def exec_pmull (inst : Advanced_simd_three_different_cls) (s : ArmState) : ArmState :=
  -- This function assumes IsFeatureImplemented(FEAT_PMULL) is true
  if inst.size == 0b01#2 || inst.size == 0b10#2 then
    write_err (StateError.Illegal s!"Illegal {inst} encountered!") s
  else
    let esize := 8 <<< inst.size.toNat
    have h₀ : esize > 0 := by
      simp_all only [Nat.shiftLeft_eq, gt_iff_lt, 
                     Nat.zero_lt_succ, mul_pos_iff_of_pos_left, 
                     zero_lt_two, pow_pos]
    let datasize := 64
    let part := inst.Q.toNat
    let elements := datasize / esize
    have h₁ : datasize > 0 := by decide
    let operand1 := Vpart inst.Rn part datasize s h₁
    let operand2 := Vpart inst.Rm part datasize s h₁
    let result :=
      pmull_op 0 esize elements operand1 operand2 (Std.BitVec.zero (2*datasize)) h₀
    let s := write_sfp (datasize*2) inst.Rd result s
    let s := write_pc ((read_pc s) + 4#64) s
    s

@[simp]
def exec_advanced_simd_three_different
  (inst : Advanced_simd_three_different_cls) (s : ArmState) : ArmState :=
  match inst.U, inst.opcode with
  | 0b0#1, 0b1110#4 => exec_pmull inst s
  | _, _ => write_err (StateError.Unimplemented s!"Unsupported instruction {inst} encountered!") s

----------------------------------------------------------------------

partial def Advanced_simd_three_different_cls.pmull.rand : IO (Option (BitVec 32)) := do
  let size := ← BitVec.rand 2
  if size == 0b01#2 || size == 0b10#2 then
    Advanced_simd_three_different_cls.pmull.rand
  else
    let (inst : Advanced_simd_three_different_cls) :=
      { Q := ← BitVec.rand 1
      , U := 0b0#1
      , size := size
      , Rm := ← BitVec.rand 5
      , opcode := 0b1110#4
      , Rn := ← BitVec.rand 5
      , Rd := ← BitVec.rand 5
      }
    pure (some (inst.toBitVec32))

/-- Generate random instructions of Advanced_simd_three_different class. -/
def Advanced_simd_three_different_cls.rand : List (IO (Option (BitVec 32))) :=
  [Advanced_simd_three_different_cls.pmull.rand]

end DPSFP
