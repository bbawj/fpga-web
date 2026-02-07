import os
import logging
import socket

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

class TcpPacketSV:
    """
    Python representation of SystemVerilog:
      typedef struct packed {
        logic [31:0] ip_source_addr;
        logic [BUFF_WIDTH-1:0] payload_addr;
        logic [15:0] payload_size;
        logic [15:0] checksum;
        logic [7:0]  flags;
        logic [15:0] peer_port;
        logic [15:0] window;
        logic [31:0] ack_num;
        logic [31:0] sequence_num;
      } packet_t;
    """

    FIELD_LAYOUT = [
        ("peer_addr", 32),
        ("peer_port",      16),
        ("payload_addr",   "BUFF_WIDTH"),  # resolved at runtime
        ("payload_size",   16),
        ("checksum",       16),
        ("flags",          8),
        ("window",         16),
        ("ack_num",        32),
        ("sequence_num",   32),
    ]

    def __init__(self, buff_width):
        self.buff_width = buff_width

        # field defaults
        self.peer_addr = 0
        self.payload_addr   = 0
        self.payload_size   = 0
        self.checksum       = 0
        self.flags          = 0
        self.peer_port      = 0
        self.window         = 0
        self.ack_num        = 0
        self.sequence_num   = 0

    # -------- construction helpers --------

    @classmethod
    def from_scapy(cls, packet, buff_width, payload_addr=0, checksum=0):
        """Create SV packet_t from a Scapy IP/TCP packet."""
        obj = cls(buff_width)

        obj.peer_addr = int.from_bytes(
            socket.inet_aton(packet["IP"].src), "big"
        )
        obj.payload_addr = payload_addr
        obj.payload_size = len(packet["TCP"].payload)
        obj.checksum = checksum
        obj.flags = int(packet["TCP"].flags)
        obj.peer_port = packet["TCP"].sport
        obj.window = packet["TCP"].window
        obj.ack_num = packet["TCP"].ack
        obj.sequence_num = packet["TCP"].seq

        return obj

    # -------- packing logic --------

    def _resolve_width(self, width):
        return self.buff_width if width == "BUFF_WIDTH" else width

    def total_width(self):
        return sum(self._resolve_width(w) for _, w in self.FIELD_LAYOUT)

    def pack_int(self):
        """Pack struct into a single integer (SV packed ordering)."""
        value = 0
        shift = self.total_width()

        for field, width in self.FIELD_LAYOUT:
            width = self._resolve_width(width)
            shift -= width
            field_val = getattr(self, field) & ((1 << width) - 1)
            value |= field_val << shift

        return value

    def to_binaryvalue(self):
        """Return cocotb BinaryValue ready for dut.packet assignment."""
        return BinaryValue(
            value=self.pack_int(),
            n_bits=self.total_width(),
            bigEndian=False  # packed structs map MSB→LSB; cocotb expects this
        )

    # -------- debug --------

    def __repr__(self):
        fields = ", ".join(f"{f}={getattr(self,f)}" for f,_ in self.FIELD_LAYOUT)
        return f"TcpPacketSV({fields})"


class ConnState:
    LISTEN = 0
    SYN_RECV = 1
    ESTABLISHED = 2
    FINWAIT = 3
    FINWAIT2 = 4
    CLOSEWAIT = 5
    CLOSING = 6
    LASTACK = 7
    TIMEWAIT = 8
    CLOSED = 9

    _names = {
        0: "LISTEN",
        1: "SYN_RECV",
        2: "ESTABLISHED",
        3: "FINWAIT",
        4: "FINWAIT2",
        5: "CLOSEWAIT",
        6: "CLOSING",
        7: "LASTACK",
        8: "TIMEWAIT",
        9: "CLOSED",
    }

    @classmethod
    def name(cls, val):
        return cls._names.get(val, f"UNKNOWN({val})")


