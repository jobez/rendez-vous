%lang starknet

from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_contract_address, get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
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
func submit_prompt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_hash: felt, prompt_arr_len: felt, prompt_arr: felt*):
    let address : felt = get_caller_address() 
    let curr_prompts_idx : felt =  prompts_len.read()
    let iter_prompts_idx : felt = curr_prompts_idx + 1
    let prompt_details = PromptDetails(address, curr_prompts_idx)
    prompt_h_to_details.write(prompt_hash, prompt_details)
    prompts_idx_to_prompt_len.write(curr_prompts_idx, prompt_arr_len)
    prompts_len.write(iter_prompts_idx)
    write_the_seq_of_short_str_to_storage(curr_prompts_idx, prompt_arr_len, prompt_arr)
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
    let p_length : felt = prompts_idx_to_prompt_len.read(p_idx)
    %{
        print(f"Printing {ids.p_idx=} {ids.p_length=} ") 
    %}
    read_the_seq_of_short_str_from_storage(p_idx, p_length, p_array)


    return (p_length, p_array)    
end

