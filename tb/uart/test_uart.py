import os
from pathlib import Path
import itertools
import logging
import pytest

import cocotb
from cocotb.runner import get_runner
from cocotb.clock import Clock, Timer
from cocotb.triggers import RisingEdge


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 40, units='ns').start())

    async def reset(self, signal):
        signal.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        signal.value = 1
        signal.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        signal.value = 0
        signal.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)


@cocotb.test()
async def uart_tx(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.rst)
    await RisingEdge(tb.dut.clk)
    tb.dut.rx.value = 0x97
    tb.dut.valid.value = 1
    await RisingEdge(tb.dut.clk)
    # tb.dut.valid.value = 0
    await Timer(2, units='ms')
    assert False


def test_simple_dff_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent

    source_folder = "../../rtl"
    sources = [f"{source_folder}/uart.sv",
               f"{source_folder}/fifo.sv",
               ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="uart",
        always=True,
        clean=True,
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        build_args=["-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                hdl_toplevel="uart", test_module="test_uart,")

if __name__ == "__main__":
    test_simple_dff_runner()
