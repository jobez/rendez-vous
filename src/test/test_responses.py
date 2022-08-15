from functools import reduce
import os
import pytest
from pytest import approx
from inspect import signature
from starkware.starknet.testing.starknet import Starknet
from asynctest import TestCase
from starkware.crypto.signature.signature import (
    pedersen_hash, private_to_stark_key, sign)
from starkware.starknet.compiler.compile import compile_starknet_files
from utils import hex_to_felt, wrap, str_to_felt, to64x61, raw_resp_to_resp, raw_prompt_to_prompt, from64x61
from sentence_transformers import SentenceTransformer, util
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad
from base64 import b64encode, b64decode
from Crypto.Random import get_random_bytes
import binascii


# The path to the contract source code.
CONTRACT_FILE = os.path.join("contracts", "response.cairo")

CONTRACT_FILE0 = os.path.join("contracts", "libs", "xoroshiro128_starstar.cairo")


class CairoContractTest(TestCase):
    @classmethod
    async def setUp(cls):
        cls.starknet = await Starknet.empty()

        compiled_contract = compile_starknet_files(
            [CONTRACT_FILE], debug_info=True, disable_hint_validation=True
        )
        compiled_contract1 = compile_starknet_files(
            [CONTRACT_FILE0], debug_info=True, disable_hint_validation=True
        )
        

        kwargs1 = (
            {"contract_def": compiled_contract1, "constructor_calldata": [42]}
            if "contract_def" in signature(cls.starknet.deploy).parameters
            else {"contract_class": compiled_contract1, "constructor_calldata": [42]}
        )
        cls.x128_ss = await cls.starknet.deploy(**kwargs1)

        kwargs0 = (
            {"contract_def": compiled_contract, "constructor_calldata": [0]}
            if "contract_def" in signature(cls.starknet.deploy).parameters
            else {"contract_class": compiled_contract, "constructor_calldata": [getattr(cls.x128_ss, "contract_address")]}
        )
        cls.contract = await cls.starknet.deploy(**kwargs0)


    # @pytest.mark.asyncio
    # async def test_array_contract(self):
    #     res = await self.contract.test_contract(s_seq=[123456, 7890]).call()
    #     self.assertEqual(
    #         res.call_info.result,
    #         [2, 123456, 7890],
    #         "Contract is still not correct",
    #     )

    @pytest.mark.asyncio
    async def test_response(self):
        [prompt, prompt_h] = raw_prompt_to_prompt("What is love?")
        [resp0, resp_embedding, resp_h] = raw_resp_to_resp("Love is a feeling.")
        [resp1, resp_embedding1, resp_h1] = raw_resp_to_resp("I am not sure, but I would rather talk about lasagna.")
        await self.contract.submit_prompt(prompt_arr=prompt, prompt_hash=prompt_h).invoke()
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h, sentence_embedding_arr=list(map(to64x61, resp_embedding))).invoke()
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h1, sentence_embedding_arr=list(map(to64x61, resp_embedding1))).invoke()

        res = await self.contract.check_matches_for_response_h(prompt_h=prompt_h, salt=100, response_h=resp_h1, response_arr=resp1).call()
        self.assertEqual(
            res.call_info.result,
            [1, resp_h],
            "Contract is still not correct",
        )

    @pytest.mark.asyncio
    async def test_response2(self):
        [prompt, prompt_h] = raw_prompt_to_prompt("What is love?")
        [resp0, resp_embedding, resp_h] = raw_resp_to_resp("Love is a feeling.")
        [resp1, resp_embedding1, resp_h1] = raw_resp_to_resp("Love is a feeling of grace.")
        [resp2, resp_embedding2, resp_h2] = raw_resp_to_resp("I am not sure, but I would rather talk about lasagna.")        
        await self.contract.submit_prompt(prompt_arr=prompt, prompt_hash=prompt_h).invoke()
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h, sentence_embedding_arr=list(map(to64x61, resp_embedding))).invoke()
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h2, sentence_embedding_arr=list(map(to64x61, resp_embedding2))).invoke()        
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h1, sentence_embedding_arr=list(map(to64x61, resp_embedding1))).invoke()
        
        res = await self.contract.check_matches_for_response_h(prompt_h=prompt_h, salt=100, response_h=resp_h1, response_arr=resp1).call()
        result = res.call_info.result
        print(result)
        self.assertEqual(
            result,
            [1, resp_h, 1537228672809129301, 0],
            "Contract is still not correct",
        )        

    @pytest.mark.asyncio
    async def test_response3(self):

        thres_num = 2
        thres_denom = 3
        
        [prompt, prompt_h] = raw_prompt_to_prompt("What is love?")

        match0_response = "Love is a feeling."
        match1_response = "Love is a feeling of grace."
        [resp0, resp_embedding, resp_h] = raw_resp_to_resp(match0_response)
        [resp1, resp_embedding1, resp_h1] = raw_resp_to_resp(match1_response)
        [resp2, resp_embedding2, resp_h2] = raw_resp_to_resp("The meaning of meaning is its practical effects.")

        iv = get_random_bytes(16)        
        
        print("we submit a prompt")
       
        await self.contract.submit_prompt(prompt_arr=prompt, prompt_hash=prompt_h, thres_num=thres_num, thres_denom=thres_denom).invoke()
        print("we submit one response")        

        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h, sentence_embedding_arr=list(map(to64x61, resp_embedding))).invoke()

        print("we submit two response")                
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h1, sentence_embedding_arr=list(map(to64x61, resp_embedding1))).invoke()
        
        print("we submit three response")                        
        encoded_se = list(map(to64x61, resp_embedding2))
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h2, sentence_embedding_arr=encoded_se).invoke()
        

        print("we submit arrange rendez vous for h1")                                

        await self.contract.arrange_rendez_vous(prompt_h=prompt_h, response_h=resp_h1,).invoke()

        print("we submit arrange rendez vous for h")          

        await self.contract.arrange_rendez_vous(prompt_h=prompt_h, response_h=resp_h,).invoke()

        print("we submit arrange rendez vous for h")        

        res_h = await self.contract.check_matches_for_response_h(prompt_h=prompt_h, salt=100, response_h=resp_h, response_arr=resp0).call()

        print("check matches for h0")                        

        
        res_h1 = await self.contract.check_matches_for_response_h(prompt_h=prompt_h, salt=100, response_h=resp_h1, response_arr=resp1).call()

        print("check matches for h1")                


        their_response_h = res_h.call_info.result[2]

        their_response_h1 = res_h1.call_info.result[2]





        
        res = await self.contract.get_rendez_vous_detail(prompt_h=prompt_h, salt=100, response_h=resp_h, response_arr=resp0, their_response_h=their_response_h).call()        
        res1 = await self.contract.get_rendez_vous_detail(prompt_h=prompt_h, salt=100, response_h=resp_h1, response_arr=resp1, their_response_h=their_response_h1).call()

        key_for_resp_h = binascii.unhexlify(format(res.call_info.result[0], 'x'))        
        key_for_resp_h1 = binascii.unhexlify(format(res1.call_info.result[0], 'x'))
        # this is really for resp_h



        
        # IV = binascii.unhexlify('69C4E0D86A7B0430D8CDB78070B4C55A')        

        encryptor_h = AES.new(pad(key_for_resp_h1, AES.block_size), AES.MODE_CBC, iv)
        encryptor_h1 = AES.new(pad(key_for_resp_h, AES.block_size), AES.MODE_CBC, iv)

        encrypted_h = list(encryptor_h.encrypt(pad(match0_response.encode('utf-8'), AES.block_size)))
        encrypted_h1 = list(encryptor_h1.encrypt(pad(match1_response.encode('utf-8'), AES.block_size)))

        print(f"this is what goes in wrt encryption {encrypted_h=}")
        print(f"this is what goes in wrt encryption {encrypted_h1=}")

        encrypted_h_h =  reduce(pedersen_hash, encrypted_h)        
        encrypted_h1_h =  reduce(pedersen_hash, encrypted_h1)


        
        await self.contract.submit_response_for_match(prompt_h=prompt_h, response_h=resp_h1, match_h=their_response_h1, encr_arr_hash=encrypted_h1_h, encr_arr=encrypted_h1).invoke()
        await self.contract.submit_response_for_match(prompt_h=prompt_h, response_h=resp_h, match_h=their_response_h, encr_arr_hash=encrypted_h_h, encr_arr=encrypted_h).invoke()
        

        
        
        res =  await self.contract.get_rendez_vous(prompt_h=prompt_h, salt=100, response_h=resp_h, response_arr=resp0, their_response_h=their_response_h).call()

        print(f"{res.call_info.result=}")
        key_over_wire = binascii.unhexlify(format(res.call_info.result[0],
                                                      'x'))


        
                
        rv_l = res.call_info.result[1]
        print(f"{res.call_info.result[2:]=}")
        rv = bytes(res.call_info.result[2:])
        print(f"{rv=}")
        encryptor_h1_a = AES.new(pad(key_over_wire, AES.block_size), AES.MODE_CBC, iv)
        encryptor_h2_b = AES.new(pad(key_for_resp_h1, AES.block_size), AES.MODE_CBC, iv)        
        maybe_decrypt1 = unpad(encryptor_h1_a.decrypt(rv), AES.block_size).decode('utf-8')
