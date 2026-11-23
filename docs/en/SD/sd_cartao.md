# SD card in the SoC: raw access and file system

🌐 [Português](../../pt-br/SD/sd_cartao.md) · [English](../../en/SD/sd_cartao.md)

## 1. Overview

The [sd_native](sd_native.md) controller moves one 512-byte block per command, by polling, and knows no card format. The software chooses how the card is organized, and the DE0-CV DOOM platform uses two forms, both read-only.

| Form | Platform name | Build variable | Card | Prepared by |
| :--- | :--- | :--- | :--- | :--- |
| Raw (direct mapped) | `sdcard_direct_mapped` | `SDFS=raw` | Header, index and payload written at fixed sectors, with no file system | `scripts/sdwrite.py` of DOOM |
| FatFs | `sdcard_FatFs` | `SDFS=fatfs` | Ordinary FAT32, with the files as files | The file explorer of the operating system |

| Criterion | Raw | FatFs |
| :--- | :--- | :--- |
| Preparing the card | A script erases the partition table and writes the image; the card stops being FAT32 | Format and copy files, no script |
| Code in the SoC | Only the sd_native driver, the header and the index | Driver, ChaN FatFs and a thin disk layer |
| Replacing or adding a file | Rewrite the whole card | Copy the file |
| Reading a byte of a file | Sector and offset computed directly, no FAT walk | Walks the FAT, with `FF_USE_FASTSEEK` for long jumps |
| Using the card in other computers | No, the system sees it without a file system | Yes |

In both forms the controller is the same and the read of one block is the one in section 5.

## 2. sd_native registers

The word address is the register number, and the byte address is the word times 4. In the DOOM platform the base is `0x80008000`. The bits of each register, the errors and the timing are in [sd_native.md](sd_native.md), section 4.

| Word | Address | Name | Access | Use in the software |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `0x80008000` | `ARG` | R/W | Argument of the next command; for CMD17, the sector number |
| 1 | `0x80008004` | `CMD` | R/W | The write starts the command: index, response format, busy wait and data block |
| 2 to 5 | `0x80008008` to `0x80008014` | `RESP0` to `RESP3` | R | Short response in `RESP0` and `RESP1`; long response (CID or CSD) in the four words |
| 6 | `0x80008018` | `STATUS` | R/W1C | `CMD_BUSY`, `DATA_BUSY`, `CMD_DONE`, `DATA_DONE`, `CMD` and `DAT` levels |
| 7 | `0x8000801C` | `ERROR` | R/W1C | Ten persistent command and data errors |
| 8 | `0x80008020` | `CONTROL` | R/W | `CLK_ENABLE`, `WIDE_BUS`, interrupt enables, `ABORT` |
| 9 | `0x80008024` | `DIVIDER` | R/W | `SD_CLK` divider |
| 10 | `0x80008028` | `TIMEOUT` | R/W | Wait limit for data and busy, in card clocks |
| 11 | `0x8000802C` | `DATA` | R/W | Window of the 128-word buffer; each access advances `PTR` |
| 12 | `0x80008030` | `PTR` | R/W | Buffer word pointed to, 0 to 127 |

With the core clock at 100 MHz, the card clock is

$$ f_{SD\_CLK} = \frac{100\ \text{MHz}}{2 \cdot (\text{DIVIDER} + 1)} $$

and divider 1 gives the 25 MHz of the default speed mode. Card identification needs at most 400 kHz, which is divider 124.

### 2.1. Registered bus

Write, address and data of the bus are registered once inside the peripheral, and the next cycle applies the writes to `CMD`, to `CONTROL.ABORT`, to `STATUS`, to `ERROR` and to `DATA`. The reads of `STATUS`, `ERROR`, `CMD` and the interrupt output already include the effect of that pending write, so the software sees the same as it would without the register: a read of `STATUS` right after writing `CMD` already shows `CMD_BUSY`. Reads gain no wait cycle, and `ARG`, `CONTROL`, `DIVIDER`, `TIMEOUT` and `PTR` follow the write in the same cycle.

| Effect | Difference |
| :--- | :--- |
| Start of the frame on `SD_CMD` after the write to `CMD` | 1 more core cycle, invisible next to an `SD_CLK` of 40 ns or more |
| End of command, end of data and errors | Appear 1 cycle later, consistently with each other |
| Write to `DATA` | Reaches the buffer 1 cycle later, and a read of the same address in the next cycle receives the new data |

## 3. Preparing the card

### 3.1. Raw card

