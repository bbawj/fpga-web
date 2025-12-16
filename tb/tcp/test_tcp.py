import os
from pathlib import Path
import logging
import pytest

import cocotb
import socket
from scapy.all import TCP
from cocotb.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout
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
async def tcp_decode(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.decode_rst)
    tb.dut.decode_valid.setimmediatevalue(0)

    packet = TCP()
    packet.show()

    for d in bytes(packet):
        await RisingEdge(tb.dut.clk)
        tb.dut.decode_valid.value = 1
        tb.dut.decode_din.value = BinaryValue(d, 8, False, 0)

    await with_timeout(RisingEdge(tb.dut.decode_done), 10, "us")
    assert tb.dut.decode_err.value == 0
    assert tb.dut.decode_source_port.value.integer == packet.sport
    assert tb.dut.decode_dest_port.value.integer == packet.dport
    assert tb.dut.decode_sequence_num.value.integer == packet.seq
    assert tb.dut.decode_ack_num.value.integer == packet.ack

    await RisingEdge(tb.dut.clk)
    tb.dut.decode_valid.value = 0
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    assert tb.dut.decode_done.value == 0

    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)


@pytest.mark.parametrize("speed_100", [True, False])
def test_simple_dff_runner(speed_100):
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent

    source_folder = "../../rtl"
    sources = [f"{source_folder}/tcp_decode.sv",
               "test_tcp.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_tcp",
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
                parameters={"MAC_ADDR": LOC_MAC_ADDR},
                extra_env={"SPEED_100M": "True" } if speed_100 else {},
                hdl_toplevel="test_tcp", test_module="test_tcp,")

if __name__ == "__main__":
    test_simple_dff_runner()
