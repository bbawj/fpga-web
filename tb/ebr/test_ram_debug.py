import os
import random
from pathlib import Path
import itertools
import logging
import pytest

import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock, Timer
from cocotb.triggers import RisingEdge, ReadWrite
from cocotbext.uart import UartSource, UartSink


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())

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
async def fifo_read_write_single(dut):
    w = int(os.getenv("DATA_WIDTH"))
    hex_val = ''.join(random.choices('0123456789abcdef', k=int(w/4)))
    payload = int.from_bytes(bytes.fromhex(hex_val))

    tb = TB(dut)
    await tb.reset()
    for i in range(4):
        dut.din.value = payload + i
        dut.valid.value = 1
        await RisingEdge(tb.dut.clk)
    dut.valid.value = 0
    await RisingEdge(tb.dut.clk)
    for i in range(4):
        dut.fifo_rd_en.value = 1
        await RisingEdge(tb.dut.clk)
        await ReadWrite()
        assert int(dut.fifo_dout.value) == payload + i
    dut.fifo_rd_en.value = 0
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)


@pytest.mark.parametrize("use_blockram", [1])
@pytest.mark.parametrize("data_width", [8, 32])
def test_simple_dff_runner(data_width, use_blockram):
    sim = os.getenv("SIM", "icarus")

    source_folder = "../../rtl"
    sources = [
        f"{source_folder}/fifo.sv",
        f"{source_folder}/ram_wrap.sv",
        f"./test_ram_debug.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_ram_debug",
        always=True,
        clean=True,
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        parameters={"DATA_WIDTH": data_width,
                    "BUF_USE_BLOCKRAM": use_blockram},
        build_args=[
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/",
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/vhdl/ecp5u/src"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                extra_env={"DATA_WIDTH": f"{data_width}"},
                hdl_toplevel="test_ram_debug", test_module="test_ram_debug")


if __name__ == "__main__":
    test_simple_dff_runner()
