import itertools
import logging

import os
import cocotb
import pytest
from cocotb.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout

from cocotbext.eth import GmiiFrame, RgmiiPhy

LOC_MAC_ADDR = "DEADBEEFCAFE"
MAC_SRC = "b025aa3306fe"

class TB:
    def __init__(self, dut, speed_100):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        if speed_100:
            cocotb.start_soon(Clock(dut.clk, 40, units='ns').start())
        else:
            cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())
        self.rgmii_phy = RgmiiPhy(dut.phy_txd, dut.phy_txctl, dut.phy_txc,
            dut.phy_rxd, dut.phy_rxctl, dut.phy_rxc, dut.rst, speed=100e6 if speed_100 else 1000e6)

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


def size_list():
    return list(range(60, 128)) + [512, 1514] + [60]*10


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

@cocotb.test()
async def arp_reply(dut):
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100 is not None)

    await tb.reset()

    ether_type = bytearray.fromhex("0806")
    op = bytes.fromhex("0001")
    sha = bytes.fromhex(MAC_SRC)
    tha = bytes.fromhex(LOC_MAC_ADDR)
    tpa = bytes.fromhex("69696969")
    spa = bytes.fromhex("c0a84564")

    test_data = bytes.fromhex("deadbeefcafeb025aa3306fe08060001080006040001b025aa3306fec0a84564DEADBEEFCAFE6969696900000000000000000000000000000000")

    #test_data = mac_payload(tha, sha, ether_type, arp_payload(op, sha, tha, spa, tpa))
    test_frame = GmiiFrame.from_payload(test_data)
    await tb.rgmii_phy.rx.send(test_frame)

    reply_op = bytes.fromhex("0002")
    expected_data = mac_payload(sha, tha, ether_type, arp_payload(reply_op, tha, sha, tpa, spa))
    rx_frame = await with_timeout(tb.rgmii_phy.tx.recv(), 50000, "ns")
    assert rx_frame.get_payload() == expected_data
    assert rx_frame.check_fcs()
    assert rx_frame.error is None

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
    payload = (dest + src + ether_type + payload)
    if len(payload) < 60:
        payload = payload + bytearray(60-len(payload))
    return payload

@pytest.mark.parametrize("speed_100", [True, False])
def test_simple_dff_runner(speed_100):
    sim = os.getenv("SIM", "icarus")

    source_folder = "../../rtl"
    sources = [f"{source_folder}/mac_encode.sv",
               f"{source_folder}/mac_decode.sv",
               f"{source_folder}/mac.sv",
               f"{source_folder}/oddr.sv",
               f"{source_folder}/iddr.sv",
               f"{source_folder}/arp_decode.sv",
               f"{source_folder}/arp_encode.sv",
               f"{source_folder}/rgmii_rcv.sv",
               f"{source_folder}/rgmii_tx.sv",
               f"{source_folder}/clk_gen.sv",
               f"{source_folder}/clk_divider.sv",
               f"{source_folder}/crc32.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="mac",
        always=True,
        clean=True,
        waves=True,
        verbose=True,
        defines= {"SPEED_100M": "True"} if speed_100 else {},
        includes=[f"{source_folder}/"],
        build_args=["-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                extra_env={"SPEED_100M": "True" } if speed_100 else {},
                hdl_toplevel="mac", test_module="test_mac,")

