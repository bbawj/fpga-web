import pytest
import cocotb
import os
from pathlib import Path
from cocotb.triggers import RisingEdge, with_timeout, ReadWrite
from cocotb.clock import Clock, Timer
from cocotb.utils import get_sim_steps
from cocotb_tools.runner import get_runner


class TB:
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(self._run_clocks(dut.clk, 0, 8))
        dut.rst.value = cocotb.handle.Immediate(1)

    async def _run_clocks(self, port, phase, period):
        half_period = get_sim_steps(period / 2.0, 'ns')
        t = Timer(half_period)

        if phase > 0:
            await Timer(phase/360.0 * period, 'ns')
        while True:
            port.value = cocotb.handle.Immediate(1)
            await t
            port.value = cocotb.handle.Immediate(0)
            await t

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
async def sdram_ctrl(dut):
    tb = TB(dut)
    await tb.reset()
    dut.wr_req.value = 1
    dut.wr_ad.value = 0x7CAFE
    await with_timeout(RisingEdge(dut.wr_granted), 400, "us")
    await RisingEdge(dut.clk)
    dut.wr_req.value = 0
    await RisingEdge(dut.clk)
    assert dut.wr_granted.value == 0
    dut.wr_req.value = 0
    dut.rd_req.value = 1
    dut.rd_ad.value = 0x7CAFE
    await RisingEdge(dut.clk)
    await with_timeout(RisingEdge(dut.rd_granted), 20, "us")
    await RisingEdge(dut.clk)
    dut.rd_req.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.rd_valid.value == 1
    await Timer(500, "ns")


def test_sdram():
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
        f"{source_folder}/sdram_ctrl.sv",
        "./test_sdram.sv",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_sdram",
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        build_args=["--threads", "8", "--trace-fst",
                    "--trace-structs"] if sim == "verilator" else [],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                hdl_toplevel="test_sdram", test_module="test_sdram")

