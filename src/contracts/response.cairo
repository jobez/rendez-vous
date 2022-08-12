%lang starknet

from contracts.prompt import write_the_seq_of_short_str_to_storage
from contracts.jhnnvector import cosine_sim
from contracts.jhnnhash import get_pedersen
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_contract_address, get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_not_equal
from cairo_math_64x61.math64x61 import Math64x61

#  prompt storage

@storage_var
func prompt_h_to_commit_response_len(prompt_h : felt) -> (commit_response_len : felt):
end

@storage_var
func prompt_h_to_commit_response_hashes(prompt_h : felt, r_idx : felt) -> (commit_response_hash : felt):
end

# resp storage

struct ResponseDetails:
    member made_by : felt
    member prompt_hash : felt
    member resp_index : felt
    member match_count : felt
end

@storage_var
func resp_h_to_resp_details(resp_h : felt) -> (details : ResponseDetails):
end

@storage_var
func resp_h_to_sentence_embedding_len(resp_h : felt) -> (sentence_embedding_len : felt):
end

@storage_var
func resp_h_to_sentence_embedding(resp_h : felt, se_idx : felt) -> (sentence_embedding_element : felt):
end

# assertions

func commit_hash_check{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(salt: felt, resp_arr_len : felt, resp_arr : felt*, commit_hash : felt):
    let resultant_hash : felt = get_pedersen(resp_arr_len, resp_arr, salt)

    assert commit_hash = resultant_hash
    return ()

end

# functions

func write_se_to_storage{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(resp_h : felt, se_arr_len : felt, se_arr : felt*):

    if se_arr_len == 0:
       return () 
    end
    
    let se_el : felt = [se_arr]
    resp_h_to_sentence_embedding.write(resp_h, se_arr_len, se_el)
    write_se_to_storage(resp_h, se_arr_len - 1, se_arr+1)
    return ()
end


@external
func submit_response{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h : felt, commit_hash : felt, sentence_embedding_arr_len : felt, sentence_embedding_arr : felt*):
    
    let address : felt = get_caller_address()     

    # assoc response to prompt

    let resp_idx : felt = prompt_h_to_commit_response_len.read(prompt_h)
    let next_resp_idx : felt = resp_idx + 1
    prompt_h_to_commit_response_hashes.write(prompt_h, resp_idx, commit_hash)
    prompt_h_to_commit_response_len.write(prompt_h, next_resp_idx)
    %{
    print(f"prompt sanity {ids.prompt_h=} {ids.resp_idx=} {ids.commit_hash=}")
    %}
    # establish details fo response
    let response_details : ResponseDetails = ResponseDetails(address, prompt_h, resp_idx, 0)    
    
    resp_h_to_resp_details.write(commit_hash, response_details)

    # assoc response sentence embedding to resp_h
    resp_h_to_sentence_embedding_len.write(commit_hash, sentence_embedding_arr_len)
    write_se_to_storage(commit_hash, sentence_embedding_arr_len, sentence_embedding_arr)

    return ()
end


func read_responses_for_prompt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h, prompt_resps_arr_len, idx_to_ignore : felt, destination_arr : felt*):

    if prompt_resps_arr_len == idx_to_ignore:
        read_responses_for_prompt(prompt_h, prompt_resps_arr_len-1, idx_to_ignore, destination_arr)
        return ()
    end

    let seq_el : felt = prompt_h_to_commit_response_hashes.read(prompt_h, prompt_resps_arr_len)
    assert [destination_arr] = seq_el
    %{
    print(f"read responses for prompt {ids.seq_el=} {ids.prompt_resps_arr_len=}")
    %}

    
    if prompt_resps_arr_len == 0:
       return () 
    else:
       read_responses_for_prompt(prompt_h, prompt_resps_arr_len-1, idx_to_ignore, destination_arr+1)
    
       return ()
    end


end

@view
func check_matches_for_response_h{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h, salt, response_h, response_arr_len : felt, response_arr : felt*) -> (resp_len : felt, resp : felt*):
    alloc_locals
    let (local destination_arr : felt*) = alloc()
    commit_hash_check(salt, response_arr_len, response_arr, response_h)
    
    let response_details : ResponseDetails = resp_h_to_resp_details.read(response_h)
    let idx_to_ignore : felt = response_details.resp_index
    let resps_l : felt = prompt_h_to_commit_response_len.read(prompt_h)
    %{
    print(f"check matches {ids.prompt_h=} {ids.resps_l=} {ids.idx_to_ignore=}")
    %}

    with_attr error_message ("there are no responses in this prompt!"):
       assert_not_zero(resps_l)
    end

    with_attr error_message ("there are no prompts to compare yours to!"):
        assert_not_equal(resps_l, 1)
    end

    read_responses_for_prompt(prompt_h, resps_l-1, idx_to_ignore, destination_arr)

    return (resps_l - 1, destination_arr)
end




@view 
func view_response() -> (r: felt):
    return (7)
end
    
