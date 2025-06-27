import itertools
import logging
import os

import cocotb_test.simulator
import cocotb
from cocotb.triggers import RisingEdge
from cocotb.regression import TestFactory

from cocotbext.eth import GmiiFrame, MiiPhy


class TB:
    def __init__(self, dut, speed=100e6):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.mii_phy = MiiPhy(dut.mii_txd, dut.mii_tx_er, dut.mii_tx_en, dut.mii_tx_clk,
            dut.mii_rxd, dut.mii_rx_er, dut.mii_rx_dv, dut.mii_rx_clk, speed=speed)

async def run_test_rx(dut, payload_lengths=None, payload_data=None, ifg=12, speed=100e6):
    tb = TB(dut, speed)

    tb.mii_phy.rx.ifg = ifg
    tb.dut.cfg_ifg.value = ifg
    tb.dut.cfg_rx_enable.value = 1

    await tb.reset()

    test_frames = [payload_data(x) for x in payload_lengths()]

    for test_data in test_frames:
        test_frame = GmiiFrame.from_payload(test_data)
        await tb.mii_phy.rx.send(test_frame)

    for test_data in test_frames:
        rx_frame = await tb.axis_sink.recv()

        assert rx_frame.tdata == test_data
        assert rx_frame.tuser == 0

    assert tb.axis_sink.empty()

    await RisingEdge(dut.rx_clk)
    await RisingEdge(dut.rx_clk)
