import os
import logging
import hmac
import hashlib

import cocotb
from cocotb.runner import get_runner
from cocotb.clock import Clock
from cocotb.binary import BinaryValue
from cocotb.triggers import RisingEdge


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())

    async def reset(self):
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0



@cocotb.test()
async def stream(dut):
    tb = TB(dut)

    await tb.reset()


    # await RisingEdge(tb.dut.s_tready_o)
    await RisingEdge(tb.dut.clk)
    dut.valid.value = 1
    dut.is_last_message.value = 1
    key = build_key(bytearray.fromhex("0b" * 20 + 44*"00"))
    m = hashlib.sha256()
    ipad = bytes.fromhex("36" * 64)
    opad = bytes.fromhex("5C" * 64)
    key_to_hash = bytes(x ^ y for x, y in zip(bytes(key), ipad))
    m.update(key_to_hash + b"abc")
    print(key)
    print(key_to_hash)
    first_stage = m.digest()
    print(first_stage)
    m = hashlib.sha256()
    key_to_hash = bytes(x ^ y for x, y in zip(bytes(key), opad))
    print(key_to_hash)
    m.update(key_to_hash + first_stage)
    print(m.digest())
    dut.K.value = BinaryValue(value=bytes(key), n_bits=512)
    dut.message.value = build_block_single()
    dut.message_length.value = 0x18
    m = hmac.new(key, b"abc", hashlib.sha256)

    await RisingEdge(tb.dut.hmac_valid)
    assert tb.dut.digest.value.buff == m.digest()
    # await RisingEdge(tb.dut.clk)
    # assert tb.dut.digest.value.buff == m.digest()

def build_key(key):
    if len(key) < 64:
        key.extend((64 - len(key)) * [0x00])
    return key

def build_block_single():
    block = ""
    tv = [0x61626300, 0x00000000, 0x00000000, 0x00000000,
                 0x00000000, 0x00000000, 0x00000000, 0x00000000,
                 0x00000000, 0x00000000, 0x00000000, 0x00000000,
                 0x00000000, 0x00000000, 0x00000000, 0x00000000]
    for i in tv:
        block += format(i, "032b")
    return BinaryValue(value=block, n_bits=512)


def test_hmacsha256():
    sim = os.getenv("SIM", "icarus")

    source_folder = "../../rtl"
    sources = [f"{source_folder}/sha256_stream.sv",
               f"{source_folder}/sha256_core.sv",
               f"{source_folder}/sha256_w_mem.sv",
               f"{source_folder}/sha256_k_constants.sv",
               f"{source_folder}/hmac_sha256.sv",
               ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="hmac_sha256",
        always=True,
        clean=True,
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        build_args=["-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                hdl_toplevel="hmac_sha256", test_module="test_hmacsha256,")

if __name__ == "__main__":
    test_hmacsha256()
