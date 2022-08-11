%lang starknet

from prompt import write_the_seq_of_short_str_to_storage
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_contract_address, get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from cairo_math_64x61.math64x61 import Math64x61


@view 
func view_response() -> (r: felt):
    return (7)
end
    
