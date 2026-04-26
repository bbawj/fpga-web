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
async def http_decode(dut):
    tb = TB(dut)
    payload = bytes("GET 1", "ascii")
    await tb.reset()
    for i in range(len(payload)):
        dut.i_payload_valid.value = 1
        dut.i_payload_data.value = payload[i]
        await RisingEdge(dut.clk)

    dut.i_payload_valid.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.res_valid.value == 1
    # CAM is empty
    print(os.getenv("ADDR_FILE"))
    if os.getenv("ADDR_FILE") == "":
        assert dut.res_err.value == 1
    else:
        assert dut.res_err.value == 0


@pytest.mark.parametrize("addr_file,size_file", [("", ""), ("addrs.mem", "lengths.mem")])
def test_http(addr_file, size_file):
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
        f"{source_folder}/http_decode.sv",
        "./test_http.sv",
    ]

    addr_file_abs = Path(addr_file).resolve()
    size_file_abs = Path(size_file).resolve()
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_http",
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        parameters={"CAM_ADDR_FILE": f'"{addr_file_abs}"',
                    "CAM_SIZE_FILE": f'"{size_file_abs}"', },
        build_args=["--threads", "8", "--trace-fst",
                    "--trace-structs"] if sim == "verilator" else [],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                parameters={"CAM_ADDR_FILE": f'{addr_file_abs}',
                            "CAM_SIZE_FILE": f'{size_file_abs}'},
                extra_env={"ADDR_FILE": addr_file,
                           "SIZE_FILE": size_file},
                hdl_toplevel="test_http", test_module="test_http")
