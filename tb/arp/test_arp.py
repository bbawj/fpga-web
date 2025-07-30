import os
from pathlib import Path
import itertools
import logging
import pytest

import cocotb
from cocotb.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.binary import BinaryValue

LOC_MAC_ADDR = "DEADBEEFCAFE"
LP_MAC_ADDR = "FEEDBABEFACE"

class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())

    async def reset(self, signal):
        signal.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        signal.value = 1
        signal.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        signal.value = 0
        signal.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

@cocotb.test()
async def arp_encode(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.encode_rst)

    op = bytes.fromhex("0002")
    sha = bytes.fromhex(LOC_MAC_ADDR)
    tha = bytes.fromhex(LP_MAC_ADDR)
    tpa = bytes.fromhex("69696969")
    spa = bytes.fromhex("00000000")
    await RisingEdge(tb.dut.clk)
    tb.dut.encode_en.value = 1
    tb.dut.encode_tha.value = BinaryValue(tha, 48)
    tb.dut.encode_tpa.value = BinaryValue(tpa, 32)
    buf = bytearray()
    speed_100 = os.getenv("SPEED_100M", None)
    ARP_LEN = 28
    for _ in range(ARP_LEN):
        await RisingEdge(tb.dut.clk)
        assert tb.dut.encode_ovalid.value == 1
        if speed_100 is not None:
            low = tb.dut.encode_dout.value.integer
            print(low)
            await RisingEdge(tb.dut.clk)
            hi = tb.dut.encode_dout.value.integer
            print(low)
            assert tb.dut.encode_ovalid.value == 1
            buf.extend(((hi << 4) | low).to_bytes())
        else:
            buf.extend(tb.dut.encode_dout.value.integer.to_bytes())

    await RisingEdge(tb.dut.clk)
    assert tb.dut.encode_ovalid.value == 0
    assert buf == arp_payload(op, sha, tha, spa, tpa)

@cocotb.test()
async def arp_decode(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.decode_rst)

    op = bytes.fromhex("0001")
    sha = bytearray.fromhex(LP_MAC_ADDR)
    tha = bytearray.fromhex(LOC_MAC_ADDR)
    tpa = bytearray.fromhex("69696969")
    spa = bytearray.fromhex("ABCDEF12")
    test_frames = [arp_payload(op, sha, tha, spa, tpa) for x in size_list()]

    tb.dut.decode_valid.setimmediatevalue(0)
    for test_data in test_frames:
        for d in test_data:
            await RisingEdge(tb.dut.clk)
            tb.dut.decode_valid.value = 1
            tb.dut.decode_din.value = BinaryValue(d, 8, False, 0)

        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.clk)
        assert tb.dut.decode_err.value == 0
        assert tb.dut.decode_done.value == 1
        assert tb.dut.decode_sha.value.buff == sha
        assert tb.dut.decode_tha.value.buff == tha
        assert tb.dut.decode_tpa.value.buff == tpa
        assert tb.dut.decode_spa.value.buff == spa

        tb.dut.decode_valid.value = 0
        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.clk)
        assert tb.dut.decode_done.value == 0

        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.clk)



def size_list():
    return [512]

def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

def arp_payload(op, sha, tha, spa, tpa):
    hw_type = bytearray.fromhex("0001")
    protocol = bytearray.fromhex("0800")
    hw_len = bytearray.fromhex("06")
    prot_len = bytearray.fromhex("04")
    op = op
    sha = sha
    spa = spa
    tha = tha
    tpa = tpa
    return (hw_type + protocol + hw_len + prot_len + op +
            sha + spa + tha + tpa)

@pytest.mark.parametrize("speed_100", [True, False])
def test_simple_dff_runner(speed_100):
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent

    source_folder = "../../rtl"
    sources = [f"{source_folder}/arp_encode.sv",
               f"{source_folder}/arp_decode.sv",
               "test_arp.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_arp",
        always=True,
        clean=True,
        waves=True,
        verbose=True,
        defines= {"SPEED_100M": "True"} if speed_100 else {},
        parameters={"arp_encode.MAC_ADDR": f"48\'h{LOC_MAC_ADDR}"},
        includes=[f"{source_folder}/"],
        build_args=["-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                parameters={"MAC_ADDR": LOC_MAC_ADDR},
                extra_env={"SPEED_100M": "True" } if speed_100 else {},
                hdl_toplevel="test_arp", test_module="test_arp,")

if __name__ == "__main__":
    test_simple_dff_runner()
