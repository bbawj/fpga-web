import itertools
import logging
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.eth import GmiiFrame, RgmiiSource, RgmiiSink, RgmiiPhy


class TB:
    def __init__(self, dut, speed=100e6):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk_25mhz, 40, units='ns').start())
        self.rgmii_phy = RgmiiPhy(dut.phy_txd, dut.phy_txctl, dut.phy_txc,
            dut.phy_rxd, dut.phy_rxctl, dut.phy_rxc, dut.rst, speed=speed)

    async def reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk_25mhz)
        await RisingEdge(self.dut.clk_25mhz)
        self.dut.rst.value = 1
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk_25mhz)
        await RisingEdge(self.dut.clk_25mhz)
        self.dut.rst.value = 0
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk_25mhz)
        await RisingEdge(self.dut.clk_25mhz)


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
    await run_test_rx(dut, size_list, incrementing_payload)