The image has three regions, all in 512-byte sectors and little endian.

| Region | Sector | Content |
| :--- | ---: | :--- |
| Header | 2048 | Magic `DOOM` and `SD01`, version, flags, number of WADs, index sectors, sector, size and CRC-32 of the payload, destination address in the SDRAM and CRC-32 of the index; the last 4 bytes of the sector are the CRC-32 of the previous 508 |
| Index | 2049 onward | 128 bytes per WAD (name, title, subtitle, address, size and kind), 4 entries per sector |
| Payload | First multiple of 8 after the index (2056 with 24 WADs) | The `wads.bin`, unchanged |

The `scripts/sdwrite.py` of DOOM builds the image and writes it, always with Python through `uv`.

```bash
uv run --no-project scripts/sdwrite.py --dry-run --target /dev/mmcblk0
uv run --no-project scripts/sdwrite.py --target /dev/mmcblk0
```

| Safeguard | Reason |
| :--- | :--- |
| Name the device on the command line | The script does not guess the disk |
| Only a whole SD, MMC or removable disk, with no mounted partition | Refuses any other kind of device |
| Confirm the name by typing it or with `--confirm` | Avoids erasing the wrong disk |
| Image file as target | Skips the disk safeguards, to test without a card |

The write erases the partition table, and the card stops being FAT32.

### 3.2. FAT32 card

The card is ordinary, with no script. The full guide is `docs/pt-br/CARTAO-FATFS.md` of DOOM, and the summary is this.

1. Format as FAT32, with a cluster of 32 KB or more, which keeps the FAT short. On Linux, `sudo mkfs.vfat -F 32 -s 64 -n DOOM /dev/sdX1`. On Windows, allocation unit size 32 KB, or `format fs=fat32 unit=32768 quick` in `diskpart` for cards above 32 GB. Formatting erases the whole card.
2. Copy `DOOM.WAD`, `DOOM2.WAD`, `PLUTONIA.WAD` and `TNT.WAD` to the root, with names in the 8.3 format.
3. For Master Levels, create the `MASTER` folder and copy the 20 levels and `DOOM2.MAP`. It only appears in the menu together with `DOOM2.WAD`.
4. Eject the card through the system.

The menu shows only what it finds on the card.

## 4. Software layers

### 4.1. sd_native driver

The same driver (`port/doom_sd.c` of DOOM) serves both forms. It initializes the card, reads sectors with CMD17 by polling, retries a failed read up to 3 times and keeps 8 sectors in a small cache for reads that do not cover a whole sector. It uses no interrupt: the enable bits of `CONTROL` stay at 0.

### 4.2. Raw form

The software reads the header at sector 2048, checks the CRC-32 and the index, and computes the sector of each WAD from the payload offset. A data read is a loop of CMD17 over the sectors of the range, without going through an allocation table.

### 4.3. FatFs form