class BitStreamReader:
    """
    MSB-first bit reader over BinaryValue.buff
    Matches SystemVerilog packed struct layout.
    """

    def __init__(self, binary_value):
        self.buff = binary_value.buff  # bytearray
        self.total_bits = len(self.buff) * 8
        # if the signal is not byte aligned e.g 180 bits, the buff attribute will include padded 0 bits
        pad_bits = (len(self.buff) * 8) - len(binary_value.binstr)
        self.bitpos = pad_bits  # MSB index

    def read_bits(self, width):
        """Read 'width' bits and return integer."""
        value = 0
        for _ in range(width):
            byte_index = self.bitpos // 8
            bit_index = 7 - (self.bitpos % 8)  # MSB-first

            bit = (self.buff[byte_index] >> bit_index) & 1
            value = (value << 1) | bit

            self.bitpos += 1

        return value


class PacketTDecoder:
    def __init__(self, buff_width=2):
        self.buff_width = buff_width

    def unpack(self, reader: BitStreamReader):
        pkt = {}

        pkt["peer_addr"] = reader.read_bits(32)
        pkt["peer_port"]      = reader.read_bits(16)
        pkt["payload_addr"]   = reader.read_bits(self.buff_width)
        pkt["payload_size"]   = reader.read_bits(16)
        pkt["checksum"]       = reader.read_bits(16)
        pkt["flags"]          = reader.read_bits(8)
        pkt["window"]         = reader.read_bits(16)
        pkt["ack_num"]        = reader.read_bits(32)
        pkt["sequence_num"]   = reader.read_bits(32)

        return pkt

    def signal_to_scapy(self, signal_value):
        reader = BitStreamReader(signal_value)
        pkt = self.unpack(reader)
        peer_addr = socket.inet_ntoa(pkt["peer_addr"].to_bytes(4))
        print(signal_value.buff)
        scap = IP(
                src="0.0.0.0",
                dst=peer_addr
        ) / TCP(
                dport=pkt["peer_port"],
                ack=pkt["ack_num"],
                seq=pkt["sequence_num"],
                flags=pkt["flags"]
                )
        return scap



class TcbDecoder:
    def __init__(self, buff_width, buff_size):
        self.buff_width = buff_width
        self.buff_size = buff_size
        self.packet_decoder = PacketTDecoder(buff_width)

    def from_signal(self, signal_value):
        reader = BitStreamReader(signal_value)
        tcb = {}

        # base
        tcb["peer_addr"] = reader.read_bits(32)
        tcb["peer_port"]    = reader.read_bits(16)
        tcb["sequence_num"]   = reader.read_bits(32)
        tcb["ack_num"]        = reader.read_bits(32)
        tcb["window"]         = reader.read_bits(16)

        # to_be_sent
        tcb["to_be_sent"] = [
            self.packet_decoder.unpack(reader)
            for _ in range(self.buff_size)
        ]

        tcb["to_be_sent_wr_ptr"] = reader.read_bits(self.buff_width + 1)
        tcb["to_be_sent_rd_ptr"] = reader.read_bits(self.buff_width + 1)

        # to_be_ack
        tcb["to_be_ack"] = [
            self.packet_decoder.unpack(reader)
            for _ in range(self.buff_size)
        ]

        tcb["to_be_ack_wr_ptr"] = reader.read_bits(self.buff_width + 1)
        tcb["to_be_ack_rd_ptr"] = reader.read_bits(self.buff_width + 1)

        tcb["state"] = reader.read_bits(4)

        return tcb


@cocotb.test()
async def tcp_sm(dut):
    tb = TB(dut)

    await tb.reset(tb.dut.rst)

    payload = Raw(RandString(size=120))
    packet = IP()/ TCP() / payload
    packet.show2()
    sv_packet = TcpPacketSV.from_scapy(packet, 2)
    tb.dut.packet.value = sv_packet.to_binaryvalue()
    tb.dut.tcp_packet_valid.value = 1
    tb.dut.tcp_packet_rx.value = 1
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)
    await RisingEdge(tb.dut.clk)

    assert tb.dut.sm_accept_payload.value == 1
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

    await RisingEdge(tb.dut.clk)
    assert tb.dut.pkt_tx_en.value == 1

    print(tb.dut.pkt_to_send.value.buff)
    print(tb.dut.pkt_to_send.value)
    s = PacketTDecoder().signal_to_scapy(tb.dut.pkt_to_send.value)
    s.show2()
    assert False


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
