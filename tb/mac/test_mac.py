import itertools
import logging
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.eth import GmiiFrame, RgmiiSource, RgmiiSink, RgmiiPhy

LOC_MAC_ADDR = "DEADBEEFCAFE"
MAC_SRC = "000000000000"

class TB:
    def __init__(self, dut, speed=100e6):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())
        self.rgmii_phy = RgmiiPhy(dut.phy_txd, dut.phy_txctl, dut.phy_txc,
            dut.phy_rxd, dut.phy_rxctl, dut.phy_rxc, dut.rst, speed=speed)

    async def reset(self):
        self.dut.rst.setimmediatevalue(1)
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


async def run_test_rx(dut, payload_lengths=None, payload_data=None, ifg=12, speed=100e6):

    tb = TB(dut, speed)

    tb.rgmii_phy.rx.ifg = ifg

    await tb.reset()

    test_frames = [payload_data(x) for x in payload_lengths()]

    for test_data in test_frames:
        test_frame = GmiiFrame.from_payload(test_data)
        await tb.rgmii_phy.rx.send(test_frame)

    for test_data in test_frames:
        rx_frame = await tb.rgmii_phy.tx.recv()

        assert rx_frame.get_payload() == test_data
        assert rx_frame.check_fcs()
        assert rx_frame.error is None


def size_list():
    return list(range(60, 128)) + [512, 1514] + [60]*10


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


@cocotb.test()
async def test_mac(dut):
    # await run_test_rx(dut, size_list, incrementing_payload)
    pass

@cocotb.test()
async def test_mac_arp(dut):
    tb = TB(dut, 1000e6)

    await tb.reset()

    ether_type = bytearray.fromhex("0806")
    op = bytes.fromhex("0001")
    sha = bytes.fromhex(MAC_SRC)
    tha = bytes.fromhex(LOC_MAC_ADDR)
    tpa = bytes.fromhex("69696969")
    spa = bytes.fromhex("00000000")

    test_data = mac_payload(tha, sha, ether_type, arp_payload(op, sha, tha, spa, tpa))
    test_frame = GmiiFrame.from_payload(test_data)
    await tb.rgmii_phy.rx.send(test_frame)

    reply_op = bytes.fromhex("0002")
    expected_data = mac_payload(sha, tha, ether_type, arp_payload(reply_op, tha, sha, tpa, spa))
    rx_frame = await tb.rgmii_phy.tx.recv()
    assert rx_frame.get_payload() == expected_data
    assert rx_frame.check_fcs()
    assert rx_frame.error is None

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

def mac_payload(dest, src, ether_type, payload):
    dest = dest[::-1]
    src = src[::-1]
    ether_type = ether_type[::-1]
    payload = (dest + src + ether_type + payload)
    if len(payload) < 64:
        payload = payload + bytearray(60-len(payload))
    return payload

