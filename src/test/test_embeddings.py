from functools import reduce
import os
import pytest
from inspect import signature
from starkware.starknet.testing.starknet import Starknet
from asynctest import TestCase
from starkware.starknet.compiler.compile import compile_starknet_files

from sentence_transformers import SentenceTransformer, util

# model = SentenceTransformer('all-MiniLM-L6-v2')
model = SentenceTransformer('all-mpnet-base-v2')

CONTRACT_FILE = os.path.join("contracts", "jhnnvector.cairo")

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

sp_1 = ["this is a sentence", "this is also a great sentence"]

spe_1 = model.encode(sp_1)

sp_2 = ["In the beginning was the word.", "What constitutes a beginning?"]

spe_2 = model.encode(sp_2)
class CairoContractTest(TestCase):
    @classmethod
    async def setUp(cls):
        cls.starknet = await Starknet.empty()

        compiled_contract = compile_starknet_files(
            [CONTRACT_FILE], debug_info=True, disable_hint_validation=True
        )
        kwargs = (
            {"contract_def": compiled_contract}
            if "contract_def" in signature(cls.starknet.deploy).parameters
            else {"contract_class": compiled_contract}
        )
        cls.contract = await cls.starknet.deploy(**kwargs)

    @pytest.mark.asyncio
    async def test_cos_sim3(self):
        res = await self.contract.cos_sim_test(a_arr=list(map(to64x61, spe_1[0])),
                                           b_arr=list(map(to64x61, spe_1[1]))).call()
        self.assertEqual(
            from64x61(res.call_info.result.pop()),
            util.cos_sim(spe_1[0], spe_1[1]),
            "Contract is still not correct",
        )

    @pytest.mark.asyncio
    async def test_cos_sim1(self):
        res = await self.contract.cos_sim_test(a_arr=list(map(to64x61, spe_2[0])),
                                           b_arr=list(map(to64x61, spe_2[1]))).call()
        self.assertEqual(
            from64x61(res.call_info.result.pop()),
            util.cos_sim(spe_2[0], spe_2[1]),
            "Contract is still not correct",
        )        
