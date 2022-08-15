%lang starknet

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_label_location  
from starkware.starknet.common.syscalls import get_contract_address, get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.hash import hash2
from cairo_math_64x61.math64x61 import Math64x61

func add_until{range_check_ptr}(s_seq_len : felt, d_seq: felt*, acc: felt) -> (res: felt):
    if s_seq_len == 0: 
        return (acc)
    end

    let seq_el : felt = [d_seq]
    let updated_acc : felt = Math64x61.add(seq_el, acc)
   # %{
   #      print(f"{ids.seq_el=}") 
   #      print(f"{ids.seq_el_squared=}") 
   #      print(f"{ids.updated_acc=}") 
   #  %}

    let recursed_acc : felt = add_until(s_seq_len -1, d_seq+1, updated_acc)
    return (recursed_acc)
end

@external
func test_add_until{range_check_ptr}( arr_len: felt, arr: felt*) -> (res: felt):
    let res : felt = add_until(10, arr, 0)
    return (res)
end

func norm{range_check_ptr}(s_seq_len : felt, d_seq: felt*, acc: felt) -> (res: felt):
    if s_seq_len == 0:
       return Math64x61.sqrt(acc)
    end

    let seq_el : felt = [d_seq]
    let seq_el_squared : felt  = Math64x61.mul(seq_el, seq_el)
    let updated_acc : felt = Math64x61.add(seq_el_squared, acc)
   # %{
   #      print(f"{ids.seq_el=}") 
   #      print(f"{ids.seq_el_squared=}") 
   #      print(f"{ids.updated_acc=}") 
   #  %}

    let recursed_acc : felt = norm(s_seq_len -1, d_seq+1, updated_acc)
    return (recursed_acc)
end

func dot{range_check_ptr}(s_seq_len : felt, a_seq: felt*, b_seq: felt*, acc: felt) -> (res: felt):
    if s_seq_len == 0:
       return (acc)
    end

    let a_seq_el : felt = [a_seq]
    let b_seq_el : felt = [b_seq]
    let seq_el_multipied : felt  = Math64x61.mul(a_seq_el, b_seq_el)
    let updated_acc : felt = Math64x61.add(seq_el_multipied, acc)
  

    let recursed_acc : felt = dot(s_seq_len -1, a_seq+1, b_seq+1, updated_acc)
    return (recursed_acc)
end

func cosine_sim{range_check_ptr}(a_arr_len: felt, a_arr: felt*, b_arr_len: felt, b_arr: felt*) -> (sim: felt):
    alloc_locals
    let norm_a : felt  = norm(a_arr_len, a_arr, 0)
    let norm_b : felt  = norm(b_arr_len, b_arr, 0)
    let norm_multiplied : felt = Math64x61.mul(norm_a, norm_b)
    let dot_a_b : felt = dot(a_arr_len, a_arr, b_arr, 0)
    let cos_sim : felt = Math64x61.div(dot_a_b, norm_multiplied)
    return (cos_sim)
end
  
@external
func norm_test{range_check_ptr}( arr_len: felt, arr: felt*) -> (res: felt):
       let norm_res : felt = norm(arr_len, arr, 0)
    return (norm_res)
end

@external
func dot_test{range_check_ptr}(a_arr_len: felt, a_arr: felt*, b_arr_len: felt, b_arr: felt*) -> (res: felt):
    assert_not_zero(a_arr_len)
    assert a_arr_len = b_arr_len
    let dot_res : felt = dot(a_arr_len, a_arr, b_arr, 0)
    return (dot_res)
end

@external
func cos_sim_test{range_check_ptr}(a_arr_len: felt, a_arr: felt*, b_arr_len: felt, b_arr: felt*) -> (res: felt):
    assert_not_zero(a_arr_len)
    assert a_arr_len = b_arr_len
    let dot_res : felt = cosine_sim(a_arr_len, a_arr, b_arr_len, b_arr)
    return (dot_res)
end

