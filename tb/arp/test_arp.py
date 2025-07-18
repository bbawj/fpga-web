import itertools
import logging

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.binary import BinaryValue

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
async def test_arp_encode(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.encode_rst)

    op = bytes.fromhex("0002")
    sha = bytes.fromhex("000000000000")
    tha = bytes.fromhex("0000DEADBEEF")
    tpa = bytes.fromhex("69696969")
    spa = bytes.fromhex("00000000")
    tb.dut.encode_en.value = 1
    tb.dut.encode_tha.value = BinaryValue(tha, 48)
    tb.dut.encode_tpa.value = BinaryValue(tpa, 32)
    await RisingEdge(tb.dut.clk)
    buf = bytearray()
    for _ in range(28):
        await RisingEdge(tb.dut.clk)
        assert tb.dut.encode_ovalid.value == 1
        low = tb.dut.encode_dout.value.integer
        await RisingEdge(tb.dut.clk)
        assert tb.dut.encode_ovalid.value == 1
        buf.extend(((tb.dut.encode_dout.value.integer << 4) | low).to_bytes())

    await RisingEdge(tb.dut.clk)
    assert tb.dut.encode_ovalid.value == 0
    assert buf == arp_payload(op, sha, tha, spa, tpa)

@cocotb.test()
async def test_arp_decode(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.decode_rst)

    op = bytes.fromhex("0001")
    sha = bytearray.fromhex("0000DEADBEEF")
    tha = bytearray.fromhex("0000DEADBEEF")
    tpa = bytearray.fromhex("69696969")
    spa = bytearray.fromhex("ABCDEF12")
    test_frames = [arp_payload(op, sha, tha, spa, tpa) for x in size_list()]

    for test_data in test_frames:
        await RisingEdge(tb.dut.clk)
        tb.dut.decode_valid.value = 1
        for d in test_data:
            tb.dut.decode_din.value = BinaryValue(d & 0xF, 4, False, 0)
            await FallingEdge(tb.dut.clk)
            tb.dut.decode_din.value = BinaryValue((d >> 4) & 0xF, 4, False, 0)
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
        assert tb.dut.decode_done.value == 0

        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.clk)



def size_list():
    return [512]

def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

def arp_payload(op, sha, tha, spa, tpa):
    hw_type = bytearray.fromhex("0001")[::-1]
    protocol = bytearray.fromhex("0800")[::-1]
    hw_len = bytearray.fromhex("06")[::-1]
    prot_len = bytearray.fromhex("04")[::-1]
    op = op[::-1]
    sha = sha[::-1]
    spa = spa[::-1]
    tha = tha[::-1]
    tpa = tpa[::-1]
    return (hw_type + protocol + hw_len + prot_len + op +
            sha + spa + tha + tpa)
