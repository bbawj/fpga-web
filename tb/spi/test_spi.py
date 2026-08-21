import os
import cocotb
from utils import WinbondRAM
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock, Timer
from cocotb.utils import get_sim_steps
from cocotb.triggers import RisingEdge, FallingEdge, with_timeout, First
from cocotbext.spi import SpiBus


class TB:
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(self._run_clocks(dut.clk, 0, 8))
        cocotb.start_soon(self._run_clocks(dut.sclk, 90, 8))

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

    async def _run_clocks(self, port, phase, period, en_sig=None):
        half_period = get_sim_steps(period / 2.0, 'ns')
        t = Timer(half_period)

        if phase > 0:
            await Timer(phase/360.0 * period, 'ns')
        while True:
            if (en_sig is not None and en_sig.value == 0):
                await t
                await t
            else:
                port.value = cocotb.handle.Immediate(1)
                await t
                port.value = cocotb.handle.Immediate(0)
                await t


@cocotb.test()
async def spi_meta(dut):
    tb = TB(dut)
    await tb.reset()
    spi_bus = SpiBus.from_entity(dut, cs_name="cs")
    spi_slave = WinbondRAM(spi_bus)
    await RisingEdge(dut.clk)
    dut.i_en.value = 1
    dut.i_inst.value = 0x9f
    dut.i_addr.value = 0
    dut.i_addr_en.value = 0
    dut.i_size.value = 1
    await RisingEdge(dut.clk)
    dut.i_en.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    trans = cocotb.start_soon(spi_slave.get_values())
    while True:
        vals = await First(RisingEdge(dut.o_valid), trans.complete)
        print(vals)
        if isinstance(vals, RisingEdge):
            assert int(dut.o_data.value) == 0xDE
        else:
            assert trans.result()["inst"] == 0x9f
            assert trans.result()["addr"] == dut.i_addr.value
            break


@cocotb.test()
async def spi_read(dut):
    inst = 0x03
    addr = 0

    tb = TB(dut)
    await tb.reset()
    spi_bus = SpiBus.from_entity(dut, cs_name="cs")
    mem = {0: 0xDE}
    spi_slave = WinbondRAM(spi_bus, mem)
    await RisingEdge(dut.clk)
    dut.i_en.value = 1
    dut.i_inst.value = inst
    dut.i_addr.value = addr
    dut.i_addr_en.value = 1
    dut.i_size.value = 10
    await RisingEdge(dut.clk)
    dut.i_en.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    trans = cocotb.start_soon(spi_slave.get_values())
    counter = 0
    while True:
        vals = await First(RisingEdge(dut.o_valid), trans.complete)
        if isinstance(vals, RisingEdge):
            assert int(dut.o_data.value) == mem[0] + counter
            counter += 1
        else:
            assert trans.result()["inst"] == inst
            assert trans.result()["addr"] == addr
            assert counter == 10
            break


def test_simple_dff_runner():
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
        f"./test_spi.sv",
        f"{source_folder}/spi_master.sv",
    ]

    # if sim == "verilator":
    #     sources.append("../../config.vlt")

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_spi",
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        build_args=["--threads", "8", "--trace-fst",
                    "--trace-structs", "--bbox-unsup",
                    ] if sim == "verilator" else [
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                hdl_toplevel="test_spi", test_module="test_spi")
