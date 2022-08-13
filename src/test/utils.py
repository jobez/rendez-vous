import re
from functools import reduce
from starkware.crypto.signature.signature import (
    pedersen_hash, private_to_stark_key, sign)
from sentence_transformers import SentenceTransformer, util

# model = SentenceTransformer('all-MiniLM-L6-v2')
model = SentenceTransformer('all-mpnet-base-v2')

MAX_LEN_FELT = 31

def hex_to_felt(val):
    return int(val, 16)

def wrap(s, w):    
    sre = re.compile(rf'(.{{{w}}})')
    return [x for x in re.split(sre, s) if x]

def single_str_to_felt(text):
    if len(text) > MAX_LEN_FELT:
        raise Exception("Text length too long to convert to felt.")

    return int.from_bytes(text.encode(), "big")

def str_to_felt(text):
    return list(map(single_str_to_felt, wrap(text, 31)))

def felt_to_str(felt):
    length = (felt.bit_length() + 7) // 8
    return felt.to_bytes(length, byteorder="big").decode("utf-8")

SCALE = 2 ** 61
PRIME = 3618502788666131213697322783095070105623107215331596699973092056135872020481
PRIME_HALF = PRIME / 2
PI = 7244019458077122842

def from64x61(num):
    res = PRIME - num if num > PRIME_HALF else num
    return res / SCALE

def to64x61(num):
    res = num * SCALE
    if res > 2 ** 125 or res < (2 ** 125) * -1:
       raise Exception("Number is out of valid range")
    return int(res)

def raw_resp_to_resp(raw_resp):
    resp_embedding = model.encode([raw_resp])[0]
    resp2 = str_to_felt(raw_resp)
    resp2.insert(0, 100)
    resp_h = reduce(pedersen_hash, resp2)
    resp = str_to_felt(raw_resp)
    return [resp, resp_embedding, resp_h]

def raw_prompt_to_prompt(raw_prompt):
    prompt = str_to_felt(raw_prompt)
    prompt_h = reduce(pedersen_hash, prompt)
    return [prompt, prompt_h]