#        maybe_decrypt1 = encryptor_h1_a.decrypt(rv).decode('utf-8')

        # maybe_decrypt2 = unpad(encryptor_h1_a.decrypt(rv), AES.block_size).decode('utf-8')               

        # print(f" {maybe_decrypt2=} ")
        breakpoint()
        self.assertEqual(
            maybe_decrypt1,
            match1_response,
            "Contract is still not correct",
        )        

        
    @pytest.mark.asyncio
    async def test_responses_for_prompt_h(self):
        [prompt, prompt_h] = raw_prompt_to_prompt("What is love?")
        [resp0, resp_embedding, resp_h] = raw_resp_to_resp("Love is a feeling.")
        [resp1, resp_embedding1, resp_h1] = raw_resp_to_resp("I am not sure, but I would rather talk about lasagna.")
        await self.contract.submit_prompt(prompt_arr=prompt, prompt_hash=prompt_h).invoke()
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h, sentence_embedding_arr=list(map(to64x61, resp_embedding))).invoke()
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h1, sentence_embedding_arr=list(map(to64x61, resp_embedding1))).invoke()

        res = await self.contract.responses_for_prompt_h(prompt_h=prompt_h).call()
        self.assertEqual(
            res.call_info.result,
            [2, resp_h1, resp_h ],
            "Contract is still not correct",
        )


    @pytest.mark.asyncio
    async def test_compare_resp_to_resp(self):
        [prompt, prompt_h] = raw_prompt_to_prompt("What is love?")
        [resp0, resp_embedding, resp_h] = raw_resp_to_resp("Love is a feeling.")
        [resp1, resp_embedding1, resp_h1] = raw_resp_to_resp("I am not sure, but I would rather talk about lasagna.")
        await self.contract.submit_prompt(prompt_arr=prompt, prompt_hash=prompt_h).invoke()
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h, sentence_embedding_arr=list(map(to64x61, resp_embedding))).invoke()
        await self.contract.submit_response(prompt_h=prompt_h, commit_hash=resp_h1, sentence_embedding_arr=list(map(to64x61, resp_embedding1))).invoke()
        sim = util.cos_sim(resp_embedding, resp_embedding1)
        res = await self.contract.compare_resp_to_resp(resp_h1=resp_h, resp_h2=resp_h1).call()
        self.assertEqual(
            approx(from64x61(res.call_info.result.pop())),
            sim.numpy(),
            "Contract is still not correct",
        )        

    # @pytest.mark.asyncio
    # async def test_commit_check(self):
    #     [prompt, prompt_h] = raw_prompt_to_prompt("What is love?")
    #     # raw_response = "Love is a feeling."
    #     # resp_embedding = model.encode([raw_response])[0]
    #     # resp = str_to_felt(raw_response)
    #     # resp.insert(0, 100)
    #     # resp_h = reduce(pedersen_hash, resp)
    #     # [resp0, resp_embedding, prompt_h] = raw_resp_to_resp("Love is a feeling.")
    #     [resp1, resp_embedding1, resp_h1] = raw_resp_to_resp("I am not sure, but I would rather talk about lasagna.")
    #     res = await self.contract.check_matches_for_response_h(prompt_h=prompt_h, salt=100, response_h=resp_h1, response_arr=resp1).call()
    #     self.assertEqual(
    #         res.call_info.result,
    #         [7],
    #         "Contract is still not correct",
    #     )        
