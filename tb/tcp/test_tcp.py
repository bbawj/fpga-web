import os
import logging
import pytest

import cocotb
from scapy.layers.inet import TCP, IP
from scapy.packet import Raw
from scapy.volatile import RandString
from cocotb.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout, ReadWrite
from cocotb.binary import BinaryValue


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())
        cocotb.start_soon(Clock(dut.sys_clk, 8, units='ns').start())

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
async def tcp_decode_full(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.rst)
    tb.dut.decode_valid.setimmediatevalue(0)

    payload = Raw(RandString(size=120))
    packet = IP()/ TCP() / payload
    packet.show2()

    for d in bytes(packet):
        await RisingEdge(tb.dut.clk)
        tb.dut.decode_valid.value = 1
        tb.dut.decode_din.value = BinaryValue(d, 8, False, 0)

    await RisingEdge(tb.dut.clk)
    tb.dut.decode_valid.value = 0
    await with_timeout(RisingEdge(tb.dut.decode_done), 10, "us")
    await RisingEdge(tb.dut.clk)
    assert tb.dut.decode_err.value == 0
    assert tb.dut.tcp_source_port.value.integer == packet.sport
    assert tb.dut.tcp_dest_port.value.integer == packet.dport
    assert tb.dut.tcp_sequence_num.value.integer == packet.seq
    assert tb.dut.tcp_ack_num.value.integer == packet.ack

    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    assert tb.dut.decode_done.value == 0

    await RisingEdge(tb.dut.clk)

    tb.dut.tcp_payload_rd_en.value = 1
    out = bytearray()
    for _ in range(30):
        await RisingEdge(tb.dut.sys_clk)
        await ReadWrite()
        out.extend(tb.dut.tcp_payload_rd_data.value.buff[::-1])
    
    assert out == bytes(payload)


@pytest.mark.parametrize("speed_100", [True])
def test_simple_dff_runner(speed_100):
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
            f"{source_folder}/tcp_decode.sv",
            f"{source_folder}/ip_decode.sv",
            f"{source_folder}/ebr.sv",
            f"{source_folder}/tcp_sm.sv",
            f"{source_folder}/tcp_arbiter.sv",
            f"{source_folder}/lfsr_rng.sv",
            f"{source_folder}/pulse_gen.sv",
               "test_tcp.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_tcp",
        waves=True,
        verbose=True,
        defines= {"SPEED_100M": "True"} if speed_100 else {},
        includes=[f"{source_folder}/"],
        build_args=["--threads", "8", "--trace-fst", "--trace-structs"],
        # build_args=["-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                extra_env={"SPEED_100M": "True" } if speed_100 else {},
                hdl_toplevel="test_tcp", test_module="test_tcp,")
