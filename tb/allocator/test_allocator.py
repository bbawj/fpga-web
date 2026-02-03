import os
import itertools
import logging
import pytest

import cocotb
from cocotb.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout, ReadWrite
from cocotb.binary import BinaryValue

LOC_MAC_ADDR = "DEADBEEFCAFE"
LP_MAC_ADDR = "FEEDBABEFACE"

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
async def allocator_sizes(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.rst)
    tb.dut.alloc_en.setimmediatevalue(1)
    tb.dut.request_size.setimmediatevalue(BinaryValue(14, 5, False, 0))

    await RisingEdge(tb.dut.clk)
    tb.dut.alloc_en.value = 0
    await with_timeout(RisingEdge(tb.dut.o_valid), 10, "us")
    assert tb.dut.o_err == 0;

    await RisingEdge(tb.dut.clk)
    tb.dut.alloc_en.value = 1
    tb.dut.request_size.value = BinaryValue(18, 5, False, 0)
    await RisingEdge(tb.dut.clk)
    tb.dut.alloc_en.value = 0
    await with_timeout(RisingEdge(tb.dut.o_valid), 10, "us")
    await RisingEdge(tb.dut.clk)
    assert tb.dut.o_err == 1;

    await RisingEdge(tb.dut.clk)
    tb.dut.alloc_en.value = 1
    tb.dut.request_size.value = BinaryValue(3, 5, False, 0)
    await RisingEdge(tb.dut.clk)
    tb.dut.alloc_en.value = 0
    await with_timeout(RisingEdge(tb.dut.o_valid), 10, "us")
    await RisingEdge(tb.dut.clk)
    assert tb.dut.o_err == 0;

@cocotb.test()
async def allocator_ebr(dut):
    tb = TB(dut)
    sizes = [14,10]
    payloads = [incrementing_payload(s) for s in sizes]
    addr = []

    await tb.reset(tb.dut.rst)
    for s, p in zip(sizes, payloads):
        addr.append(await alloc_readback(tb, s, p))
    # check for data integrity
    for i, a in enumerate(addr):
        tb.dut.rd_en.value = 1
        tb.dut.i_addr.value = a
        out = bytearray()
        for _ in range(sizes[i]):
            await RisingEdge(tb.dut.clk)
            await ReadWrite()
            out.append(tb.dut.o_rd_data.value.integer)
        assert out == payloads[i]
        tb.dut.rd_en.value = 0
        await RisingEdge(tb.dut.clk)


async def alloc_readback(tb, alloc_len, alloc_payload):
    out = bytearray()
    tb.dut.alloc_en.value = 1
    tb.dut.request_size.value = BinaryValue(alloc_len, 5, False, 0)
    await with_timeout(RisingEdge(tb.dut.o_valid), 10, "us")
    assert tb.dut.o_err == 0;
    tb.dut.alloc_en.value = 0
    tb.dut.wr_en.value = 1
    tb.dut.i_addr.value = tb.dut.o_addr.value
    addr = tb.dut.o_addr.value
    for d in alloc_payload:
        tb.dut.wr_data.value = BinaryValue(d, 32, False, 0)
        await RisingEdge(tb.dut.clk)

    tb.dut.wr_en.value = 0
    tb.dut.rd_en.value = 1
    for i in range(alloc_len):
        await RisingEdge(tb.dut.clk)
        await ReadWrite()
        out.append(tb.dut.o_rd_data.value.integer)
        if i == alloc_len - 1:
            tb.dut.rd_en.value = 0
    await RisingEdge(tb.dut.clk)
    assert out == alloc_payload
    return addr

def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

@pytest.mark.parametrize("speed_100", [True, False])
def test_simple_dff_runner(speed_100):
    sim = os.getenv("SIM", "icarus")

    source_folder = "../../rtl"
    sources = [
            f"{source_folder}/ebr.sv",
            f"{source_folder}/allocator.sv",
               "test_allocator.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_allocator",
        always=True,
        clean=True,
        waves=True,
        verbose=True,
        defines= {"SPEED_100M": "True"} if speed_100 else {},
        includes=[f"{source_folder}/"],
        # build_args=["--trace-fst", "--trace-structs"],
        # build_args=["-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                parameters={"MAC_ADDR": LOC_MAC_ADDR},
                extra_env={"SPEED_100M": "True" } if speed_100 else {},
                hdl_toplevel="test_allocator", test_module="test_allocator,")

if __name__ == "__main__":
    test_simple_dff_runner()
