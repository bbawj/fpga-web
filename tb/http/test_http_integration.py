import pytest
import cocotb
import os
from pathlib import Path
from cocotb.triggers import RisingEdge, with_timeout
from cocotb.clock import Timer
from cocotb.utils import get_sim_steps
from cocotb_tools.runner import get_runner
from cocotbext.eth import RgmiiPhy
from scapy.all import Raw, RandString, Ether, TCP, IP
from tcp.utils import TCPIntegrated, TCP_client_sim, PacketGen, TCP_rst_client

LOC_MAC_ADDR = "DEADBEEFCAFE"
MAC_SRC = "b025aa3306fe"
server_ip = "105.105.105.105"
server_port = 8080
dst_mac = ":".join([LOC_MAC_ADDR[i:i+2]
                    for i in range(0, len(LOC_MAC_ADDR)-1, 2)])
src_mac = ":".join([MAC_SRC[i:i+2]
                    for i in range(0, len(MAC_SRC)-1, 2)])


class TB:
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(self._run_clocks(dut.clk, 0, 8))
        cocotb.start_soon(self._run_clocks(dut.clk90, 90, 8))
        dut.rst.value = cocotb.handle.Immediate(1)
        self.rgmii_phy = RgmiiPhy(dut.phy_txd, dut.phy_txctl, dut.phy_txc,
                                  dut.phy_rxd, dut.phy_rxctl, dut.phy_rxc, dut.rst, speed=1000e6)

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
async def http_integration_small_page(dut):
    tb = TB(dut)

    await tb.reset()
    tb.dut.tcp_echo_en.value = 0
    client_ref = []
    client_ip = "192.168.1.1"
    client_port = 5000
    gen = PacketGen(client_ip, client_port)
    tcp = TCPIntegrated(tb, False, dst_mac, src_mac)
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    assert tcp.recv_count == 1
    gen.from_bench.put(Raw("GET /0\r\n"))
    await Timer(50, "us")
    assert tcp.recv_count == 5
    with open("../pages/0.html", "rb") as f:
        assert bytes(tcp.payload) == f.read().rjust(32, b'\x00')


@cocotb.test()
async def http_integration_big_page(dut):
    tb = TB(dut)

    await tb.reset()
    tb.dut.tcp_echo_en.value = 0
    client_ref = []
    client_ip = "192.168.1.1"
    client_port = 5000
    gen = PacketGen(client_ip, client_port)
    tcp = TCPIntegrated(tb, False, dst_mac, src_mac)
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    assert tcp.recv_count == 1
    gen.from_bench.put(Raw("GET /1\r\n"))
    await Timer(300, "us")
    with open("../pages/1.html", "rb") as f:
        assert bytes(tcp.payload) == f.read().rjust(32, b'\x00')
    assert tcp.recv_count == 19


@cocotb.test()
async def http_no_path(dut):
    tb = TB(dut)

    await tb.reset()
    tb.dut.tcp_echo_en.value = 0
    client_ref = []
    client_ip = "192.168.1.1"
    client_port = 5000
    gen = PacketGen(client_ip, client_port)
    tcp = TCPIntegrated(tb, False, dst_mac, src_mac)
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    assert tcp.recv_count == 1
    gen.from_bench.put(Raw(
        """GET /favicon.ico HTTP/1.1
Host: 105.105.105.105:8080
Connection: keep-alive
User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36
Accept: image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8
Sec-GPC: 1
Accept-Language: en-GB,en;q=0.9
Referer: http://105.105.105.105:8080/0
Accept-Encoding: gzip, deflate"""))
    await Timer(20000, "ns")
    client_ref[0].stop(wait=False)
    await Timer(5000, "ns")
    assert tcp.recv_count == 5


