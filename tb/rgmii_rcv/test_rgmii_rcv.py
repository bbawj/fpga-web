import itertools
import logging

import cocotb
from cocotb.clock import Timer, Clock
from cocotb.triggers import RisingEdge, with_timeout
from cocotbext.eth import GmiiFrame, RgmiiSource

class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())
        self.source = RgmiiSource(dut.mii_rxd, dut.mii_rxctl, dut.clk, dut.rst)

    async def reset(self):
        # self.dut.rst.setimmediatevalue(0)
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
async def test_mac_rgmii_rcv_invalid_payload(dut):
    tb = TB(dut)

    await tb.reset()

    test_frames = [incrementing_payload(x) for x in size_list()]

    for test_data in test_frames:
        test_frame = GmiiFrame.from_payload(test_data)
        await tb.source.send(test_frame)
        await tb.source.wait()
        assert dut.ip_valid.value == 0
        assert dut.arp_valid.value == 0
        assert dut.crc_err.value == 0

@cocotb.test()
async def test_mac_rgmii_rcv_arp_payload(dut):
    op = bytes.fromhex("0001")
    sha = bytearray.fromhex("0000DEADBEEF")
    tha = bytearray.fromhex("0000DEADBEEF")
    tpa = bytearray.fromhex("69696969")
    spa = bytearray.fromhex("ABCDEF12")
    tb = TB(dut)
    await tb.reset()
    test_frames = [arp_payload(op, sha, tha, spa, tpa) for x in size_list()]

    for test_data in test_frames:
        test_frame = GmiiFrame.from_payload(test_data)
        await tb.source.send(test_frame)
        await with_timeout(RisingEdge(tb.dut.arp_valid), 320, "ns")
        assert dut.arp_valid.value == 1
        await tb.source.wait()
        assert dut.ip_valid.value == 0
        assert dut.arp_valid.value == 0
        assert dut.crc_err.value == 0

def size_list():
    return [512]

def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

def arp_payload(op, sha, tha, spa, tpa):
    MAC_DEST= bytearray.fromhex("0000DEADBEEF")
    MAC_SRC= bytearray.fromhex("000000000000")
    ether_type = bytearray.fromhex("0806")
    hw_type = bytearray.fromhex("0001")[::-1]
    protocol = bytearray.fromhex("0800")[::-1]
    hw_len = bytearray.fromhex("06")[::-1]
    prot_len = bytearray.fromhex("04")[::-1]
    op = op[::-1]
    sha = sha[::-1]
    spa = spa[::-1]
    tha = tha[::-1]
    tpa = tpa[::-1]
    payload = (ether_type + hw_type + protocol + hw_len + prot_len + op +
            sha + spa + tha + tpa)
    return mac_payload(MAC_DEST, MAC_SRC, ether_type, payload)

def mac_payload(dest, src, ether_type, payload):
    dest = dest[::-1]
    src = src[::-1]
    ether_type = ether_type[::-1]
    return dest + src + ether_type + payload

