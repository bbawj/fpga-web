import cocotb
import os
from spi.utils import WinbondRAM
from cocotbext.spi import SpiBus
from pathlib import Path
from cocotb.triggers import RisingEdge, with_timeout
from cocotb.clock import Timer
from cocotb.utils import get_sim_steps
from cocotb_tools.runner import get_runner

LOC_MAC_ADDR = "DEADBEEFCAFE"
MAC_SRC = "b025aa3306fe"
server_ip = "192.168.69.69"
server_port = 8080
dst_mac = ":".join([LOC_MAC_ADDR[i:i+2]
                    for i in range(0, len(LOC_MAC_ADDR)-1, 2)])
src_mac = ":".join([MAC_SRC[i:i+2]
                    for i in range(0, len(MAC_SRC)-1, 2)])


class TB:
    def __init__(self, dut):
        self.dut = dut
        self.spi_bus = SpiBus.from_prefix(dut.spi, "spi", cs_name="cs")
        cocotb.start_soon(self._run_clocks(dut.clk_25mhz, 0, 40))
        cocotb.start_soon(self._run_clocks(dut.sysclk, 0, 8))
        cocotb.start_soon(self._run_clocks(dut.spiclk, 0, 8))
        cocotb.start_soon(self._run_clocks(dut.spiclk90, 90, 8))
        cocotb.start_soon(self._run_clocks(dut.sysclk90, 90, 8))
        dut.pll_locked.value = cocotb.handle.Immediate(1)
        dut.button.value = cocotb.handle.Immediate(1)
        dut.rst.value = cocotb.handle.Immediate(1)

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
        await RisingEdge(self.dut.sysclk)
        await RisingEdge(self.dut.sysclk)
        self.dut.rst.value = 1
        self.dut.rst.value = 1
        await RisingEdge(self.dut.sysclk)
        await RisingEdge(self.dut.sysclk)
        self.dut.rst.value = 0
        self.dut.rst.value = 0
        await RisingEdge(self.dut.sysclk)
        await RisingEdge(self.dut.sysclk)

        flash_offset = self.dut.OFFSET_IN_FLASH.value.to_unsigned()
        mem = {flash_offset: 0xDE}
        self.spi_slave = WinbondRAM(self.spi_bus, mem)
        self.spi_slave._sclk = self.dut.spiclk90
        self.spi_slave._miso = self.dut.flash_miso


@cocotb.test()
async def boot_mem_integrity(dut):
    tb = TB(dut)

    await tb.reset()
    num_bytes = dut.NUM_BYTES.value.to_unsigned()
    cocotb.log.info(
        f"Checking {num_bytes} bytes of SDRAM memory for asc values starting at 0xDE")
    await with_timeout(RisingEdge(dut.spi_en_stretched), 400, "us")
    await with_timeout(RisingEdge(dut.flash_done), 4, "ms")
    await with_timeout(RisingEdge(dut.mac_instance.http_rdy), 1, "ms")

    mem = dut.m.mem.value
    for i in range(int(num_bytes/4)):
        assert mem[i].to_unsigned() == (0xDE + i) & 0xFFFFFFFF

    cam_addr = dut.mac_instance.http_dec.cam.cam_addr.mem.value
    cam_size = dut.mac_instance.http_dec.cam.cam_size.mem.value
    for i in range(512):
        assert cam_addr[i].to_unsigned() == (0xDE + i) & 0xFFFFFFFF
    for i in range(512, 1024):
        assert cam_size[i & 511].to_unsigned() == (0xDE + i) & 0xFFFFFFFF


def test_boot():
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
        "../../config.vlt",
        "../../top.sv",
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

    content_file = "content_hex.mem"
    content_file_abs = Path(content_file).resolve()
    assert content_file_abs.exists()

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="top",
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        defines={"SIM": "True"},
        parameters={
            "HTTP_CONTENT_FILE": f'"{content_file_abs}"',
        },
        build_args=[
            "--threads", "8", "--trace-fst",
            "--trace-structs", "--bbox-unsup",
            "--timing"
        ] if sim == "verilator" else [
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                extra_env={"CONTENT_FILE": content_file_abs},
                hdl_toplevel="top", test_module="test_boot")
