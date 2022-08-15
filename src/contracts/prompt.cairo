%lang starknet

from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_contract_address, get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_le
from cairo_math_64x61.math64x61 import Math64x61

const XOROSHIRO_ADDR = 0x06c4cab9afab0ce564c45e85fe9a7aa7e655a7e0fd53b7aea732814f3a64fbee

@contract_interface
namespace IXoroshiro:
    func next() -> (rnd : felt):
    end
end

struct PromptDetails:
    member incited_by : felt
    member prompt_idx : felt
    member thres_num : felt
    member thres_denom : felt
end


@storage_var
func prompt_h_to_details(prompt_h : felt) -> (details : PromptDetails):
end


@storage_var
func prompts_idx_to_prompt_len(prompt_idx : felt) -> (prompt_len : felt):
end

@storage_var
func prompts_len() -> (whole_idx : felt):
end

@storage_var
func prompts(whole_idx : felt, part_idx : felt) -> (prompt_seg: felt):
end


func write_the_seq_of_short_str_to_storage{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(whole_idx : felt, s_seq_len : felt, s_seq: felt*):
    if s_seq_len == 0:
       return ()
    end

    let seq_el : felt = [s_seq]
    prompts.write(whole_idx, s_seq_len, seq_el)
    write_the_seq_of_short_str_to_storage(whole_idx, s_seq_len -1, s_seq+1)
    return ()
end


@external
func submit_prompt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_hash: felt, thres_num, thres_denom, prompt_arr_len: felt, prompt_arr: felt*):
    let address : felt = get_caller_address() 
    let curr_prompts_idx : felt =  prompts_len.read()
    let iter_prompts_idx : felt = curr_prompts_idx + 1

    with_attr error_message ("a prompt can only have two responses"):
        assert_le(iter_prompts_idx, 3)
    end

  
    let prompt_details = PromptDetails(address, iter_prompts_idx, thres_num, thres_denom)
    prompt_h_to_details.write(prompt_hash, prompt_details)
    prompts_idx_to_prompt_len.write(iter_prompts_idx, prompt_arr_len)
    prompts_len.write(iter_prompts_idx)
    write_the_seq_of_short_str_to_storage(iter_prompts_idx, prompt_arr_len, prompt_arr)
    return ()
end

func read_the_seq_of_short_str_from_storage{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(p_idx: felt, s_seq_len : felt, d_seq: felt*):
    if s_seq_len == 0:
       return ()
    end

    let seq_el : felt = prompts.read(p_idx, s_seq_len)
    assert [d_seq] = seq_el
    read_the_seq_of_short_str_from_storage(p_idx, s_seq_len -1, d_seq+1)
    return ()
end

@view 
func get_prompt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_hash : felt) -> (ss_len: felt, ss: felt*):
    alloc_locals
    let (local p_array : felt*) = alloc()
    let p_details : PromptDetails = prompt_h_to_details.read(prompt_hash)
    let p_idx : felt = p_details.prompt_idx
    let incited_by : felt = p_details.incited_by

    with_attr error_message ("prompt_h doesn't exist"):
        assert_not_zero(incited_by)
    end
    

    let p_length : felt = prompts_idx_to_prompt_len.read(p_idx)
    %{
        print(f"Printing {ids.p_idx=} {ids.p_length=} ") 
    %}
    read_the_seq_of_short_str_from_storage(p_idx, p_length, p_array)


    return (p_length, p_array)    
end

func inner_get_prompt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_idx, prompt_len, dest_arr_l : felt,  dest_arr : felt*) -> (dest_len : felt):
     alloc_locals
     if prompt_len == 0:
        return (dest_arr_l)
     end

     let prompt_el : felt = prompts.read(prompt_idx, prompt_len)
     assert [dest_arr] = prompt_el

     %{
    print(f"inner get prompt {ids.prompt_idx=} {ids.prompt_el=} ")
    %}
     let updated_dest_arr : felt = inner_get_prompt(prompt_idx, prompt_len-1, dest_arr_l+1, dest_arr+1)          
     return (updated_dest_arr)
end

func outer_get_prompts{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(curr_prompts_idx, dest_arr_l : felt,  dest_arr : felt*) -> (dest_len : felt):
     alloc_locals

     if curr_prompts_idx == 0:
        return (dest_arr_l)
     end

     
     let this_prompts_len : felt = prompts_idx_to_prompt_len.read(curr_prompts_idx)


     let inc_by : felt = this_prompts_len+1
     
    %{
    print(f"outer get prompt {ids.curr_prompts_idx=} {ids.this_prompts_len=} ")
    %}


     let updated_dest_arr_l : felt = inner_get_prompt(curr_prompts_idx, this_prompts_len, dest_arr_l+1, dest_arr+1)

     assert [dest_arr] = 0

let updated_dest_arr_l_ : felt =  outer_get_prompts(curr_prompts_idx-1, updated_dest_arr_l,  dest_arr+inc_by)
     return (updated_dest_arr_l_)                                          
end
@view
func get_all_prompts{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (p_arr_len : felt, p_arr : felt*):
    alloc_locals
    let (local dest_arr : felt*) = alloc()
    let total_prompts : felt = prompts_len.read()
    let dest_prompt_len : felt = outer_get_prompts(total_prompts, 0, dest_arr) 
    return (dest_prompt_len, dest_arr)
end
