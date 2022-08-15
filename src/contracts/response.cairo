%lang starknet

from contracts.prompt import write_the_seq_of_short_str_to_storage, prompt_h_to_details, PromptDetails
from contracts.jhnnvector import cosine_sim
from contracts.jhnnhash import get_pedersen
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_contract_address, get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.math import assert_not_zero, assert_not_equal
from cairo_math_64x61.math64x61 import Math64x61

@contract_interface
namespace IXoroshiro:
    func next() -> (rnd : felt):
    end
end

@storage_var
func xoroshiro_address() -> (address : felt):
end

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

# match storage

struct MatchDetails:
    member a_match_hash : felt
    member b_match_hash : felt
    member similarity: felt
end

struct MatchCache:
    # idx where cache is valid
    member prompt_idx : felt
    member cache_len : felt
end

@storage_var
func resp_h_to_cache_detail(resp_h: felt) -> (detail : MatchCache):
end

@storage_var 
func resp_h_to_match_h(resp_h: felt, idx: felt) -> (match_h : felt):
end

@storage_var
func match_h_to_match_detail(match_h : felt) -> (match_d : MatchDetails):
end

# rendezvous storage

struct DirMatchDetails:
    member rendez_vous: felt
    member signed_message_hash: felt
    member signed_message_length: felt
end


@storage_var
func directed_match_to_details(directed_match_hash : felt) -> (dir_match_details : DirMatchDetails):
end

@storage_var
func match_to_disclosure_count(match_hash : felt) -> (match_count : felt):
end

@storage_var
func signed_message_hash_to_signed_message(signed_message_hash : felt, signed_message_idx) -> (signed_message_el : felt):
end

# assertions

