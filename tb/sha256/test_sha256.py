import os
import logging
import hashlib

import cocotb
from cocotb.runner import get_runner
from cocotb.clock import Timer, Clock
from cocotb.binary import BinaryValue
from cocotb.triggers import RisingEdge

tv = [0x61626380, 0x00000000, 0x00000000, 0x00000000,
      0x00000000, 0x00000000, 0x00000000, 0x00000000,
      0x00000000, 0x00000000, 0x00000000, 0x00000000,
      0x00000000, 0x00000000, 0x00000000, 0x00000018]

NIST_2_1 = [0x61626364, 0x62636465, 0x63646566, 0x64656667,
            0x65666768, 0x66676869, 0x6768696a, 0x68696a6b,
            0x696a6b6c, 0x6a6b6c6d, 0x6b6c6d6e, 0x6c6d6e6f,
            0x6d6e6f70, 0x6e6f7071, 0x80000000, 0x00000000]

NIST_2_2 = [0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x000001C0]

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
        self.dut.s_tvalid_i.value = 0



@cocotb.test()
async def stream_single(dut):
    tb = TB(dut)

    await tb.reset()

    m = hashlib.sha256()
    dut.mode.value = 1

    await RisingEdge(tb.dut.s_tready_o)
    dut.s_tvalid_i.value = 1
    dut.s_tfirst_i.value = 1
    data = build_block(tv)
    dut.s_tdata_i.setimmediatevalue(data)
    print(data.buff)
    m.update(b"abc")

    await RisingEdge(tb.dut.digest_valid_o)
    assert tb.dut.digest_o.value.buff == m.digest()

@cocotb.test()
async def stream_double(dut):
    tb = TB(dut)

    await tb.reset()

    m = hashlib.sha256()
    dut.mode.value = 1

    await RisingEdge(tb.dut.s_tready_o)
    dut.s_tvalid_i.value = 1
    dut.s_tfirst_i.value = 1
    data = build_block(NIST_2_1)
    dut.s_tdata_i.value = data
    print(data.buff)
    m.update(bytes.fromhex('6162636462636465636465666465666765666768666768696768696a68696a6b696a6b6c6a6b6c6d6b6c6d6e6c6d6e6f6d6e6f706e6f7071'))

    await RisingEdge(tb.dut.digest_valid_o)
    data = build_block(NIST_2_2)
    dut.s_tdata_i.value = data
    dut.s_tfirst_i.value = 0
    await RisingEdge(tb.dut.digest_valid_o)
    await RisingEdge(tb.dut.clk)
    assert tb.dut.digest_o.value.buff == m.digest()

def build_block(tv):
    block = ""
    for i in tv:
        block += format(i, "032b")
    return BinaryValue(value=block, n_bits=512)


def test_sha256():
    sim = os.getenv("SIM", "icarus")

    source_folder = "../../rtl"
    sources = [f"{source_folder}/sha256_stream.sv",
               f"{source_folder}/sha256_core.sv",
               f"{source_folder}/sha256_w_mem.sv",
               f"{source_folder}/sha256_k_constants.sv",
               ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="sha256_stream",
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
                hdl_toplevel="sha256_stream", test_module="test_sha256,")

if __name__ == "__main__":
    test_sha256()
