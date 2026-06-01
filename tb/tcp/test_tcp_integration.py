import pytest
import cocotb
import os
from pathlib import Path
from cocotb.triggers import RisingEdge, with_timeout
from cocotb.clock import Clock, Timer
from cocotb.utils import get_sim_steps
from cocotb_tools.runner import get_runner
from scapy.all import Raw, RandString, Ether, TCP, IP
from tcp.utils import TCPIntegrated, TCP_client_sim, PacketGen, PayloadLossyClient, TCP_rst_client
from cocotbext.eth import GmiiFrame, RgmiiPhy

LOC_MAC_ADDR = "DEADBEEFCAFE"
MAC_SRC = "b025aa3306fe"
server_ip = "105.105.105.105"
server_port = 8080
client_ip = "192.168.1.1"
client_port = 5000
dst_mac = ":".join([LOC_MAC_ADDR[i:i+2]
                    for i in range(0, len(LOC_MAC_ADDR)-1, 2)])
src_mac = ":".join([MAC_SRC[i:i+2]
                    for i in range(0, len(MAC_SRC)-1, 2)])


class TB:
    def __init__(self, dut, speed_100):
        self.dut = dut

        if speed_100:
            cocotb.start_soon(Clock(dut.clk, 40, units='ns').start())
            cocotb.start_soon(self._run_clocks(dut.clk90, 90, 40))
        else:
            cocotb.start_soon(self._run_clocks(dut.clk, 0, 8))
            cocotb.start_soon(self._run_clocks(dut.clk90, 90, 8))
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


@cocotb.test()
async def tcp_integration_full(dut):
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100 is not None)

    await tb.reset()
    tb.dut.tcp_echo_en.value = 1
    client_ref = []
    gen = PacketGen(client_ip, client_port)
    tcp = TCPIntegrated(tb, True, dst_mac, src_mac)
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    gen.from_bench.put(Raw(RandString(size=21)))
    await Timer(5000, "ns")
    gen.from_bench.put(Raw(RandString(size=20)))
    await Timer(5000, "ns")
    gen.from_bench.put(Raw(RandString(size=3)))
    await Timer(5000, "ns")
    gen.from_bench.put(Raw(RandString(size=4)))
    await Timer(5000, "ns")
    gen.from_bench.put(Raw(RandString(size=120)))
    await Timer(5000, "ns")
    client_ref[0].stop(wait=False)
    await Timer(5000, "ns")
    client_ref = []
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port + 123, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    client_ref[0].stop(wait=False)
    await Timer(5000, "ns")


@cocotb.test()
async def tcp_connect_multi(dut):
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100 is not None)

    await tb.reset()
    tb.dut.tcp_echo_en.value = 1
    client_ref = []
    gen = PacketGen(client_ip, client_port)
    tcp = TCPIntegrated(tb, True, dst_mac, src_mac)
    tcp2 = TCPIntegrated(tb, True, dst_mac, src_mac, dont_read=True)
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    gen.from_bench.put(Raw(RandString(size=21)))
    await Timer(5000, "ns")
    # expect to receive packets for the other client so multi set to True
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp2, client_ref, True, server_ip, server_port, client_ip, client_port + 123, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    client_ref[0].stop(wait=False)
    await Timer(10000, "ns")
    client_ref[1].forcestop(wait=False)
    await Timer(5000, "ns")


