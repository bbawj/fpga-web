import pytest
import cocotb
import os
from multiprocessing import Queue
from cocotb.triggers import RisingEdge, with_timeout, ReadWrite
from cocotb.clock import Clock, Timer
from cocotb.utils import get_sim_steps
from cocotb_tools.runner import get_runner
from scapy.all import Raw, RandString, Ether, TCP, IP
from utils import TCPSimSock, TCP_client_sim
from cocotbext.eth import GmiiFrame, RgmiiPhy
import logging

LOC_MAC_ADDR = "DEADBEEFCAFE"
MAC_SRC = "b025aa3306fe"
server_ip = "105.105.105.105"
server_port = 8080
dst_mac = ":".join([LOC_MAC_ADDR[i:i+2]
                    for i in range(0, len(LOC_MAC_ADDR)-1, 2)])
src_mac = ":".join([MAC_SRC[i:i+2]
                    for i in range(0, len(MAC_SRC)-1, 2)])


class TB:
    def __init__(self, dut, speed_100):
        self.dut = dut

        if speed_100:
            cocotb.start_soon(Clock(dut.clk, 40, units='ns').start())
            cocotb.start_soon(self._run_clocks(dut.phy_txc, 90, 40))
        else:
            cocotb.start_soon(self._run_clocks(dut.clk, 0, 8))
            cocotb.start_soon(self._run_clocks(dut.phy_txc, 90, 8))
        dut.rst.value = cocotb.handle.Immediate(1)
        self.rgmii_phy = RgmiiPhy(dut.phy_txd, dut.phy_txctl, dut.phy_txc,
                                  dut.phy_rxd, dut.phy_rxctl, dut.phy_rxc, dut.rst, speed=100e6 if speed_100 else 1000e6)

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
async def tcp_integration_basic(dut):
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100 is not None)

    await tb.reset()
    payload = Raw(RandString(size=120))
    test_data = Ether(dst=dst_mac, src=src_mac) / \
        IP() / TCP(sport=5000) / payload
    test_data.show2()
    test_frame = GmiiFrame.from_payload(bytes(test_data))
    await tb.rgmii_phy.rx.send(test_frame)
    rx_frame = await with_timeout(tb.rgmii_phy.tx.recv(), 50000, "ns")
    rx = Ether(rx_frame.get_payload())
    cocotb.log.info(rx[TCP].chksum)
    cocotb.log.info(rx[IP].chksum)
    actual_ip_chksum = rx[IP].chksum
    actual_tcp_chksum = rx[TCP].chksum
    del rx[TCP].chksum
    del rx[IP].chksum
    rx = rx.__class__(bytes(rx))
    rx.show2()
    assert rx[IP].chksum == actual_ip_chksum
    assert rx[TCP].chksum == actual_tcp_chksum
    assert rx_frame.check_fcs()
    assert rx.dst == src_mac.lower()
    assert rx[TCP].dport == 5000


class TCPIntegrated(TCPSimSock):
    def __init__(self, tb):
        self.tb = tb
        super().__init__(tb.dut.clk)

    async def send_pkt_to_hdl(self, pkt):
        await RisingEdge(self.tb.dut.clk)
        await ReadWrite()
        cocotb.log.info("packet to HDL")
        pkt = Ether(dst=dst_mac, src=src_mac) / pkt
        cocotb.log.info(pkt.show2(dump=True))
        test_frame = GmiiFrame.from_payload(bytes(pkt))
        await self.tb.rgmii_phy.rx.send(test_frame)

    async def recv_async(self):
        while True:
            rx_frame = await with_timeout(self.tb.rgmii_phy.tx.recv(), 50000, "ns")
            rx = Ether(rx_frame.get_payload())
            cocotb.log.info("packet received from HDL")
            cocotb.log.info(rx.show2(dump=True))
            assert rx_frame.check_fcs()
            self.from_hdl.put(rx, block=False)


class PacketGen:
    """
    Packets we want to send to the TCP HDL engine. Called by file descriptor named "tcp". 
    """

    def __init__(self, ip, port):
        self.payload = Raw(RandString(size=120))
        self.sent = False
        self.from_bench = Queue()

    def recv(self, n=None):
        cocotb.log.info("Packet gen triggered")
        self.sent = True
        return self.payload

    def empty(self):
        return self.sent or self.from_bench.empty()

    def send(self, pkt):
        pass


@cocotb.test()
async def tcp_integration_full(dut):
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100 is not None)

    await tb.reset()
    tb.dut.tcp_echo_en.value = 1
    client_ref = []
    client_ip = "192.168.1.1"
    client_port = 5000
    gen = PacketGen(client_ip, client_port)
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        TCPIntegrated(tb), client_ref, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    gen.from_bench.put_nowait(gen.payload)
    await Timer(5000, "ns")
    client_ref[0].stop(wait=False)
    await Timer(5000, "ns")


@pytest.mark.parametrize("speed_100", [False])
def test_simple_dff_runner(speed_100):
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
        f"../../config.vlt",
        f"{source_folder}/mac_encode.sv",
        f"{source_folder}/mac_decode.sv",
        f"./test_tcp_integration.sv",
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
        f"{source_folder}/clk_gen.sv",
        f"{source_folder}/clk_divider.sv",
        f"{source_folder}/crc32.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_tcp_integration",
        always=True,
        clean=True,
        waves=True,
        verbose=True,
        defines={"SPEED_100M": "True"} if speed_100 else {},
        includes=[f"{source_folder}/"],
        build_args=["--threads", "8", "--trace-fst",
                    "--trace-structs"] if sim == "verilator" else [
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                extra_env={"SPEED_100M": "True"} if speed_100 else {},
                hdl_toplevel="test_tcp_integration", test_module="test_tcp_integration")
