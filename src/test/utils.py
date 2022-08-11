import re

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