func commit_hash_check{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(salt: felt, resp_arr_len : felt, resp_arr : felt*, commit_hash : felt):
    let resultant_hash : felt = get_pedersen(resp_arr_len, resp_arr, salt)

    assert commit_hash = resultant_hash
    return ()

end

func rendez_vous_check{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(sender, receiver : felt) -> (signed_message_hash, signed_message_length, signed_message_key : felt):
    let sender_sends_to_receiver : felt = hash2{hash_ptr=pedersen_ptr}(sender, receiver)  

    let rendez_vous_details : DirMatchDetails = directed_match_to_details.read(sender_sends_to_receiver)

    let signed_message_hash : felt = rendez_vous_details.signed_message_hash
    let signed_message_length : felt = rendez_vous_details.signed_message_length    

    with_attr error_message ("arrangements have not been from #{sender} to #{receiver}. if #{sender} is yours, make arrangements by calling `arrange_rendez_vous`"):
        assert_not_zero(signed_message_hash)
        assert_not_zero(signed_message_length)
    end

    return (signed_message_hash, signed_message_length, rendez_vous_details.rendez_vous)
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

func read_responses_for_prompt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h, prompt_resps_arr_len, idx_to_ignore : felt, destination_arr : felt*):

     %{
    print(f"read responses for prompt entry {ids.idx_to_ignore=} {ids.prompt_resps_arr_len=}")
    %}
    
    if prompt_resps_arr_len == 0:
        %{
    print(f"read responses on zero {ids.idx_to_ignore=} {ids.prompt_resps_arr_len=}")
        %}
        return ()
    end

    if prompt_resps_arr_len == idx_to_ignore:
      read_responses_for_prompt(prompt_h, prompt_resps_arr_len-1, idx_to_ignore, destination_arr)
      tempvar syscall_ptr=syscall_ptr
      tempvar pedersen_ptr=pedersen_ptr
      tempvar range_check_ptr=range_check_ptr
      return ()  
    else:

      tempvar syscall_ptr=syscall_ptr
      tempvar pedersen_ptr=pedersen_ptr
      tempvar range_check_ptr=range_check_ptr
    end

    %{
    print(f"read responses for prompt {ids.idx_to_ignore=} {ids.prompt_resps_arr_len=}")
    %}
    let seq_el : felt = prompt_h_to_commit_response_hashes.read(prompt_h, prompt_resps_arr_len)
    assert [destination_arr] = seq_el


    
    read_responses_for_prompt(prompt_h, prompt_resps_arr_len-1, idx_to_ignore, destination_arr+1)
    
    return()
end

# can this be folded up/abstracted? potentially via some experimentation with https://gist.github.com/fracek/846d3082f9803a7e65edc44292da9241
func read_sentence_embedding_from_storage{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(resp_h: felt, se_len : felt, d_seq: felt*):
    if se_len == 0:
       return ()
    end

    let encoded_1 : felt = Math64x61.fromFelt(1)    
    let seq_el : felt = resp_h_to_sentence_embedding.read(resp_h, se_len)
    let removed_one : felt = Math64x61.sub(seq_el, encoded_1)
    assert [d_seq] = removed_one
    read_sentence_embedding_from_storage(resp_h, se_len-1, d_seq+1)
    return ()
end

@external
func compare_resp_to_resp{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(resp_h1, resp_h2: felt) -> (cos_sim: felt):
    alloc_locals
    let (local resp1 : felt*) = alloc()
    let (local resp2 : felt*) = alloc()
    let resp_h1_se_len : felt = resp_h_to_sentence_embedding_len.read(resp_h1)
    let resp_h2_se_len : felt = resp_h_to_sentence_embedding_len.read(resp_h2)

    with_attr error_message ("sentence embeddings aren't the same length! did you use the same model to encode them?"):
       assert resp_h1_se_len = resp_h2_se_len
    end
    
    read_sentence_embedding_from_storage(resp_h1, resp_h1_se_len, resp1)
    read_sentence_embedding_from_storage(resp_h2, resp_h2_se_len, resp2)

    let (sim : felt) = cosine_sim(resp_h1_se_len, resp1, resp_h2_se_len, resp2)    

    return (sim)

end

@external
func _compare_resp_to_resp{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(resp_h2: felt, resp_h1_se_len: felt, resp_h1_se : felt*) -> (cos_sim: felt):
    alloc_locals

    let (local resp2 : felt*) = alloc()
    let resp_h2_se_len : felt = resp_h_to_sentence_embedding_len.read(resp_h2)
    %{
    print(f"compare resp to resp {ids.resp_h1_se_len=} {ids.resp_h2_se_len=} {ids.resp_h2=} ")
    %}
    with_attr error_message ("sentence embeddings aren't the same length! did you use the same model to encode them?"):
       assert resp_h1_se_len = resp_h2_se_len
    end
    
    read_sentence_embedding_from_storage(resp_h2, resp_h2_se_len, resp2)

    let (sim : felt) = cosine_sim(resp_h1_se_len, resp_h1_se, resp_h2_se_len, resp2)    

    return (sim)

end

# this implementation re-reads the lhs resp for each comparison. 
# OPTIMIZATION: rewrite where this happens once and is passed down
func compare_resp_to_resps{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(thres_num, thres_denom, resp_h, resp1_se_len, resp_hs_len : felt,  resp1_se_arr: felt*, resp_hs: felt*, match_hs_len: felt, match_hs: MatchDetails* ) -> (match_hs_len: felt):
    alloc_locals
    if resp_hs_len == 0:
        return (match_hs_len)
    end

    let resp_h2 : felt = [resp_hs]
    let (sim : felt) = _compare_resp_to_resp(resp_h2, resp1_se_len, resp1_se_arr)

    let encoded_num : felt = Math64x61.fromFelt(thres_num)
    let encoded_denom : felt = Math64x61.fromFelt(thres_denom)
    let threshold : felt = Math64x61.div(encoded_num, encoded_denom)
    %{
    print(f"check matches {ids.sim=} {ids.threshold=}")
    %}
    let sim_meets_threshold : felt = is_le(threshold, sim)
    if sim_meets_threshold == 1 :
      let match_detail = MatchDetails(resp_h,resp_h2, sim)  
      assert [match_hs] = match_detail
      let (updated_match_hs_len : felt) = compare_resp_to_resps(thres_num, thres_denom, resp_h, resp1_se_len, resp_hs_len-1, resp1_se_arr, resp_hs+1, match_hs_len+1, match_hs+1)
      return (updated_match_hs_len)
    else:
      let (updated_match_hs_len : felt) = compare_resp_to_resps(thres_num, thres_denom,resp_h, resp1_se_len,resp_hs_len-1, resp1_se_arr, resp_hs+1, match_hs_len, match_hs)
      return (updated_match_hs_len)        
    end
    
end

func _get_cached_matches{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(response_h, cache_len : felt, matches_arr : MatchDetails*):
    if cache_len == 0:
        return ()
    end

    let match_hash : felt = resp_h_to_match_h.read(response_h, cache_len)
    let match_detail : MatchDetails = match_h_to_match_detail.read(match_hash)
    assert [matches_arr] = match_detail
    
    _get_cached_matches(response_h, cache_len-1, matches_arr)
    return ()
end

func _get_matches_for_response_h{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h, response_h : felt) -> (resp_len : felt, resp : MatchDetails*):
    alloc_locals
    let (local resps_arr : felt*) = alloc()
    let (local matches_arr : MatchDetails*) = alloc()

    let response_details : ResponseDetails = resp_h_to_resp_details.read(response_h)
    let author_of_record : felt = response_details.made_by

#  assert conceived author is actual author
    let idx_to_ignore : felt = response_details.resp_index
    let prompt_details : PromptDetails = prompt_h_to_details.read(prompt_h)
    let prompt_thres_num : felt = prompt_details.thres_num
    let prompt_thres_denom : felt = prompt_details.thres_denom
    let resps_l : felt = prompt_h_to_commit_response_len.read(prompt_h)
    %{
    print(f"get matches for response h {ids.prompt_h=} {ids.resps_l=} {ids.idx_to_ignore=}")
    %}

    with_attr error_message ("there are no responses in this prompt!"):
       assert_not_zero(resps_l)
    end

    with_attr error_message ("there are no prompts to compare yours to!"):
        assert_not_equal(resps_l, 1)
    end

    let match_cache : MatchCache = resp_h_to_cache_detail.read(response_h)


    # if resps_l == match_cache.prompt_idx:
    #    let cache_len : felt = match_cache.cache_len
    #     %{
    #     print(f"cache hit {ids.cache_len=}")
    #     %}

    #    _get_cached_matches(response_h, cache_len, matches_arr)
    #     return (cache_len, matches_arr)
    # end

   %{
    print(f"before read_responses_for_prompt {ids.resps_l=}")
    %}
    read_responses_for_prompt(prompt_h, resps_l, idx_to_ignore, resps_arr)

    let (local resp1_se : felt*) = alloc()    
    let resp_h1_se_len : felt = resp_h_to_sentence_embedding_len.read(response_h)
    read_sentence_embedding_from_storage(response_h, resp_h1_se_len, resp1_se)

    # resps_l is decremented because we ignore self-same element
    let (matches_arr_len : felt) =  compare_resp_to_resps(prompt_thres_num, prompt_thres_denom, response_h, resp_h1_se_len, resps_l-1, resp1_se, resps_arr, 0, matches_arr)

    return (matches_arr_len, matches_arr)
end


@view 
func responses_for_prompt_h{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h : felt) -> (r_len: felt, r : felt*):
    alloc_locals
    let (local destination_arr : felt*) = alloc()
    let resps_l : felt = prompt_h_to_commit_response_len.read(prompt_h)

    read_responses_for_prompt(prompt_h, resps_l, -1, destination_arr)

    return (resps_l, destination_arr)
end


@external
func submit_response{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h : felt, commit_hash : felt, sentence_embedding_arr_len : felt, sentence_embedding_arr : felt*):
#    alloc_locals
    let address : felt = get_caller_address()     

    # assoc response to prompt

    let last_idx : felt = prompt_h_to_commit_response_len.read(prompt_h)
    let resp_idx : felt = last_idx + 1
    prompt_h_to_commit_response_hashes.write(prompt_h, resp_idx, commit_hash)
    prompt_h_to_commit_response_len.write(prompt_h, resp_idx)
    %{
    print(f"submit response {ids.prompt_h=} {ids.resp_idx=} {ids.commit_hash=}")
    %}
    # establish details fo response
    let response_details : ResponseDetails = ResponseDetails(address, prompt_h, resp_idx, 0)    
    
    resp_h_to_resp_details.write(commit_hash, response_details)

    # assoc response sentence embedding to resp_h
    resp_h_to_sentence_embedding_len.write(commit_hash, sentence_embedding_arr_len)
    write_se_to_storage(commit_hash, sentence_embedding_arr_len, sentence_embedding_arr)
    # let possible_to_match : felt = is_le(1, resp_idx)
    # if possible_to_match == 1:
    #     
    #    tempvar syscall_ptr=syscall_ptr
    #    tempvar pedersen_ptr=pedersen_ptr
    # else:
    #    tempvar syscall_ptr=syscall_ptr
    #    tempvar pedersen_ptr=pedersen_ptr                                            

    # end

    return ()
end

func make_directed_hash{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(response_h : felt, match_detail : MatchDetails) -> (directed_hash : felt):
    let a_match_hash : felt = match_detail.a_match_hash
    let b_match_hash : felt = match_detail.b_match_hash

    if a_match_hash == response_h:
        let d_hash : felt = hash2{hash_ptr=pedersen_ptr}(response_h, b_match_hash)
        return (d_hash)
    else:
        let d_hash : felt = hash2{hash_ptr=pedersen_ptr}(response_h, a_match_hash)
        return (d_hash)
    end

end

func make_match_hash{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(match_detail : MatchDetails) -> (match_hash : felt):
    let a_match_hash : felt = match_detail.a_match_hash
    let b_match_hash : felt = match_detail.b_match_hash

    return (a_match_hash + b_match_hash)
end

func write_rendez_vous_junctions{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h, response_h, matches_arr_l : felt, matches_arr : MatchDetails*):
    if matches_arr_l == 0:
       return ()
    end
    
    let match_detail : MatchDetails = [matches_arr]
    let directed_match_hash : felt = make_directed_hash(response_h, match_detail)
    let rendez_vous_details : DirMatchDetails = directed_match_to_details.read(directed_match_hash)
    let rendez_vous_detail : felt = rendez_vous_details.rendez_vous
    let rendez_vous_assigned_p : felt  = is_not_zero(rendez_vous_detail)
    
    if rendez_vous_assigned_p == 0:
        let xoroshiro_addr : felt = xoroshiro_address.read()

        let match_hash : felt = make_match_hash(match_detail)
        let match_cache : MatchCache = resp_h_to_cache_detail.read(response_h)
        let cache_valid_idx : felt =     prompt_h_to_commit_response_len.read(prompt_h)
        let updated_cache_len : felt = match_cache.cache_len + 1
        let updated_match_cache : MatchCache = MatchCache(cache_valid_idx, updated_cache_len)
        resp_h_to_cache_detail.write(response_h, updated_match_cache)

        resp_h_to_match_h.write(response_h, updated_cache_len, match_hash)

        match_h_to_match_detail.write(match_hash, match_detail)

        let (rnd : felt ) = IXoroshiro.next(contract_address=xoroshiro_addr)
        let rendez_vous_details : DirMatchDetails = DirMatchDetails(rnd, 0, 0)        
        directed_match_to_details.write(directed_match_hash, rendez_vous_details)
        tempvar syscall_ptr=syscall_ptr
        tempvar pedersen_ptr=pedersen_ptr
        tempvar range_check_ptr=range_check_ptr
    else:
        tempvar syscall_ptr=syscall_ptr
        tempvar pedersen_ptr=pedersen_ptr
        tempvar range_check_ptr=range_check_ptr        
    end
    
    write_rendez_vous_junctions(prompt_h, response_h, matches_arr_l-1, matches_arr+1)

    return ()
end


@external
func arrange_rendez_vous{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h, response_h: felt):

    let (matches_arr_l : felt, matches_arr : MatchDetails*) = _get_matches_for_response_h(prompt_h, response_h)

    write_rendez_vous_junctions(prompt_h, response_h, matches_arr_l, matches_arr)

  
    return ()
end

@view
func check_matches_for_response_h{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h, salt, response_h, response_arr_len : felt, response_arr : felt*) -> (resp_len : felt, resp : MatchDetails*):

    commit_hash_check(salt, response_arr_len, response_arr, response_h)
    let (matches_arr_l : felt, matches_arr : MatchDetails*) = _get_matches_for_response_h(prompt_h, response_h)

    return (matches_arr_l, matches_arr)
end



@view
func get_rendez_vous_detail{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h, salt, response_h, response_arr_len : felt, response_arr : felt*, their_response_h : felt) -> (rendez_vous_detail : felt):
    commit_hash_check(salt, response_arr_len, response_arr, response_h)


    let directed_match_hash : felt = hash2{hash_ptr=pedersen_ptr}(response_h, their_response_h)  

    let rendez_vous_details : DirMatchDetails = directed_match_to_details.read(directed_match_hash)
    let rendez_vous_detail : felt = rendez_vous_details.rendez_vous

    %{
    print(f"get rendez vous detail  {ids.response_h=} {ids.their_response_h=} ")
    %}


    with_attr error_message ("arrangements have not been made! call 'arrange_rendez_vous' if you are sure this is a match"):
        assert_not_zero(rendez_vous_detail)
    end

    return (rendez_vous_detail)
end


func write_sm_to_storage{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(signed_message_h : felt, sm_arr_len : felt, sm_arr : felt*):
    if sm_arr_len == 0:
       return () 
    end

    
    let sm_el : felt = [sm_arr]
    signed_message_hash_to_signed_message.write(signed_message_h, sm_arr_len, sm_el)
   %{
    print(f"write sm to storage {ids.sm_arr_len=} ")
    %}
   
    write_sm_to_storage(signed_message_h, sm_arr_len - 1, sm_arr+1)
    
    return ()


end


@external 
func submit_response_for_match{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h, response_h, match_h, encr_arr_hash, encr_arr_len : felt, encr_arr : felt*):
    let address : felt = get_caller_address()     

    let directed_match_hash : felt = hash2{hash_ptr=pedersen_ptr}(response_h, match_h)  
    #todo assert caller made the response h    

    let rendez_vous_details : DirMatchDetails = directed_match_to_details.read(directed_match_hash)
    
    with_attr error_message ("a response has been submitted!"):
        assert rendez_vous_details.signed_message_hash = 0
        assert rendez_vous_details.signed_message_length = 0
    end
    let rendez_vous_details : DirMatchDetails = DirMatchDetails(rendez_vous_details.rendez_vous, encr_arr_hash, encr_arr_len)
    %{
    print(f"submit response for match   {ids.encr_arr_len=} ")
    %}
    directed_match_to_details.write(directed_match_hash, rendez_vous_details)
    write_sm_to_storage(encr_arr_hash, encr_arr_len, encr_arr)
    return ()
end

func read_sm_from_storage{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(resp_h: felt, se_len : felt, d_seq: felt*):
    if se_len == 0:
       return ()
    end
   %{
    print(f"read sm from storage {ids.se_len} ")
    %}
    let seq_el : felt = signed_message_hash_to_signed_message.read(resp_h, se_len)
    assert [d_seq] = seq_el
    read_sm_from_storage(resp_h, se_len-1, d_seq+1)
    return ()
end

@view
func get_rendez_vous{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(prompt_h, salt, response_h, response_arr_len : felt, response_arr : felt*, their_response_h : felt) -> ( rendez_vous_detail : felt, rendez_vous_arr_len, rendez_vous_arr : felt*):

    alloc_locals
    let (local sm_arr : felt*) = alloc()
    commit_hash_check(salt, response_arr_len, response_arr, response_h)

    # the case where i disclose my signed message to matchee
    rendez_vous_check(response_h, their_response_h) 
    # the case where the matchee disclosse their signed message to me
let (signed_message_hash, signed_message_length, signed_message_key : felt) = rendez_vous_check(their_response_h, response_h) 
   %{
    print(f"get rv {ids.signed_message_key} ")
    %}
    read_sm_from_storage(signed_message_hash, signed_message_length, sm_arr)
    return (signed_message_key, signed_message_length, sm_arr)
end
    
@constructor
func constructor{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(x128_ss_contract_addr : felt):
    xoroshiro_address.write(x128_ss_contract_addr)
    return ()
end
