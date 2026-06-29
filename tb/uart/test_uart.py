import os
import random
import logging
import pytest

import cocotb
from cocotbext.uart import UartSink
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())

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
async def uart_tx_single(dut):
    w = int(os.getenv("DATA_WIDTH"))
    nibbles = int(w / 4)
    hex_val = ''.join(random.choices('0123456789abcdef', k=nibbles))
    cocotb.log.info(f"Payload is {hex_val}")
    tb = TB(dut)
    uart_sink = UartSink(dut.uart_tx, baud=460800, bits=8)

    tb.dut.valid.value = 0
    await tb.reset(tb.dut.rst)
    await RisingEdge(tb.dut.clk)
    # slice out the correct number of nibbles
    payload = int.from_bytes(bytes.fromhex(hex_val))
    tb.dut.data.value = payload
    tb.dut.valid.value = 1
    await RisingEdge(tb.dut.clk)
    tb.dut.valid.value = 0
    await RisingEdge(tb.dut.clk)
    data = bytearray()
    for i in range(int(w/8)):
        data.extend(await uart_sink.read())
        # inject uart request mid transaction
        if i == 0:
            tb.dut.data.value = payload + 1
            tb.dut.valid.value = 1
            await RisingEdge(tb.dut.clk)
            tb.dut.valid.value = 0
            await RisingEdge(tb.dut.clk)

    data.reverse()
    assert int.from_bytes(data) == payload
    data = bytearray()
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    # assert w != 32
    for i in range(int(w/8)):
        data.extend(await uart_sink.read())
    data.reverse()
    assert int.from_bytes(data) == payload + 1


@pytest.mark.parametrize("use_block_ram", [0, 1])
@pytest.mark.parametrize("data_width", [8, 32])
def test_uart(data_width, use_block_ram):
    sim = os.getenv("SIM", "icarus")

    source_folder = "../../rtl"
    sources = [f"{source_folder}/uart.sv",
               f"{source_folder}/fifo.sv",
               f"{source_folder}/ram_wrap.sv",
               f"{source_folder}/ram_dp.sv",
               "./test_uart.sv",
               ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_uart",
        always=True,
        clean=True,
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        parameters={"DATA_WIDTH": data_width, "USE_BLOCK_RAM": use_block_ram},
        build_args=[
            "-DSYNTHESIS=1",
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/",
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/vhdl/ecp5u/src"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                extra_env={"DATA_WIDTH": f"{data_width}"},
                hdl_toplevel="test_uart", test_module="test_uart,")


if __name__ == "__main__":
    test_uart()
