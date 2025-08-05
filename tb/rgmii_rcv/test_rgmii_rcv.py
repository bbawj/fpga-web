import os
import itertools
import logging
import pytest

import cocotb
from cocotb.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout
from cocotbext.eth import GmiiFrame, RgmiiSource

class TB:
    def __init__(self, dut, speed_100):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8 if speed_100 else 40, units='ns').start())
        cocotb.start_soon(Clock(dut.phy_rxc, 8 if speed_100 else 40, units='ns').start())
        self.source = RgmiiSource(dut.phy_rxd, dut.phy_rxctl, dut.phy_rxc, dut.rst)
        self.source.mii_mode = speed_100 is not None

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
async def mac_rgmii_rcv_invalid_payload(dut):
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100)

    await tb.reset()

    test_frames = [incrementing_payload(x) for x in size_list()]

    for test_data in test_frames:
        test_frame = GmiiFrame.from_payload(test_data)
        await tb.source.send(test_frame)
        await tb.source.wait()
        assert dut.ip_valid.value == 0
        assert dut.arp_decode_valid.value == 0
        assert dut.rgmii_rcv_crc_err.value == 0

@cocotb.test()
async def mac_rgmii_rcv_arp_payload(dut):
    ether_type = bytearray.fromhex("0806")
    op = bytes.fromhex("0001")
    sha = bytearray.fromhex("0000DEADBEEF")
    tha = bytearray.fromhex("DEADBEEFCAFE")
    tpa = bytearray.fromhex("69696969")
    spa = bytearray.fromhex("ABCDEF12")
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100)
    await tb.reset()
    test_frames = [mac_payload(tha, sha, ether_type, arp_payload(op, sha, tha, spa, tpa)) for x in size_list()]

    for test_data in test_frames:
        test_frame = GmiiFrame.from_payload(test_data)
        await tb.source.send(test_frame)
        await with_timeout(RisingEdge(tb.dut.arp_decode_valid), 5000, "ns")

        await tb.source.wait()
        assert dut.ip_valid.value == 0
        assert dut.arp_decode_valid.value == 0
        assert dut.rgmii_rcv_crc_err.value == 0

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

def mac_payload(dest, src, ether_type, payload):
    dest = dest
    src = src
    ether_type = ether_type
    return dest + src + ether_type + payload

@pytest.mark.parametrize("speed_100", [True, False])
def test_simple_dff_runner(speed_100):
    sim = os.getenv("SIM", "icarus")

    source_folder = "../../rtl"
    sources = ["./test_rgmii_rcv.sv",
               f"{source_folder}/clk_divider.sv",
               f"{source_folder}/mac_decode.sv",
               f"{source_folder}/iddr.sv",
               f"{source_folder}/rgmii_rcv.sv",
               f"{source_folder}/crc32.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_rgmii_rcv",
        always=True,
        clean=True,
        waves=True,
        verbose=True,
        defines= {"SPEED_100M": "True"} if speed_100 else {},
        includes=[f"{source_folder}/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                extra_env={"SPEED_100M": "True" } if speed_100 else {},
                hdl_toplevel="test_rgmii_rcv", test_module="test_rgmii_rcv,")
