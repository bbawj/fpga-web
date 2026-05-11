import os
from pathlib import Path
import itertools
import logging
import pytest

import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock, Timer
from cocotb.triggers import RisingEdge
from cocotbext.uart import UartSource, UartSink


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())


@cocotb.test()
async def uart_tx(dut):
    tb = TB(dut)
    uart_sink = UartSink(dut.uart_tx, baud=38400, bits=8)

    tb.dut.button.value = 1
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    tb.dut.button.value = 1
    await RisingEdge(tb.dut.clk)
    tb.dut.button.value = 0
    await RisingEdge(tb.dut.clk)
    tb.dut.button.value = 1
    # tb.dut.valid.value = 0
    data = bytearray()
    for i in range(4):
        data.extend(await uart_sink.read())
    cocotb.log.info(data)
    assert data == 0xDEDEDEDE


@pytest.mark.parametrize("use_block_ram", [0, 1])
def test_simple_dff_runner(use_block_ram):
    sim = os.getenv("SIM", "icarus")

    source_folder = "../../rtl"
    sources = [f"{source_folder}/uart.sv",
               f"{source_folder}/fifo.sv",
               f"{source_folder}/ebr.sv",
               f"{source_folder}/ram_wrap.sv",
               f"./test_ebr_debug.sv",
               ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_ebr_debug",
        always=True,
        clean=True,
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        # build_args=["--threads", "8", "--trace-fst", "--trace-structs"],
        build_args=[
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/",
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/vhdl/ecp5u/src"],
        parameters={"USE_BLOCK_RAM": use_block_ram, },
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                hdl_toplevel="test_ebr_debug", test_module="test_ebr_debug")


if __name__ == "__main__":
    test_simple_dff_runner()
