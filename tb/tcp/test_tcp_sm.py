import os
import logging
from utils import *

import cocotb
from scapy.all import TCP_client
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock, Timer
from cocotb.triggers import RisingEdge, with_timeout, ReadWrite


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        # payload = Raw(RandString(size=120))
        # self.packet = IP() / TCP(sport=5000) / payload
        # self.packet.show2()
        self.pkt_decoder = PacketTDecoder()
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

    async def send_pkt_to_hdl(self, pkt):
        await RisingEdge(self.dut.clk)
        await ReadWrite()
        sv_packet = TcpPacketSV.from_scapy(pkt, 2)
        self.dut.packet.value = sv_packet.to_binaryvalue()
        self.dut.tcp_packet_valid.value = 1
        self.dut.tcp_packet_rx.value = 1


    async def recv_pkt_from_hdl(self):
        await with_timeout(RisingEdge(self.dut.pkt_tx_en), 100, "us")

        s = self.pkt_decoder.signal_to_scapy(self.dut.pkt_to_send.value)
        print("Test Bench trying to send packet:")
        s.show2()
        return s

    def recv(self):
        return cocotb.task.resume(self.recv_pkt_from_hdl)()

    def send(self, pkt):
        cocotb.task.resume(self.send_pkt_to_hdl)(pkt)

    @staticmethod
    def select(sockets, remain=None):
        # first element is "cmdin" we are trying to return ourselves back to Automaton i.e. listen_socket
        return [sockets[1]]

    def close(self):
        self.closed = True
        pass

    def __del__(self):
        pass

    def __exit__(self, exc_type, exc_value, traceback):
        # type: (Optional[Type[BaseException]], Optional[BaseException], Optional[Any]) -> None  # noqa: E501
        """Close the socket"""
        pass


# @cocotb.test()
# async def tcp_sm(dut):
#     tb = TB(dut)
#
#     await tb.reset(tb.dut.rst)
#
#     payload = Raw(RandString(size=120))
#     packet = IP() / TCP(sport=5000) / payload
#     packet.show2()
#     sv_packet = TcpPacketSV.from_scapy(packet, 2)
#     tb.dut.packet.value = sv_packet.to_binaryvalue()
#     tb.dut.tcp_packet_valid.value = 1
#     tb.dut.tcp_packet_rx.value = 1
#     await RisingEdge(tb.dut.clk)
#     await RisingEdge(tb.dut.clk)
#     await RisingEdge(tb.dut.clk)
#     await RisingEdge(tb.dut.clk)
#
#     assert tb.dut.sm_accept_payload.value == 1
#     decoder = TcbDecoder(
#             buff_width=2,
#             buff_size=4
#     )
#     tcb = decoder.from_signal(tb.dut.tcb_sm.value)
#     # check that a new TCB is created with expected parameters
#     assert tcb["peer_addr"] == sv_packet.peer_addr
#     assert tcb["peer_port"] == sv_packet.peer_port
#     assert tcb["ack_num"] == sv_packet.sequence_num + 1
#     assert tcb["sequence_num"] != 0
#     assert tcb["state"] == 1
#
#     await RisingEdge(tb.dut.clk)
#     assert tb.dut.pkt_tx_en.value == 1
#
#     s = PacketTDecoder().signal_to_scapy(tb.dut.pkt_to_send.value)
#     print("Test Bench trying to send packet:")
#     s.show2()
#     assert False


@cocotb.test()
async def tcp_sim(dut):
    tb = TB(dut)
    await tb.reset(tb.dut.rst)
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(tb))
    await Timer(1000, "ns")
    assert False


class TCP_client_sim(TCP_client):
    def __init__(self, tb):
        self.tb = tb
        super().__init__(sock=self.tb)

    def parse_args(self, **kargs):
        print(self.tb)
        # Call parent with simulation IPs
        super().parse_args("0.0.0.0", 80, debug=10, srcip="192.168.1.1", **kargs)

    def _do_start(self, *args, **kargs):
        ready = Dummy()
        args=(ready,) + (args)
        super().run(wait=False)
        super()._do_control(*args, **kargs)
        print("yeet")

    def syn_ack_timeout(self):
        raise self.CLOSED()

class Dummy:
    def set(self):
        pass

def test_tcp_sm():
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
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
        build_args=["--threads", "8", "--trace-fst", "--trace-structs"] if sim == "verilator" else [],
        # build_args=["-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                hdl_toplevel="test_tcp_sm", test_module="test_tcp_sm,")
