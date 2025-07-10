import itertools
import logging

import cocotb
from cocotb.clock import Timer, Clock
from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.binary import BinaryValue
from cocotbext.eth import GmiiFrame, RgmiiSink

class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())

    async def reset(self):
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)



@cocotb.test()
async def test_arp_decode(dut):
    tb = TB(dut)

    await tb.reset()

    sha = bytearray.fromhex("0000DEADBEEF")
    tha = bytearray.fromhex("0000DEADBEEF")
    tpa = bytearray.fromhex("69696969")
    spa = bytearray.fromhex("ABCDEF12")
    test_frames = [arp_payload(sha, tha, spa, tpa) for x in size_list()]

    for test_data in test_frames:
        await RisingEdge(tb.dut.clk)
        tb.dut.valid.value = 1
        for d in test_data:
            tb.dut.din.value = BinaryValue(d & 0xF, 4, False, 0)
            await FallingEdge(tb.dut.clk)
            tb.dut.din.value = BinaryValue((d >> 4) & 0xF, 4, False, 0)
            await RisingEdge(tb.dut.clk)

        await RisingEdge(tb.dut.clk)
        assert tb.dut.err.value == 0
        assert tb.dut.done.value == 1
        assert tb.dut.sha.value.buff == sha
        assert tb.dut.tha.value.buff == tha
        assert tb.dut.tpa.value.buff == tpa
        assert tb.dut.spa.value.buff == spa

        tb.dut.valid.value = 0
        await RisingEdge(tb.dut.clk)
        assert tb.dut.done.value == 0

        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.clk)



def size_list():
    return [512]

def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

def arp_payload(sha, tha, spa, tpa):
    hw_type = bytearray.fromhex("0001")[::-1]
    protocol = bytearray.fromhex("0800")[::-1]
    hw_len = bytearray.fromhex("06")[::-1]
    prot_len = bytearray.fromhex("04")[::-1]
    op = bytearray.fromhex("0001")[::-1]
    sha = sha[::-1]
    spa = spa[::-1]
    tha = tha[::-1]
    tpa = tpa[::-1]
    return (hw_type + protocol + hw_len + prot_len + op +
            sha + spa + tha + tpa)