@cocotb.test()
async def tcp_lossy_payload(dut):
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100 is not None)

    await tb.reset()
    tb.dut.tcp_echo_en.value = 1
    client_ref = []
    gen = PacketGen(client_ip, client_port)
    tcp = TCPIntegrated(tb, True, dst_mac, src_mac)
    cocotb.start_soon(cocotb.task.bridge(PayloadLossyClient)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    gen.from_bench.put(Raw(RandString(size=21)))
    await Timer(45, "us")
    assert tcp.recv_count == 4
    client_ref[0].stop(wait=False)
    await Timer(10000, "ns")


@cocotb.test()
async def tcp_lossy_synack(dut):
    pass


@cocotb.test()
async def tcp_idle_timeout(dut):
    """
    TCB should transition from ESTABLISHED to FINWAIT after at maximum IDLE_TIMEOUT
    IDLE timeout is around 100us
    """
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100 is not None)

    await tb.reset()
    client_ref = []
    gen = PacketGen(client_ip, client_port)
    tcp = TCPIntegrated(tb, True, dst_mac, src_mac)
    cocotb.start_soon(cocotb.task.bridge(TCP_rst_client)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(2500, "ns")
    assert tcp.recv_count == 1
    await Timer(110, "us")
    assert tcp.recv_count == 3


@cocotb.test()
async def tcp_rst_in_established(dut):
    speed_100 = os.getenv("SPEED_100M", None)
    tb = TB(dut, speed_100 is not None)

    await tb.reset()
    client_ref = []
    gen = PacketGen(client_ip, client_port)
    tcp = TCPIntegrated(tb, True, dst_mac, src_mac)
    cocotb.start_soon(cocotb.task.bridge(TCP_rst_client)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    client_ref[0].stop(wait=False)
    await Timer(5000, "ns")
    cocotb.start_soon(cocotb.task.bridge(TCP_client_sim)(
        tcp, client_ref, False, server_ip, server_port, client_ip, client_port + 123, external_fd={"tcp": gen}))
    await Timer(5000, "ns")
    assert False

# @cocotb.test()


def check_check(dut):
    b = "b025aa3306fedeadbeefcafe0800450002a80001400040065ef269696969c0a845e21f90a1dcea449c16e5f36332501805b828c000003c21444f43545950452068746d6c3e0a3c68746d6c206c616e673d22656e223e0a3c686561643e0a202020203c6d65746120636861727365743d225554462d38223e0a202020203c6d657461206e616d653d2276696577706f72742220636f6e74656e743d2277696474683d6465766963652d77696474682c20696e697469616c2d7363616c653d312e30223e0a202020203c7469746c653e50616765204e6f7420466f756e643c2f7469746c653e0a202020203c7374796c653e0a2020202020202020626f6479207b20746578742d616c69676e3a2063656e7465723b2070616464696e673a2031353070783b20666f6e742d66616d696c793a2073616e732d73657269663b207d0a20202020202020206831207b20666f6e742d73697a653a20353070783b207d0a2020202020202020626f6479207b20666f6e742d73697a653a20323070783b20636f6c6f723a20233333333b207d0a202020202020202061207b20636f6c6f723a20233030376266663b20746578742d6465636f726174696f6e3a206e6f6e653b207d0a2020202020202020613a686f766572207b20746578742d6465636f726174696f6e3a20756e6465726c696e653b207d0a202020203c2f7374796c653e0a3c2f686561643e0a3c626f64793e0a202020203c6469763e0a20202020202020203c68313e3430343c2f68313e0a20202020202020203c703e536f7272792c20746865207061676520796f75277265206c6f6f6b696e6720666f7220646f65736e27742065786973742e3c2f703e0a20202020202020203c703e3c6120687265663d222f223e52657475726e20486f6d653c2f613e3c2f703e0a202020203c2f6469763e0a3c2f626f64793e0a3c2f68746d6c3e0a2ab37c1d"

    check(b, "")

    assert False


def check(b, payload):
    b = bytes.fromhex(b)
    frame = GmiiFrame.from_raw_payload(b)
    cocotb.log.info(frame.get_fcs())
    assert frame.check_fcs()
    pkt = Ether(b)
    actual_chksum = pkt[TCP].chksum
    pkt.show2()
    del pkt[TCP].chksum
    pkt = pkt.__class__(bytes(pkt))
    pkt.show2()

    correct_chksum = pkt[TCP].chksum
    cocotb.log.info(actual_chksum)
    cocotb.log.info(correct_chksum)
    if (payload != ""):
        del pkt[TCP].chksum
        pkt[TCP].payload = Raw(bytes.fromhex(payload))
        pkt = pkt.__class__(bytes(pkt))

        cocotb.log.info(pkt[TCP].chksum)


@pytest.mark.parametrize("speed_100", [False])
def test_simple_dff_runner(speed_100):
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
        "../../config.vlt",
        "./test_tcp_integration.sv",
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
        f"{source_folder}/tcb.sv",
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
                    "--trace-structs", "--bbox-unsup",
                    "-y", "/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/",
                    "-y", "/home/bawj/lscc/diamond/3.14/cae_library/simulation/vhdl/ecp5u/", "--timing"
                    ] if sim == "verilator" else [
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                extra_env={"SPEED_100M": "True"} if speed_100 else {},
                hdl_toplevel="test_tcp_integration", test_module="test_tcp_integration")
