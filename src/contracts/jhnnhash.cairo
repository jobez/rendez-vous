%lang starknet

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_label_location  
from starkware.starknet.common.syscalls import get_contract_address, get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.invoke import invoke
from cairo_math_64x61.math64x61 import Math64x61


func get_pedersen{range_check_ptr, pedersen_ptr : HashBuiltin*}(s_seq_len : felt, d_seq: felt*, acc: felt) -> (res: felt):
    alloc_locals
    if s_seq_len == 0: 
        return (acc)
        
    end


    let seq_el : felt = [d_seq]

    let updated_acc : felt = hash2{hash_ptr=pedersen_ptr}(acc, seq_el)


    let recursed_acc : felt = get_pedersen(s_seq_len -1, d_seq+1, updated_acc)
    return (recursed_acc)
end

# func reduce{range_check_ptr, pedersen_ptr : HashBuiltin*}(reducer: felt, s_seq_len : felt, d_seq: felt*, acc: felt) -> (res: felt):
#     alloc_locals
#     if s_seq_len == 0: 
#         return (acc)
        
#     end


#     let seq_el : felt = [d_seq]
    
#     let (reducer_args : felt*) = alloc()
#     assert [reducer_args] = acc
#     assert [reducer_args + 1] = seq_el
#     let updated_acc : felt  = invoke{hash_ptr=pedersen_ptr}(reducer, 2, reducer_args)

#     let recursed_acc : felt = get_pedersen(s_seq_len -1, d_seq+1, updated_acc)
#     return (recursed_acc)
# end

@external
func test_get_pedersen{range_check_ptr, pedersen_ptr : HashBuiltin*}( str: felt) -> (res: felt):

    let (arr : felt*) = alloc()
    assert [arr] = str
    let res : felt = get_pedersen(1, arr, 100)
    return (res)
end


@external
func test_get_pedersen2{range_check_ptr, pedersen_ptr : HashBuiltin*}(str_arr_len: felt, str_arr: felt*, salt : felt) -> (res: felt):
    let hash2_ptr : felt = get_label_location(hash2)

    let res : felt = get_pedersen(str_arr_len, str_arr, salt)
    return (res)
end