The ChaN [FatFs](http://elm-chan.org/fsw/ff/) runs over a thin disk layer (`port/doom_diskio.c`) that connects disk initialization and sector reads to the sd_native driver. The configuration (`port/ffconf.h`) is the smallest the game needs.

| Option | Value | Effect |
| :--- | :--- | :--- |
| `FF_FS_READONLY` | 1 | No writes; the card is never altered |
| `FF_USE_LFN` | 0 | 8.3 names only |
| `FF_USE_FASTSEEK` | 1 | A jump inside a large file does not walk the FAT |
| `FF_USE_MKFS` | 0 | No formatting by the SoC |
| `FF_FS_EXFAT` | 0 | FAT12, FAT16 and FAT32 only; the card is FAT32 |
| `FF_MULTI_PARTITION` | 0 | One logical drive: the first MBR partition, or the volume with no MBR |
| `FF_MIN_SS` and `FF_MAX_SS` | 512 | 512-byte sector |

The disk layer hands the read straight to the destination when it is 4-byte aligned, and goes through a one-sector buffer when it is not, because the controller buffer is read in 32-bit words. The card capacity comes from CMD9, read once at initialization.

## 5. Initialization sequence and reading a block

The driver follows the specification sequence for SDHC and SDXC.

| Step | Action | Check |
| ---: | :--- | :--- |
| 1 | Aborts any operation, clears `CONTROL` and writes the identification divider to `DIVIDER` | Divider 124, 400 kHz |
| 2 | Turns on `CLK_ENABLE` for 2 ms and turns it off | At least 74 clocks with `CMD` at 1 |
| 3 | CMD0, no response | No `ERROR` |
| 4 | CMD8 with `0x000001AA`, short response | The low 12 bits of `RESP0` are `0x1AA`; no response means no card; different means unsupported card |
| 5 | Repeats CMD55 and ACMD41 with `0x40FF8000` (response without CRC) every 5 ms, for up to 1.2 s | Bit 31 of `RESP0` at 1 |
| 6 | Checks bit 30 of `RESP0`, the CCS | At 0 it is an SDSC card, refused |
| 7 | CMD2 (long response) and CMD3 | RCA in bits 31 to 16 of `RESP0` |
| 8 | CMD9 with the RCA (long response) | If the CSD is version 2, the capacity is $(C\_SIZE + 1) \cdot 1024$ sectors; a failure here does not prevent use |
| 9 | CMD7 with the RCA and `WAIT_BUSY` | Card in the transfer state |
| 10 | CMD55 and ACMD6 with argument 2, then `WIDE_BUS` in `CONTROL` | Four data lines |
| 11 | `DIVIDER` to 1 and `TIMEOUT` to 5000000 | 25 MHz, 0.2 s limit |

Reading a sector is one command: write the sector number to `ARG` (an SDHC card addresses by sector, not by byte), write CMD17 with a short response and `DATA_EN` to `CMD`, wait for `CMD_DONE` and `DATA_DONE` in `STATUS`, clear the flags, check `ERROR`, point `PTR` to 0 and read 128 words of `DATA`. During `DATA_BUSY` the software does not access `DATA`, because the data controller owns the buffer.

```c
#include <stdbool.h>
#include <stdint.h>

#define SD_BASE ((volatile uint32_t *)0x80008000u)

enum { ARG = 0, CMD = 1, STATUS = 6, ERROR = 7, DATA = 11, PTR = 12 };
enum { CMD_DONE = 1u << 2, DATA_DONE = 1u << 3 };
enum { CMD17 = 17u, RSP_R1 = 1u << 6, DATA_EN = 1u << 9 };

/* Reads the 512-byte sector into words, with the card already initialized. */
bool sd_read_sector(uint32_t sector, uint32_t words[static 128])
{
    SD_BASE[ARG] = sector;
    SD_BASE[CMD] = CMD17 | RSP_R1 | DATA_EN;
    while ((SD_BASE[STATUS] & (CMD_DONE | DATA_DONE)) != (CMD_DONE | DATA_DONE)) {
    }
    SD_BASE[STATUS] = CMD_DONE | DATA_DONE;
    uint32_t errors = SD_BASE[ERROR];
    SD_BASE[ERROR] = errors;
    if (errors != 0u) {
        return false;
    }
    SD_BASE[PTR] = 0;
    for (uint32_t i = 0; i < 128u; i++) {
        words[i] = SD_BASE[DATA];
    }
    return true;
}
```

A real read bounds the wait, aborts the command in `CONTROL` when the limit expires and repeats the read. The complete initialization example, with the writes, is in [sd_native.md](sd_native.md), section 6.3.

## 6. Enabling it in the DOOM platform

The peripheral enters the `platform.yaml` of the platform, under `peripherals`, with the type `sd_native` and the address. The peripheral clock is the core clock (`clocks.core`, 100 MHz), and the interrupt line the map assigns to it stays unused, because the driver polls.

```yaml
SD:
  kind: sd_native
  base: 0x80008000
```

After editing the file, `riscv-tools generate-memory-map` regenerates the map and the top, and `memory_map.h` carries the SD base. The driver uses `0x80008000` when the constant does not exist. The DOOM build variables that choose the form are `SD=demand ONDEMAND=1` (the WADs stay only on the card) and `SDFS=raw` or `SDFS=fatfs`.

## 7. Limitations

| Limitation | Detail |
| :--- | :--- |
| SDHC and SDXC only | The driver checks the CCS bit of the OCR and refuses SDSC cards, which address by byte |
| Read only | The controller can write blocks (CMD24, tested in simulation), but the platform driver, FatFs and the disk layer only read |
| Capacity (CMD9) | Read at initialization in both forms, but only FatFs uses it; a failure does not prevent block reads |
| Long names | FatFs runs without long names; a FAT32 card mixing long and short names was not tested |
| Interrupt | The driver polls; the controller interrupt path is not exercised by the platform |
| Validation on a real card | FatFs was tested on the board with a 30 GB FAT32 card, formatted with a 32 KB cluster, and the 5 games (DOOM, DOOM II, Plutonia, TNT and Master Levels) |

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).
