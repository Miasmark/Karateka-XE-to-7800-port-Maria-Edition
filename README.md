# Karateka: Atari XE to Atari 7800 port, MARIA Edition

A second version of the Atari 7800 port of the Atari XE Game System
cartridge of *Karateka*. The
[stable port](https://github.com/Miasmark/Karateka-XE-to-7800-port) keeps
the XE's way of drawing: the game draws into a bitmap, and the 7800 shows
that bitmap. The MARIA Edition draws the game the 7800's own way. Fighters,
hit stars, Akuma, the hawk, the scenery, the text and the status bar are
all MARIA objects and tiles, kept in the second half of a BankSet
cartridge, which only MARIA reads (v1 also copies some of them into
cartridge RAM as each scene loads). No scene draws into a bitmap.

There are two builds of it, v1 and V2 (below). Like the stable port, the
build reads your own dump of the XE cartridge and reassembles the game as
a 7800 cartridge.

**This repository contains no game code or data.** You need your own copy of
the XE cartridge (`Karateka.car`) to build anything.

## The three versions

| | Stable port | MARIA Edition v1 | MARIA Edition V2 |
|---|---|---|---|
| Repository | [Karateka-XE-to-7800-port](https://github.com/Miasmark/Karateka-XE-to-7800-port) | this one | this one |
| Cartridge | 128K SuperGame, 16K RAM at `$4000` (A78 type `$0006`) | 2 × 128K BankSet, one 16K RAM at `$4000` shared by both halves (`$2006`) | 2 × 128K BankSet, no cartridge RAM (`$2002`) |
| How the picture is drawn | the game's own blitter into a bitmap, shown through MARIA | MARIA objects and tile sets from the cartridge's MARIA half; each scene's tiles, fighter slices and poses are written into cartridge RAM when the scene loads | the same objects and tiles, all in ROM; each scene has its own page, and play needs no bank switching |
| Fighters | as the XE draws them | MARIA objects | MARIA objects, coloured: the guards' belts go by strength and their trim by type; the player has a black belt and blue trim |
| Other changes | | | Akuma's red robe; the hawk in 160B colour on level 3; Mt Fuji redrawn; the torii's front posts drawn over the fighters |
| Joystick | one button: a short press punches, a long one kicks (the `two-buttons` option gives button 1 punch, button 2 kick) | one button, as the XE | two buttons built in (button 1 punches, button 2 kicks); a one-button stick still works |
| Runs on | stock MAME, 7800 hardware with a SuperGame RAM board | BankSet with shared RAM: the patched MAME below, the openFPGA 7800 core for the Analogue Pocket | BankSet (the spec's plain form): the patched MAME below, the openFPGA 7800 core |
| Whole game, frames (forced replay, below) | 20,282 | 17,590 (13.3% fewer) | 18,173 (10.4% fewer) |

The stable port is the reference: it is the most faithful, and it runs
anywhere the 7800 runs SuperGame cartridges. Choose v1 for the most speed,
and V2 for colour and two-button control on a cartridge without RAM.

### Speed, level by level

One recorded game, from the start to the ending, replayed on each cartridge
in MAME. Each picture flip's recorded game state is written back, so all
three play exactly the same game. The figures are frames from one flip to
another (fewer is faster). Every cartridge is built with the `invincible
easy` options, as the recording was.

| Frames | Stable | v1 | V2 | v1 vs stable | V2 vs stable | V2 vs v1 |
|---|---|---|---|---|---|---|
| Level 1 | 5,075 | 4,031 | 4,358 | −20.6% | −14.1% | +8.1% |
| Level 2 | 4,715 | 5,244 | 4,897 | +11.2% | +3.9% | −6.6% |
| Level 3 | 5,612 | 4,349 | 4,650 | −22.5% | −17.1% | +6.9% |
| Level 4 | 3,035 | 2,538 | 2,729 | −16.4% | −10.1% | +7.5% |
| The ending | 1,823 | 1,405 | 1,514 | −22.9% | −17.0% | +7.8% |
| Whole game | 20,282 (338 s) | 17,590 (293 s) | 18,173 (303 s) | −13.3% | −10.4% | +3.3% |

Level 2 is the exception: drawing its windows as objects costs more than
the stable port's bitmap. V2's colour costs MARIA time that v1 doesn't
spend. Its 160B fighters have twice the bytes, and its level 4 has
Akuma's red. Forced replays are close to real play's timing, not exact.
`FINDINGS.md` has the method ("Speed: the release carts").

## Building

You need Python 3.10 or later and git.

```
git clone --recurse-submodules https://github.com/Miasmark/Karateka-XE-to-7800-port-Maria-Edition.git
cd Karateka-XE-to-7800-port-Maria-Edition
python port/build7800.py --car path/to/Karateka.car -o karateka7800-v1.a78
python port/build7800.py --car path/to/Karateka.car --v2 -o karateka7800-v2.a78
```

Without `--car`, the build looks for `Karateka.car` in the repository's top
folder (git ignores it there), or in the `KARATEKA_CAR` environment variable.
Without `-o`, v1 goes to `work/karateka7800.a78` and V2 to
`work/v2/karateka7800.a78`. Each build also writes its symbol file,
zero-page map and patch sites beside the cartridge.

Expected files:

| File | SHA-1 |
|---|---|
| `Karateka.car` (input, XE cartridge with its 16-byte CAR header) | `cddf050abc67aa2708763d781cdb247fb3bff50a` |
| v1 (output) | `071d95f8d3639dbf63424935ae7c245fe23b0282` |
| V2 (output) | `bbf3803016f2a8d743a4d557b73892acfdf96cc7` |

Both outputs are 256 KB BankSet cartridges, the CPU's half first, with a
signed ROM and an A78 header.

If you cloned without `--recurse-submodules`, run
`git submodule update --init` first. The assembler and signing tools come
from [a7800-toolkit](https://github.com/Miasmark/a7800-toolkit), pinned as a
submodule.

## Running the cartridges

Both versions need BankSet support. Stock MAME 0.287 refuses BankSet
cartridges.

- **MAME:** `port/mame/` has scripts that patch a MAME 0.287 source tree.
  Run them in order, each with the tree's path:
  1. `mame_bankset.py` adds the BankSet cartridge types, including v1's
     `$2006` with shared RAM;
  2. `mame_bsrules.py` adds the BankSet RAM rules as warnings: no display
     lists or code in cartridge RAM;
  3. `mame_mariaspace.py` gives MARIA its own address space, for the
     probes;
  4. `mame_newopts.py` adds `-playback_offset` and `-bios skip`.

  Build only the 7800 driver: `make SUBTARGET=a78
  SOURCES=src/mame/atari/a7800.cpp`. The first script is enough to play.
  `FINDINGS.md` has the details ("MAME with BankSet").
- **The Analogue Pocket:** the
  [openFPGA 7800 core](https://github.com/Miasmark/openFPGA-7800) runs both
  versions.

v1's `$2006` form (one RAM both halves see) is not in the BankSet spec. It
is how the openFPGA core maps BankSet with RAM, so other BankSet hardware
and emulators may not run v1. V2's `$2002` is the spec's plain BankSet
SuperGame form.

## Cartridge options

After a build, `port/kitopt.py` writes variants of a cartridge with options
applied and the ROM re-signed:

```
python port/kitopt.py invincible easy --cart karateka7800-v2.a78 -o karateka7800-v2-invincible-easy.a78
```

The options are `invincible`, `easy`, `start-level2` and `start-level3`,
for either version. `kitopt.py` reads the patch sites the build wrote
beside the cartridge (`<cart>.sites.json`), so keep those files together.
V2 has two-button control built in, and v1 has no room for it, so there is
no `two-buttons` option here.

## Census data

To tell code from data, the build uses what the original game was seen to
do, recorded under MAME. These recordings are kept in `census/` and contain no
cartridge bytes:

- `census*.ex`: the instruction addresses each recorded run executed, with
  their counts.
- `xe-display-lists.txt`: the display lists each scene selected.
- `reloc.txt`: the pointer bytes the port relocates, by location. The bytes
  themselves are read from your cartridge at build time.

They are the same as the stable port's. `port/mkcensus.py` regenerates
the folder from the full census recordings (`work/analysis`, made by the
probes in `probes/`). The tables in `port/` (`l1shapes.txt`, `s*shapes.txt`,
`*world.txt`, `akposes.txt`) list which images the game draws, where, and
in which rows, as the probes saw them. They also contain no cartridge
bytes.

## Known issues

- Level 2's windows: once, in one test build, two window panes lost their
  joints and a joint stood inside a pane for a picture. It depends on
  timing and hasn't been reproduced.
- The attract demo: a post's top hangs in the air for a moment just left
  of the wall's start (both versions).
- v1: one picture with a white sky just before "the end".
- A frame of corruption before level 2's first cutscene, seen once on the
  Pocket and not reproduced in MAME.
- Tested in MAME and on the openFPGA 7800 core for the Analogue Pocket,
  not on other BankSet hardware.

## The rest

- `port/sys7800.asm`: the 7800 system code (display lists, DLIs, MARIA
  objects, sound, bank switching) that replaces the XE hardware. Lines
  tagged `#V1` or `#V2` belong to one build only.
- `port/layout7800.py`, `port/link7800.py`, `port/build7800.py`: the memory
  layout, the per-scene linker and the cartridge build.
- `port/fighters7800.py`, `port/akpose7800.py`, `port/l1scene7800.py`,
  `port/fuji7800.py`: the fighters' pre-cut parts, Akuma's and the hawk's
  poses, the tile sets and the scenery's objects, made from your cartridge
  at build time.
- `probes/`: MAME Lua probes and Python tools used to study the original
  and check the port.
- `Record Karateka 7800.bat` and `Play Karateka 7800 Recording.bat`:
  record and replay a session in MAME. Set `MAME` to a BankSet build. Button
  2 is Space or Left Shift (`mame-ctrlr/`), because Windows takes a lone
  Left Alt tap for the window's menu.
- `FINDINGS.md`: the development notes, including corrections and dead ends.

## Licence

The port's own code, tools and notes are under the MIT licence (`LICENSE`).
It does not cover the game: *Karateka* was created by Jordan Mechner and
published by Broderbund; the XE cartridge was published by Atari. This
project is an unofficial fan port and is not affiliated with any of them.
