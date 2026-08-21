import cocotb
from cocotb.clock import Timer
from cocotb.triggers import FallingEdge, First, select, ReadWrite
from cocotbext.spi import SpiSlaveBase, SpiConfig, SpiFrameError


class WinbondRAM(SpiSlaveBase):
    _config = SpiConfig(
        word_width=8,     # all parameters optional
        sclk_freq=125e6,   # these are the defaults
        cpol=False,
        cpha=False,
        msb_first=True,
        data_output_idle=0,
        cs_active_low=True  # optional (assumed True)
    )

    def __init__(self, bus, mem=None):
        self.values = {"inst": 0, "addr": 0}
        self.mem = mem
        super().__init__(bus)

    async def get_values(self):
        await self.idle.wait()
        return self.values

    async def _byte_2_bit(self, frame_end, b):
        for i in range(self._config.word_width):
            self._miso.value = bool(
                b & (1 << (self._config.word_width - 1 - i)))
            s = await First(FallingEdge(self._sclk), frame_end)
            t = await First(Timer(1.5, unit="ns"), frame_end)
            assert frame_end not in (
                s, t), "SPI ended in the middle of transaction"

    async def _transaction(self, frame_start, frame_end) -> None:
        await frame_start
        self.idle.clear()
        if bool(self._sclk.value):
            raise SpiFrameError(
                "sclk should be low at chip select edge")

        self.values["inst"] = int(await self._shift(8))
        if (self.values["inst"] != 0x9f):
            self.values["addr"] = int(await self._shift(24))
            starting_val = self.mem[self.values["addr"]]
        # FIXME: the behavior does not match the data sheet. MISO only changes
        # 1 cycle after the last MOSI bit. workaround here:
        await FallingEdge(self._sclk)

        counter = 0
        if (self.values["inst"] != 0x9f):
            while True:
                task = cocotb.start_soon(self._byte_2_bit(
                    frame_end, starting_val >> (8*counter)))
                s = await First(task, frame_end)
                if (counter == 3):
                    counter = 0
                    starting_val += 1
                else:
                    counter += 1
                if s == frame_end:
                    task.cancel()
                    break
        else:
            await self._byte_2_bit(frame_end, 0xDE)
            await frame_end
