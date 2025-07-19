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
        self.sink = RgmiiSink(dut.phy_txd, dut.phy_txctl, dut.phy_txc, dut.rst)

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



@cocotb.test()
async def test_mac_mii_output(dut):
    tb = TB(dut)

    await tb.reset()

    MAC_DEST= bytearray.fromhex("DEADBEEFCAFE")
    MAC_SRC= bytearray.fromhex("000000000000")
    ETHER_TYPE = bytearray.fromhex("0800")
    test_frames = [incrementing_payload(x) for x in size_list()]
    tb.dut.ethertype.value = 0x0800;
    tb.dut.mac_dest.value = 0xDEADBEEFCAFE;
    tb.dut.mac_phy_txd.value = 0;

    for test_data in test_frames:
        tb.dut.mac_phy_txen.value = 1
        test_frame = GmiiFrame.from_payload(test_data)
        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.send_next)
        for d in test_frame.get_payload(strip_fcs=True):
            assert tb.dut.send_next.value == 1
            tb.dut.mac_phy_txd.value = BinaryValue(d, 8, False, 0)
            await RisingEdge(tb.dut.clk)
        tb.dut.mac_phy_txen.value = 0
        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.clk)

    for test_data in test_frames:
        frame = await tb.sink.recv()
        copy = bytearray(reversed(MAC_DEST)) + bytearray(reversed(MAC_SRC)) + bytearray(reversed(ETHER_TYPE)) + test_data
        assert frame.get_payload() == copy
        assert frame.check_fcs()
        assert frame.error is None


def size_list():
    return [512]

def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

