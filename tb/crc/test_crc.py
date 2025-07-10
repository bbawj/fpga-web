import itertools
import logging

import cocotb
from cocotb.clock import Timer
from cocotb.binary import BinaryValue
from cocotbext.eth import GmiiFrame


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

    async def reset(self):
        await Timer(10, units='ns')



async def calc_crc(dut, payload_lengths=None, payload_data=None):
    tb = TB(dut)

    await tb.reset()

    test_frames = [payload_data(x) for x in payload_lengths()]

    for test_data in test_frames:
        test_frame = GmiiFrame.from_payload(test_data)
        for i, d in enumerate(test_frame.get_payload(strip_fcs=False)):
            tb.dut.din.value = BinaryValue(d & 0xF, 4, False, 0)
            tb.dut.crc_next.value = tb.dut.crc_out.value if i != 0 else 0xFFFFFFFF
            await Timer(10, units='ns')

            tb.dut.din.value = BinaryValue((d >> 4) & 0xF, 4, False, 0)
            tb.dut.crc_next.value = tb.dut.crc_out.value
            await Timer(10, units='ns')

        out = ~tb.dut.crc_out.value
        assert int(out, 2) == 0x2144DF1C


def size_list():
    return list(range(60, 128)) + [512, 1514] + [60]*10


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

@cocotb.test()
async def test_crc(dut):
    await calc_crc(dut, size_list, incrementing_payload)