@cocotb.test()
async def http_no_path_during_normal(dut):
    tb = TB(dut)

    await tb.reset()
    tb.dut.tcp_echo_en.value = 0
    client_ref = []
    client_ip = "192.168.1.1"
    client_port = 5000
    gen = PacketGen(client_ip, client_port)
    tcp = TCPIntegrated(tb, False, dst_mac, src_mac)
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    assert tcp.recv_count == 1
    gen.from_bench.put(Raw("GET /0\r\n"))
    await Timer(30000, "ns")
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port+123, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    gen.from_bench.put(Raw(
        """GET /favicon.ico HTTP/1.1
Host: 105.105.105.105:8080
Connection: keep-alive
User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36
Accept: image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8
Sec-GPC: 1
Accept-Language: en-GB,en;q=0.9
Referer: http://105.105.105.105:8080/0
Accept-Encoding: gzip, deflate"""))
    await Timer(20000, "ns")
    client_ref[1].stop(wait=False)
    await Timer(5000, "ns")
    assert tcp.recv_count == 10


@cocotb.test()
async def http_tcp_rst(dut):
    tb = TB(dut)

    await tb.reset()
    tb.dut.tcp_echo_en.value = 0
    client_ref = []
    client_ip = "192.168.1.1"
    client_port = 5000
    gen = PacketGen(client_ip, client_port)
    tcp = TCPIntegrated(tb, False, dst_mac, src_mac)
    cocotb.start_soon(cocotb.task.bridge(TCP_rst_client)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    gen.from_bench.put(Raw("GET /0\r\n"))
    await Timer(20000, "ns")
    assert tcp.recv_count == 3
    client_ref[0].stop(wait=False)
    await Timer(5000, "ns")
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port + 123, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    client_ref[1].stop(wait=False)
    await Timer(5000, "ns")


@cocotb.test(skip=True)
async def http_integration_stop_during_payload(dut):
    pass


def test_http_integration():
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
        "../../config.vlt",
        "./test_http_integration.sv",
        f"{source_folder}/utils.sv",
        f"{source_folder}/cache.sv",
        f"{source_folder}/http_decode.sv",
        f"{source_folder}/http_entry.sv",
        f"{source_folder}/mac_encode.sv",
        f"{source_folder}/ram_wrap.sv",
        f"{source_folder}/slab_allocator.sv",
        f"{source_folder}/ram_sp.sv",
        f"{source_folder}/sdram_dummy.sv",
        f"{source_folder}/mac_decode.sv",
        f"{source_folder}/synchronizer.sv",
        f"{source_folder}/ebr.sv",
        f"{source_folder}/tcp.sv",
        f"{source_folder}/mac.sv",
        f"{source_folder}/mac_tx.sv",
        f"{source_folder}/oddr.sv",
        f"{source_folder}/iddr.sv",
        f"{source_folder}/lfsr_rng.sv",
        f"{source_folder}/ip_encode.sv",
        f"{source_folder}/tcp_encode.sv",
        f"{source_folder}/tcp_arbiter.sv",
        f"{source_folder}/tcp_sm.sv",
        f"{source_folder}/tcp_decode.sv",
        f"{source_folder}/ip_decode.sv",
        f"{source_folder}/arp_decode.sv",
        f"{source_folder}/arp_encode.sv",
        f"{source_folder}/rgmii_rcv.sv",
        f"{source_folder}/rgmii_tx.sv",
        f"{source_folder}/clk_divider.sv",
        f"{source_folder}/delay.sv",
        f"{source_folder}/fifo.sv",
        f"{source_folder}/pulse_stretcher.sv",
        f"{source_folder}/to_ack_fifo.sv",
        f"{source_folder}/tcb.sv",
        f"{source_folder}/crc32.sv"]

    addr_file = "./addrs.mem"
    size_file = "./lengths.mem"
    content_file = "./content_hex.mem"
    addr_file_abs = Path(addr_file).resolve()
    size_file_abs = Path(size_file).resolve()
    content_file_abs = Path(content_file).resolve()
    assert addr_file_abs.exists() and size_file_abs.exists()

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_http_integration",
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        parameters={"HTTP_ADDR_FILE": f'"{addr_file_abs}"',
                    "HTTP_SIZE_FILE": f'"{size_file_abs}"',
                    "HTTP_CONTENT_FILE": f'"{content_file_abs}"',
                    },
        build_args=["--threads", "8", "--trace-fst",
                    "--trace-structs", "--bbox-unsup",
                    "-y", "/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/",
                    "-y", "/home/bawj/lscc/diamond/3.14/cae_library/simulation/vhdl/ecp5u/", "--timing"
                    ] if sim == "verilator" else [
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                hdl_toplevel="test_http_integration", test_module="test_http_integration")
