import os
from pathlib import Path
import logging
import pytest

import cocotb
import socket
from scapy.all import IP
from cocotb.runner import get_runner
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
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
async def ip_decode(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.decode_rst)
    tb.dut.decode_valid.setimmediatevalue(0)

    packet = IP(proto=6)
    packet.show()

    for d in bytes(packet):
        await RisingEdge(tb.dut.clk)
        tb.dut.decode_valid.value = 1
        tb.dut.decode_din.value = BinaryValue(d, 8, False, 0)

    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    assert tb.dut.decode_err.value == 0
    assert tb.dut.decode_done.value == 1
    assert tb.dut.decode_sa.value.buff == socket.inet_aton(packet.src)
    assert tb.dut.decode_da.value.buff == socket.inet_aton(packet.dst)

    tb.dut.decode_valid.value = 0
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    assert tb.dut.decode_done.value == 0

    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)

@cocotb.test()
async def ip_encode(dut):
    packet = IP(proto=6, flags=["DF"])
    b = bytes(packet)
    tb = TB(dut)
    await tb.reset(tb.dut.encode_rst)
    tb.dut.encode_en.value = 1
    tb.dut.encode_sa.value = int.from_bytes(b[12:16])
    tb.dut.encode_da.value = int.from_bytes(b[16:20])
    tb.dut.encode_len.value = int.from_bytes(b[2:4])
    out = bytearray()
    await RisingEdge(tb.dut.clk)
    while tb.dut.encode_valid.value == 0:
        await RisingEdge(tb.dut.clk)
        out.append(tb.dut.encode_dout.value.integer)

    assert bytes(out) == b


@pytest.mark.parametrize("speed_100", [True, False])
def test_simple_dff_runner(speed_100):
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent

    source_folder = "../../rtl"
    sources = [f"{source_folder}/ip_decode.sv",
               f"{source_folder}/ip_encode.sv",
               "test_ip.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_ip",
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
                hdl_toplevel="test_ip", test_module="test_ip,")

if __name__ == "__main__":
    test_simple_dff_runner()
