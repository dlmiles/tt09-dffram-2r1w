# SPDX-FileCopyrightText: Copyright © 2024 Darryl Miles
# SPDX-License-Identifier: Apache-2.0

import os
from random import Random
import cocotb
from cocotb.clock import Clock
from cocotb.binary import BinaryValue
from cocotb.triggers import ClockCycles


# uio_in
LOHI_A = 0x10
LOHI_B = 0x20
W_EN   = 0x80

RANDOM_SEED = cocotb.RANDOM_SEED # int(os.getenv('RANDOM_SEED'))
#print(f"RANDOM_SEED={RANDOM_SEED}")
RANDOM = Random(RANDOM_SEED)


def calc_ui_in(ui_in: int, aa: int = 0, wd: int = 0) -> int:
    return ui_in | ((aa & 0xf) << 4) | (wd & 0xf)


def calc_uio_in(uio_in: int, we: bool = None, ab: int = None) -> int:
    if ab is not None:
        uio_in = (uio_in & 0xf0) | (ab & 0xf)
    if we is not None:
        if we:
            uio_in |= 0x80
        else:
            uio_in &= ~0x80
    return uio_in


def generate_data(mode: int, addr: int) -> int:
    if mode == 0:
        return 0x0
    elif mode == 1:
        return 0xf
    elif mode == 2:
        return ~addr & 0xf
    elif mode == 3:
        return (addr + 3) & 0xf
    elif mode == 4:
        return (addr + 4) & 0xf
    elif mode == 5:
        return RANDOM.randint(0, 0xf)
    else:
        return addr & 0xf


async def reset_into(dut, uio_in: int, cycles: int = 10) -> None:
    dut.rst_n.value = 0
    dut.uio_in.value = uio_in
    await ClockCycles(dut.clk, cycles)

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, cycles)

    return None


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    # Reset test latches
    await reset_into(dut, 0x7f)

    # Reset test latches to default
    await reset_into(dut, 0x00)

    dut._log.info("Start")

    ui_in = 0
    uio_in = 0
    #   0 addrhi
    #   4 read_buffer_a
    #   5 read_buffer_b
    #   6 write_through
    for reset_mode in [0x00, 0x30, 0x40, 0x70, 0x01, 0x31, 0x41, 0x71, 0x00, 0x30, 0x40, 0x70]:
        await reset_into(dut, reset_mode)
        for addr_b in range(16):
            for mode in [0x80, 0x00, 0x81, 0x01, 0x82, 0x02, 0x83, 0x03, 0x84, 0x04, 0x85, 0x05, 0x86, 0x06]:
                for addr in range(16):
                    addr_a = addr
                    #addr_b = 0
                    we = True if (mode & 0x80) else False

                    tmp_uio_in = calc_uio_in(uio_in, we=we, ab=addr_b)
                    bv_uio_in = BinaryValue(tmp_uio_in, n_bits=8)
                    dut.uio_in.value = bv_uio_in

                    wdata_a = generate_data(mode & 0xf, addr_a)

                    tmp_ui_in = calc_ui_in(ui_in, aa=addr_a, wd=wdata_a)
                    bv_ui_in = BinaryValue(tmp_ui_in, n_bits=8)
                    dut.ui_in.value = bv_ui_in

                    wedesc = 'WE' if (we) else '  '
                    dut._log.info(f"ui_in ={str(bv_ui_in)} uio_in={str(bv_uio_in)}  AD_A={addr_a:#2x} AD_B={addr_b:#2x}  {wedesc} WDATA_A={wdata_a:#2x}")

                    await ClockCycles(dut.clk, 1)
                    bv_uio_in = BinaryValue(tmp_uio_in | LOHI_A | LOHI_B, n_bits=8)
                    dut.uio_in.value = bv_uio_in

                    tmp_uo_out = dut.uo_out.value
                    if tmp_uo_out.is_resolvable:
                        rdata_a = tmp_uo_out & 0xf
                        rdata_b = (tmp_uo_out >> 4) & 0xf
                    else:
                        rdata_a = 0
                        rdata_b = 0
                    dut._log.info(f"uo_out={str(tmp_uo_out)}  RDATA_A={rdata_a} RDATA_B={rdata_b}")

                    await ClockCycles(dut.clk, 1)
                    bv_uio_in = BinaryValue(tmp_uio_in, n_bits=8)
                    dut.uio_in.value = bv_uio_in

                await ClockCycles(dut.clk, 10)

    # trailer
    await ClockCycles(dut.clk, 20)
