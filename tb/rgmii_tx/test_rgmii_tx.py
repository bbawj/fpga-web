import os
import pytest
import itertools
import logging

import cocotb
from cocotb.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge
from cocotbext.eth import GmiiFrame, RgmiiSink
from cocotb.binary import BinaryValue

class TB:
    def __init__(self, dut, speed_100):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())
        self.sink = RgmiiSink(dut.phy_txd, dut.phy_txctl, dut.phy_txc, dut.rst)
        self.sink.mii_mode = speed_100 is not None

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
async def mac_mii_output(dut):
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100)

    await tb.reset()

    MAC_DEST= bytes.fromhex("DEADBEEFCAFE")
    MAC_SRC= bytes.fromhex("000000000000")
    ETHER_TYPE = bytes.fromhex("0800")
    test_frames = [incrementing_payload(x) for x in size_list()]
    tb.dut.ethertype.value = BinaryValue(ETHER_TYPE, 16);
    tb.dut.mac_dest.value = BinaryValue(MAC_DEST, 48);
    tb.dut.mac_payload.value = 0;

    for test_data in test_frames:
        tb.dut.en.value = 1
        test_frame = GmiiFrame.from_payload(test_data)
        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.send_next)
        for d in test_frame.get_payload(strip_fcs=True):
            assert tb.dut.send_next.value == 1
            if speed_100 is None:
                tb.dut.mac_payload.value = BinaryValue(d, 8, False, 0)
                await RisingEdge(tb.dut.clk)
            else:
                tb.dut.mac_payload.value = BinaryValue(d, 8, False, 0)
                await RisingEdge(tb.dut.clk)
                tb.dut.mac_payload.value = BinaryValue(d >> 4, 8, False, 0)
                await RisingEdge(tb.dut.clk)
        tb.dut.en.value = 0
        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.clk)
        await RisingEdge(tb.dut.clk)

    for test_data in test_frames:
        frame = await tb.sink.recv()
        copy = MAC_DEST[::-1] + MAC_SRC[::-1] + ETHER_TYPE[::-1] + test_data
        assert frame.get_payload() == copy
        assert frame.check_fcs()
        assert frame.error is None


def size_list():
    return [512]

def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

@pytest.mark.parametrize("speed_100", [True, False])
def test_simple_dff_runner(speed_100):
    sim = os.getenv("SIM", "icarus")

    source_folder = "../../rtl"
    sources = [f"{source_folder}/mac_encode.sv",
               f"{source_folder}/oddr.sv",
               f"{source_folder}/rgmii_tx.sv",
               f"{source_folder}/clk_gen.sv",
               f"{source_folder}/crc32.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="mac_encode",
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
                hdl_toplevel="mac_encode", test_module="test_rgmii_tx,")

