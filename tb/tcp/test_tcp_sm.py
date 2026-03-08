import os
import logging
from utils import *
from scapy.all import Raw, RandString

import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock, Timer
from cocotb.triggers import RisingEdge, with_timeout, ReadWrite


class TB(TCPSimSock):
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        cocotb.start_soon(Clock(dut.clk, 8, units='ns').start())
        super().__init__(self.dut.clk, self.dut.tcp_arb_rdy,
                         self.dut.packet, self.dut.tcp_packet_rx, self.dut.pkt_tx_en, self.dut.pkt_to_send)

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
        self.dut.tcp_packet_rx.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

    def recv_checks(self, pkt):
        calculated_from_hdl = pkt.chksum
        del pkt.chksum
        pkt.show2()
        assert pkt.chksum == calculated_from_hdl

    def send(self, pkt):
        super().send(pkt)

        if len(pkt[TCP].payload) == 0:
            assert self.dut.sm_accept_payload.value == 0
            assert self.dut.sm_reject_payload.value == 1
        else:
            assert self.dut.sm_accept_payload.value == 1
            assert self.dut.sm_reject_payload.value == 0

    async def send_pkt_to_hdl(self, pkt):
        await super().send_pkt_to_hdl(pkt)

        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)


class PacketGen:
    """
    Packets we want to send to the TCP HDL engine. Called by file descriptor named "tcp". 
    """

    def __init__(self, ip, port):
        self.payload = Raw(RandString(size=120))
        self.queue = Queue()

    def recv(self, n=None):
        cocotb.log.info("Packet gen triggered")
        return self.queue.get()


@cocotb.test()
async def tcp_tcb_creation(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.rst)

    payload = Raw(RandString(size=120))
    packet = IP() / TCP(sport=5000) / payload
    packet.show2()
    sv_packet = TcpPacketSV.from_scapy(packet, 2)
    tb.dut.packet.value = sv_packet.to_binaryvalue()
    tb.dut.tcp_packet_rx.value = 1
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)

    assert tb.dut.sm_reject_payload.value == 1
    decoder = TcbDecoder(
        buff_width=2,
        buff_size=4
    )
    tcb = decoder.from_signal(tb.dut.tcb_sm.value)
    # check that a new TCB is created with expected parameters
    assert tcb["peer_addr"] == sv_packet.peer_addr
    assert tcb["peer_port"] == sv_packet.peer_port
    assert tcb["ack_num"] == sv_packet.sequence_num + 1
    assert tcb["sequence_num"] != 0
    assert tcb["state"] == 1


@cocotb.test()
async def tcp_sim(dut):
    client_ip = "192.168.1.1"
    client_port = 5000
    server_ip = "0.0.0.0"
    server_port = 80
    gen = PacketGen(client_ip, client_port)
    tb = TB(dut)
    await tb.reset(tb.dut.rst)
    client_ref = []
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tb, client_ref, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(1000, "ns")

    # tb.dut.tcp_echo_en.value = 1
    # await Timer(1000, "ns")

    client_ref[0].stop(wait=False)
    await Timer(200, "ns")


def test_tcp_sm():
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
        f"{source_folder}/tcp.sv",
        f"{source_folder}/tcp_sm.sv",
        f"{source_folder}/tcp_arbiter.sv",
        f"{source_folder}/lfsr_rng.sv",
        f"{source_folder}/pulse_gen.sv",
        "test_tcp_sm.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_tcp_sm",
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        build_args=["--threads", "8", "--trace-fst",
                    "--trace-structs"] if sim == "verilator" else [],
        # build_args=["-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                hdl_toplevel="test_tcp_sm", test_module="test_tcp_sm,")
