import socket
import cocotb
from cocotb.clock import Clock, Timer
from scapy.all import TCP, IP, TCP_client
from cocotb.triggers import RisingEdge, ReadWrite
from multiprocessing import Queue
from cocotb.types import LogicArray


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
        ("payload_addr",   19),  # resolved at runtime
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
        self.payload_addr = 0
        self.payload_size = 0
        self.checksum = 0
        self.flags = 0
        self.peer_port = 0
        self.window = 0
        self.ack_num = 0
        self.sequence_num = 0

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
        return LogicArray.from_unsigned(
            self.pack_int(),
            self.total_width(),
            # packed structs map MSB→LSB; cocotb expects this
        )

    # -------- debug --------

    def __repr__(self):
        fields = ", ".join(f"{f}={getattr(self,f)}" for f,
                           _ in self.FIELD_LAYOUT)
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
        pkt["peer_port"] = reader.read_bits(16)
        pkt["payload_addr"] = reader.read_bits(19)
        pkt["payload_size"] = reader.read_bits(16)
        pkt["checksum"] = reader.read_bits(16)
        pkt["flags"] = reader.read_bits(8)
        pkt["window"] = reader.read_bits(16)
        pkt["ack_num"] = reader.read_bits(32)
        pkt["sequence_num"] = reader.read_bits(32)

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
            sport=80,
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
        tcb["peer_port"] = reader.read_bits(16)
        tcb["sequence_num"] = reader.read_bits(32)
        tcb["ack_num"] = reader.read_bits(32)
        tcb["window"] = reader.read_bits(16)

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


class TCP_client_sim(TCP_client):
    def __init__(self, sock, ref, *args, **kargs):
        self._sock = sock
        ref.append(self)
        super().__init__(*args, sock=self._sock, **kargs)

    def parse_args(self, *args, **kargs):
        print(f"TB: {self._sock}")
        # Call parent with simulation IPs
        super().parse_args(*args, debug=3, **kargs)

    def _do_start(self, *args, **kargs):
        class Dummy:
            def set(self):
                pass
        ready = Dummy()
        args = (ready,) + (args)
        super().run(wait=False)
        super()._do_control(*args, **kargs)
        assert False, "TCP died due to exception"

    def master_filter(self, pkt):
        assert IP in pkt
        assert pkt[IP].src == self.dst
        assert pkt[IP].dst == self.src
        assert TCP in pkt
        assert pkt[TCP].sport == self.dport
        assert pkt[TCP].dport == self.sport
        if pkt[TCP].flags == "A":
            assert self.l4[TCP].ack == pkt[TCP].seq
        assert self.l4[TCP].seq >= pkt[TCP].ack  # XXX: seq/ack 2^32 wrap up  # noqa: E501
        assert ((self.l4[TCP].ack == 0) or (
            self.sack <= pkt[TCP].seq <= self.l4[TCP].ack + pkt[TCP].window))  # no
        # assert super().master_filter(pkt), f"What? {self.l4.show2(dump=True)}"
        return True

    def syn_ack_timeout(self):
        pass


class TCPSimSock:
    def __init__(self, sig_clk, sig_rdy=None, sig_pkt=None, sig_pkt_rx=None, sig_pkt_txen=None, sig_pkt_to_send=None):
        self.from_hdl = Queue()
        self.pkt_decoder = PacketTDecoder()
        self.sig_clk = sig_clk
        self.sig_rdy = sig_rdy
        self.sig_pkt = sig_pkt
        self.sig_pkt_rx = sig_pkt_rx
        self.sig_pkt_tx_en = sig_pkt_txen
        self.sig_pkt_to_send = sig_pkt_to_send
        cocotb.start_soon(self.recv_async())

    async def reset_pkt_sent(self):
        await RisingEdge(self.sig_clk)
        await ReadWrite()
        if self.sig_pkt_rx is not None:
            self.sig_pkt_rx.value = 0

    def send(self, pkt):
        cocotb.log.info("Simulator trying to send packet:")
        cocotb.task.resume(self.send_pkt_to_hdl)(pkt)

    async def send_pkt_to_hdl(self, pkt):
        await RisingEdge(self.sig_clk)
        while self.sig_rdy.value == 0:
            await RisingEdge(self.sig_clk)
            await ReadWrite()
        cocotb.log.info("packet to HDL")
        # pkt.show2()
        sv_packet = TcpPacketSV.from_scapy(pkt, 2)
        self.sig_pkt.value = sv_packet.to_binaryvalue()
        self.sig_pkt_rx.value = 1
        await self.reset_pkt_sent()

    async def recv_async(self):
        while True:
            await RisingEdge(self.sig_pkt_tx_en)
            cocotb.log.info("Test Bench trying to send packet:")
            # TODO: check no packet then just quickly return
            s = self.pkt_decoder.signal_to_scapy(self.sig_pkt_to_send.value)
            self.recv_checks(s)
            s.show2()
            self.from_hdl.put(s, block=False)

    def recv_checks(self, pkt):
        """
        Override to do test specific checks
        """
        calculated_from_hdl = pkt.chksum
        del pkt.chksum
        pkt.show2(dump=True)
        assert False
        assert pkt.chksum != calculated_from_hdl

    async def recv_pkt_from_hdl(self):
        await RisingEdge(self.sig_clk)
        if self.from_hdl.empty():
            return None
        return self.from_hdl.get()

    def recv(self):
        return cocotb.task.resume(self.recv_pkt_from_hdl)()

    @ staticmethod
    def select(sockets, remain=None):
        # first element is "cmdin" we are trying to return ourselves back to Automaton i.e. listen_socket
        new = []
        for s in sockets:

            if hasattr(s, "from_hdl") and s.from_hdl.empty():
                continue
            if hasattr(s, "from_bench") and s.from_bench.empty():
                continue
            if hasattr(s, "empty") and s.empty():
                continue
            if hasattr(s, "rd"):
                if hasattr(s.rd, "empty") and s.rd.empty():
                    continue
            new.append(s)

        if len(new) == 0:
            cocotb.task.resume(TCPSimSock.move_sim_time)()
        return new

    @ staticmethod
    async def move_sim_time():
        await Timer(10, "ns")

    def close(self):
        self.closed = True
        pass

    def __del__(self):
        pass

    def __exit__(self, exc_type, exc_value, traceback):
        # type: (Optional[Type[BaseException]], Optional[BaseException], Optional[Any]) -> None  # noqa: E501
        """Close the socket"""
        pass
