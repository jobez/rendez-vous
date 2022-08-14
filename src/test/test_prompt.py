from functools import reduce
import os
import pytest
from inspect import signature
from starkware.starknet.testing.starknet import Starknet
from asynctest import TestCase
from starkware.crypto.signature.signature import (
    pedersen_hash, private_to_stark_key, sign)
from starkware.starknet.compiler.compile import compile_starknet_files
from utils import hex_to_felt, wrap, str_to_felt 

# The path to the contract source code.
CONTRACT_FILE = os.path.join("contracts", "prompt.cairo")
PRODUCT_ARRAY = [(x, x + 1) for x in range(1, 6, 2)]


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

    # @pytest.mark.asyncio
    # async def test_array_contract(self):
    #     res = await self.contract.test_contract(s_seq=[123456, 7890]).call()
    #     self.assertEqual(
    #         res.call_info.result,
    #         [2, 123456, 7890],
    #         "Contract is still not correct",
    #     )

    @pytest.mark.asyncio
    async def test_prompt(self):
        prompt = str_to_felt("I am not sure if the difference is linear across all potential sentences. I guess the question is how often do these really infinitesmal values occur in embeddings? Is it model dependent?")
        prompt_h = reduce(pedersen_hash, prompt)              
        await self.contract.submit_prompt(prompt_arr=prompt, prompt_hash=prompt_h).invoke()
        res = await self.contract.get_prompt(prompt_h).call()
        prompt.insert(0, len(prompt))
        self.assertEqual(
            res.call_info.result,
            prompt,
            "Contract is still not correct",
        )    

    @pytest.mark.asyncio
    async def test_get_all_prompt(self):
        prompt1 = str_to_felt("life?")
        prompt2 = str_to_felt("death?")
        prompt3 = str_to_felt("How does it rain in Eurasia? Well, I hope.")
        prompt4 = str_to_felt("What do you dream of? Do you lucid dream? Do you remember your dreams?")        
        prompt_h1 = reduce(pedersen_hash, prompt1)
        prompt_h2 = reduce(pedersen_hash, prompt2)
        prompt_h3 = reduce(pedersen_hash, prompt3)
        prompt_h4 = reduce(pedersen_hash, prompt4)                              
        await self.contract.submit_prompt(prompt_arr=prompt1, prompt_hash=prompt_h1).invoke()
        await self.contract.submit_prompt(prompt_arr=prompt2, prompt_hash=prompt_h2).invoke()
        await self.contract.submit_prompt(prompt_arr=prompt3, prompt_hash=prompt_h3).invoke()
        await self.contract.submit_prompt(prompt_arr=prompt4, prompt_hash=prompt_h4).invoke()                
        res = await self.contract.get_all_prompts().call()
        zero_pad = [0]
        result = zero_pad + prompt4  + zero_pad + prompt3 + zero_pad + prompt2 + zero_pad + prompt1
        result.insert(0, len(result))
        self.assertEqual(
            res.call_info.result,
            result,
            "Contract is still not correct",
        )    
        
