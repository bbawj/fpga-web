import itertools
import logging

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.binary import BinaryValue
from cocotbext.eth import GmiiFrame


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 40, units='ns').start())

    async def reset(self):
        self.dut.rst.setimmediatevalue(0)
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


async def calc_crc(dut, payload_lengths=None, payload_data=None):
    tb = TB(dut)

    await tb.reset()

    test_frames = [payload_data(x) for x in payload_lengths()]

    for test_data in test_frames:
        test_frame = GmiiFrame.from_payload(test_data)
        for d in test_frame.get_payload():
            await RisingEdge(tb.dut.clk)
            tb.dut.en = 1
            tb.dut.din = BinaryValue(d & 0xF, 4, False, 0)
            await RisingEdge(tb.dut.clk)
            tb.dut.din = BinaryValue((d >> 4) & 0xF, 4, False, 0)

        await RisingEdge(tb.dut.clk)
        tb.dut.en = 0
        await RisingEdge(tb.dut.clk)
        out = tb.dut.crc_out.value
        assert out == test_frame.get_fcs()


def size_list():
    return list(range(60, 128)) + [512, 1514] + [60]*10


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

@cocotb.test()
async def test_crc(dut):
    await calc_crc(dut, size_list, incrementing_payload)
