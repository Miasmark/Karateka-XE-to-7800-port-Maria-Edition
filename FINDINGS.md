# Karateka XEGS → 7800 Port — Findings & Plan

Working folder: `Karateka-Port/` (tools copied from kareteka-disasm, ROM in `work/`).
Source ROM: `work/Karateka.car` — 131,088 bytes = 16-byte CART header + 16 × 8K banks.

## What has been established

### 1. The cartridge format
- CART header: `43415254` ("CART"), type `0x0E` (XEGS 128K cart).
- Address space: cart appears at `$8000–$BFFF` (16K window).
- **Bank 15 is fixed** at `$A000–$BFFF` (contains the boot code + vectors).
- **Banks 0–14 rotate** through `$8000–$9FFF`; write low 4 bits of any value
  to `$D500–$D5FF` to select. Bank 0 is all `0xFF` (padding).
- Vectors (end of bank 15): `NMI=$B7B1`, `RESET=$0400`, `IRQ=$BFE0`.
  RESET points into RAM — the cart boots by copying code into RAM and jumping there.

### 2. It is "a disk that happens to be silicon"
The boot chain (traced with `a8dis.py`, matches repo docs):
```
$B7B1  set SDLST=$BFE1 (blank screen), DMA off
       → select bank 13 → copy 8K $8000→$1000 → run $2F5A → JMP $7760
```
`$B2CC` is a plain 8K block mover (`LDA ($00),Y / STA ($02),Y` loop).
The game then runs **entirely from RAM**: ~31K in use, three banks resident
at once (code bank → `$1000`, data bank → `$6000`, common bank 12 → `$0480`).

### 3. Scene → bank map (from `a8dis.py --scene N`)
| Scene | code bank | data bank | traced code |
|-------|-----------|-----------|-------------|
| 1 | 7 → `$1000` | 8 → `$6000` | 11,444 bytes |
| 2 | 1 | 2 | ~9,600 |
| 3 | 5 | 6 | ~8,300 |
| 4 | 3 | 4 | ~7,900 |
| 5 | 13 | 11 | ~9,200 |
| 6 | 9 | 10 | ~6,700 |
| 7/8 | invalid (bank 169/1 mod 16) | — | 2 bytes — **scene table wraps; ring of 6 stages** |

Bank 12 (common, entropy 0.37) holds the **Forth interpreter core** — the
game is an indirect-threaded Forth image; 6502 tracing only reaches ~75 bytes
from the cart vectors because everything else is a thread of addresses.

### 4. The RAM problem (the big one)
- Atari 8-bit: ~31K RAM live (code `$1000`, data `$6000`, common `$0480`).
- Atari 7800: **4K RAM** (`$1800–$20FF` + mirrors). Code+data per scene = 16K.
- **User's thesis (sound):** most of what's copied to RAM is read-only
  (graphics, Forth dictionaries, level data). ROM reads are fast enough;
  only genuinely *written* state needs to live in 7800 RAM.
- Evidence so far: static scan of bank 13 found only 3 apparent absolute
  stores into the data-bank region (`$6000–$7FFF`) — likely false positives
  from byte-scanning; needs verification with the tracer, not a byte sweep.
- 190/1024 blocks are low-entropy (sprite sheets: figure-on-black = mostly
  zeros); 105 blocks are high-entropy = **compressed/encrypted** — these must
  be decoded before any port can use them. **Status correction:** a later
  direct Shannon-entropy check over 128-byte blocks found zero blocks above
  7.2 bits per byte, so do not restart work from the 105-block count. See
  `notes/scene-cache-and-compression.md`.

### 5. Hardware mapping (from repo docs, `porting-karateka.md`)
| Chip | Verdict |
|------|---------|
| POKEY `$D200` → cart POKEY `$4000` | **Nearly free** — same chip, same registers; 64 accesses visible on cart image |
| PIA `$D300` → RIOT `$0280` / TIA `$0C–0D` | Rename — 15 sites, same info, different bits |
| ANTIC (54 accesses) | **Rebuild** — no display-list DMA on MARIA; HSCROL/VSCROL (21 sites) have no counterpart |
| GTIA (54 accesses) | **Rebuild** — no hardware collision; every `HITCLR` read becomes coordinate arithmetic |
| OS ROM deps | Only 2 on the cart image |

### 6. The trap that broke every prior build
NTSC 7800 hashes the cart and checks a signature at `$FF80–$FFF7`;
a failing cart boots into **2600 mode** (black screen, no error).
`tools/sign7800.py` re-signs (Rabin hash, e=2). Every build path must sign.

### 7. Pacing finding (relevant to the port)
The 8-bit game runs 10 routines from the VBLANK handler every frame;
the 7800 game parcels logic across frames (9 entity slots, 13-frame loop).
**Take the 8-bit frame structure** — it's what makes the game feel
controllable — but **not its memory model**.

## Current build status and remaining work

Completed and verified:

- The 7800 boot stub selects SuperGame bank 0 and jumps to the relocated
  scene-0 entry at `$B760`, bypassing the XEGS copy-to-RAM boot loader.
- The signed ROM has a valid signature and `RESET=$CC00`.
- Boot/title/attract output is pixel-identical to the previous working
  copy-to-RAM build for the sampled title sequence.
- Scene-bank pairing and the `$4800-$5FFF` gameplay framebuffer have been
  documented in `notes/scene-cache-and-compression.md` and
  `notes/4800-5fff-framebuffer.md`.

Known critical gaps:

- The old `$2F5A`/`$9F5A` runtime loader remains in the scene banks. Its
  XEGS bank numbers and bulk-copy destinations have not yet been replaced by
  a SuperGame paging dispatcher.
- Scene 6 mapping is inconsistent: step 0 places it in SuperGame bank 6,
  while the older `SCENE_MAP` and graphics patching still use bank 5.
- The gameplay framebuffer writer still targets XEGS `$4800-$5FFF`; on the
  7800 this is cartridge space, so it needs a MARIA rendering replacement.
- Display-list construction is still a placeholder.
- Full gameplay, scene transitions, combat, collisions, scrolling, audio,
  input, interrupts, RAM/DMA limits, and hardware testing remain unverified.

## Completed implementation steps

### Step 1 — paging dispatcher, unified mapping, code-preserving graphics
- `tools/build_final.py` now wedges a fixed-bank scene dispatcher at
  `$CC0A` (`LDA $D0 / AND #$07 / TAX / LDA table,X / STA $8000 / RTS`)
  with the page table `[0,1,2,3,4,0,6]` at `$CC16`. Boot sets `$D0=0`,
  calls the dispatcher, then jumps to the scene main entry.
- The stale fixed-bank boot copy sequence (`$F7C9`) and every paged
  `$9F5A` loader body were replaced with dispatcher calls, so the XEGS
  bulk-copy path can no longer run.
- `SCENE_MAP` scene 6 was corrected to SuperGame bank 6 (matching step 0);
  scene 6 graphics now patch bank 6 instead of the codeless bank 5.
- Converted-graphics patching now skips bytes the scene traces reach as
  code, preserving data-bank code such as the `$7760` main entries.
- Verified: build green, signature VALID, `RESET=$CC00`, title animation
  frames pixel-identical to the previous build.
- New finding: after the title animation the screen now goes black with
  the CPU hung at `$AD3C`, falling into `JSR $284E` — an untranslated
  code-bank self-reference (`$2857` should be `$9857` in-window). The old
  gray attract screen is therefore believed to have been a crash artifact
  (old livestate showed the CPU executing signature bytes at `$BFE1`),
  not a working attract mode. Do not "fix" this by re-overwriting code
  with graphics.
- Precise next step: full absolute-address relocation for scene code/data
  (`$1xxx-$2xxx` to `$8xxx-$9xxx`, `$6xxx-$7xxx` to `$Axxx-$Bxxx`,
  common `$0480-$247F` to fixed `$C000-$DFFF`, fixed `$Axxx-$Bxxx` to
  `$Exxx-$Fxxx`), applied at decoded instruction sites, plus a home for
  CartWin bank-14 window references.

### Step 2 — absolute-address relocation into the window
- New `step8_relocate_scene_addresses` rewrites absolute operands only at
  decoded instruction sites from the per-scene traces (never a blind
  sweep), verifying opcode and operand before touching a byte.
- Result: 1,972 sites relocated, 166 already correct, 289 skipped
  (bytes installed by other steps, or sources with no fixed home).
- Verified: build green, signature VALID, `RESET=$CC00`, title animation
  still pixel-identical (frames 0-5, now fully 0 px differ).
- New finding: the hang moved from `$AD3C` into real relocated code at
  `$9837` — the framebuffer clear loop (`STA $FF00,Y` with `STA $9839`
  self-patching the store address). On ROM the self-patch is ignored, so
  the loop spins forever. This confirms
  two follow-ups: the `$4800` framebuffer needs its MARIA rewrite, and
  self-modifying code needs RAM shadows or branch-based variants — ROM
  execution cannot honor either as-is.

### Step 3 — clear neutralization, table completion, animated attract
- New `step9_framebuffer_clear`: the two per-bank JMP vector tables
  (`$9800`, `$9E00`) have their code-band targets relocated (verified JMP
  opcode + in-range target per slot), and the self-patching framebuffer
  clear routine (signature `A5 07 C9 20`, 63 bytes) becomes RTS + NOPs in
  all six scene banks. Clearing a nonexistent bitmap is meaningless; the
  routine's callers recompute `$14/$15` themselves.
- Fixed a build-script bug found by the new guards: scene 5 shares SG
  bank 0, so the per-scene loop patched bank 0 twice; step 9 now visits
  each SG bank once.
- Verified: build green, signature VALID, title animation still
  pixel-identical — and the attract mode now animates past the old hang
  (grayscale demo frames render and change frame to frame).
- New finding: execution then crashes with the window reading `$00` and
  PC in the signature zone. Mechanism: the blitter's self-modifying
  stores (`STA $AB11` etc.) write into `$8000-$FFFF`, where every store
  is a SuperGame bank switch — e.g. storing `$05` selects the empty bank
  5, unmapping the running code. An inventory of ~100 self-modifying
  stores per scene (blitter patch sites `$2ADA/$2B10/$2DA1`-family plus
  clear-loop patching) is the input to the framebuffer rewrite: each
  needs a RAM shadow or a branch-based variant, which simultaneously
  fixes rendering state and stops spurious bank switches.
- Also verified this turn: step 8's uniform band mapping is sound for
  code/data bands (whole banks move together, so embedded data follows
  correctly), and common-band variables below `$1000` were correctly left
  to step 3's RAM mapping (step 8 skips already-rewritten sites).

### Step 4 — decoded-site translation framework (kills sweep corruption)
- Root cause found: steps 1-4 swept the ROM linearly, reading every byte
  as a possible opcode. A real instruction's bytes overlap misdecoded
  "instructions", and the overlapping writes clobber each other — e.g.
  `STA $0C4C / ASL A` became `STA $0C4C / JSR ...`. Translation counts
  were mostly false positives (step 3: 3303 claimed; only 279 real).
- All address translation (steps 1-4) now happens ONLY at decoded
  instruction-operand sites from the scene traces plus the boot walk
  (`translate_decoded_sites`), verifying opcode and operand before each
  write. New counts: POKEY 10, hardware 56, RAM 279, bank-switch 25.
- Step 5's byte-pair scan made non-overlapping (adjacent matches can no
  longer clobber each other): 372 translations (was 394).
- Step 6 fallout fixed: the joystick routine was previously *created* by
  sweep luck (its `LDA $D300` was never decoded); step 6 now matches the
  original XEGS bytes (`AD 00 D3...` at XEGS `$AD09` = fixed `$ED09`).
- Verified: build green, signature VALID, title animation pixel-identical,
  attract reaches the same stage and crashes with the same self-mod
  bankswitch signature (`$BFE0` after window reads `$00`). No regression;
  corruption eliminated at the source.
- Known limit (by design): undecoded code keeps original operands instead
  of being corrupted. Coverage-bound misses remain possible and will
  surface as wrong behavior, never as silent corruption.

### Step 5 — minimal RAM shadows (self-mod writes stop crashing)
- New `step10_ram_shadows`, fully derived from traces (no hand lists):
  store targets with decoded readers get RAM shadows at `$2600+` (all
  accesses redirected); write-only STA/STX/STY are NOPed; write-only RMW
  is shadowed (preserves N/Z flag semantics); JSR/JMP targets untouched;
  dead-code sites skipped by the opcode guard.
- Result: 26 shadows (`$2600-$2619`), 158 redirected, 146 NOPed. The
  dispatcher initializes every shadow from the fresh scene's ROM bytes on
  each switch (exact XEGS RAM-copy values); `$BFE7` (read by undecoded
  code, ROM home destroyed by signing) gets immediate-init from source.
- Verified: build green, signature VALID, title animation pixel-identical
  (now fully 0 px differ). Post-title no longer crashes: PC stays in the
  plot loop (`$991A-$9999`) with bank intact for 1000+ frames (was: window
  zeros + `$BFE0` park). Late frames are black — display, not logic.
- New finding: a 60 s run never leaves attract and never writes `$D0`;
  the button routine never executes in the observed windows, so the
  demo→gameplay handoff path is still unexercised (next work).

### Step 6 — button routine translated, input verified end to end
- New `step11_button_routine`: the undecoded console/button routine
  (fixed `$EF51-$EFD4`) gets 11 surgical patches with byte verification
  (`LDA $D01F`→`LDA $0282` ×4, `JMP $2E00`→`JMP $9E00` ×3,
  `STA $0F12`→`STA $2512` ×2, `JSR $24D7`→`JSR $94D7`,
  `STX $D01F`→`STX $0282`). Previously it read garbage console state and
  jumped into a RAM mirror (the observed `$E014` park).
- Verified: build green, signature VALID. Input reaches the game:
  fire held → INPT4 reads `$00` (pressed) and the button-state byte `$DB`
  takes `$80` (vs `$00` hands-off). SWCHB reads `$FD`/`$FE` correctly
  with Select/Reset held.
- The START press (`$D0=1`, scene-1 load) has not been observed yet:
  `$D0` stayed `$00` under fire/Select/Reset, and the button routine did
  not execute in 2399 sampled frames. On XEGS the handoff needs the
  console START value through this routine; whether the demo-end flow
  calls it (and when) is the next trace target. No crash in any input
  run — worst case observed is continued attract.

### Step 7 — demo-end handoff traced to missing CartWin bank 14
- 14,390-frame run: `$D0` never changes after boot; the dispatch chain
  (`$B4F5/$B880/$BFD9/$B80D/$EF66`) never executes — not a long demo,
  the dispatch condition never fires.
- `$D0` writers found: `$7808`/`$7286` (data bank) plus window `$AF77`/
  `$AFC3`/`$AFCA` (bank 14). The button routine's only caller is
  `$BFD9` (data bank: save regs, `JSR $EF66`, restore, `JMP $B80D`),
  itself called from `$B4F5/$B502/$B880/...` — none of which ever run.
- Decisive input test: fire held → INPT4 reads `$00` and `$DB` takes
  `$80` (vs `$00` hands-off). Input reaches game logic, but `$DB`'s
  consumer (hold-counter at XEGS `$B640`) has no decoded callers and never
  runs. Correction to an earlier hypothesis: `$B640` is fixed bank-15
  code (present in the image at `$F640`), not missing CartWin bank-14
  code — the earlier "cartridge window" labels from `where()` cover all
  of `$8000-$FFFF`, hiding fixed `$A000-$BFFF`. Zero decoded PCs fall in
  the true window (`$8000-$9FFF`), so no evidence anywhere says bank 14
  bytes execute; the missing piece is CALLERS (undecoded dispatch paths),
  not a missing bank. The spare-bank-5 + trampoline plan is shelved;
  the VBLANK frame call below is the actual unblocker.

### Step 8 — NMI is dead; VBLANK chain must move to the main loop
- Root cause of the stalled demo, proved three ways over 7000+ frames:
  the NMI vector region (`$B7xx`/`$F7xx`) executes exactly once (boot
  sampling), and POKEY gets zero writes — the entire 10-routine VBLANK
  chain (music `$104E`, input poll `$0FA2`, scene state `$0F66`,
  display pick `$0F87`, ...) never runs.
- Why: on XEGS the handler runs per-frame via NMI; the 7800 has no
  VBLANK NMI (NMI is MARIA's per-zone display interrupt only), and our
  NMI vector still points at `$B7B1` (window graphics on the 7800).
  The title animation is 100% main-line driven.
- Consequence: music, VBLANK input polling, the scene state machine,
  and display-list selection all need a once-per-frame call from the
  main loop (frame-synced via MSTAT), not an interrupt. That call is
  the prerequisite for demo advance, input consumption, and music.
- Next step: build the main-loop frame call (MSTAT sync + JSR into the
  relocated VBLANK chain in fixed/window banks) and verify music
  (POKEY writes resume) and state advance (`$D0`/phase bytes move).

### Step 9 — frame gate built; MSTAT dead, timer owned, nondeterminism
- `step12_frame_gate`: 52-byte fixed routine + 24 hooked `JSR $9995`
  sites (verified bytes, all six scene banks). Gate preserves A/flags/zp
  exactly like XEGS NMI preemption, fires the selective chain
  (music/countdown/state/input, display routines excluded to protect
  MARIA palette state), then tail-calls the pixel routine. Title intact.
- MSTAT (`$28`) reads `$00` at every sample, including VBLANK phase, so
  the MSTAT edge gate never fires (chain: 0 POKEY writes / 1700 frames).
  Whether MAME models the bit with DMA off, or plot never overlaps
  VBLANK, is undecided — either way MSTAT is unusable as a frame clock.
- RIOT timer hijack rejected with evidence: the game itself writes
  `$0296` (alternating `$F6`/`$64` — its own delay pacing), and XEGS RAM
  vars in `$0284-$02FF` collide with 7800 RIOT registers. Related find:
  `$0296` is one of several XEGS `$028x` RAM vars with no 7800 RAM home
  (step 3 blanket-excludes `$0280-$02FF`); they need explicit shadows.
- PROVEN run-to-run nondeterminism: identical build, identical inputs,
  animation frames diverge after ~frame 115 (12798 px differ at F0/F1 on
  rerun) while frames 100-110 match exactly. The demo is free-running
  (no VSYNC/WSYNC strobes exist in the image) with no frame pacing, so
  tiny timing differences accumulate into phase drift — and likewise
  explain crash-timing variance. Title verification stays valid only for
  the deterministic prefix (~frames 100-115).
- LASTV (`$2635`) initialized to `$00` in the dispatcher to remove one
  confirmed entropy source (was garbage `$E3`); placement verified
  outside step-3-mapped and footprint-used RAM.
- Standing next steps: (a) true frame tick — best candidate is DLI-based
  NMI once display lists exist, which also fixes pacing determinism;
  (b) `$028x` RAM-var shadows; (c) remaining undecoded window stores
  behind the `$BFE0` crash.

### Step 10 — $028x verdict: no shadows needed, tap discipline confirmed
- Trusted write-tap over `$0280-$02FF` (tap validity proven: it captured
  the boot `STA $D0`): ZERO game writes in 30 s unthrottled. The
  alternating `$0296` reads are MAME RIOT-model behavior on untouched
  timer regs, not game writes — the earlier linear-scan `$028x` hits
  re-examined as data false positives (sprite/table bytes containing
  opcode-shaped sequences).
- Therefore no `$028x` shadows to install (nothing writes them); reads
  of untouched regs return model values, a latent quirk for undecoded
  code, not a live bug. Timer hijack stays rejected.
- Tap discipline re-proven the hard way: a window (`$8000-$FFFF`) tap
  breaks banking (title renders black with it installed), so its two
  logged stores (dispatcher `$8000←$01`, `$F112` from `$04BA`) are
  discarded as artifacts, not findings.
- Methodology correction: `-script` probes attach ~240 frames late (7800
  BIOS splash), so all probe frame numbers are relative to cart boot,
  not power-on. Boot stub executes exactly once (no crash-reboot loop).
  The `$D0` tap confirms scene number never changes: still attract-only.

### Step 11 — display is configured; crash forensics; mirror decision
- Display finding: the game DOES drive MARIA — DLL `$1F84`, per-frame
  `CTRL $43/$40` toggling, per-frame DLISTL (`$22`), WSYNC strobes, and
  occasional scroll-reg writes were all captured live. Title DL walked
  (16 zones, RAM objects at `$1984+`). Title→black decoded exactly:
  frame 241 writes `CTRL=$60` + `DPPH=$00` from RAM-executed code
  (`$23C7`/`$0485`) — crash artifacts blanking the screen, not an
  intentional blank.
- Crash sequence nailed (dense per-frame sampling): `$2401-$240F`
  (SP=$FD balanced) through F249, then `$C001`-JAM (`$02` opcode) with
  SP=$FF — i.e. a stray RTS popping `$C001`, after a bad bankswitch
  zeroed the window (`$A5→$00` between F180-250).
- Root-cause neighborhood: the game constructs helper routines in RAM
  `$2407+` at runtime (frame-14 `$FB35`-path fills + `$BBEE` copy +
  patches; frame counter `$2406` ticks there per frame). Their baked-in
  operands (`LDA $2436,Y`, `ADC $6200,X`) assume XEGS RAM copies that
  don't exist on 7800 (`$2436` RAM is boot-fill garbage, `$6200` is
  cartridge space). No ROM template exists (constructed, not copied).
- `$9400`-trampoline (`JMP $2422`) + unrelocated `JSR $2400` sites in
  banks 2-4 mapped as further crash feeders for non-title scenes.
- Step 13 (this turn): NMI+IRQ vectors now point at a fixed-bank RTI
  stub (`$CD94`) — XEGS `$BFE0` was a bare RTS, and the signature zone
  made any BRK/IRQ unrecoverable. Verified vectors + title intact.
- DECISION — selective RAM mirror (next implementation): at scene
  switch the dispatcher already copies shadows; extend it to mirror
  DECODED-CODE bytes of the scene's code bank into RAM `$1800-$27FF`
  (same offsets the XEGS loader used), leaving non-code offsets alone
  for step-3 variables/shadows. This reproduces XEGS loader semantics
  for exactly the executable slice: undecoded `JSR $24xx` calls land on
  real code, constructed-code reads (`$2436`) hit real bytes, and
  self-modifying writes work natively — while step-3 variables and
  `$26xx` shadows keep their RAM. Constraint: mirror must skip
  non-code offsets (else it clobbers step-3 variables); `$1000-$17FF`
  calls stay unmappable (not RAM) and need trampolines if observed.

## Open questions (not yet answered)
1. Which blocks, if any, are packed/encrypted rather than merely dense lookup
   tables or graphics? Use the row-correlation method from
   `kareteka-disasm/docs/porting-karateka.md`, not another Shannon sweep; see
   `notes/scene-cache-and-compression.md`.
2. What exactly is written to RAM per level — needs a dynamic run in MAME
   with the probes, not static scanning.
3. Does the Forth dictionary itself live in the data banks (likely — bank 12
   header words point into `$70xx/$71xx/$79xx…` regions)?
4. 7800 cart mappers: does any existing mapper give >4K RAM? (Decision
   deferred per user: extra RAM only if absolutely necessary.)

## Step-by-step plan

### Phase A — Understand the image (static)
1. **Run `tools/forth.py` on `work/Karateka.car`** — decompile the Forth
   image; generate entry points (`patches/karateka-entries.py` pattern) and
   re-run `disasm.py` with them to push coverage past 18.3%.
2. **Classify every 256-byte block**: code / Forth dictionary / sprite sheet /
   compressed / padding. Build `annotations.json` from `templates/annotations.json`.
3. **Crack the compression**: take one high-entropy block, check for the
   EOR/ROL/SBC/ROR self-decryptor idiom the docs mention; if it's real
   compression, identify the codec before porting anything that uses it.

### Phase B — Measure what must live in RAM (dynamic)
4. **Boot the cart in MAME** (`mame xegs -cart work/Karateka.car` — MAME
   0.289 has the `xegs` machine; BIOS `c101687.rom` already in folder).
   Adapt probes from `kareteka-disasm/probes/` (they target the 7800 game;
   addresses differ for the 8-bit cart).
5. **Watchpoint every RAM window** (`$1000–$9FFF`, `$0480–$04FF`) during a
   full playthrough; log all writes. Output: a per-address write map that
   answers "what actually changes per level" — the user's core question.
6. Decide from data: which blocks are read-only (stay in ROM) vs written
   (must fit in 4K RAM). If written-state > 4K, *then* evaluate mappers
   with extra RAM (Bankset, etc.) — last resort.

### Phase C — Restructure for 4K RAM
7. Reorganize level data so per-level state fits in 4K: Forth dictionaries
   stay in ROM (read-only), variables compacted into zero-page + `$1800` block.
8. Map the 6-stage ring: each stage's ROM banks + which bank is paged when.

### Phase D — ANTIC → MARIA (the real work)
9. Convert display lists → MARIA display lists; bitmap backgrounds → direct
   mode or character-mode equivalents; scrolling → redraw logic driven by
   the odometer-style travel budget (`$18B3–$18BD` equivalents).
10. Replace every GTIA collision read with coordinate comparison (the 7800
    port's weak hit detection came from skipping this — do it properly).
11. Port POKEY driver base `$D200`→`$4000`; port PIA→RIOT joystick reads.

### Phase E — Build & verify
12. Assemble with `tools/asm.py`; verify with `tools/verify.py` +
    `tools/selftest.py`; **sign with `tools/sign7800.py`** (else black screen
    on hardware); test in MAME `a7800`/`a7800p` with the existing probes.

### Working rules
- One phase-step per session; write results to `work/` as JSON/CSV so
  progress survives restarts.
- Static scan counts are upper bounds — confirm anything load-bearing by
  running it (MAME), per `docs/method.md`.
- Every "dead region" claim needs a positive control (see
  `docs/karateka-from-siblings.md` — a wrong zero is worse than no answer).

## 2026-09-24 — re-evaluation against the running original

Measured, not inferred. MAME 0.287 throughout; scratch probes kept in the
session scratchpad (`kport/`).

### The original runs in MAME after all
- `mame xegs -cart work/Karateka_16header.bin -rompath roms` boots and plays
  (story text, title, the cliff fight). Only the `.car` header was refused
  ("Cart type 14 unsupported"); the raw 128K image is accepted. The earlier
  "no runtime evidence is possible" conclusion in
  `notes/scene-cache-and-compression.md` is withdrawn.
- Run it windowless with a scratch `-inipath` whose `ui.ini` holds
  `skip_warnings 1`, plus `-video none`: `xegs` is flagged as imperfect
  graphics and otherwise waits for a keypress on a warning screen.
  Snapshots still work with `-video none`.
- Fire (P1 Button 1) starts a game from attract; `$D0` goes 0 → 1 at
  frame 1865 in the measured run.

### The source image is not pristine
`work/Karateka.car` differs from the original (`karateka/Karateka.car`,
SHA-256 `484b3264…cb1c`, the same bytes as `Karateka_Atari_USA.zip`) in six
bytes: bank 11 `$8001-$8008`, the scene-0 data jump table at RAM
`$6000-$6008`, where three `JMP` targets (`$600A`, `$60D2`, `$60E3`) were
changed to `$F7CD`. A port patch was saved into the build's input on Sep 21.
`Karateka_16header.bin` is the untouched original without its 16-byte
header.

### The current build does not run
`build/KaratekaXE.a78` in MAME (NTSC BIOS): black screen at every sample
from frame 300 to 3600, CPU looping `$0000` (BRK) → IRQ → RTI stub `$CD94`.
The "attract mode runs stably" status in `BUILD_NOTES.md` does not describe
this build: its boot stub now starts scene 1 directly (a diagnostic), and
`build_manifest.json`'s output hash is stale.

### Zero page $00-$3F was never remapped
The original writes **all 64 bytes of `$00-$3F`** during play (≈7 million
writes in 7,000 frames), plus 130 bytes of `$40-$FF`. Step 3 maps only
`$0200-$0FFF`. On the 7800, `$00-$3F` are TIA and MARIA registers: `$01` is
INPTCTRL, `$24` WSYNC, `$2C` DPPH, `$3C` CTRL. The step-11 observation
"frame 241 writes CTRL=$60 + DPPH=$00" is most likely the game's own
zero-page variables landing on MARIA, not a crash artifact. It also means
194 zero-page bytes are in use against the 7800's 192 (`$40-$FF`), so some
must move to absolute RAM, which lengthens their instructions: that cannot
be done by in-place operand rewriting.

Stack use is `$01E4-$01FF` (28 bytes), inside the 7800's RAM stack page.

### What the original writes during play (scene 1, OS and loader excluded)
| Region | Addresses written | What it is |
|---|---|---|
| `$4808-$5FEF` | 6,120 | framebuffer A (40 bytes × 153 rows) |
| `$3010-$47F7` | 6,120 | **framebuffer B**: the game double-buffers; the earlier note found only A |
| `$0880-$08FF` | 128 | a table built at runtime (PC `$2E60`) |
| `$2409-$2421` | 25 | code constructed at runtime |
| `$1000-$2FFF` other | ~26 | self-modified operands (`$28FA`, `$291D-$2926`, `$2ADA`, `$2B10`, `$2DA1`, …) |
| `$0480-$0FFF` other | ~23 | variables and self-modified bytes |
| `$0200-$047F` | 11 | OS vectors and shadows (`VDSLST`, `VVBLKI`, `SDMCTL`, `SDLSTL/H`, …) |
| `$6000-$7FFF` | 2 | `$7096-$7097` only: the data bank is otherwise read-only |

So about 12.5K must be writable, 12,240 bytes of it the two bitmaps. That
cannot fit in the 7800's 4K; it fits in the 16K of a SuperGame+RAM cartridge
(`a78_sg_ram` in MAME).

### Hardware the original touches during play
| Register | Use |
|---|---|
| POKEY `$D200-$D207`, `$D208`, `$D20E-$D20F` | music (4 channels), IRQ/SKCTL setup |
| GTIA `$D016-$D019` COLPF0-3 | written together by the DLI handler at `$1152`, about 3 times a frame |
| GTIA `$D010` TRIG0 | the fire button, read every frame (`$0FB4`) |
| GTIA `$D01F` CONSOL | console keys (`$AF66`, `$AFD1`) |
| PIA `$D300` | joystick (`$AD09`) |
| ANTIC `$D402/3` DLISTL/H | display-list flip every frame (`$0F8D`) |
| ANTIC `$D40A` WSYNC, `$D40B` VCOUNT, `$D40E` NMIEN, `$D400` DMACTL | DLI timing, a raster wait (`$2F8A`), setup |

**None of these during play:** player/missile graphics, collision registers
(`$D000-$D00F` reads), `HITCLR`, `HSCROL`/`VSCROL`. Collision is computed in
software and nothing scrolls. The "rebuild GTIA collision" and "scrolling
becomes a redraw" items in the older assessments do not apply to the
cartridge's play.

### Display
Display lists at `$19B3` and `$1908`, one per buffer, flipped each frame:
24 blank lines, three ANTIC mode 8 rows (a low-resolution band), then
mode E (160 × 1-line, 2 bits per pixel) from `$4808` / `$3010` with a second
LMS at the 4K boundary, DLIs on several lines, and a 7-line mode-E status
bar from `$5ED8` / `$46E0`. Mode E's byte layout (four 2-bit pixels, the
leftmost in bits 7-6, `00` = background) is MARIA 160A's, so MARIA can
display the game's bitmaps as they are, from constant display lists in ROM.
The notes `antic-maria-dl-translation.md` and `maria-dl-implementation-plan.md`
describe MARIA's DL format incorrectly and should not be built from.

### Corrections to earlier entries
- "Bank 12 holds a Forth interpreter": no sign of it. The 7800 version's
  `NEXT` signature does not occur in the XEGS image; the traced code is
  ordinary 6502. Forth is the 7800 version's architecture, not this one's.
- The `$4800-$5FFF` note is right about buffer A and incomplete: there are
  two buffers.

### Where the renderer reads its art (same day)
Write tap on `$3000-$5FFF` during play, recording the writer's PC and the
source pointer `$03/$04`:

- Sources are the scene data bank's RAM copy (`$66xx-$6Bxx`), a common-bank
  table (`$0Bxx`), **and cartridge ROM directly**: `$83xx-$9Axx`, bank 14,
  which stays paged in at `$8000`. The game already draws from ROM where
  its layout allows; the copying to RAM comes from the loader, which is
  shaped like the disk version's (a disk game has to load into RAM), not
  from any need of ANTIC's. ANTIC can fetch from ROM as well.
- What has to be RAM is the picture itself: the fighters are composited over
  the background in software, with masks, into two alternating bitmaps.
  About 415 bytes are written per frame on average, 2,233 at most, so it
  redraws the changed areas, not the whole screen. The finished screen
  exists nowhere in ROM.
- Values written are mostly `$00`, `$AA`, `$55`, `$FF` (solid fills in one
  colour) plus composited sprite bytes.

Consequence: displaying from ROM on MARIA needs the compositing replaced by
display lists (fighters as objects, background as objects), not just the
display lists moved. Keeping the compositor needs ~12K of cartridge RAM.

### Retail 7800 cartridge layouts (MAME's software list)
Retail boards carried POKEY or RAM, never both:
- SuperGame + 16K RAM at `$4000` (`a78_sg_ram`): Summer Games, Winter
  Games, Impossible Mission (Epyx, 1987), Tower Toppler (1988), Jinks (1989).
- POKEY: Ballblazer (`a78_pokey`), Commando (`a78_sg_pokey`).
Decision (user, 2026-09-24): stay within retail layouts, so POKEY music
converts to TIA.

### Collision is already software (same day)
No instruction anywhere in the 128K image addresses the GTIA collision
registers (`$D000-$D00F`) or `HITCLR` (`$D01E`), not even as a byte
pattern in data (a sweep of every bank for absolute-mode reads and writes:
0 hits). With the fight's runtime tap also showing zero reads, the XEGS
game detects hits in software, so its collision code is portable game
logic, not a hardware dependency to rebuild. The remaining gap is access
through a pointer (`LDA ($zp),Y` aimed at `$D00x`); the per-scene runs will
tap `$D000-$D00F` reads to close it. The "54 GTIA accesses" in the older
static count are colour, console and trigger registers.

Route decided (user, 2026-09-24): SuperGame + 16K RAM at `$4000` (the
Summer Games board), the game's own compositor kept, POKEY music rearranged
for TIA.

### Step 1 test cartridge: MARIA shows the game's bitmap (same day)
`port/bitmap_testcart.py` builds a 128K SuperGame + 16K RAM cartridge (header
flags `$0006`) from one captured frame of the original (frame 4000 of the
scripted fight; `xcap.lua` records RAM and the DLIST/colour writes with
their scanlines). It copies both framebuffers into cartridge RAM
(XEGS address + `$1000`) and shows the frame through ROM display lists: one
1-line zone per XEGS scanline, each drawn line two 20-byte 160A objects
pointing at the bitmap row, mode-8 rows widened into 40 bytes, and the
DLI colour changes turned into a palette per line (3 palettes for this
frame).

- **Pixel check:** against the original's screenshot, aligned
  (7800 x+8, y+2), all 71,680 overlapping pixels agree under a one-to-one
  colour mapping (6 colours, 0 disagreements). The colour bytes carry over
  unchanged; MAME's two palettes differ by a few RGB units.
- One wrong turn: placing each colour change one line after its DLI line
  was two lines early (128 sky pixels on two rows). The logged write line
  (`VCOUNT*2`) + 1 is right.
- **CPU left per frame (MAME a7800):** counting loop, 8 cycles a pass:
  2,788 passes with the bitmap displayed (≈22,300 cycles), ≈3,719 with
  MARIA DMA off (≈29,750). The display costs about 25% of the CPU.
- **The original, for comparison:** MAME's `xegs` cannot give this number.
  The same counting loop hijacked into the running original showed ANTIC
  DMA costing only ~3% (3,584 vs 3,686 passes), where the ANTIC rules
  give ~29% for this display list (40 playfield cycles per mode-E line ×
  153 lines, 9 refresh cycles on every one of 262 lines, DL fetches):
  MAME does not model ANTIC's cycle stealing. Computed from those rules,
  the original has ≈21,200 cycles a frame. So the 7800 leaves about the
  same CPU time as the XEGS did, a little more. To be confirmed in Altirra
  (cycle-accurate) and on hardware; MAME's MARIA timing is also a model.

### Step 2: census of every reachable scene (same day)
`xscene.lua` (scratchpad `kport/`), one run per scene, 6,000 frames each,
the same scripted input. Scenes other than 1 are reached by substituting
the scene number for the game-start write of `$D0 = 1` (at `$7808`); the
loader then brings in that scene's banks. Scenes 2, 3 and 4 accept it and
write their own number back; scene 6 runs 41 frames and hands over to
scene 1 (a lead-in); scene 5 shares scene 0's banks (13/11) and stays black
when forced, so it wants its own entry, probably the ending. Scenes 2 and 3
fell back to scene 1 partway through (the scripted player dying, most
likely).

- **Collision: closed.** 0 reads of `$D000-$D00F` in any scene. The tap
  sees every access however it is addressed, so the pointer case is
  covered too.
- **Writes outside the framebuffers, all scenes together: 238 addresses**
  above `$01FF`: OS vectors/shadows (`$0200-$0244`), a 22-byte-stride
  table at `$0480-$06DA`, the 128-byte table `$0880-$08FF`, variables at
  `$0AF6-$0F14` and `$1193-$1196`, constructed code `$2409-$2421`,
  self-modified operands in `$2839-$2E0D`, and 3 bytes of the data bank
  (`$7096-$7097`, `$76FF`).
- **Zero page: 208 bytes** written across the scenes (all 64 of `$00-$3F`,
  144 of `$40-$FF`); scene 1 alone uses 196. The 7800 has 192 bytes of
  zero-page RAM, so some variables must move to absolute RAM. That
  lengthens instructions, so the port reassembles rather than patching
  bytes in place.
- **Stack:** lowest SP `$EB`.
- **Code already executes from cartridge ROM:** 1,470-1,610 distinct
  instructions per fight scene are in fixed bank 15 (`$A000-$BFFF`).
  Bank 14 (`$8000-$9FFF`) never executes; it is art. The "data" bank
  holds code too (157-1,155 instructions per scene).
- **Colours:** at most 4 colour sets in any frame of any scene (MARIA has
  8 palettes), COLBK always `$00`, colour changes on up to 3 lines per
  frame, and the lines vary (98-202).
- **Display lists:** the game flips between fixed DLs at `$1908-$1B04`,
  which are never written, so they are data loaded with the common bank.
  Each can become a MARIA DLL built at assembly time and held in ROM,
  with DLI bits where the ANTIC list has them, and a MARIA DLI handler
  rewriting a palette where `$1152` rewrites COLPF0-2.
- **New:** scene 0 (title and story) writes CONSOL `$D01F` ~580,000 times.
  That is the built-in keyclick speaker used as a sound source, and it
  needs a TIA replacement alongside the POKEY music. **Wrong (2026-09-26):** every one of those
  writes is `$08` from `$AFD1` (`LDX #$08 / STX $D01F`), the end of the
  console-key routine, which resets CONSOL (speaker off) on each call and is
  called in tight loops while the game waits for a key. A constant never
  toggles the speaker, so the XEGS game makes no speaker sound, and nothing
  is missing on the 7800. See "The silent Akuma fight". TRIG1 (`$D011`) is
  read in scene 1.

Measured by the scripted run only: paths it never took (winning a fight,
the hawk, the princess, scene 5) are not in the executed set yet.

### Player health, and recording a full playthrough (same day)
- **`$00B6` is the player's health.** It is 14 at the start of a life, one
  less per hit, and 0 is dead. Found by matching RAM against the
  status-bar arrows read from the bitmap (correlation 0.973 over 830
  samples; the next best byte managed 0.57).
- `probes/xe-invincible.lua` refuses any write that lowers it (outside
  scene 0), so hits cost nothing; raises (new life, refill) pass. Tested:
  18,000 frames of the scripted player, health never below 14, and it
  then won its way along the cliff to the gate and the Akuma cutscene
  (which runs inside scene 1: `$D0` stays 1).
- `Record Karateka XE.bat` records a human session of the original
  (`inp\xe-NN-inv.inp`, cheat on by default; `KXE_CHEAT=0` for none).
  `Play Karateka XE Recording.bat` replays one, reloading the cheat for
  `*-inv` names, since a recording made under the cheat diverges without
  it from the first hit. Both skip MAME's imperfect-graphics warning with a
  copy of MAME's own `ui.ini` plus `skip_warnings 1` in `mame-ini\`
  (searched first).

### Health, instant deaths and the gate (same day)
From the user's recording `inp/xe-01-inv.inp` (1,261 s, ~75,600 frames;
scene 1, scene 2, a death, scene 1 again, scene 2 again, the gate) and
targeted replays of it.

**Health is symmetrical.** `$B6` player, `$B7` enemy; maxima `$B0`/`$B1`.
Damage: `$0BDD` (player: `DEC $B6`, and at 0 clears the alive flag `$5D`)
and `$0BEE` (enemy: `DEC $B7`, clears `$5E`). Refill: `$0C1E`/`$0C30`
count up **until health equals the maximum** (equality, not less-than).
Each new opponent lowers the player's maximum and raises the enemy's
(`$78F0` in scene 1: `DEC $B0 / INC $B1`, floor 10) and caps `$B6` at the
new maximum through `$7BB6` (`$7BB8 STA $B6`); scene 2 does the same at
`$77AF`/`$7927`.

**Version 1 of the cheat was wrong.** Blocking every lowering of `$B6`
also blocked that cap, so `$B6` sat above `$B0`, the refill never met its
equality test, and health ran to 255 (then the wrap to 0 was blocked too).
It also missed the instant deaths, which are decided before `$B6` is
written: the player died at frames 16,044 and 41,429 with health pegged at
255.

**Three instant deaths, found by replaying to each and reading the stack:**
1. *Hit while unprotected* (running, walking; the hawk as well). The hit
   dispatcher `$B14A` sends victim states 6-8, `$0B-$0D` and `$22`+ to
   `$B12A`: `LDA $62 / CMP $22 / BEQ $B131`, and `$B131` sets `$B6 = 0`,
   `$5D = 0` and starts the death sequence (`JMP $A540`). The call chain
   was `$77F8 → $79C0 → $B277 → $B2BE → $B14A` in scene 1 and
   `$7811 → $7AD3 → $B277 …` in scene 2.
2. *The gate* (scene 2, the portcullis). `$A9` = gate triggered, `$A7` =
   how far down, `$62` = player position. `$79C1-$79D3` crush when the gate
   is triggered, `$A7 >= $82` and `$62` is `$1F-$21`; `$79F3` then sets
   health to 2 (1 if below 3) and `$7B08-$7B16` take one away at a time
   while the player lies under it. The check at `$7C11` only redraws the
   gate over a dead player.
3. *Driven off the cliff* (scenes 1, 6, and the same code in scene 5's
   bank). `$A2` set means over the edge; the main loop then clears `$5D`
   (`$7914 LDA $A2` … `$791E STA $5D`; `$758D` … `$7597` in bank 11).
   Found when a scripted player holding right in fighting stance (which
   kicks rather than walks) was pushed back over the edge: game over,
   "the end", without passing through `$B131`.

**Version 2, `probes/xe-easy.lua`,** changes five single instructions:
the damage `DEC $B6` at `$0BE5` keeps the old value; the `BEQ` at `$B12E`
is fetched as `BIT $01`; `LDA $A7` at `$79C5` (scene 2) reads 0;
`LDA $A2` at `$7914` (scenes 1, 6) and `$758D` (scene 5) reads 0; writes
of `$B7` above 1 store 1 (not in scene 0, where `$B7` is something else:
clamping it there kept the title from ever starting a game, 40,000 frames).
Tested with scripted players: 40,000 frames reached scene 3 (scene 2 at
frame 10,168, scene 3 at 21,157) with 20 foes killed, 0 deaths and the
gate defused once; a hold-right run that died off the cliff without the
cliff block ran 12,000 frames with it, past the Akuma cutscene, without
dying. The unprotected-hit block has not yet been seen to fire in a test
(no scripted run was hit while running).

The recording batch now uses version 2 (`*-easy.inp`); version 1 stays
for replaying `xe-01-inv.inp`.

### The ending, and coverage from two human playthroughs (same day)
`inp/xe-01-easy.inp` (512 s, easy mode) reaches the ending: scene 1 at
frame 160, scene 2 at 5,045, scene 3 at 8,738, **scene 4 at 24,549, which
holds the finale**: the last fights, the hawk, Akuma defeated, Mariko
freed, and the epilogue text ("and so this adventure ends…"). Scene 5
(scene 0's banks) appeared in no run, human or scripted; it may be unused.

Easy mode during that run: 159 hits absorbed, the gate check defused once,
362 cliff checks neutralised, 11 foes killed. The instant-death block fired
196 times, in bursts every 6-18 frames with the victim in states
`$22-$29` and `$07`. That is more than hits on the player explain, so the
`$62 = $22` test at `$B12A` is probably not "the victim is the player"
as first read; the block may also spare guards that would have died
outright. The user reports running past guards a couple of times, which
the real game cannot do (a running player dies at the first contact),
so the run passed through states the original never produces. Read its
coverage with that in mind. The user also notes that kicking needs a long
press on the stick, which made the hawk hard. That is the XEGS input
design (held frames are counted, `$0FB0`), and the port has to keep it.

**Coverage, instructions executed** (census probe over the scripted runs,
`xe-01-inv.inp` and `xe-01-easy.inp`; window bank excluded):

| Scene | Scripted | + recording 1 | + recording 2 | Union | Static trace | Executed, not in static trace |
|---|---|---|---|---|---|---|
| 0 | 1,112 | +142 | +0 | 1,254 | 5,591 | 94 |
| 1 | 4,194 | +1,170 | +15 | 5,379 | 5,784 | 154 |
| 2 | 3,911 | +1,194 | +143 | 5,248 | 5,777 | 78 |
| 3 | 3,806 | +0 | +789 | 4,595 | 5,187 | 82 |
| 4 | 2,006 | +0 | +1,695 | 3,701 | 5,089 | 76 |
| 6 | 475 | +0 | +0 | 475 | 4,546 | 26 |

The last column is what a static trace alone would have missed: computed
jumps and code built at runtime. 76 of those instructions are common to
every scene (the code-bank region; most likely the routine built at
`$2409-$2421`). Static trace ∪ executed is the code map step 3 starts
from; static-only bytes are plausible code, not proven.

### Why a kick needs a long press: the stick is read every 6-10 frames (same day)
Replaying `inp/xe-01-easy.inp` with a read tap on PORTA (the game's reads are
at `$AD09`; `$C1F3`/`$C200`/`$C4ED`/`$C51A` are the OS) and the stick as
held each frame (MAME port `:ctrl1:joy:JOY`):

| Scene | Frames | Frames with a read | Median gap | Commonest gaps |
|---|---|---|---|---|
| 1 | 4,885 | 407 | 6 | 5, 6, 4, 8 |
| 2 | 3,693 | 371 | 7 | 7, 6, 8, 5 |
| 3 | 15,811 | 1,637 | 10 | 10, 8, 9, 11 |
| 4 | 6,452 | 215 | 7 | 7, 9, 6 |

The stick is read when the player's fighter reaches a decision point, not
every frame. Of 562 stick pushes, 199 (35%) ended between two reads and were
never seen: pushes of 1-3 frames were missed 55 times in 67, 4-7 frames 105
in 205, 13 frames or more almost never. (Some pushes fell in cutscenes, where
nothing reads the stick, so 35% is an upper bound.) The same kind of problem
as the 7800 version's lag (13-14 frames between reads there), milder.

**Trial fix on the original, `probes/xe-easy-latch.lua`:** sample the stick
every frame, keep the latest push, and when the game reads a centred stick
hand it the kept push once, then clear it; a push still held is read live.
A tap therefore arrives once at the next decision point and a hold still
reads as a hold, which is what the withdrawn 7800 button latch got wrong.
Scripted test, fighting stance, a 2-frame right tap every 25 frames for
6,900 frames: without it the game read 1 of 276 taps, with it 276 of 276,
and play carried on normally. `Record Karateka XE (quick stick).bat` records
with it (`*-easylatch.inp`) so it can be judged by feel before the port
commits to it; the 7800 difficulty switch could select original or quick.

### Step 3 begins: scene 1 as source that rebuilds exactly (same day)
`port/xesource.py` writes one scene's address space as assembler source:
segments `common` ($0480-$0FFF, bank 12's first $B80 bytes: the code bank
overwrites the rest, confirmed against RAM in scene 1), `code` ($1000),
`data` ($6000), `art` (bank 14 at $8000, never executed) and `fixed`
(bank 15 at $A000). Instructions come from the static trace plus every
instruction the census saw run; every operand pointing at code, data,
zero page, RAM or hardware becomes a symbol (`L_xxxx`, `Z_xx`, `V_xxxx`,
register names), references into the middle of an instruction become
`label+n`. Output goes to `port/build/` (ignored: it contains cartridge
bytes). **Scene 1: all five segments rebuild byte for byte** with the
toolkit's `asm.py`: 6,426 instructions, 5,625 of them seen executing,
12 self-modified operand references ($2839, $28FA-B, $291D-E, $2926,
$2ADA-B, $2AFF-$2B00, $2B11, $7C50).

**Census correction.** Keying executed code by `$D0` misfiled a few frames
at every scene change: the game writes `$D0` before the loader has
replaced the banks, so the old scene's last instructions were filed under
the new scene. That showed up as 24 impossible overlaps in scene 1's data
bank. The census now keys by the scene the loader actually loaded (the
`$D0` read at `$2F75`, taking effect when `$2F84` runs); the overlaps are
gone. Two remain, and they are real: `$2925/$2926` and `$2B10/$2B11`,
self-modifying code whose instruction boundaries change at run time.
These routines go to RAM in the port. It also corrects scene 6: it is not
a 41-frame lead-in. Loaded by force it runs the whole 4,103 frames; it
sets `$D0 = 1` straight away, which the old keying mistook for a return
to scene 1.

### All scenes rebuild exactly; the code banks share an engine (same day)
With the census rerun keyed by the loaded scene (all seven runs: five
scripted, both recordings), `port/xesource.py` generates every scene, and
**all six (0, 1, 2, 3, 4, 6) rebuild byte for byte in all five segments.**
The only overlapping instructions left in any scene are the two
self-modifying spots (`$2925/$2926`, `$2B10/$2B11`; none in scene 0).

Coverage, corrected (supersedes the table above, which was keyed by `$D0`):

| Scene | Scripted | + recording 1 | + recording 2 | Union | Static trace | Executed, not in static trace |
|---|---|---|---|---|---|---|
| 0 | 1,219 | +35 | +0 | 1,254 | 5,591 | 92 |
| 1 | 4,028 | +1,246 | +15 | 5,289 | 5,784 | 76 |
| 2 | 3,914 | +1,193 | +150 | 5,257 | 5,777 | 76 |
| 3 | 3,809 | +0 | +786 | 4,595 | 5,187 | 76 |
| 4 | 1,910 | +0 | +1,704 | 3,614 | 5,089 | 76 |
| 6 | 3,168 | +0 | +0 | 3,168 | 4,546 | 58 |

The code the static trace cannot see is the same 76 instructions in every
gameplay scene.

**The code banks share an engine.** Of each code bank's 8,192 bytes,
4,935 are identical in all six scenes: `$1000-$1202` (515 bytes),
`$2300-$24A4` (421) and `$24AC-$2FFF` (2,900). That covers the drawing
code with every self-modified operand (`$2839-$2B11`), the constructed
routine's neighbourhood and the loader. Seven bytes at `$24A5-$24AB`
differ per scene. So a code bank is ~4.9K of shared engine plus ~3.2K of
scene code at `$1203-$22FF`. The port can hold the engine once (its
self-modifying part in RAM) and give each scene page only its own code
and data.

### ROM size decided: 128K (same day)
Retail SuperGame+RAM boards (header `$0006`, from the Rom Library dumps):
Summer Games, Winter Games, Impossible Mission and Jinks are 128K; Tower
Toppler is **64K**, so 64K + RAM is also a retail layout. The unique content
comes to ~83K even with scene 6 stored as a 231-byte patch on scene 1, so
64K would need ~20K of it to be unread. The only size between 64K and 128K
(144K, 9 banks) puts its extra bank at `$4000`, where this board has its
RAM. **Decision (user, 2026-09-24): 128K**, eight 16K banks, bank 7 fixed
at `$C000`, 16K RAM at `$4000`. Pages 6-7 are headroom.

Budget, visible at once: ~28.8K shared (XEGS bank 15 8K, art bank 14 8K,
engine 4.9K, common 2.9K, display lists ~3.5K, 7800 boot/sound/glue ~1.5K)
plus ~11.3K per scene (code 3.3K, data 8K), against ~39K available (16K
fixed, 16K page, ~3.8K cartridge RAM beside the framebuffers, ~3.5K console
RAM). The split is settled by the read census (every byte each scene reads,
running now): dead XEGS boot/loader code and unread data are the slack.

### Read census: a dummy-read trap, and the shared segments (same day)
A read tap over `$0480-$BFFF` for every scene (`xreads.lua`) first reported
every byte of scenes 0-3's code and data banks as read. Wrong: the 6502
makes a dummy read of the destination on `STA (zp),Y`, so the loader's copy
loop at `$B2CC` "reads" each byte it writes, and since the scene key
changes only when the copy is done, those reads landed on the previous
scene. The OS's RAM clear at power-on does the same to scene 0. The census
now ignores reads made by `$B2CC-$B2EA` and by the OS (PC ≥ `$C000`).
Anything measuring reads on a 6502 needs that filter.

Unaffected by it (ROM the loader never writes), the two shared ROM
segments, union over scenes 0-4 and 6, all seven runs:

| Segment | Read | Never read |
|---|---|---|
| XEGS bank 15 (`$A000-$BFFF`) | 6,495 of 8,192 | 1,697 |
| art bank 14 (`$8000-$9FFF`) | 7,581 of 8,192 | 611 |

(The first pass also showed the common bank and the engine as read in
full; they are loader destinations too, so those figures were inflated
in the same way and wait for the filtered rerun.)

Art per scene, in 256-byte pages: scene 0 reads one page (`$80`); scenes
1-3 read 30-32 of 32; scene 4, 26; scene 6, 22. The fighters' art is
common to every fight, so art cannot be split per scene to any useful
degree.

Filtered rerun (loader and OS reads excluded), union of all seven runs:

| Segment | Size | Read | Never read |
|---|---|---|---|
| XEGS bank 15 (`$A000-$BFFF`) | 8,192 | 6,289 | 1,903 |
| art bank 14 (`$8000-$9FFF`) | 8,192 | 7,581 | 611 |
| common (`$0480-$0FFF`) | 2,944 | 2,185 | 759 |
| engine (the shared code-bank ranges) | 3,836 | 3,158 | 678 |

| Scene | Own code read (of 4,356) | Data bank read (of 8,192) |
|---|---|---|
| 0 | 816 | 1,709 |
| 1 | 777 | 6,690 |
| 2 | 1,758 | 6,960 |
| 3 | 2,132 | 5,353 |
| 4 | 2,742 | 4,657 |
| 6 | 441 | 2,144 |

(The engine is 3,836 bytes, the three identical ranges; the "4,935
identical bytes" above also counted short scattered matches.) Unread is a
lower bound on what is unused, not proof: ~130,000 frames of play, no
scene 5. So the layout below does not depend on dropping any of it.

### The banking layout (128K SuperGame + 16K RAM)

The art and the scene data cannot share a page: 8K + 8K + the scene's own
code (4.4K) is more than 16K. But nothing needs to see both at once except
the drawing code, and that is the shared engine. So art gets a page of its
own, and the engine selects the art page for a blit whose source is art and
puts the scene page back before returning.

| Bank / area | Address | Contents | Size |
|---|---|---|---|
| bank 7 (fixed) | `$C000-$FFFF` | XEGS bank 15 8K, common 2.9K, engine 3.8K (its self-modifying routines copied to RAM at boot), 7800 boot, DLI handler, TIA sound driver, page-switch wrapper | ~16K: tight |
| banks 0-5 | `$8000-$BFFF` | one per scene (0, 1, 2, 3, 4, 6): the scene's own code 4.4K, its data bank 8K, and a copy of the display lists 3.5K | ~15.9K each |
| bank 6 | `$8000-$BFFF` | art bank 14 at `$8000-$9FFF`, its XEGS address, plus the display lists again | ~11.5K |
| cartridge RAM | `$4000-$7FFF` | framebuffers A and B (12.2K), the engine's self-modifying routines, the routine built at `$2409`, the `$0880` table | ~16K |
| console RAM | `$1800-$27FF` | the moved zero-page overflow, the variables (~250 bytes of the common/data banks' written bytes), two display list lists (one per buffer, DLI bits patched when the game changes display list), latch and sound state | ~2.5K of 4K |
| zero page / stack | `$40-$FF`, `$140-$1FF` | the game's zero page (208 bytes used: 16 must move out), the stack (lowest SP `$EA`) | |

The display lists sit in every page that can be selected while the screen is
being drawn, because MARIA reads them in the middle of the frame.

**Every bank is used.** Scene 6 is scene 1 with 231 bytes changed, so its page
can become scene 1's plus a patch applied at load, which frees one bank if the
fixed bank runs out. The fixed bank is the tight spot: slack there comes from
the XEGS-only code that can go (boot `$B7B1`, the copy routine `$B2CC`, the
loader `$2F5A`, the OS vertical-blank glue), then from the unread bytes if the
coverage is widened enough to trust them.

To check before building on it: that no single blit reads both art and scene
data (the blitter has one source pointer, `$03/$04`, plus mask tables in the
common bank, which is in the fixed bank), and that nothing outside the
engine reads the art directly.

### The art bank checks out (same day)
Probe `xpages.lua` (scratchpad `kport/`), scenes 1, 2, 3, 4, 6 scripted plus
`xe-01-easy.inp`, keyed by the loaded scene. Code split by where it will
live: fixed bank (common, engine, XEGS bank 15) or scene page (the scene's
own code, its data bank).

1. **No scene-page code reads the art.** Zero art reads by code at
   `$1203-$22FF`, `$24A5-$24AB` or `$6000-$7FFF`, in any scene.
2. **Stretches of fixed-bank code that read art also touch scene-page
   bytes, and three of the four causes are artifacts:**
   - `RTS`/`RTI` end with a throwaway read at the return address; returning
     into the scene page counts as a scene-page read (`$2A03`, `$2D02`,
     `$B884`, `$BCA5`, all `RTS`). A probe that keeps only the last read of a
     stretch sees nothing else, because the `RTS` always comes last.
   - ANTIC's display-list fetches go through MAME's CPU address space and a
     read tap files them under whatever instruction is running: 24,405 such
     "reads" of `$1900-$1BFF`, the XEGS display lists, which MARIA's
     replace.
   - Real ones, 2,041: `$0FA2` (the vertical-blank button routine) reading
     `$7FE7` from the scene data bank (1,966, an interrupt landing in the
     middle of a blit); blits whose sprite is in the scene's own code or
     data (`$291A` from `$16xx`/`$18xx`, `$29EB`/`$2AFC` from `$7Exx-$7Fxx`);
     and `$2573` reading scene tables `$2036-$2156` between blits.
3. **A blit's source never crosses between regions.** The source pointer
   (`$03/$04`) was loaded ~1.1 million times and stepped within a blit
   (`INC`/`DEC $04`) ~40,000 times across all runs; no step ever moved it
   between art (`$80-$9F`), scene data (`$60-$7F`) and elsewhere.

**Rule for the port:** one bank per blit, chosen from the high byte of the
source pointer (`$80-$9F` → the art bank, otherwise the scene page), and the
scene page restored when the blit returns; the frame interrupt selects the
scene page on entry and restores the previous one on exit (or `$7FE7` moves
to RAM at scene load). Nothing else sees the art.

Two general lessons for read probes on MAME: exclude `RTS`/`RTI` throwaway
reads (track the opcode from the instruction fetch), and expect video DMA to
appear as reads by whatever instruction happens to be running.

### Finding the addresses stored in data: an origin tracer (same day)
Relocation needs every byte that holds part of an address, not only the
instruction operands (those are symbols already). `xorigin.lua` follows
each loaded value back to the byte it came from, through register
transfers, arithmetic, stores to RAM and pushes, and when a value is used
as an address, (zp),Y / (zp,X) pointers, `JMP (vector)`, `RTS` to a pushed
address, or a self-modified absolute operand, it records the origins of the
high and low halves and where they pointed. `port/origin_report.py` sorts
the origins into immediates (`LDA #n` operands, which become `#>label` /
`#<label`), table bytes (which become `.byte >label` entries) and addresses
built in RAM (to read by hand).

**Wrong turn:** the first version took an instruction's data address to
be its last observed read. MAME routes ANTIC's DMA, display-list and
screen fetches, through the same address space, so those reads land in
the middle of CPU instructions and were taken for operands: it reported
5,924 "table" origins, with art bytes pointing at the framebuffers and the
display list at `$1908` as the origin of hundreds of pointers. Corrected:
effective addresses are now computed from the opcode, its operand bytes and
X/Y/SP at the instruction fetch, the way the CPU forms them, and never taken
from observed reads. A short scene-1 run then gives 16 immediates, 169
table bytes and 1 built-in-RAM origin; the first table found is the high
bytes at `$0715`+ in the common bank, one per 22-byte fighter record at
`$0480-$06B1` (the 22-byte-stride writes seen in the census).

General rule, now twice learned: on MAME's Atari 8-bit, a read tap sees
ANTIC's DMA as reads by whatever instruction is running. Filter by
address or compute addresses; never infer an instruction's operands from
the reads around it.

### Where the analysis harness lives (2026-09-25)
A session restart wiped the scratchpad that held the probes, run scripts and
census data used above. They are rebuilt as project files so it cannot
happen again: `probes/xe-census.lua` (writes, reads, executed code, hardware
and colour timing per loaded scene, with the loader/OS dummy-read filter),
`probes/xe-origin.lua` (the origin tracer, effective addresses computed),
`probes/optable.lua` (generated by `port/mkoptable.py` from the toolkit's
6502 table), and `port/run-probe.sh`, which runs any probe over the
standard set (scripted scenes 1, 2, 3, 4, 6 and both recordings) into
`work/analysis/<name>/` (ignored). The runner exits non-zero only on a Lua
error, not on the empty search that made earlier batches report "failed".

### The relocation list (2026-09-25)
Full origin trace (`probes/xe-origin.lua` via `port/run-probe.sh`; the
census rerun alongside reproduced the earlier frame counts exactly),
reported by `port/origin_report.py` into `work/analysis/origin/report.txt`:
71 immediates, 539 table bytes and 1 address built in RAM, as high-byte
origins. Checking each origin's value against the pointer it fed splits
them:

- **482 direct** (447 table bytes, 35 immediates): the stored byte *is* the
  pointer's high byte. These relocate mechanically (`>label` in place of a
  number). Among them: art pointer tables in bank 15 (`$A02A-$A053`,
  `$A0D2-$A0FB`, `$A24C-$A271`, `$BD23-$BD2D` …), dispatch tables in the
  engine (`$25E3-$264F`, `$2701-$27AE`, `$119D-$11C6`), per-scene pointer
  tables in the scene data (e.g. scene 4 `$7DE0-$7FA3`), and the framebuffer
  bases as immediates (`$2818` = `#$30` for buffer B, `$2829` = `#$48` for A,
  `$AD97/$AD9F/$ADB3/$ADBB` in bank 15).
- **128 derived** (92 table, 36 immediate): the value changed between origin
  and use. Three patterns, to be read by hand:
  1. offset-encoded tables. The fighter-record table `$0715-$0731` holds
     `$00-$02` for records at `$04xx-$06xx`: a base of `$04` is added in the
     code, and the base is what relocates;
  2. base + offset arithmetic. `#$28` (the 40-byte row stride), `#$00`,
     small art bytes: the tracker keeps the origin of the loaded operand
     when a base is added to it, so the offset is credited instead of the
     base;
  3. misattributions. `$7962-$7969` hold opcode-like values (`$C9 $20 $F0`)
     and `$7BEA-$7BF7` hold `$FF`: not address bytes.
- **1 built in RAM:** the stack at `$01FF` during the XEGS boot (an RTS trick
  at `$BFE0`), which the 7800 does not use.

Coverage caveat as before: this is what the recorded runs used. The safety
net is end-to-end: the port is checked against the original frame by frame
(same inputs, framebuffer contents compared), which catches any address the
list missed.

### Reviewing the derived origins, and a layout correction (2026-09-25)
**The small-sprite block is written to.** The table at `$0715` is
offset-encoded: `LDA $06F4,X / ADC #$80 / STA $03 / LDA $0714,X / ADC #$04 /
STA $04` (`$0796-$07A3`), so every small sprite's address is an offset from
`$0480`, and the base is the immediates at `$079B` and `$07A2`. The code
also writes into those sprites' headers (clips a height at `$07BD`, draws,
restores at `$07C4`), so the 616-byte block `$0480-$06E7` needs RAM.

**Framebuffer constants.** Shifting both buffers by +$1000 (A `$4808`→`$5808`,
B `$3010`→`$4010`) keeps their spacing and each byte's position within its
page, so row arithmetic and buffer-to-buffer copies still work and only
high-byte constants change. Every executed immediate in `$30-$5F` was read
in context; the framebuffer ones are the base `#$30`/`#$48`, the end
`#$47`/`#$5F` (only compared, so the origin trace cannot see them) and the
row base `ADC #$30`/`ADC #$48`: `$2817 $2820 $2828 $2831 $2D65 $2D73` in the
engine and `$AD96 $AD9E $ADA9 $ADB2 $ADBA $ADC5` in bank 15. The rest are
coordinates and animation states.

**Blit sources in the scene page** (`probes/xe-blitsrc.lua`: every byte
read through `($03),Y`, computed at the fetch; scripted scenes plus the
ending recording). The "art bank for `$80-$9F`" rule needs every scene
sprite outside `$8000-$9FFF` in the scene page, which leaves only 8K for
12.4K. Measured:

| Scene | Scene-code sprites read | Scene-data sprites read | Also |
|---|---|---|---|
| 0 | 227 (pages `$21-$22`) | 867 (`$61-$7E`) | 78 bytes of the XEGS OS font (`$F8xx`), 530 of the small-sprite block |
| 1 | 0 | 2,600 (`$60-$7E`) | framebuffer B (buffer copy) |
| 2 | 971 (`$12-$18`) | 3,301 (`$60-$7F`) | both framebuffers |
| 3 | 1,327 (`$12-$18`) | 2,822 (`$60-$7F`) | 256 bytes of the OS font (`$FD-$FE`) |
| 4 | 1,577 (`$12-$1F`) | 2,449 (`$60-$76`) | |
| 6 | 0 | 509 (`$66-$6C`) | |

Scene-data sprites cover nearly the whole data bank, so the data bank stays
whole at `$A000-$BFFF`. The scene-code sprites are few (~4.1K over all
scenes) and move to the fixed bank, each at its own address. (The reads of
the XEGS OS ROM noted here were first taken for its font. They are not; see
"The OS ROM reads" below.)

**Corrected layout:**

| Where | What |
|---|---|
| fixed bank `$C000-$FFFF` | XEGS bank 15 (8K), the read-only part of the common bank (~2.2K), the scene-code sprites of scenes 0, 2, 3, 4 (~4.1K), 7800 system code (boot, NMI/DLI handler, bank wrappers, dispatcher, TIA sound, stick latch) |
| cartridge RAM `$4000-$7FFF` | framebuffer B `$4010-$57F7`, A `$5808-$6FEF`, **the whole engine** (3.8K, at `$7000`, copied at boot: its self-modifying code and the routine built at `$2409` run as on the XEGS) |
| banks 0-5, `$8000-$BFFF` | one per scene: its own code at `$8000`, its data bank at `$A000`, the display lists |
| bank 6, `$8000-$BFFF` | the art at `$8000-$9FFF` (its XEGS address), the engine's boot copy, the display lists |
| console RAM | the common bank's written parts (small-sprite block, the `$0880` table, variables), the two display list lists, the zero-page overflow, latch and sound state |

Blit rule: source page `$80-$9F` → art bank, `$A0-$BF` → scene page,
`$C0`+ → fixed, below `$80` → RAM. No two sources share a page range.

### Relocation written into the source (2026-09-25)
Every move in the layout is a whole number of pages, so an address's low
byte never changes and relocation is only "add the region's page delta to
its high bytes". `port/reloclist.py` merges the origin trace's direct
origins with the cases read by hand (the twelve framebuffer constants and
the small-sprite base at `$07A2`) into `work/analysis/reloc.txt`: 488 high
bytes, 270 in shared segments and 23-85 per scene. By region pointed into:
scene data 196, art 151, scene code 55, engine 60, common 10, framebuffers
12, the small-sprite block 1, and 4 into the XEGS OS ROM (the font-glyph
pointers, to be pointed at the port's own glyphs).

`port/xesource.py --reloc` writes each of them as an expression over its
region's base symbol (`.byte >R_sdata+$0D00`, `LDA #>R_fbA+$1700`), region
bases defined as `R_<region>` equates. **All six scenes still rebuild byte for
byte, with every relocation (293-355 per scene) landing on an immediate or
a data byte.** A mistake in scene keys was caught on the way: scene 0's
origins are keyed `0*65536+address`, which is just the address, so they
first read as shared; the list now treats an untagged byte in a
scene-specific region as scene 0's.

Regions (XEGS ranges that move as one piece): `sprites $0480-$06E7`,
`common $06E8-$0FFF`, `engine1 $1000-$1202`, `scode $1203-$22FF`,
`engine2 $2300-$24A4`, `scode2 $24A5-$24AB`, `engine3 $24AC-$2FFF`,
`fbB $3000-$47FF`, `fbA $4800-$5FFF`, `sdata $6000-$7FFF`, `art $8000-$9FFF`,
`bank15 $A000-$BFFF`, `os $C000-$FFFF`.

### The OS ROM reads: checksums, and a bug that draws garbage (2026-09-25)
The four places that point into the XEGS operating system ROM, which were
first taken for its font. (The OS character set lives at `$E000-$E3FF`;
these addresses are OS code.)

- **Three checksums of the OS ROM, all in scene 3, all disabled.** `$7315`
  sums `$FD08-$FE07` and compares with `#$77`; `$69D9` EORs and adds
  `$C482-$C581` against `#$7C`; `$7974` sums `$C214-$C313` against `#$05`.
  In the first two a `JMP` placed right after the `CMP` skips the `BEQ` and the
  failure path (`$7328 JMP $7340`, `$69F0 JMP $69FC`, failure at `$69F5`
  setting `$A4/$A5`); in the third, `LDA $84` overwrites the flags before any
  branch. Copy protection or a genuine-hardware check from the disk version,
  switched off when the game went to cartridge. The port drops the loops.
- **A bug that draws OS code as a sprite.** The engine table at `$25C0`
  holds addresses (`$25F8`, `$25FC`, …); it is read one byte out of step,
  so one entry's low byte (`$F8`) becomes a pointer's high byte and the
  blitter draws from `$F820-$F876`. In the title and story sequence this
  happens at frames 105, 111, 609, 615 and 651 (5-61 screen bytes each).
  **Visible in the original:** with those writes suppressed, 277 pixels
  change on the title screen (a blotch beside "KARATEKA" and a dotted line
  under "Copyright 1988 Atari Corporation") and 5 in the story text (dashes
  under "craggy c…", moving up as it scrolls).

The game's stylised lettering is its own art, drawn by the same blitter
into the same bitmap as everything else: no OS font or text mode is
involved. **Decision (user, 2026-09-25): no graphics corruption; bugs in the game are
fixed in the port.** The `$25C0` read is fixed rather than reproduced, and the
frame comparison lists those title/story pixels as a known, deliberate
difference. The dots are the CPU writing OS bytes into the bitmap, so they
are not MAME's XEGS rendering faults; but because that machine's graphics are
imperfect, the port is checked against the original's **framebuffer bytes in
RAM**, never against MAME's rendered XEGS picture.

### The display lists, and the layout that holds (2026-09-25)
**The conflict.** MARIA reads the display lists on every line, whatever bank
is selected, so they must exist at the same addresses in the art bank and
every scene page. But the blit rule needs art and scene sprites in opposite
halves of the window, which leaves no range free in both. 21 of the 32
scene-data pages hold sprites in some scene (`$60-$6E`, `$75-$76`,
`$7C-$7F`; union over scenes), too many to share a half with ~3.1K of
display lists. RAM is full, and with the common bank in it the fixed bank is
~1K short.

**The fix: display lists in the fixed bank, the common bank in each scene
page.** Checked first, with `probes/xe-artblit.lua` (every instruction's
effective address computed at its fetch, interrupts excluded, scripted
scenes plus the ending recording): **while a blit reads art (`$29D8` to
`$29FB` with the source pointer in `$80-$9F`), the game touches only zero
page, the framebuffers, the engine and the art, and runs only engine code.**
No common bank, scene code, scene data or bank 15. The only art read
outside such a blit is the XEGS loader's copy loop (`$B2DA`), which the port
replaces. So `$29D8`/`$29FB` are the whole bank-switching hook.

The health-arrow sprites the blitter reads from the common bank
(`$0B12-$0B24`, pointer built by `LDA #$12 / LDA #$0B` at `$0B70`/`$0B74`;
both `#$0B` immediates, `$0B75` and `$0BBB`, are in the relocation list) move
with the scene-code sprites to the fixed bank.

The scene-code sprites share: every address read as a sprite in more than
one scene holds identical bytes (1,131 addresses, 0 differing), so one copy
serves every scene: 2,047 bytes, in runs `$1203-$1523`, `$1530-$15B2`,
`$1600-$18A1`, `$18BF-$18D7`, `$1C80-$1CED`, `$1F00-$1F28`, `$1FD7-$1FFC`,
`$2193-$2275`.

| Bank / area | Contents | Size |
|---|---|---|
| fixed `$C000-$FFFF` | XEGS bank 15 at `$C000` (it may grow: unrolled copy loops and zero-page movers; nothing points into it), 7800 system code, **the display lists**, scene-code and arrow sprites (page-aligned copies), vectors | ~15.5K |
| banks 0-5 (scene pages) | scene code `$1203-$22FF` at `$8203` (+`$7000`), **common `$06E8-$0FFF` at `$96E8`** (+`$9000`), scene data at `$A000` (+`$4000`) | ~14.9K each |
| bank 6 (art) | art at `$8000-$9FFF` (unchanged), the engine's boot image, the initial copies of the RAM-resident data | ~12.5K |
| cartridge RAM | framebuffer B `$4010`, A `$5808` (+`$1000`), engine at `$7000`/`$7300` (+`$6000`/+`$5000`) | 16K |
| console RAM | zero-page movers, OS-page shadows, the small-sprite block (`$0480-$06E7` → `$1B80`), carved-out variables and the `$0880` swap buffer, system state, mode-8 expansion rows, the two display list lists | ~2.5K of 3.7K |

The NMI selects the scene page on entry and restores the previous bank on
exit, so the interrupt handlers (which live in the common bank now) always
see their code.

### The linker (2026-09-25)
`port/layout7800.py` holds the map (regions, carve-outs, sprite copies,
zero-page allocation, hardware and OS-page mapping, replacements);
`port/link7800.py` assembles every region of every scene at its 7800
address from the source generator's analysis, computing each relocated high
byte from its pointer's target. **It links all six scenes**: every chunk
outside bank 15 assembles to exactly its original size with every label where
the layout says, and the shared chunks (bank 15, engine, art, small-sprite
block) assemble identically for every scene. Bank 15 grows by 528 bytes
(`$C000-$E20F`: the six unrolled record copies and 18 zero-page bytes moved
to absolute RAM). The engine's seven per-scene bytes `$24A5-$24AB` are the
only difference allowed.

Found on the way:

- **Code crossing a region boundary:** one place in any scene. The
  vertical-blank step at `$0FFB` starts in the common bank (`LDA $0F17 /
  BNE $101F`) and runs on into the engine at `$1000`; contiguous in XEGS RAM,
  apart on the 7800. Its 5 bytes become a jump to a system routine that does
  the same and continues in the engine.
- **The garbage-dots bug is a zero-page clash, not a bad table read.**
  `$2422` is the sound-effect starter (`LDA #$15 / JSR $2422`); it uses
  `$04/$05` as its own pointer into the sound table at `$25C0` and leaves the
  first entry's low byte, `$F8`, in `$04`, the high byte of the blitter's
  source pointer. Text is drawn while the typing sounds start, and a text
  blit that reloads only `$03` then reads from `$F8xx`. Fixed in the port:
  `$2422`'s first 4 bytes become a jump to a routine that keeps `$04` around
  the original.
- **OS references that never ran:** scene 0's `LDA #$14 / JSR $F946` (the
  middle of an OS screen-editor loop, `DEX / DEX / DEX / BPL / RTS`, on a
  path no run took) and scene 3's `LDX $FEA8` / `ROL $0278` (data the static
  trace misread as code). They get a system entry that returns and a sink byte.
- **A shared table cannot point per scene.** Bank 15's tables at
  `$B827-$B82A` and `$BE6E-$BE74` point at scene-code sprites, which live in
  the fixed-bank copy in scenes 2-4 and are ordinary scene code in scenes 0,
  1, 6. Only runs that reached scenes 2-4 ever used those entries, so a
  pointer stored in a shared chunk always resolves to the copy.
- **The engine's code map must be shared too.** Scene 6's analysis decoded
  the engine's (identical) bytes around `$10FE` differently from scene 0's,
  because only scene 6 had run that IRQ path; the engine ranges now take the
  union of every scene's code, as the common bank and bank 15 do.
- The source generator had been importing `Karateka-Port/tools/asm.py`, the
  old copy, ahead of the toolkit's; the toolkit's now wins.

### The first 7800 build boots and draws the title (2026-09-25)
**Result: scene 0 runs on the 7800 (MAME `a7800`) and its title frame is the
original's, byte for byte,** except where the original's garbage-dots bug
draws (buffer B rows 56-60 around the "TM" spot, rows 133-134 under the
copyright lines), which the port fixes. Compared as framebuffer bytes, not
screenshots: `probes/fbdump.lua` on both machines, `port/fbcompare.py`
(rows and columns that differ, plus a side-by-side PNG). The story scroll that
follows runs and reads correctly (not yet compared byte for byte).

**Room in the fixed bank.** The NMI redesign overflowed it. Freed:
- dead XEGS code removed from bank 15 (which may change size, since
  nothing points into it): the 8K copy routine `$B2CC-$B2EB` (only the boot
  and the loader call it) and the cartridge boot `$B7B1-$B7DA`. Bank 15 is now
  `$C000-$E1D7` and the system jump table starts at `$E1D8`.
- the common-bank carve list and the scene-to-bank table moved into every
  scene page after the zero-page tables at `$9300` (the loaders always run
  with a scene page in).
- the empty DL and the three mode-8 row DLs (32 bytes) moved to a gap
  between the sprite copies, `$F8B4`.
The system block (code plus the per-row DLs, 3,060 bytes of it) ends at
`$F4E1`, so about 30 bytes are spare before the sprite copies at `$F503`.
**This is tight.** The TIA sound driver will not fit in the fixed bank.
Code that never switches banks can live in the scene pages (about 1K free in
each) instead.

**Bugs found booting, all in the port's system code:**
- **MAME never raises the DLI of a DLL's last line.** The vertical-blank
  stand-in was on line 242 of 243, and no NMI ever came. It works on any
  earlier line.
- **Interrupt code clobbering foreground scratch.** `Inputs` (in the NMI)
  used `S_TMP`, the loaders' byte counter, so an NMI during the engine copy
  cut it short at `$7169` and the game later ran into zeros. The list
  builder used `S_TMP` too. Now `Inputs` uses none, and the builder has its
  own `S_BTMP`.
- **The game's DLI and VBI handlers must never nest.** Both save `$14/$15`
  and `$03/$04` in the same four bytes (`$1193-$1196`) on entry and restore
  them on exit (`$1169`/`$117E`). On the XEGS the vertical blank ends long
  before the next frame's first DLI. On the port, a VBI that ran long
  (building a list takes more than a frame) let the next frame's DLIs in,
  and the VBI then "restored" the DLI's values into `$14/$15`. That
  pointer is the end marker of the screen-clear loop at `$2835`, which then
  ran on and wiped the engine at `$7000`. Now:
  - The VBI DLI sits on the first blank line after the list's content, not
    the last line. That leaves the whole bottom border and top border to
    finish in.
  - A VBI that arrives during a game DLI waits until the DLI ends.
  - A DLI that arrives during the VBI is dropped.
  - A VBI that arrives while the last one is still running is dropped, as a
    late XEGS VBI would be.
  This replaces the "VBI on the last line" design in the previous entries.
- **Self-modifying code writes a zero-page operand.** The blitter picks its
  write mode by storing an opcode (ORA, AND, STA or NOP) at `$2925` and
  `$2B10`. It also stores the operand, `LDA #$14 / STA $2926` (`$289B`) and
  `$2A6D`→`$2B11`, which is the address of `$14`. `$14` moved to `$D5`, so on
  the port those blits read the TIA instead of the framebuffer. The
  capitals B and A drew as solid blocks, and strokes of the logo's "t" were
  lost. Both immediates are now linked as `#<Z_14`. A scan of every scene
  for stores into operand bytes finds only these two zero-page cases. The
  others are low bytes of JSR targets (`$28BB`, `$28BE`, `$2A8D`, `$2A90`,
  from the table at `$298D`), which relocation keeps since it moves only
  high bytes.

**How the title difference was run down**, since the same method will serve
the other scenes:
1. `blitlog.lua` showed every blit had the same source, header and zero page
   on both machines.
2. `fbwrites.lua` logged every framebuffer write in order, and the first
   differing write came in blit 4.
3. `blittrace.lua` traced that blit on both, interrupts excluded, with the
   destination pointer. The first difference was the value `ORA ($14),Y`
   read.
4. `bytewatch.lua` and `p7800-watch.lua` showed who wrote the ORA's
   operand.

**Speed: MAME's `xegs` is not a fair clock.**
- **Measurements.** `probes/cycles.lua` sums 6502 cycle counts per executed
  instruction. MAME's `xegs` executes 28,665 of the frame's 29,868 cycles:
  it doesn't steal ANTIC DMA cycles, as noted earlier. The port under
  `a7800` executes 22,928: 18,985 in the main program and 3,943 in the NMI
  (the original: 2,690).
- **Real-XEGS estimate.** A real XEGS loses about 10K cycles a frame to
  ANTIC (40 bytes a line for 192 lines, plus display-list and refresh
  cycles). That leaves its main program about 17K. **So the port should run
  at least as fast as the real machine**, even though it runs visibly slower
  than MAME's `xegs`. The title's busy loop runs at 64% of MAME-`xegs`
  speed, and the title and the story scroll take correspondingly longer.
  Frame-by-frame comparison against MAME's `xegs` therefore has to be keyed
  on the game's own progress, not on frame numbers.
- **To trim later.** The port's NMI costs about 1,250 more cycles a frame:
  - the wrapper around each of the six DLIs;
  - `Frame` on every VBI, to follow the game's buffer flip.

**Harness** (all in the project): `port/run7800.sh` and `port/runxe.sh` run
a probe windowless against the build or the original. The build writes
`work/karateka7800.sym` (system symbols) and `work/karateka7800.zp` (zero-page
map) for the probes. The probes:
- 7800-only: `p7800-events.lua` (system-routine entries), `p7800-run.lua`
  (state every 20 frames and writes into the ROM window), `p7800-crash.lua`
  (the last N fetches before a jump into RAM, a BRK or JAM, or a deep stack),
  `p7800-watch.lua`, `p7800-peek.lua`, `p7800-ramcheck.lua`, `p7800-rate.lua`.
- Either machine: `fbdump.lua`, `blitlog.lua`, `blittrace.lua`,
  `fbwrites.lua`, `bytewatch.lua`, `pccount.lua`, `pchist.lua`,
  `cycles.lua`, `xe-snap.lua`.

### The story scroll matches too (2026-09-25)
Compared at the same points in the game's own progress rather than at the
same frame: `probes/fbdumpkey.lua` dumps both framebuffers at the Nth
call of `$0862` (buffer flip and frame wait). At flips 10, 20, 40, 60, 80, 100 and
120 (the title through the scrolling story text) the buffers match except
for 3 bytes in one text row, which scroll up with the text. Every differing
framebuffer write was traced (`fbwrites.lua` grouped by blit, then
`blittrace.lua` with the source pointer). The whole difference is the
garbage-dots bug:
- The first differing blit (the original's 117th) has its source pointer
  change to `$F820` partway through the glyph, so it reads OS ROM.
- The 130th blit reads OS ROM for 110 steps.
- The 131st differs by one byte only because it ORs over the 130th's
  garbage.
The port draws the intended glyphs.

The port makes two more blits than the original at the start of the story (the
glyph at `$0522` three times where the original draws it once). They
write nothing, and every framebuffer write lines up one for one after them
(225,282 writes compared). This is likely a wait-for-time loop that simply
goes round more or fewer times at a different speed. Not a difference on
screen.

### Scene 1 runs and matches (2026-09-25)
Scene 1 (the first courtyard fight) plays on the 7800 build. Driven by the
same scripted player on both machines, its framebuffers match the
original's byte for byte at every flip checked through flip 800. That
covers the fight, the player's death and the restart that follows. It took
four fixes and two changes to the comparison method.

**Fixes:**
- **NMIEN is write-only on the XEGS.** Scene 1's start (`$0E97`) enables DLIs
  with `LDA NMIEN / ORA #$80 / STA NMIEN`. The XEGS reads `$FF` there, so this
  also turns the vertical blank back on (the loader had turned both off).
  The port's NMIEN is a readable shadow, which returned 0, so the VBI stayed
  off and the game waited forever at `$0E1A` for the VBI to clear `$0F0F`.
  `$0EA1` is now `LDA #$FF / NOP`. (Scene 0 had worked only because
  `S_NMIEN` starts at `$40`.) A static scan of every scene found no other
  read of a write-only register. The genuine hardware reads are TRIG0/1,
  CONSOL, KBCODE, IRQST (in an IRQ path the 7800 never takes), SKSTAT,
  PORTA and VCOUNT, and the port maps all of them.
- **Mode8 was half the CPU.** In play the NMI took 11,800 cycles a frame
  (the original: 2,300). Nearly all of it went to `Mode8`, which widened the
  30 status-row bytes pixel by pixel on every buffer flip. It also used
  `S_TMP`, the loaders' counter, inside the NMI, the same bug as `Inputs`.
  Now it widens only bytes that changed since the last flip, a nibble at a
  time from two 16-byte tables (in the `$F8B4` gap, after the small DLs),
  with its own scratch. The NMI is down to 4,400 cycles a frame and the main
  program gets 17,800. **That's more than a real XEGS's main program has**
  (MAME's `xegs` gives it 26,000 only because it steals no DMA cycles).
- **An untraced blit source: the player's death.** Every census run used a
  health cheat, so the player never died. The death routine `$6C52` (scene
  data, scenes 0 and 1) sets the source with `LDA #$1E / STA $04` and never
  ran, so it was never relocated. Its sprites are scene code at `$1E00`
  (19×4), `$1E4E` (15×7), `$1EB9` (12×2) and `$1ED3` (13×4). Scene code
  sits at `$8203+` in the scene page, which is the art bank's half of the
  blit rule, so the blitter read art and drew garbage past the framebuffer
  into the engine at `$7000`. The fix:
  - The loader now copies `$1E00-$1F08` to RAM at `$1900` when scene 1
    loads (a scene carve; carves can now come from scene code, and long
    ones are split into 255-byte entries).
  - The `$0880` swap buffer moved from `$1A00` to `$1880` to make room.
  - The immediate is a MANUAL relocation.

  A scan of every scene for `LDA #imm / STA $04` found two more unrelocated
  sources on untraced paths, scene 4's `$703B` (`#$60`) and `$7CD4`
  (`#$6F`). Both point into scene data and are now relocated. Scene 0 has
  unrelocated copies of scene 1's routines in its data, but the title never
  runs them. **Wrong:** the attract sequence runs them after the cutscene
  (the opening run and a demo fight), and they froze the port there; see
  "Story crash" below.

**The comparison method:**
- **Input keyed on game progress.** MAME latches inputs at frame
  boundaries, and those fall at different points of the game on machines
  of different speed. `playkey.lua` counts buffer flips instead:
  - `$0862` in the title and story; `$B60F` in play (bank 15, `$D752` on
    the 7800).
  - `INJECT=1` feeds the stick and fire straight into the game's reads
    (PORTA/TRIG0; SWCHA/INPT4, with the left difficulty forced to B).
  - It dumps the framebuffers and zero page at chosen flips.
- **Fire held for one flip, not two (`SHORT=1`).** The VBI times each press
  in frames (`$0FB0-$0FF8`): 20 frames or more makes the other move
  (`$46`, the kick), shorter makes `$47`. Two flips last about 20 frames on
  MAME's fast `xegs` and about 30 on the port, so the same script made
  different moves. **This is the long-press kick.** It is real time, so the
  port keeps it faithfully.
- **A flip counts when its instruction runs.** When an interrupt arrives
  just as MAME fetches the key opcode, MAME fetches it again after the RTI.
  The probe counted such a flip twice (the original's "missing" buffer
  toggle at flip 652). A key fetch now only arms the count, and the next
  fetch confirms it.

Dead ends, for the record:
- The divergence at flip 653 looked like real-time pacing. `$24A4` loads
  frame-wait counts `$0AFC/$0AFD` from the music data, and `$B60F` skips
  the flip while `$0AFE` is set. It was only the double count.
- MAME's Lua API has no CPU clock scale, so MAME's `xegs` can't be slowed to
  match.

### Scenes 2, 3, 4 and 6 match too (2026-09-25)
The same comparison (`playkey.lua` with `SCENE=n`, which substitutes the
scene for the game-start `$D0 = 1` as the census does; `INJECT=1 SHORT=1`)
at flips 195, 200, 210, 250, 300, 400, 500, 600 and 800:
- **Scenes 2, 3 and 4:** both framebuffers identical at every point. In
  scene 2 the scripted player dies and the game goes back to scene 1, the
  same on both. **Correction (2026-09-26):** scene 4 started this way never
  gets going. The player stands in the right-hand doorway on both machines
  (the scene needs what the end of scene 3 hands over), so scene 4's
  comparison covered only that frozen opening. See "The princess room".
- **Scene 6:** identical. It hands on to scene 1 before flip 200.
- **Scene 1:** identical through flip 2000.

**One more fix, found in scene 3: a sprite that starts inside the engine.**
Scene 3's floor stripes (a 9×22 sprite drawn while the room is revealed)
start at `$1200`. Their header `09 16 AA` is the last three bytes of the
engine's first part (`$1000-$1202`) and their pixels are the first bytes of
scene code. That is contiguous in XEGS RAM but apart on the 7800: the
engine is in cartridge RAM at `$7000`, and `$7203-$72FF` is an empty gap.
The port drew the header's size and blank stripes. No code refers to
`$1200-$1202` and they aren't code, so the fixed-bank copy of scenes 2-4's
sprites now starts at `$1200` (`$F500`, three bytes that were free) instead
of `$1203`. All six scenes hold the same header bytes there, and scene 1
never blits from `$1200` (checked over 50,604 blits).

A note on the method: blit counts per flip were equal on both machines,
which is what pointed at the data rather than at timing.

### The keyboard comes out; the console buttons by retail convention (2026-09-25)
The 7800 has no keyboard, so every keyboard read and the code only they
reach is removed (the user's call). The original reads keys through the
POKEY keyboard interrupt (`$10FD`: IRQST, then KBCODE into `$DD`, with
`$DF = $FF` as "a key came"). The vertical blank's key repeat reads SKSTAT
(`$1004`). The key codes the game checks:
- **Walking mode (`$AE78`):** Space (`$21`), + and * (`$06`/`$07`, walk
  left and right).
- **The move dispatch (`$AEBA-$AF33`)** compares the key in A against Q A Z
  and W S X (moves by key) and B (`$15`, bow, at `$AF20`). The same path
  also reads the joystick's fire flags `$47`/`$46`. With no key, A is 0.
- **Play (`$B71E`):**
  - Esc (`$1C`) pauses.
  - J/K (`$01`/`$05`) switch between joystick and keyboard control (`$C4`).
  - Ctrl-R (`$A8`) skips to the next scene and Ctrl-N (`$A3`) sets the
    enemy's health to 1, both developer cheats.
- **The ending (scene 4, `$7883`)** waits for Ctrl-R to restart.

**Removed:**
- In the move dispatch, the key tests only. A is now always 0 there
  (`LDA #$00` in place of the `$DF` test, since the old path left A = 0), and
  the joystick branches stay. So the bow by joystick (up and fire, which the
  user confirmed) still works.
- The whole `$B71E` key handler, the Esc check at `$B773` and the Esc pause
  loop `$B785`.
- In the engine, the key repeat and the interrupt's reads. The interrupt is
  now `PHA / PLA / RTI`; the 7800 raises no IRQ anyway.
- The ending's Ctrl-R wait. Its loop now only runs the console check
  (`$B603` → `$AF66`), where START restarts.

Bank 15 shrank by 330 bytes (it now ends at `$E0D9`), and the system jump
table moved down to `$E0DA`. The fixed bank now has about 1K spare.
`$AEB1/$AEB3` looked keyboard-only but is the common exit for every move
(`$AED2`, `$AEF9`, `$AF1D`, ...). The linker's check on labels inside a
removed range caught it. That check now ignores references that come from
code another removal replaces.

**Console buttons.** The game's own console keys (`$AF66`, called during
play and at the ending):
- START (CONSOL bit 0) restarts at scene 1.
- SELECT (bit 1) is a pause (press to pause, press again to resume).
- OPTION (bit 2) switches between the title and scene 6.

The 7800 buttons now map by retail convention: Reset → START, Pause →
SELECT (the game's own pause), Select → OPTION. Checked:
`probes/p7800-pausetest.lua` presses Pause at frame 3500 in scene 1, and the
game stops advancing; a second press at 4000 resumes it. Scenes 1-4 still
match the original byte for byte at every checkpoint after the change.
Not yet checked: restarting from the ending with Reset (no run reaches the
ending yet), and Select.

`playkey.lua` now takes the play flip key from the build's symbol file
(`K_B60F`, which the build writes), since bank 15 moves.

### TIA sound (2026-09-25)
**How the game plays.** Captured with `probes/xe-pokey.lua` (title and
play). AUDCTL is `$78` from every scene start: channels 1+2 and 3+4 are each
joined into a 16-bit divider on the 1.79 MHz clock. So the game has exactly
two voices, pitch 1789790 / (2 (N + 7)). The only writer is the engine at
`$10C1-$10DD`. For each voice X it writes:
- the distortion `$2410,X`, to the low channel with volume 0 and to the high
  channel ORed with the volume envelope `$240E,X`;
- the divider, `$2412,X` (low byte) and `$2414,X` (high byte).

It writes about 2.4 times a frame. Distortion `$A0` (pure tone) carries the
music and most effects, and `$00` (poly noise) some effects in play.
Volumes run 1-15.

**The music is tuned about 38 cents flat of A440 throughout** (20 notes,
A1 to F5).

**The port:** `TiaSound` (`sys7800.asm`), run once a frame in the vertical
blank NMI, turns each voice's shadow registers into one TIA channel:
- A tone becomes the nearest TIA tone (AUDC 4, C or 6). A binary search runs
  over the 88 dividers where the nearest tone changes, and a packed table
  gives each tone's mode and AUDF.
- Noise becomes AUDC 8 at the nearest rate (a table by N >> 6).
- A tone above 16 kHz (N below 49) is silent.
- The volume passes through.

`port/sndconv.py` makes the tables (296 bytes, placed by the build in free
gaps among the sprite copies) and renders WAVs by the same rule.
`build7800.py --snd-offset CENTS` transposes the whole score, since TIA's
pitches are fixed and sparse. Recorded from MAME, the port at offset 0
follows the original's pitch track (bass 54 and 72 Hz exactly, the opening
E2 at 78 Hz against 80).

**Choosing the key** (15 notes that sound more than 40 frames, weighted by
use):

| offset | weighted mean error | notes merged | worst common note |
|---|---|---|---|
| 0 (original key) | 25 cents | none | 59 cents |
| +780 | 11 cents | 69 frames' worth | 43 cents |
| -918 | 16 cents | none | 52 cents |

At 0 the melody is mostly within ±25 cents. A#4 is +73, and in the bass
A2 is +77 and E2 is -59. AUDC 6's pitches are about two semitones apart
there, a TIA limit. The default is 0 until the user picks. Recordings to
compare are in `work/analysis/snd/`: `mame/xe.wav` (the original) and
`keys/port0.wav`, `port780.wav`, `port-918.wav`.

**A toolkit bug found on the way, and fixed.** The toolkit's TIA model
(`tracker.py`) had AUDC C, D, 6, A, E and F an octave low. It took "÷6" as a
square stepping every 6 ticks (a period of 12), and "÷31" likewise. The
port's first recording played an octave above the model's render, which
exposed it. Every AUDC was then measured with single-tone cartridges
(`mktone.py --tia`, new) and autocorrelation:
- `$4`/`$5`: 2 ticks;
- `$C`/`$D`: 6;
- `$6`/`$A`: 31, 18 high and 13 low;
- `$E`: 93;
- `$1`: 15;
- `$2`/`$3`: 465;
- `$7`/`$9`: 31;
- `$F`: 93;
- `$8`: 511.

`tracker.py`, `docs/audio.md` and a new self-test (`t_tia_periods`) are
corrected in `a7800-toolkit-local`, not yet committed or carried to the
public repo.
- Hand-written songs now play as written.
- Captures made before the fix name those modes' pitches an octave low, so
  they should be made again.
- `sim.py`'s POKEY mismatches are unrelated: it compares register logs,
  not pitches.

### MARIA's DMA in play, measured (2026-09-25)
`probes/p7800-dma.lua` works out, per 100 frames of play:
- the 6502 cycles actually executed: base counts, plus taken branches, plus
  page crossings worked out from the operands and index registers at each
  fetch;
- the slow-access penalty: TIA and RIOT run at 1.19 MHz, which costs +0.5
  cycle per access;
- **measured DMA = 29,868 − executed − slow.**

It also prices the display list list on screen with `dmabudget.py`'s
constants. The scripted player drove the game with `INJECT=1 SHORT=1`.

| scene | lines drawn | executed | slow | measured DMA | frame | model |
|---|---|---|---|---|---|---|
| 1 | 177 | 22,298 | 125 | **7,445** | 25% | 7,897 |
| 2 | 135 | 23,725 | 125 | **6,017** | 20% | 6,472 |
| 3 | 105 | 24,751 | 125 | **4,991** | 17% | 5,455 |
| 4 | 105 | 24,751 | 125 | **4,992** | 17% | 5,455 |

- Within a scene it varies by about ±5 cycles between blocks. It depends
  only on how many lines show bitmap: every line is its own zone with two
  20-byte objects, about 41 cycles a drawn line and 7 a blank one.
- **The model overstates by a near-constant 455-465 cycles** (6-9%) in every
  scene. That looks like a fixed per-frame term, about 4 scanlines, not a
  per-line one. Not chased.
- **A real XEGS's ANTIC would take about 8,700 a frame** for scene 1's
  screen: 41 cycles per mode-E line, plus refresh on all 262 lines. So MARIA
  steals less than ANTIC did. MAME's `xegs` charges none of it.
- These are MAME's timings; real hardware is the check still to do.

### Flicker: the new frame was shown a frame late (2026-09-25)
**Reported from the Analogue Pocket** (openFPGA 7800 core): the screen
flickered, as if some objects were not drawn every frame. The byte
comparisons could not catch this. They check what is in the buffers, not
which one is on screen.

**The cause.** The game double-buffers: it draws into the hidden buffer,
then switches the display in its vertical blank (DLISTL/H, taken by ANTIC at
once). The port's `Frame` applied a new list at once only if MARIA was in
vertical blank (MSTAT bit 7), and otherwise waited for the next vertical
blank. The game's VBI runs at the port's stand-in DLI below the picture,
where MSTAT does not yet show vertical blank. So every switch waited a frame,
and for that frame the screen showed the buffer the game was already
redrawing.

**Measured** with `probes/p7800-shown.lua` (writes into the buffer on screen,
while on screen) against `probes/xe-shown.lua`:
- the original: 0 in every 100 frames of play;
- the port: 2,400-7,700 writes, in 3-7 frames of every 100, about one per
  buffer flip.

**The fix.** `Frame` applies at once when called from the game's vertical
blank (`S_INVBI` set), and keeps the MSTAT test only for calls from the main
program mid-frame. This is safe because MARIA reads DPPH/DPPL only at the
start of a frame. At the stand-in point the rest of the frame is blank lines,
so the new list starts exactly at the next frame, as ANTIC's would.

**After the fix:** 0 visible writes over 3,200 frames of scene 1 play.
- 1,390 writes landed in the old buffer after that frame's switch, below the
  picture. The first version of the probe miscounted them as visible, because
  it moved its idea of "shown" at MAME's frame boundary rather than at the
  switch.
- Scenes 1-4 still match the original byte for byte.

### Hanging notes and the palette: the NMI count drifted (2026-09-25)
Two more reports from the Pocket:
- a note hangs after a button press in the intro or between scenes, until
  the next part loads;
- the enemy's health arrows (bottom right) and the fighters' outlines are
  sometimes the wrong colour (grey or blue).

Both came from how the port told the vertical-blank NMI from the DLIs: by
counting NMIs in the frame against `S_NMIVBI`.

**The hanging note.** Pressing fire in the title music:
- The original holds the last note 32 frames, then its next scene's setup
  (`$0E46`) zeroes POKEY.
- The port held it 269 frames.

During the gap the port's frame counter stood still. `S_NMICOUNT` was 89,
past the blank loading list's `S_NMIVBI` of 1, because that list had taken
over mid-frame. An exact match (`BEQ`) then waited for the count to wrap:
256 NMIs, one per frame, over 4 seconds with no vertical blank, so no music
driver and no progress. A first fix (`BCS`, "at or past") cured that case.

**The palette.** `probes/p7800-palette.lua` against `probes/xe-palette.lua`:
- The original writes COLPF0-3 three times a frame: from the VBI (its DLI
  counter `$0F14` at 0, the top band), then at counter values 3 and 6. The
  values match the port's.
- The port wrote only two sets, and `probes/nmicount.lua` showed 5 game DLIs
  a frame against the original's 6.

`probes/p7800-nmitrace.lua` showed the count one out of step, and stable that
way:
- the game's last DLI (line 193) was taken for the VBI;
- the real stand-in (line 205) arrived while that "VBI" still ran, and was
  dropped;
- so every DLI ran one index late, and the last colour set (the bottom band,
  the health arrows) never happened.

Once a list change mid-frame puts the count one out, it never recovers, since
every frame has the same number of NMIs. (The grey itself is partly the
game's own: its counter-3 set writes COLPF1 = `$08` instead of `$88` in
about 2-4% of frames on both machines.)

**The fix: no counting.** The RIOT timer, unused by the port until now, tells
the NMIs apart:
- Every vertical blank arms `T1024T` with 28 (28,672 cycles, just short of a
  frame's 29,868).
- An NMI that finds `TIMINT` bit 7 set is the vertical blank.
- The stand-in moved to a fixed line, `VBI_LINE` (241). ANTIC's VBI comes at
  display-list line 240, so this restores the original's timing: about 52
  lines to the next frame's first DLI, and the handlers need about 2,300
  cycles.
- Every list's last DLI is at line 193, 48 lines ahead. The build now refuses
  any list whose last DLI is within 16 lines of `VBI_LINE`.
- `S_NMICOUNT` is kept only for the probes.

**Checked after the change:**
- 6 game DLIs and 1 VBI a frame;
- three colour sets at counter values 0, 3 and 6 with the original's values;
- 0 writes into the shown buffer;
- a note held 37 frames after a press (original: 32);
- scenes 1-4 byte for byte.

### No RIOT timer; the NMI count made unable to drift (2026-09-25)
**RIOT is not safe while MARIA runs DMA** (the user pointed to
7800.8bitdev.org, "RIOT limitations and workarounds"). MARIA halts the 6502
but not the 6532, so an access under way when a halt begins loses its
address and write-enable partway through. Some consoles are affected and some
are not, and it is worse with heavier DMA. The timer design wrote `T1024T`
at line 241 and read `TIMINT` at every NMI, all during DMA. It is gone. The
port now uses RIOT only for the joystick and console switches, and reads
them once a frame in vertical blank.

**The design now:**
- **Every list has the same seven NMIs.** All 20 XEGS lists have exactly six
  DLIs (at lines 31, 84-85, 112-126, 137-138, 180-190 and 193), plus the
  stand-in at `VBI_LINE` (241). The build refuses any list that differs.
- **The blank list is in ROM** (`BLANK_DLL`, 37 entries). It has six dummy
  DLIs on the usual lines and the stand-in at 241. The dummy DLIs skip the
  game while it is shown (`S_SHOWBLANK`), since the XEGS gets no DLIs with
  DMA off. Being in ROM, it is never rebuilt over a list on screen, which was
  one way the count used to drift. MARIA reads DPPH/DPPL only at the start of
  a frame, so switching lists cannot change the frame under way.
- **A safety net for the count.** The NMI the count names as the vertical
  blank waits for MSTAT bit 7, up to 110 turns (about 10 lines).
  - Measured: it arrives after 4 turns, every frame.
  - If it never comes, the NMI was mid-screen. It is handled as a DLI, and the
    count is set so the next NMI is the vertical blank. Any slip then heals
    within a frame. No corrections were seen in 6,000 frames.
- **RIOT only in vertical blank.** `Inputs` (vertical blank) keeps SWCHA and
  SWCHB in `S_RSWCHA/B`. `ReadStick` uses that copy, so a stick reading is up
  to a frame old; the XEGS reads live.

**A correction on MARIA's DLIs: a zone's DLI comes as the zone starts, not
at its last line.** The first ROM blank list merged blank lines into 16-line
zones and flagged the zone covering 226-241 for the vertical blank. Its NMI
came about 17 lines before vertical blank, at the zone's start, so the MSTAT
wait never succeeded and no vertical blank ran. The game lists never showed
this, because their zones are one line tall. Flagged zones must be exactly
the flagged line; the blank list now uses one-line flagged zones with 16-line
fillers between. (`probes/p7800-mstat.lua` measured MSTAT: vertical blank is
about 20 lines a frame.)

**The comparison method, again.** With the vertical blank at line 241 the
port and MAME's `xegs` agree less well on where the VBI falls against the
main loop. The game's VBI turns the trigger into the short-press flag `$47`,
and the main loop then took it one flip earlier on the port (flip 221,
against 222). The scene then diverged: timing, not a fault.
- `playkey.lua FIREFLAG=1` now presses fire by setting `$47` at the start of
  the flip on both machines (unless `$46` is set, as the VBI does).
- With `INJECT=1` it also feeds the port's stick copy, and only once the
  cartridge runs. A first version tapped those RAM bytes from power-on, and
  the 7800 BIOS, which uses the same RAM, hung at `$F96E`.

**Checked:**
- scenes 1-4 byte for byte (flips 300-800, and 250/500/800);
- 6 DLIs and 1 VBI a frame, confirmed every frame;
- the three colour sets as on the original;
- 0 writes into the shown buffer;
- a note held 36 frames after a press (original: 32).

**The post-death title** (reported: the lower half of the last 'a' missing
on the Pocket) could not be reproduced. At that point both framebuffers
match the original byte for byte, and MAME shows the logo whole on both
machines (the original shows no copyright lines there either). The logo sits
across the second DLI line, so a DLI landing on the wrong band could hide
part of it; the count drift was that kind of fault. Retest on the Pocket
pending.

### Story crash: the attract sequence past the census (2026-09-25)
Reported from the Pocket: the story scroll stops at "Defeat Akuma and
rescue the..." and the machine stops responding. Every census run pressed
fire during the story, so nothing after about line 17 of the story was ever
traced: not the rest of the scroll, not the cutscene, not what follows. Each
fix below let the no-input run get a little further, to the next untraced
fault.

**The chain, in order:**
1. **The story text table.** `$7983` loads line pointers from `$7BCC,X` /
   `$7BE6,X` into `$E5/$E6`. The census relocated only the lines it saw, so
   lines 18-25 were read out of cartridge RAM. Fix: `MANUAL_TABLES` in
   `reloclist.py` (split tables relocated whole).
2. **The hyphen glyph lies past the sprite block.** The glyph sits at
   `$06E8-$06F5`, just after the block's end at `$06E8`. Fix: the build
   appends that tail to the sprite image (`SPRITE_TAIL`), and `LEN_SPRITES`
   covers it.
3. **A write to `$6009` as the story ends (`$740A`).** On the XEGS that is
   RAM. On the 7800 it lands in ROM, and any write to `$8000-$BFFF` switches
   the bank, so the next fetch came from bank 7. Fix: carved to `$1AA0` for
   scene 0.
4. **The cutscene's sprites.** They are drawn from scene code and from bank
   15's hi-byte tables, which were unrelocated or in a bank the blitter
   doesn't read. The fixes:
   - `ART_COPIES` (scene 0's sprites copied into the art bank);
   - a per-scene page map (`SP_PAGEMAP`, `$81A0`): the blitter reads a
     `$A0-$BF` source from the art bank when the page is marked;
   - `SCENE_TABLES`: per-scene copies of bank 15's hi-byte tables at `$81C0`.
   A linker slip came with the last one: bank 15's references still
   resolved to its own local table. The table ranges now go into
   `assemble_chunk`'s carved set, so references go through the resolver.
5. **After the cutscene the port froze at `$7043`.** The engine code in
   cartridge RAM at `$7000` had turned into `$AA` bytes.
   - A write tap found the blitter (`$7927`) copying straight past the end
     of buffer A (`$6FEF`) into the engine.
   - The stack at the first bad write gave the caller: scene 0's `$6D91`,
     `LDA #$6A / STA $04`, a sprite at `$6A31` in scene data. It was never
     relocated, so the blitter read a "sprite" out of framebuffer A (`$6A31`
     on the 7800). The garbage height ran the copy off the end.
   - This is the code the earlier scan dismissed ("the title never runs
     them"). After the cutscene the attract sequence plays the opening run
     and a demo fight with scene 0's bank, and most of scene 0's data
     (`$63C4-$73EC`) and part of its scene code are scene 1's, at the same
     addresses. They differ only in JSR operands: scene 0 calls the engine
     at `$284E` where scene 1 has `$2803`, and at `$2B82` for `$2809`.
6. **Fix, part one: scene 1's relocations applied to scene 0.**
   `reloclist.py` gives scene 0 a copy of every scene 1 entry whose
   surroundings (16 bytes either side, JSR/JMP operands aside) are the same
   in both scenes. That is 27 entries: `$6C58`, `$6D38`, `$6D92`, `$6DD9`,
   the `$6E0C` table, `$7061` and `$71C3-$71C7`.
   - `$6C58` is the death-sprite pointer. In scene 1 those sprites are
     carved into RAM at `$1900`, since scene code sits in the art bank's
     half of the blit rule. Scene 0 now gets the same carve.
7. **Fix, part two: scene 0's own opening-run code.** The next freeze had
   the same cause: `$773C` → `$6383` draws the scenery from a split table,
   lows at `$6353` and highs at `$635F` (12 entries, X 12-23), never
   relocated. A new scan, `probes/scanhi.py`, finds pointer high bytes a
   scene loads and stores to `$04`, `$E6` or `$15`, as immediates or from
   tables, that `reloc.txt` doesn't cover. In scene 0 it turned up:
   - the `$6353/$635F` table (`MANUAL_TABLES`);
   - blit sources at `$78D5` (`#$7E`) and `$7934` (`#$7F`);
   - four text pointers (`#$62` into `$E6`) in stubs at `$620E/$622C`. These
     stubs are called only from a block after `$7790`'s unconditional JMP,
     so they are probably dead code. They print a hidden developer message.
   The scan's remaining hits are tails of shorter tables that it over-reads.

**Result:**
- The no-input run loops cleanly through title, story, cutscene, opening
  run, demo fight (the player loses) and back to the title, 15,000 frames
  without a fault.
- Fire pressed in the story (twice, including at "Defeat Akuma"), the
  cutscene, the opening run, the demo fight and the title starts scene 1
  every time.
- `port/regress.sh` (new; it reuses the original's dumps) still shows
  scenes 1-4 byte for byte identical.

**Still open:**
- **The original crashes here on MAME's `xegs`.** After its cutscene
  (f4686-4739), `$ADCA`'s buffer copy runs away past `$5FF0`, and the PC
  later reads `$0000`. The port runs the same copy without trouble. The
  suspect is `$04` changed under the copy by nested DLI/VBI timing on
  MAME's `xegs`, which lacks ANTIC DMA. Not confirmed, and not a port
  fault. It is why no reference run reaches this part of the game.
- **Other scenes have untraced stretches too.** `scanhi.py` over scenes 1-6
  flags partly relocated tables. Some are the over-read tails of shorter
  tables, but several look real:
  - scene 1 `$7623` (`$762F-$763A` relocated, `$7623-$762E` not) and
    `$7C17`;
  - scene 2 `$7117` and `$B097`/`$BCDE`, which are bank 15 addresses;
  - scene 4 `$1D34` (24 entries, none relocated) and `$7DDF`, `$7EA3`,
    `$7F0F`, `$7E22`, `$7F82`;
  - scene 6, which holds scene 1's code like scene 0 does, with none of it
    relocated (`$6C57`, `$71C3`, `$7623`, `$7C17`).
  Each needs its real length and index range read from the code before it
  is relocated. Scenes 1-4 still match on the scripted runs, so these are
  paths that those runs don't take.

### sys7800.asm lost and rebuilt from the transcript (2026-09-25)
An inline edit did `s.index('BlitBank:')`, meaning to cut from that routine
to the next one. It matched `SysBlitBank:` first and deleted most of the
file. Nothing was committed yet. The file was rebuilt by replaying the
session transcript: the last full Write of the file, then every later Edit,
`sed -i` and inline Python step that touched it, in order, stopping before
the damaging edit. Python `assert`s became `_ =` so a step's replacement
still ran.
- **Checked:** the head and tail matched the parts that survived.
- **Checked:** the assembled bytes equal the last good build, apart from
  operands of symbols that moved.

The replay script and a checkpoint of the source now sit in
`../Karateka-Port-checkpoints/` (dated folders, no ROM data), until the port
is committed.

### Pocket retest: the post-death 'a' is gone (2026-09-25)
The user could no longer reproduce the missing lower half of the logo's last
'a' after the palette fix. So it was most likely the same fault: the NMI
count drifting, so that a DLI's colour change landed on the wrong band (the
logo crosses the second DLI line). Closed unless it comes back.

**A lead for the partly relocated tables (user):**
- In levels 2 and 3 the game keeps sending enemy after enemy while the
  player stays away from the right-hand side. Their heads come from a
  roster the game cycles through, so the tables `scanhi.py` flags in scenes
  2 and 3 may be the later entries of that roster.
- The scripted runs never go that far down the roster.
- Testing it by hand needs an easier build.

### A build without MAME: the patch kit (2026-09-25)
The user asked for a build that doesn't depend on MAME. A script should chop
the cartridge up, put it back together in the right order, apply a BPS or
an ABP (with options such as invincible and easy mode), add the .a78 header
and sign it. `port/mkkit.py` now writes that kit to `dist/karateka7800-kit/`:
- `make.py`, the one command:
  `python make.py Karateka.car [--with invincible,easy] [-o out.a78]`,
  or `--list` for the options;
- `kit.json`: the original's identity, the chop map and the header fields;
- `karateka7800.bps`: the chopped original to the port's 128K body;
- `karateka7800-options.abp`: the options, in the Anchored Bundle of
  Patches format;
- copies of `bps.py` and `abp.py` (from Anchored-Bundle-of-Patches, MIT)
  and `sign7800.py` (from the toolkit).

make.py needs only Python 3. It:
1. checks the dump (the .car, or the same 128K bare) by SHA-256;
2. chops it into the 7800's order;
3. applies the BPS, then any options;
4. signs and verifies, and adds the header.
With no options it also confirms the result equals the release build.

**The chop map is derived, not written by hand.** The first try matched
whole pages, and it left 860 original 8-byte runs as literals in the
patch. The loader copies some material to addresses that aren't
page-aligned with where the cartridge holds it: the common block is at
`$A268` in the cartridge and runs at `$06E8`. The map now has two passes:
- **Alignment.** Each 32-byte block of the port votes for the offset into
  the original where its 8-byte runs occur. Runs found in more than four
  places don't vote. Neighbouring blocks with the same offset merge. That
  gives 420 pieces in place.
- **Completion.** Original material the port uses that the first pass
  placed nowhere goes into the chopped image's unused space: 372 pieces,
  32.6K. These are images that start mid-block, and code too dense with
  changed operands to vote.

**The BPS uses all four beat actions.** `bps.py`'s `create` only writes in
place (SourceRead/TargetRead). With that, the reassembled fixed bank would
ride along as literal bytes. `mkkit.py` has its own encoder:
- SourceRead: 54.9K;
- SourceCopy, original material at another offset: 20.2K;
- TargetCopy, the port's tables repeated across scene banks: 46.3K;
- literal: 9.7K, the port's own code and tables plus changed operands.
The patch is 20.4K. `bps.py`'s apply reads all four actions, and nothing
else has applied the patch yet.

**Checks in `mkkit.py`, each of which fails the run:**
- the kit, run in a separate process on the .car, rebuilds
  `work/karateka7800.a78` byte for byte;
- no literal run of 8+ bytes in the patch occurs in the original;
- every option set applies, edits only its own sections (besides the
  signature), re-signs and verifies;
- each option site holds the instruction it is meant to patch.

**The options.** They are the xe-easy.lua playthrough aid made into
patches. Every scene bank except bank 0 carries them; bank 0 is the title
and attract sequence, which stay as the original.
- **invincible** (knob "player"):
  - `DEC $B6 / BNE` at `$0BE5` becomes `BEQ` to the RTS. Z is always set
    there by the preceding `LDA #$00`, so A, X and Y leave as before.
  - The instant-death `BEQ` at bank 15 `$B12E` becomes `NOP NOP`.
  - The gate's `LDA $A7` (scene 2) becomes `LDA #$00`.
  - The cliff's `LDA $A2` (scenes 1 and 6) becomes `LDA #$00`.
- **easy** (knob "foes"): the foe's `DEC $B7` at `$0BF6` becomes
  `STA $B7`. A is 0 there and Z stays set, so any hit is a last hit.

The build now writes the sites' 7800 addresses to
`work/karateka7800.sites.json` (`PATCH_SITES` in `build7800.py`), taken
from each scene's resolver as a label plus an offset. A first version asked
the resolver for `$B12E` itself. That address is inside a routine, so the
resolver returned bank 15's plain offset (`$D12E`). The routine really sits
at `$D208`, because bank 15 was reassembled and instructions changed
length. Only labels map exactly.

**Checked in MAME** (`CART=` now selects the cartridge for `run7800.sh`),
scripted fights, invincible+easy against the plain build:
- no damage write from `$9BE5` at all (plain: health down to 7 in scene 2);
- the first hit sets the foe's health to 0 (`$9BF6`), and the game then
  sets up the next foe as usual.

**Still needs MAME, for development only:** regenerating the kit from
source needs the census and origin data in `work/analysis`, which came
from MAME runs of the original. The kit itself needs none of it.

### Flashing black after the story (2026-09-25)
Reported from the Pocket: once the text scroll ends, every screen flashes
black constantly. MAME showed the same, once looked at frame by frame (the
earlier checks sampled one frame in 100). `probes/p7800-blanklog.lua` logs
the list on screen each frame. After the story the port showed the blank
list for about 8 frames in every 18.

**Cause:** `Frame` falls back to the blank list when the game asks for a
list its scene doesn't have. Each scene's lists came from the census, which
never got past the story. Scene 0 lacked `$19B3`, the play screen, which
the attract sequence's opening run and demo fight use.

**Fix:** the build now gives each scene every list another scene's census
saw, whenever this scene holds a valid list at that address (it parses, has
six DLIs, and ends above the vertical blank line; `build7800.py`
`shared_display_lists`).
- Scene 0 gains `$19B3`. It is scene 0's own version, whose third DLI is
  ten lines lower than scene 1's.
- Scene 4 gains `$1A0A`, and scene 6 gains `$1A5E` and `$1B04`.
- **Dead end:** first I required the list to describe identically in both
  scenes. Scene 0's `$19B3` differs from scene 1's, so it wasn't added.

**Result:**
- **Attract loop:** no blank frames in 15,000 frames, beyond the 13 at
  power-on before the game picks its first list.
- **Play:** the only blanks come with a scene load (DMA off, and the
  loader's own list `$2F48`), as on the original.

### Drawing below the screen, and a DLI inside a DLI (2026-09-25)
With `$19B3` on screen the attract sequence crashed at about f5200: the
engine at `$7000` was overwritten again. Two faults, both in the original,
both fatal only on the 7800.

**1. No bottom check on the row address.**
- `$2D46` computes row Y−35, times 40, plus the buffer. The blitters (two)
  and the fills then draw `$0D` rows, 40 bytes apart. Nothing stops a draw
  past row 153. `$2DA4` clamps only the top, and only for fills.
- A sprite partly below the screen wrote past the buffer. On the XEGS that
  lands in scene-data RAM at `$6000`. From buffer B it lands in the top of
  buffer A, which is visible. On the 7800 it lands in the engine.
- A draw starting above the top wraps to a large row and also runs past the
  end. On the XEGS none of it shows.

**Fix:** `$2D46`'s first 16 bytes (up to the multiply) become
`JSR SysRowBase`. `RowBase` then:
- cuts `$0D` to the rows left above the bottom;
- sends a draw that starts at or past the bottom (or wraps) to a 48-byte
  scratch row (`S_CLIPROW`), one row only, returning straight to the
  caller;
- leaves the game's own code after the multiply to add the buffer base.

Every blit and fill sets `$0D` afresh, and only the engine's own loops read
it, so capping it per call is safe. Nothing that reaches the screen changes.
The once-per-call check costs almost nothing. A per-row check would have
cost about 30 cycles on every row of every sprite.

**Room:** the fixed bank's system block had 16 bytes left. The build now
assembles everything after `;;; FAR` in `sys7800.asm` separately, places it
in a free gap (RowBase: 47 bytes at `$FE25`) and hands its labels to the
main block as equates. The jump table gains `SysRowBase`, last, so no other
entry moves.

**2. A DLI inside a DLI.** Even with the clipping, the blitter wrote
`$71D7` at f4264. Its registers made no sense for that address: `$06` =
`$77` (row 84), buffer B, 43 rows. A trace of saves and restores showed the
cause:
1. The blitter sets `$14/$15`.
2. A DLI saves them (`$7169`), and its body (`$7125`) sets them to its own
   pointer.
3. A second DLI arrives before the first ends. It saves that pointer and
   restores it.
4. The first DLI restores the same wrong pointer. The blitter then draws
   into the engine.

Scene 0's `$19B3` has two DLIs only 3 lines apart (scene 1's are 13
apart), which is less than the handler takes on the 7800 with the NMI
dispatch on top. The port already kept a DLI out of the VBI and made a VBI
wait for a DLI, but it never guarded DLI-in-DLI. This is probably the same
fault behind the original's own crash after the cutscene on MAME's `xegs`
("Story crash", still open), where `$04` changes under the `$ADCA` copy.

**Fix:** a DLI that arrives while one is running sets `S_DLIPEND` and runs
as soon as the first ends. The game's handler counts its own DLIs, so the
late one still does its band's work, a few lines late.

**Checked:**
- attract loop, no input: 15,000 frames without a fault; the cutscene, the
  opening run and the demo fight all draw correctly;
- no blitter write past either buffer (`$6FF0-$7FFF`, `$57F8-$5807`), in
  the attract loop or in scripted play in scenes 1-4 (`p7800-firstover.lua`
  now takes `WLO/WHI/BLITONLY` and reports when playkey ends the run);
- six game DLIs and one VBI every frame, cutscene included (`nmicount.lua
  NOPLAY=1`);
- scenes 1-4 byte for byte (`port/regress.sh`);
- the kit rebuilt and re-proved.

### How much of the screen the game redraws (2026-09-26)
The user asked whether the whole screen is written every frame.
`probes/p7800-fbwork.lua` counts framebuffer writes by routine, per buffer
flip (a DPPH change), over 600 frames:

| span | flips | bytes written per flip | distinct bytes touched, both buffers |
|---|---|---|---|
| scene 1, scripted fight | 45 | 2,947 | 7,736 of 12,240 |
| scene 2, scripted fight | 44 | 3,840 | 7,132 |
| attract demo fight | 35 | 3,875 | 7,996 |
| story scroll | 58 | 7,045 | 12,160 |

- **In play the game redraws only what changes.** A buffer is 6,120
  bytes, and about half of it is rewritten per flip. The rest (sky,
  mountain, most of the floor) is drawn once when the scene is set up.
  `$280F` clears a buffer and `$ADCA` copies one buffer into the other.
- **The writers in play, largest first:**
  - rectangle fill `$2CE6` (erasing the last positions; 1.2-1.8K a flip);
  - blitter A's stores `$2927/$2946` (1.0-1.4K);
  - blitter B `$2B12/$2B3E` (0.3-0.5K);
  - the pattern fill `$2D20/$2D29` (the striped floor, about 0.35K).
- **The story rewrites nearly everything:** the scroll (`$0845`) moves
  about 5,800 bytes per flip.
- **A new picture every 13-17 frames in these scripted fights.** MARIA
  shows the finished buffer every frame and re-reads all of it each time,
  whether or not it changed.

### Empty zones for the sky? Measurements (2026-09-26)
The user suggested giving MARIA nothing to draw on the top lines in play,
which seem to hold only a colour fill. That saves about 34 cycles a line: a
zone with the row's two 20-byte objects costs about 41, an empty zone about
7.

**What the rows hold** (`probes/p7800-rowuse.lua`: every row of the buffer
going on screen, at every flip, grouped by the scene in play):
- **Scene 1** (566 flips):
  - rows 0-15 are uniform `$AA` in 97-100% of flips;
  - rows 16-46 are `$AA` in 70-95% (something passes through them the
    rest of the time; not identified);
  - rows 47 and down are nearly always mixed.
- **The sky isn't background.** `$AA` is pixel value 2, a playfield
  colour, and COLBK is always black. An empty zone shows MARIA's BACKGRND,
  so BACKGRND would have to be the sky colour for those lines, switched at
  the band's own DLIs. Any value-0 pixel in that band would then also turn
  sky-coloured, so it only works while every row of the band is uniform.
  In scene 1's list, the first bitmap band is rows 0-37: 38 lines, about
  1,300 cycles a frame.
- **Scenes 2-4** (the fortress) have content in their top rows. Only
  scattered rows are always zero (2-4 per band edge, about 8-10 rows in
  all). **Wrong, corrected in "The top band, measured in real play"**
  (the fork's FINDINGS): the same logs show rows 0-23 (scene 2) and 0-47
  (scenes 3 and 4) uniform `$00` in every picture but the first after a
  scene load; the user pointed out that the fortress rooms are black above.

**Whether freed cycles help** (`probes/p7800-idle.lua`: turns of the flip
wait loops at `$D6F9/$D70B`, 7 cycles each). In play the game waits only
500-700 cycles a frame, about 2%. It is CPU-bound, so any DMA saved goes
straight into drawing, and new pictures come sooner. The exceptions are
scene setups (up to 35% waiting in scene 3's first seconds).

### The NMI's cost, trimmed (2026-09-26)
Kept fallback: `../Karateka-Port-checkpoints/2026-09-26_KEEP_before-nmi-trim/`
(source, both cartridges, the kit), until this build proves itself on
hardware.

**Measured first** (`probes/p7800-nmiprof.lua`): every instruction from
the NMI's entry to its final RTI, charged to the nearest system label or
to the game's code by region. A first version never saw the final RTI and
counted everything as NMI. It had looked up the RTI's address at script
load, before the cartridge is mapped.

**Scene 1 play, before:** 4,860 cycles a frame in the NMI:
- the game's own handlers: about 2,270 (the DLI body at `$1026` and the
  sound work it calls, and the VBI);
- the port's overhead: about 2,590:
  - Mode8, 880 (its 30-byte compare, run every frame);
  - entry, exit and DLI dispatch for 7 NMIs, about 990;
  - Frame/SetDlist, about 300;
  - inputs, sound and Apply, about 270.

**1. Frame does nothing when nothing changed.** The game's VBI asks for its
list every frame, but a new picture comes only every 13-17 frames. Frame
now records the list and DMA bit it last chose (`S_CHOSEN`) and returns at
once on a repeat. Power-on and every scene load clear the record.
- Safe because the game never writes into the buffer on screen: 0 writes
  over 15,000 frames of the attract loop and scripted play in scenes 1-4
  (`p7800-shown.lua`, now with `NOPLAY`).
- Scene 1: 4,860 → 3,816. Story: 3,931 → 3,679.

**2. The DLI goes straight to the game's handler.**
- **Before:** the NMI saved A, X and Y, switched banks, and built a fake
  interrupt frame so the handler's RTI came back into the port. The
  handler then saved A, X and Y again.
- **Now:** the NMI saves only A and the bank, and jumps to the handler.
  The handler's ending (`$1034`, `PLA/TAY/PLA/TAX/PLA/RTI`) is patched to
  `JMP SysDliExit`. `DliExit` pops the handler's copies (X and Y are the
  interrupted code's again), runs a waiting DLI or VBI, and makes the one
  RTI.
- **The VBI** saves X before the confirming spin, since the spin uses X.
  It gives X back if the NMI turns out to be a DLI, and saves Y once the
  VBI is confirmed.
- **`DliDefault`** now pushes A, X and Y and leaves through `DliExit`.
- **The bank switch stays:** the DLI handler reads the scene page
  (`$90xx`, from the sound code at `$7546-$75B7`;
  `probes/p7800-dlireads.lua`).
- Scene 1: 3,816 → **3,567**. Story: 3,679 → 3,441.

**Result:** scene 1's NMI went from 4,860 to 3,567 cycles a frame (−27%).
The main program's share went from 16,660 to 18,008 (+8%). The game is
CPU-bound (it waits about 2% of a frame), so new pictures come about that
much sooner.

**Room in the fixed bank.** The system block now also takes pieces placed
in free gaps: each `;;; FAR` piece in `sys7800.asm` is assembled on its own
(RowBase, ReadStick).
- The build assembles in two passes: first the main block with placeholder
  far addresses, then each piece against the main block's labels, then the
  main block again. Every reference between them is an absolute address
  above `$E000`, so nothing changes size, and the build checks that.
- **A bug caught on the way:** the free-space searches ran up to `$FFF8`,
  across the NTSC signature (`$FF80-$FFF7`), which the signer writes after
  everything is placed. A far piece briefly landed at `$FF76`. All searches
  now stop at `SIG_START` (`$FF80`). The kept build had nothing above
  `$FE53`.

**Checked:**
- scenes 1-4 byte for byte (`port/regress.sh`);
- attract loop, 15,000 frames, no fault and no blank frames beyond
  power-on;
- no blitter write past either buffer;
- six DLIs and one VBI a frame. The only drops are the one long VBI at the
  story-to-cutscene change (it builds the new scene's lists and overruns a
  frame), the same in the kept build.
- **Colour timing** (`probes/p7800-palline.lua`, lines from emulated time;
  this MAME's Lua has no scanline call):
  - the middle band's colours change on the same line as before;
  - the low band's, the health arrows, one line earlier. Neither build
    reaches the handler's `STA WSYNC` on the DLI's own line, because the
    handler runs sound work first. The new dispatch (about 40 cycles to the
    handler) is closer to the XE OS's (about 20) than the old (about 100).
  - Screenshots of both builds at the same flips in scenes 1, 2 and 4 are
    pixel-identical. The hardware test is the real check here.

### The princess room: recording a 7800 session (2026-09-26)
Reported from the Pocket: the princess room seems to cause a crash.

- **Scripted, scene 4 (the finale), invincible + easy:** it got as far as
  the palace door and walked into it for 32,000 frames without a fault.
  The door and the hawk need kicks and positioning, beyond `playkey.lua`
  (the user's point), so a human recording is the way through.
- **The patch kit's new knob "start":** `start-level2`, `start-level3`
  and `start-finale` rewrite the operand of the title's game start
  (`LDA #$01 / STA $D0` at XE `$7806`, site `game-start`, bank 0 `$B807`)
  to 2, 3 or 4. The title and attract sequence are unchanged, and dying
  still returns to scene 1. Checked: a fire press at the title of a
  `start-finale` cartridge starts scene 4.
- **`Record Karateka 7800.bat` / `Play Karateka 7800 Recording.bat`:** the
  first makes the cartridge with the kit (`K78_WITH`, default
  `start-finale,invincible`), keeps it as `inp\NAME.a78` beside
  `inp\NAME.inp` (both git-ignored) and records in a window. The second
  plays a recording back on its own cartridge.
- **Next:** the user's recording, replayed under the crash probes.

**Correction, the same day: `start-finale` doesn't work, and it's removed.**
The user's first recording with it froze as soon as fire was pressed. A
replay (`CART=inp\princess.a78` with `EXTRA="-input_directory ../../../inp
-playback princess.inp"`; paths with a space must be relative) showed no
crash. The game runs scene 4, but the player stands in the right-hand
doorway and never moves.
- **The original does the same** with the swap: the scene 4 regression
  images show that pose at every flip.
- **The natural arrival** (`xe-01-easy.inp`, frame 24,549, snapshots via
  `probes/xe-snapplay.lua`) is different. Scene 3's handover
  (`JSR $2400`; `$0AFC=$AA`, `$0AFE=$FF` hold the flip for about 170
  frames; `$B0=8`; `$D0=4`; `JMP $2E00`) keeps scene 3's last picture up
  while scene 4 is drawn. The player then stands mid-room over the last
  guard and walks right.
- **RAM at the start of scene 4, natural against swapped**
  (`probes/xe-scenedump.lua`): dozens of zero-page and swap-buffer bytes
  differ, the player's position among them.
- **Dead end:** setting just the handover's three values (`playkey.lua
  HANDOVER=1`) still left the player in the doorway.
- **What replaces it:** `start-level2` and `start-level3` stay (both start
  cleanly), and `Record Karateka 7800.bat` now defaults to
  `start-level3,invincible`: play on through level 3 into the finale.
  Checked on the port: a start-level3 cheat cartridge plays scene 3 (the
  scripted player stays there for 40,000 frames; the doors need a real
  player).

**The crash itself (user recording `7800-02`, 738 s, start-level3 +
invincible).**
- **Replay:** scene 4 begins at frame 42,000. The player reaches the far
  door, and at 43,493 the engine at `$7000` is overwritten. The blitter
  (`$7927`) wrote `$7000`, called from scene 4's finale code
  (`$7AE4` ← `$7A19` ← `$77F3`).
- **The sprite pointer was `$16B0`,** an XEGS scene-code address: entry 24
  of the `$1D0F/$1D34` table ($16AE, past its header), whose high byte was
  never relocated. On the 7800 `$16AE` is console RAM. Its "header" gave
  width 0, and a zero width makes the row loop run 256 bytes, through the
  end of buffer A into the engine.
- **Why unrelocated:** the census playthrough freed Mariko one way. The
  finale's frame tables (`$7DDF`, `$7E22`, `$7EA3`, `$7F0F`, `$7F82` in
  scene data, `$1D34` in scene code) were relocated only for the entries
  that run drew. The `probes/scanhi.py` report of 2026-09-25 had listed
  them as open.

**Fixed:**
- `MANUAL_TABLES` relocates the six tables whole. A new region "auto"
  relocates each entry by the region its target is in; art entries
  (`$8000`) don't move.
- **Two finale frames the blitter couldn't reach:**
  - `$1CEE` (5×2): the `$1C80` fixed-bank copy now runs to `$1CF9`;
  - `$1F29` (43×4): the art bank at `$BB29`, page `$BB` marked in scene
    4's page map. Its fixed-bank slot holds the TIA tables.
- **A second, older fault:** the shared fixed-bank copy of `$1600-$18A1`
  (scenes 2, 3 and 4) is scene 2's bytes. From `$16FE` on, scene 4's
  differ (its own finale frames). The build let that pass ("the same where
  read"), which was only as good as the census's reading, so frames like
  `$1772` and `$181E` drew scene 2's bytes. Now:
  - scene 4 has its own copy of `$16FE-$18A1` in the art bank
    (`$BCFE-$BEA1`, pages `$BC-$BE`, not drawn from in scene 4's own data);
  - the build refuses any shared copy whose scenes differ anywhere in it.
    Only this one group did.
- **Checked:** `probes/checktables.py` follows every entry of the seven
  tables through the cartridge the way the blitter reads. All 125 real
  sprites read identically to the original's; 46 entries are art or not
  sprites (absurd headers: never drawn). Scenes 1-4 are still byte for
  byte.

**Replaying on a rebuilt cartridge doesn't work.** The two replays differ
from frame 20: the BIOS's signature check takes a different time for a
different cartridge, so the game starts at another moment and the recorded
inputs miss. So recordings are tied to their cartridge.
`probes/p7800-inputlog.lua` carries one across instead:
- MODE=log, on the old cartridge under playback: saves a state at SAVEAT
  and logs every SWCHA/SWCHB/INPT4/5 read per frame after it;
- MODE=feed, on the new cartridge started from that state: answers those
  reads frame by frame.
The code addresses are the same in both builds; only scene 4's tables and
the copies moved.

**Verified with the hand-off.**
- **Setup:** state saved at frame 43,000 of `7800-02` on its own cartridge,
  and the reads that followed logged. Starting MAME with `-state` never ran
  a frame here, so `M:load()` from Lua at the second frame does it.
- **Old cartridge + logged inputs:** the blitter's stray write at frame
  494 after the state, which is 43,494, the recording's own crash. So the
  hand-off is faithful.
- **Fixed cartridge + the same inputs:** no stray write through 1,500
  frames. The fight in Akuma's hall ends, the player goes through the door
  and walks through the next room towards Mariko at the far door.
- **Still open:** the rest of the finale (Mariko, the epilogue, a restart)
  needs a new recording on a new cartridge. The other partly relocated
  tables `scanhi.py` lists (scene 1 `$7623/$7C17`, scene 2 `$7117`, scene
  6, scene 4's text table `$6323`) are still unchecked.

### The other half-relocated tables: can anything reach them? (2026-09-26)
The user asked for the conditions that would read the unrelocated entries,
before fixing anything. (Their own test: level 2's enemies left to spawn
indefinitely, no crash, so not the enemy heads.) New helper:
`probes/callers.py SCENE ADDR` (every JSR/JMP to an address, with the code
before it). Every site `scanhi.py` still flags, read from its code:

- **Scene 1 `$7623`** (`$7683`, via the vector `$7600`, from `$7B95`):
  32-entry tables `$7603/$7623` (column `$7643`, row `$7663`). It draws
  entries X+1 and X+2 with X = `$99`. `$99` is set to 11 when the scene
  starts (`$77D1`), stepped by 2 each frame (`$7A86`) and cleared at 23 or
  more (`$7A4D`). So only entries 12-23 are ever read, exactly the
  relocated ones. (A "`STY $99`" at bank 15 `$B83D` is table data.)
  **Unreachable.**
- **Scene 1 `$7C17`** (`$7C4A`, 17 entries): called with fixed X = 0, 1-7,
  10-16. The unrelocated entries are 8 and 9. **Unreachable.**
- **Scene 1 `$71C3`, `$6E0C`; scene 2 `$7117`, `$7DDC`; scene 3 `$6AA8`:**
  complete tables (5, 18, 11, 6 and 15 entries). The flagged bytes are the
  next tables, which the scan over-reads.
- **Scene 2 `$B097` and `$BCDE`** (bank 15): not tables at all; those
  bytes are 6502 code, the same in every scene. They are read only from
  `$70B7` and `$7CB4`, stale copies of the real routines at `$7137` and
  `$7DB4`. Neither was ever executed or has a caller. **Dead code.**
- **Scenes 2 and 3, `$21BC`** (`LDX #$0F / STX $E6`): never executed, and
  the bytes around it store into ROM and jump into data. **Dead.**
- **Scene 4 `$6323`** (the epilogue's line table, `$6203`, live): its one
  unrelocated entry is line 10 (`$6315`, an empty line and end marker).
  The loop at `$6334` draws X = 0-9 (`CPX #$0A`). **Unreachable.**
- **Scene 6**: unrelocated copies of scene 1's routines (`$6C57`, `$71C3`,
  `$7623`, `$7C17`). Scene 6 is the 41-frame lead-in, and it clears `$99`
  to 0, so `$7683` doesn't run. None of its table entries was relocated by
  the census, which means none of those routines ran there. **Unreachable
  as long as the lead-in stays a lead-in.**

Result: no remaining flagged table can be read past its relocated part on
any path in the code.

**The console's Select at the title** leads to scene 6. **Correction, the
same day:** I first read the run log's "scene 5" as scene 5. That column
is the bank in use, and scene 6 lives in bank 5. `$D0` goes 6, then 1
(below). "The keyboard comes out" was right.
- It's a fight at the gate with two fighters in stance, the right-hand one
  apparently on joystick 2.
- `probes/p7800-select.lua` presses Select by answering SWCHB reads.
  6,000 frames idle and 15,000 frames with the scripted player fighting on
  joystick 1: no crash, no stray blitter write.
- **Not yet compared** with the original: scene 5 against MAME's `xegs`,
  and joystick 2.

### Select, scene 6: a whole mode the census filed under scene 1 (2026-09-26)
The user recorded the Select mode in MAME (`7800-03`): the scene stays put
at the gate in the first level, and winning behaves normally. The replay
was clean: 5,856 frames, no stray writes. The original does the same with
OPTION (`probes/xe-option.lua`, which answers its CONSOL reads): the same
fight, with `$D0 = 1`.

**Correction to "can anything reach them?":** scene 6 isn't a 41-frame
lead-in.
- Bank 15's console handler (`$AF66`): START → scene 1; SELECT → pause;
  OPTION from the title (`$7FE7` = 0) → `$D0 = 6`.
- Scene 6 sets up the fight, then writes `$D0 = 1` (`$B71B` on the 7800,
  frame 44 after the press) **without reloading**. It plays on in its own
  banks (bank 5 on the 7800).
- The census keys what it sees by `$D0`, so it filed scene 6's fight under
  scene 1. In scene 6 that code looked like never-run data, and the build
  copied it raw.

**Measured** (`probes/twindiff.py`: where scene 6 holds scene 1's original
bytes, its built bank should hold scene 1's built bytes): 245 bytes
differed. They were raw zero-page operands (`STA $03`, which on the 7800
is a TIA register), unrelocated pointers, and the flags at
`$7096`/`$7097`. Scene 6 had no carve for those, so a write went to
`$B096`/`$B097`: a bank switch, as with `$6009` in the story. That the
scripted and recorded fights didn't crash was luck of the paths they took.

**Fix:**
- **`xesource.py` `TWIN_OF = {6: 1, 0: 1}`:** a scene with a twin also
  takes the twin's executed and static code map wherever it holds the same
  instruction (same opcode and operands; a JSR/JMP target may differ).
- **`reloclist.py`:** scene 1's relocations are applied to scenes 0 and 6
  wherever the bytes around them agree (the scene 0 rule, generalised).
- **`CARVE_SDATA[6]`:** `$7096-$7097` and the death sprites, as scene 1.
- **Result:** scene 6 differs from scene 1's build in one byte, at `$79EF`,
  inside dead code (scene 6's own version jumps away just before it).
  Scene 0's four remaining hits are coincidences (different instructions
  that share one byte value).
- **The zero-page map moved:** usage now counts scene 6's code, so
  operands changed in every bank. That's consistent, and checked.

**Checked:**
- scenes 1-4 byte for byte;
- the title and story as before (3 bytes per buffer at flips 40-120, the
  same in the previous build: the original's garbage-dot bug, which the
  port fixes);
- attract loop 15,000 frames and Select-mode scripted fight 15,000 frames,
  no stray writes;
- the kit rebuilt.

### The silent Akuma fight (2026-09-26)
The user's recording `7800-04` (761 s) reaches the good ending: the
princess room and the epilogue now run. But the Akuma fight was silent,
and sound came back once he fell.

**Measured** (`probes/soundlog.lua`: per frame, the game's POKEY
registers as written, via the port's shadow `$1E17` or the original's
registers, and the TIA): through the whole fight (frames 36,000-40,400)
the game wrote no audible POKEY setting at all. The TIA faithfully played
nothing.
- **Not the console speaker.** `probes/writecount.lua` on CONSOL: on both
  machines only `$08` from `$AFD1`. The XE's ~70,000 writes per 200 frames
  at the ending are the same routine polling for a key. (Correction to the
  step 2 note, above.)
- **The cause, the tune table** at `$2422`/`$25C0`: 29 interleaved pointers
  (low, high), `$FFFF` after. The census heard tunes 0, 12 and 17-28. The
  high bytes of 1-11 and 13-16 stayed XEGS engine addresses (`$25FC`,
  `$2606`, `$260E`, `$2618`, `$261E`). On the 7800 those are console RAM in
  the middle of DLL_B, so those tunes played display-list bytes as notes:
  silence.
- **The tune table fix was real but not this fight's fix.** `MANUAL_TABLES`
  takes a stride: `("*", 0x25C0, 0x25C1, 29, "auto", 2)` relocates the whole
  table (now `$75F8-$764A` in the engine's RAM copy). The table has 28 tunes;
  the 29th "entry" is tune 0's first list word (`$2000`), also a pointer, so
  relocating it is right anyway.

**Correction: the first verification tested the wrong fight.** The hand-off
(a state saved at frame 36,000 of `7800-04`, loaded onto the fixed cartridge,
with `p7800-inputlog.lua`'s `PATCH` writing the table's high bytes) reported
sound in "the fight": 0 blocks before, 166, 33, 33 ... after. It wasn't
Akuma. The fixed build's zero-page map differed from the state's, so the
game restarted at level 1 and the sound was a level 1 fight
(`akuma-fight-MAME.wav` too). The user saw the fight still silent on MAME
and on the Pocket, and their timeline (bird, door, boss music, two bumps and
the kick, then silence until the joyous prelude) exposed it. A hand-off is
only valid between builds with the same code addresses and zero-page map.

**The real cause: the music data below the table.** The format, from the
driver (`$2422` starts a tune, `$2441` reads its list, `$24E3` steps each
frame, `$2505` plays a note, `$259D` loads a header; `$258D` swaps zero page
`$00-$07` with `$3000-$3007`, the sequencer's own copy):
- tune table `$25C0` (28 words) → a **tune list**: words, each a pattern
  reference, or `$xxFF` end (`$24D7` stops), or 4-byte `$xxFE lo hi`
  (frame wait into `$0AFC/$0AFD`) and `$xxFD lo hi` (delay into
  `$0F15/$0F16`);
- a **pattern reference** (a word: the stream, `$2451` → `$00/$01`);
- the **stream**: its first word points at its **header** (tempo `$240B`,
  voice settings, `$259D` → `$02/$03`), then notes of 3 bytes (length,
  voice 1, voice 2: `$2300` table offsets, 0 rest, `$FF` hold), `$FE n`
  (header index `$240A`), `$FF` (next list entry, `$248C`).

The pattern references at `$2000-$2009` and the streams are scene code
(`$1203-$2300`), different in every scene; the lists are in the shared
engine. The census relocated only what its runs played. Akuma's music is
tunes 13-16: list `$261E` → `$2000` → (scene 4) `$200A` → header `$20C0`.
None of those three pointers was relocated, so on the 7800 the sequencer
read `$2000` (console RAM) as the reference, and from there garbage: tempo 0
(`$2420` counting down from 256), note lengths like `$F2`, and voices held
at silence. The sequencer owns the voices while `$2409` is `$FF`, so the
hits' sounds were never heard either: the whole fight was silent.

**Fix:** `reloclist.music_pointers()` walks the tune data of every scene
(table → lists → references → streams → headers) and relocates each
pointer the census missed. A reference whose stream does not parse (a
valid header pointer, even voice offsets, an `$FF` end within 400 notes) is
not that scene's music and is left alone: `$2000-$2009` hold other bytes in
scenes that don't use every tune. Scene 0's streams end at `$2178`, just
before code the census executed at `$2179`. 14 new entries:
- shared lists: `$2601`, `$2603`, `$260B`, `$2613`, `$2615`, `$261F`
  (tunes 1-5, 6-7, 8 and 13-16);
- scene 4: `$2001`, `$200B` (Akuma's reference and header);
- scene 0: `$2003`, `$2005`, `$2007`, `$202A`, `$20C9`, `$211D`.

`probes/tunewalk.py SCENE` checks the linked build against the walk; it
reported 8 wrong pointers in scene 4 before the fix and none after.

**Verified on the recording's own cartridge.** `inp/7800-04mf.a78` is
`7800-04tf.a78` with only those 8 bytes changed (every scene 4 pointer),
re-signed; `inp/7800-04mf.inp` is the recording, which stays in sync to the
ending. Frames with TIA sound per 500, frames 35,000-40,500 (Akuma's health
from `$14` down):
- `7800-04tf` (table fix only): 0 in every block until he falls;
- `7800-04mf`: 439, 295, 57, 76, 51, 90, 104, 85, 70, 82, 84.
The first thousand frames are near-continuous (music), the rest come in
bursts (the blows).
(`work/analysis/r4mf/akuma-mf.wav`.)

The rebuilt cartridge differs from the last one in exactly those 14 bytes.
Scenes 1-4 are still byte for byte; the kit is rebuilt.

### Resources left for enhancements (2026-09-26)
Measured on the current build.
- **ROM:** each bank's free space as the build leaves it.
- **RAM:** `probes/p7800-ramuse.lua`, writes after power-on over the
  attract loop and scripted play in scenes 1-4, read against the layout.
  "Never written" is not "free": data copied in at power-on, assigned
  variables that are rarely written, and the mirrors of page zero and the
  stack were all taken out.

**ROM** (128K; bigger boards are outside the retail layouts):

| bank | free | notes |
|---|---|---|
| fixed (`$C000-$FFFF`) | ~109 bytes, in scraps of 26 or fewer | runs whatever bank is mapped: bank 15, the system code, the display lists, the sound tables, sprite copies |
| scene banks 0-5 | ~930-970 each | 712 of it at `$9420-$96E7`; readable only while that scene's page is in, and the blitter reads `$80-$9F` from the art bank, so code or data, not sprites |
| art bank 6 | 1,878 | `$B179+951`, `$BEA2+350`, `$BBD7+295`, `$B8D8+236`; the blitter can read it (pages above `$A0` through a scene's page map) |

**Console RAM** (4K at `$1800-$27FF`), free:
- `$184E-$187F` (50);
- `$1A09-$1A7F` (119);
- `$1AA1-$1B7F` (223);
- `$1EAF-$1EFF` (81);
- `$1F78-$203F` (200);
- `$2100-$213F` (64);
- `$27B9-$27FF` (71).

That's about 808 bytes, plus `$1900-$1A08` (265) in scenes 2-4 only (the
death-sprite carve of scenes 0, 1 and 6). The stack is written down to
`$01D2` (nested interrupts), so `$0140-$01BF` or so (~128 bytes) is spare
with a margin.

**Zero page:** all 192 bytes (`$40-$FF`) are assigned; the overflow is at
`$1800-$184D`.

**Cartridge RAM** (16K at `$4000-$7FFF`), free: `$7203-$72FF` (253, between
the engine's two parts), `$57F8-$5807` (16), `$6FF0-$6FFF` (16) and
`$4008-$400F` (8).

**CPU:** a frame is 29,868 cycles.
- MARIA's DMA: 5.0-7.4K (17-25%, by how many lines show bitmap).
- The NMI: about 3.6K in play (the game's own handlers about 2.3K).
- The main program: about 18K.
- The game waits only about 2% of a frame in play. It is CPU-bound, so
  any added work slows how often it draws a new picture, about 1% per 300
  cycles a frame.
- Known savings: the empty sky zones in scene 1 (about 1,300 cycles a
  frame); more NMI trimming (the bank switch, the gate checks: a few
  hundred).

**Sound:** both TIA channels carry the game's two POKEY voices whenever
music plays; there is no free channel.

**Display:** the game uses at most 4 of MARIA's 8 palettes in a frame, and
only 160A (3 colours + background per palette). Each line is two 20-byte
objects. Another object on a line costs about 2 cycles of DMA, plus 0.74 a
byte.

### Where level 1's drawing time goes (2026-09-26)
The user suspected the cliff (left) and the arch (right).
`probes/p7800-drawprof.lua` times every call of the blitters (`$284E`,
`$2B82`, `$2B8B`), the fills (`$2CCD`, `$2D03`) and the clear (`$280F`)
from entry to return. It uses emulated time, so MARIA's DMA counts as it
does for the game, minus any NMI inside the call, and also counts the
cycles executed. Calls are keyed by sprite, and the sprites were rendered
to identify them.

Scene 1, scripted fight, 89 flips; drawing takes about 225,000 cycles a
flip (about 20,000 a frame):

| what | cycles a flip | share | calls a flip | a call (executed) |
|---|---|---|---|---|
| player's health arrows (`$FE12`, 7×1) | 35,400 | 15.7% | 11 | 3,260 (2,360) |
| rectangle fills (erasing) | 23,100 | 10.3% | 4 | 5,480 (3,680) |
| foe's health arrows (`$FE1C`, 7×1) | 20,800 | 9.3% | 8 | 2,700 (1,920) |
| fence rail piece (`$AB8E`, 1×4) | 20,100 | 8.9% | 14 | 1,420 (1,030) |
| the cliff (`$AA7D`, 29×6) | 13,800 | 6.1% | 0.8 | 17,560 (12,650) |
| striped floor (pattern fill) | 10,400 | 4.6% | 2.5 | 4,150 (2,690) |
| arch beam (`$AB94`, 4×15) | 4,900 | 2.2% | 0.8 | |

- **The health arrows are the biggest item:** a quarter of all drawing.
  Every new picture fills the status row (rows 181-188, full width) and
  redraws every arrow, and each 7-byte arrow costs about 2,000-2,400
  executed cycles (the blitter's per-row setup and pixel shift), though
  health changes only on a hit.
- **The cliff and the arch** are real but smaller: about 6% and about 3%
  (beam alone).
- **The fence rail's small pieces** add up to about 9%.

**Follow-up, the same day: blows still reported silent.** The user
reports, with a fixed build: the fight's prelude plays, then nothing until
the victory music.
- **Every current cartridge has the fixed table:** `75 75 75 75`, the
  stable build and the fork's. Every recording's cartridge made before the
  fix has `75 25 25 25`.
- **All sound goes through one routine**, the driver's per-frame copy of
  its voices into POKEY (`$70C8-$70DA`, XE `$10C8`;
  `probes/p7800-pokeywriters.lua`). Blows don't start tunes: a level 1
  fight starts only tune 26, once (`probes/p7800-tunelog.lua`).
- **MAME, the fixed build, from the `akuma` state with the recorded
  inputs:**
  - 31 blows land (health drops), 13 of them with sound within 10 frames.
    Ordinary fights in `7800-04` (level 3): 28 of 73. The same ratio.
  - Sound in 10.8% of the fight's frames, against 9.0% in level 3 fights.
  - The same TIA settings: AUDC 8, AUDF 2/5/8/3, volumes mostly 1-4.
- **Audio** (`run7800.sh` now takes `WAV=file` to record it): RMS per
  second through the fight is 600-2,800, the same as a level 3 fight.
  Files: `work/analysis/akWav/akuma.wav` and
  `work/analysis/l3Wav/level3.wav`.
- **So in MAME the fixed build plays the fight's sound.** Where the user
  heard silence (the Pocket or MAME, and whether other fights' blows were
  audible on the same setup) is the open question.

### regress.sh could compare stale dumps (2026-09-27, correction)
Found in the fork (`../karateka-enh-port/FINDINGS.md`, "The column
routine"). `regress.sh` compared whatever `fbk*.bin` its output folders
held, so a port run that died before writing them was compared using the
last run's files and passed. It now deletes the port's dumps before
running. The results recorded here came from builds whose other runs went
to completion.

## The fork's speed-ups, merged (2026-09-27)
The user tested the enhancement fork's builds on the Pocket (running their
port of the MiSTer 7800 core), found no issue, and asked for them in the
stable port. None of them changes the picture: every buffer is byte for
byte what the original draws. The details, measurements and checks are in
`../karateka-enh-port/FINDINGS.md`. In short:
- **The health bars are drawn only when they change** (a per-buffer cache
  in the scene pages at `$9420`). Every picture used to clear the status
  row and redraw every arrow, about a quarter of a fight's drawing.
- **The row address, faster:** the game's general 8×8 multiply `$2D78`
  (about 290 cycles, paid by every draw call) became a fixed × 40 (about
  60).
- **Level 1's columns:** posts and pillars drawn as loops of 1- and 2-row
  pieces (one blit call a piece, clipped away whole when off screen) go
  through a routine that draws the first and last pieces with the blitter
  and copies the rest. It lives in scenes 1 and 6's pages only (the
  build's `;;; LEVEL1PAGE`, placed in parts).
- **The fast fill:** the rectangle and pattern fills' store loops run from
  cart RAM at `$7203` (copied at every scene load), 4 rows at a time,
  column by column: 5 cycles a byte against 11.

**Level 1, scripted fight, pictures per 1,000 frames:** 89 before, 123 now
(about 38% more). The fills and the row address help every level.

**The merge:** `build7800.py`, `layout7800.py`, `link7800.py` and
`sys7800.asm` came from the fork whole. The only lines unique to this side
were ones the fork had rewritten. The probes are synced both ways; this
side kept its newer `run7800.sh` (WAV) and `soundlog.lua`. The build here
gives the fork's cartridge byte for byte, including the option cartridges
from the kit.

**Checked here:**
- `regress.sh`: 13 comparisons byte for byte, fresh dumps;
- `p7800-colcheck.lua`: 1,275 columns and 12,179 blits, 0 wrong;
- `p7800-fillcheck.lua`: 4,758 fills, 0 wrong;
- `p7800-firstover.lua`: 15,000 attract frames, no stray write.

Checkpoint before the merge: `../Karateka-Port-checkpoints/2026-09-27_KEEP_before-merge`
(the source, both cartridges, the kit), kept until this build proves
itself on hardware. The fork continues with the display rework (MARIA
drawing the fighters).

## karateka-enh: display lists by the 7800's rules (2026-09-29)
A new fork of the stable build (`Karateka-Port`, commit `20f73ef`), made
after the one-line-zone prototype was stopped (`../karateka-proto`,
FINDINGS there). It builds the stable cartridge byte for byte.

**The user's goal 1:** make the stable build follow the 7800 Software
Guide's display list rules, by moving to 8- or 16-line zones.

**The rules** (7800 Software Guide, "Display List List"):
- a display list list (DLL) may cross only one page boundary, so it is at
  most 512 bytes; so may a display list (DL);
- both must be in RAM ("due to the required access time");
- OFFSET counts down: a zone's top line reads page `high + OFFSET`, each
  line below it one page lower;
- holey DMA (odd 4K or 2K blocks read as zeros) works only for addresses
  above `$8000`.

**The stable build against them:**
- each DLL has 243 one-line entries: 729 bytes. `DLL_A` (`$2200-$24D8`)
  crosses two page boundaries, `DLL_B` (`$24E0-$27B8`) three;
- the DLs are in ROM: the row lists (10 bytes a buffer row, both buffers:
  3,060 bytes of the fixed bank), `DL_EMPTY`, the Mode8 row lists.

**Merging only the blank lines isn't enough.** Scenes 0-2 show all 153
buffer rows; with one entry a row, the Mode8 rows and the blanks merged,
the busiest list still needs about 183 entries (about 550 bytes). The
buffer rows themselves must be in multi-line zones.

**The game's lists** (every list the port uses, as runs: blanks, Mode8
rows of 8 lines, buffer rows): the six game DLIs fall at fixed lines,
e.g. scene 1's `$1908` after buffer rows 37, 78, 89, 132 and 145. MARIA
raises a DLI after the last line of the zone before the flagged entry, so
a zone must start at each of them (the port flags the run's last line).

**What multi-line zones need of the buffers:** a zone's rows one page
apart, the top row on the highest page. A row can't run past its page's
end, so a page holds six 40-byte rows (16 bytes over). Both buffers, 306
rows, need 51 pages; `$4000-$6FFF` has 48 (the engine is at `$7000`).

**The code that writes the buffers** (`p7800-fbwork.lua`, the attract
sequence and scripted play, 9,000 frames; each steps 40 bytes a row today):

| PC | what |
|---|---|
| `$9845` | the story scroll (`$0845`; moves most of the screen each flip) |
| `$7927`, `$7946` | blitter A's stores |
| `$7B12`, `$7B3E` | blitter B/C's stores |
| `$7D19`-`$7D22` | the fast fill's four-row store block |
| `$7837` | the full clear (`$280F`) |
| `$CE09` | the buffer copy (`$ADCA`) |
| `$815A` | level 1's column routine |
| `$E15F` | the reset's RAM clear |

The Mode8 expansion reads the buffers too.

**The engine's RAM** (`probes/p7800-enginewrites.lua`): in the attract
sequence, only 56 of its bytes are written after loading: the operands
the blitters and fills patch into themselves (`$7839`, `$78FA-$78FB`,
`$791D-$791E`, `$7925-$7926`, `$7ADA-$7ADB`, `$7AFF-$7B00`,
`$7B10-$7B11`, `$7CCC`, `$7D1A-$7D27`, `$7DA1-$7DA2`), a few bytes at
`$7193`, `$72B8`, `$72F8`, and the routine the game builds at `$7409`
(25 bytes). In play the loader (`$E6F3`) copies the whole engine again at
each scene's load. So most of the engine is read-only once loaded.

### Step 1: the engine's first part in the fixed bank (2026-09-29)
- `engine1` (XEGS `$1000-$1202`) is now assembled for the fixed bank at
  `$F200` (layout `ENGINE1_AT`, kind "fixed") and no longer copied to cart
  RAM at each scene's load. Its save slot `$1193-$1196` (the only bytes
  the original writes there) is carved out to console RAM `$184E`
  (`CARVE_ENGINE1`; not copied at load: the game writes it before reading).
  Cart RAM `$7000-$7202` is free.
- **Found: a move must be by whole pages.** The first try put it at
  `$F2E0`: the first display list interrupt jumped to `$F326`, the middle
  of the handler, and returned into the stack page. The game sets its DLI
  vector with separate low and high byte constants, and the relocation
  fixes only high bytes (every region so far moved by whole pages). At
  `$F200` the low bytes stay right.
- **Room for it, for now:** a development switch (`ENH_DEV1=1`) makes buffer
  B's ROM row lists the same as A's, which frees 1,530 bytes of the fixed
  bank. The display is wrong in that build (B shows A); the framebuffers
  aren't affected. Step 2 removes the ROM row lists for good.
- **Checked:** `port/regress.sh` (scenes 1-4 against the original, both
  buffers at every checkpoint): 0 bytes differ. Scene 0 (title, story,
  attract fight) ran 9,000 frames without a bad fetch
  (`probes/p7800-crashtrace.lua`).

### Step 2: multi-line zones, display lists in RAM (2026-09-29)
**Done: the build follows the display list rules.**
- DLLs in console RAM, a page each: `DLL_A` `$2200`, `DLL_B` `$2300`. The
  largest list is 51 entries (153 bytes; scene 0's `$1908`), so none
  crosses a page boundary at all.
- Display lists in RAM: each zone's list (10 bytes: the row's two 20-byte
  halves and the end) in `$2400` (buffer A) or `$2500` (B), at most 18 a
  list (180 bytes). The empty list, the three Mode8 row lists and the blank
  DLL are static: copied at boot from an image in the system block to
  `$2780`.
- The ROM row lists (3,060 bytes of the fixed bank) are gone; the system
  block now ends at `$EB74`, and 2,244 bytes of the fixed bank are free. The
  development switch of step 1 (`ENH_DEV1`) is gone with them.
- The build checks every list the port uses: at most 85 DLL entries and 25
  zone lists (`build7800.zones`, the builder's rules in Python).

**The framebuffers** (`build7800.fb_row`, `sys7800.asm` `RowAddr`): pages
`$40-$72`, six 40-byte rows a page at bytes 16-255 (bytes 0-15 are left
free; `$4000-$400F` is the cartridge's POKEY). Buffer A is columns 0-2,
B columns 3-5; a column is 51 rows, from page `$72` down. So "the next
row" is one page down, or at a column's foot (`$40`) the next column's top.
Each buffer is 120 bytes of every page, so the clear and the copy are page
loops. Cart RAM `$7000-$72FF` now holds rows; the fast fill moved to
console RAM `$2600`.

**The zone builder** (`BuildDll`, rewritten; it runs in the NMI when a
buffer's list changes):
- a line with a game DLI is a zone of its own (MARIA raises the DLI as the
  flagged zone starts, after the previous zone's last line: the same line
  as before);
- blank lines: zones of up to 16;
- buffer rows: zones of up to 16 within one column; the zone's list points
  at the bottom row's page (MARIA reads line k at page `high + OFFSET`,
  OFFSET counting down from the zone's height less one);
- the Mode8 rows stay one line a zone: each of their 8 lines repeats the
  row, and a multi-line zone reads a new page each line;
- the vertical blank stand-in (`VBI_LINE`) as before.

**What changed in the game's drawing:**

| where | was | now |
|---|---|---|
| row address (`$2D46`, `SysRowBase`) | row × 40, then `$2D56` adds the buffer | `RowAddr`, returning past `$2D56` |
| blitter A's next row (`$295F`) | `ADC #$28` | `JSR SysRowNext` |
| the mirrored blitter's (`$2B5A`) | `ADC #$28` plus the shift's odd bit | `JSR SysRowNextC` (the carry kept) |
| the fills (fast fill, `;;; RAMFILL`) | strides of 40 or 80 bytes | 1 or 2 row steps (`FpStep`); the last row from the last store, not a step back |
| the full clear (`$280F-$284D`) | linear, self-modifying | `SysClearBuf`, page by page |
| the buffer copy (`$AD83`) | `$ADC7` and `$AE05`, linear | `SysCopyBuf`, page by page |
| the story scroll (`$0830`, `$084B`) | two pointers, +40 a row | `SysRowNextS`, `SysRowNextE` |
| level 1's columns (`LEVEL1PAGE`) | a piece's second row at Y + 40, the next piece +80 | explicit row steps, the piece's first row kept |
| Mode8's source | the buffer's first 30 bytes | row 0's first 30 bytes (`FBA_ROW0`/`FBB_ROW0` now row 0's address) |

The row routines use A only: the game's row address kept X and Y, and the
story scroll keeps its loop count in X. A pointer outside the buffers
(RowBase's clip row) only moves a page, so it never lands in a buffer.

**Found on the way:**
- Pieces assembled apart (the level 1 parts, the `;;; FAR` pieces) see
  equates only: they call the new routines through `J_ROWNEXT` and
  `J_ROWADDR` (the jump table's addresses).
- The build's fast-fill label filter assumed `$7203-$72FF`; it now follows
  `RAMFILL_TABLE`.

**Checked:**
- `port/regress.sh` (the dumps read row by row from the new layout,
  `probes/playkey.lua`): scenes 1-4, both buffers at every checkpoint, 0
  bytes differ from the original.
- The screen against the stable build at the same checkpoints
  (`playkey.lua SNAPS=1`, the stable run with its own symbols through
  `run7800.sh SYMFILE`/`ZPFILE`): scene 1 (4 pictures) and scene 3 (3)
  pixel for pixel identical.
- The attract sequence by picture (`probes/p7800-snapflips.lua`, every
  10th flip, 71 pictures): the title and story identical; 11 pictures of
  the demo fight differ, all in the health arrows' colour (their flashing
  caught at another point, and in one picture only the first status line):
  the two builds reach the same picture at different frames, since this one
  runs about 2% slower (flip 710 at frame 8,978 against 8,766).
- Scene 0 ran 2,000 frames with no bad fetch.

**Still open:**
- About 2% slower in the attract sequence: the row steps are now calls.
- Whether the first status line's colour differs only with timing, or the
  new zones move the last DLI's colour change, is not settled.
- Not yet run on hardware.

### Late colours: a flickering floor line (2026-09-29)
Reported from hardware on the zone build: "a flickering row of pixels
during the intro animation in the lower right, just below the floor line in
the princess room in the attract mode animation. and there is a flickering
line in the floor during the animation with Akuma after the first level."

**Reproduced in MAME, and in the stable build too** (so not the zones):
`probes/p7800-snaprange.lua` (a snapshot every frame) through the princess
room, and a flicker finder (pixels that go A, B, A): screen line 189,
x 280-317, grey for one frame in every four, on both builds; the original
(XEGS, `probes/xe-snapevery.lua`) shows nothing of the kind.

**What it is:**
- The princess room and the Akuma hall use the lists `$1908`/`$19B3`,
  whose last buffer rows are the status bar's (rows 146-152). The floor's
  far end reaches into row 146, and the game hides it there with the status
  bar's colours: black.
- The colours come from the game's DLI handler (`$1026`, engine1), which
  works by its count in the frame (`$1A9A`): the third and sixth DLIs set the
  colours (`$F2F4`: `$25-$28` from a table; the sixth's are the status bar's,
  all black), the other four run the music driver, alternating a short and
  a long path (up to about 11 lines in MAME on a note's tick).
- The port runs one DLI at a time (the game's handlers share save bytes;
  a DLI inside a DLI once sent the blitter into the engine), so a DLI that
  arrives during another waits for it. In scene 0's lists the fifth DLI (a
  music one) is 3 lines above the sixth; in the others, 13. On a long tick
  the sixth waited until the fifth was done, and its black landed after row
  146's line had started: the floor's pixels showed in grey.
- Measured (`probes/p7800-nmitime.lua`, `probes/p7800-colwrites.lua`;
  lines estimated from emulated time, as this MAME's screen has no `vpos`):
  normal frames, the fifth handler 4 lines, the colours 5 lines after it;
  the flicker frames, the fifth 11 lines, the colours 7 lines later.
- On the XEGS a DLI interrupts a DLI (the 6502 takes an NMI inside an NMI),
  so the colours come on time there.

**The fix** (`build7800.space_dlis`): the music DLIs change nothing on
screen, so the build moves any music DLI closer than `DLI_GAP` (28) lines
above a colour DLI up to 28 lines above it, or just below the DLI before
it (the run is split there). Every list keeps its six DLIs in the same order,
and the colour DLIs stay on the game's lines. In practice the fifth DLI
moves to line 165 in every list (from 190 in scene 0's, 180 in the
others); the second moves up one line in scene 2's and 3's lists. The music
driver's timing within the frame moves by at most 25 lines (about 1.6 ms).
`NO_DLI_SPACE=1` builds without it, for comparison.

**Checked:** the princess room, 1,301 frames: no flicker at all (it was
line 189 every fourth frame). The Akuma cutscene doesn't flicker in MAME
with or without the fix (13 lines were enough there in MAME, evidently not
on hardware); 28 lines leave the handler more than twice MAME's longest.

**Also for the stable build:** it has the same fault (measured above). The
fix is the same few lines in `build7800.py`.

### Dots on the floor in the Akuma hall (2026-09-29)
Reported from hardware with a screenshot: "a series of dots on the floor in
front of the door that blink seems to blink mostly during akuma animation."

**Reproduced in MAME, the zone build only** (the stable build's same run:
none). Screen line 168, x 250-271: orange and white dots (Akuma's colours)
on and off over stretches of frames, so the one-frame flicker finder missed
it; a crop of the floor every 15 frames showed it. Buffer B's row 129 had
`13 13 11` at bytes 31-33 (A's row 129 didn't): in the zone layout those
bytes are `$57F7-$57F9`.

**Cause: a game record in the old gap between the buffers.** The game keeps
a 16-byte record at XEGS `$47F7-$4806` (bank 15's unrolled copies at `$BA73`
and `$BA7E`, zero page `$70-$7F` to and from it; they run in the Akuma
cutscene, which no census run reached, so the census has no writes there).
Its first byte is buffer B's last row's last byte; the other 15 are the gap
between the buffers. The linker placed the buffers' bytes by the old
straight mapping (`fbB` `$3000` → `$4000`), so the record went to
`$57F7-$5806`, which in the zone layout is B's column 5 on page `$57`: row
129's last 9 bytes.

**Fix: the linker maps buffer addresses by the new layout**
(`layout7800.fb_home`): a row byte goes where that row now is; the gaps the
game uses go to free bytes (`XE_GAPS`: `$3000-$300F` stays at `$4000` as
before; `$47F8-$4807` to `$4100`, right after `$40FF`, B row 152 byte 39,
so the record stays in one piece; `$5FF0-$5FFF` to `$4200`).
- **Split addresses into the buffers** (a low and a high byte relocated
  apart) can't follow a layout that isn't one block. The linker now lists
  them (`link7800.FB_RELOCS`): 8 places in each scene, all in code that no
  longer runs (the game's buffer base after `$2D46`, `$2D66` and `$2D74`,
  skipped by RowBase; the old buffer copy's setup, `$AD97-$ADC6`, replaced by
  `SysCopyBuf`). The build stops if any other appears.

**Checked:** the Akuma cutscene (the invincible, one-hit cartridge, the
scripted player, frames 4,250-4,660): no coloured pixels on the floor in
front of the door in any of its 379 hall frames (before: several stretches).
- Regression (scenes 1-4, both buffers, every checkpoint): 0 bytes differ;
  scene 0, 9,000 frames: no bad fetch.

**Test cartridge:** `python port/kitopt.py invincible easy -o
work/karateka7800-invincible-easy.a78` (the kit's options on this build, as
`protoopt.py` did for the prototype): the player can't lose, one hit
finishes any foe.

### Performance against the stable build (2026-09-29)
**Picture rate** (`probes/p7800-fliptimes.lua`: the frame of every buffer
flip, the regression's scripted player, inputs keyed to pictures so both
builds play the same game), pictures 300 to 800:

| scene | stable, frames | zones, frames | zones against stable |
|---|---|---|---|
| 1 | 6,550 | 6,770 | 3.4% slower |
| 2 | 6,403 | 6,588 | 2.9% slower |
| 3 | 6,045 | 6,198 | 2.5% slower |
| 4 | 3,500 | 3,500 | the same (paced by the game's waits) |

The first 100 pictures come sooner (1,759 frames against 1,786: the
engine's first part is no longer copied at each load). The attract
sequence: 2.4% slower.

**Why** (`probes/p7800-cycles.lua`, scene 1, pictures 300-800, executed
cycles by the 6502's table):

| | stable | zones |
|---|---|---|
| CPU cycles a frame (what MARIA's DMA leaves) | 21,569 | 21,973 (+1.9%) |
| cycles a picture | 282,565 | 297,515 (+5.3%) |
| of which: the row steps (`RowNext` and the rest) | — | 11,024 |
| the fast fill | 6,285 | 10,257 |
| the blitters (engine2) | 141,393 | 136,104 (their inline steps gone) |
| RowBase | 1,850 | 2,398 |
| the list builder | 686 | 262 |

- **The zones save DMA:** MARIA reads a DLL entry per zone instead of per
  line, so the CPU gets 1.9% more of each frame.
- **The row steps cost more than that:** the game's step was 13 cycles
  inline (`LDA/CLC/ADC #$28/STA/BCC`); now it is a call, about 25 (JSR,
  DEC, the column-foot test, RTS), and the fast fill steps each row through
  `FpStep` (a JSR and a loop). Net about 15,000 cycles a picture more,
  3.3% slower.

**What would win it back:** the common case of a row step is only "one
page down, unless that was the column's foot":
- in blitter A's step (11 bytes free): `DEC $15 / LDA $15 / CMP #$3F / BNE
  / JSR wrap`, 13 cycles like the original, the call only at a column's foot
  (1 row in 51);
- the fast fill: the step inline in its patch blocks, and the pattern fill's
  two-row step as two such steps;
- the mirrored blitter (10 bytes: its step adds the shift's odd bit), the
  story scroll: calls kept or folded likewise.
Estimated: the row steps from 11,000 to about 2,000 cycles a picture and
the fill back near 6,300, which with the DMA saving would put the zone
build about 1% ahead of the stable one.

### The row steps made fast (2026-09-29)
Known-good checkpoint first: `../Karateka-Port-checkpoints/
2026-09-29_KEEP_enh-goal1-zones` (source, cartridges, symbols).

**What changed:**
- **Blitter A's step** (`$295F`, 11 bytes): `DEC $15 / LDA $15 / CMP #$3F /
  BNE / JSR SysRowWrap`, inline: 12 cycles in the common case (the game's
  `ADC #$28` was 13), the call only at a column's foot (1 row in 51).
- **The mirrored blitter's** (`$2B5A`, 10 bytes: too few for the inline
  step and its shift's odd byte): still a call, but `RowNextC` now goes
  straight to `RowNext` when the carry is clear, and adds the byte with
  `INC` otherwise (no `PHP`/`PLP`).
- **The story scroll's** (`$084B`, 23 bytes): both pointers' steps inline
  (`SysRowWrapE0`, `SysRowWrapE2` at a column's foot).
- **The fast fill:** two patch sequences, rows one apart (the rectangle)
  and two apart (the pattern), with the step inline instead of `FpStep`'s
  counted loop; `FpSeq` picks the sequence. The patch code moved to just
  after the jump table so it stays in one page (`FpPatchLo` holds low
  bytes). 353 bytes at `$2600`.

**Result** (the regression's scripted player, pictures 300-800):

| | stable | zones, first | zones, fast steps |
|---|---|---|---|
| scene 1 | 6,550 frames | 6,770 | 6,522 (0.4% faster than stable) |
| scene 2 | 6,403 | 6,588 | 6,324 (1.2% faster) |
| scene 3 | 6,045 | 6,198 | 5,976 (1.2% faster) |
| scene 4 | 3,500 | 3,500 | 3,500 |
| attract, picture 710 | frame 8,765 | 8,978 | 8,593 (2.0% faster) |

Scene 1, cycles a picture: 286,304 (stable 282,565, the first zone build
297,515); the row routines 5,876 (were 11,024), the fast fill 7,347 (were
10,257; stable 6,285); the CPU gets 21,949 cycles a frame (stable
21,569), so a picture takes fewer frames than on the stable build.

**Scene 4 always 7 frames a picture:** not a wait the game sets (its
picture hold at `$1A86`, the one scene hand-overs use, is never written
there). A finished picture is shown at the next vertical blank, so a
picture takes whole frames; in the scripted run (the player standing in
the doorway) each takes between 6 and 7 frames' work on either build, so
both round to 7: about 8.6 pictures a second, against 4.4-4.8 in scenes
1-3, where pictures take 4 to 17 frames (7 the most common, 13-14 the mean).
The zone build has 3.1% more CPU a frame there (24,435 cycles against
23,701), which the rounding hides.

**Checked:** the regression, 0 bytes differ at all 13 checkpoints; scene 0,
9,000 frames, and the invincible/easy cartridge, 6,000 frames of play, no
bad fetch.

### Stray pixels by a fallen guard: an image read as code (2026-09-30)
The user's report, with a recording on the invincible/easy cartridge
(`test-karateka7800-invincible-easy-0929-2309.inp`, copied with its cart
to `inp/`): stray pixels near a body that dropped, when chapter 3's third
guard is defeated.

- **Where:** frame 12,140 of the recording, the guard in the hat lying
  under the right-hand door: an orange and a white pixel past his head on
  the last row, and the row above it wrong at the same end (buffer rows
  126-127, bytes 25-26). Steady, not a flicker: the same bytes in both
  buffers, every picture he lies there.
- **Not a stray write.** `probes/p7800-fbwatch.lua` (every framebuffer
  writer by PC over the whole recording) and `probes/p7800-fbstray.lua`
  (the same writers' writes anywhere else: none, once the reset's RAM
  clear and stack pushes are left out) found nothing out of place;
  `probes/p7800-boxwrites.lua` showed the fill clearing both bytes every
  picture and the blitter (`$7B12`, engine2 = XEGS `$2B12`) writing them
  back; `probes/p7800-blitsetup.lua` put it in the second of the body's three
  blits: a mirrored 3-byte by 9-row image from `$BFC5` (XEGS scene 3
  data `$7FC5`), rows 119-127.
- **The image in the cartridge is wrong** (`probes/p7800-peekat.lua` with
  `SRC=BFC5`): its last two rows are `A8 60 CE C6 00 CE`, the original's
  `00 33 CE 00 00 CE`. The original's snapshot of the same pose
  (`xe-01-easy.inp`, frame ~13,080, `probes/xe-snapplay.lua`) matches the
  port pixel for pixel but for those two rows.
- **Cause: the static trace read the image as code.** `xesource.ENTRIES`
  has the dispatch chain `$7FD9` as an entry for every scene, and the fixed
  bank's `JSR $7FD9` (`$BC5A`) leads there too, but only scene 0's data
  bank (11) holds that routine (`$7FD9-$7FE6`: save X and Y, `JSR $AF66`,
  restore, `JMP $780D`). The other data banks hold image bytes there; scene
  3's decode as `INC $3300 / DEC $0000 / ...`, and the linker relocated the
  "operands": `$3300`, a framebuffer address, through `fb_home` to `$60A8`
  (the `A8 60`), and `$0000` through the zero-page map to `$00C6`. (Scenes
  1, 2 and 6 decode to illegal opcodes there, which the trace drops; scene
  4's to `AND #$27`, nothing to relocate.)
- **The stable build has it too, smaller:** its bytes are `00 43 CE C6 00
  CE` (`$3300` moved to `$4300` with the old buffer base), so one pixel
  pair was wrong there; enh's framebuffer mapping made it two rows.
- **Fix:** `xesource.static_code` drops the trace's claims on
  `$7FD9-$7FE6` in a scene whose data bank doesn't hold scene 0's bytes
  there. The build then differs from the last in exactly the three bytes,
  and the image is the original's.

**The same kind of mistake, searched for.** `probes/staticonly.py` lists
every byte the linker changes inside an instruction only the static trace
claims (never run in that scene) and whether another scene ran that
address, with the same bytes or other ones; `probes/deadfall.py` lists the
trace's code reached only by falling through a branch that always branches
(`LDX #$1D / BPL`), with nothing jumping there. Of the latter, one more is
data: **scene 4 `$1F00`**, after `LDX #$1D / BPL` at `$1EFC`, is the first
bytes of a finale sprite read as `ORA $1403 / BRK`; its "operand" moved
`$1F02` from `$14` to `$F7`. `xesource.NOT_CODE = {4: [(0x1F00,
0x1F04)]}` keeps it data (one byte back to the original's). The other
fall-throughs (`$0A0C`: `JSR $B603 / JMP $AE78` in every scene; scene 0
`$7837`: `JSR $0862 / LDX #`) read as real code and are left alone. The
census's read map (`.rd`) doesn't tell data from code: it has instruction
fetches too, so every executed byte is "read".
- **Dead end:** "ran in another scene with other bytes" doesn't mark data
  either: the scenes hold different code at the same addresses (the
  scene code and data banks), so `staticonly.py` lists hundreds of those.
- `probes/scanwrites.py` missed every `STA.w` form (its pattern had no
  `.w`), which is why its scan of engine1 found no writes; fixed, it finds
  `$1193-$1196` only, the bytes carved to RAM. The live watch
  (`p7800-fbwatch.lua`, the ROM copy `$F200-$F402`) saw no write either.

**Checked:** the regression, 0 bytes differ at all 13 checkpoints; the
user's recording replayed on the fixed invincible/easy cartridge (4 bytes
different from the recording's) stays in sync to the ending, and the guard
matches the original.

### Princess music with Akuma's: not reproduced (2026-09-30)
The user's report: in the last fight the princess music plays at the same
time as Akuma's. On MAME, the same recording:
- **One tune at a time.** `probes/p7800-tunelog.lua`: tune 23 (f14,621),
  17 on entering Akuma's hall (f15,181), 16 as Akuma comes on (f15,709,
  from scene 4's `$7B84`: `$39` reaching `$18`), 18 when he falls, 19 the
  princess, 20 the ending. `probes/p7800-seqlog.lua` (the sequencer's
  context, XEGS `$3000-$3007` at `$4000`): tune 17 ends at f15,515, before
  16 starts, and the driver has one sequencer: a new tune replaces the
  last (the port's `Sound` keeps that: swap in, set up, swap out).
- **The same as before enh:** the stable-era recording `7800-04mf` plays
  17, then 16 (f35,057-35,757), then 18. The original's `xe-01-easy`
  run never shows Akuma fighting (easy mode's instant-death block), so it
  plays 23, 17, 18, 19, 20 without 16 (`probes/xe-tunelog.lua`).
- **The music data is the original's:** scene 4's streams `$2000-$21FF`
  differ from the original only in the relocated header pointers, the same
  in enh, stable and the recording's cartridge; `tunewalk.py`: 70 pointers,
  0 wrong. Nothing writes engine1's ROM copy (so no lost music state).
- **The driver runs at the original's rate:** `probes/p7800-pccount.lua`,
  per frame: the step (`$24E3`) 2 and 3 times alternately, the voice copy 4
  and 6, on the original, enh and stable alike; in the fight 7 NMIs and 6
  DLIs every frame, none dropped.
- **One writer of the TIA's sound registers,** `TiaSound`, once a frame
  (`probes/p7800-tiawrites.lua`), following tune 16's two voices.
- **How the TIA renders tune 16** (`probes/p7800-voicelog.lua`, octaves
  ignored): notes within about ±25 cents but for some bass notes (152 Hz
  -88, 136 Hz +112, 108 Hz +77 cents: the TIA's tones are sparse that low),
  so 5 of the 28 note pairs have their interval off by 70-110 cents. That
  is the conversion rule's (shared with stable), not a second tune.

Not yet explained: what the user heard. The fight was silent before the
music-pointer fix (above, "The silent Akuma fight"), so tune 16 may be new
to the user's ears; open until the user says where in the fight and on
what (MAME, hardware, the Pocket) it happens.

**Where the user hears it:** from the moment the player enters the
princess's room and Akuma pushes him back into his hall. That is tune 16's
start (f15,709 in the recording): the tune the pointer bug silenced, heard
for the first time since the fix (the user has reached it once). So the
report is most likely tune 16 itself, not a second tune. To judge it by
ear: `probes/p7800-shadowlog.lua` logs the POKEY shadow (what the original's
driver writes) in `xe-pokey.log` form, and `port/sndconv.py` renders it as
the original's POKEY (`work/analysis/rec-shadow/orig.wav`) and as the
port's TIA (`tia+0.wav`, `SND_OFFSET` 0): frames 15,100-16,420, tune 17 at
1.4-6.9 s, tune 16 from 10.2 s.

## karateka-enh merged: the display lists by the rules in the stable port (2026-09-30)
The user called goal 1 finished (display lists by the 7800's rules: the
DLL and every DL in RAM, at most 512 bytes and one page crossing, 8/16-line
zones, the static lists copied from ROM, engine1 in the fixed bank) and
asked for it in the stable port, as the foundation for drawing with MARIA
objects instead of a framebuffer (zones hold objects over many lines, so
nothing has to be declared line by line).

**The merge:** the stable side had not changed since the fork was copied
from it (every file here dated 2026-09-27 or earlier), so the fork's
`port/` (`build7800.py`, `layout7800.py`, `link7800.py`, `sys7800.asm`,
`xesource.py`, `run7800.sh`, the new `kitopt.py`), its new and changed
probes and this file came over whole, in this side's CRLF. One name
clash: the fork had written a new probe over `p7800-blitlog.lua` (the
draw-call log); the fork's is now `p7800-blitsetup.lua` and the old one is
back on both sides.

**Checked here:**
- the build gives the fork's cartridge and symbol file byte for byte;
- `regress.sh`: 13 comparisons byte for byte, fresh dumps;
- the kit (`mkkit.py`) rebuilds the cartridge and every option set, and
  its `make.py` run on `../karateka/Karateka.car` gives the same carts as
  `kitopt.py` (base; invincible, easy; start-level3, invincible);
- the option cartridges in `work/` rebuilt: invincible, invincible-easy,
  level3-invincible. `karateka7800-cheat.a78` was left alone: it is from
  an older build and its options aren't recorded.

Checkpoint before the merge: `../Karateka-Port-checkpoints/2026-09-30_KEEP_before-enh-merge`
(source, probes, this file, the cartridges, the kit), kept until this build
proves itself on hardware.

### Performance against the original (2026-09-30)
The same scripted player (`playkey.lua`, `FIREFLAG=1 INJECT=1`, scenes
2-4 by `SCENE`) on the XEGS, the stable cart before the merge (the
checkpoint) and the merged build; pictures counted the same way on both
machines (calls of the flip and wait, `$0862`/`$B60F`), `playkey.lua` now
logging each counted flip's frame. Frames from picture 300 to 800
(`work/analysis/perf.sh`; the regression shows the same pictures on all
three, so the same play):

| Scene | XEGS (MAME) | stable before | merged | merged vs MAME's XEGS |
|---|---|---|---|---|
| 1 | 5,834 | 6,613 | 6,573 | 12.7% slower (4.6 pictures a second against 5.1) |
| 2 | 5,716 | 6,414 | 6,336 | 10.8% slower |
| 3 | 5,498 | 6,087 | 6,019 | 9.5% slower |
| 4 | 3,500 | 3,500 | 3,500 | the same (7 frames a picture) |

(Scenes 2 and 3's scripted player dies before picture 800, so their
windows end in scene 1, alike on all three.)

**Why, scene 1** (`p7800-cycles.lua` over the same window): the port does
less work a picture, about 288,600 executed cycles against the original's
318,100 (9% less: the health cache, row address, column routine and fast
fill), but its CPU gets about 21,950 cycles a frame against the XEGS's
27,270: MARIA's DMA (the display lists and 40 bytes of graphics a line)
halts the CPU for longer than ANTIC's does. 13.1 frames a picture against
11.7.

**But MAME's `xegs` is not a real XEGS** (the user; karateka-proto's
FINDINGS, "CPU left per frame"): it charges almost none of ANTIC's DMA
(a counting loop lost ~3% where ANTIC's rules give ~29%). For this screen
(mode E, 153 lines, refresh on all 262) a real XEGS's ANTIC takes about
8,700 cycles a frame, leaving about 21,200 of 29,870; in this probe's
units (instruction table cycles, without page-crossing and branch extras,
which MAME's 27,270 a frame is in) about 19,900. The work a picture, the
wait loops taken out (`$B627`/`$B634` on the XEGS, `$D6F6`/`$D703` here),
and the frames a picture that gives:

| Scene | work a picture, XEGS | here | real XEGS, estimated | here, measured (MAME a7800) |
|---|---|---|---|---|
| 1 | 307,700 | 281,100 | 14.5-15.5 | 13.1 |
| 2 | 300,600 | 275,100 | 14.2-15.1 | 12.7 |
| 3 | 288,600 | 260,600 | 13.6-14.5 | 12.0 |
| 4 | ~170,400 | ~152,600 | 8.0-8.6 of work, so 9 | 7 |

So on hardware the port should be ahead of the original, about 10-17% in
scenes 1-3 and 7 frames a picture against about 9 in scene 4, not behind
as MAME's `xegs` shows. Estimates: the XEGS side assumes the same ANTIC
cost in every scene (the same bitmap), and the 7800 side is MAME's MARIA
model (karateka-proto found it within 6-9% of the MARIA rules). Altirra
(cycle-exact) or hardware would settle both.

**Scene 4 is capped by rounding, confirmed on the original (MAME):** the XEGS
waits for the vertical blank 3,175 of its 27,523 cycles a frame
(`$B627`), the picture hold (`$B634`) never runs, so a picture is about
6.2 frames of work and shows at the 7th; the port's is about 6.3 (152,600
cycles at 24,110 a frame, the flip routine's wait taken out), also the 7th.
So the port's scene 4 is the original's speed, and a picture 10% lighter
would not change it on either machine.

## The graphics inventory: what each level draws, and from where (2026-09-30)
For the move to MARIA drawing (objects pointing at ROM where possible),
the user asked for an inventory of what is drawn, how much ROM each level
and animation needs, and which images already have identical copies in
ROM, since the ROM layout may be rearranged altogether.

**How:** on the original (MAME `xegs`), where every image goes through the
game's own blitters and nothing is the port's. `probes/xe-assetlog.lua`
hooks the header read every blit shares (`$29D8`, taken at its `RTS`
`$29FA`): the source, the window bank, the size (the image's first two
bytes are rows and width), the variant (normal `$284E`, right-aligned
`$29C2`, mirrored `$2B82`, mirrored right-aligned `$2B8B`) and the routine
that called the blitter; each image's bytes once; the screen clears
(`$280F`) and scene loads, which cut the log into segments; a snapshot after
each. Runs (`work/analysis/assets.sh`): the attract mode, both XEGS
recordings (`xe-01-easy.inp` to the ending, `xe-01-inv.inp` with two
deaths and the gate) and the scripted player in scenes 1, 2, 3, 4 and 6
(the regression's, which dies in scenes 2 and 3): 2.2 million blits.
`probes/assetinv.py` maps each source to the cartridge (the scene's banks:
data `$6000`, code `$1000`, common `$0480`, window `$8000`, bank 15 `$A000`)
and checks the bytes: **every image drawn is the cartridge's bytes where it
was drawn from** (the story's glyphs are drawn from RAM copies whose row
count the scroll lowers; they count as the stored glyph). Output in
`work/analysis/assets/`: `images.csv` (every image, its cartridge copies,
where drawn from, scenes, mirrored, callers), `segments.csv`,
`callers.csv`, and `phases.csv` from `probes/assetphases.py` (segments of a
scene drawing nearly the same images grouped, with a snapshot each).

**379 distinct images, 22,786 bytes** (headers not counted); 10,344 of those
bytes are drawn mirrored somewhere. MARIA can't mirror, so a native
renderer needs a second copy of those: 33,130 bytes in all.

| scene | images | bytes | drawn mirrored | + mirrored copies | fighters' art (bank 14) | the scene's own and shared |
|---|---|---|---|---|---|---|
| 0 title, story, intro | 98 | 5,667 | 1,389 | 7,056 | 1,422 (+1,358 mirrored) | 4,245 |
| 1 level 1 | 214 | 10,431 | 7,367 | 17,798 | 7,218 (+6,455) | 3,213 (+912) |
| 2 level 2 | 195 | 11,845 | 7,210 | 19,055 | 7,128 (+6,365) | 4,717 (+845) |
| 3 level 3 | 161 | 10,339 | 6,398 | 16,737 | 6,151 (+5,694) | 4,188 (+704) |
| 4 finale | 161 | 8,241 | 5,618 | 13,859 | 3,751 (+3,462) | 4,490 (+2,156) |
| 6 gate fight | 60 | 2,444 | 2,220 | 4,664 | 1,706 (+1,698) | 738 (+522) |

- **The fighters' art bank (14) is the core:** 141 images, 7,372 bytes,
  6,545 of them mirrored; 7,654 of its 8,192 bytes are drawn (headers
  included). Every level uses most of it.
- **Where the rest lives** (one copy each, by the bank first drawn from):
  scene data banks 2 (3,458), 4 (2,404), 6 (2,152), 8 (1,752), 11 (1,257),
  10 (386); code banks 13 (1,916), 3 (999), 5 (271), 7 (257); the common
  bank 12 (562: the glyphs and the status bar).
- **Identical copies already in the cartridge:** 82 images have more than
  one, 9,178 bytes of extra copies, almost all at the same offset in
  another scene's bank: level 1's data shared with the attract demo and
  the gate fight (banks 8, 10, 11: 41 images, 3,458 bytes; 8 and 10: 16,
  867), levels 2 and 3 (data banks 2, 6: 6 images, 538), and sprite blocks
  in several code banks (1, 3, 5, 13: 4 images, 2,463; 1, 3, 5: 6, 770;
  1, 7, 9, 13: 4, 795). The port's scene pages keep the data-bank copies
  (each page holds its scene's data bank); its fixed-bank sprite copies
  already share the code-bank ones.
- **Drawn from RAM holding another scene's bytes:** scene 1 draws sprites
  at `$7E00-$7F9F` whose bytes are scene 2's data bank (2), after a death
  in level 2 sends the game back to level 1 (the RAM copy isn't reloaded
  there). Real ROM data, bank 2.
- **The routines that draw** (`callers.csv`): bank 15 `$A857-$A953` the
  fighters (the art bank), scene data `$7A53-$7AC7` (level 1),
  `$7B5C-$7BA0` (level 2), `$7AEB-$7B39` (level 3) the other fighter
  parts, all mirrored; `$07BF` the text glyphs; `$B958`/`$B95D` the status
  bar; scene 0's `$BCxx-$BDxx` and scene 4's `$7CFF-$7D7E` the cutscene
  actors.
- **Phases** (`phases.csv`, `phases.txt`): the level-wide totals above are
  solid; the split into rooms and cutscenes is rougher, since a cutscene
  can run inside a level's segment without a screen clear (the Akuma
  cutscenes), and the snapshot taken 60 frames after a clear sometimes
  shows the next segment. The largest single phases: level 1's cliff and
  fights 10,074 bytes (7,367 mirrored), level 2's 9,322, level 3's
  corridors 6,096-6,658, the finale's princess room 3,994-4,228.
- **Not covered:** images no run drew (rarer poses and deaths in levels 3
  and 4; the player's death was missed once before, "An untraced blit
  source"). Walking the game's sprite pointer tables would close that.

### The sprite tables walked: what no run drew (2026-09-30)
The user: no recording bows, for one. `probes/spritetables.py` finds every
place the code loads the blitter's source pointer from split tables
(`LDA lo,X / STA $03 ... LDA hi,X / STA $04`) or immediates, walks each
table (bounded by the next address the code refers to) in every scene
that has it, and reads each entry as an image. 23 table pairs and 27
immediate pointers: 362 images, 304 of them drawn in the runs. 135 pointer
loads are computed another way (table + offset, a shared `STA $04` tail),
so 75 drawn images aren't reached statically: the runs and the walk
together make the inventory. `probes/drawimages.py` renders images to a
PNG to look at (`SCALE=2`).

**The 58 found but never drawn** (`work/analysis/assets/undrawn.csv`):

| what | images | bytes |
|---|---|---|
| noise: a table read in a scene it doesn't serve (the pointers land in unrelated bytes that pass as a header) | 9 | 4,414 |
| copies in scenes 1 and 6's code banks (7, 9) of other scenes' sprites (the intro cutscene's figures, stairs, floor pieces), older bytes, which no code there draws | 21 | 1,989 |
| **the bow**: two small pieces in the art bank (`$9150` 4×3, `$916C` 4×4, the mask table `$A0A8/$A0D2` entries 11 and 13) | 2 | 28 |
| the finale (scene 4): the orange pieces of the four tables `$7E00`, `$7E88`, `$7EF4`, `$7F60`, entries 20-30, `$16FE` 38×3, `$1F29` 43×4, `$1CEE`, `$6000` (first read as Mariko's kick ending; **corrected below: most are Akuma's**) | 21 | 1,378 |
| small, not identified (`$9879`, scene 1 `$6296`/`$62A4`, `$7F03`, scene 3 `$1D7E`) | 5 | 209 |

- **The bow, confirmed on the original:** `xe-assetlog.lua` with
  `BOWPLAY=1` (its own input: fire to start, then right, then up + fire)
  bows at frame ~1,975 of level 1 (snapshot `as-bow2`), drawn by scene 1's
  `$7A53`; the only images not in the inventory are those two pieces. The
  rest of the bow is the fighter's usual parts.
- **The fighters' tables are otherwise complete in the runs:** all 42
  lower-body images (`$A000/$A02A`) and 38 upper-body ones (`$A226/$A24C`)
  were drawn.
- **Correction (the user: "some akuma parts in there"): the finale's
  orange pieces are Akuma's.** None of the XEGS runs has a real Akuma
  fight (`xe-01-easy`'s easy mode ends it at once; the scripted scene 4
  player stands in the doorway), so his parts were missing from the runs,
  not only from the walk. The user's 7800 recording has the whole fight;
  `probes/p7800-assetlog.lua` (the port's blitter at the same header read,
  engine2 `$79FA`; the images are the original's bytes) over its finale,
  frames 14,000-18,360 (snapshots `rec-akuma`):
  - **drawn there, 600 bytes:** `$16FE` 38×3 is Mariko seated (as Akuma
    grabs the player at the door, f15,712); `$6862`/`$68A3`/`$68E4` and
    `$75E4`/`$7601`/`$761E` are Akuma's robe and legs walking in
    (f15,856-15,876); and six more of his pieces at `$6F00-$6FC7` (9×3, 9×5)
    that neither the XEGS runs nor the walk had (their pointers are
    computed);
  - **still never drawn, Akuma, 767 bytes:** the wide-stance robe
    (`$6966`/`$69D1`/`$6A3C` 21×5), the pieces lying horizontal
    (`$6AA7`-`$6BB5`, falls: his defeat in the user's fight used others, so
    likely one per kind of blow), a bent upper body (`$63DB`) and two small
    pieces;
  - **Mariko's kick ending:** only `$1F29` 43×4, 172 bytes; `$1CEE` and
    `$6000` (55 bytes) not identified.
- So the inventory grows by about 1.6K over the XEGS runs (1.8K with the
  unidentified): the bow's 28 bytes, Akuma's 600 drawn in the 7800 fight
  and 767 not yet drawn, the kick's 172, and 264 unidentified. Recordings with other Akuma defeats and
  with the approach to Mariko in fighting stance would settle the rest.

## Display zones: where everything is drawn (2026-09-30)
The user: the fighters seem to stay in one band the whole time, which
should have display lists of its own; the zones will shape how the image
data is laid out. `xe-assetlog.lua` now also logs each blit's `$05`
(column) and `$06` (top line; the buffer row is `$06 - 35`, `$2D46`) and
each fill's rectangle; `probes/assetbands.py` gives each drawing routine's
rows per scene (`work/analysis/assets/bands.txt`). Buffer rows 0-152.

**The bands (all scenes, all runs):**

| what | rows | drawn by |
|---|---|---|
| the fighters (player, guards) | 79-128 (heads from 79, feet to 128) | bank 15 `$A857-$A953`, each level's part routines (`$7A53-$7AC7`, `$7B5C-$7BA0`, `$7AEB-$7B39`) |
| the hawk | 75-125 | `$B533`, `$B580`, `$7ACF`... |
| Akuma | 84-134 | scene 4 `$7CFF`, `$7D4A`, `$7D7E`, `$7B0A`, `$7B4B` |
| Mariko | 88-134 | scene 4 `$7B28`, `$7B57`, `$7AF9`, `$7B10` |
| the doorways (frames, lintels, portcullis) at the screen's edges | 48-136, columns 0-7 and 32-39 | bank 15 `$B866-$B9xx`, from the art bank |
| level 1's scenery (sky, mountain, fence, posts) | from row 1 | scene 1 `$6ExX-$6F6F`, `$71xx`, `$7Cxx` |
| the floor and its repairs | to about 145 | the levels' own routines, fills |
| the status bar (health arrows) | 146-152 | `$0B7A`, `$0BC0` (every picture) |
| the text (story, titles, "the end") | anywhere in scene 0 and the finale | `$07BF` |

**The colour bands** (the XEGS display lists' third and sixth DLIs, which
set the palette): after buffer row 78 in level 1, the gate fight and the
title screen, after row 64 in levels 2-4, and after row 145 (the status
bar) in all. So the fighters' band lies inside one colour band everywhere;
in level 1 it starts exactly at the change. The hawk reaches up to 75, and
there takes the upper band's colours, as on the XEGS.

**Fixed rows:** of the images drawn (by source), 384 of 509 are only ever
drawn at one row; of the art bank's 141, 130. The fighter code sets each
part's top line from a pose table plus a constant (`$06` = table + `$72`,
`$A943`); only the column moves. The ones that move vertically: the heads
(a few rows, by the upper body's pose: `$8EC1`, `$8E9B` at 81-91, `$8ECB`,
`$8F2B` at 79-105), the hawk (flying: `$93AB`, `$942A`, 75-104, and its
mirrored parts), the story's text (it scrolls), and some of level 1's
scenery pieces.

**What it means for the image data:** an image always at the same rows
can be stored already cut at the zone boundaries, each zone's slice in
that zone's pages (MARIA reads a zone's line L from page `hi + (15 - L)`),
so MARIA only ever moves it sideways and no holey DMA or padding is
needed. Images at fixed rows can be packed together in a zone's page block
by their rows and widths. The few that move vertically need either a copy
per row they use (the heads: a few small images) or the usual vertical
positioning (holey DMA in ROM above `$8000`, or padding pages).

### The user's zone decisions, and the mountain (2026-09-30)
**Decided:** the fighter band as proposed (16-line zones from buffer row 79,
the same in every scene); Akuma and the hawk may be drawn above or below it.
Background: ideally each scrolling background laid out in contiguous ROM
and scrolled by moving the objects' pointer, looping sections a set number
of times where that saves ROM. The mountain is a special object: fixed,
always behind, in levels 1 and 2.

**The mountain is two small images, at fixed positions:**

| | image | rows × bytes | buffer row | column | drawn by | cartridge |
|---|---|---|---|---|---|---|
| level 1 peak | `$6948` | 11 × 4 | 46 | 18 | `$6D47` | banks 8, 10, 11 (level 1, the gate fight, the attract demo: identical copies) |
| level 1 base | `$6976` | 8 × 8 | 57 | 16 | `$755E` | banks 8, 10, 11 |
| level 2 peak | `$6592` | 9 × 4 | 46 | 18 | `$7391` | bank 2 |
| level 2 base | `$65B8` | 9 × 8 | 58 | 16 | `$7346` | bank 2 |

108 bytes of pixels each level (plus 2-byte headers). They are one
mountain cut two ways: level 2's peak is level 1's without its last two
rows, and level 2's base starts a row lower and has three more rows at the
foot. The whole mountain (level 1's peak and both bases) is rows 46-66, at
most 21 rows × 8 bytes, about 170 bytes as one image. Drawn once when a
room is set up; the fence (level 1) and the wall (level 2) are drawn over
it, so in the walled sections its lower part is hidden and in level 1's
section without a wall it shows whole. In level 2 the colours change
after row 64, so its last two rows (65-66) take the lower band's palette,
as on the XEGS. The sky is no image: the upper band's background colour.
- **Correction:** the "level 1 mountain" first assembled here (six pieces
  from `$7C61`, `$6006-$6274`) is the gate structure's roof at the screen's
  right edge, with its posts below (the routine draws down to row 142); level
  2's large `$6274` (61 × 10) and `$6602` (122 × 8) are its gate building and
  its doors. An earlier listing of the set-up's draws was cut to one line by
  a wrong `sort -u` key, which made it look as if the mountain wasn't blitted.

## The conversion to MARIA objects: the plan (proposed 2026-09-30)
The user asked whether the conversion can go step by step or has to go all
in on a level. **It can go step by step.** With multi-line zones, objects sit
in the same display lists as the bitmap's two slices, so anything not yet
converted keeps drawing into the bitmap, and each step moves one thing out
of it. The game stays whole and playable after every step (the level 1
prototype could not: with one-line zones every object needed an entry on
every line). Some steps are naturally cross-level (the fighters' code is
shared), others per level (the scenery).

**Step 1, foundations (no visible change):**
- the object layer: each zone's list = the objects behind the bitmap (the
  mountain), the bitmap's slices, the objects in front; the fighter band's
  zones rebuilt every picture, the others when a room is set up; double
  buffered with the pictures, as now;
- the converter (build time): images from the inventory into MARIA's
  layout, fixed-row ones cut at the zone grid and packed by rows and widths,
  mirrored copies, masks as black silhouettes;
- the new check: the buffers stop being byte-comparable once things leave
  them, so a picture compare (a 7800 screenshot against the original's
  framebuffer through its palettes) replaces `regress.sh`'s byte compare for
  converted parts, plus a per-line MARIA time check;
- **the visibility decision** (below), before the fighters.

**Step 2, the status bar** (rows 146-152, the health arrows, drawn every
picture: 0.76 million blits in the invincible recording alone). Small,
fixed, one zone: proves the object layer, ROM graphics and the colours by
zone, and removes the game's most frequent blits.

**Step 3, the mountain** (levels 1 and 2): one fixed object placed before
the bitmap's slices, so the fence and wall (the bitmap's non-zero pixels)
cover it; the sky is colour 0, transparent. The game stops drawing it.

**Step 4, the fighters** (the big one): the player and guards in the band's
zones as objects from the converted art, the blits and the wipes of their
old boxes removed from the bitmap. The bank 15 routine is shared, so level
by level means routing each level's part routines in turn (level 1 first,
the others still blitting until theirs is done).

**Step 5, the actors:** the hawk, Akuma, Mariko, the cutscenes' figures
(allowed above and below the band).

**Step 6, the scenery, level by level:** each scrolling background laid out
as contiguous ROM and scrolled by moving the objects' pointer (sections
looped where that saves ROM), the doorways at the edges, the floor. This is
where the bitmap empties.

**Step 7, text:** the story, titles, "the end": a small bitmap band or glyph
objects.

**Step 8, the bitmap goes:** the framebuffers (12K of RAM) and the software
blitters and fills leave; their ROM and RAM become free. The game will then
run as fast as its logic allows, so it needs pacing to the original's speed.

**What must be settled first: what MARIA can see.** MARIA reads graphics
while the screen is drawn, from the fixed bank, RAM, or the bank in the
`$8000-$BFFF` window at that moment. The game switches that window for every
blit and runs its scene code from it. The fixed bank has about 2K free, and
the fighters' converted art is about 14K with the mirrored copies. Options:
- the converted fighters in RAM: each picture copies the shown poses'
  slices into a sprite buffer (the prototype's measurement: 0.4-2.4K a
  picture, up to 5.8K); tight until the framebuffers go;
- a window bank that stays mapped while the screen is drawn: the art and
  the scene code rearranged so the code runs from the fixed bank or the
  same bank as the art (the ROM rearrangement the inventory was for);
- a board where MARIA reads its own banks: to be checked against MAME 0.287
  and the user's Pocket core before relying on it; the user's earlier
  decision was to stay within retail layouts.

### The health arrows and MARIA's time (2026-09-30)
The user asked whether the number of arrows will cost much DMA. Each arrow
is a 7 × 1-byte image (the small-sprite block: `$0B12` mirrored for one
bar, `$0B1C` for the other), drawn at a 5-pixel pitch (a 4-pixel arrow and
a gap), so the 160-pixel bar holds 32 at most; the game draws them one blit
each (up to 117 blits in a frame). MARIA's time on each of the 7 lines
(about 2-2.5 CPU cycles an object plus 0.75 a byte; a line is 113.5):
- **one object an arrow:** 38 cycles for 10 arrows, 76 for 20, **122 for 32:
  over the line**;
- **each bar as whole 4-arrow blocks from one ROM strip (5 bytes a block,
  the pitch lining up with the bytes every 4 arrows) plus a tail image of
  1-3 arrows:** 20-35 cycles for 10-32 arrows, about what the bitmap's two
  20-byte slices cost there now (34). The count only changes two objects'
  widths; ROM: one strip and three tails per direction, under 200 bytes.

## Step 1 begins: the title and the story first (2026-09-30)
The user: do step 1, then convert the title screen and the scrolling story
to display lists before anything leaves the framebuffer. Checkpoint first:
`../Karateka-Port-checkpoints/2026-09-30_KEEP_enh-before-maria-step1`.

**How the game draws them:**
- **Text** (`$0780`, common bank): a string is a column, a shift, then
  characters (`$60` + index; a byte below `$60` ends it). Each glyph
  (the common bank's glyph block at `$0480`, pointers `$06F4`/`$0714`, index
  0 the space, not drawn) is ORed in at the column, shifted by shift/2
  pixels, all hanging from one top row; the column and shift advance by
  the tables `$0734`/`$0754`, a shift of 8 carrying into the column. **The
  font is proportional, placed to the pixel.**
- **The story** (scene 0 `$784C`): strings 4-25 of `$7BCC`/`$7BE6`, each
  scrolled in over 14 steps (`$E8` from `$AF` to `$A2`), then five blank
  lines' worth to scroll out. Each step (`$0806`) copies 145 buffer rows up
  one row (5.8K moved), clears the bottom and draws the entering string
  clipped at the bottom (the glyph headers' row counts lowered in RAM).
  20 of the 22 strings have text (two are blank lines).
- **The logo** (`$790B`): 8 blits of 5 letter images (K, A, R, T, E; K and A
  twice), 652 bytes, at fixed places. **Correction:** they are in scene 0's
  data bank (XEGS `$7C00-$7E9A`, bank 11), not bank 15: the listing showed
  the port's relocated `$BCxx` (the scene page's data half at `$A000`). In the
  port they are in bank 0's page, which MARIA sees only while it is mapped.

**`probes/storytext.py`** is the text renderer in Python (for pre-rendering
at build time). Against the original's buffers (`probes/xe-fbdump.lua`,
attract frame 2,000): buffer A matches the rendered story over all 153
rows, 0 bytes different (buffer B: 7, a string half drawn in at the
bottom).

**The story as MARIA data, two ways:**
- **pre-rendered lines** (direct mode): 20 lines × 12 rows (descenders
  included), 8,100 bytes trimmed to each line's columns; scrolled by moving
  the lines' pointers, partial zones at the top and bottom handled by each
  object's own high byte. Simple, no DLIs of its own.
- **character mode**, 1-byte tiles (4 pixels × 12 rows): the story has 250
  distinct tiles, under the 256 codes: 3,000 bytes of tiles + 800 of codes,
  3.8K. Two objects a line (40 codes; an object holds 32 at most), about
  65 of the line's 113.5 cycles. (2-byte tiles: 276 distinct, 7K: the
  proportional font lands at every phase.) The catch: in character mode
  the glyph's page comes from CHBASE, one register for the screen, so the
  partial zone at the bottom of a scroll (the top rows of the entering line)
  needs CHBASE changed there by a DLI of the port's own every frame.

### What the intro takes in ROM (2026-09-30)
**Bank 0, scene 0's page: 15,744 bytes** (640 free): the XEGS data bank 11
whole (8,192), the scene code from code bank 13 (4,349), the scene's
relocated copy of the common bank (2,328; every scene page has one),
tables, descriptions and scene-page system code (875).

**The images the intro draws: 98, 5,667 bytes** (the title, the story, the
intro cutscene, the attract demo fight): code bank 13 (the cutscene's
figures, 1,916), the fighters' art bank (shared with the levels, 1,422),
data bank 11 (1,257: the logo's 652 and the demo fight's level-1 pieces),
the glyphs (shared, 511), and copies of level-1 pieces also held in other
banks (561). The rest of bank 0's page is code, the demo fight's and the
cutscenes' logic, the story's strings and tables.

## The story as letter objects (2026-09-30)
The user chose one MARIA object a letter for the story (narrowing the
scroll if the line time doesn't hold). Built and working on MAME.

**How:** scene 0's story loop (`$785B`) called the scroll (`$0806`: 145 rows
copied up), the bottom clear (`$78B0`) and the string (`$7884`) each step;
`SCENE_REPLACEMENTS[0]` makes those nine bytes one `JSR SysStoryStep`
(`sys7800.asm`, "the story as letter objects"). The step:
- **the first time**, lays the glyphs out a row a page in the idle
  framebuffer pages (glyph row r at page `STORY_G - r` = `$5F - r`, 14 rows
  with the blank ones; offsets and widths at `STORY_GTAB` `$5110`), from the
  glyph block (`$1B80`, the game's `$06F4/$0714` pointers), and builds each
  of the 22 lines' objects once (templates, pages `$60-$6A`, two a page)
  from the game's own strings (`$7BCC/$7BE6`) and advance tables
  (`$0734/$0754`), placing each letter as `$0780` does (x = 4 × column +
  shift / 2; the space not drawn);
- **every time**, waits for the pace (`STORY_PACE` 9: 8.0 frames a step on
  average, as the bitmap version), counts the step (`S_STORYT`, 0-377) and
  builds the next picture's display lists in the main program (the other
  buffer's list of the pair on screen, found by buffer and mode), which the
  flip then shows as built.

The list builder's zone height and zone emit go through `ZoneH`/`ZoneEmit`:
in story mode the buffer rows become zones of the story (the same runs,
DLIs and 16-line limit): a row's text slot is (row + step) / 14 less
`STORY_L0` (10), its row in the slot the remainder; rows 2-140 show text,
the rest blank (as the original's clears). **A zone ending on its slot's
last row points at the line's template directly** (its objects' high byte
`STORY_G - 13` is right for any zone that ends there, since MARIA reads a
zone's line L at page high + OFFSET); a zone ending higher (cut by a DLI,
or the bottom of the text) gets a copy with high `STORY_G - (last row)`
(`StoryPatch`, at most 8 a buffer, pages `$6B-$6E` and `$6F-$72`). So a
step builds one DLL and at most a few ~100-byte copies. `StoryOff` (in the
full clear `$280F` and the scene loader) turns story mode off and forgets
the lists built, so the next pictures are the bitmap's again.

**Checked:**
- **pixel for pixel against the bitmap build** (the checkpoint's cart),
  MAME screenshots at the same scroll step (just before the next step):
  steps 5, 20, 60, 100, 139, 140, 141, 200, 260, 300, 350 and 376, 0
  pixels different;
- all 378 steps (frames 909-3,925; the bitmap build 909-3,913);
- the rest of the attract loop (the cutscene, the demo fight, the title,
  the story again) runs as before; the demo fight's course differs (it
  depends on timing, and the story's frames changed slightly);
- fire in the middle of the story starts level 1 normally;
- `regress.sh`: 13 comparisons byte for byte.

**ROM:** code only, 928 bytes in the fixed bank (14,181 → 15,109 used; 1,275
free); no graphics added
(the glyphs, templates and lists are built in RAM from what the game has).
**Not yet checked:** MARIA's time per line on hardware (up to 24 letter
objects on a text line, estimated 84-102 of 113.5 cycles; MAME drew them
all). The title screen (the logo, "presents", "a game by", "jordan
mechner", the copyright) is still the bitmap's.

## The title as objects, and a blank screen around the objects' data (2026-09-30)
**The title** (`$77CC`): the logo (`$790B`, 8 blits of 5 letter images,
into each buffer) and the two copyright lines (`$7918`, then `$2179`: the
images at XEGS `$2193` and `$6100`, 9 rows × 25 and × 29 bytes, rows 115 and
126) are pictures, not glyph text. `SCENE_REPLACEMENTS[0]` makes the three
calls (`$77CF`, `$77DF`, `$77EC`) `SysTitleLogo`/`SysTitleCopy`, which mark
what the buffer `$07` names now holds (`S_TITLEA`/`B`: 1 the logo, 2 the
copyright) and forget its lists. The first mark of a title lays the 10
objects out once (`TitleLayout`): a row a page in two canvases in the idle
framebuffer pages (the logo's rows 29-60 and the copyright's 115-134, each
canvas's top row at page `$63`, each object its own columns), and a
template of each canvas's objects (page `$64`). The build writes the object
table (`TITLE_SLO/SHI/X/ROW/CAN`) from the game's logo table
(`$795A-$797F`) and the copyright routines' immediates, so the positions
are the game's. A canvas's zones get a copy of its template with the high
byte for where the zone ends (`StoryPatch`, its base page now `S_SGB`).
The logo and copyright show from frame 190/194 (the bitmap build: 192/202);
while the title is up the picture is the bitmap build's pixel for pixel
(frames 300-500).

**The glitches found on the way** (frame-by-frame screenshots of both
builds, every 2 frames, compared by picture):
- the objects' data is written into framebuffer pages, so while a bitmap
  list is on screen it shows as garbage (stray dots before the title and
  story), and the game's full clear at the end of the title wiped the
  canvases while the other buffer still showed the title from them (a
  half-erased logo);
- the canvases were laid out again at each logo call, on screen (a logo
  appearing as "ka", "karat").

**The fix, the blank screen** (`ObjBlank`, `ObjEnd`, `S_OBLANK`): before the
story's or title's data is written, both buffers' bitmaps are marked as
holding it (a bit a buffer); a marked buffer's rows are shown as empty
zones unless the story's or title's lists show it; every list is rebuilt
and the step waits three frames so the list on screen is blank before any
write. The game's full clear of a buffer takes its mark off (a buffer copy
passes on its source's). When a clear or a scene load comes while the
story or title is on (their ends, or START), both modes go off first, then
the blank, then the clear (switching them off after the blank left the
title's lists rebuilt during the wait: one half-erased frame). The title
is laid out once. After: **every picture the new build shows through the
title, the story's start, the story's end and the cutscene is one the
bitmap build shows** (the cutscene's first picture, which the bitmap build
shows half drawn for one frame, is black instead).

**Timing:** the title is about 70 frames shorter (it ends at 590 against
662). Its waits (`$783C`) are busy loops, not frame counts, and with the
title as objects MARIA's DMA takes fewer cycles, so the loops run faster.

**Checked:** `regress.sh` 13 byte for byte; START during the title and
during the story starts level 1 (one black frame between).

**ROM:** the fixed bank is now full to within 356 bytes (the main system
block ends `$F1EA`, 22 bytes before engine1 at `$F200`); `TitleLocate`,
`TitleZoneH` and the blank routines are far pieces, placed from engine1's
end (`$F403`) as well as above `$F500`.

### The buffers' top rows: what still draws there (2026-09-30)
The user: next, shrink the buffers by the top of the screen that play never
uses. The inventory's positions (`xe-assetlog.lua` `$06`), the title's and
story's drawing left out (they are objects now), the topmost buffer row
each scene draws on:

| scene | topmost row | what |
|---|---|---|
| 0 (cutscenes, demo fight) | 46 | the mountain |
| 1, 6 (level 1, the gate fight) | 1 | the torii gate at the right edge as it scrolls in: two stacks of pieces (`$6EDF-$6EE4`: `$6707` 18×5 at row 1, `$6857`, `$682B`, `$67D1`, `$6763`; `$7C61`: `$6274` 8×3 at row 3, `$6242`, `$61B4`, `$6146`, `$60A8`, `$6038`, `$6006`) |
| 2 (level 2) | 18 | the gate building (`$6274` 61×10) and its doors (`$6602` 122×8, from row 22) |
| 3 (level 3) | 48 | |
| 4 (finale) | 0 | only the ending text ("and so this adventure ends…", `$07BF`, rows 0-135); otherwise 60 |

So the top 46 rows are free in level 3, the finale's play and the
cutscenes, but not in levels 1 and 2, nor in the ending text. Freeing them
(46 rows × 40 bytes × 2 buffers, about 3.7K) needs those three as objects
first: the ending text as the story's letters, level 1's torii and level
2's gate building as scenery objects. (Also: the play lists' three mode-8
rows read row 0's first 30 bytes.)

## The ending's text as letter objects (2026-09-30)
The ending (scene 4 `$784E`: clear, flip, the text lists, clear, `JSR $6200`
→ `$632E`, flip, then the START loop) draws ten strings (`$6318`/`$6323`)
with the story's routine `$0780`, 14 rows apart from row 0, once (no
scroll). `SCENE_REPLACEMENTS[4]` makes `JSR $6200` (`$7870`) `JSR
SysEndText` (`EndText`, a far piece): the story's engine with the ending's
strings, frozen at step 140 (the first string at row 0). To share it, the
story's set-up now copies its line pointers into RAM (`STORY_PLO/PHI`,
`$5160`/`$5180`) and the count and the text's top and bottom rows are
variables (`S_SLN`, `S_STOP`, `S_SBOT`: the story's 22, 2, 140; the
ending's 10, 0, 152).

**Checked** (the ending reached by jumping to it, `probes/p7800-jumpto.lua`:
scene 4 by the scripted player, then the PC set to `$B84E` at a safe moment,
the scene page in and no interrupt running; `p7800-jumpsnaps.lua` every 2
frames): the text is the bitmap build's pixel for pixel; the pictures on
the way are the bitmap build's plus one plain black frame (the blank), and
none of its half-drawn one.

**On the way:**
- a clear now builds a buffer's lists again only when its bitmap had held
  the objects' data (the first version did it at every clear: an extra
  rebuild at every room change, and at the ending one frame of the room in
  the text lists' mode);
- the system variables had no room (the "64 bytes free" counted before the
  48-byte clip row; there were 16): the objects' scratch (16 bytes) moved to
  page `$43`'s first 16 bytes (`OBJVARS`: framebuffer pages keep offsets
  0-15 out of the buffers, and the full clear starts at 16); the flags stay
  in the system variables. The story's line count had first been named
  `S_SN`, which TiaSound already uses: it is `S_SLN`;
- the fixed bank: `StoryPatch` is a far piece (its last part, the next
  slot, in the main block, and its callers now pass the zone's last row,
  to fit the 110-byte gap at `$FE25`); the fixed bank has 220 bytes left, the
  main system block 8 before engine1.

`regress.sh`: 13 byte for byte; the title and the story's end: every
picture one the bitmap build shows (the story's first step, one row of text,
is too short for the old run's every-2-frames sampling).

## The status bar as objects (2026-09-30)
The user: convert the health arrows first, hand that area to MARIA and free
the buffers' status rows at the bottom of the screen (the player's health is
highest in the bird fight; Akuma likely the foe's highest).

**What the game does.** Every picture, into the buffer being drawn: `$0B27`
fills the status rows (146-152) with 0; `$0B3E` draws `$B6` player arrows
(the image `$0B12`, mirrored, at x = 5i) and `$0B98` `$B7` foe arrows
(`$0B1C` at 155 - 5i). Below 3, the arrows are not drawn while `$07 = $20`
(buffer B being drawn), so they blink; the player's first drop below 3
starts the warning tune (`$15`, once: the flag `$0B26`). Scene 0 calls the
three directly (`$760E`, `$7654`, `$7699`), every scene also through the
table at `$0B00`.

**Now.** The three routines are replaced in place (`layout7800.STATUS_CODE`,
same size, NOP-filled by `fitted`: the entries keep their addresses): each
sets how many arrows the buffer being drawn shows (`S_STP`/`S_STF`, per
buffer; none below 3 in buffer B), keeps the warning as the game has it, and
builds that buffer's status list (`ScStBuild`, in the scene page). The
status zone (rows 146-152) shows only that list: `STATUS_DLA` or `_DLB`
(console RAM `$1F80`/`$1FCC`, 76 bytes each). The list is built only for the
buffer being drawn, which is never on screen; the full clear empties it and
the buffer copy copies it, as they did the rows.

- **The arrows:** each bar as blocks of 4 arrows (5 bytes: the 5-pixel
  pitch lines up with the bytes every 20 pixels), one 5-byte object a
  block, then single arrows (one byte each: a strip's first byte holds just
  its first arrow); the player's from x = 0 rightwards, the foe's from 160
  leftwards.
- **The strips:** a block's 7 rows, 5 bytes each per bar, in the heads of
  framebuffer pages `$44-$4A` (offsets 0-4 the player's, 5-9 the foe's).
  Those heads are outside the buffers; nothing but the boot's clear writes
  them (`probes/p7800-pageheads.lua`: title, story and play, 9000 frames).
  They are made at the first status clear (RAM is zero at boot; the
  player's first strip byte is not), from 70 bytes of patterns
  (`layout7800.ST_PAT`, from the game's two images; the build checks they
  are the game's).
- **Where the bars meet:** the game draws the foe's arrows after the
  player's. Each one is opaque over its 4-pixel place, and both bars use the
  same 32 places, so a foe arrow hides a player arrow completely. MARIA's
  zero pixels are transparent, so the list shows only the player arrows
  left of the foe's (at most 32 − foe). Found by the check below at 25 + 25
  and at 20 + 14.
- **The list's room:** up to 32 arrows (all a bar can show) take at most 12
  objects; the list holds 18 and its end. A guard stops a list at its room.
  A first version kept 48 bytes (11 objects); 27 + 3 arrows (the player's
  health rises on its own during a hold) needs 12 and lost an arrow.

**What it frees:** the status rows of both buffers (2 × 7 × 40 bytes: in
pages `$40-$46`, buffer A's column 2 and B's column 5). The game no longer
draws there, since `RowBase` stops every draw above row 146, and nothing
shows them. The first version kept each bar's full strip (35 bytes × 7 rows)
in those rows' place. That was one object a bar but took 490 of the 560
bytes, so the 5-byte blocks replaced it. Also gone: the arrow blits (up to
28 a picture) and the status fill. The stable port's cache that drew the
arrows only when they changed (the `$B60F` and `$AD80` hooks) is not
needed.

**ROM:** the entries and their helpers live in the game's old status code
(`$0B12-$0BDC`, whose images are now layout's patterns). The patterns live
in the story scroll's old code (`$0806-$0861`: dead since the story became
objects). Its fixed-bank helpers (`RowNextS`, `RowWrapE0/E2`, `RowNextE`)
and five dead jump-table entries (with `SysStClr`) went too. The scene
page's system code is 280 bytes (the limit is 311, for level 1's code). The
main block is 4196 bytes, and the far pieces may now use its tail before
engine1. `TitleMark` reaches `ObjBlank` through the main block (`ObjBlankM`),
because one far piece cannot call another. The fixed bank has 403 bytes
left.

**Checked:**
- `regress.sh`: 13 byte for byte. `playkey.lua`'s port dumps now draw the
  status rows from the buffer's list, as MARIA shows them.
- Screenshots at those points against the stable build: 10 of 10
  identical.
- A lockstep run with held health (`playkey.lua HOLDS=250`: from flip 250
  the health is set at every flip to 37 pairs in turn, 12 flips each; all
  counts 3-26, the blink pairs below 3, 24 and 27 arrows). Both machines
  dumped both buffers at every flip, 250-720, and the status rows match the
  original at all 471. The pictures match too, except in scene 0 after the
  scripted player's deaths (the story, objects by design) and the first flip
  back.
- `HPAIRS=25:25,30:30,16:16,20:14` (overlapping bars): both whole buffers
  match at every flip.
- `probes/p7800-stsweep.lua` / `stsweep.py`, port only, every frame: the
  rows the buffer on screen shows are always the arrows for its counts (48
  pairs). The warning tune starts once at each drop below 3 (4 of 4).

**Corrections and dead ends:**
- A write tap seemed to show other code writing the RAM after the lists
  (`$1FE0-$203F`: PCs `$F908`, `$FB57`, `$2542`...). Those writes all come
  before the cartridge's boot clear: the 7800 BIOS (its RAM test, and the
  code it runs from RAM). `$1F78-$203F` is free after boot, as noted before
  (`probes/p7800-ramwrites.lua` lists writers in first-write order).
- The sweep's own first checks were wrong in three ways. It looked at both
  buffers, but only the one `$07` doesn't name is on screen. Re-poking the
  health after each frame let the game's own `DEC` kill the player (it tests
  the zero it computed). And it ORed overlapping arrows.
- On the invincible/easy cart the sweep's counts follow the game's logic
  (one hit ends a fight), so only its "rows shown" check applies there: 0
  mismatches.

Not tried: the user's recording (`test-karateka7800-invincible-easy-0929-
2309.inp`). It was made on the stable build, and this one's title is
shorter, so it would likely run out of step. `S_STW` is unused now (a byte,
for the cleanup).

## The status bar's rows given back (2026-09-30)
The user: nothing should be drawn in the status bar's rows and below any
more; reclaim that RAM, and keep track of what is no longer used, which
will be one of the hard parts of the conversion.

**Checked first:** a write tap on the status rows' RAM (pages `$40-$46`,
bytes 96-135 of buffer A's column and 216-255 of B's) in scenes 1, 2, 3, 4
and 6. Only whole-buffer sweeps wrote there: the boot's RAM clear, the
game's full clear (`ClearBuf`) and the buffer copy (`CopyBuf`). The game
draws nothing there (`RowBase` stops every draw above row 146).

**The buffers end above the bar:** `FB_ROWS` is 146 (it was 153), and a
column is `(FB_ROWS + 2) // 3` = 49 rows (was 51). The pages are
`FB_PBOT-FB_PTOP` = `$42-$72` (was `$40-$72`), so pages `$40` and `$41` are
free past their heads: 479 bytes. Each column's last row, 146, is allocated
but unused (80 bytes). Everything that walks the buffers takes the
geometry from `layout7800`: the row address and steps, the clear and copy,
the fast fill, the zone heights, and the level-1 column routines, whose
bottom cut (`FB_ROWS`) now agrees with `RowBase`'s. Also:
- the blitter's inline row step compared with `$3F`; it is `FB_PBOT - 1`
  now;
- the game's 17-byte record at `$47F7` (XEGS: B's last byte, then 16 past
  it) keeps its 7800 home, `$40FF-$410F`, as an explicit gap now that its
  first byte is no longer a buffer byte;
- the game's own buffer-copy set-up and page loop (`$AD8C-$ADE3`) named
  addresses in the rows that are gone. They are reached only from the two
  calls `SysCopyBuf` replaced, so they are removed: 88 more bytes for the
  fixed bank, 477 free now;
- the zone height (`RowsZoneH`): rows from the status bar down are not a
  buffer's, and are cut at most 16 (the first build split the bar at the
  column's foot, a 1-row zone, and the bar vanished; the screenshots against
  the stable build caught it). The build's mirror of the zone count
  (`zones()`) does the same, and now also stops at the bar's top;
- `playkey.lua` and `p7800-fbflips.lua` take the geometry from the symbol
  file (`FB_BAND`, `FB_PTOP`, `FB_ROWS`); other probes that hard-code 51
  rows are older-layout tools.

**The ledger:** `layout7800.FREE_RAM` lists the RAM nobody uses:
- console RAM `$1F78-$1F7F` and `$2018-$203F`, around the status lists;
- pages `$40` and `$41` past their heads, except the record and the story's
  line pointers (`$4010-$404F`: moved there by the fix in "The story's
  patched lists overran"), so 175 + 240 bytes;
- the heads (bytes 0-15) of pages `$44-$72`, less the strips' 10 bytes in
  `$44-$4A`.

The build writes the ledger to `work/karateka7800.free`, and
`port/freecheck.sh` proves it. It runs `probes/p7800-freecheck.lua` in every
scene (0 unplayed, the others with the scripted player): a tap on each
range, counting every write after the boot's clear. The BIOS writes some of
that RAM before the cartridge runs, so writes before the boot's clear don't
count. Result: 0 writes, all six scenes. Whatever the conversion frees next
goes into the ledger and gets the same check.

**Checked:** `regress.sh` 13 byte for byte. The lockstep hold run against
the original: the status rows match at all 471 flips, and the pictures
match outside scene 0. The overlap run matches in both whole buffers.
Screenshots against the stable build: 10 of 10 identical. The status
sweep: the rows shown are always right, and the tune plays 4 of 4.

## The story's patched lists overran (2026-09-30, correction)
While checking the shorter buffers, the title and story were compared frame
by frame with the build before. They were identical, one frame earlier.
But against the stable (bitmap) build, 16 of 161 story frames showed
pictures the bitmap build never shows, in a pattern repeating every 16
frames (two story steps). So the claim in "The story as letter objects"
(every picture one the bitmap build shows) was wrong: that check sampled
every 2 frames and matched pictures loosely. Two bugs, both there since the
story became objects:

1. **The patched lists overran.** A zone that ends partway through a text
   line needs a copy of the line's letter list with its own high byte
   (`StoryPatch`). There is one at the partial top line, one at the partial
   bottom line, and two at each of the four DLI rows inside the text: up to
   10 a picture. Each buffer had 8 slots (4 pages, two a page), A's at
   `$6B-$6E` and B's at `$6F-$72`. Buffer A's 9th copy went into B's first
   slot. Building one buffer's lists then rewrote a copy the other buffer's
   picture was showing:
   - A's partial bottom line showed B's top line (frames +66-68 of every
     16);
   - B's partial top line showed scrambled rows (frames +60 and +76).

   Found with `probes/p7800-dlldump.lua` (the DLL MARIA uses and each zone's
   first objects, at chosen frames). Now each buffer has 10 slots
   (`STORY_PATN` = 5 pages): A's at `$6B-$6F`, and B's at `$42-$46`, pages
   neither the title's canvases (`$47-$66`) nor the story's data (`$51-$6A`)
   use. `StoryPatchNext` never moves past its buffer's last slot, and the
   build checks that the areas overlap nothing and each other.
2. **A line of dots at the story's start.** For one frame (856) a
   full-width line showed on a black screen. The story's set-up copies the
   lines' pointers (`STORY_PLO/PHI`) before its set-up routine blanks the
   buffers (`ObjBlank`), and they lived in page `$51`. So buffer B's
   bitmap, shown that frame, had them in row 33. (Traced with
   `probes/p7800-frametrace.lua`: at 856 the frame routine built B's list
   as a bitmap, then `ObjBlank` ran.) The pointers now live at
   `$4010`/`$4030`, in page `$40`, which is outside the framebuffers now.
   The ending (`EndText`) copies them the same way and gets the same fix.

**Checked:**
- The whole story, every frame from 800 to 4700 (3,901 snapshots,
  `p7800-snapat.lua`), against every frame of the stable build's story
  (700-4900): every picture is one the stable build shows.
- The most slots one picture takes (`probes/p7800-patmax.lua`, the same
  run): 9 in each buffer, of 10. (With 8 a buffer, 9 had overflowed.)
- The ending, frame by frame from the jump (`p7800-jumpsnaps.lua`,
  `EVERY=1`, 602 frames, `END` set: `run7800.sh`'s default of 300 also
  ends the scripted player): every picture is one the stable build shows,
  except the change from the room to the text. There the new build shows 12
  plain black frames and the stable build shows 30 black frames with the
  player's arrows.
  - The original's full clear (`$280F`) covers each buffer whole,
    status rows included, so plain black is the original's picture.
  - The stable build's arrows come from its arrow cache, which draws them
    again at the flip after a clear even when the game draws none: a small
    divergence in the stable port.
  - The text comes 19 frames sooner, as known (it isn't drawn a letter at
    a time).
- `regress.sh` 13 byte for byte, and `freecheck.sh` 0 writes in all six
  scenes.

## The status bar as objects: its cost (2026-09-30)
The user asked how the new arrows affect performance. Measured against the
stable build (its arrow cache: the arrows are drawn into the bitmap only
when they change).

**CPU, the status entries per picture** (`p7800-drawprof.lua` with
`TIMED=` entries, now also `TOP=` for the whole list; emulated time from
entry to return, so MARIA's DMA counts; scripted player, frames 3000-9000):

| | scene 1 (fights), a picture | scene 4 (Akuma's hall), a picture |
|---|---|---|
| stable: clear / player / foe / flip hook | 466 / 2,809 / 6,758 / 108; 9,260 all | 58 / 52 / 65 / 91; 266 all |
| new: clear / player / foe | 388 / 922 / 1,520; 2,580 all | 330 / 585 / 559; 1,470 all |

- **In fights, about 6,700 cycles less a picture.** The stable cache still
  blits the arrows that change, and in a fight they change often. The
  original (before the cache) spent about 56,000 a picture there: the
  status fill and every arrow's blit, about 2,000-2,400 each ("Where the
  drawing time goes").
- **When nothing changes, about 1,200 more a picture.** Each of the three
  entries builds the buffer's whole list, though only the last one's
  counts. A build per picture at the flip, and none when the counts are
  the same, would bring this near the cache's 266.
- **The pace:** scene 1, flips 300 to 449 (play only), 1,296 frames against
  the stable build's 1,338: 3% faster. In scene 4 both take exactly the
  same frames (1,750 and 2,100 for its two stretches): its pace is the
  game's own frame minimum there, not the drawing.

**MARIA, the status zone's DMA** (about 2 CPU cycles an object header and
0.75 a graphics byte, 7 lines a frame): the bitmap's two 20-byte objects
cost 238 a frame whatever the arrows. The lists cost 0 with none, 116 at
3/3, 259 at 23/0, 318 at 14/14, and at most 357 (12 objects). That's
between −238 and +119 a frame, of about 29,900: under 0.4%.

**Hardware (2026-09-30):** the user tested the status-bar build on the
Pocket: good through the attract demo and up to the crushing gate. The
variant carts (invincible, invincible-easy, level3-invincible) are rebuilt
from the current build (the RAM and story fixes).

## The tall objects' tops: sizes, and what the art bank holds (2026-09-30)
The user: rather than separating the tall objects whole, convert the
portion above the buffers' new top in place in ROM. The game's draws have
to be cut at that row anyway, and so, eventually, the buffers.

**Above row 45** (from the original's per-draw logs, `as-*/assetlog.log`;
every image is drawn at one row, except level 1's 2-row post pieces at
37-43):

| | Images (mirrored counted apart) | Bytes above row 45 | Whole images |
|---|---|---|---|
| Level 1 and the gate fight | 19: the torii pieces, the gate structure's roof, the post pieces | 888 | 1,125 |
| Level 2 | 2: the gate building (61 × 10, from row 18) and its doors (122 × 8, from 22) | 454 | 1,586 |

The rest of what draws there are erase fills. As objects, the tops take
about 1.3K, against the 3.6K the buffers' rows take.

**What MARIA can see.** While the screen draws, the cartridge window holds
the scene page (the scene code runs from it), except during blits from the
art bank (pages `$80-$9F`: the fighters), when it holds bank 6. So data
for objects in the window must be at the same addresses in both: the
level's scene pages (1 and 5 for level 1, 2 for level 2) and bank 6. Or it
must be in the fixed bank, or in RAM.

**Bank 6 (the art bank)**, as the build places it:

| Address | Bytes | What | Read when |
|---|---|---|---|
| `$8000-$9FFF` | 8,192 | The original's art bank 14 (141 images, 7,372 bytes: the fighters' parts; 122 also drawn mirrored) | Blits from pages `$80-$9F` |
| `$A000-$A160` | 353 | The fast fill's code | Copied to cart RAM at each scene load |
| `$A203-$AF02` | 3,328 | Engine part 2 | Copied to `$7300` at load |
| `$AF03-$B178` | 630 | The small-sprite block and the hyphen | Copied to `$1B80` at load |
| `$B530-$B8D7`, `$B9C4-$BAFA` | 1,247 | The intro cutscene's sprites | Scene 0 blits |
| `$BB29-$BBD6`, `$BCFE-$BEA1` | 594 | The finale's Mariko frame and frames | Scene 4 blits |

That is 14,344 used and 2,040 free, in six gaps of 46-951 bytes. 4.3K of
it (engine part 2, the fast fill, the sprite block) is read only at scene
loads and could live in any bank.

**Room in MARIA's layout** (a run of consecutive pages with the same byte
range free in every bank that must hold it; computed from the build's
placements): none today. Level 1's tops, 18 pages free in banks 1, 5 and 6
at once: 0 bytes. Level 2's, 27 pages in banks 2 and 6: 0 bytes. Banks 1
and 5 have 224 bytes free in all.

### What draws above row 45, and how it is erased (2026-09-30)
`probes/p7800-toplog.lua` (on the port, the scripted player driving)
logs:
- every blit and fill reaching above `TOPCUT` (45), with the buffer it goes
  to and its position;
- every full clear and buffer copy;
- each flip.

`probes/topana.py` replays the log per buffer: a draw adds a piece, a
clear empties the buffer, a copy copies it. For each fill it checks whether
the pieces under it are covered whole or in part. Runs: level 1 (9,000
frames) and level 2 (9,000; the scripted player died there and went on in
level 1).

**Level 1's scenery is state-driven.** `$6E7D` draws the torii and `$7C65`
the gate structure (`$4C` picks which). Each piece's image, top line and
column offset come from tables (`$6DFA`/`$6E0C`, `$6E30`, `$6E1E`), placed
at column `$52` and shift `$50`. The routine redraws everything when
`$52`/`$50` differ from the last drawn (`$E1`/`$AE`). When the fighters
stand near a post, it draws the posts again over them: the bitmap's z-order
is its draw order. On one side (`$52` below 20, or wrapped negative) the
pieces go through the other blit entry (`JSR $280C` instead of `JMP $2803`),
apparently the mirrored blit; this run never drew there.

**Erasing:** before each redraw, a fill of sky (`$AA`, colour 2) over
columns 28-40, rows 0-69, the torii's old place, then all the pieces 2
pixels further on. Level 2's doors (`$6602`, 122 × 8, from row 22, at the
left edge and partly off it) are erased with black (columns 0-8, rows
22-118) and drawn again. In both runs, 422 erases covered their pieces
whole and none covered one in part. **So objects can follow the game's own
draws:** a draw adds a piece, a fill removes the pieces it covers, a clear
empties the list, a copy copies it.

**The sky is pixels.** At room set-up, level 1 fills rows 0-69 with `$AA`:
the sky is colour 2 in the bitmap, not the background colour (levels 3 and
4 are black there; level 2's top 18 rows are never drawn). Without those
rows, MARIA has to draw the sky.

**The pieces are opaque, black included:**
- the torii's pieces hold many colour-0 pixels: its black shading, with the
  sky's colour 2 baked in around it (beam `$6707`: 104 of 360 pixels are
  colour 0);
- the doors: 1,160 of 3,904;
- the game's blits write the whole rectangle.

In MARIA's 160A mode colour 0 is transparent, so over a sky shown as the
background colour, the torii's black would turn sky-blue. Reproducing it
exactly needs:
- **kangaroo mode** (CTRL) for the top zones, where colour 0 is drawn in
  the background colour (black), so a later piece covers an earlier one
  completely, as the game's blits do;
- **the sky as a full-width colour-2 object** behind the pieces;
- a DLI at the zones' start and end to switch CTRL. The port already
  changes the palettes by DLI.

**Missed by the probe:** the posts' pieces log only at rows 37 and 39. The
port's level-1 column routine (`ColA`/`Col68`) copies the middle pieces
straight into the buffer, rows 41-44 included, so the cut must cover it
too. Not yet seen: the torii mirrored (left half), and level 2's gate
building (`$6274`, from row 18).

**The user's plan: the sky as the background colour** for those zones (it
is one flat colour). Checked with `probes/topsky.py`. For every picture
shown in the level 1 run, it renders rows 0-44 twice:
- the bitmap's way: sky fill, then the pieces written whole in draw order,
  erase fills as logged;
- the objects' way: background = sky; each piece converted, its colour 2
  (the baked-in sky) transparent and its colour 0 (black) an opaque colour
  that is black; drawn in order.

Result: 775 pictures (329 with pieces on screen), every row the same.
Control: with colour 0 left transparent, 1,780 rows differ. So no sky
object and no kangaroo mode; instead:
- the background colour is the sky for level 1's top zones, and black again
  from row 45 (a DLI at the top zones' last line);
- the converted pieces use a palette of their own: colours 1 and 3 the
  bitmap's for that band, colour 2 black. The game's colour writes go only
  to palette 1 and the background, so the others are free. MARIA's colour
  registers can't be read, so the port sets that palette from the values
  the game uses for the band.

### The top rows as objects: the capture rules, checked (2026-09-30)
Runs on the invincible-easy cart, so the scripted player gets far: level 1
(3,054 pictures: the torii crossing to the left half, mirrored; the gate
structure; the posts) and level 2 (2,630: the doors and the gate
building). `p7800-toplog.lua` now:
- logs `$D0` at each flip;
- dumps the shown buffer's rows 0-44 (`DUMPTOP=1`);
- logs the port's level-1 column routine (`ScColA`/`ScCol68`: the caller's
  piece again every 2 rows to the first line at or past the limit in A,
  mirrored through `$280C` when `$52` is negative or below 20).

`probes/topcheck.py` replays a log and renders each shown picture's rows
0-44 as objects, against the real buffer.

**Result:** rows 0-44 identical in every level picture, both levels.

**The rules this establishes:**
- **Placement:** a normal blit's piece at x = 4 × `$05` + shift. A mirrored
  one (`$2B8B`, through `$280C`) is the image reversed with its left edge
  at 4 × (`$05` − width + 1) + shift (fitted against the bitmap: every
  draw, all four shifts).
- **A draw** adds a piece, and removes any piece wholly under its
  rectangle. The game's blits are opaque rectangles: the gate structure is
  redrawn in place each time, and without this its pieces pile up.
- **A fill** removes the pieces it covers. A piece it covers only in part
  keeps its other pixels. Seen 24 times in level 1, always the same: the
  gate structure's roof piece (`$60A8`, 12 × 13, row 42, x 108) against the
  erase fill of columns 28-40. Its first byte column (x 108-111) stays in
  the bitmap after the structure moves on, a leftover of the original's,
  so the object keeps 1 byte of width. The piece is byte-aligned, so the
  leftover is whole bytes of its data.
- **The background:** each buffer's top starts black after a full clear;
  a fill across the whole top sets it to the fill's colour (level 1's sky,
  colour 2). A buffer copy copies the pieces and the background.
- **Conversion:** level 1's pieces over the sky have their colour 2
  transparent and their colour 0 opaque black (a palette whose colour 2 is
  black). Level 2's top is black, and its pieces' colour 0 transparent is
  exact.

### Step 1 of the top cut: the buffers begin at row 45 (2026-09-30)
- **The buffers** hold rows 45-145 (`FB_TOP` 45): columns of 34 rows,
  pages `$4F-$72` (they were `$42-$72`). `fb_row` and `RowAddr` count from
  `FB_TOP`. The zones of rows 0-44 lie on a 15-row grid (`TOP_ZONE`); for
  now they are empty lines (the objects come next).
- **The cut:** `RowBase` cuts a draw's rows above 45. For a blit (called
  from `$78xx`/`$7Axx`; a fill comes from `$7Cxx`/`$7Dxx`), the source
  moves on by `$1F` bytes a row, both blitters stepping their source that
  way. A draw wholly above goes to the scratch row, as before. Scratch:
  `S_CUTK` at `$1F78` (`TOPVARS`, taken from the free-RAM ledger).
- **The level-1 column routine** blits pieces above the cut one at a time
  until one lies wholly in the buffer, then copies from that one, so the
  posts keep the speed-up.
- **The three mode-8 rows** at the top of the play lists showed buffer row
  0's first 30 bytes, which only ever hold the top's background (sky or
  black). They are empty lines now (over the background colour), and their
  widening (`Mode8`) is gone. Its tables `M8NIB_*`, `S_M8COPY` and
  `MODE8_ROWS` are unused: for the cleanup.
- **Dead game code:** the rest of `$2D46` (`$2D56-$2D77`: the times-40 and
  the buffer base, which named row 0) was never reached once `RowBase`
  returned to the caller. Now fill bytes.
- **Build checks:** the story's patched lists must be in cart RAM pages
  (they had to be framebuffer pages); the title canvases must lie above the
  pages' reserved heads (`$40-$42`).
- **Checked:** `regress.sh` with `fbcompare.py --from-row 45`: 13 of 13 byte
  for byte from row 45 down, the status rows included. `playkey.lua` writes
  rows 0-44 as zeros for now.

**For step 2:** with off-screen pieces dropped (the blitter draws none of
them: the torii approaching from the right), a buffer holds at most 13
pieces above the cut in level 1, and 1 in level 2 (`topcheck.py`, still
identical).

### Steps 2-5: the top rows as objects, built (2026-09-30)
**The pieces:** `layout7800.TOP_PIECES` lists the placements the logs saw.
Level 1 (scenes 1 and 6) has 31:
- the gate structure's five pieces;
- the torii's five, normal and mirrored;
- the posts' two pieces at rows 37-43, normal and mirrored.

Level 2 has 2: the gate building and its doors. The build reads each
image's header from the scene's ROM and makes a global table, one array a
field (`TOP_SRCLO` ... `TOP_Z2`). Each piece's rows above 45 get a column
for each 15-row zone they cross, in pages `$40-$4E` (row r at page `$4E` −
r mod 15, bytes 16-174): level 1 needs 159 bytes a page, level 2 needs 36.

**Each buffer's pieces:** fixed arrays (`TOPLI`, `TOPLX`, `TOPLK0`,
`TOPLK1`: piece, left pixel's low byte, first and end byte kept; A's
entries 0-15, B's 16-31), a count and the top's background colour
(`TOPLN`, `TOPLBG`). The capture rules are those `topcheck.py` checked:
- `TopCapture` (from `BlitBank`) adds a piece, unless it is wholly off the
  screen, and takes out pieces wholly under it;
- `TopErase` (from `RowBase`) runs for fills, with the rectangle fill
  recognised by its return address; it removes the pieces a fill covers,
  trims those covered from one side on whole bytes, and a fill over the
  whole top sets the background;
- `TopClear` and `TopCopy` (from `ClearBuf` and `CopyBuf`) empty and copy
  the lists.

Any change makes that buffer's display list stale, so it is built again
when next shown.

**The top zones' lists:** `TopEmit` gives each piece with rows in the zone
an object reading its slice, with the high byte of the zone's last row's
page. They go in 6 slots a buffer (page tails `$40-$4B`), or the empty
list when no piece is there.

**Loading:** at each scene load, `TopLoad` clears the columns and copies
the pieces' rows from the scene's ROM. Mirrored pieces go through the
mirrored blitter's own byte table (`$2BC0`). Level 1's are converted:
colours 0 and 2 swapped, `x ^ ((~x & $55) << 1)`.

**The sky:** when a buffer's top background is the sky (colour 2), its
list gets two DLIs of the port's own, counted among the game's (the NMI
recognises them by their number in the frame, `S_NMIPD1/2`, and handles
them first: `STA WSYNC`, then the background colour):
- sky on: the blank run before the top region gets a flagged last line;
- sky off: row 44 is a zone of its own, flagged.

If the sky-off DLI cannot be placed, neither is used. Every frame
`TopColours` makes the top band's colours as the game's colour set 0 does
(`$1125`: scheme `$0F0C`, tables `$1197`/`$119D`, less the fade `$0F12`).
That gives the sky's colour for the DLI, and palette 2 for the converted
pieces: colours 1 and 3 the band's, colour 2 black. Palette 2 was unused.
The unused `S_M8COPY`, `S_M8B` and `S_M8Y` gave their 32 bytes of system
variables to these.

**ROM, where everything went** (the fixed bank was the limit):
- **Scene-0/4 code into banks 0 and 4:** the story's and title's far
  pieces (`TitleZone`, `StoryLocate`, `StoryPatch`, `EndText`) are only
  ever run in scenes 0 and 4, with their scene page in. A new kind of far
  piece, `;;; FAR04`, places them where banks 0 and 4 are both free, the
  same bytes in each. `TitleBits` moved to the main block: every zone asks
  it, in every scene. `TitleMark` stayed fixed: no room in both. That gave
  the fixed bank 475 bytes.
- **Far pieces in two passes,** so one may use another's labels (every
  reference between them is an absolute address above `$8000`). And they
  may now sit before the main block too (`$E07F-$E0D9`, left by bank 15's
  shrinking).
- **The top code into the art bank** (bank 6), behind fixed stubs that
  select it meanwhile, as a blit's source does, with `S_BANK` kept true
  for the NMI. `;;; FARART` pieces:
  - `TopHelp`, `TopCapture`, `TopErase`, `TopClearCopy`, `TopEmit`,
    `TopLoad`, `TopColours` and the tables;
  - `TopLoad` reads the images through a fixed helper (`TopRowRead`) that
    selects the scene page for each row.
- **Scratch kept apart:** `TopEmit` runs in the NMI, maybe inside
  `TopCapture`, so it has scratch of its own (`S_E*`). The main program's
  indirect calls use `S_TTMP`; the NMI's colour call has its own stub.

Now the fixed bank has 393 bytes free and the art bank 142.

**A harness:** `probes/farcheck.py` assembles each far piece on its own,
to find its own errors (a branch out of range) before the build.

### The top rows as objects: checked (2026-09-30)
Both builds' invincible-easy carts, the scripted player, a screenshot
every 2 flips (`playkey.lua SNAPK=`). The builds keep step by flips, so the
same flip is the same moment.

**Results:**
- **Level 1** (601 pictures: the torii crossing both ways, the gate
  structure, the posts, the sky): every top identical to the stable
  build's.
- **Level 2** (601: the doors, the gate building): identical apart from the
  status bar.
- **The gate fight, scene 6** (176): all identical.
- The status-bar differences (99 in level 1, 33 in level 2) are all the
  player's arrows. The stable build shows them where this build shows
  none, after a full clear the game follows with only the foe's: the stable
  build's arrow cache, as at the ending ("The story's patched lists
  overran"). This build's status rows matched the original's at every
  flip ("The status bar as objects: checked").
- `regress.sh` (now from row 45 down, `fbcompare.py --from-row 45`): 13 of
  13 byte for byte.
- The free-RAM check: 0 writes in all six scenes.
- The story, every frame from 800 to 2000: every picture one the stable
  build shows.
- **The ending,** jumping at the same flip on both builds
  (`p7800-jumpto.lua` now takes `ATFLIP=`; a frame jumps at different
  game moments in two builds): the same pictures in the same order, apart
  from 2-3 single frames at the room's clear. The ending clears the buffer
  on screen, so those frames show it part cleared, and the two builds
  clear in different orders. The final text is identical.

**The sky's switch lines:**
- **The first attempt** wrote the background after one line end
  (`STA WSYNC`): both changes came a line early.
- **Two line ends:** still a line early.
- **Three line ends:** the sky turned on right but off a line late. Row
  44's DMA (its pieces) and the blank line's (none) halt the CPU for
  different times, so a write after `WSYNC` lands at different points.
- **The fix: both switch lines opaque.** The blank line before the top
  shows two 20-byte objects of colour 2 in palette 2 (black). The top's
  last row shows the same in palette 1 (sky) under its pieces. A
  background change anywhere within those lines doesn't show. Both use
  one 20-byte run of `$AA` (`TOPSKYROW`, set at the scene's load); the
  handlers wait two line ends. On the hardware the margin is that line
  either way.

**ROM after:** the fixed bank has about 270 bytes free, the art bank about
175. The zones' column tables (`TOP_Z0-2`) moved to the fixed bank when
the art bank ran out.

**For the cleanup (now unused):**
- `ObjBlankM`: far pieces can call each other now;
- `Mode8`'s `RTS` stub and the `M8NIB` tables (removed: "The top rows'
  flicker");
- `MODE8_ROWS`' 120 bytes of console RAM;
- the `DL_M8` lists (removed: "The top rows' flicker").

### The top rows' flicker (2026-10-01)
**The report (hardware):** a lot of momentary flicker in the buffer region
when the game slows down, on the top-cut build.

**The cause: a full list rebuild at almost every flip.**
- Every change to a buffer's top pieces (`TopStale`) threw away that
  buffer's whole display list, so `BuildDll` built it again as the
  buffer was next shown.
- The rebuild runs in the game's vertical blank, and takes most of a
  frame (fights in level 1: 225-250 lines).
- While it runs, the game's DLIs are dropped (a DLI during the vertical
  blank is dropped by design: "Drawing below the screen"). So for that
  frame the buffer region's colour changes don't happen.
- Before the top cut, the list was rebuilt only when the game switched
  lists.

**What drives the changes in a fight:** the game erases some top pieces
and draws them again in every picture (`probes/p7800-topstale.lua`, level
1's fight, 800 frames: 142 deletes, 146 captures, 146 erase overlaps).
The list comes out the same, but each round marked it changed. While
walking, the torii really do change in every picture.

**Measured** (`probes/p7800-buildtime.lua`: the scripted player, 8000
frames; "late" = a build still running when MARIA leaves the vertical
blank; drops = game DLIs lost in the vertical blank):

| Build | Level 1 builds | late | frames with drops | Level 2 builds | late | frames with drops |
|---|---|---|---|---|---|---|
| Before the top cut | 226 | 26 | 42 | 230 | 26 | 40 |
| Top cut | 329 | 127 | 141 | 522 | 316 | 328 |
| Fixed | 229 | 29 | 41 | 232 | 28 | 38 |

**The fix:**
- **A change marks, not rebuilds.** `TopStale` sets the buffer's mark
  (`TOPLD`). Only a change of the top's background (`TopBgSet`, the sky)
  still rebuilds the list, since that moves the sky's DLIs. It rebuilds
  only when the colour actually changes.
- **Each top zone keeps its slot, even when empty** (an empty list).
  Each slot records its zone's first row and height (`TOPDL_ARG`, after
  its longest list). So its list can be written again without the DLL
  changing.
- **`TopRefresh` writes the marked buffer's top-zone lists again** from
  the recorded zones.
- **It runs at the flip, in the main program.** `$B60F`'s first
  instruction (`LDA $0AFE`, same size: bank 15 has no room) is now `JSR
  SysTopFlip`. That refreshes the buffer just drawn (`$07`), before
  `$B60F` toggles `$0F0A`, then does the load; its RTS leaves the flags.
  The frame routine keeps out meanwhile (`S_BUSY`), as it would build
  with the same scratch. X, Y and `$00/$01` are kept.
- **The first try ran the refresh in the vertical blank** (`FrameGo`, as
  the buffer is shown). It was much cheaper than a rebuild, but still
  ran past the game's first DLI: one DLI lost at every flip in a fight.
  `FrameGo` still refreshes a marked buffer, for a flip `$B60F` didn't
  see; in the runs that was 2 a scene (its first picture).
- **The refresh's loop counter is its own (`S_ER`).** It can run in the
  NMI while `TopCapture` uses `S_TJ`.

**Checked:**
- No top zone without a slot. Lists have at most 6 top zones: level 1
  `0+15 15+15 30+7 37+1 38+6 44+1`, level 2 `18+12 30+6 36+1 37+1 38+7`
  (`probes/p7800-topzones.lua`).
- The invincible-easy screenshots every 2 flips (levels 1 and 2, 601
  each) and every 4 (the gate fight, 176): identical to the top-cut
  build's. The gate fight's are also identical to the stable build's.
- `regress.sh` 13 of 13; the free-RAM check 0 writes in all six scenes.
- **Speed** (frames from picture 300 to 800, the scripted player):

| | Before the top cut | Top cut | Fixed |
|---|---|---|---|
| Level 1 | 6,301 | 6,078 | 6,031 |
| Level 2 | 6,133 | 5,970 | 5,840 |

**ROM:** the fixed bank was short for the hook. Removed:
- the mode-8 widening tables (`M8NIB`, 32 bytes), `Mode8` and Apply's
  call to it;
- the three mode-8 row lists in the boot image (`DL_M8`);
- `S_PM8`'s and `S_PIDX`'s stores (the variables stay, for the cleanup).

`TopRefresh` is a FARART piece of its own (the art bank's gaps were too
small for it inside `TopEmit`'s). `TOP_FLAGS` moved to the fixed bank.
Now the system block has 99 bytes free to engine1.

**Probe notes:**
- A tap on an art-bank address must check `S_BANK` (6). Other banks run
  code at the same addresses: a first count of top zones without a slot
  (65) was that.
- `M.time` read inside a tap is coarse (the timeslice's), so the build
  lengths in `buildtime.log` are only rough. The late counts read MSTAT's
  vertical-blank bit.

## ROM room: what the scene pages duplicate (2026-10-01)
The user: more ROM room is needed (for the fighters as objects); could the
cutscenes run in the page where gameplay already holds their assets?

**The banks' overlap** (`probes/bankoverlap.py`: bytes identical at the
same offset, in runs of 16 or more / found anywhere in the other bank):

| Scenes | Data banks | Code banks |
|---|---|---|
| 1 and 6 (level 1, the gate fight) | 7,835 / 7,976 of 8,192 | 8,185 / 8,185 |
| 0 and 1 (the intro, level 1) | 3,791 / 4,231 | 5,332 / 5,803 |
| 0 and 6 | 3,770 / 4,088 | 5,325 / 5,796 |
| 2 and 3 | 749 / 1,848 | 6,770 / 7,316 |
| any other pair (data) | 0-1,089 | |

(The code banks' wide overlap between all scenes is the game's shared
code at the same offsets in each.)

**The gate fight is level 1 with features switched off.** Its banks are
copies of level 1's, patched by the original's developers:
- **The code bank:** 7 bytes at `$24A5`, the frame-wait counts read
  from `$0AF9`/`$0AFA` instead of `$0AFC`/`$0AFD`.
- **The data bank:** about 40 sites, all in `$7000-$7FFF` (the scene's
  own code), 357 bytes. Mostly `NOP`s over level-1 code (`$7368`: four
  `INC`s; `$7A8F`: `JSR $6C30`) and branches pointed past code
  (`$7A5A-$7A74`: six branches to `$7A76`). The largest, `$771F-$77D5`
  (183 bytes), is the scene's start-up: the same stores with the gate
  fight's own values.

On the 7800 they are two 16K pages, banks 1 and 5, almost byte for byte
the same.

**The intro (scene 0)** holds about 4K of level 1's data (the demo
fight's level-1 pieces, the mountain) at the same offsets. Its own
cutscene sprites are not copies: the intro's (1,247 bytes) and the
finale's Mariko (594) are each held once, in the art bank.

**The 40 sites** (`probes/scenediff.py`, written to
`work/analysis/scenediff-1-6.txt`; the user: the vs fight mode is a
non-scrolling section of level 1). By kind:
- **Skipped in the vs fight** (`NOP`s over level 1's code): about 20 sites.
  `INC`/`DEC $52`, `$51`, `$62`, `$72`, `$91`; `STA $46`/`$47` (five
  times); `JSR $6D0C` (three times), `$7260`, `$7090`, `$6C30`; a `BEQ`; a
  `JMP`.
- **Level-1 constants:** `#$0B` (the vs fight `#$01`) at `$7007`, `$7293`,
  `$73C9`, `$7CB6`; `#$0B` / `#$00` at `$7B76`; `#$3C` / `#$05` at
  `$7936`; `#$00` / `#$01` at `$7999`.
- **Other exits:** `JMP $2E03` / `JMP $7700` (`$7855`); `JMP $2E00` /
  `JMP $7850` (`$7A03`); `JSR $B9A0` / `JMP $7850` (`$79E1`); `LDA $44 /
  BNE` / `JMP $7850` (`$786C`); a branch at `$795E`.
- **Two branch groups** (`$7A5A-$7A74`, `$7A9F-$7AB9`): six branches each,
  all sent to the group's end in the vs fight.
- **The start-up** (`$771F`, entered from `$7703`): rearranged, with the
  vs fight's own values (`$52 = $22`, `$62 = 5`, `$72 = $22`, ...).
- **Other addresses:** `STA $0AF7` / `$0AF4` (`$79ED`); `STY $06BD` /
  `$06B9` (`$7C49`); `JSR $AB00` / `JSR $0976` (`$797A`); and engine
  part 2's `$24A5-$24AB` (`$0AFC`/`$0AFD` / `$0AF9`/`$0AFA`), already per
  scene (each page holds its 7 bytes, copied at load).
- **Data:** one entry of each of the sprite-pointer tables `$7603` (entry
  24: `$7A` / `$BA`) and `$7663` (entry 23: `$7F` / `$BF`), read by
  `$7683`; and `$7FE7`, the scene's identity byte (1 / 6; 0 on the
  title), which the vertical-blank button routine (`$0FA2`) reads.

**For a shared page:**
- The vs fight writes `$D0 = 1` and plays on without reloading ("Select,
  scene 6"), so a shared page can't tell the modes apart by `$D0`. It
  needs a flag of its own, set by the loader.
- Level 1's page (bank 1) has 204 bytes free, but its scene code area
  holds the code bank's leftover copies of other scenes' sprites (about
  2K that no level-1 code draws: "The sprite tables walked") and the
  death sprites (265 bytes, read only from their RAM copy).

## The vs fight in level 1's page (2026-10-01)
Built: the vs fight (scene 6) runs in level 1's page (bank 1), and **bank
5 is free** (16K; 77 bytes of it now hold the boot's static display lists,
below). Checkpoint before: `2026-10-01_KEEP_enh-before-vsmerge`.

**How** (`layout7800.py`, "the vs fight in level 1's page"):
- **The mode:** `S_VS` (`$80` in the vs fight). The loader sets it at the
  end of a scene's load: `LoadSceneDone` → the scene page's `ScVsSetup`,
  which only in level 1's page goes on to `VsSetup` (level-1 page code). The
  game's `$D0` can't tell the modes apart, because the vs fight writes 1
  there and plays on.
- **The sites:** each of the 40 is a same-size `JSR` or `JMP` into a
  helper (`VsJ6D0C`, `VsJ22`, ...). The helper tests `S_VS` inside `PHP` /
  `BIT S_VS` / `PLP`, so the registers and flags come out as the original
  instructions would leave them. Two-byte sites take a neighbouring
  instruction along. The branch groups' vs form re-runs the same tests to
  the group's end (`_chain`).
- **The helpers' home:** scene code `$12C8-$1587` (page `$82C8-$8587`,
  704 bytes, 646 used). It held scenes 2-4's sprites, never drawn in level
  1; level 1's code map has no instruction, label or relocation there. The
  helpers' labels pass from the scene-code chunk to the scene-data chunk
  through the linker (`link7800.EXPORTS`).
- **Level 1's constant `$0B`** (the vs fight's `$01`, at four sites):
  zero-page `$FF`, the only free zero-page byte (the map leaves no other),
  set by `VsSetup`.
- **The start-up** is level 1's, with four hooks: six stores moved, other
  values, two more stores.
  - **Correction:** the first version took the six stores (`$10`, `$50`,
    `$AD`, `$AE`, `$5D`, `$5E`) to be skipped in the vs fight. They are
    skipped only from the `$7703` entry. From `$7700`, the set-up at
    `$7706` falls into them with A = 1, before `JSR $B000`. Without them
    the player stood in the walking pose (`VsJ1F`, `VsJ03` now).
- **The identity byte `$7FE7`** (1 level 1, 6 the vs fight, 0 the title)
  is read by the vertical blank's button routine (`$0FA2`: if 6, `JSR
  $0900`, the vs fight's per-frame step) and by bank 15's console code
  (`$A75E`, `$AF4E`, `$AF5A`, `$AFB6`, `$B5B2`).
  - **The first fix replaced only `$0FA2`.** The fight then diverged at
    flip 192: bank 15's `$AF4E` (if 6, `$F7 = $80`) still read level 1's
    page.
  - **Now every read** is `LDA S_SCID`, in all scenes, and the loader
    copies the page's byte to `S_SCID` (`VsSetup` sets 6). This is also
    the move "Drawing below the screen" suggested: the vertical blank no
    longer reads the window, which a blit may have switched to the art
    bank.
- **The engine's frame-wait counters** (`$24A5`, `$0AFC`/`$0AFD` against
  `$0AF9`/`$0AFA`): `VsSetup` writes the vs fight's two bytes over level
  1's after the load.
- **The build:** `PAGE_SCENES` (the scenes that own a page) for every
  per-page placement. A scene in another's page must need no display list
  or carve that page lacks (checked). The kit's patch sites are listed
  once per bank.

**ROM:** the fixed bank ran short twice on the way. Fixes:
- `VsSetup` went into level 1's page code, and the "is this level 1's
  page" test into the scene-page code (`VsSetupSp`).
- `ObjBlankM` removed (far pieces call each other directly now).
- The boot's static display lists (the empty list and the blank DLL, 77
  bytes) moved from the system block to the spare bank (`SPARE_BANK` 5,
  at `$8000`; Reset selects it for the copy).

The system block now has 165 bytes free; level 1's page has 149.

**Checked:**
- Every site holds its replacement (the built page read back).
- The invincible-easy screenshots: level 1 (601), level 2 (601) and the
  vs fight (176), identical to the build before.
- **The game's zero page at every flip** (`playkey.lua ZPFROM=0`, `$FF`
  left out) identical to the build before:
  - 1,500 flips of the vs fight on the invincible-easy cart;
  - 2,500 on the normal cart.
- `regress.sh` 13 of 13; the free-RAM check 0 writes in all six scenes.
- **Which vs paths the runs reached** (`probes/p7800-pcbank.lua`, each
  helper's vs branch):
  - **Reached:** the per-frame ones (the skipped calls `$6D0C`, `$7260`,
    `$7090`; the branch groups; `$7934`, `$795A`, `$79AA`, `$7999`,
    `$797A`, `$7B74`) and the start-up's.
  - **Not reached** (checked against the vs fight's bytes by hand):
    - the exits on losing (`VsJ17`, `VsJ18`, `VsJ30`, `Vs28`);
    - the `$7703` entry;
    - the scrolling code (`VsInc5`, `VsInc6`, `Vs10`, `VsDec4`);
    - `VsJ16`, `VsJ33b`, `Vs38`, `VsLo`, `VsRow`, `VsJ6C30`.

**Comparing by frames doesn't work across builds.** The BIOS's signature
check takes a time that depends on the ROM, so two builds' power-on frames
are offset (the BIOS's own logo frames differ). MAME's `a7800` has no BIOS
to skip (`-listbios`: the retail and the prototype ones). The user
suggested skipping it; the probe-side equivalent: `p7800-snaprange.lua`
counts frames from the cartridge's `Reset` instead.
- **Aligned that way, the two builds' title and story** (frames 300-1,500
  after `Reset`, a picture every frame) are identical frame for frame,
  1,201 of 1,201.
- **Counted from power-on instead:** four windows of the attract sequence
  match as sets, every new picture one the old build shows, except the last
  2-5 of a window: the offset at the window's end.

## The fighters as objects: measured (2026-10-01)
The user: with bank 5 free, should the fighting frames be loaded there;
Akuma in his fight keeps to the other fighters' lines (he is bigger only in
the cutscenes), so in fights only the hawk is an exception. A measurement
pass, no code changes:
- `probes/xe-bandlog.lua`: the original's every blit and fill, with its
  picture, shift (`$10`), mode (`$0F`: 0 OR, negative AND, else store),
  buffer and caller.
- `probes/bandana.py`: the analysis.
- `p7800-drawprof.lua`: the port's drawing time.

Runs: the scripted player, 16,000 frames each, scenes 1-4 and 6 (scene 4's
player stands in the doorway, so no Akuma fight there).

**What a fighter is:** 4-5 art-bank parts a picture, each a mask (AND) and
a sprite (OR):
- legs `$A857`/`$A863`, head `$A887`/`$A891` (bank 15);
- the torso from each level's part routines (`$7A53-$7AC7`; level 2 adds
  `$7B5C-$7BA0`, level 3 `$7AEB-$7B39`);
- the guard's are the same, mirrored (`$A8DF-$A91D`).

The parts' pixel shifts differ within a fighter (body 1, head 5), so they
are not byte-aligned to each other. Other art-bank callers: the hawk
(`$B533`, `$B580`), Mariko (scene 4 `$7AF9-$7B57`), the doorways
(`$B866-$B88E`), and level 3's door frames scrolling in (`$7116-$7132`,
rows 48-145: scenery).

**The band:** the actors (fighters, hawk, Mariko) cover buffer rows
**79-128 in every scene measured**, the user's observation. The hawk
didn't fly below row 79 in these runs; the inventory has it from 75.

**Per picture with actors** (avg / 95% / max):

| scene | parts | part bytes (separate objects) | composed boxes (bytes) | groups | wipes (fill bytes) | other writes into the band |
|---|---|---|---|---|---|---|
| 1 | 11 / 13 / 16 | 539 / 773 / 1,182 | 433 / 590 / 840 | 2 / 4 / 5 | 1,013 / 1,122 / 2,750 | 933 / 1,668 / 2,304 |
| 2 | 11 / 13 / 16 | 518 / 678 / 1,096 | 430 / 590 / 840 | 3 / 4 / 5 | 1,028 / 1,122 / 2,516 | 1,011 / 1,982 / 2,306 |
| 3 | 10 / 13 / 15 | 514 / 673 / 1,071 | 415 / 588 / 840 | 3 / 5 / 6 | 997 / 1,330 / 2,750 | 902 / 1,668 / 2,425 |
| 4 (Mariko) | 9 / 10 / 10 | 275 | 245 | 1 / 2 | 1,111 | 894 |
| 6 (vs) | 12 / 12 / 14 | 523 / 608 / 702 | 459 / 514 / 604 | 3 / 3 / 6 | 1,017 / 1,585 / 3,900 | 246 |

**ROM:** the art bank's 141 images (7,372 bytes, masks included) plus
mirrored copies of the 122 drawn mirrored (6,545) make **13,917 bytes**.
That fits bank 5 (16,307 free) with about 2.4K to spare. The
bytes are already MARIA's 160A layout (the port shows the XEGS
framebuffer's bytes as they are).

**Time** (`p7800-drawprof.lua` on the port, its largest entries):

| | drawing a picture | the fighters' blits | wipes (fills, patterns) | the rest |
|---|---|---|---|---|
| the vs fight | 109,500 cycles | about 70,000 | about 14,500 | about 22,500 |
| level 1 (walking and fights) | 95,800 | about 32,000 | about 14,600 | about 24,000 |

Copying about 500-600 bytes of parts a picture from ROM costs about
6-8,000 cycles with the lists. **In fights, drawing would drop from about
110,000 cycles a picture to about 35,000.**

**RAM is the open question.**
- Removing the fighters doesn't free the band's bitmap. The band still
  changes for scenery while walking (about 900-1,000 bytes a picture in
  levels 1-3), so it stays double-buffered.
- **The sprite RAM** (the shown picture's and the next's) is about 1-1.5K
  on average and up to about 2.8K: 1.4K a buffer at most.
- **MARIA can't read the frames in bank 5 during the picture:** the window
  holds the scene page, whose code is running. So they must be copied to
  RAM.

## The RAM census (2026-10-01)
For the fighters' sprite RAM ("The fighters as objects: measured": about
1-1.5K, up to 2.8K, for the shown picture and the next).

**How:** `probes/p7800-ramcensus.lua` marks every address of console RAM
(`$1800-$27FF`) and cart RAM (`$4000-$7FFF`) written after the boot's
clear; `probes/ramcensus.py` merges runs and lists what no run wrote.
13 runs:
- the attract loop, no input;
- scenes 1-4 and 6 with the scripted player, on both the normal and the
  invincible-easy carts;
- the invincible-easy recording replayed on the current cart (60,000
  frames);
- the ending (`ALSO=p7800-jumpto.lua`, jumping to scene 4's `$784E`).

A second pass logged reads of the candidates (`READS=`).

**Two probe lessons:**
- The 6502's indexed stores (`STA abs,X`, `STA (zp),Y`) make a dummy read
  of their target, and MAME makes it too. The boot's clear loop "read" all
  of RAM until the probe ignored reads by the clear loop's own code.
- The remaining reads of never-written bytes are of the same kind (the
  copy loop, the fast fill's indexed stores, `FpPatched`, `FillPat`),
  plus about six a run by MARIA (logged with a PC in the fixed bank's
  sprite data). Those touch `$1B00-$1B7F` and `$1F00-$1F3F`: to trace
  before use.

**Never written, in runs of 8 or more: 3,177 bytes.** By kind:
- **Console RAM, free** (each run within one or two pages):
  - `$2038-$21FF`, 456: after the top rows' scratch;
  - `$1AA1-$1B7F`, 223: after the common bank's carves;
  - `$1ED8-$1F7F`, 168: past the clip row; holds the old mode-8 rows'
    120 and the ledger's 8;
  - `$1A09-$1A7F`, 119: after the death sprites;
  - smaller: `$1852-$187F` 46, `$182B-$184D` 35, `$27CD-$27FF` 51,
    `$2761-$277F` 31, `$1812-$181F` 14, `$1DF6-$1DFF` 10.

  About 1,150 bytes in all.
- **Headroom of lists that can grow:**
  - the DLLs' tails (`$22A2-$22FF`, `$23A2-$23FF`, 94 each; a DLL may
    reach 85 entries, 255 bytes);
  - the zone lists' tails (`$248C-$24FF`, `$258C-$25FF`, 116 each);
  - the top-row slots' tails (26-66 bytes in each of `$40-$4B`).

  Free only up to the build's static maximum, still to be computed.
- **Cart RAM page heads,** offsets 0-15 of pages `$4B-$72` (40 pages,
  640 bytes), and 10-15 of `$44-$4A` (42): the ledger's, confirmed.
- **Pages `$4F` and `$50`, offsets `$69-$FF`** (151 each): no buffer row
  lands there.
- `TOPLX`/`TOPLK1`'s tails (32 each), `TOPLD`'s neighbours (10), the
  bytes after `TOPBLACKDL` (34).

**The catch is shape.** MARIA reads a zone's line L from page `hi + (H-1-L)`
at one offset, so a 16-line zone's graphics take one offset in 16
consecutive pages: a column. The console RAM that is free is single-page
runs, usable for lists, variables and code but not for multi-line
graphics. The column-shaped free RAM:
- **the page heads:** 16 bytes across 40 consecutive pages (`$4B-$72`),
  640 bytes;
- the 151 bytes in pages `$4F`/`$50` (two pages only).

That holds about one buffer's average fighter parts, not two, nor the peaks.

### The RAM census: gameplay against the rest (2026-10-01)
The user: is there RAM only the text and attract modes use that would make
a difference? Gameplay is what matters.

**How:** `probes/p7800-ramcensus2.lua` tags each write by the scene page in
the window: gameplay (`S_SCENEBANK` 1-4: levels 1-3, the vs fight, the
finale with its ending text, which errs safe) or the rest (scene 0's
title, story, intro cutscene and demo, and the boot).
- **Pass 1, writes:** the same 13 runs as "The RAM census".
- **Pass 2, gameplay's reads of what pass 1 found free:** six runs.
  - **Correction:** the first try tapped reads on all of RAM and ran at
    about 1/100 speed (1,200 frames in two hours, stopped at the limit).
    Reads are now tapped only on the candidates (`READS=`).

`probes/ramcensus2.py` merges them.

**Free during gameplay** (gameplay neither writes nor reads it): **4,211
bytes**.
- **The title, story and demo use 959 of them,** almost all in console RAM:
  - the small-sprite block's area (`$1B80-$1DE7`, the text's glyphs): 
    copied in at boot, read by the title and story, and never read in
    gameplay;
  - some of the story's patched-list slots (pages `$42-$45`).
- **Read in gameplay after all,** of what pass 1 found: 24 bytes at `$1F00`
  (the display reads noted before) and 74 in `$2761-$27FF` (the fast
  fill's tail and the static lists).
- **The largest runs:** `$1AA0-$1DFF` (about 840, mostly the sprite block
  and its neighbours), `$2038-$21FF` 456, `$4EEE-$510F` 546, `$1A09-$1A7F`
  119, `$1F18-$1F7F` 104, the display lists' tails (94-126 each).

**Column-shaped** (the same offsets free in consecutive pages: what a
multi-line zone's graphics need):
- **16-line zones:** 844 bytes. The page heads `$00-$0F` of pages
  `$4B-$72` (640), and offsets `$F0-$FB` of `$40-$50` (204).
- **8-line zones:** 1,096 bytes. The heads (640), and offsets `$D6-$FB`
  of `$40-$4B` (456). That block is the top-row slots' tails: headroom a
  slot can grow into (a slot's list reaches 74 bytes), so not free.

**Answer:** the text and attract modes' own RAM is about 1K, and it is
console RAM in single-page runs. That is fine for lists, variables and
code, but the fighters' graphics need columns. The column-shaped RAM free
in gameplay stays about 640-850 bytes, against about 1.8-2.8K for two
copies of the fighters' parts. It doesn't change the picture.

## Rows 45-78 as objects: the costed plan (2026-10-01)
The user: the background is very samey; apart from the stationary
mountain (levels 1-3) and the leftmost and rightmost portions, the only
visibly moving things in the middle are the columns. Do the scenery as
patchwork. Rows 45-78 freed in every scene give back the framebuffers'
first page-striped column (offsets 16-55 for A, 136-175 for B, across the
34 framebuffer pages): **2,720 bytes of column-shaped RAM**, what the
fighters' graphics need ("The RAM census").

### What the scenes draw there
**From the draws** (`probes/xe-bandlog.lua`, now with clears `C`, buffer
copies `K` and fill colours; `probes/upperana.py`, only what is drawn
while the run's own scene is loaded):

| Scene | Distinct images | What |
|---|---|---|
| Level 1 | 30, 1,289 bytes | the posts (stacks of 2×2 and 2×1 pieces, 10 positions); the fence rails (`$6A11` 8×2 at every even column, once a room; `$6A31`/`$6A23` 12×1, plain and mirrored); the wall top (rows 77-78); the mountain (2 images, once a room); edge fills |
| Level 2 | 17, 1,723 | the wall line pieces (22×1, 17-25 columns); the mountain; the gate building's doors; the door frames at the edges (art bank, mirrored) |
| Level 3 | 13, 1,728 | the door frames scrolling in; a column 92 rows × 10 bytes (`$6000`, rows 51-142, at 13 positions: it reaches into the fighters' band) |
| Finale | 6, 558 | the door frames at both edges, redrawn every picture |
| Vs fight | 22, 1,065 | level 1's, still; its post redrawn every picture (about 17 pieces) |

**Copying the game's pieces one for one doesn't work.** `probes/upperplan.py`
kept each buffer's pieces by the top rows' capture rules:
- Level 1 came to about 420 objects a picture, 107 on a line (worst 179),
  far past MARIA's time.
- **Part of that is the rails:** many small pieces on one row, up to about
  49 objects on row 65.
- **The rest is a model error:** while walking, the game erases a post in
  several fills, and the rule "a fill takes out what it covers wholly" kept
  them. Tracking each piece's rows helped little; most covers are partial
  in width (the posts sit at pixel shifts, the fills on whole bytes). The
  capture rules for this scenery will need checking against the buffers,
  as `topcheck.py` did for the top rows.
- Level 2's static parts (about 80-100 objects, 100 on a line) are too
  many as well; levels 3, 4 and the vs fight would fit.

**From the finished pictures** (`probes/rowana.py`: the original's
framebuffers every 5 flips, both buffers, only dumps in the run's own
scene; levels 2 and 3 with `xe-easy.lua` through `probes/xe-cheatplay.lua`,
since the scripted player dies there and a death goes back to level 1).
Each row is split into its best repeating pattern (the background) and
the runs of bytes it doesn't match (the rest, one object each):

| Scene | Rows 45-78 | Rest objects a line (avg / 95% / max) | MARIA, worst line | Rest objects a picture |
|---|---|---|---|---|
| Level 1 | 45-64 sky (uniform `$AA`, 65-90% of the time), the rest the mountain, posts and torii; 65-69 and 73-76 a 12-byte pattern (48 pixels: the fence) whose phase changes as the screen scrolls; 70-72 and 77-78 black | 2 / 4 / 9 | 76 | 55 / 84 / 108 |
| Level 2 | 45-54 and 57-66 an 8-byte pattern (the wall, scrolling); 55-56 and 67-78 black | 2 / 5 / 7 | 68 | 68 / 87 / 110 |
| Level 3 | black, but rows 57-58 (a 15-byte pattern); the rest the door frames and columns | 2 / 4 / 4 | 56 | 60 / 66 / 84 |
| Finale | black; the door frames | 3 / 4 / 9 | 15 | 105 |
| Vs fight | level 1's, still | 2 / 4 / 9 | 76 | 70 / 70 / 92 |

(MARIA's time counts the background as objects of 8-byte tiles plus the
rest. The tile and rest-run data totals it prints count every pixel shift
and phase apart: upper bounds, not needs.)

### The plan
**What shows rows 45-78:**
- **Uniform rows: the background colour.** Level 1's sky goes on to row
  64, with the port's sky DLIs moved down. The black rows need nothing.
- **Repeating rows: a tile strip.** A few objects (24 bytes, 2-3 periods,
  each), all reading one stored tile per row, placed by the pattern's
  phase. Level 1's fence: 9 rows × 24 bytes. Level 2's wall: 20 rows × 24
  bytes. One copy per level, loaded with the scene.
- **The rest as objects, one a piece:** the mountain, the posts, the door
  frames, level 3's columns and the torii's lower parts. Pieces are placed
  by the pixel, so each image is stored once, unshifted.
- **The mechanism:** the top rows' capture, extended down: the game's draws
  above `FB_TOP` captured, `FB_TOP` moved down, lists per buffer.
  - **New:** a run of one image drawn at successive columns (rails, wall
    lines) becomes a tile strip at the run's phase, not one object a
    piece.
  - **New:** erasing by several partial fills, to be modelled as the
    buffers show it (checked as `topcheck.py` did).

**Steps, top down, every scene at each step** (so each gives RAM back):
1. **Rows 45-64:** sky, wall rows, the mountain, the posts' and frames'
   upper parts. The colour bands change after row 64 in levels 2-4, so the
   step ends on a zone boundary there. Gives back 20 rows × 80 = 1,600
   bytes.
2. **Rows 65-78:** the fence and the wall's last rows, black rows, the rest
   of the frames and posts. Gives back 14 × 80 = 1,120 bytes, and `FB_TOP`
   reaches 79, the fighters' band.

**Costs:**
- **MARIA:** the worst line about 76 cycles of 113.
- **RAM:**
  - each level's scenery data (tiles and pieces in zone columns) about
    0.3-1K, once, not per buffer;
  - lists about 60-110 objects a picture, about 300-500 bytes a buffer, in
    console RAM (4.2K is free in gameplay).
- **Net column RAM after both steps:** 2,720 − about 1K + the page heads'
  640 = **about 2.3K**, against the fighters' 1.8-2.8K (two copies). Enough
  for the average; the worst pictures need either fewer bytes (a part's
  mask and sprite in one object) or a fallback for those pictures.
- **CPU:** the scenery's blits and fills above row 79 stop (the vs fight's
  post alone is about 17 blits a picture), and its lists cost less than
  that drawing.

**Still open:**
- the phase of the scrolling patterns from the captured draws (or the
  game's scroll state);
- the erase model;
- level 3's tall column below row 78, which stays in the bitmap until the
  band is converted.

### Step 1 (rows 45-64): the open questions settled (2026-10-01)
**Erasing while walking (level 1):** each picture the game fills columns
28-39, rows 0-68, with the sky (`$6FCC`, colour `$AA`), then draws the torii
coming in at the right edge one step further on (`$6763`, the post
`$685F` stack, `$6684`, `$6703`; shifts 7 → 1 → 5 between pictures). That is
the top rows' own case: a region fill wipes the pieces, blits add them.
- **Correction to `upperplan.py`'s count:** its partial covers came mostly
  from pieces hanging off the right edge (columns 40-41, shift 7), whose
  off-screen pixels no fill covers. The top rows' code clips pieces to the
  screen first (`TopVis`), so the capture rules hold here as they are.

**Level 2's wall doesn't scroll in rows 45-64.** It is drawn once a room:
- colour bands by fills: `$AA` rows 46-54 and 58-66, `$FF` single lines at
  rows 45 and 57 (`$72BA`, `$72C5`, `$72D6`, `$7B31`);
- 1-byte, 22-row joint pieces every 8 columns (`$64F0`, `$64D8`, plain and
  mirrored, by `$7303`/`$72FD`), starting at a column that varies by room
  (−7, 1, 9, ...): the "8-byte pattern" with its phase.

Afterwards each picture only columns 0-8 (the gate building's side) are
erased and redrawn (`$708B`, `$6546` at column 8). The scrolling pattern
(the fence, rows 65-76) is step 2's.

**Scene 0** (the attract loop, `bl-s0`), in rows 45-64:
- the intro cutscene's door frames at both edges (art bank `$9600`,
  `$964A`, `$96CE`, `$9980`, by bank 15 `$B866-$B980`), each picture;
- the mountain once;
- **the title's big letters** (`$7C00`, `$7C82`, `$7CEC`, `$7D75`, `$7E0D`,
  by `$7911`, rows 29-64). These are drawn at boot and on returning to the
  title (also seen in level 1's run then). The title is objects already
  (`SysTitleLogo`), so the top cut lost nothing there.

### Step 1: the design
- **The mechanism:** the top rows' capture, its rows to 64, `FB_TOP` 65.
  Each scene's pieces in rows 45-64 join its piece table: level 1 and the
  vs fight's torii parts, posts and mountain; level 2's joints, mountain
  and door frames; level 3's frames and column tops; the finale's frames;
  scene 0's frames and mountain. The zone grid continues: 45-59, 60-64.
- **Uniform areas as fill pieces:** a fill of colour c is kept like a
  piece. It is shown as objects reading a short stored run of that colour's
  byte (5 objects of 8 bytes cover a line: about 41 cycles), not by more
  background-colour DLIs (the sky's showed how touchy their timing is).
  Level 1's sky stays the background colour, its off-switch moved from row
  44 to 64.
- **RAM:** with `FB_TOP` at 65 the buffers take 27 pages (`$58-$72`)
  instead of 34, which frees pages `$4F-$57` whole (9 × 240 = 2,160 bytes),
  next to the top data's pages `$40-$4E`. Level 1's top data already fills
  its 159 bytes a page there, so:
  - the top data grows into the freed pages (a 15-page grid block,
    offsets 16-255);
  - the single-page users there (the top zones' list slots, 12 × 80, and
    the piece lists) move to console RAM free in gameplay ("The RAM
    census: gameplay against the rest": the story's and title's areas are
    free while a level plays, and these lists are used only then).

  Also added: the uniform runs (about 128 bytes a colour).
- **Checks:** pictures against the stable build (every 2 flips, all
  scenes); `topcheck.py`-style piece checks against the buffers; regress
  from the new `FB_TOP`; free-RAM; hardware.

### Step 1, stage A: the top rows' machinery moved to bank 5 (2026-10-01)
Checkpoint before: `2026-10-01_KEEP_enh-before-step1`.
- **The move:** the FARART pieces (`TopCapture`, `TopErase`, `TopEmit`,
  `TopLoad`, `TopRefresh`, `TopColours`, the helpers) and every `TOP_`
  table now live in bank 5 (`TOP_BANK` = `SPARE_BANK`). Their stubs and
  `TopRowRead` select it. They read only RAM and their own tables, so they
  need no scene page in the window.
- **The tables come home:** `TOP_Z0-2`, `TOP_FLAGS` and `TOPSCN`, squeezed
  into the fixed bank earlier, are back with their code.
- **ROM after:** bank 5 holds 2,170 bytes (the boot's static lists
  included); the art bank is back to its own contents (14,344); the fixed
  bank gained about 150 bytes.
- **Checked:** the invincible-easy screenshots, levels 1 and 2 (601 each)
  and the vs fight (176), identical to the build before.

### Step 1: the capture model per zone, and level 2's wall (2026-10-01)
`upperplan.py` with the pieces clipped to the screen as the top rows' code
does (rows 0-64, the 15-row zone grid; most objects in one picture /
on one line / in one zone):

| Scene | objects | on a line | in a zone | MARIA, worst line |
|---|---|---|---|---|
| 0 (attract) | 8 | 8 | 8 (rows 30-74) | 44 |
| 1 | 26 | 6 | 14 (45-59) | 22 |
| 2 | **81** | **79** | **81** (45-59) | **242** |
| 3 | 9 | 9 | 9 | 81 |
| 4 | 6 | 4 | 4 | 14 |
| 6 | 11 | 3 | 6 | 16 |

**Correction: level 2's wall scrolls** (not "drawn once a room", the
earlier reading from the first pictures only).
- While walking, each picture draws the joints (`$64F0`, 1 byte × 22 rows)
  at a pixel position one or two further on (x 56, 57, 58, 60, ... in one
  picture's list). It doesn't erase the old ones.
- The blitter keeps the pixels around an image's own, so an old joint's
  one leftover pixel column stays in the bitmap, the wall's colour, and
  doesn't show.
- As captured pieces those old joints stay as objects: 81 in one zone.
- **So level 2's rows 45-66 need step 2's tile strip now:** a few objects
  reading one stored 32-pixel tile of the wall (its colour bands, its
  lines and a joint), placed by the latest joint's position. The gate
  building's side (columns 0-8, cleared black and redrawn each picture)
  trims the strip there, as the top rows trim a piece a fill covers from
  one side.

### Step 1: the rest of the inventory, and the layout (2026-10-01)
**"the end"** (levels 1-3, after the player dies, on a cleared screen): the
common text routine `$07BF` draws five glyphs from the small-sprite block
(`$0614` t, `$0522` h, `$04D8` e twice, `$0588` n, `$04C2` d, 10 × 2 each)
at row 56, columns 14-23. In rows 45-64, so captured pieces too: six objects
in one zone.

**Some pieces are in the art bank:** the door frames (`$9600`, `$964A`,
`$96CE`, `$9980`) in levels 2-4 and scene 0. Loading their rows needs the
art bank in (`TopRowRead` reads the scene page now).

**The posts need one object a post, not a piece.**
- A MARIA object costs its time on every line of its zone, not only on its
  own rows. (`upperplan.py`'s "on a line" counted only a piece's own rows,
  so it understates. Per zone: level 1 at most 14 objects in rows 45-59,
  about 56 cycles a line.)
- Every stacked piece also needs its own data column: level 1's posts alone
  (`$6684` at 10 rows, `$6703`, `$685F`, plain and mirrored) would want
  about 80 bytes a page more, past the 239 the pages have with its 159.
- **The port already draws level 1's posts and pillars with its column
  routine** (`ScColA`/`ScCol68`, which replaced the game's 13-byte column
  loops: "The tiny sprites are columns"). That is where a whole post can be
  captured as one piece: one object a zone, one data column of the
  repeated image.

**The layout** (`FB_TOP` 45 → 65 directly, scenes converted one after
another on internal builds; no cart to the user until all are):
- **The buffers:** `FB_BAND` 34 → 27 pages (`$58-$72`), freeing pages
  `$4F-$57`.
- **The top data:** keeps its 15-row grid (rows 0-64 = grid zones 0-4) in
  pages `$40-$4E`, data offsets 16-254 instead of 16-174.
- **The zone list slots:** to `$4F-$56`, three 80-byte slots a page, 12 a
  buffer (6 before).
- **The pieces' lists** (`TOPLI` and the rest): to console RAM free in
  every mode (`$2038-$21FF`), 32 pieces a buffer (16 before).
- **Scenes 0 and 4:** their story, title and ending text reuse some of
  these pages. The top data gets a valid flag, cleared by the text's
  set-up; a capture reloads it, and a zone shows nothing while it is
  invalid.

### The RAM census: correction (2026-10-01)
**Console RAM `$2040-$20FF` is zero page `$40-$FF`, and `$2140-$21FF` is
the stack page `$140-$1FF`:** the 7800 mirrors them. MAME's taps are per
address, so writes made through zero page or the stack never showed at
`$20xx`/`$21xx`, and the census called `$2038-$21FF` (456 bytes) free.
Only `$2038-$203F` and `$2100-$213F` of it are.
- **Found the hard way:** step 1 first put the top pieces' lists at
  `$2040-$214F`. Each list write changed the game's zero page (`$50`, the
  scroll's shift, became `$23`), the blitter then indexed its shift table
  out of range and jumped into the art bank, and level 1 crashed at flip
  247.
- **The census probes should tap the mirrors** (`$0040-$00FF`,
  `$0140-$01FF`) as `$2040-$20FF`, `$2140-$21FF`. Their other results stand.

### Step 1, stage B: level 1 and the vs fight (2026-10-01)
**The layout:**
- `FB_TOP` 65; the buffers in pages `$58-$72` (`FB_BAND` 27).
- The top data in pages `$40-$4E`, offsets 16-254 (level 1 uses 224
  bytes a page).
- The zone list slots in `$4F-$56`, three 80-byte slots a page, 12 a
  buffer (`TopNextSlot`).
- The lists in page `$57`: `TOPLI`, `TOPLX`, `TOPLK0`, `TOPLK1`, 2 × 28
  each, then the counts.
- `TOPROW`, `TOPSKYROW` and `TOPBLACKDL` at `$1F18-$1F45` (the old mode-8
  rows).
- **The last top zone is cut at `FB_TOP`** (rows 60-64): `RowsZoneTop`
  clamps it, since 65 isn't on the 15-row grid.

**The machinery, generalised:**
- five zones' data columns (`TOP_Z0-4`, `S_TZ`);
- pieces in the art bank (`TOP_FLAGS` `$20`: `TopRowRead` loads them with
  the art bank in);
- the pieces' tables given XEGS addresses, which the build relocates per
  scene.

**Columns:** the level-1 column routine (`ColA`, and `ColC` for its
mirrored loop) captures the whole column above the cut as one piece
(`TopColumnF` → `TopCapCol`; `TOP_FLAGS` `$10` plus the image's height,
loaded repeated to the cut). The column's own pieces then aren't captured
(`S_TCOL`).
- **The column's first piece** is drawn by the game before the loop the
  routine replaced, so its top is `$06` − 35 on entry. The first try took
  `$06` + 2, matched nothing, and the posts went missing.
- **A slip:** `ColC` first stored its entry A as the limit, but `Col68`
  enters it with `$52` in A. The column loop then ran on, and level 1 hung
  at flip 478.

**Level 1's pieces above row 65:** the posts and pillars as columns
(`$6684`, `$6703` from row 37, `$685F` from 55, plain and mirrored;
`$6000` at 64), the mountain (`$6948` at 46, `$6976` at 57), and `$6038`
(at 54), beside the top rows' own.

**Erasing a piece in part, in rows only** (FINDINGS "Step 1: the vertical
erase", the rule): the build lists each piece byte's first and last rows
with a visible pixel (`TOP_NTI`, `TOP_NTLO`/`HI`). A fill covering some of
a piece's rows takes it away if it spans its kept width and every kept
byte shows only in those rows. Over the piece's left or right edge, the
bytes it spans are trimmed off one by one while each shows only there.
- **The case:** the gate (`$60A8`, 13 bytes, rows 42-53, drawn at x 108).
  The game erases column 27, rows 49-50, every picture (`$6FAB`); then the
  sky fill (columns 28-39) trims the gate to its first byte. That byte's
  only visible pixels are in rows 49-50, so the bitmap shows nothing of it.
  Without the rule it stayed as an object and showed a 2-pixel speck in
  431 of 601 pictures.
- **Checked against the bitmap:** the stable build's draws (`p7800-toplog.lua`
  `TOPCUT=65 DUMPTOP=1`) replayed by `topcheck.py` (cut 65; it now skips
  images the asset logs lack). All 40 partial covers in level 1 are this
  gate.

**Checked:** the invincible-easy screenshots against the build before.
- **The vs fight:** 176 of 176 identical.
- **Level 1:** 582 of 601 identical. The other 19 are level 2's opening
  picture (the run goes on into level 2, not converted yet).

### Step 1: level 3's pillar and door frames, one object each (2026-10-01)
**The ghosting:** with level 3's pieces captured (`_T3`: the door frames,
the pillar `$6000`, "the end"), 100 of 601 pictures differed from the
build before step 1, all at the left edge.
- **The pillar** (`$6000`, 92 rows × 10 bytes, from row 51) is drawn by
  level 3's `$7006` at column `$52` (0 or `$F4-$FF`: the room's left edge)
  with the shift `$50`. `$7046` first fills its old place's right part
  (columns `($E1+7)&$FE`, 5 wide, rows 51 down), and the new draw covers the
  rest: in the bitmap its black pixels erase.
- **As objects** black is transparent, and the fill isn't on whole bytes
  of a piece drawn with a shift, so the capture kept the old entry whole
  (`TopErase`: "not on whole bytes"). The old pillar showed through the
  new one.
- **The door frames** (bank 15 `$B8E8`, object X: image `$B815/$B820,X`,
  column `$B82B,X − $E0 + $52`, line `$B836,X`, shift `$50`; level 3's
  `$710C`/`$7128` draw X 0-4, and 5 when `$84` is 5) move the same way.

**The rule:** these are single objects in the game's own terms (one per
routine object), so a draw of one replaces its earlier places. A piece
marked `"one"` in `TOP_PIECES` gets `TOP_FLAGS` `$08` (never with a
column's `$10`); `TopCapture` then takes the piece's earlier entries out of
the buffer's list (`TopOne`) before adding the new one. This is done at
the capture rather than by patching `$7006` and `$B8E8`: the same effect,
with no patch sites in the scene or bank 15.

**Checked:** invincible-easy screenshots against the build before step 1.
- **Level 3:** 601 of 601 identical (100 differed before).
- **Level 1:** 582 of 601, as before (the 19 are level 2's opening).
- **The vs fight, the finale:** 176 of 176 each.

### Step 1: level 2's wall (2026-10-01)
**Correction to "the capture model per zone, and level 2's wall":** the wall
is a window strip (blue panes, black joints with a white line, the distant
mountain through it), and its joints are not left behind. Each walking
picture the game:
1. paints the wall over the old joints (`$64F0`, 22 × 1: the wall's own
   colours) at their old places;
2. fills the gate building's side (columns 0-7) black and the wall's bands
   there again (`$72BA` `$AA` rows 46-54, `$72C5` rows 58-66, `$72D6` and
   `$7B31` `$FF` rows 45 and 57);
3. draws the mountain through the panes (`$6592`, `$65B8`, at fixed columns);
4. draws the joints one step on (`$64D8`), plain at the left and mirrored
   (`$2B82`) at the right;
5. draws the gate building (`$6602`) and its black edge (`$6546`).

A room's first picture does the bands across the whole width after a clear.

**Opaque objects:** the blitter's store mode is opaque, so the joints' and the
gate's black pixels erase the wall. As MARIA objects colour 0 is
transparent. Every level 2 piece lacks colour 1 or colour 2, so its black
moves to the colour it lacks, in a palette where that colour is black
(`TOP_CONVERT[2]` `"opaque"`):
- no colour 2 (the gate, its edge, the joints): colours 0 and 2 swapped,
  palette 2 (level 1's converted palette: game colour 1, black, game colour 3);
- no colour 1 (the mountain, the door frames): colours 0 and 1 swapped, palette
  3 (`TOP_PAL2`: black, game colours 2 and 3; set by `TopColours` each frame).

`TopLoad` tells the two swaps apart by the piece's palette.

**New piece kinds** (`TOP_FLAGS`, a piece not a column):
- **`"fill"` (`$02`):** the wall. Its row-46 `$AA` fill stands for the whole
  wall (rows 45-66: the bands, the black rows 55-56 as colour 1) over the
  fill's columns, in entries of 20 bytes (`TOP_FILLP`, its rows' bytes in
  the top bank). `TopFillAdd` runs after a fill's erase; the other three
  band fills only erase. A full-width wall is two objects; the gate side
  adds one.
- **`"erase"` (`$04`):** `$64F0`. Its blit isn't kept; the pieces wholly under
  it go (`TopCover`). The first try used the fill's erase rule, which trims
  whole bytes. The joints sit at pixel shifts, so it trimmed a byte off the
  wall's right half each picture, until the wall was gone (picture 216 on).
- **`"one"` (`$08`):** the gate, its edge, the mountain, the door frames.

**The mirrored blit's other entry:** `$2B82` (mirrored, its column the left
byte's) besides `$2B8B` (the right byte's). `TopCapture` knew only `$2B8B`,
so the right-hand joints were missing. It now tells `$284E`, `$2B82` and
`$2B8B` apart by their returns' low bytes (the build checks they differ);
`S_TRAL` says which way the column counts.

**Also:**
- **A zone's list slot holds 17 objects and the end** (its zone byte at
  `TOPDL_ARG`). `TopEmit` now leaves out any past that instead of writing
  over it.
- **The visible-row tables reached 296 entries**, past a byte index. Pieces
  whose runs are the same (the door frames and "the end" in several
  scenes) now share them.

**Level 2 at most:** about 14 objects in rows 45-59 (wall 3, mountain 2,
joints 6, gate, edge, `$6274`), 160 bytes a page of top data.

**Checked:** level 2, 601 of 601 identical to the build before step 1.

### Step 1: scene 0, and level 1's cutscene (2026-10-01)
**Level 1's page has a cutscene:** Akuma in his room, between levels 1 and 2
(`$D0` 1), with the door frames at both edges (bank 15's `$B866-$B980`).
- Level 1's top data has 16 bytes a page free, and the door frames need
  about 21.
- They're never on screen with level 1's scenery.

So a scene can have **another set of pieces** (`TOP_ALT`), in the same
columns.
- `TopLoad` loads one set (`S_TSET`, `TopLoadSet`).
- `TopCapture` matches pieces from both (`S_TN` counts both). A piece from the
  set not loaded loads that set first (`TopSwitch`: both lists emptied, the
  blit's state and the game's `$00-$03` kept).
- The door frames as level 1's other set are drawn as they are, on the
  cutscene's black (`"raw"`), not with level 1's sky conversion. The first
  try converted them: the posts' grey (colour 2) went transparent.

**Scene 0 (the attract loop):**
- **The title and the story** put their data in the top pages (the story's
  glyphs and patched lists in `$40-$5F`, the title's canvases in
  `$47-$66`). The story already turned the tops off (`StoryInit`); the title
  now does too (`TitleMark`).
- **When either ends at a full clear** (`ObjEnd`, now carry set), `ClearBuf`
  loads the scene's pieces again (`ClearTopLoad`, keeping the registers and
  `$00-$03`). A scene load does it anyway.
- **The cutscenes:** the door frames (the other set, raw).
- **The demo fight:** level 1's scenery, by scene 0's own copy of level 1's
  code (the torii, the mountain, the posts, on the sky: level 1's
  conversion).
  - **The build before step 1 showed it wrong:** black above row 45, since
    scene 0 had no top pieces. MAME's XEGS goes to a blank purple screen
    where the demo would start, so the original's log stops there (501
    pictures).
  - **Scene 0's posts are drawn by the game's own column loops.** The port's
    column routine lives only in level 1's banks, it is about 530 bytes, and
    bank 0 has 182 free. So a post is a **chained column** (`"chain"`,
    `TOP_FLAGS` `$18` plus the rows): the blit of its first piece (row 37,
    or 55) captures the whole column to the cut. The pieces below match no
    entry and are ignored. A column's image may have up to 7 rows now
    (level 1's have 2).

**Checked:**
- **Level 1:** 601 of 601 identical, the cutscene included (19 differed
  before: its door frames' tops were missing).
- **The attract loop (800 pictures):** identical to the build before step 1
  except the demo's pictures, which now show the sky, torii and posts the
  stable port shows. The stable port runs out of step with it from picture
  268 on, so the demo was checked by eye.

### Step 1: a flip shown a frame late (2026-10-01)
**The glitch:** a screenshot of every frame (`probes/p7800-showdraw.lua`,
`probes/frameana.py`) found frames with both fighters missing. Level 2,
flips 470-530: 2 in the build before level 2's work, 4 after. The display
was still on the buffer the game had started redrawing.

**The cause** (`probes/p7800-flipapply.lua`):
- The game's flip (`$B60F`) toggles the buffers and waits for `$0AF6`, which
  its vertical blank clears (`$0F66`).
- Later in the same vertical blank it sets the new list (`$0F87`, `$0F93`:
  `SetDlist`, `Frame`).
- On some flips that came at line 25-28 after the frame's end, past MARIA's
  vertical blank. `FramePend` still applied the list at once, because it
  was inside the vertical-blank handler. MARIA had already read DPPH/DPPL,
  so the new list showed a frame late, while the game had resumed.

**The fix:**
- `FramePend` applies a list only while MARIA is in vertical blank (`MSTAT`).
  Past it, the list stays pending for the next blank's `Apply`.
- If the game was waiting for its flip when the blank began (`S_VWAIT`), and
  its handler left a list pending, `NmiVbiDone` sets `$0AF6` again
  (`G_L0AF6`). The game then waits one frame more, until its picture is on
  screen.

**After:** no such frame in flips 470-530; all scenes' pictures as before.
- **The build before step 1** shows frames with a fighter partly missing
  (2 in level 2's flips 470-530), likely the same race.
- **The stable port** has the same `Frame` code, but showed no such frame in level 2's flips 400-700 ("RAM and fixed ROM: the inventory").

**Also:**
- The build's scene groups were ordered by the lists' object ids, so the
  `TOP_` tables' order could change between builds. They are now ordered by
  scene.
- `port/regress.sh` compares from `FB_TOP`, not row 45.
- **Regress:** all 13 dumps byte-identical from row 65 down.
- **Freecheck:** no writes in any scene.

## RAM and fixed ROM: the inventory (2026-10-02)
The user: free RAM or fixed ROM first; is there anything copied into RAM
once that could live in bank 5 instead? No code changes here, only the
inventory. The build now writes each bank's map beside the cartridge
(`work/karateka7800.map`: what was placed where).

**The limit:** MARIA and the game's code can't see bank 5 during a picture,
since the scene page holds the window. What they read mid-picture must be
in RAM or the fixed bank. Bank 5 can hold:
- images copied at a load;
- code that runs behind a stub selecting it, reading only RAM and its own
  tables.

### The fixed bank (16,090 of 16,384 bytes used)
| What | Bytes |
|---|---|
| The game's bank 15 (`$C000-$E07E`) | 8,319 |
| The system code and tables (`$E0DA-$F1AC`) | 4,307 |
| Scene-code sprite copies (`$1200`, `$1530`, `$1600`, `$16FE`, `$18BF`, `$1C80`, `$1F00`, `$1FD7`, `$0B12`) | 1,854 |
| Engine part 1 (read-only) | 515 |
| Far system code (top-row stubs, `RowBase`, `TopSky`, title marks, `ObjEnd`, `CopyFill`) | 812 |
| The TIA sound's tables (`SND_*`) | 278 |

The system code's largest routines, and what they read besides RAM and
the fixed bank:

| Routine(s) | Bytes | Reads |
|---|---|---|
| The display-list builder (`BuildDll`, `FrameCheck`, `RowsZoneEmit`, `RowsZoneH`, `BuildBlankRun`, `BuildRowsZone`, `BuildM8Run`, `BlankZones`, `PutEntry`, ...) | about 1,100 | the scene page's `DLT_*` and `SP_NDL` (a few dozen bytes a scene); calls the story's and title's scene-page code |
| The story (`StoryInit`, `StoryStep`, `StoryEmit`, ...) | about 680 | the scene's strings and glyph tables (`G_STORY*`, `G_GLY*`, `G_ADV*`) |
| The title (`TitleLayout`, `TitleEmit`) | about 400 | its images through pointers (scene 0's page) |
| `TiaSound`, `Sound` | 256 (+278 tables) | RAM (the POKEY shadows); `Sound` calls the game's sound code |
| `Reset` (the boot) | 226 | the spare bank's static lists (at boot, any bank can be in) |
| `CopyBuf`, `ClearBuf` | 323 | RAM only |
| `LoadScene` and the copies | about 400 | the banks it copies from: stays fixed |
| The NMI, `Apply`, `Inputs`, `BlitBank` | about 450 | stays fixed |

**Movable to bank 5 behind stubs** (as the top rows' code was):
- RAM-only now: sound, boot, input, the buffer clear and copy. About 1,100
  bytes with the sound tables.
- The builder, once its scene-page tables are copied to RAM at the load,
  and with its story and title calls through stubs. About 1,100.

**The sprite copies (1,854)** can go to the art bank's `$A000-$BFFF` free
space through the scene pages' page map, as `ART_COPIES` already does for
scenes 0 and 4. That needs room in the art bank, below.

### Engine part 2 (3,328 bytes, cart RAM `$7300-$7FFF`)
It is copied there at every scene load. Its writers on the 7800
(`probes/p7800-e2writes.lua`, all scenes, the load's own copy left out):

| Page | What gets written |
|---|---|
| `$73` (XEGS `$23`) | nothing; no code runs there; only `$2312-$2373` is read (the original's census) |
| `$74` | the variables `$7409-$7421` (25 bytes, by engines 1 and 2); the scene's 7 bytes `$74A5-$74AB` at each load |
| `$75-$77` | nothing |
| `$78-$7B` | the blitter's own operands (`$78FA-$7B11`): self-modifying |
| `$7C` | `$7CCC`, by `$7DA8` (self-modifying) |
| `$7D` | `$7D1A-$7D27` by the port's fast fill (`FpPatch0`), `$7DA1` by `RowBase` (`$FF28`): the port's patches |
| `$7E-$7F` | nothing (the original's `$2E09-$2E0D` writes don't happen in the port) |

So pages `$73` and `$75-$77` are read-only, and so are `$7E-$7F`.
- **Moved to the fixed bank as whole pages** (as engine part 1 was),
  `$74` follows with its variables carved out to RAM (as engine 1's save
  slot) and its scene bytes handled per scene.
- **The RAM part** is then pages `$78-$7D`, or `$78-$7B` if the three
  patched spots are reworked.
- **Placed at the top of cart RAM**, that frees 7-9 consecutive pages next
  to the buffers (1.8-2.3K), the column-shaped RAM the fighters need. It
  costs 7-9 pages of fixed ROM, page-aligned.

### Bank 6 (the art bank: 14,344 used, 2,040 free)
4.3K of it is images copied at loads, which could live in bank 5:
- engine part 2, 3,328 (less if part of it moves to the fixed bank);
- the fast fill, 353;
- the small-sprite block, 630.

Moved, the art bank has about 6.3K free: room for the fixed bank's sprite
copies (1,854), or for most of the fighters' mirrored frames (6,545), not
both. Bank 5 has 11,666 free.

### Console RAM
- **The small-sprite block** (616 bytes at `$1B80`, copied at load): in
  gameplay only "the end" uses it (five glyphs, about 100 bytes). Copied in
  only for the title and story, about 500 bytes are free in gameplay. That
  room could take the piece lists out of page `$57`, and more.
- **The top rows' zone list slots** (`$4F-$56`, 12 × 80 bytes a buffer,
  1,920): the busiest zone seen uses about 56 bytes of its 76.

### Also checked
The stable port and the new build, level 2's flips 400-700, every frame:
no frame with the fighters missing in either.

### RAM and fixed ROM: steps 1 and 2 (2026-10-02)
**Step 1: the images copied at loads moved to bank 5** (`IMG_BANK`): engine
part 2 (`$A000`), the small-sprite block (`$AD00`) and the fast fill's code
(`$AF76`). `LoadCommon` and `LoadScene` select that bank for their copies.
The art bank went from 14,344 bytes used to 10,033; bank 5 from 4,718 to
9,029.

**Step 2: the scene-code sprite copies moved from the fixed bank to the art
bank.**
- Read there through the scenes' page maps, as `ART_COPIES` already were. A
  `SPRITE_COPIES` entry below `$C000` is now in the art bank; the health
  arrows (19 bytes) stay in the fixed bank.
- **The fixed bank went from 16,090 bytes used to 14,255: 2,129 free.**

The constraints:
- **The copies keep their offsets in the page** (the relocation moves only
  high bytes).
- **A page a scene sends to the art bank must hold none of its own blit
  sources.** `OWN_SPRITE_PAGES` lists them per scene: the runs' images, the
  table walk's, Akuma's finale pieces, and the port's own blits
  (`probes/p7800-blitpages.lua`). The build now refuses a map that would
  hide one.
- **Bank 15's table at `$B826-$B82A`** (scenery objects 6-10: `$1200`,
  `$12C8`, `$14BE`, `$18BF`, `$18D0`) is the same in every scene. Those
  copies are mapped in all four scenes that draw them (0, 2, 3, 4). `$18BF`
  is now listed for scene 0 too, which draws it through that table (the
  build checks its bytes are the same). The table at `$BE6E` is read
  through each scene page's own copy (`SCENE_TABLES`).
- **A first layout broke scene 0's demo:** its sprite pages came from the
  original's runs, which never reach the demo (MAME's XEGS stops there).
  The port's blits show the demo drawing from `$A3-$AC`, where scene 0's
  two copies had been moved. Scene 0's own pages are `$A1-$AC`, `$B2`,
  `$B3`, `$BB-$BF`.
- **The layout** (a search for a byte-exact packing):

| Copy | Scenes | Art bank |
|---|---|---|
| `$1200-$1523` | 0, 2, 3, 4 | `$B700-$BA23` (the only 4 pages all four leave free) |
| `$18BF-$18D7` | 0, 2, 3, 4 | `$BABF-$BAD7` |
| `$16FE-$18A1` | 2, 3 | `$B0FE-$B2A1` |
| `$1600-$16FD` | 2, 3, 4 | `$B300-$B3FD` |
| `$1530-$15B2` | 3, 4 | `$B430-$B4B2` |
| `$1C80-$1CF9`, `$1F00-$1F28` | 4 | `$A280`, `$A200` |
| `$1FD7-$1FFC` | 4 | `$B2D7` |
| scene 0's `$1530-$18D7`, `$1CC4-$1DFA` | 0 | `$AD30-$B0D7`, `$B4C4-$B5FA` |
| scene 4's `$1F29`, `$16FE` (unchanged) | 4 | `$BB29`, `$BCFE` |

- **The pages mapped now:**
  - scene 0: `$AD-$B0`, `$B4`, `$B5`, `$B7-$BA`;
  - scenes 2 and 3: `$B0-$B3` (and `$B4` in 3), `$B7-$BA`;
  - scene 4: `$A2`, `$B2-$B4`, `$B7-$BE`.

  These are the scenes' code and text pages (scene 4's `$A2`: the ending's
  code and strings), and no sprite pointer the table walk found lands in
  them.

**Checked:**
- **`port/checkall.sh`** (new: builds, then every scene's pictures against
  its reference): all identical, after each step.
- **The recording `test-karateka7800-invincible-easy-0929-2309`**, a
  screenshot every 50 frames to 19,000, on the builds before and after
  step 2: 380 of 380 identical. It falls out of step with the game on
  these builds (made on an older one) and stays in level 2, so it doesn't
  reach the finale.

### RAM and fixed ROM: step 4, engine part 2 split (2026-10-02)
Checkpoint before: `2026-10-02_KEEP_enh-before-engine-split`.

**Engine part 2 is four page-aligned modules** in the original, each
opening with a jump table and padded at its end:

| Module | Pages | What | Writes |
|---|---|---|---|
| data | `$23` | read by module A | none |
| A | `$24-$27` | sound | its variables `$2409-$2421`; two operands set per scene |
| B | `$28-$2D` | blitters and fills | its own operands |
| C | `$2E-$2F` | | `$2E09-$2E0D` |

A first plan cut between `$24` and `$25`, but a routine runs across that
seam. The split follows the modules instead.

**Now:**
- **The data page and modules A and C are in the fixed bank** (`$F800`,
  `$F900-$FCFF`, `$FD00-$FEFF`).
- **Module B is in cart RAM at `$7A00-$7FFF`**, copied at each scene load
  from bank 5.
- **Cart RAM `$7300-$79FF` (1,792 bytes, seven consecutive pages next to
  the buffers) is free**, and in the free-RAM ledger.
- The health arrows' copy moved to `$FF12` to make room. The fixed bank is
  at 16,084 of 16,384.

**What made it work:**
- **The bytes written outside module B are carved to RAM** (`CARVE_ENGINE2`,
  zeroed at each scene load as the original's copy did): the sound's
  variables (`$1A09`) and `$2E09-$2E0D` (`$1A22`). They are reached only by
  absolute operands (the linker checks for split references).
  - **Found the hard way:** module C keeps the vertical blank's vector there
    while it swaps it. My write probe on the engine's RAM started at frame
    1,500 and missed it; the original's census had it. In ROM the save was
    lost, the restore wrote `$0000`, and level 1 crashed at its first
    vertical blank in play (flip 191).
  - `probes/p7800-romwrites.lua` now checks from frame 0 that nothing writes
    the ROM modules: none, in every scene.
- **The vs fight's two operands** (its frame-wait counters `$0AF9/$0AFA`
  where level 1's are `$0AFC/$0AFD`) were patched into RAM by `VsSetup`. Now
  `$24A4` and `$24AA` are `JSR SysFwLo`/`SysFwHi`, which choose by `S_VS`.
- **`RowBase` told blitters from fills by the caller's page**, with a
  literal `CMP #$7C` (blitters `$78-$7B`, fills `$7C-$7D`). With module B at
  `$7A00` the mirrored blitter's return (`$7CA1`) read as a fill. Its blits
  then took the fill path, erasing top pieces and leaving stray bytes
  (`$E8` at offsets `$34`/`$5C` of every buffer page).
  - Found by bisecting module by module, then a write watch on a stray byte
    (PC `$7B27`, the blitter's store), then the caller check.
  - It now compares with the fills' first page, `>G_L2C00`.

**Checked:**
- `port/checkall.sh`: every scene identical to its reference.
- `port/regress.sh`: all 13 dumps byte-identical.
- `port/freecheck.sh`: no writes to the free RAM, the new run included.
- No writes to the ROM modules.
- The recording against the build with module B at `$7800`: 377 of 380
  identical. The other 3 are the BIOS logo and the title fading in, whose
  timing varies with the ROM image.

### RAM and fixed ROM: step 3, the clear, copy and sound in bank 5 (2026-10-02)
The user: the goal is room in the fixed bank and/or RAM for the fighters'
animations used everywhere.

**Moved to the top bank** (`;;; FARART` pieces):
- the game's full clear and buffer copy (`ClearBuf`, `CopyBuf`, `ClearTopLoad`);
- the TIA sound (`TiaSound`) and its tables (`SND_*`).

**Their stubs, in the fixed bank:**
- `ClearBufF`, `CopyBufF` (`StubIn`/`StubOut`): the caller's bank is kept in
  `S_STUBBK`, and A and the flags come back as the routine left them.
- `TiaSoundF`: the NMI's, which keeps the bank on the stack, as
  `TopColoursF` does.
- `FwLo`/`FwHi` stay in the fixed bank, since the engine's sound module calls
  them.

**The fixed bank went from 16,084 bytes used to 15,343: 1,041 free.**

**Checked:**
- **`port/checkall.sh`:** every scene identical.
- **The sound:** the TIA writes (`probes/p7800-tialog.lua`) and the game's
  POKEY shadow writes, level 1, 8,000 frames, by flip.
  - Two builds with the same code and different ROMs: identical.
  - This build against the one before: 76 of about 1,800 lines differ.
- **That is timing, not the conversion.** The port samples the POKEY shadow
  once a frame (`TiaSound` in the NMI), and the game's sound commands come
  from both its main program and its vertical blank, so a change in either's
  cycles moves some sound events by a frame. Two controls built from this
  source show it:
  - the sound back in the fixed bank, called directly: 18 lines differ
    (from the clear and copy stubs alone);
  - that, plus 38 cycles of `NOP`s where the stub's cost is: 75 lines.

  Any change to the CPU's timing does this. It shows as a sound effect
  starting a frame earlier or later now and then.

### RAM and fixed ROM: step 5, the fills to ROM (2026-10-02)
The fighters' frame data needs as many consecutive pages as the band's zones
have lines (FINDINGS "The fighters as objects: measured"). Seven free pages
(`$73-$79`) are one short of an 8-line zone. The blitter module's last two
pages are the fills (their own jump table at `$2CC0`). Moving them to ROM
makes nine.

**What the fills' pages held that is written:**
- `$2CCC`, the saved `$06` (a variable, not an operand);
- `$2DA1-$2DA3`, the row multiply's operands;
- the port's fast-fill store block at `$2D19`, patched for each block.

**Now:**
- **The two variables are carved to RAM** after the others (`$1A27`,
  `$1A28`; one run that `LoadScene` zeroes).
- **The store block is in the fast fill's own code** in console RAM
  (`FILL_BLK`, `FILL_BPLI`, `FILL_NEXT`; the build checks it stays in one
  page, since `FpGo`'s jump is set by its low byte).
- **The fills' pages are in the fixed bank at `$F600-$F7FF`.**
- **The mirrored blitter's byte table `$2BC0-$2CBF`** runs from the
  blitters' last page into the fills' first, so it is read whole from a copy
  at `$F500` (a `SPRITE_COPIES` entry; its references are absolute indexed
  only).
- **The blitters (`$2800-$2BFF`) are at `$7C00-$7FFF`.**
- **Cart RAM `$7300-$7BFF` is free:** 2,304 bytes, nine consecutive pages,
  in the free-RAM ledger.
- The fixed bank is at 16,117 bytes used.

**`RowBase` tells a blitter by its caller being inside the blitters'
module** (`G_L2800`, `E2_BPAGES` pages). The common code's two calls of
`$2D46` (`$081C`, `$082A`, at `$98xx`) counted as fills under the old page
test, and still do.

**Slips on the way:**
- **`_pg` lost its parentheses:** `and ... or name.startswith("engine2")`
  matched an engine region for any address. The vs fight's helpers' jumps
  into scene data came out wrong (`$6C22` as `$14122`): level 1, the vs
  fight and the demo crashed at the start of play.
- **The new blitter test left the page minus `$7C` in A** before the
  rectangle-fill test that follows it. The fill over the whole top went
  unseen, and level 1's sky was missing.

**Checked:**
- `port/checkall.sh`: every scene identical.
- `port/regress.sh`: 13 of 13 dumps byte-identical.
- `port/freecheck.sh`: clean.
- No writes to the ROM modules (`$F500-$FEFF`) in any scene.

### RAM and fixed ROM: step 3b, the display-list builder in bank 5 (2026-10-02)
**Moved to the top bank** (`;;; FARART (Builder)`): `BuildDll` and its run
and zone routines, through `PutEntry`, and the story's and title's zone
routines (`StoryZoneH`, `StoryEmit`, `TitleEmit`), which end in `PutEntry`.

**What stays in the fixed bank:**
- **`BuildDllF`**, the entry, called by `FrameGo` and `StoryStep`. With the
  scene page in, it copies the list's description into `DESCBUF` (`$1A2C`,
  64 bytes, in the run the census found free; the build checks every
  description fits) and its table entries into `S_DLBUF`/`S_DLLO`/`S_DLHI`.
  Then it runs the builder in bank 5.
- **The builder's four calls into banks 0 and 4** (`StoryLocate`,
  `StoryPatch`, `TitleLocate`, `TitleZoneH`), made through wrappers
  (`...S`, `ScnIn`/`ScnOut`): the scene page in meanwhile, A and the flags
  kept, then back to bank 5.
- `TitleBits`, which both sides call.
- The top-zone stubs still jump back to `RowsEmitEntry` once they have
  restored the caller's bank (now bank 5).

**The fixed bank went from 15,343 bytes used to 15,107: 1,277 free.**

**A slip, and a dead end:**
- **The renaming of the callers to `BuildDllF` also caught `BuildDllF`'s
  own call to the builder.** It called itself, the stack ran out, and
  nothing showed past the BIOS.
- **I first blamed a vertical blank arriving during bank-5 code,** after
  finding the description buffer holding bank 5's bytes, and made `FrameGo`
  select the scene page while it reads its tables. The NMI already does
  that on entry, so that wasn't the cause. The change stays as a guard for a
  main-program caller.

**Checked:**
- `port/checkall.sh`: every scene identical.
- `port/regress.sh`: 13 of 13 byte-identical.
- `port/freecheck.sh`: clean.

## The fighters' parts: masks and colours (2026-10-02)
The user: lower the colour depth for MARIA (grey becomes white, so a part
fits 160A with an opaque black), and keep the upper body's colours if it has
no black. One enemy at a time, always facing left; the player always faces
right; Akuma only in the finale (mostly orange).
- **Tools:** `probes/fighterparts.py` (bank 15's part tables, sprites with
  masks, converted, rendered); `probes/actorparts.py` (the original's draw
  logs by routine and mode); `probes/p7800-blitmodes.lua` (the port's blits
  by image and mode, to replay a 7800 recording on its own cartridge).

**The colours** (palette 1 in level 1's band, from the DLIs' writes):

| Index | Colour |
|---|---|
| 1 | skin `$3A` |
| 2 | grey `$08` below scanline ~158, light blue `$9A` above it (the same pixels look bluish on a fighter's upper half) |
| 3 | white `$0E` |

**How bank 15 draws a fighter** (both use the same images; the enemy
mirrored, `$2C` negative):
- **lower body**, pose X: mask `$A0A8/$A0D2` (AND, at row `$A126`, column
  offset `$A0FC`), drawn first for both fighters from the level's code
  (`$A789` → `$AA58` the player's, `$A786` → `$AA32` the enemy's); later the
  sprite `$A000/$A02A` (OR, row `$A07E`);
- **head**: mask `$A1D9/$A1D6`, then the sprite `$A1CD/$A1CA` (the
  player's) or the enemy type's (`$3E`, `$AA75`: seven sets of three);
- **upper body**: sprite `$A226/$A24C`, OR only, **no mask**;
- poses 6, 7, `$0A-$0D`, `$14-$1D`, `$27`: an extra mask piece (`$9A2A` or
  `$9A18`).

**Correction to my earlier message:** level 1's `$7A53`/`$7A76` are the
lower-body masks (called from the level's code), not torso masks.

**The masks are mostly the shadow under the feet.** In most lower-body
poses many sprite pixels lie outside the mask's box. The sprite's other 0
pixels (between the legs, around the belt) let the background through in
the original too, so as objects they stay transparent. Where the original
ORs colours over a non-black background they mix; objects show the clean
colours.

**Every part, converted** (black inside a mask opaque, grey to white;
boxes as the union of sprite and mask):

| Parts | Count | Bytes | Colours (pixels) | Opaque black |
|---|---|---|---|---|
| lower body | 40 | 4,096 | all four; grey 591 | 1,857 pixels |
| upper body | 37 | 1,895 | 1, 2, 3; no black needed | none |
| head, player | 3 | 32 | all four | 1 pixel |
| head, each enemy type | 3 | 90 | all four; grey 24-35 | 11-16 pixels |

**Akuma** (finale; his pieces in scene 4's data, e.g. `$6862`, `$6966`,
`$6F00`, `$75E4`):
- index 1 (orange in the finale's palette) and white, with 7-12 grey pixels
  a piece;
- drawn with masks too, from the user's recording replayed on its own cart
  (`$A02F-$A1C4`, `$AC21-$AF00`, `$B502-$B5E4` in scene 4's data);
- **open:** some masks hold value 1, which ANDs the background to its low
  bit rather than to black. Their effect needs a look before converting.

**The princess:** a 20-byte mask (`$7AF9`, `$7B10`) and 36-byte sprites
(`$7B28`, `$7B57`), skin, a few grey and white.

**The hawk:** sprites `$942A` 20×5 and `$94E6` 15×4 (brown and white, one
grey pixel); masks `$93AB` 25×5 and `$9490` 21×4, larger than the sprites,
which outline it in black.

**So:**
- **grey to white for the masked parts** (lower body, heads, Akuma, the
  princess, the hawk) frees index 2 for an opaque black in a palette of
  their own;
- **the upper body keeps its four colours as it is**, in the game's palette
  1, so its grey also follows the band's switch to light blue as now;
- **each part converts once, at the build** (sprite and mask merged): about
  6K for the fighters' set, plus Akuma's, all right-facing, in the ROM banks;
- each picture copies only the current parts to RAM, mirroring the enemy's.

### The actors' RAM working set, merged and trimmed per zone (2026-10-02)
The user: per-zone trimming of the merged parts; does it fit the budget?
`probes/workingset.py` replays the original's draw logs (levels 1-3, the vs
fight).
- Each actor's parts are merged (a mask joins the sprite it overlaps most).
- Each part is cut at the band's zones and each slice trimmed to its opaque
  bytes.
- A slice costs its width × its zone's height. An object reads every line
  of its zone, and RAM has no holey DMA, so the lines outside the part must
  hold zeros.

**Bytes a picture (one buffer), one object per part:**

| Band zones | Average | 95% | Max | Objects in a zone (max) |
|---|---|---|---|---|
| 16 lines | 475-598 | 641-764 | 975 | 7 |
| 8 lines | 413-548 | 573-646 | 853 | 6 |

Each actor composed into one object a zone instead: averages 5-15% lower
and at most 3 objects a zone, but maxima up to 1,286 bytes (the union boxes
take in the gaps between parts), and it costs CPU each picture.

**The budget:** two buffers (the shown picture's and the next's), about
1.7K at worst with 8-line zones. Cart RAM `$7300-$7BFF` is 2,304 bytes in
nine consecutive pages, plus the page heads (16 bytes in each of pages
`$4B-$72`).

**8-line zones are needed in the band:**
- **A slice needs as many consecutive pages as its zone has lines.** Nine
  pages hold 8-line zones' slices, not 16-line ones.
- **8-line zones also cut the bytes about 12%** (less padding).

**MARIA's time:** about 6 part objects of about 15 bytes in a zone, next to
the bitmap's 2 objects of 20 bytes, comes to about 60 of a line's 113
cycles.

**Not measured here:** Akuma and the princess (the finale: one enemy and the
princess, no fight elsewhere on screen).

### Keeping colours: heads on the torso, black as its own layer (2026-10-02)
The user: attach a plain head to the torso (which keeps its four colours)
and make the enemies' heads "helmets" without skin, the skin showing through
from the plain head.

**The head goes with the torso.** Both are chosen by the upper body's pose
`$21` (head `$A1A4,X`, placed at `$A1DA,X`/`$A200,X` against the torso's
`$A272,X`/`$A298,X`), so a head can be attached to each torso at a fixed
offset.

**The helmets, measured:** each enemy head (seven types, three poses)
against the player's head as the base, at the game's offset (the enemy's
head 2 rows up and a byte across; `$2C` taken as -1):
- **3-11 pixels of the base** stick outside the enemy's outline (24 for
  type 1, pose 1). The helmet could paint them black, invisible on the
  band's black.
- **0-11 of the enemy's skin pixels** have no skin beneath, and a helmet
  without skin can't make them. So it is close, not exact.

**Exact instead:**
- **The only colour a head lacks in palette 1 is the opaque black.** So the
  head's skin, grey and white go on the torso's object (palette 1, the
  enemy's composed as its parts are copied), and its black pixels (11-16)
  go in a one-colour layer of their own.
- **Exact for the player and every enemy type:** the same object count as a
  separate head, a few bytes more.

**The same split everywhere** (`probes/workingset.py --layers`): every part
as a colour object in palette 1 and a black layer, keeping grey on the legs
too.
- **Bytes a picture, 8-line zones:** average 532-699, max 1,218 (against
  853 with grey made white).
- **Objects in a zone:** up to 9.
- **Two buffers at worst, about 2.4K:** past the nine-page run (2,304), so
  it would lean on the page heads.

**So:**
- heads and torsos keep their colours exactly at no real cost;
- the lower body is the choice: grey made white (fits with room), or its
  own black layer (fits only just, at the worst moments).

### The fighters as objects: decided, and the plan (2026-10-02)
**The user agreed:**
- heads on the torsos with all their colours (palette 1), the heads'
  black as its own one-colour layer;
- the lower body merged with its mask, grey made white (its own black layer
  later, if RAM is freed);
- parts trimmed per zone, 8-line zones in the band;
- the player's parts as drawn, the enemy's mirrored in software as they are
  copied, one enemy at a time; Akuma in the finale only.

**The look:** `probes/renderfighters.py` composes the original's pictures
both ways (`work/analysis/fighters_vs.png`, `fighters_zoom.png`). The
legs' grey edge pixels become white; the rest is unchanged.

**The plan, in steps, each checked against the pictures:**
1. **The band's zones at 8 lines** (the builder's `RowsZoneH` for the
   buffer's rows). The bitmap is unchanged, so every scene should be
   identical.
2. **The converted parts, at the build:**
   - per lower-body pose, merged sprite and mask, trimmed per 8-line zone;
   - per upper-body pose, torso and the player's head;
   - the enemy types' heads, and the heads' black layers;
   - the extra pose masks (`$9A2A`, `$9A18`), the hawk, the princess.
   - In bank 5, right-facing. (Akuma's after his partial masks are
     understood.)
3. **The runtime:**
   - hooks at bank 15's fighter drawing (`$A815`, the lower-body masks
     `$AA58`/`$AA32`), and the hawk's and finale's routines: each picture's
     parts and places recorded instead of blitted;
   - the parts' slices copied into cart RAM `$7300-$7BFF` per buffer, the
     enemy's mirrored and its head composed in;
   - objects added to the band's zone lists (as `TopEmit` does for the
     top);
   - a palette for the black layers and the merged lower bodies (skin,
     black, white), set each frame.
4. **The bitmap stops drawing the actors.** The game's wipes of their boxes
   stay at first (they also restore the scenery behind), and are trimmed
   later for speed.
5. **Checks:**
   - the pictures against the original's, composed as `renderfighters.py`
     does (the legs' grey the only difference);
   - every scene's run, the vs fight, the finale with the recording;
   - MARIA's time in the band;
   - hardware.

### The fighters as objects: step 1, the top rows' slots (2026-10-02)
Checkpoint before: `2026-10-02_KEEP_enh-before-fighter-zones`.

**8-line zones in the band, tried:**
- **The zone height rule:** `RowsZoneH` and the build's `zones()` take a
  zone of buffer rows at most `BAND_ZH` (8) rows, on a grid within the
  buffer column, for rows to `BAND_ZEND`. The build's count also now
  measures from `FB_TOP` (it took the absolute row mod `FB_BAND`).
- **Blocked:** scene 0's list `$1908` then needs 26 row-zone lists, and the
  zone lists' pages (`DLS_A`, `DLS_B`) hold 25. The grid is in the code but
  off (`BAND_ZEND` 0).
- **Uncounted until now:** the fighters' objects go in the band zones'
  lists:
  - a band zone's list grows from 10 bytes to about 26 (4 objects) or 34
    (6 objects);
  - with about 11 band zones a buffer, about 300-370 bytes a buffer.

**Objects in a zone, with the pose masks (`$9A2A`, `$9A18`) merged into the
lower body** (8-line zones, levels 1-3 and the vs fight):
- 4 at most nearly always: two fighters with two pieces each in one zone
  (at the waist the lower body and torso; at the head the torso and the
  head's black layer);
- 5-6 a handful of times, all in the head zone (rows 92-99): the hawk
  flying past, or the logs' enemy head drawn more than once in a picture,
  which objects won't repeat.

**The top rows' list slots, measured** (`probes/p7800-topslots.lua`, all
scenes; each pass a build or a refresh):
- at most 10 slots a buffer (indexes 0-9), of the 12 there were;
- at most 52 bytes of objects in a slot (level 2's wall: 13 objects), of
  76.

**So the slots are now 60 bytes, four a page, ten a buffer:**
- `TOPDL_A` `$4F10`, `TOPDL_B` `$5188` (mid-page), ending at `$5410`.
- `TopEmit` stops at 14 objects (`TOPDL_ARG` 58); `TopNextSlot` steps
  `TOPDL_SIZE`.
- The slot-exhaustion check compares the whole address, since B's slots
  start mid-page. `TopRefresh` sets both bytes of each buffer's first slot.
- **Pages `$54-$56` are freed (720 bytes) in gameplay.** The title's
  canvases (pages `$47-$66`) write them, so they're not in the free-RAM
  ledger.

**Checked:** `port/checkall.sh` every scene identical; `port/freecheck.sh`
clean.

### The fighters as objects: step 1, the band's lists (2026-10-02)
Checkpoint before: `2026-10-02_KEEP_enh-step1-slots`.

**The user's call:** gameplay gets its own, optimised zone lists; the attract
demo must have them too.

**What decides it:** the builder's `RowsBand` (bank 5), asked for a buffer
row's zone:
- **its result:** a band zone when the row is at most `BAND_ZEND` (134) and
  the title is off for both buffers (`S_TITLEA`, `S_TITLEB` 0);
- **the attract demo:** it runs with the title off, so it gets band lists
  like the levels;
- **why the title check covers both buffers:** the title marks one buffer
  while the other may still be shown as a bitmap, and the title's canvases
  are in the band lists' pages;
- **the story and the blanked buffers** never reach this path: they have
  their own emitters.

**What a band zone gets:**
- **the grid:** zones on the 8-line grid (`RowsZoneH`);
- **its list:** packed in its buffer's half of pages `$54-$56` (A
  `$5410-$5587`, B `$5588-$56FF`, 360 bytes each, through `S_BDLP`). A list
  never crosses a page's end: the next goes on at offset 16 of the next
  page.
- **With the title up:** everything as before (zones of up to 16, lists in
  `DLS_A`/`DLS_B`).

**Fixed slots were tried first, and dropped:**
- **The plan:** 30-byte lists (the bitmap's two objects, five fighter
  objects, the end), 12 a buffer.
- **Why they fail:**
  - The game's DLIs in the band split it further (a flagged row is a zone
    of its own, and the 27-row columns leave 3-row ends off the grid).
  - So a buffer has up to 16 band zones (lists `$1A5E`, `$1A3C`, `$1A0A`
    and their pairs). Rows 65-72, above the actors, take one of them.
  - 32 lists of 30 bytes is 960 bytes. There are 720.
- **Packed instead:**
  - each list gets only what's in it;
  - a picture's fighters need far fewer objects than 4 in every zone (a
    zone has 1-2 pieces a fighter, most zones one);
  - the bitmap's lists take at most 160 bytes a buffer of the 360.
- **Step 3 must therefore:**
  - rewrite a buffer's band lists each picture, packed;
  - patch the band zones' DLL entries' list addresses.
  - The builder could record those entries (where and which rows) while
    building.

**Build check:** both modes counted for each list (`zones(d, band)`). DLL
entries at most 85, `DLS` lists at most 25, band zones at most `BAND_N` (16).
- **Largest with the title off:** 59 entries, 11 `DLS` lists, 16 band.
- **With the title up:** 21 `DLS` lists.
- **Scene 0's `$1908`** needed 26 with the grid before; it now needs 11
  plus 15 band.

**Bug caught before running:** the packing's page step at first lost the
carry when a list ended exactly at a page's end (start `$xxF6`), which put
the next list in the page head. It now steps on the carry.

**Checked:**
- `port/checkall.sh`: every scene identical (levels 1-3 601/601, scenes 4
  and 6 176/176, the attract loop 800/800);
- `port/regress.sh`: clean;
- `port/freecheck.sh`: 0 writes.

**Probe:** `probes/p7800-bandlists.lua` (level 1 with the scripted player,
and the attract loop).
- **What it does:** each frame it walks the DLL MARIA is given (the last
  DPPH/DPPL writes) and counts the zones whose list is in the band area, by
  mode. It also checks each band list is still as written.
- **In play and the attract demo:** at most 16 band zones a buffer; lists end
  by `$54B0` (A) and `$5638` (B); none outside its half or overwritten.
- **With the title or the story up:** none on screen.
- **A dead end on the way:** its first version walked both DLLs whatever
  MARIA was shown. It reported 18 band zones and band lists with the title
  up. Those were stale DLLs, lists caught mid-build, and boot garbage
  (frame 12), none of them on screen. Count only the DLL MARIA is given.

### The small-sprite block moved to paged ROM (2026-10-02)
Checkpoint before: `2026-10-02_KEEP_enh-step1-band-lists`.

**The user's call:** "the end" can come from paged ROM. It's on screen
briefly and by itself (a cleared screen at a game over), and it belongs with
the title and the story scroll, the other users of the same glyphs.

**Who reads the block (`$1B80-$1DF5`, 616 bytes and the 14-byte hyphen
tail):**
- **The tool:** `probes/p7800-ramreaders.lua` logs every reader by PC (the
  older `p7800-ramreads.lua` keeps only an address's first, which hid them).
- **The runs:** the attract loop; levels 1-3, the finale and the gate fight
  (scripted player); a game over in level 1.
- **What reads it:**
  - **the boot:** the clear and the block's copy;
  - **the story's set-up** (`StoryInit`, also the ending's text);
  - **the level's load:** `TopRowRead` reading "the end"'s rows for the top
    data (9 rows of 5 glyphs);
  - **the draw of "the end":** the game's text routine and the blitter
    (each glyph's header and its 10th row, which lands in bitmap row 65).
- **Nothing else**, including the title.
- **Ignore frames before 160:** the BIOS's own code and display lists use
  that RAM too.

**Why the game's draw can't read ROM:**
- **It writes the glyphs.** The text routine (`$0780`) lowers a glyph's row
  count when it would pass row `$BB`, and writes the count back after
  every draw (`$07BD`, `$07C4`). A write in `$8000-$BFFF` switches the bank.
- **The base can't move freely.** It's added as split immediates (`ADC #$80`
  / `ADC #$04`, the font table `$06F4`/`$0714` holding offsets), so a moved
  base keeps its low byte.
- **No room anyway.** The art bank has no free place where the five glyphs'
  offsets land in pages that levels 1 and 2 can map: their own sprite pages
  cover most of it. Bank 1 has 146 bytes free.

**So:**
- **The boot** no longer copies the block.
- **`StoryInit`** reads the glyphs from the block's image in bank 5
  (`IMG_SPRITES`). The build emits the game's glyph offsets there
  (`STORY_GLYLO`/`HI`, checked the same in every scene), and the routine has
  bank 5 in for its two glyph loops.
- **The game's text routine** starts with `JSR SysTextIn` in place of
  `LDY #$00` / `STY $0F` (`$0780`, every scene's common code).
  - If the block isn't in RAM since the scene loaded (`S_GLYIN`), `TextIn`
    (bank 5) copies it in.
  - It then loads the scene's top pieces again, because the level's load
    read "the end"'s rows from RAM that didn't hold the block. That reload
    is skipped with the title or story up: their data is in those pages.
  - Then the routine's two instructions.
- **Every text draw is covered:** "the end", the finale's game over, and the
  credits cards (`$7793`, `$620E`, `$622C`) if they ever run. Nothing
  reaches them in the port; no reference to `$7793` was found.
- **The scene's load** clears `S_GLYIN`: the RAM is the scene's again.

**Freed:** `$1B80-$1DF5` (630 bytes) in play, until a text draw (a game over,
when the screen is cleared and the scene reloads after). Not in `FREE_RAM`:
it's written then.

**Cost:**
- **fixed bank:** 11 bytes more (15,118 used): the stub and the jump-table
  entry, less the boot's copy;
- **bank 5:** 67 bytes of code and the 64-byte glyph table.

**Checked:**
- **Every scene's pictures** (`port/checkall.sh`, the attract loop's story
  included): identical; `port/regress.sh` clean; `port/freecheck.sh` 0
  writes.
- **Game over** (level 1, `playkey.lua` `QUIET=200`: from that flip on, left
  held, off the cliff):
  - pictures against the build before: none differ, "the end" the same;
  - readers: the copy-in, then `TopRowRead`'s reload, then the draw;
  - writes in `$8000-$BFFF`: only the bank select at `$8000`.
- **The ending's text** (jumped to scene 4's `$B84E` at flip 200): 479 of 481
  pictures the same. The other two are the same text two pictures sooner:
  the jump landed 6 frames earlier.

**Still in the fixed bank** (the user asked): about 1.1K of the title and
story code.
- **The story,** about 606 bytes: `StoryStep`, `StoryBuild`, `StoryInit`.
- **The title,** about 372 bytes: `TitleLayout`, `TitleBits`, the stubs.
- **The marks and blanking,** 137 bytes: `TitleMark`, `ObjBlank`, `ObjEnd`.
- **Why there:** they read the scene's own data as they run (the story's
  strings, the font's advance tables `$0734`/`$0754`, the logo and
  copyright images).
- **Already moved** into scenes 0 and 4's pages: about 475 bytes (locate,
  patch, zone heights, `EndText`). Those pages have about 190 and 160 bytes
  free.
- **To bank 5:** possible if the build emits that data there too.

### The title and story code in bank 5 (2026-10-02)
**The user's call:** text is never drawn in play. The title, the story and
the ending's text all happen together, outside play and the room
animations, so their code can all live in bank 5.

**Moved to the top bank (bank 5, FARART pieces):**
- `StoryStep` (the start and each step), `StoryInit` (glyphs and line
  templates), `StoryGlyphP`;
- `TitleLayout`, `TitleLogo`/`TitleCopy`/`TitleMark`, `ObjBlank`/`ObjEnd`;
- the title's object tables (`TITLE_SLO` … `TITLE_CAN`, out of the system
  block's tables);
- the font's advance tables, emitted by the build as `STORY_ADVC`/`STORY_ADVS`
  from the game's `$0734`/`$0754` (checked the same in every scene), beside
  `STORY_GLYLO`/`HI`.

**What stays in the fixed bank:**
- **The ways in** (7 bytes each, through `TopArtCall`): `StoryStepF`
  (`SysStoryStep`), `StoryInitF` (scene 4's `EndText`), `TitleLogoF`,
  `TitleCopyF`, `ObjEndF` (`LoadScene`; the carry comes back through
  `TopStubOut`). `ClearBuf`, already in bank 5, calls `ObjEnd` directly.
- **`BuildDllS`:** the scene page in, `BuildDllF`, back (`StoryBuild`: a
  list's description is in the scene page).
- **`ScnRead`:** A = `(ZP_P1),Y` read with the scene page in, then bank 5
  back (X, Y kept). Bank 5 code reads the scene page only through it:
  - the story's string pointers and strings;
  - the scene's list table (`SP_NDL`, `DLT_*`, one block from `$8040`);
  - the logo and copyright images.
  - A fixed routine that switched the window and returned would come back
    into the scene page's bytes. So the switch, the call and the switch
    back are always together in the fixed bank.
- **`TitleBits`, `StoryPatchNext`, the builder's wrappers:** scenes 0 and
  4's code calls them.
- **`StoryBuild`'s search for the lists** now holds `S_BUSY` throughout,
  not only around the build: it keeps its count in the story's scratch,
  which the frame routine's builds also use.

**Freed:**
- **fixed bank:** 1,019 bytes (15,118 → 14,099 used, 2,285 free);
- **bank 5:** 1,198 bytes used (10,179 used, about 6.2K free for the
  fighters' parts).
- Nothing was duplicated: the strings and images stay in the scene pages.

**Checked:**
- **Every scene's pictures** (`checkall.sh`; the attract loop has the title
  and the story scroll): identical; `regress.sh` 13/13; `freecheck.sh` 0
  writes.
- **Game over** ("the end", `QUIET=200`): every picture the same as the
  band-lists checkpoint's.
- **The ending's text** (jumped to scene 4's `$B84E` at flip 200): the same
  438 pictures, aligned on the text's appearance.
- **A dead end on the way:** unaligned, the new cart showed the text 18
  pictures late. The ending sets the game's frame-wait counters (`$0AFC` =
  `$5A`, `$0AFE` = `$FF`) before its flips, so the wait after a jump
  depends on where they stood. Jumping at flips 210 and 230 gave 258 and
  513 frames on one cart or the other, either way round
  (`probes/p7800-pctimes.lua` logs when named routines run). A jump test
  must align on the event, not the frame.

### The fighters as objects: step 2, the parts converted (2026-10-02)
**The user's idea:** make the trimmed rows ourselves, and take back a little
color depth that way.

**Why the build can cut the parts.** Bank 15 places every fighter part by
its pose's table row + `$72` (`$A943`). The fighters have no vertical
position, so each pose's rows are fixed and its parts can be cut on the
band's 8-line grid at the build.
- **One image, several rows:** an image can serve several poses at
  different rows (the head `$8EC1`/`$8E9B` at 116-142, by upper pose).
  Pre-cutting is per pose.
- **The hawk's rows vary:** it is placed at copy time.

**The color depth taken back** (`probes/fighterslices.py`):
- each slice is its own object, so it gets its own palette;
- a slice with no black keeps the game's palette 1 (skin, grey, white);
- only slices holding the mask's black use the black palette (skin, black,
  white: grey made white);
- **the lower bodies keep 277 of their 591 grey pixels.** It was 508
  before the belt went black (below): the belt's zone then needs the black
  palette too.

**The belt is black** (the user: "the belt area should be black"):
- **In the original the belt is a gap.** It's a band of empty pixels in
  the lower-body sprite's top rows, between the jacket's hem and the
  trousers, and the background shows through it: black in most of the band.
- **As objects it must be an opaque black.** The converter fills a
  sprite's empty pixels that have the figure above and below in their
  column, across a gap of at most 3 rows (`BELT_GAP`), in the sprite's top
  6 rows (`BELT_ROWS`).
- **A dead end:** without the row limit, folded legs' short gaps filled
  too (poses 28, 30). Limited to the waist, only the belt line fills: a
  band with its knot in the standing poses, short marks in the stances and
  kicks.
- **The data's size didn't change:** the belt is inside the slices' boxes.

**What is stored, and where** (`port/fighters7800.py`, placed by the build):
- **Lower bodies,** pose `$20` (40 distinct of 42), converted and pre-cut:
  - 179 slices;
  - 3,795 bytes with their headers, in the art bank;
  - a pose's blob: the sprite's width, the slice count, then per slice
    three header bytes (zone | row in zone | palette; rows | width; byte
    offset from the sprite's left byte) and its rows.
  - Bank 5's `FT_LOWLO`/`FT_LOWHI` give each pose's blob.
- **Torsos and the heads' colours: no new data.** They need no conversion,
  so the copy will read the game's own images (torsos `$A226`/`$A24C` in the
  art; heads `$A1CD`/`$A1CA`, the enemies' through `$AA75`, some in scene
  data at `$7E00-$7FC3`).
- **Black-only and merged images,** plain (rows, width, rows), 367 bytes in
  the art bank:
  - **the heads' black layers:** the head mask `$8EC1` (head image 0's only:
    images 1 and 2 have none) where the head leaves it uncovered. One for
    the player, one per enemy type; identical ones are stored once.
    `FT_HBLKLO`/`HI` index them.
  - **the pose masks** `$9A2A` and `$9A18`: black where they clear;
  - **the hawk,** each sprite (`$942A`, `$94E6`) merged with its mask
    (`$93AB`, `$9490`; the same column, 3 rows higher, from the draw logs).
- **The build checks it:** every pose's blob is read back from the bank
  image and compared with the conversion.
- **Pictured:** `probes/fighterconv.py` draws every pose decoded from the
  cartridge beside the original's composition
  (`work/analysis/fighters_conv.png`).
- **Checked:** nothing reads the data yet, so every scene's pictures are the
  same (`checkall.sh`), `regress.sh` 13/13, `freecheck.sh` 0 writes. That
  run was before the belt. The belt changes only the data's contents.

**Placement rules found in bank 15** (`$A815-$AAF2`), for step 3:
- **Mirrored lower bodies:** `$A2BE,X` set (poses 28-32) draws the lower
  body (sprite and mask) mirrored for the player and plain for the enemy
  (`$2B82`/`$29C2`). The copy mirrors per part, not per fighter.
- **The pose masks** are chosen by the upper pose `$21`:
  - `$9A2A` for 6 and `$14-$1D`, 15 rows down, at the torso's column + `$2C`;
  - `$9A18` for 7, `$0A-$0D` and `$27`, 22 rows down, at the torso's column.
- **Heads,** by `$A1A4,X` (the upper pose):
  - values 8 and 9 are head images 1 and 2 (no mask);
  - values 0, 2, 4 and 6 are image 0 with its mask, nudged that many
    eighths of a byte (`$AACE`; negated for the enemy).
  - An enemy's head (or the player's when `$36` is set) is the type's
    (`$3E`), 2 rows up and `$2C` across.

**Not in this step:** Akuma and the princess (the finale).
- **Correction:** the "princess" entry in "The fighters' parts: masks and
  colours" names routines (`$7AF9`, `$7B10`, `$7B28`, `$7B57`), not images.
  Those routines draw a fighter in the finale (mask `$9043`, torso `$821E`,
  fixed at column 30). The princess's images are still to be found.

**A measurement mistake on the way:** the torsos first came to 6,886 bytes.
I had taken the head's column offset as unsigned (255 is -1). Signed, the
torsos with the player's head are 2,038 bytes. They aren't stored now
anyway: the enemy needs them without the player's head, so heads are put in
at copy time.

**Room:**
- **the art bank:** 16,000 of 16,384 used (384 free). Akuma's parts will
  need space elsewhere, or the original actor images' space once the bitmap
  stops drawing the actors (step 4).
- **bank 5:** 10,279 used (the tables, 100 bytes);
- **the fixed bank:** unchanged.

### The fighters as objects: step 3a, the lower bodies at the flip (2026-10-02)
**The runtime, first stage** (the lower bodies only, shown over the bitmap's
own fighters so that a misplacement shows):
- **Recording:** bank 15's fighter drawing (`$A815`: `LDX $20`, `LDA $50`)
  calls `SysFRec` first. It stores the fighter for the buffer being drawn
  (`$07`) in four records (`FR_*`: each buffer's player and enemy), with its
  poses, column, shift, enemy type and `$36`. The scene code's own enemies
  (`$2C` negative, `$4D` not 0 or 5: `$A827`) are not recorded.
- **At each flip** (`TopFlip`, now on every flip, not only with top pieces):
  - `FtEmit` (bank 5) turns the buffer's records into objects. Each slice
    of the pose's blob is copied into the buffer's half of pages `$73-$7A`
    (A columns 0-127, B 128-255; grid line g at page `$7A - g`), by the
    fixed bank's `FtCopy` with the art bank in, mirrored through `$F500`.
  - Each slice becomes an object entry (`FO_*`: the grid cell, x, palette
    and width, the column). The records are then used up.
  - `BandRefresh` rewrites the buffer's band lists and patches their DLL
    entries.
- **The builder** records each band zone it makes (`ZT_*`: the DLL entry,
  grid cell, first line in it, height, bitmap row) and writes its list
  through the same `BandWrite`. So a rebuild in the interrupt keeps the
  fighters.
  - A list is the bitmap's two objects, the cell's fighter objects (the
    high byte from the zone's first line in the cell), and the end.
  - Objects are left out when the room after a list would not hold the
    zones still to come.
- **The tables** live in the small-sprite block's RAM (`$1B80-$1D5B`,
  `layout7800.FT_TABLES`): they are free in play. `TextIn` now marks the
  glyphs in before copying them over the tables, and nothing reads the
  tables while they're in. The scene's load clears them.
- **The black palette** (palette 4): the colour routine's end (`$1155`)
  jumps to `ColTail`. Palette 4 takes the same set's skin and white (less
  the fade `$0F12`) and black, at every DLI that sets palette 1.
- **Placement rules confirmed:**
  - the enemy is drawn MR (mirrored, box ending at its column), a rigid
    mirror of the merged part;
  - the `$A2BE` poses (28-32) draw sprite and mask each mirrored in its own
    box (M for the player, AR for the enemy). Their mask columns are set
    for that, and the merged part holds as a rigid mirror there too.
- **Cost:** fixed bank +289 bytes (14,388 used); bank 5 +990 (11,269).

**Checked** (`checkall.sh`, pictures compared with the references; the
bitmap still draws the fighters underneath):
- **Every scene runs through.** The most differing pixels in a picture: 246
  (level 1), 222 (attract), 160-164 (levels 2-3), 88 (gate fight), 10
  (finale).
- **No misplacement:** the player's and the enemy's lower bodies sit
  exactly on the bitmap's.
- **The expected differences:** the legs' grey edge pixels made white in
  the slices holding black, and the belt.

**Two problems found:**
1. **Scenery in front of the fighters.**
   - **Where:** level 1's torii pillars (also the attract demo's), level 2's
     door frames at the screen's edges, and level 3's pillar.
   - **Why:** the game draws that scenery into the bitmap after the
     fighters. Objects follow the bitmap's two objects in a list, so they
     are always in front.
   - **Effect:** a fighter behind a pillar now shows over it.
2. **One fighter's black over the other's colours.** The original draws
   both lower-body masks first, then each fighter's colours, so colours
   always win. A merged part's black can cover the other fighter's colours
   (level 3: a fighter lying on the floor, its black over the standing
   player's foot).

### The fighters as objects: step 3b, clipping, order, the scenery in front (2026-10-02)
**The user's calls:**
- **the scenery the game draws in front of the fighters:** as objects on
  top (not the fighters cut around it);
- **one fighter's black over the other's colours:** reorder only (the
  slices holding black first in a zone).

**Clipping as the blitter clips** (`$2869`/`$2A40`: signed columns, bytes
left of 0 and from 40 on not drawn):
- each slice is cut to columns 0-39 (`FtLower`);
- a fighter off-screen at the left no longer wraps round past x 255 (level
  2's lying fighter at the room's edge).

**The order:** a zone's fighter objects are listed black-palette ones first,
then the others (`FtSort`).

**The scenery in front, as objects on top, without new data:**
- **The front boxes.** A band draw (blit or fill) after the picture's
  fighters and not part of one is in front of them. `RowBase` (every blit
  and fill) records its box (`FgRec`):
  - a blit's columns `$1E`, `$0E` (and the shifted byte), a fill's
    `$05-$09`, rows from `$06`;
  - "after the fighters": `FT_SEEN`, set by the fighter record hook, and
    no fighter being drawn (`FT_IN`, from the record hook to the torso's
    blit, patched at `$A8B4`/`$A940` to `SysFtEnd`/`SysFtEnd2`);
  - a box with the same columns touching the last one extends it;
  - at most 8 a buffer.
- **The level-1 column routine** (`ColA`) copies a column's middle pieces
  without `RowBase`, so its end (`ColDone`) records the column's whole box
  (`FgCol`, through `SysFgCol`; the first line in `S_CTOP`).
- **In each band zone with fighter objects,** for each box crossing it,
  after the fighters:
  1. a black block (32 columns of `$AA` in the slice pages, palette 4's
     colour 2), as wide as the box;
  2. the bitmap row's own bytes over the box.

  The box then shows exactly what the bitmap holds there, opaque. Up to 3
  pixels of background beside a piece's edge also cover the fighter.
- **Found by the trace probe** (`probes/p7800-drawlog.lua`: every draw's
  rows, columns, caller and state around a flip): level 1's pillar is
  drawn after the fighters at some scroll positions and before them at
  others. The original's log had only shown the second kind.

**Three faults found and fixed on the way:**
- **A variable defined twice:** my `S_FK` was also the fast fill's block
  counter. Renamed `S_FTK`; `layout7800.sysvars()` now refuses duplicate
  names.
- **Lists over their area:** when a list moved to the next page and then
  the room check failed, the bitmap-only list was still written at the
  moved place. For buffer B that was `$5710`, the top rows' piece lists
  (`TOPLI`), so the door lintels vanished (level 2). Now the place is
  chosen, the room checked, and on failure the list is placed again,
  without the fighter objects, from the original place.
- **The pillar boxes ran out:** the column routine's 2-row blits filled
  the 8 boxes with the pillar's top rows, so the legs were uncovered.
  Touching boxes now merge.
- **Lists in the page heads:** a list ending exactly at a page's end left
  the next one's place at offset 0 of the following page, in the page heads
  (free RAM). `freecheck.sh` caught it (`$5600-$560F`). A place below
  offset 16 now moves to 16.
- **The enemy heads' black layers** were built with the head at its mask's
  place. An enemy's head (or the player's with `$36` set) is drawn 2 rows up
  and a byte across from the mask (`$A9AE`): in the image's own frame a
  byte to the left. Rebuilt with that offset (`fighters7800.head_black`).

**Checked** (`checkall.sh` against the references, the bitmap still drawing
the fighters underneath; `regress.sh` 13/13; `freecheck.sh` 0 writes):
- **every scene runs through;** the worst pictures are 112-128 differing
  pixels (levels 1-3, attract);
- **the pillars and door frames** are in front of the fighters as in the
  reference;
- **what remains:**
  - the legs' grey made white in the slices holding black;
  - the belt;
  - a lying fighter's black covering its own torso. The torso is still the
    bitmap's underneath; it goes when torsos become objects.

**The cost** (`probes/p7800-fttime.lua`, level 1, in scanlines):

| Work | Average a picture |
|---|---|
| The copy | 184 |
| The list refresh | 150 (242 before sorting by cell and the reserve table) |
| Bank 15's drawing of one fighter (still done) | 316 |

- **Now the game runs slower:** level 1 reached 3,075 flips by frame 24,000
  against 4,171, because it pays for both.
- **After step 4,** when the bitmap no longer draws the fighters (about
  630 a picture plus the lower-body masks), a picture should cost less than
  the original's.
- **Room:** the fixed bank 14,858 used; bank 5 11,855.

### The fighters as objects: step 3c, the upper bodies (2026-10-02)
**Every fighter part is now an object** (still over the bitmap's own
fighters; step 4 removes those). `FtUpper` follows bank 15 (`$A815-$AACD`)
for each recorded fighter:
- **The base:** the column `$22 ± $A150,lower pose`, eighths `$50 ±
  $A17A,pose` with the carry or borrow.
- **The pose mask** (`FT_PMASK_*`, black):
  - `$9A2A` for upper poses 6 and `$14-$1D`: 15 rows down, at the base +
    `$2C`;
  - `$9A18` for 7, `$0A-$0D` and `$27`: 22 rows down, at the base.
- **The head,** by `$A1A4`:
  - 8 and 9 are images 1 and 2;
  - otherwise image 0, nudged that many eighths (the enemy's less), with
    the head mask's black (`FT_HBLK*`) at the base `± $A1DA`, row `$A200`.
  - The enemy's head (or the player's with `$36` set) is the type's
    (`$3E`), 2 rows up and `$2C` across. The build gives every head image's
    address and bank (`FT_HEADLO/HI/B`): some types' heads are in scene data.
- **The torso:** `$A226/$A24C` at the base `± $A272`, row `$A298`.
- **The enemy's parts** are drawn mirrored, each box ending at its column.
- **The plain images** (heads, torsos, black layers) are cut at the grid's
  cells as they are copied (`FtPlain`). The torsos and the heads' colours are
  read from the game's own images; their source bank is a variable
  (`FT_SRCB`).

**Faults found and fixed:**
- **The mirrored-flag poses' merged mask** (28-32, `$A2BE`) sat a byte off:
  the mask goes at `W - mw - mcol` there. That was worked out for step 3a
  but never put into the converter. The player's waist showed white in
  pose 29 (level 3).
- **32 objects a buffer were too few** for two whole fighters (up to 32
  were made, the second's last parts dropped). Now 40, with the RAM
  rearranged:
  - the front boxes' tables in page heads of pages `$5B-$63` (16 bytes:
    a buffer's 8 each), out of the free-RAM ledger;
  - the sorted list as indexes (`FS_I`) in page `$7B`.

**Checked:**
- **`checkall.sh`:** every scene's worst picture 108-134 differing pixels.
  The differences are the belt, the legs' grey made white in the zones
  with black, a few pixels where the fighters overlap, and two at a head.
- **`freecheck.sh`:** 0 writes.
- **Room:** fixed bank 14,860; bank 5 12,667.

### The fighters as objects: step 4, the bitmap's fighters gone (2026-10-02)
**Bank 15 no longer draws a recorded fighter into the bitmap.** The objects
are the only picture of it:
- `BlitBank` drops a blit while `FT_IN` is 1 (a recorded fighter being
  drawn): `PLA` x4, `RTS`.
- `MaskP`/`MaskE` (`$AA71`, `$AA54`) skip the lower-body masks.
- The scene code's own enemies (`$4D` not 0 or 5) are still drawn by the
  bitmap: `FRec` sets `FT_IN` 2 for them, and records nothing.
- The emit moved to the common flip (`$0862`'s `JSR $0878` is now
  `JSR Flip0`, in play only), so each buffer's objects change with the swap.

**Choices (the user's):** the scenery in front of the fighters stays as
objects on top (the front boxes of step 3b). Where the two fighters
overlap, only the order is used.

**Dead end: the `$0862` hook "broke the attract demo".** Bisecting pointed
at the hook. The cause was `playkey.lua`: it confirms a flip by the next
fetch being `$0878`, and with a `JSR` there the next fetch is its target.
`playkey` now also accepts the target of a `JSR` at `$0862`.

**Faults found and fixed:**
- **Legs and lying fighters as thin lines (level 1):** the band lists ran
  out of room. `probes/p7800-bandroom.lua` counted 60 of 1,502 list
  refreshes in level 1 with a zone's fighter objects all dropped:
  - with two fighters and the torii box, the zones need up to 34 bytes,
    against 376 a buffer;
  - one list skipping to the next page wasted 26 bytes in buffer B.

  The fixes:
  - **Each zone's own 16 bytes:** a list of at most 16 (the bitmap's two
    objects and one more) goes in the page head kept for that zone
    (`BAND_HEADS`: pages `$4B-$5A` for A, `$64-$72` for B, B's last in page
    `$7B`'s tail). Those were free RAM in the ledger. Only the longer lists
    use the area, so no room is kept for the zones still to come (the old
    `FT_RESV`, 12 each, is gone).
  - **Page `$7B`'s tails** after the fighters' sort (`$7B46-$7B7F` A,
    `$7BC6-$7BEF` B) take a list the area can't.
  - **Short of room after all,** the front boxes are left out first, then
    the objects one at a time from the last, never the whole zone.
  - **A box inside another** (same rows and columns, and not an opaque one
    inside a see-through one) is left out, and one holding an earlier box
    replaces it. The overlays show the bitmap's own final bytes, so the
    inner box adds nothing. Level 2's door posts gave two boxes, cols 2+2
    inside 0+4, each 8 bytes in every zone it crossed.

  After: 0 refreshes with anything left out in scenes 1, 2, 3, 4 and 6.
- **Fighters gone in Akuma's cutscene** (scene 0's attract and between
  levels: the player at the door vanished for 3 pictures). The emit used a
  buffer's records up at each flip. The cutscene draws the player once and
  then redraws Akuma alone (`$7CCD` blits after fills at cols 26-32). The
  game leaves a fighter it doesn't redraw in its buffer. Now:
  - a record stays (`FR_V` 1: an earlier picture's; `FRec` writes 2) until
    the game redraws that fighter;
  - or erases it: an opaque band draw over its box (`FgStale`; the box,
    `FR_C0/C1/R0/R1`, from its objects at the emit: `FtBoxOf`);
  - or clears the buffer (`FtForget`);
  - or copies the other buffer over it (`FtCopyRec`: the source's records
    and shown front boxes become the target's).
  - **A buffer with nothing drawn or erased** (`FT_SEEN`, `FT_DIRTY` both 0)
    is left as shown: no copy, no list refresh, which also saves the time.
    One with only earlier fighters keeps its front boxes.

**Checked:**
- **`checkall.sh`** (`probes/snapcount.py`, pictures with over 300
  differing pixels): scene 1 12 of 601, scene 3 5, scenes 0, 2, 4, 6 none.
  Before these fixes: 31, 6, 13, 8, 0, 0.
  - **Every one left is timing:** our next flip matches the reference
    within 6-52 pixels. The emit runs before the swap and delays it, and
    the snapshot is taken at the flip's `JSR`, mid-frame. Three looked
    wrong at the next flip too (a standing torso on running legs): torn
    snapshots, half one frame and half the next. With `SNAPEND=1`
    (`playkey.lua`: the snapshot at the frame's end) those pictures are
    whole and right.
- **`regress.sh`:** about 41-47 rows a buffer differ from the original,
  in every scene and at every flip checked. That is expected: the fighters
  are no longer in the bitmap. The fighters are checked by screenshots.
- **`freecheck.sh`:** 0 writes in every scene (8 ranges now: the band heads
  and page `$7B`'s tails left the ledger, and `$1F78` is `S_BX`).
- **Room:** fixed bank 15,202 of 16,384; bank 5 13,305.

**Still open:** the game runs slower than the original:
- level 1 reaches 3,008 flips by frame 20,000, against 3,431;
- a flip's copy takes about 184 scanlines and its list refresh about 150.
  Bank 15's drawing, about 316 a fighter, is skipped now.

Also still open: the hawk, Akuma and the princess as objects.

### The fighters as objects: speed (2026-10-02)
The user: work on the speed. Level 1 with the scripted player made 2,888
flips by frame 20,000. The stable port made 3,199, and step 1 (no fighter
objects, the fighters drawn into the bitmap) 3,443.

**Measured first:**
- **The CPU is busy in every build:** about 24-25k cycles executed a frame,
  so the speed is the work a flip. Per flip (instructions, frames
  3000-9000), step 1 executed about 41.0k and step 4 about 43.5k. The
  blitter's share fell by 12.4k (the fighters no longer drawn), but the
  objects added about 14.5k: the copy 4.3k, the band lists 3.6k, `FtObj`
  2.1k, the record hooks (`FgRec`, `FgBox`, `FgStale`) 1.5k more than step 1,
  the sort 1.0k, the rest 1.9k.
- **MARIA's extra DMA is small:** about 5,300 cycles a frame against step 1's
  4,630 (`p7800-dma.lua`), about 3%.
- `p7800-fttime.lua`: an emit's copy, objects and sort took about 507
  scanlines, the list refresh 195. (Correction: the 184 noted earlier was
  an earlier, smaller step's.)
- `p7800-pcsample.lua` now takes `CYCLES=1` (each instruction weighted by
  its opcode's base cycles) and `BYSYM` (bank 5 by symbol);
  `probes/pccat.py` sums a log by the fighters' parts.

**Reuse: designs simulated** (`probes/p7800-ftsame.lua SEQ=1`, the parts'
keys and columns at each emit; `probes/ftcache.py`). A part is a fighter's
upper or lower body.
- **Each part's largest** (`probes/p7800-ftmax.lua`, every pose and type
  forced in turn): a lower body 24 columns, an upper body 45 (pose 25 or 2
  with a type's head). Two fighters at their largest need 138, more than a
  buffer's 112. The old sequential packing already left parts out then:
  12 of about 3,470 emits in the scripted runs.
- Copy saved, levels 1-3:
  - a part reused when its buffer's last emit had it: 39-61%;
  - a pool of 224 columns over both buffers: 64-80%;
  - two regions per part class: 57-66%. It needs fixed regions, and those
    don't fit the largest parts (138 + 138 > 224). **Rejected.**
  - **chosen:** sequential packing with the upper bodies first (they are
    the most reused: the player's 85%, the enemy's 62%), a part reused
    when its key, first column and wholeness match its buffer's last emit:
    35-58%.
- **Whole emits that could be skipped** (both records and the front boxes
  as the buffer's last emit; `probes/p7800-ftunchanged.lua`): 6% in level
  1, 4% in level 2, 28% in level 3.

**Done:**
- **Parts reused** (`RU_K1/K2/COL/OK`, 4 parts a buffer):
  - The copy order is the player's upper body, the enemy's, the player's
    lower body, the enemy's. The draw order stays as bank 15's: `FtPlace`
    walks the parts in the old order (`FT_PORD`).
  - A part's slices are copied whether shown or not, so its columns don't
    depend on where it stands.
  - A part not emitted (no fighter, a pose out of range, a slice without
    room) is marked not whole, so its columns are never trusted again.
- **The columns:** A's parts are packed from 0 up, B's from 224 down, each
  to where the other's shown parts begin (`FT_USE`). This gives either
  buffer more than 112 when the other needs less, fixing most of the old
  overflow.
- **The band lists:**
  - a zone with no objects whose own bytes already hold its bitmap list
    (`ZT_H` bit 7) is not written again;
  - the objects' column extent is worked out once a cell (`FB_CELL`), not
    once a zone;
  - lists are written by index, with no call a byte.
- **The copy:**
  - the mirrored row loop works through `ZP_P2 + width - 256` at `255 - j`,
    37 cycles a byte against 51;
  - the forward loop is down to 16 cycles a byte;
  - a cell's lines before and after the slice are cleared as two runs;
  - a slice's three header bytes are read with one bank switch (`FtRead3`).
- **The rest:**
  - `FtPlain` finds a row's cell from a table (`FT_ROWCELL`) instead of
    searching;
  - the sort and the placing are one pass, black ones first (the others'
    cursors borrow page `$7B`'s band tail, idle until the refresh);
  - each record's box grows as its objects are made (`FtObj`), with no
    second pass.
- **Whole emit skipped** (`FtSame`): when both records are as at the
  buffer's last emit (`LS_22/LS_50`, the parts' keys in `RU_*`) and the
  recorded front boxes are the shown ones, the emit does only the
  bookkeeping. Its objects and lists stand.

**Result**, flips by frame 20,000 (scripted player):

| build | level 1 | level 3 |
|---|---|---|
| step 4 | 2,888 | |
| reuse | 3,034 | |
| + lists, loops, cell table, boxes in `FtObj` | 3,201 | |
| + one-pass sort, `FtRead3`, clears | 3,283 | |
| + whole emit skipped | **3,302** | **1,942** |
| the stable port | 3,199 | |
| step 1 | 3,443 | 1,991 |

An emit is now about 371 scanlines and a refresh 163 (from 507 and 195).
Level 1 is 3% faster than the stable port and 4% slower than step 1.

**Not done (costed):** pre-mirrored lower-body blobs. The mirrored copy is
still about 5k cycles a flip. Mirrored copies of the 9 most used poses
(about 1K of ROM) would cover 60% of it, 2K would cover 90%: about 2% more
speed. ROM is the binding constraint and the remaining objects need it.

**Checking with the speed moving:** a faster build moves every picture
against the reference, and the old snapshots were taken mid-frame at the
flip's `JSR`.
- `playkey.lua SNAPDL=1` takes the snapshot at the end of the first frame
  after the flip's display list change, so each build is caught showing
  the same picture.
- `port/checkdl.sh` compares a build with SNAPDL references made from the
  step-1 checkpoint (`port/checkdl.sh ref`).
- Result: scenes 1, 2, 3, 4 and 6 have no picture over 300 differing
  pixels.
- **The attract demo can't be compared across speeds:** its play depends
  on the speed. With reuse off, the build matches the slower step 4
  exactly, and both differ from the reference by thousands of pixels.
- **Correction:** picture 0640 is flip 1282 (picture n is flip 2 + 2n),
  not 1280. It took a slice-page dump with a render of the live lists
  (`probes/p7800-slicedump.lua`) to see that.

**A fault found (not new): the hit star over the floor.** At flip 1282 of
the attract demo the player's legs vanish:
- The star (`$93AB` mask, `$942A` sprite) is drawn into the bitmap after
  the fighters, so it is a see-through front box.
- Its overlay is the bitmap's own bytes, and in the floor's rows those are
  the floor. The floor is laid over the legs.
- The fix is the star as an object: see the plan below.

**Also checked:**
- `p7800-bandroom.lua`: no zone loses anything for room in scenes 0-4
  and 6.
- `freecheck.sh`: 0 writes.
- **Room:**
  - fixed bank 15,292 of 16,384;
  - bank 5 13,904 (2,480 left);
  - the fighters' tables are 2 bytes short of `$1DF6`.

## The remaining objects: the plan (2026-10-02)
The user: plan out the remaining objects.

**Corrections to the inventory:**
- **`$93AB`/`$942A` and `$9490`/`$94E6` are the hit stars, not the hawk**
  (a big and a small one, each a mask and a sprite). They are drawn at the
  point of a hit, which is why they "move vertically": rows 75-125. The
  "hawk" rows in "The bands" and "Keeping colours" are the stars, and so
  are `fighters7800.black_images`' `hawk_942A/94E6`. Those are already
  converted, in the art bank.
- **`$7AF9`, `$7B10`, `$7B28`, `$7B57` are scene 4's fighter-part routines**
  (masks and sprites of the art bank's torsos, e.g. `$83A8`, `$9550`), like
  the levels' `$7A53-$7AC7`. They are not the princess. They are already
  objects.

**What still draws actors into the bitmap**, from the inventory
(`work/analysis/assets`) and bank 15's code:

| actor | where | drawn by | images | with a fighter? |
|---|---|---|---|---|
| hit stars | every fight, the attract demo | mask: bank 15 `$B533`; sprite: the level's `$7ACF`/`$7ADA` | big 25×5 + 20×5, small 21×4 + 15×4 (rows × bytes), converted | always, on top |
| Akuma, fighting | the finale (scene 4) | bank 15 `$A815` jumps to scene 4's `$7C50` when `$4D` isn't 0 or 5 (`$7C56`: bank 15's structure, his tables `$7E44`...); parts `$7CFF`, `$7D7E`, `$7D4A`, `$7B0A`, `$7B4B`, and variants | in scene 4's data `$602F-$6E5C` (up to 36×4, 21×5, 15×10), with masks; some masks hold value 1 (open) | yes: the fight |
| Mariko | the finale | scene 4's code `$1E9E`, `$7AE2`, `$1EE5`, `$1EEE`, `$1EF9` | cart bank 3: `$1772` 46×3, `$181E` 45×2, `$1530` 43×3, `$1C80` 36×3, `$1600` 20×3, smaller ones | at the end (the embrace) |
| the hawk | the finale | not identified. Candidate: scene 4's `$7DA9` family (`$7F60`/`$7F82` by `$70`, column `$72`, masks) | ? | it attacks the player |
| the cutscene figures | level 1's page, the attract (Akuma's room, the princess room) | the cutscene code (`$7CCD` blits) | Akuma at cutscene size, Mariko | no overlap with the fighters |

Today Akuma is drawn into the bitmap (`FT_IN` 2). The player's objects
always sit over him, and his draws after the player become see-through
front boxes: his pixels over the player, his mask's black outline lost.
None of the scripted runs fights him, so this hasn't been checked.

**What exists to build on:**
- per-buffer records with the earlier-picture semantics (kept until
  redrawn, erased, cleared or copied);
- the copy into the slice pages with runtime cell cutting at any row
  (`FtPlain`);
- part reuse, front boxes, the band lists with their room handling.

**What the rest needs:**
- **An effect record a buffer** (image, row, column, shift, mirrored; and
  its box for erasing), emitted after both fighters so it draws on top.
  The stars first, maybe the hawk.
- **The game's own masks as black layers at copy time:** a 256-byte table
  turns a mask byte into a black-palette byte (a cleared pixel black, a
  kept one transparent), like `FT_MIR`, and a mirrored-mask table beside
  it. Akuma and Mariko then need no converted copies in ROM (512 bytes of
  tables against about 2-3K of copies), at the mirrored copy's speed. The
  masks with value 1 (they AND the background to its low bit) need a look
  first.
- **Akuma as the enemy record:** his routine hooked as `FRec` hooks bank
  15's, his parts read from scene 4's data, his tables in place of
  `$A054`/`$A150`.

**Budgets:**
- **RAM:** the fighters' tables have 2 bytes left. An effect record is
  about 20 bytes for both buffers, more for Akuma's own pose state.
  Sources:
  - packing `ZT_S` and `ZT_H` into one byte: 32;
  - `FT_FON` 40 to 36: 32;
  - `$1F79-$1F7F`: 7.
- **Columns:**
  - a star takes up to about 24;
  - Akuma's parts are larger than a guard's in the cutscenes, not in the
    fight;
  - the flexible A/B split gives up to 224 between the buffers.
- **ROM:** bank 5 has 2,480 bytes, the art bank 384, banks 3 and 6 about
  600 each. Runtime masks keep Akuma and Mariko out of it.
- **List room:** a star adds 2-4 objects in 3-4 zones.

**Order:**
1. **5a, the stars:** they fix the fault above. The effect record; hook
   `$B533` and the level routines' star blits (blits dropped as the
   fighters' are); emit from the converted images, mirrored as drawn.
2. **5b, measure the finale:** a 7800 recording through the hawk, the
   Akuma fight and the ending (the user's `Record Karateka 7800.bat`;
   `xe-bandlog.lua` doesn't load the easy cheat, so the XEGS recording
   diverged and never reached it). From it: the hawk's code and images,
   who is on screen together, Akuma's masks with value 1.
3. **5c, Akuma in the fight,** as the enemy record.
4. **5d, Mariko,** and the embrace's order.
5. **5e, the hawk.**
6. **5f, the cutscene figures:** optional. They never overlap a fighter,
   so the bitmap shows them correctly.

### The hit stars as objects (2026-10-03)
The user: start with the hit flashes (step 5a of the plan).

**How the game draws one** (bank 15, the routines at `$B503` big and `$B54D`
small):
- the mask (`$93AB`, or `$9490`) at row `$06` from a table by Y, column `$05`
  = `$22` + 4 for the player or `$22` - 8 for the enemy, shift `$10` = `$50`,
  by `JSR $284E` at `$B533` (or `$B580`), in AND mode;
- then the sprite (`$942A`, or `$94E6`) 3 rows lower, in OR mode, by a tail
  `JMP $284E` at `$B549` (or `$B592`). That is why the level routines
  (`$7ACF`, `$7ADA`, ...) show up as the sprite's callers: they called the
  star routine.
- No other code draws these four images.

**Done:**
- **The record:** `SysStarM` replaces the mask's blit. It records the star
  for the buffer being drawn: `SR_V` 2, the image, row `$06` - 35,
  column, shift. It also sets `FT_SEEN`.
- **Both blits still run, with nothing drawn** (`FT_IN` 1, as a fighter's
  parts: `BlitBank` drops them). `SysStarS` replaces the sprite's tail
  call. With the text up or the glyphs in, both draw into the bitmap as
  before.
- **The emit:** the star is a fifth part after the fighters' four. It is
  the merged image the build already made (`star_942A`/`star_94E6` in
  `fighters7800`, formerly `hawk_*`), cut at its rows by `FtPlain`, in the
  black palette.
- **Its objects go after everything in their cells,** black or not:
  `FtSort` leaves them out of the black count, and `FtPlace` puts them
  with the others last.
  - **Fault found on the way:** at first they went with the cell's black
    ones, so the fighters' coloured objects covered the star.
- **The earlier-picture rules apply as to a fighter:** after its emit
  `SR_V` is 1. It goes when an opaque draw covers its box
  (`FR_C0/C1/R0/R1` 4 + buffer: `FgStale`), when its buffer is cleared
  (`FtForget`), or when the other buffer is copied over it (`FtCopyRec`
  copies the star too).
- **No whole-emit skip** (`FtSame`) while a star is shown or was at the
  last emit (`LS_STAR`).
- **RAM:** `ZT_S` is gone. A zone's first line in its cell is now in bits
  4-6 of `ZT_H` (height bits 0-3, BandWrite's flag bit 7). That freed 32
  bytes. The star's tables took 23 of them, so 11 are left.

**Dead end: "the stars broke level 2".** With the stars in, scene 2's
pictures all differed from the reference: the game started earlier and
played differently.
- Bisecting: the build without the star hooks did it too, and the build
  before the star work didn't.
- **The cause was `playkey.lua`:** it counted a flip at any fetch from
  `$9862`, `$0862`'s home, which is in the banked window. Bank 5 had grown,
  and the story's code now sat at `$9862` in bank 5, so every story step
  counted as a flip. The scripted player then pressed early and the game
  started sooner.
- `playkey` now counts `$9862` only with the scene's page in (`S_BANK` =
  `S_SCENEBANK`).
- A first suspicion along the way, that skipping the blitter left the game's
  zero page differently, wasn't the cause. The star's blits still run with
  nothing drawn, though, since that keeps the blitter's side effects
  exactly.

**Checked:**
- `port/checkdl.sh`: scenes 1, 2, 3, 4 and 6 have no picture over 300 pixels
  (scene 0's one is its speed-dependent demo).
- The stars themselves: level 1's first six (`probes/p7800-starlog.lua`)
  at their own (odd) flips against the step-1 build: 54-112 pixels each,
  the fighters' known differences. The star is whole and on top.
- `p7800-bandroom.lua`: no zone loses anything for room.
- `freecheck.sh`: 0 writes.
- Room: fixed bank 15,453, bank 5 14,133.

**The recording batch file** (the user: drag the right ROM onto it, and don't
make builds): `Record Karateka 7800.bat` now records with the `.a78`
dropped on it.
- It copies that cartridge to `inp\NAME.a78` beside the recording, since a
  recording replays only on its own cartridge.
- NAME is the cartridge's name and the next free number; a second argument
  names it instead.
- The patch kit is no longer involved.
- `Play Karateka 7800 Recording.bat` takes a dropped `.inp`.

### Akuma as objects; the princess (2026-10-03)
The user: do what you can with Akuma and the princess; the cutscene figures
go with the remaining scenery.

**The finale measured** (the XEGS playthrough `xe-01-easy.inp`, replayed
with its cheat: `xe-bandlog.lua` now takes `CHEAT`):
- scene 4 runs:
  1. the guard and the player;
  2. the player alone;
  3. Akuma and the player (about 70 pictures);
  4. Akuma, the princess and the player (32);
  5. Akuma and the princess alone (the ending).
- **Akuma's blits:** 4-7 a picture (5 in 99 of 115 pictures).
  - Masks (AND) by `$7B0A`, `$7B4B`, `$7CF9`, `$7D6D`, `$7D2B`, `$7C95`,
    `$7CA5`; sprites (OR) by `$7CFF`, `$7D4A`, `$7D7E`.
  - Almost all mirrored right-aligned, 4 right-aligned. All from scene 4's
    data.
- **His masks hold value 1 widely** (e.g. `$6E5C`: 256 of 600 pixels).
  AND `01` keeps the background's low bit: over black or the floor's grey,
  black. Over the player's white it gives orange, which objects can't
  reproduce.
- **The princess** (`$1E9E`, `$1EE5`, `$1EEE`, `$1EF9`, `$7AE2`; images in
  cart bank 3, up to 46 rows × 3 bytes) is drawn in store mode: opaque
  rectangles.
- **No hawk in this playthrough's finale.** Candidates from level 2: the
  `$7BBA`/`$6DF1` blits of `$6000` (4×5) at moving rows 116-122, and
  `$7DAF`'s masks `$6C8D`/`$6CA8`.

**The blitter kinds** (`probes/p7800-blitkind.lua`): every blit reaches
`BlitBank` through `$29D8`'s header read. Its return identifies the kind:
- `TOP_RETA` `$7C50`: normal;
- `BL_RETAR` `$7DC4`: right-aligned (the game's `$29C2`);
- `TOP_RETM` `$7F84`: mirrored, its column the left byte's;
- `TOP_RETMR` `$7F8D`: mirrored, its column the right byte's.

Every kind places the image the same way: its left byte (column − width +
1 when right-aligned), × 4, plus `$10` / 2.

**Done: Akuma's blits captured** (the plan's "runtime masks", generalised):
- **Capturing:** when FRec meets the scene's own enemy (`$4D` not 0 or 5:
  Akuma), it sets `FT_IN` 2 and starts the buffer's capture (`AK_N` 0,
  `AK_V` 2). `BlitBank` then hands each blit to `AkCap`.
  - It is captured when its image is in the scene's data (`AK_PG0-AK_PG1`,
    `$A0-$BF`), it is an OR or an AND, its kind is one of the four, and
    the buffer has room (`AK_MAX` 10).
  - It records the image and its bank (as `BlitBank` picks it), column,
    row, shift and flags (mirrored, right-aligned, mask). Then the blit is
    dropped, as a fighter's.
  - Anything else is drawn as before.
- **The end of his drawing:** scene 4's `$7C50` (bank 15's jump for the
  scene's own enemy: `JMP $7C56`) is now `JSR SysAkW`. `AkW` takes `$7C56`
  from the return address (+4: `$7C50-$7C56` stay contiguous in the
  scene's page, checked in the ROM), calls it, and sets `FT_IN` 0. So the
  draws after him (the princess) are front boxes, as after a fighter.
- **Emitting** (`FtEmitAk`): each captured blit in order, through `FtPlain`,
  after the fighters' parts and before the hit star.
  - Like the star, his objects go after all the others in their cells, in
    their own order: his masks, then his sprites, over the player as the
    game draws him.
  - A mask is converted at copy time (`FtRowK`): a pixel 3 transparent, any
    other black, in the black palette. That is the best fit for the value-1
    pixels (exact over black and the grey floor).
  - A sprite uses the scene's palette.
  - `FtPlain` takes right-alignment from `S_FMIR` bit 6 (the fighters'
    enemy now `$C0`) and the mask from bit 5.
- **The earlier-picture rules,** as for the fighters and the star: his box
  is `FR_C0/C1/R0/R1` 6 + buffer. `FgStale`, `FtForget` and `FtCopyRec`
  (his blits too) handle him, and `FtSame` doesn't skip while he is shown.
- **RAM:** his tables are at `$1AA1-$1B36`, console RAM that play leaves
  alone. It is written only at boot (`p7800-ramwriters.lua`). The census's
  reads of `$1B00-$1B1B` are page-crossing dummy reads of `ZT_BLO,X`.

**Checked:**
- **Tested on a guard** (`probes/p7800-aktest.lua`): level 1's guard turned
  into an "Akuma" at each record (`FT_IN` 2, the capture from the art
  bank). 1,212 blits captured in 6,000 frames. Each picture matches the
  normal one in place and mirroring, with the upper body's mask black over
  the player. Only the lower body's black is missing: a guard's lower mask
  isn't drawn, the expected difference.
- `checkdl.sh`: scenes 1, 2, 3, 4 and 6 have no picture over 300.
- `freecheck.sh`: 0 writes.
- Room: fixed bank 15,834, bank 5 14,442.
- **Not yet checked:** Akuma himself, the column room with him (his parts
  can take 60-80 columns), and the princess's order. The scripted player
  can't get through the finale's doors. The user's recording with the new
  `Record Karateka 7800.bat` will show them.

**The princess:** left in the bitmap. Her blits are opaque rectangles, so
drawn after a fighter they become an opaque front box over it (black block
and bitmap bytes, now also after Akuma), and drawn before it they stay
behind it, as in the game.

### Fixes from the user's level 3 recording; the hawk as objects (2026-10-03)
The user recorded `inp/karateka7800-level3-invincible-01.inp` (468 seconds,
on `inp/karateka7800-level3-invincible-01.a78`) and reported three faults:
- a black rectangle in front of the belt when a fighter has both feet down;
- Akuma seen through the right-hand wall for a few lines as the room
  changed;
- Akuma's alignment off several times.

The replay also showed the hawk drawn white instead of grey once it became
objects (below).

**Replaying a recording on another build.** A recording plays back only on
the cartridge it was made with; on a new build the game's timing differs,
and the inputs land elsewhere within a few seconds. The fix forces the
recorded game's state onto the new build at every flip:
- `probes/gamestate.py` lists the game's own state to `work/gamestate.txt`:
  451 addresses (its zero page through the build's map, plus the carve
  maps' engine, common and scene flags). Our display code touches none of
  them.
- `probes/p7800-staterec.lua` runs the recording on its own cartridge. At
  each `TopFlip` with `$D0` not 0 it writes those bytes to `state.bin`, one
  record a flip, and each flip's frame to `flips.txt`.
  - Play's flips go through bank 15's `$B60F`, not `$0862` (that one serves
    the title and story only). Both reach `TopFlip`.
- `probes/p7800-stateplay.lua` plays the same recording on the new build
  and writes each record back at the same flip.
  - `SNAPF` takes snapshots of chosen flips.
  - `SPALSO` runs a companion probe (`colroom`, `bandroom`, `slicedump`,
    `blitkind`, `pcsample`).
  - `_G.STATEPLAY_N` gives the companion the flip count.
  - `DIFFLOG=1` logs, before each forcing, the bytes this build's game
    differs in (`diffs.txt`).
- `probes/stateskip.py` finds the bytes that must not be forced. These are
  build-specific pointers, which differ at most of the first flips between
  `staterec` runs on the two cartridges: zero page `$47-$49` and
  `$7F-$81`, plus `$1A22-$1A26`. Forcing them sent the new build into the
  old build's code: the game stopped at flip 1 once the hawk wrapper
  (below) moved code.
- **What the pictures show:** each picture is this build's game stepping
  one flip from the recorded state. A recorded input read at a different
  moment can make that step differ (a different punch, a hit a flip later).
  `DIFFLOG` tells those apart from drawing faults: at 1732-1734 the player's
  move bytes (`$60`, `$65`, `$66`) differ; at 1810 the hit flags (`$43`,
  `$4E`, `$5C`, `$96`) aren't set yet. Where the state matches and the
  picture still differs, it's a drawing fault.
- MAME lessons:
  - The autoboot script's globals aren't the `dofile`d probes'; share
    through `_G`.
  - Two probes must not both assign the same tap variable (`TW`), and two
    taps on the same registers don't both fire.
  - `run7800.sh` sets `END` to 300 unless given.
  - An error inside a tap callback is silent. `p7800-palframe.lua`'s
    `scr:vpos()` (this MAME's screen has no `vpos`) therefore logged
    nothing; it now estimates the line from emulated time, as
    `p7800-colwrites.lua` does.

**The belt** (fixed): the upper body's pose mask (black) was drawn after the
lower body. Its rows over the waist put a solid black band where the
original shows the jacket's white. The draw order (`FT_PORDS`/`FT_PORDE`)
is now each fighter's pose mask, then its lower body, then the rest of its
upper body. The emit order is unchanged; the pose mask's objects end at
`PO_ST+7`/`+8`.

**Akuma through the wall** (fixed): at frame 21,540 a stray line showed at
row 155, columns 37-39, inside the doorway post's front box. The zone's list
had run out of room, and the front-box overlays go first when it does. The
doorway's scenery is recorded as several narrow boxes side by side, each
costing list bytes in every zone it crosses. In `FgBox` (bank 5):
- **Side-by-side merge:** two boxes of the same kind whose rows are within
  one of each other and whose columns touch become one. Opaque unions may
  be at most `FT_BLKW` (16) wide, see-through ones 31.
- **Splitting:** an opaque box wider than the black block is split into
  boxes `FT_BLKW` wide.
- These come on top of the containment merge (a box inside another is left
  out).
- Refreshes with drops on the replay went from 16 to 4.

**Akuma's alignment** (fixed): his placement was right (checked by
simulation and the guard test). His slices were left out for want of
columns: 179 slices on the replay. Two changes:
- **The black block is 16 columns** (`FT_BLKCOL` 240, `FT_BLKW` 16; it was
  32 at 224), so the parts have 240 columns (`FT_COLS`).
- **Mask and sprite pairs merged** (`FtAkPair`): a mask followed by a
  sprite with the same column, row, shift, bank, kind and width is emitted
  as one image (`FP_PAIR`). `FtRowP2` builds each row from both:
  - the sprite's pixels, grey made white;
  - else black where the mask clears (not 3);
  - else transparent.

  Both use the black palette. The mask's pointer is the game's `$14/$15`,
  saved in `FP_Z14` and restored after. `FtPairNext` steps both images; a
  pair's rows are the larger of the two.
- Slices left out on the replay went from 179 to 7.

**Room:**
- The fixed bank filled, so the front-box recorder (`FgRecB`, `FgColB`,
  `FgBox`, `FgSide`, `FgStale`) moved to bank 5 behind fixed stubs
  `FgRec`/`FgCol`. The return address on the stack moves with it: `TSX`
  offset `$0108` → `$010B`.
- `FT_RAM` filled, so the star's tables moved into the Akuma region
  (`$1B37` on).

**The hawk as objects:** level 3's hawk is drawn by the level's loop, `$7B09`
`JSR $6980`. It is now `JSR SysHawkW`: `HawkW` sets `FT_IN` 3 around the
call, so `AkCap` captures its blits as Akuma's. When objects are off (text
up, glyphs in), it is drawn as before.
- **Its blits** (bank 3):
  - the floor shadow's mask, `$AC8D`/`$ACA8` (row 122-124);
  - the body masks, `$A600`/`$A652`/`$A681`;
  - the sprites, `$AAC5`/`$AB2B`/`$AB64`, 5 bytes wide and 11-20 rows.
- The capture list now starts afresh at each buffer's first capture after
  an emit (`AK_FR`), since Akuma's and the hawk's share it.
- **Colours:**
  - **The sprites:** mostly grey (2), a white head (3) and up to 7 skin
    pixels (1, the talons).
  - **The masks:** only 0, 2 and 3.
  - **The first conversion:** the Akuma pair merge made the hawk white
    (grey made white in the black palette).
  - **Unmerged:** the hawk kept its grey, but its masks took their own
    columns. At peaks the hit star, emitted last, lost its slices: 64 left
    out on the replay, 44 of them the star's. Flip 1738's star was missing
    with the game state matching.
  - **Now:** the hawk's pairs merge into palette 3 (`TOP_PAL2`), which
    holds black, grey `$08` and white `$0E` in level 3. It is set at the
    top of the screen (`TopColours`) and not rewritten in the band,
    measured with `probes/p7800-palwrites.lua`. The band's palette 1 has
    the same grey and white.
    - `FP_PAIR` 2 (sprite flag bit 4, set by `AkCapK` for `FT_IN` 3)
      selects `FtRowPH`: black as colour 1, the sprite's pixels kept, skin
      made grey.
    - `FtObj` takes `S_FPAL` bit 6 as palette 3.
  - **The cost:** the talons are grey instead of skin, a handful of pixels.
    The user accepted grey talons (2026-10-03).
- **Checked on the replay** against the recording's own cartridge:
  - the hawk matches;
  - flip 1738's star is back;
  - the remaining differences at 1734, 1748, 1750, 1806 and 1810 are input
    timing (`DIFFLOG`).

**Measured on the replay (this build):**
- 8 slices left out (frames 3294, 13592, 15309, 15310, 23685, 24974,
  25485, 25532: single slices);
- 5 of 2,358 list refreshes with a drop (most bytes 376);
- `checkdl.sh`: no picture over 300 in scenes 0-4 and 6; `freecheck.sh`:
  0 writes.
- Room: fixed bank 15,546 of 16,384 used, bank 5 15,646.

## The rest of the buffer: the plan (2026-10-08)
The user: look at the memory map and the banks' organisation, and plan how
to remove the rest of the buffer.

### Today
**What the buffer still is:** rows 65-145 of both pictures, 81 rows × 40
bytes × 2 = 6,480 bytes in cart RAM pages `$58-$72` (offsets 16-255, six
rows a page: A in columns 0-2, B in 3-5). Rows 0-64 are captured pieces
(the top rows' machinery). The fighters, the stars, Akuma and the hawk are
objects. Everything else in the band is still bitmap: the game draws it, and
each band zone shows it as two 20-byte objects under the actors.

**Cart RAM (`$4000-$7FFF`), by page:**

| Pages | Holds |
|---|---|
| `$40` | the XEGS gaps' homes, the story's text pointers |
| `$40-$4E` | the top rows' piece data (15-row grid, offsets 16-254) |
| `$4F-$53` | the top zones' list slots (10 × 60 bytes a buffer) |
| `$54-$56` | the band zones' lists (the title's canvases when it is up) |
| `$57` | the top pieces' lists |
| `$58-$72` | **the buffer** (rows 65-145, both pictures) |
| heads of `$4B-$5A`, `$64-$72` | each band zone's own 16-byte list |
| heads of `$5B-$63` | the front boxes |
| `$73-$7A` | the actors' slices (240 columns + the 16-column black block) |
| `$7B` | the actors' sort, the band lists' overflow tails |
| `$7C-$7F` | the blitter (engine part 2's self-modifying module) |

Console RAM is full the same way: the actors' tables at `$1AA1-$1DF5`,
the DLLs and zone lists at `$2200-$25FF`, the system variables at `$1E00`.
The free-RAM ledger lists only page heads and 7 bytes.

**ROM** (128K SuperGame, 8 banks): about 4K free in all.

| Bank | Holds | Used | Free |
|---|---|---|---|
| 0 | scene 0 (title, story, attract) | 16,195 | 189 |
| 1 | level 1 and the vs fight | 16,249 | 135 |
| 2 | level 2 | 15,724 | 660 |
| 3 | level 3 | 15,742 | 642 |
| 4 | the finale | 16,227 | 157 |
| 5 | spare: top rows (about 4.7K), front boxes (0.85K), the actors' emit and band lists, title and story | 15,646 | 738 |
| 6 | the art (and the converted fighter parts) | 15,771 | 613 |
| 7 | fixed: bank 15, engine parts, system code | 15,546 | 838 |

**What the game still draws into rows 65-145** (the 7800 build's own
buffers, `fb78-s<N>` dumps every 5 flips through `probes/rowana.py 65 145`,
which now takes any `-s<N>` folder; and the original's draw logs `bl-s<N>`
through `probes/upperana.py 65 145`):

| Scene | Background rows | Pieces |
|---|---|---|
| Level 1, vs fight | 65-76 the fence (a 12-byte pattern whose phase scrolls), black to 117, the ground (`$55`) 118-145 | the posts (stacks of 2×2 tiles `$6684`/`$668A`, bases and caps `$66C0`, `$687B`, `$66A6`, `$66EF`, `$66D4`, `$6877`, `$6703`, `$685F`, `$6865`, `$6C1A`), the fence rails (`$6A11` at every even column, `$6A31`/`$6A23` plain and mirrored) and edge (`$69B8`, `$69E2`), the torii's pillar (a stacked 1×4 tile `$6B8E`, `$6B94`, `$6B4A`, `$6B7C`) and its 29-row shadow `$6A7D` |
| Level 2 | the wall's last rows 65-66, black, the floor 118-145 (alternate rows `$55` and black) | the gate building's door `$6602` (122 rows × 8 bytes, rows 22-143; its upper part is already a top piece), `$65B8`, the wall joints |
| Level 3 | black, the floor 118-145 (alternate rows: an 18-byte perspective pattern, black) | the door frames scrolling in (`$964A` 65×2, `$96CE` 77×1, `$971D` 8×4, art bank) |
| Finale | as level 3 | the frames at both edges, wiped and redrawn every picture; the princess (store-mode rectangles) |
| Cutscenes (attract, between levels) | black, floors | the figures (art bank `$974B` 43×6, `$9EB8` 42×5, `$9F8C`, `$9FC4`, `$984F`; Mariko `$1CC4`-`$1D00`), the princess's room (`$1200` 9×22, `$12C8` 50×10, `$14BE`, `$18BF`, `$18D0`), level 1's Akuma cutscene pieces (`$63C5`-`$65CC`) |
| Any level | | the player's death sprites (`$1E00`-`$1ED3`, scene code `$6C48`/`$6C4C`): still bitmap draws |

**The fills:** the largest are bank 15's `$A7C2` (rows 79-117) and the
levels' floor patterns (`$7A0F`, `$7A12`, `$7B25`, `$79E7`, ...; rows
118-128) over each fighter's box, every picture. They only erase the
fighters from the bitmap, which no longer has them. The rest are region
wipes at the scrolling edge (`$6FCC`, `$6FDB`, `$6FEA`, `$7247`, `$708B`,
`$7178`, `$B8AF`, ...), the top rows' own case.

**What the drawing costs** (`p7800-pcsample.lua CYCLES=1`, frames
4000-6000, the invincible-easy cart): the blitter (`$7Cxx-$7Fxx`) takes
about 20% of the CPU in level 1, 21% in level 2 and 38% in level 3; the
fast fill another 6-7%. The top rows' capture takes 5-8%. With the actors
already objects, almost all of the blitter's time is this scenery.

### The design
**The band becomes a scenery layer built from the game's own draws,** as
the top rows are. Each draw is captured, kept as a piece in the buffer's
list and dropped (never blitted). Each zone's list is then back scenery,
then the actors, then the front scenery.
- **One grid:** the band's 8-line zones (`BAND_ZH`) for all of rows
  65-145. The piece data goes into slices as the actors' does (one byte
  column in 8 consecutive pages), so a piece is cut on the grid once when
  it is captured.
- **Piece kinds** (the top rows' kinds, plus three):
  - **an image** at its row and pixel, plain or mirrored at copy;
  - **a column stack:** one image repeated down (a post, the pillar),
    captured as one piece. Its slice holds the repeat once, so every zone
    it crosses shares one data column. The port's column routine
    (`ScColA`/`ScCol68`) already draws these and is where they're captured;
  - **a tile strip:** a run of one image at successive columns (the fence
    rails, level 2's joints), kept as a few 24-byte objects reading one
    tile, placed by the run's phase;
  - **a uniform area:** black needs nothing (the background colour). The
    ground and the floors' coloured rows are objects reading a stored run
    of their byte, 2 a line (about 35 of a line's 113 cycles, what the
    bitmap's two objects cost now);
  - **opaque pieces** (the princess's store-mode blits) as the top rows'
    opaque conversion does (palettes 2 and 3).
- **The erase model** (the top rows' rule): a fill wipes the pieces it
  covers, and a draw adds one. The fighter-box fills (`$A7C2` and the floor
  patterns) are dropped outright, since they erase only what is now an
  object. To check: nothing else relies on them.
- **In front:** a piece drawn after a picture's actors is a front piece,
  later in the zone's list. That replaces the front boxes, their recorder
  (`FgRec`, `FgBox`, `FgSide`, `FgStale`: 0.85K in bank 5, a hook in the
  fixed bank) and the black block (16 columns back to the actors).
- **Unchanged:** the actors' machinery, the top rows (rows 0-64 keep their
  15-row grid; merging the two grids is later work, not needed for this).

**The memory map after:**
- Pages `$58-$72` (6,480 bytes) become the scenery's slices. Three 8-page
  blocks (`$58-$5F`, `$60-$67`, `$68-$6F`) give 720 slice columns, plus
  `$70-$72`.
- Each room's scenery is about 0.5-2.5K: the door 1K, a post's stack one
  2-byte column and its pieces, the frames about 0.5K with their mirrored
  copies, the cutscene figures 1.2K, the princess 0.6K. It is stored once
  and shared by both buffers when both show it.
- Only the lists are per buffer (about 3-8 scenery objects a zone), in the
  band heads and areas as now. The buffer's two objects a zone are gone.
- The page heads of `$5B-$63` go back when the front boxes do.
- The blitter stays in `$7C-$7F`: the capture hooks its header read, so
  its body no longer runs for captured draws.

### Stages
Bottom up, then top down, every scene at each stage, as `FB_TOP` 45 → 65
was done, so each stage gives the next its RAM. Pieces that cross the
boundary are clipped (the top rows' `TopVis` does that today at row 65).
0. **Tools first:**
   - a 7800 band log (`xe-bandlog.lua`'s output, for the port's own
     draws after the actors' capture);
   - a zone budget simulator (`upperplan.py` for 8-line zones: objects and
     MARIA cycles a line, with the actors' objects from the replays);
   - the state replay of the user's recordings as the regression next to
     `checkdl.sh`.
   - A quick win to try on its own: drop the fighter-box fills and check
     the pictures unchanged (a speed gain with no RAM or ROM cost).
1. **Rows 118-145 (the floors):** the ground and floor rows as uniform
   areas and tile strips (level 3's perspective rows to check: do they
   change with the room?); the post bases and shadows, the frames' bases
   and the room's floor as pieces. `FB_ROWS` 146 → 118. Gives back 9 pages
   (2,160 bytes).
2. **Rows 65-78:** the fence as a tile strip at its scroll phase, level
   2's wall rows, the posts' and frames' tops. `FB_TOP` 65 → 79. Gives back
   5 pages (1,200 bytes).
3. **Rows 79-117:** the posts and pillar as column stacks, the door, the
   frames, the cutscene figures, the princess, the death sprites. The
   buffer is gone (the last 13 pages, 3,120 bytes).
4. **Afterwards:** the front boxes and the black block removed; the
   blitter's and fills' play paths checked unused; the RAM map redrawn and
   the ledger updated.

Checks at each stage: `checkdl.sh` (pictures against the stable
references), the state replay of the user's recordings, `freecheck.sh`,
the zone budget, and hardware.

### Budgets
- **MARIA:**
  - Every black row stops costing the bitmap's two objects (about 35 of
    113 cycles a line, rows 70-117 in most rooms). Since DMA halts the
    CPU, that comes back as CPU too.
  - The busiest zones become the floor zones (2 run objects, the actors'
    feet and shadows, bases) and level 1's post zones. The simulator
    (stage 0) settles it before any build.
- **CPU:** the blitting of the scenery and the fighter-box fills go (about
  25-45% of a picture's work today). The capture costs some back: the top
  rows' share is 5-8% for 5 zones.
- **ROM:** the band's kinds and tables are about 1.5-3K. Bank 5 has 738
  free, and the front boxes give back 0.85K once gone. See decision 2.
- **RAM:** the scenery data fits the freed pages with room to spare; the
  lists use what the bitmap's objects used.

### Decisions for the user
1. **The game's speed.** The game is CPU-bound: a picture is about 12-13
   frames of work in levels 1-3 ("Performance against the original"), and the
   fighters move a step a picture. Removing the drawing makes the game
   itself faster than the original. Options:
   - a pace cap at the original's frames a picture, per scene (measured
     on the XEGS, or by the cycle counts above);
   - let it run faster (a kit option, perhaps);
   - or both.
2. **ROM.**
   - Moving to a 256K SuperGame cartridge doubles the room. It needs
     checking on the user's 7800 core for the Pocket, MAME and the cart
     formats the user cares about.
   - Or reclaim: level 1's page holds about 2K of other scenes' sprite
     copies no level-1 code draws ("ROM room: what the scene pages
     duplicate"); the front boxes 0.85K; code the bitmap needed.
3. **The order of the stages:** bottom up as above (the floors first:
   most rows, simplest content), or the middle first (the most CPU: level
   3's frames, level 1's posts).

### Open
- Level 3's floor perspective rows: fixed per room or redrawn with the
  scroll.
- Level 2's door: opened by redrawing (a sequence of pictures) or by
  fills; the capture model for it.
- The game's DLIs inside the band (colour changes) against the new
  zones.
- The death sprites and level 1's Akuma cutscene: who draws them and in
  which buffer.

### The fighter-box fills dropped (2026-10-08)
The user: drop the fills that are unused; they had wondered why the port
went little if at all faster once the fighters were objects.

**Why it wasn't faster:** every picture, the game still erased each
fighter's box from the bitmap, which no longer had the fighters in it.
Bank 15's erase (`$A780` the enemy's, `$A78C` the player's, one body at
`$A797`):
- fills rows 79-117 black over the box (`$A7C2`, `JSR $2CCD`);
- then refills the floor rows 118-128 with the level's pattern or fill
  (the tail jumps at `$A7F1`, `$A800`, `$A809`, `$A812`).

Every level calls only these two entries (all 25 `JSR $A780`/`$A78C` in
the cartridge; nothing else enters the body).

**The fills still have a job:** every draw passes `RowBase`, whose front
box recorder (`FgRec` → `FgBox` → `FgStale`) removes an earlier picture's
fighter record under an opaque draw. So a dropped fill keeps its
bookkeeping and paints nothing: with `S_NOFILL` set, `RowBase` sends it to
the scratch row (`RowOff`).

**First try, every erase dropped:** level 1 +7.6%, level 3 +3.8%, but a
ghost stayed on the ground in level 1 and the attract demo (10 and 3
pictures over 300). It is the player's opening pose: drawn into the
bitmap by level 1's own code (`$7B9E`: `$63C5`, `$63E9`; found with a write
watch on its bytes and `probes/p7800-blitwin.lua`), not through `FRec`,
and in the original erased by the player's erase once he moves.

**Second try, decided by the record (`FR_V` 1, an object last time):**
pictures clean, but level 1 only +3.9% and level 3 +0.3%
(`probes/p7800-erasedec.lua`):
- the player's erase runs first, and its bookkeeping wipes the enemy's
  record wherever the boxes overlap (any fight), so the enemy's erase then
  paints;
- with no enemy, the game parks its column at `$EE`, and bank 15 clamps
  that to column 0: the absent enemy's erase painted columns 0-10 every
  picture.

**Done:** each erase decides at its entry (`ErP`, `ErE`, through `SysErP`/
`SysErE` at `$A78C`/`$A780`) and keeps the decision for its fills
(`S_ERS`; `NoFill`/`NoPat` at the five fill sites). `FT_DRW`, one byte a
record, says how the fighter was last drawn in that buffer:
- 1: as objects (`FRec`);
- 2: into the bitmap (the glyphs in, or the scene's own enemy, Akuma);
- 0: not drawn.

The erase takes the byte (sets it back to 0). The player's erase paints
unless it was 1, since its 0 is the level's own figures (the opening pose,
the cliff fall). The enemy's paints only at 2, since its 0 is no enemy.
With the glyphs in, everything paints as before. RAM: `$1F79-$1F7E` from
the ledger's run (`$1F7F` left).

**Result**, flips by frame 20,000 (scripted player, invincible-easy, same
method for both builds):

| | before | after |
|---|---|---|
| level 1 | 3,213 | 3,448 (+7.3%) |
| level 3 | 1,941 | 2,014 (+3.8%) |

**Checked:**
- `checkdl.sh`: no picture over 300 in any scene.
- The cliff fall (`QUIET=200`: left held from the start of level 1, the
  death sprites `$1E00-$1ED3` are bitmap draws): 126 pictures every 2
  flips, all the same as the build before.
- `freecheck.sh`: 0 writes.
- Fixed bank 15,707 of 16,384.

### Level 1's page: the copies no one reads (2026-10-08)
The user: check that the sprite copies in level 1's bank are unused,
remove them and test again.

**Correction to the plan:** of the 21 copies (1,989 bytes, "The sprite
tables walked"), `$12C8-$1587` (704 bytes) already holds the vs fight's
helpers (`VS_BLOCK`). What was left as data:
- `$1203-$12C7`: the princess room's floor (its header is in engine part
  1);
- `$1588-$18CF`: the intro's figures;
- `$1CC4-$1DFA`: Mariko's pieces.

That is 1,348 bytes, not about 2K.

**Checked unused:**
- `probes/p7800-bankreads.lua`: every read of those addresses with bank 1
  in the window. Runs:
  - level 1 through to level 2's load (60,000 frames, invincible-easy);
  - level 1 on the normal cartridge (40,000);
  - the cliff fall;
  - the vs fight (30,000).
- No reads, except one in the vs fight: `$8204` "read" by a `BMI` at
  `$82FC`. That is the 6502's dummy read when a taken branch crosses a
  page (old page, new low byte: the target is `$8304`), not a use.
- The census executed nothing in those ranges in any run.
- At build time: no instruction, label or relocation of scene 1's or 6's
  is in them.

**Done:** `layout7800.PAGE_RELEASE` lists them, and the build leaves them
out of the page after placing its chunks (`Image.release`), with that
check. Bank 1: 16,249 → 14,901 bytes used. The level-1 code's largest part
(390 bytes) moved into the freed run at `$8588`, so bank 1 has 1,483 bytes
free. Only level 1 and the vs fight can use it (it is their page).

**Checked:** `checkdl.sh` clean; the cliff fall the same; `freecheck.sh` 0
writes. Checkpoint `2026-10-08_KEEP_enh-nofill`.

### The floor: what draws there, and what objects would cost (2026-10-08)
The user: work on the cheapest part, the floor (rows 118-145), and free its
2,160 bytes. Measured before building; stopped to report.

**`probes/p7800-floorlog.lua`** (every draw reaching `RowBase` whose rows
meet 118-145: blit or fill, source, mode, rows, columns, fill bytes, in
front of the fighters or not, caller; each scene's scripted run, the
attract, the cliff fall). At `RowBase` entry the stack holds the stub's
return first; the draw's kind is the second return, its caller the third.

What still draws on the floor:
- **The fighter-box floor patterns** (`by E9C5`, `NoPat`): the most
  frequent, now painting nothing.
- **The background:** each floor row is one byte across:
  - level 1 and the vs fight: the ground, `$55`;
  - level 2: rows alternating `$00`/`$55`;
  - levels 3 and 4: `$AA`/`$00`, narrowed to a perspective trapezoid where
    the frames stand.
- **Pieces**, all store-mode blits (opaque: their black pixels show):
  - level 1: the posts' bases and the pillar's shadow (`A325`, `A34F`,
    `A2E0`, `A310`, ...), redrawn as they scroll, with edge wipes (`rect`
    `AFDD` cols 28-40);
  - level 2: the door's bottom (`A604`, rows 22-143);
  - levels 3 and 4: the frames' lower parts and feet (`964C`, `96D0`,
    `9745`, `971F`), every picture, one of them in front of the fighters;
  - the cutscenes and the attract: the princess room's floor and furniture
    (`B702`, 23 bytes wide; `B7CA`, `B9C0`, ...) and the intro's figures;
  - the cliff fall: the death sprites.

**The correction:** the plan's "frees 2,160 bytes" counted the buffer's
floor rows but not the objects' own data. As objects, every floor piece
needs its rows in slices (column-shaped RAM, one byte column in 8
consecutive pages), and those can only go in the pages the floor gives
back. Floor pieces each kept once, by run:

| run | pieces | slice bytes |
|---|---|---|
| level 1 | 44 | 3,520 |
| level 2 | 20 | 2,392 |
| level 3 | 14 | 1,704 |
| finale | 4 | 168 |
| vs fight | 3 | 152 |
| attract | 51 | 3,784 |

These are totals over each run; at one moment less. But the princess room
alone shows about 1K of floor pieces. With the fill runs (about 320 bytes
for the two background bytes) and per-buffer copies where the buffers
differ, the floor as objects would give back roughly 0-1.2K, not 2,160.

**What it would take:** a capture engine for the band like the top rows':
- floor blits kept as pieces in each buffer's list, store-mode ones over a
  black underlay;
- fills setting the rows' background and wiping the pieces they cover;
- front pieces after the fighters' objects;
- their slices copied as the actors' are.

The top rows' code can't serve as it is: it is built for its region (five
15-row zones, `TOP_Z0-4`, 16 uses of `FB_TOP`), and floor zones share
their lists with the fighters' feet (`BandWrite`). Roughly 1-1.5K of new
code, against 738 bytes free in bank 5.

**What the floor would still give:** CPU. Its blits and fills would be
captured and dropped (level 3's frames alone are 8 blits a picture), and
the rows' DMA would cost less.

### The copied sprites' originals given back (2026-10-09)
The user: any other optimisations to free space?

**Found:** scenes 0, 2, 3 and 4 draw scene-code sprites from copies in the
art or fixed bank (`SPRITE_COPIES`, `ART_COPIES`: the pointers resolve to
the copy), but every scene page still held the originals at their own
addresses, byte for byte.

**Checked unused** (`probes/p7800-bankreads.lua`, which now takes
`NOPLAY=1` for a recording; ranges in `work/analysis/deadcopies.txt`):
- the attract loop, 40,000 frames;
- the title to level 1;
- levels 2 and 3 and the finale, scripted (40,000 each);
- the user's level 3 recording through the finale and the ending, on its
  own cartridge (the `2026-10-03_KEEP_enh-akuma` checkpoint's symbols).

No reads, except 18 in the ending at `$8F00` and `$8FA3` by `$8EFE`. Scene
4's `BPL $1EA3` at `$1EFE` is the last instruction on its page, and a taken
branch across a page puts the next opcode's address and the fix-up
address on the bus. The same artefact as level 1's `$8204` read.

**Done:** `PAGE_RELEASE` for scenes 0, 2, 3 and 4. The build's check found
no instruction, label or relocation in them.

| bank | before | after | freed |
|---|---|---|---|
| 0 | 16,195 | 14,146 | 2,049 |
| 2 | 15,724 | 14,223 | 1,501 |
| 3 | 15,742 | 14,110 | 1,632 |
| 4 | 16,227 | 14,219 | 2,008 |

That is 7,190 bytes, and with bank 1's 1,348 about 8.5K in the scene
pages. Each page's room serves only its own scenes: scene-specific code
and data, not shared code (that needs bank 5 or the fixed bank).

**Checked:**
- `checkdl.sh` clean; the cliff fall the same; `freecheck.sh` 0 writes.
- The user's recording replayed through the ending on this build against
  its own cartridge: 16 of 17 pictures the same. The one that differs
  (flip 2680, the princess's arm a picture later) has the game state
  departing there (`DIFFLOG`: the player's move bytes, the joystick latch
  `$1A9A`): input timing, not drawing.

Checkpoint `2026-10-09_KEEP_enh-pagerelease`.

**Not reliable for finding dead code: the original's census.** It calls
common's `$0900-$098F` untouched, but that is the vs fight's routine
(`$0900`), and it misses bank 15's cutscene code (`$B866-$B980`) that the
attract runs. Dead code in common (copied into every scene page, so worth
five times its size) or bank 15 needs coverage runs on the 7800 build
first.

### Coverage: common and bank 15 (2026-10-09)
The user: go for the coverage runs (dead code in the common code, which
every scene page holds, and in bank 15).

**`probes/p7800-coverage.lua`:** every address read, instruction fetches
and data alike, in the common code (`$96E8-$9FFF` with a scene page in)
and the fixed bank, as bitmaps.
- Counting starts at the BIOS's hand-over (its write to `INPTCTRL` `$0001`
  with bits 0 and 2), since the BIOS reads the whole cartridge for its
  signature check. Counting from frame 600 instead lost the game's boot
  code (7,124 bytes read against 7,487).
- **The runs** (12, this build):
  - the attract loop, 60,000 frames;
  - level 1 to level 2's load;
  - levels 2 and 3, the finale and the vs fight, invincible;
  - levels 1-3 on the normal cartridge (deaths, game over);
  - the cliff fall;
  - the user's recording through the finale and ending, replayed on this
    build (`p7800-stateplay.lua`, `SPALSO`).
- **`probes/coverage.py`** maps the bytes back (common at +`$9000`; bank
  15 and the engine parts through scene 1's resolver), adds the original's
  census (executed instructions with their operands, data reads), and
  lists what neither touched (`work/analysis/coverage-dead.txt`).

**Untouched, in runs of 16 or more:**
- common: 584 bytes in 7 runs;
- engine part 2: 496 in 7;
- bank 15: 269 in 13;
- engine part 1: none.

**Most of it is live on paths no run takes, so kept:**
- common `$0905-$095F` and `$09F9-$0AF5`, next to the vs fight's `$0900`,
  read `$D011` (the second joystick's trigger): two-player paths;
- engine part 2's `$2374` table (a descending 16-bit list, pitches of
  notes not played);
- bank 15's code runs.

**Released:** only the zero padding, all of it never read:
- **common** (`COMMON_RELEASE`, in every scene page): `$07E6-$07FF`,
  `$0D8B-$0DFF`, `$0EB5-$0EFF`, 218 bytes a page, 1,090 in all;
- **the fixed bank** (`FIXED_RELEASE`, new: the same check, and the range
  must lie in the fixed bank in one run): engine part 2's `$2656-$26FF`,
  `$27DB-$27FF`, `$2DE4-$2DFF`, `$2FD4-$2FFF` (module ends), and bank 15's
  `$AD59-$AD74`, `$B2F0-$B2FF`, 323 bytes.

The build's check found no instruction, label or relocation of any scene
in them. Fixed bank 15,707 → 15,384 (1,000 free); scene pages 0-4 218 each.

**Checked:**
- `checkdl.sh` clean; the cliff fall the same; `freecheck.sh` 0 writes.
- The recording's ending: as before (16 of 17; the one input timing).

Checkpoint `2026-10-09_KEEP_enh-coverage`.

**ROM now** (the copies' originals, these, bank 1's copies):

| bank | free |
|---|---|
| 0 | 2,456 |
| 1 | 1,701 |
| 2 | 2,379 |
| 3 | 2,492 |
| 4 | 2,383 |
| 5 | 738 |
| 6 | 613 |
| fixed | 1,000 |

### Which bank is in the window during play (2026-10-09)
The user: which bank is active during gameplay, the scene bank or another?
`probes/p7800-bankshare.lua`: at every CPU read of `$8000-$FFFF`, frames
4000-6000, the window's bank (`S_BANK`) and where the code runs.

| window | level 1 | level 2 | level 3 |
|---|---|---|---|
| the scene page | 52% | 48% | 42% |
| bank 5 (the port's system code) | 39% | 46% | 48% |
| bank 6 (art: blits reading images) | 9% | 7% | 10% |

- **The scene page:** in while the game's logic runs, mostly bank 15's
  code in the fixed bank with the scene page left in (35-46%), plus the
  scene's own code (5-7%).
- **Bank 5:** in almost as long. That is the top rows, the actors' emit and
  the band lists.
- **The weighting:** by reads, so time in the blitter (cart RAM) is
  undercounted.

So MARIA can't take graphics from the window (any of three banks may be in
when it fetches), and shared code has room only in the fixed bank and bank
5.

### The floor as a repeating slice and end objects (2026-10-09)
The user: the answer is RAM, unless that can change; the background is
already in each scene's page; reduce it to a repeatable slice and the end
objects.

**Measured** (the 7800 buffers' floor rows, `fb78-s<N>` dumps every 5
flips, both buffers): each row's background is its most common byte, and
an end object is any column of a zone where a row differs from its
background.

| scene | background patterns | end-object slice bytes, both buffers (avg / 95% / max) | end objects a picture (avg / max) |
|---|---|---|---|
| level 1 | `$55` all rows (and `$AA/$00` in 16 pictures: its cutscene) | 115 / 528 / 1,152 | 2 / 26 |
| level 2 | `$00/$55` alternating | 270 / 288 / 288 | 7 / 8 |
| level 3 | `$AA/$00` alternating | 539 / 608 / 992 | 14 / 18 |
| finale | `$AA/$00` alternating | 544 | 20 |
| vs fight | `$55` | 144 | 6 |

This corrects "The floor: what draws there", which counted every piece's
whole image.
- **The background:** three patterns in all. A zone starts on an even row
  (118, 126, 134, 142), so one 8-line slice serves each pattern: 20 bytes ×
  8 lines = 160 bytes. Three would fit in the fixed bank (the one bank
  always mapped, since MARIA can't read the window: "Which bank is in the
  window"), no RAM.
- **The end objects:** about 300-600 bytes of RAM in play. The peaks are
  level 1's princess-room cutscene, with no fighters, so their slice pages
  could take them.
- **Net:** about 2,160 − 600 (end objects) − about 500 (longer zone lists)
  ≈ 1K given back, plus the floor's drawing gone.
- **Exactness:** the background objects leave out the end objects'
  columns (an end object's black pixels would otherwise show the stripes),
  and store-mode end objects that overlap need a black underlay.
- **Open, the user's call:**
  - capture at run time (the game's floor fills and blits as an ordered
    stack per buffer, items dropped once covered: every floor as drawn,
    and the engine serves the middle later; about 1-1.5K of code);
  - or floors precomputed per scene from the scene page (less code, but
    every floor state each room reaches must be listed).

## The floor as tiles: the design (2026-10-09)
The user chose the tile map (the floor as character codes, private tiles
copied on first write) over an item stack, and RAM (not the fixed bank) for
the floor's data.

**Layout:**
- `FB_ROWS` 146 → 118: the bitmap holds rows 65-117, `FB_BAND` 18, pages
  `$61-$72`.
- The floor is rows 118-145 in four zones: 118-125, 126-133, 134-141 and
  142-145. They start on even rows, so the stripes line up.
- **The character set** (`CHBASE`) is pages `$58-$5F`. A character is 2
  bytes wide (`CTRL` bit 4), its line L in a zone of height H at page
  `$58 + H - 1 - L`. Codes 16-214 (100 characters); code 16 is the zero
  tile, never freed.
- The pages' offsets 216-255 hold each buffer's four 20-code maps and the
  characters' use counts. Page `$60` holds the scratch row and the floor's
  variables.

**Display:** each floor zone line is one indirect object (5-byte header,
`$60`) reading its map's 20 codes. Zones 134-145 have no actors, so their
lists are fixed per buffer (the map changes underneath). Zones 118-133 are
band zones (`BandWrite`): the indirect object, the fighters' objects, and
for a front box one direct object a cell reading its character (a
character is a slice).

**The grid:** the bitmap's columns are 18 rows (8, 8, 2), so a band cell is
`column × 3 + row in column / 8`. The floor cells are 9 (118-125) and 10
(126-133). The fighters' parts are cut again by the build. The tables sized
by the cell count (`FC_*` on page `$7B`) grow to 11.

**The DLIs:** the music DLI after row 140 (the fifth) moves up to row 117.
A DLI line is a zone of its own, and the floor's zones must stay whole.

**Writes:**
- A byte: its cell's character copied first if shared (use count over 1,
  or the zero tile), then written.
- **Fills** (`RowBase` sees the rows): the floor part goes to the tiles;
  the bitmap part is cut at row 118. A cell the fill covers across gets a
  character from a memo (old code → new), so a full-width fill gives one
  character a zone, not twenty. A pattern fill cut by an odd number of rows
  has its two values swapped for the bitmap part, and swapped back at
  `FillPat`'s end.
- **Blits:** the game's own blitter draws each floor row into a 48-byte
  scratch row, which is first filled from the tiles over the blit's columns
  and merged back (changed bytes only) at the row's step.
  - Blitter A's step (`$295F`, cart RAM) is patched to the port's for a
    blit that reaches the floor and restored at its end (`BlitDone`).
  - The mirrored blitter's step is `RowNextC` already.
- **Others:** the level 1 column routine (posts reach row 136), the
  game's full clear (maps to the zero tile) and buffer copy (maps copied,
  use counts up).

**Steps** (each built and checked):
1. layout, grid, builder, `CTRL`/`CHBASE`, a blank floor;
2. the tiles and the fills;
3. the blits;
4. the front boxes;
5. the column routine, clear and copy;
6. checks: `checkdl.sh`, the fall, the recording, free RAM, MARIA's time
   on the floor lines, characters running out.

### The floor as tiles: steps 3 and 5, and the speed (2026-10-09)
Test cart `work/fl-ie.a78` (invincible, easy); reference: the build before
the floor, `work/nofill-ie.a78`. Each level was run with the scripted input
(`SCENE=1-4 FIREFLAG=1 INJECT=1`) and compared at flips 100-800.

**Faults found and fixed:**
- **Level 2-4 hang (flip 412, level 3).** Bank 15's door-frame routine
  (`$B866`-`$B8B2`) keeps an object's index in X from one blit to the next
  (`JSR $B8F9` then `JSR $B908`, same X). The floor code changed X: FlDraw's
  `TSX`, FlUnswap, and the scene-page row routines. The next mirrored blit
  then read its source, column and row from the tables at a wrong index (src
  `$63AD`, 0 rows: a 256-row blit that ran past row 145 and wrote over RAM).
  X is now kept in every floor routine the blitters reach (`FL_XS`).
  Found by logging every blitter call with its caller and parameters in
  both builds (`probes/tmp-blitcalls.lua`, zero-page reads through the
  `.zp` map: the game's `$03` is the 7800's `$C9`).
- **Doubled stripes and a stray line under the fighters' feet.** The
  floor's zones were split in the DLL:
  - Row 133 came out a zone of its own. `space_dlis` moved the fifth DLI
    from row 132 up to 117 and left that run cut in two. Runs of rows
    are joined again after the moves (`space_dlis`).
  - Row 145 (the sixth DLI, the status bar's colours) was a 1-line zone,
    so zone 142-145 came out as 3 + 1.
  A character's line is read at `CHBASE` + the zone's OFFSET, so a cut zone
  shows the wrong lines. `FlZoneDli` now gives a floor zone that ends on a
  run's flagged row that row and the DLI flag; the DLI still comes at the
  end of row 145. Found with `probes/p7800-linepix.lua`, which builds each
  line's pixels from memory the way MARIA reads them (DLL, headers, direct
  and indirect objects) for a diff between builds.
- **Level 2's grey floor on one buffer.** The game draws the scene into one
  buffer and copies it (`$ADC7`/`$AE05`, `CopyBuf`). The maps are now copied
  too (`FlCpyBuf`: the source's codes counted up first, then the target's
  old ones released, so a code both hold is never freed in between).
  `ClearBuf` puts the buffer's maps back to the zero tile (`FlClrBuf`).
  Both skip while the story or title owns pages `$58-$60`.
- **Level 1's gate post cut short.** The column routine copies each piece
  2 rows below the last with `RowNext`; past row 117 there are no bitmap
  rows. A piece that would reach the floor now goes through the blitter
  (`ColNext` → `ColPlain1`), and the blitter's floor path draws it.

**Result:** the floor matches the old build at all 32 compared flips. The
only differences are 2-16 pixels a picture at rows 108-117: the fighters'
upper and lower-body palettes meeting on the new cell grid (the third column
is cut 8, 8, 2 now). The colours are the same family (white and grey). Open:
which one the original shows there.

**The speed.** The first working build ran 19-45% slower than the old one.
Changes, in order, with flips reached in 12,000 frames (old build: L1 1947,
L2 1513, L3 1214, L4 1792):

| change | L1 | L2 | L3 | L4 |
|---|---|---|---|---|
| first working | 1581 | 1259 | 820 | 990 |
| rows a cell at a time, not a byte (`FlGet`/`FlPut` ~130 cycles a byte each way) | 1713 | 1359 | 908 | 1151 |
| row code in the fixed bank (no bank switch per row) | 1716 | 1363 | 922 | 1151 |
| out and in merged into one step | 1735 | 1374 | 945 | 1258 |
| blit columns exactly `$1E` to `$1E+$0E` (the margin byte each side never written: `probes/tmp-scrcols.lua`) | 1750 | 1377 | 984 | 1258 |
| state kept for the whole blit: `ZP_P1` (the game's `$00/$01`, which the blitters never touch) the line's page, a row map `FL_RM` of codes + byte parity, rebuilt only at a zone change; ~23 cycles a byte | 1776 | 1398 | 1020 | 1391 |
| bitmap rows of a floor blit counted down (`FL_NB`), not tracked | 1774 | 1400 | 1039 | 1391 |
| fills: a cell already holding the fill's values is its own result (`FlSame`), a byte already right is skipped (`FlPut`) | 1781 | 1402 | 1040 | 1391 |

- **Dead end: entering the floor at `RowWrap`.** The third column has
  pages for 18 rows but only 16 bitmap rows (102-117). The step from row
  117 doesn't wrap, so the floor can't be caught there.
- **Whole frames.** Every flip in level 4 takes exactly 6 frames in the old
  build and exactly 8 in the new one (`probes/p7800-fliptimes.lua`), so the
  pace moves in steps of 2 frames. The new build's floor work is about 19%
  of level 4's cycles (about 1.5 frames a flip). Even at no cost it would
  only just get back under 6.
- **What level 4 does every flip:** a black rectangle over each door frame
  (columns 0-3 and 37-40, rows 60-137), the frame posts blitted again in
  front (`$96D0`, 77 rows), the frames' feet (`$964C`, `$9745`), and two
  pattern refills of the floor (`$EB38`). Together they change nothing on
  screen. On tiles each post cell goes to the zero tile and back
  (allocate, copy, write) every flip. In the bitmap the same redraws are
  about 40% of the old build's time (the blitters).

**Fitting the code:**
- The scene pages ran out of runs free in all of them, so each page now
  gets its own copy of the floor code. It sits in that page's own free
  runs (`place_parts` per bank); each page's jump table is assembled
  against its copy. `work/karateka7800.apsym` lists every page's
  addresses; the symbol file has bank 0's.
- In the fixed bank: the row code as gap pieces (`FlRow`, `FlZoneSet`,
  `FlInL`, `FlOutL`, `FlOwnF`, `FlBuf`); 281 bytes free.
- The buffer clear and copy moved to the scene pages behind a 30-byte
  stub.
- A build that fails to place a fixed-bank piece now lists the fixed bank's
  free runs.

### The floor as tiles: scene 0 runs out of characters; what RAM it gives (2026-10-09)
`checkdl.sh`: scenes 1-4 and 6 clean, scene 0 has 32 pictures over 300
pixels (it was clean before the floor):
- **Pictures 220-248, the princess's room in the attract:** her legs and
  stripes are missing on rows 118-126, and fills leave old bytes. Tile byte
  dumps before each draw (`probes/tmp-floorbytes.lua`) show the room's
  black rectangle and stripe refill missing cells. The cause: all 98
  character codes in use, none free, for about 59 flips around the room
  (`probes/tmp-flfree.lua`). With no code to copy into, a fill or blit
  can't make a shared cell its own and drops that cell. The room's floor
  (`B702` 23 bytes wide, `B7CA`, `B9C0`, the princess, both buffers) needs
  more distinct cells than the set holds.
- **Pictures 316 and 640-641, the attract fight:** the poses differ at the
  same flip. Not looked into yet. The attract may depend on frame timing,
  which the slower build changes.
- **Ruled out:** the story's text and the floor's pages. FlDraw skipped the
  floor while any buffer was marked blank (`S_OBLANK`), but the first clear
  after the text already makes the floor new. A flag outside the text's
  pages (`S_FLLIVE`, `$1F7F`: the ledger's one console byte, now used) now
  says the floor's pages are the floor's: set by FloorInit, cleared by
  ObjBlank. It is right, but it didn't change the pictures.

**What RAM the tiles give back:** the character set (codes 16-210, two bytes
by 8 lines: 1,568 bytes), the eight maps (160), the use counts (196), the
scratch row, memo, variables and row map fill pages `$58-$60`. Those are
the 9 pages the bitmap gave up (`FB_ROWS` 146 → 118). What is left unused
in them is about 190 bytes (each page's first 16 bytes, page `$60`'s
tail). As built, the tile floor gives back almost no RAM. The 2,160 bytes
of stage 1 would need a much smaller character set, and the princess's
room already uses all 98 characters.

Work in progress kept as `Karateka-Port-checkpoints/2026-10-09_enh-floor-tiles-wip`
(not a KEEP: not a known-good build). The last good build before the floor
is `2026-10-09_KEEP_enh-coverage`.

### Midnight Mutants: how it draws and scrolls its background (2026-10-09)
The user suggested looking at it. Measured in MAME (`probes/mm-dldump.lua`:
fire to start, then walking; DLL and headers dumped at frames 1600, 1610,
1700 and 2400; register and bank writes logged per frame). The user's own
disassembly (`Documents/Atari 7800/disasm`) already describes the map.
- **The playfield is character mode, all of it.** Ten 16-line zones. Each
  one's first object is one indirect 5-byte header (`[lo 60 hi 2B/0B
  hpos]`) reading 21 two-byte characters (168 pixels: one more than the
  screen, for fine scroll). They come from that zone's own 100-byte row of
  the map in RAM (`$2400`, `$2464`, ...). The map is also the terrain grid.
- **The scroll is in the headers alone.**
  - Fine: hpos `00` → `FC` → `F9` (0 to −7 pixels).
  - Coarse: each header's low byte up by one character (+8 between frames
    1610 and 1700).
  A step costs two bytes in each of ten headers. The map isn't rewritten
  while a room scrolls.
- **The characters are ROM, in the banked window.** `CHARBASE` `$80`, 16
  line pages. The game writes the bank register at its DLIs (4 times a
  frame: bank 0 for the status rows' text, bank 1 for the playfield). Its
  code runs from `$4000-$7FFF` (ROM bank 6 there) and the fixed bank, so
  the window holds only what MARIA reads. The disassembly's `$4150` waits
  for a DLI tick before switching, so a switch never lands mid-zone.
- **Sprites:** direct objects reading the fixed bank (`$C4xx`, `$B4xx`), in
  zones with holey DMA (`H16`).
- RAM for the whole playfield: the map (1,000 bytes for a 100 × 10 room)
  and the lists. No RAM for any pixel.

**What carries over to Karateka:**
- Characters in ROM need a bank MARIA can see while it draws the floor
  lines. Here the window holds game code: the scene page 42-52% of the
  time, bank 5 39-48%, the art bank 7-10% ("Which bank is in the window
  during play"), switched hundreds of times a frame. So the window would
  need the same character set at the same address in every bank. In the
  current build no 8-page group has even one two-byte column free in all
  of banks 0-4: the scene pages hold the game's scene data nearly
  wall to wall. Otherwise the fixed bank: 281 bytes free, in pieces.
- The RAM-character version (what was built) keeps the pixels in RAM, so
  it gives back nothing.
- The scroll by headers needs the scenery as a wide map of ready
  characters. Karateka's scenery is images blitted at any column, shift
  and row, so its rooms would have to be rendered into characters at
  build time ("precomputed per scene"), with the dynamic parts (the
  princess, the door frames scrolling in, level 1's posts) as objects.

### More ROM for MARIA: the cartridge options (2026-10-09)
The user asked whether the cart's 16K of RAM could be swapped for more
fixed ROM.
- **ROM at `$4000` instead of RAM** (the SuperGame layout Midnight Mutants
  uses: bank 6 at `$4000`): gives 16K more ROM always mapped, but takes the
  RAM away. Today the RAM holds the bitmap (6.9K), the top pieces (3.8K),
  the display lists (2.3K), the fighters' slices (2K), and the blitter (1K,
  self-modifying). The console's 4K is full. Not possible until nearly all
  of that is gone.
- **BankSet** keeps the RAM and adds a second ROM half that only MARIA
  reads. The user's core supports it (`openFPGA-7800`
  `src/fpga/mister/rtl/cart.sv`):
  - header bit 13; the file is two halves, the CPU's first;
  - after `/HALT`, MARIA's reads come from the second half, counted out
    two cycles as SALLY releases the bus;
  - SuperGame: MARIA's window shows the second half's bank with the same
    number the CPU has selected (`bs_map` = the half's bank count);
  - RAM at `$4000` (`ram_cs`) is shared by both sides.
  So a 2 × 128K BankSet leaves the CPU side exactly as today. MARIA gets
  128K of its own: the same 16K copied into all seven window banks (the
  CPU's window churn doesn't matter then) plus its own `$C000` bank. That
  is 32K of graphics ROM it can always read. Any graphics MARIA reads from
  the fixed bank today must be copied to the same addresses on its side.
- **Emulation:** a7800 v5.2 supports BankSet (the toolkit's
  `docs/cartridges.md`, `docs/emulation.md`). MAME 0.287, which every probe
  runs on, does not. a7800's Lua has no `install_write_tap`/
  `install_read_tap` (checked: nil on the address space), only the older
  debugger watchpoints.
- **The BankSet spec's RAM rules** (7800.8bitdev.org, "Bankset
  Bankswitching"; bit 13 BankSet, bit 14 BankSet RAM):
  - Each side has its own 16K at `$4000`. The CPU writes MARIA's through
    `$C000-$FFFF`, and can't read it back.
  - No code may run from the CPU's cart RAM.
  - Display lists must be in console RAM.
  The test carts with RAM are type `$6002` (bits 13, 14, SuperGame).
  a7800 implements only that (16K a side). The port breaks all three rules:
  - the blitter runs from cart RAM (`$7C00-$7FFF`, self-modifying);
  - the zone lists are in cart RAM (`$4F-$57` and page heads);
  - MARIA reads what the CPU draws: the bitmap, read and written by the
    blitter, and the slices.
- **Shared RAM:** the user's core also accepts BankSet with the ordinary
  RAM-at-`$4000` flag (bit 2, not bit 14). It then addresses RAM with no
  side bit, so both sides share one 16K, which is the port's model today.
  It isn't in the spec, so a7800 won't do it, and Concerto+ is unknown.
  (The user says Concerto+ supports BankSet.)
- **The test cart** (`port/bankset_test.py` → `work/bankset-test-shared.a78`,
  type `$2006`, and `work/bankset-test-spec.a78`, type `$6002`; code in
  the CPU half's fixed bank, lists in console RAM). Five bars:
  1. console RAM (the control);
  2. `$E000`, MARIA's fixed bank (stripes = the CPU's half);
  3. `$8000` with the CPU on bank 3 (a bar of bank + 1 bytes);
  4. red: cart RAM the CPU wrote at `$4000` (shared);
  5. green: RAM written through `$C800` (MARIA's own).
  In a7800 v5.2 the spec cart shows 1, 2, 3 (a 4-byte bar: MARIA reads its
  own bank 3) and 5, as designed. The shared cart shows garbage stripes
  there: a7800 doesn't do that combination. Real hardware (the Pocket core,
  Concerto+) is with the user.
- **The user:** cart RAM can't hold code or display lists either way. With
  that much ROM for MARIA, the game shouldn't need the blitter at all: every
  blit becomes an object reading its image from ROM.

### Console RAM: what must stay (2026-10-09)
The user: is anything in the 4K that doesn't need to be there? Under
BankSet's rules, console RAM must hold the display lists, any code run from
RAM, and zero page and the stack. Graphics MARIA reads can go in its own
cart RAM; data only the CPU uses can go in the CPU's cart RAM.

**Measured** (`probes/p7800-ramclass.lua`, merged by `probes/ramclass.py`;
on `2026-10-09_KEEP_enh-coverage`; the attract loop to frame 14,000 and
scenes 1, 2, 3, 4 and 6 scripted to 12,000). Each frame the DLL in use is
walked as MARIA reads it. Bytes executed after the boot are code (the
BIOS's signature check runs from `$2300-$27FF` first: a dead end until the
probe ignored the boot). Every write after the boot's clear counts.

| class | bytes | where |
|---|---|---|
| CPU-only data | 1,760 | `$1800-$1EFF`, the top's row buffer `$1F18`, the fast fill's patch bytes |
| lists MARIA reads | 705 | `DLL_A`/`DLL_B` (183 used of 256 each), the status lists `$1F80-$203F`, `$2780` small lists, `DLS_A`/`DLS_B` (30 used each) |
| graphics MARIA reads | 20 | `TOPSKYROW` |
| code | 158 fetched (about 400 with operands) | the fast fill `$2600-$2773` (self-modifying) |
| zero page, stack | 384 | `$2040-$20FF`, `$2140-$21FF` (the hardware's) |
| never written | 1,069 | list tails (`$2400`, `$2500` 226 each; the DLLs 73 each), `$2100-$213F`, `$1F00-$1F17`, `$27CD-$27FF`, scattered |

The CPU-only data:
- the game's zero-page movers (`$1800`);
- the zero-page swap buffer (`$1880`);
- the scene variables' carves (`$1900-$1A09`);
- the DL descriptions (`DESCBUF`);
- the common carves (`$1A80`);
- Akuma's tables (`$1AA1`);
- the fighters' tables (`$1B80-$1DF5`);
- the system variables (`$1E00`).

The build places all of them, so they could be relocated.
"Never written" covers these runs only: the ending and a game over weren't
run.

**For a blitter-free BankSet design:**
- Free for lists: the 4K less zero page and the stack is 3,712 bytes, if
  the CPU-only data (1.76K) moves to cart RAM.
- The fast fill goes with the bitmap.
- The lists now in cart RAM must come in: the top zones' slots (1,200),
  the band lists (768), the top pieces' lists (256), the page-head lists
  (about 450). With today's console lists, about 3.3K in all. Tight.
- Objects in place of the bitmap make lists longer. Characters for the
  big backgrounds (one indirect object a zone, as Midnight Mutants) keep
  them short.

### A 144K cart: the fit (2026-10-09)
The user's proposal: no cart RAM. SuperGame with an extra ROM bank at
`$4000` (type `$000A`, 144K: Crossbow, Alien Brigade), a standard layout
MAME runs. Display lists and other must-be-RAM data go to console RAM,
shared graphics and code into the new 16K, and level code and graphics
stay in each scene page.
- **MAME runs it** (`port/sg144_test.py` → `work/sg144-test.a78`). MARIA
  reads the `$4000` ROM, and CPU bank n puts file bank n + 1 in the window
  (`$4000` is file bank 0, `$C000` file bank 8).
- **Console RAM:** 4,096 less zero page and the stack (384) and the
  CPU-only data (1,760, which has nowhere else to go now) leaves 1,952.
  - What the display uses in play (`probes/p7800-listsize.lua`, text
    screens excluded): at most 575 list bytes a picture and a 61-entry
    DLL (183), so about 1.5K for two buffers. That leaves about 450 for
    the new engine's own state. It fits, tightly.
  - Scenery as objects adds entries; backgrounds as characters (one
    indirect header a zone) and 16-line zones cut them.
- **The window:** level graphics in a scene page reach MARIA only while
  that page is in the window. During play (`probes/p7800-wincode.lua`,
  scenes 1-4), bank 5 makes 81-91% of the window's instruction fetches,
  running 6.5-8.2K of code (the top-bank system code: the DL builder, the
  top rows' and fighters' emitters, ...). The scene page makes the rest,
  1.6-5.2K. The art bank runs no code; the blitters read images from it.
  So either:
  - bank 5's play code moves to `$4000` or the fixed bank, competing with
    the shared graphics (the art bank's 8K of art and 4.2K of fighters'
    parts today);
  - or every graphic MARIA reads lives in `$4000` and the fixed bank,
    every level's included.
- **No bitmap is possible at all:** with no cart RAM there's nowhere to put
  one. Every blit has to be a ROM object or characters before the 144K
  cart can run.
- **A path that stays testable:** on today's layout, treat cart RAM as the
  future ROM. Load what will be ROM into it at load time, and empty the
  rest step by step: the bitmap, the slices, the lists and the blitter.
  `probes/p7800-ramclass.lua` can prove no run writes there after loading.
  Then switch the header to 144K. The one thing loading hides: per-scene
  data can be reloaded into RAM but not into ROM, so the window question
  above must be settled before that switch.

### Back to the bitmap floor (2026-10-09)
The user: start from the last checkpoint. `port/` is restored from
`2026-10-09_KEEP_enh-coverage` (build7800, fighters7800, layout7800,
link7800, sys7800.asm). The cart and the invincible-easy kit rebuild byte
for byte as the checkpoint's. Kept: FINDINGS, the probes, and the test
carts' scripts (`port/bankset_test.py`, `port/sg144_test.py`). The tile
floor is in `Karateka-Port-checkpoints/2026-10-09_enh-floor-tiles-wip`.
Worth carrying over later:
- `space_dlis` joining the runs a moved DLI cut;
- `place_parts` per scene page;
- the fixed bank's free-run report;
- `S_FLLIVE`'s lesson: the floor's pages are reinitialised at the first
  clear after the text, not when both buffers are clear.

### A 144K cart: the scenery's graphics (2026-10-09)
**How:** `probes/p7800-blitcensus.lua`, summed by `probes/blitcensus.py`.
At BlitBank, each blit's kind (from its caller's return) and `FT_IN`. At
its end, `BlitBankKeep` (or `BlitBankX` for Akuma's and the hawk's
captured blits), the bank in and the image's header (rows, bytes a row).
- **Runs:** the attract loop 24,000 frames; scenes 1-3 30,000 and 4 and 6
  20,000, scripted; the user's level 3 recording through the finale,
  replayed by `p7800-stateplay.lua`.
- **Not covered:** the story and title (objects already); the ending and
  a game over.
- **A dead end:** the fighters' blits leave BlitBank before their bank is
  chosen, so a header read there is another bank's; they are left out.

**Every image the game blits** (raw bytes, rows × bytes a row; "both"
adds a mirrored copy for images drawn both ways):

| bank | images | bytes | + both ways | total |
|---|---|---|---|---|
| scene page 0 (attract, cutscenes) | 41 | 1,647 | 24 | 1,671 |
| scene page 1 (level 1, vs fight) | 56 | 2,452 | 515 | 2,967 |
| scene page 2 (level 2) | 20 | 2,744 | 274 | 3,018 |
| scene page 3 (level 3, the hawk's 23) | 18 | 2,501 | 430 | 2,931 |
| scene page 4 (the finale, Akuma's 60) | 63 | 3,510 | 687 | 4,197 |
| the art bank (shared) | 59 | 4,367 | 1,228 | 5,595 |

About 20K in all, before any layout waste. **The fighters** (build and
"The fighters as objects"): the lower bodies 3,861, black and merged 367,
the torsos with the player's head 2,038. About 6.3K a direction, 12.5K if
the enemy's mirror is stored rather than made in RAM at copy time.

**For 144K:**
- MARIA can always read 32K: `$4000` and `$C000`, less the fixed bank's
  code.
- The shared graphics alone are about 18K: the fighters both ways 12.5K
  plus the art bank's 5.6K.
- Every level's scenery (about 14.8K) doesn't fit there as well. It has to
  stay in its scene page, so the window has to hold the scene page while
  MARIA draws. That means bank 5's 6.5-8.2K of play code moving out, which
  has no room either.
- On these numbers 144K is too small. MARIA's always-visible ROM is the
  limit, not the RAM. A bigger cart only adds window banks.

### What a scene page holds (2026-10-09)
From the build's map, with the window code log (`p7800-wincode.lua`,
scenes 1-4 in play) and the blit census by address range. Each of banks 0-4
holds:
- `sdata`: the scene's XE `$6000-$7FFF` at `$A000`, 8,192 bytes;
- `scode`: XE `$1203-$22FF` at `$8203`, 4,349;
- `common`: the game's common code (XE `$06E8-$0FFF`, the same in every
  page) at `$96E8`, 2,328;
- the port's 0.6-1.1K: the jump table and its code, zero-page tables, list
  descriptions, loader tables, the page map;
- released 1.6-2.3K (the copied sprites' originals, padding); free 1.7-2.5K.

| page | code run in play (sdata / common / scode) | images drawn (all in sdata) |
|---|---|---|
| 0 (attract, cutscenes) | not measured | 1,729 |
| 1 (level 1, vs fight) | 3,339 / 725 / 768 | 2,564 |
| 2 (level 2) | 2,918 / 729 / 0 | 2,784 |
| 3 (level 3) | 1,802 / 713 / 0 | 2,537 |
| 4 (the finale) | 723 / 677 / 0 | 3,636 |

(Code counted as each fetched opcode and two bytes after it; images as rows
× bytes + their 2-byte header.)
- `scode` is mostly the sprite originals, now released. Only level 1 runs
  code there in play.
- Of `sdata`'s 8K, the images are 1.7-3.6K and the code run in play
  0.7-3.3K. The rest is tables (level layouts, the AI's, text) and code
  these runs didn't reach (the cutscenes, other paths).

### Converting the scene images in place: alignments and bank 5's code (2026-10-09)
The user asked whether the images already in the scene pages could simply
be converted. That would be a re-layout (each row on its own page, as MARIA
reads), plus copies pre-cut for the rows each is drawn at. Two
measurements:

**Row alignments** (`p7800-blitcensus.lua` now records each image's rows;
`probes/rowphase.py`; the same seven runs): 257 scenery images are drawn
at 321 alignments on an 8-line grid. Almost every one sits at one row.
- **What moves:** level 1's column pieces (`$A684` at 50 rows, `$A68A`,
  `$A703`, `$A85F`), which the column routine stacks into posts and would
  become one tall image each; and the hawk (scene page 3).
- **A pre-cut copy** fills whole zones: ceil((alignment + rows) / Z) zones
  of Z lines, each the image's width, twice for an image drawn both ways.

| bank | raw | 8-line zones | 16-line zones |
|---|---|---|---|
| page 0 | 1,671 | 3,304 | 5,920 |
| page 1 | 2,967 | 5,784 | 9,824 |
| page 2 | 3,018 | 4,984 | 6,144 |
| page 3 | 2,931 | 8,096 | 10,864 |
| page 4 | 4,197 | 6,144 | 8,784 |
| art bank | 5,595 | 7,440 | 8,944 |
| all | 20,379 | 35,752 | 50,480 |

The padding is the zones' unused lines. Holey DMA (blank reads from the
half of each 4K or 2K block that is a hole) could give most of it back,
at a cost in layout.

**Bank 5's code run in play** (`probes/b5code.py` over the
`p7800-wincode.lua` logs, scenes 1-4), 8,625 bytes in all, by `FARART`
section:

| section | bytes run | share of bank 5's fetches | a ROM-object design |
|---|---|---|---|
| FtEmit | 3,229 | 40.8% | its list building stays, smaller; the copying of slices into RAM goes |
| TopHelp | 280 | 22.1% | the top rows' capture: goes |
| TopEmit | 372 | 10.7% | the top pieces' lists: replaced |
| FgRecB | 810 | 10.2% | the front boxes (bitmap bytes in front of the fighters): go; order in the lists does it |
| TopCapture | 537 | 7.4% | goes |
| TiaSound | 175 | 3.5% | stays (run from the NMI, so it must be out of the window if the window is pinned) |
| TopColours | 84 | 2.4% | stays, small |
| TopErase, TopRefresh, TopLoad, TopClearCopy | 1,258 | 2.3% | capture bookkeeping: goes |
| ClearCopy | 610 | 0.4% | the buffers' clear and copy: goes |
| Builder | 1,198 | 0.1% | the DLL builder: stays, rarely run |
| TitleMark, ObjBlank | 72 | 0.1% | the text screens: can stay in bank 5 |

About 3.6K of it is capture and bitmap bookkeeping that ROM objects don't
need. What would stay in play: list building for the fighters and the
scenery, the DLL builder, sound and colours. Perhaps 2-3K rewritten (an
estimate, not measured).

### The enemy's mirrored poses (2026-10-09)
The user: the bow isn't used by the enemy in play, only in a cutscene
facing right; vs mode could drop it for both players, though it probably
frees little.
- **How:** `probes/p7800-poses.lua` records each fighter's lower pose
  `$20`, upper pose `$21`, `$3E`, `$36` and side at FRecP; summed by
  `probes/poses.py`.
- **Runs:** the attract loop, scenes 1-4 and 6 invincible, scenes 1-3 on
  the normal cart, and the user's level 3 recording.
- **The mirror rule:** a lower blob is mirrored when (enemy XOR pose
  28-32, `$A2BE`); torsos are mirrored for the enemy.

| part | plain | mirrored | needed both ways |
|---|---|---|---|
| lower bodies (fighters7800 blobs) | 40, 3,795 bytes | 37, 3,547 bytes | 37, 3,547 bytes |
| torsos (`$A226`/`$A24C`) | 36, 1,825 bytes | 32, 1,689 bytes | 31, 1,619 bytes |

- **Plain only:** lower poses 11, 12 and 13 (the player's alone, 248
  bytes); upper 29, 11, 12 and 13 (the player's); upper 28, 69 bytes,
  only in the attract loop on the first fighter's side, which fits the
  user's bow.
- **Mirrored only:** upper 24 (the enemy's).

So the enemy needs nearly every part mirrored. The fighters in ROM both
ways come to about 11K (lower 7.3K, torsos 3.5K, plus heads and black
layers). Dropping the bow saves under 150 bytes.

### The inventory (2026-10-09)
The user: dump out all the pieces, see what each scene needs and how they
fit, rather than poking at the edges; and could scene 1 be split between
its two stretches (the user's level 1, the cliffs and the first gate; level
2, the mirrored gate, the torii, and logic that follows the enemy running)?

**How:** `probes/p7800-inventory.lua`, merged by `probes/inventory.py`
(report: `work/analysis/inventory-report.txt`).
- **What it records:** every ROM read from the BIOS's hand-over, by bank
  (the window's by `S_BANK`), classed opcode, operand or data. Data inside
  an image the blit census saw counts as image; the rest is tables.
- **The labels:**
  - the game's scene (`$D0`);
  - scene 1 split by `$4C` (which structure it draws: `s1g0`, `s1g1`);
  - `s1cut`/`s2cut`: a flip drawing the art bank's door frames or
    cutscene figures;
  - `text`: the story and title.
- **Runs:** the attract loop 40,000 frames; scenes 1-3 30,000 and 4 and 6
  20,000 invincible; scenes 1-3 30,000 on the normal cart; the user's
  level 3 recording to the ending.

**Read in all runs** (bytes; "one" = by a single label):

| bank | region | code (one) | tables (one) | images (one) |
|---|---|---|---|---|
| page 0 | sdata / scode / common / port / low | 2,710 / 360 / 778 / 229 / 40 | 2,092 / 820 / 293 / 287 / 292 | 1,729 |
| page 1 | same | 3,533 / 945 / 953 / 267 / 139 | 732 / 369 / 164 / 261 / 227 | 2,564 |
| page 2 | same | 3,000 / 0 / 839 / 260 / 0 | 580 / 147 / 151 / 260 / 244 | 2,766 |
| page 3 | same | 2,460 / 0 / 885 / 286 / 0 | 355 / 215 / 162 / 261 / 249 | 2,537 |
| page 4 | same | 1,672 / 363 / 777 / 277 / 76 | 687 / 771 / 127 / 257 / 221 | 3,636 |
| bank 5 | | 10,478 | 4,116 | |
| art bank | | | 6,110 | 4,475 |
| fixed | | 11,343 | 2,141 | |

- **A scene page reads 7.4-10.1K of its 16K.** The rest is code and data
  no run reached, the released ranges and the free space.
- **Shared parts:** the common code (2.3K, the same in every page) is
  read 0.8-1.0K a page. Bank 5 and the fixed bank are shared by all.

**Each stretch's own bytes** (used by no other label):
- **s0** (attract): page 0's code 2,803, tables 856, images 831; the art
  bank's images 1,282; the fixed bank's code 1,129.
- **s2:** page 2's code 3,420, tables 824, images 1,814.
- **s3:** page 3's code 3,366, tables 878, images 2,537.
- **s4:** page 4's code 2,705, tables 1,647, images 3,636; the art bank's
  images 606.
- **s6** (the vs fight): nothing of its own. It uses level 1's page
  entirely.

**Scene 1's page by stretch:**

| used by | code | tables | images |
|---|---|---|---|
| s1g0 only (the first gate, the cliffs) | 2,581 | 1,214 | 2,078 |
| s1g1 only (the torii) | 390 | 77 | 294 |
| both | 2,288 (+ 532 also in the cutscene) | 270 | 192 |
| the cutscene only | 27 | | |

The torii's own share is small: about 760 bytes (its enemy-following
logic among them). Most of level 1's page is either the first stretch's
alone or shared. Splitting it would copy about 3K into both halves, to
move out the torii's 0.8K. The `s1g1` label covers few flips in these
runs, so its share may be undercounted.

### The space below $4000 (2026-10-09)
The user asked about the high score cart's ROM space as more room (the
BankSet page mentions it).
- **In 7800 mode the console answers only:** `$1800-$27FF` (zero page and
  the stack are mirrors inside it), the TIA, MARIA and RIOT registers in
  `$0000-$03FF`, and the RIOT's RAM. Everything else is the cartridge's
  (`openFPGA-7800` `Maria/control.sv`; `top.sv`: `cs_cart` is everything
  else).
- **The high score cart** is 4K of ROM at `$3000-$3FFF` and 2K of RAM at
  `$1000-$17FF` (`cart.sv`: `hsc_rom_cs`, `hsc_ram_cs`), not 8K.
- **Formats using `$3000`:** only the flat 52K (`$3000-$FFFF`, no
  banking) and BankSet's 2×52K. The BankSet page: "extended format covers
  $3000-$FFFF, so the added space comes at the expense of being
  incompatible with the High-Score Cart". No listed format pairs it with
  SuperGame banking, cart RAM or the 144K layout. Neither MAME nor the
  core maps a SuperGame cart there.
- **What it would give:** 4K more that MARIA can always read. A 144K +
  `$3000` cart would be a custom mapper: easy in the user's core
  (`hardware_map[3]`), but MAME and Concerto+ would need it too.
  Karateka saves no high scores, so the conflict with the high score cart
  costs nothing.

### MAME with BankSet (2026-10-09)
The user chose adding BankSet to MAME 0.287 over moving a7800 onto a new
MAME: a7800 is a fork of an older MAME (pre-0.2xx macro style, no Lua
memory taps) with many changes; the port is one cart file's worth.
- **Toolchain:** MSYS2 at `C:\msys64` (UCRT64: gcc 16.2, Python 3.14). The
  source is `C:\Users\thuco\Documents\mame-src`, tag `mame0287`, branch
  `bankset` (uncommitted). Build: `make PTR64=1 MINGW64=/ucrt64
  SUBTARGET=a78 SOURCES=src/mame/atari/a7800.cpp NOWERROR=1
  ARCHOPTS=-Wno-sfinae-incomplete IGNORE_GIT=1 -j17` → `a78.exe`. The
  probes use it through `MAME=` (`port/run7800.sh`).
- **Dead ends on the way:**
  - winget's MSYS2 install failed (0x80070001); used the release's sfx,
    with its published sha256.
  - Without `PTR64`/`MINGW64` the makefile picks the 32-bit target.
  - A path with a space ("Atari 7800") breaks makedep's Python call.
  - GCC 16's `-Wsfinae-incomplete` stops `emu.h`'s precompile under
    `-Werror`. `NOWERROR` needs `REGENIE=1` to take.
  - A shell left inside the tree blocks moving it.
- **The baseline** (stock 0.287, 7800 only) gives byte-identical results
  to the installed MAME (`p7800-linepix.lua`, scene 2, flip 300; the
  frame-4,000 state).
- **The patch** (`port/mame/bankset.patch`, made by
  `port/mame/mame_bankset.py`):
  - **The flag:** `set_maria_dma` on the cart interface and the slot.
    The driver sets it around `maria_startdma`, where MAME's MARIA does
    all its reads.
  - **Three cart types** in `rom.cpp`:
    - `a78_bs_sg` (`$2002`): each half's second-last bank at `$4000`;
    - `a78_bs_sgr` (`$6002`, the spec): 16K of RAM each side, MARIA's
      written at `$C000-$FFFF`;
    - `a78_bs_sgs` (`$2006`): one shared 16K of RAM, as the user's core.
  - **Header detection:** bits 13 and 14 kept through `validate_header`,
    which otherwise strips everything above `$0300`.
- **Two bugs on the way:**
  - I first numbered the types after VersaBoard. The VersaBoard RAM
    check (`A78_VERSABOARD` to `A78_VERSA_POK450`) caught them, so the RAM
    was allocated twice and MAME stopped on "duplicate save state". They
    are `$40-$42` now.
  - `validate_header` refused both carts as unsupported mappers.
- **Checked:**
  - Our test carts: the spec one shows bars 1, 2, 3, 5 (as a7800); the
    shared one 1, 2, 3, 4.
  - a7800's own "Bankset Test 2x128K" and "2x128K RAM" ROMs show the same
    screens in both emulators.
  - The current Karateka cart runs byte-identical to the stock MAME.
  - Not done: POKEY@800 BankSet (`$E002`, refused: Karateka has no
    POKEY); the flat 2×32K/48K/52K formats.

### BankSet step 1: the graphics MARIA reads, and the cart format (2026-10-09)
The user:
- the blitter and the graphics it puts into RAM needn't go at once:
  MARIA's RAM is write-only from the CPU, so nothing on the CPU side may
  read it;
- the first step is to put the graphics that aren't the blitter's into
  MARIA's ROM;
- anything converted into RAM goes into MARIA's ROM too, unless space is
  needed.

**What MARIA reads today** (`probes/p7800-mariagfx.lua`; each frame's lists
walked as MARIA reads them; the attract loop and scenes 1-4 and 6). In
play it reads no ROM at all:

| what | where | bytes | made by |
|---|---|---|---|
| the bitmap | cart RAM `$58-$72` | 6,480 | the blitter |
| the top rows' pieces | cart RAM `$40-$4E` | 2,816 | TopLoad at scene load, from the scene's images (mirrored, level 1's sky converted) |
| the fighters' slices | cart RAM `$73-$7A` | 1,944 | FtEmit every flip, from the parts (heads put on, the enemy mirrored) |
| the sky row | console RAM `TOPSKYROW` | 20 | converted |

On the text screens, also the story's letters and the title's canvases
(cart RAM `$4F-$57`, console RAM: 1.1K, from the glyph block).

**To MARIA's ROM** (all but the bitmap): the top pieces per scene, the
fighters' parts both ways, the sky row, the glyphs.
- **What MARIA sees of its half:** its fixed bank `$C000-$FFFF`, 16K, and
  its window, which shows its copy of whatever bank number the CPU has in.
  The CPU switches banks all through the frame, so window data must be the
  same in all seven of MARIA's window banks: 16K more.
- **The fit:** about 20K wanted (top pieces about 8.6K for all scenes,
  fighters about 11K, glyphs 0.6K) of the 32K.

**The CPU-read probe** (`probes/p7800-cpureads.lua`): its first run
counted indexed stores, whose dummy read of the target looks like a read.
Stores are now left out. Not yet rerun: the blitter's question is for
later.

**The format (done):**
- `python port/build7800.py --bankset` writes a 2 × 128K BankSet image:
  the CPU's half as ever, signed alone, then MARIA's, for now a copy.
- Header `$2006`: BankSet with one RAM at `$4000` both sides share, so
  today's lists and code in cart RAM keep working through the transition.
  The spec's `$6002` comes once cart RAM holds no code or lists.
- `port/kitopt.py` signs only the CPU half of a BankSet image.
- **Checked:** the BankSet invincible-easy cart on the patched MAME gives
  byte-identical pictures to the normal cart on the stock MAME, scenes
  1-4, flip 300 (`p7800-linepix.lua`).
- **Open:** whether Concerto+ accepts `$2006` (shared RAM is not in the
  spec). The test cart `work/bankset-test-shared.a78` answers it.

### The fighters' heads in MARIA's ROM: 160B (2026-10-09)
The user asked whether one generic enemy head (the helmets of 2026-10-02)
would do, and then pointed to the reason for the head handling: the
original's heads have four colours (skin, grey, white, opaque black). A
160A object has three and transparent, so 3 + 1 doesn't translate.
Proposed: the heads in 160B.
- **Correction to "The fighters as objects: decided":** the code doesn't
  compose heads onto torsos. FtUpper copies the head and then the torso,
  each its own object through `FtPlain` (plain stores, `FtRowP`, no OR).
  Where the boxes overlap, the torso is drawn over the head. That is what
  the screen shows today.
- **160B** (the write mode bit in an object's 5-byte header): 2 pixels a
  byte, 4 bits each: two for the colour and two picking one of the four
  palettes in the object's group (0-3 or 4-7). A head is then one exact
  object, with no separate black layer.
- **Cost:** twice the bytes of 160A. All heads (the player's 3, facing
  right; 7 types × 3 mirrored) about 1.4K, against 0.7K plus the black
  layers. Fewer objects in the heads' zones.
- **The palettes:**
  - palette 1 holds the game's colours (the bitmap's and the fighters'
    colour objects, `PAL`);
  - palette 3 (`TOP_PAL2`) has opaque black as colour 1;
  - the fighters' black palette is 4 (`FT_PAL`), in the other group.
  So group 0-3 holds every colour a head needs, if palette 3's colour 1
  is black whenever a fighter is drawn: to check per scene. Otherwise a
  copy of palette 1's colours in group 4-7, beside the black palette,
  derived each frame as the black palette is.
- **Not the lower bodies:** 160B would restore their grey and drop their
  black layers, but doubles 7.3K to 14.6K, which MARIA's 32K of visible
  ROM can't hold beside the rest.

### BankSet step 1: the top pieces (2026-10-09)
The user: yes to 160B heads; look at space after the conversion for more
160B graphics later (an accent or eye colour in the heads). Step 1 starts
with the top pieces.
- **How they work today:**
  - TopLoad converts each scene's pieces at load into columns of pages
    `$40-$4E`, row r at page `TOP_PBASE - r % 15` (zone 4's slices 0, 5 or
    10 pages lower, `TOP_Z4O`). It mirrors through the mirrored blitter's
    byte table (`$2BC0`), swaps colours 0/2 (`TOP_PAL1`) or 0/1
    (`TOP_PAL2`), repeats a column's image rows to the cut, and lays a fill
    piece's row byte across.
  - TopEmit makes each object's high byte from the constant `TOP_PBASE`
    and its low byte from the piece's column `TOP_Zn`.
  - The other set (`TOP_ALT`) is loaded into the same columns when drawn.
- **The build now does the conversion** (`build7800.py`, beside the piece
  tables; written to `work/karateka7800.topdata.json` per scene and set).
- **Checked against TopLoad in the emulator** (`probes/tmp-topdump.lua`:
  pages `$40-$4E` and `S_TSET` at chosen flips): scene 0's two sets (the
  demo, flips 510-670, and the cutscenes, 390-490) and every other set,
  identical. Scenes 1-4's first sets differ only in the 16 columns of the
  five "THE END" glyph pieces. Their source is the glyph block, in RAM only
  while the text is in, so TopLoad converts whatever is there at scene
  load. The build reads the real glyphs.
- **A dead end:** scene 0 at flips 700 and 900 is the story again, whose
  text uses those pages: not a comparison.
- **Moved (done):**
  - **Packing:** the build packs the ten sets into three groups of 15
    pages in MARIA's window block (`TOP_MPAGE` `$80`; 244, 247 and 109
    columns used, widest first, sets side by side), shifts each set's
    pieces' columns, and gives each scene its sets' top page
    (`TOPSCN_PB`, `TOPSCN_PBA`).
  - **MARIA's half:** the window block in all seven of its window banks.
    The cart is now always BankSet (`$2006`).
  - **TopLoad** only sets `S_TPB` (console `$1F18`, TopLoad's old row
    buffer: the system variables are full), and TopEmit's high bytes
    come from it. The RAM clear, the conversion and TopRowRead are gone.
    The fixed bank went from 15,817 bytes used to 15,342. Cart RAM `$40-$4E`
    bytes 16-254 are no longer written in play (the story's text still
    uses them).
  - **The tools:** `port/run7800.sh` now runs the BankSet MAME build by
    default (`runxe.sh` and `run-probe.sh`, for the XEGS, keep the stock
    MAME).
- **A probe lesson:** Lua's address space is the CPU's view, so a probe
  reading ROM sees the CPU's half while MARIA reads its own.
  `p7800-linepix.lua` read garbage at the moved pieces until it took ROM
  bytes from the cart file's MARIA half (its fixed bank, or its copy of
  `S_BANK`). It now also prints each zone's object headers.
- **Checked:**
  - `p7800-linepix.lua` line for line against the old cart on the stock
    MAME: scenes 0 (the demo, flip 520), 1, 2, 3 and 4, identical;
  - `checkdl.sh`: no picture over 300 in any scene;
  - the cliff fall to the title, every 2 flips, identical.
  - **Not seen:** "THE END" (a game over after a fight), the one place the
    data changed, to the real glyphs.

### BankSet step 1: the fighters' parts (2026-10-09)
The user: go ahead with the fighters, the heads in 160B. Every part the
fighters' emit used to copy into the slice pages now comes from MARIA's
ROM; nothing is copied at the flip. Akuma's and the hawk's captured blits
(scene images, captured at run time) still go through the slice pages.

**The data** (`port/fighters7800.py`, "the parts in MARIA's ROM"):
- **Pre-cut parts,** both ways (the mirrored ones rigid mirrors of the
  box): the lower bodies (42 poses), the torsos (38 upper poses), the two
  pose masks. Their rows are fixed by the pose, so each slice is stored as
  a window of its whole cell: line g at page T - g, the lines outside the
  slice zero. A zone of the cell then reads only its slice, wherever the
  zone starts.
- **Tall images** for what moves vertically: the heads (rows by pose) and
  the hit stars. Row r at page P0 - r, with 7 zero rows above and below
  (a zone reads at most 7 lines past an image). Pre-cutting the heads per
  row would have taken about 20K; tall, about 5K.
- **The heads in 160B:** image 0 and its mask's black as one object.
  Colours in palette 1 (skin, grey, white), black as palette 3's colour 1
  (`TopColours` writes `$00` there every frame). Images 1 and 2 have no
  mask and stay 160A.
- **The enemy types' heads differ by scene** (types 1-6 are in scene data,
  `$7E00-$7FC3`): 46 distinct head images. Which types each scene uses
  comes from the pose census (`HEAD_TYPES`); a type outside its scenes
  takes the first scene's image. Scenes 5 and 6 use level 1's.
- **Packing:** greedy, into the pages and columns the top data leaves in
  MARIA's window block (copied into all 7 window banks) and into MARIA's
  fixed bank (`$C000-$FFFF`, its own now). Identical windows and images
  are stored once. **4,662 bytes of MARIA's 32K are left**, mostly pages
  `$AD-$B3` and the third top group's columns 109-255.
- **The CPU's records** (3,464 bytes, art bank): a pre-cut part is the
  box's width, the slice count, then per slice its cell and palette, offset
  from the box's left, width, address and page. A tall image is its width,
  rows, palette, address and page. Tables in bank 5: `FT_LOW*`/`FT_LOWM*`,
  `FT_TOR*`/`FT_TORM*`, `FT_HT*` (a head's record pair, the mirrored one
  next), `FT_HVAR` (24 a scene) and `FT_HV24`.
- **The build checks it:** every record read back through MARIA's view
  against its source, the tall images' gaps included.

**The engine:**
- `FtLower`, the pose mask and the torso go through `FtPart`; the head
  and the hit star through `FtTall`, one object per cell the rows cross.
  Both make objects through `FtObjV` without copying. The head-black
  layers (`FT_HBLK*`) and the per-head source banks are gone.
- **A page per object** (`FO_HB`): BandWrite's high byte is now the
  object's page for its cell's line 0 plus the zone's part (1 less its
  first line and height). Copied objects get `FT_PTOP`. `FO_HB` is in cart
  RAM, page `$4E` bytes `$B0-$FF`. Measured with a write tap over pages
  `$47-$4E` bytes 16 on: in every scene only the title's canvas clear
  (`TitleZB`, bytes 16 to about 105) and its image copy write there.
- **160B and MARIA's write mode** (MAME's `maria.cpp`): only a 5-byte
  header sets the write mode, and it stays set across objects, lines and
  zones. So:
  - a 160B object is marked by palette 0 in `FO_PW` (no 160A fighter
    object uses palette 0);
  - BandWrite gives it a 5-byte header with the write-mode bit, and the
    next object a 5-byte header without it;
  - a list whose last object is 160B ends with a 160A header for one byte
    at x 160, off the screen, so every list ends in 160A;
  - the room check counts 6 more bytes for each 160B object in the cell.
- The reuse bookkeeping's column check (`RU_COL`) is gone: the parts no
  longer have columns. Its keys stay for `FtSame`.
- **Room:** bank 5 15,287 → 15,829 bytes used; the art bank 15,771 →
  15,332; the fixed bank 15,342 → 15,370.

**A fix on the way:** the old head black layers for the enemy types were
built from scene 1's head images, which differ from scenes 2 and 3's. A
few black pixels on the enemies' heads there were wrong; the 160B heads
use each scene's own. These are the only picture changes found.

**A change of order:** the head's black used to sort with a cell's black
objects, under every coloured one. Now it is part of the head, drawn in
the fighter's order, so a second fighter's head black can cover the first
fighter's colours. That is the order bank 15 draws in (each fighter's head
mask, then its head).

**Checked:**
- `p7800-linepix.lua` now follows the write mode and decodes 160B.
  `probes/cmplinepix.sh` compares the invincible-easy cart with a
  reference build line for line (palette 3's black and palette 4's count
  the same). Against `2026-10-09_KEEP_enh-topmaria`, scenes 0-4 at flips
  300, 600 and 1000: identical but for the head-black fix (scene 3 flip
  300: 4 lines; scene 2 flips 600 and 1000: 2 and 3 lines).
- `checkdl.sh`: no picture over 300 in scenes 0, 1, 2, 3, 4 and 6.
- `freecheck.sh`: 0 writes.
- `p7800-bandroom.lua`, scenes 1-3: no refresh with anything left out.
- **Speed,** flips by frame 20,000 (scripted): level 1 3,454 → 4,202
  (the copy was most of the emit); level 3 2,016 → 2,055.
- **The user's level 3 recording** replayed by forced state on both
  builds: Akuma and the hawk draw as before. The pictures differ by pose
  between builds, because each build steps the forced state with the
  inputs at its own speed.
  - **A dead end:** keeping only flips whose state matched the recording
    in both builds (`DIFFLOG`): 2,709 of 2,725 flips have some difference,
    which leaves nothing to compare.
  - **The user asked about a head** in the old build's picture (flip
    2400: the player, upper pose 6, hit by the star, beside Akuma's kick).
    `probes/tmp-ftforce.lua` writes the old build's records for that
    picture (the player, Akuma's six blits, the star; dumped by
    `probes/tmp-akdump.lua`) into the new build's emit. The fighters, the
    star and Akuma are pixel for pixel the same, so the head there is the
    pose's own placement with the star over the face, not this change.
    (The user: different stances; it may just look odd.)

**Not yet:** the glyphs and the sky row (next), "THE END" (seen since: below), the hardware
test, and the old converters' leftovers in `fighters7800.py` (`lower_blobs`,
`black_images`: cleanup, last).

### "The end" seen from MARIA's ROM (2026-10-09)
The user: put "the end" somewhere MARIA can find it. The top-pieces step
had already put its five glyph pieces there (the build converts them from
the real glyphs), but no run had shown them. Now seen:
- **The run:** a game over in level 1 (`playkey.lua QUIET=200`: from flip
  200, left held, off the cliff), the normal cart, a picture every 2 flips
  from 200 to 420 (`SNAPDL`), on this build and on
  `2026-10-09_KEEP_enh-coverage` (before BankSet, the pieces converted
  into RAM by TopLoad).
- **All 111 pictures identical,** "the end" among them (flip 226), then the
  title and the story.
- **Where MARIA reads it** (`p7800-linepix.lua`, flip 227): the glyphs'
  rows 56-64 are six objects in the top zones, reading pages `$80-$8A` of
  MARIA's window block (the top data's first group). The glyphs' tenth row
  is row 65, the band's first, in the bitmap: the game's text routine
  draws it with the blitter from the glyph block `TextIn` copies into
  console RAM. That is the blitter's part, which stays for now (the
  user's rule).

### BankSet: the CPU off cart RAM, the inventory (2026-10-09)
The user: under BankSet the CPU isn't supposed to use cart RAM (MARIA's);
fix that first. The spec (7800.8bitdev.org "Bankset Bankswitching",
re-read): with BankSet RAM (bit 14, type `$6002`) the CPU's 16K at `$4000`
is its own; MARIA's 16K is written through `$C000-$FFFF` and is write-only
for the CPU; no code may run from the CPU's cart RAM; display lists must be
in console RAM.

**How measured:**
- `p7800-ramclass.lua` now takes `LO`/`HI` (cart RAM: `4000`, `7FFF`) and
  `NOREAD=1`. Its read tap on cart RAM is too slow there (MARIA's DMA reads
  fire it): the attract run had reached frame 100 after ten minutes.
- `p7800-cpureads.lua` gives the CPU's data reads; `probes/cartuse.py`
  merges both by page, with the readers named from the symbol file.
- Runs: the attract loop 14,000 frames, scenes 1-4 and 6 scripted 12,000,
  a game over (the cpureads runs 8,000-9,000 frames).

**What cart RAM holds** (bytes, play):
- **MARIA's lists: 4,360,** besides the 705 in console RAM. The top
  rows' slots and piece lists (`$42-$46`, `$4F-$57`), the band lists
  (`$54-$56`) and the zones' own lists in the framebuffer pages' heads,
  the list areas in `$60-$6F`, the band tails in `$7B`. The CPU reads some
  of them back (`TopRefSlot`, `TopDel1`, `StoryPatchObj`).
- **MARIA's graphics: 7,435:** the bitmap (27 pages, `$58-$72`), the
  slice pages, the story and title text, the black block.
- **The bitmap is read by the CPU too:** module B's blits (AND masks and
  OR sprites read the destination), level 1's column routine
  (`ColPByte`, `ColTByte`), and its page heads hold CPU data (the front
  boxes `FG_*`, read by `FtEmitFg`, `FgBox`, `BandWK3`, `BandWFront`).
- **Code:** module B (the game's blitters and fills), `$7C00-$7FFF`, 1K,
  self-modifying, copied in at each scene load.
- **The CPU's own data** (fine under the spec, in its own 16K): `FO_HB`,
  `FS_I` and the cell tables (`$7B`), the story's variables (`$43`) and
  pointers (`$40`).

**What the spec asks, then:**
1. **Module B out of cart RAM:** into console RAM (1K) or rewritten to run
   from ROM (its self-modified operands made variables).
2. **The bitmap twice:** the CPU's copy in its own cart RAM (the blits read
   it) and MARIA's written alongside through `$C000-$FFFF`: every store
   into the bitmap made twice (module B, the fast fill, the clears and
   copies, level 1's column routine).
3. **MARIA's other graphics** (slices, text, black block): written through
   `$C000-$FFFF` only.
4. **Every list in console RAM:** about 5.1K of lists today against about
   2.3K console RAM could give them. That needs every CPU-only byte out
   to the CPU's cart RAM (1.76K) and the code (the fast fill, module B)
   not there. This looked like the blocker: see the next section.

### BankSet: the lists' real size (2026-10-09)
**The user:** display lists are never in ROM, period. (Correction: the
inventory above suggested fixed lists in MARIA's ROM; dropped.)

**What a picture needs** (`probes/p7800-listsize.lua` on this build: each
frame's lists walked as MARIA reads them, each list once; `TEXT=1` now
measures the text screens instead of play):

| run | DLL entries (worst) | list bytes, mean | list bytes, worst picture |
|---|---|---|---|
| attract (play parts) | 61 | 396 | 511 |
| level 1 | 61 | 379 | 491 |
| level 2 | 61 | 394 | 550 |
| level 3 | 61 | 355 | 491 |
| finale | 43 | 303 | 314 |
| vs fight | 61 | 462 | 475 |
| game over | 61 | 230 | 342 |
| title and story | 34 | 359 | 1,460 (the title: 355 objects) |

- **Play:** at most 550 list bytes and 183 of DLL a picture, about 730 a
  buffer, about 1.5K for both. The 4.4K in cart RAM is the layout: fixed
  slots per zone, page heads, worst-case areas, both buffers, the text
  screens' lists beside play's.
- **Console RAM** less zero page and the stack (384) and the fast fill's
  code (372) leaves about 3.3K, once the CPU-only data (1.76K) moves to the
  CPU's cart RAM and module B runs from ROM. Play's lists fit with room;
  the title's (1,460 a picture) fit if play and the text screens share one
  area, and shrink a lot once the title's images come from MARIA's ROM.

### BankSet: cart RAM write-only, the blitter reads it back (2026-10-09)
**The user:** cart RAM is write-only for the CPU and read only by MARIA
(the CPU's own 16K under the spec is not to be used either); the CPU's
data stays in console RAM. (Correction: the previous two sections planned
the CPU-only data into the CPU's cart RAM; dropped.)

**The blitter reads the bitmap in every mode** (module B, `$2800-$2BFF`
in the original, `dis.py 1 2800-2C00`):
- Its mode is `$0F`, and `$28A0` patches the store at `$2925` to match:
  - `$0F` 0: `ORA ($14),Y` then `STA ($14),Y`: OR, reads every byte;
  - `$0F` negative: `AND ($14),Y`: AND (the masks), reads every byte;
  - `$0F` positive: `NOP`s, a plain store.
- Even the store mode reads: each row's last byte (the shifted image's
  spill, `$2937`) is `LDA ($14),Y`, `AND $2985,X` (the destination's pixels
  outside the image), `ORA $19`, `STA`. With no shift it rewrites the byte
  unchanged, but still reads it.
- The blit census (`bcs-*`, play): store mode makes almost all the draws
  (16,800-130,800 a run), OR and AND a few hundred to 5,200 (the scene's
  own enemies, text, cutscene figures).
- Level 1's column routine (`ColPByte`, `ColTByte`) reads the bitmap too.

**So under this rule the blitter can't stay:** the bitmap can only be
written, and every blit mode needs to read it. Patching it to skip the
spill byte would leave the shifted images' right edges wrong (the
neighbouring pixels lost).

**Console RAM under this rule** (all CPU data stays there):
- 4,096 less zero page and the stack (384), the CPU data now in console RAM
  (1,760) and the CPU data now in cart RAM that comes back (about 450:
  `FO_HB`, the sort and cell tables, the story's variables and pointers,
  the front-box tables) leaves about 1,500.
- Play's lists and DLLs need about 1,470 for both buffers (550 + 183 a
  picture, worst). The fast fill's code (372) and module B (1K) have to
  leave RAM to get there; both go with the bitmap.
- The title's lists (1,460 a picture) need its images from MARIA's ROM
  and far fewer objects.

### The title and the opening scroll in their own bank: sizing (2026-10-09)
**The user:** give the title screen and the opening scroll their own page
space, drawn from a pre-rendered MARIA image with holey DMA; or character
mode, if the zone grid can follow the scroll each frame.

**Which banks are in while they run** (`p7800-bankshare.lua TEXT=1`, the
attract loop's title and story, frames 150-4,200): bank 5 (the port's
code) 53%, bank 0 (scene 0's page) 47%. Both banks' MARIA copies carry the
shared window block that play needs, so the title's images can't live in
either. They need a bank of their own, the only one in the window while
MARIA draws them: its CPU half a copy of scene 0's page (the game's title
and story code runs from it), the port's per-picture work done there or in
the fixed bank (the frame's vertical-blank work may use any bank: MARIA
reads nothing then). The cart has no spare bank: 2 × 256K (the user's
core: `cart_size_bs[18]`; MAME's BankSet device counts banks from the
size) gives banks 7-14 spare, the fixed bank becoming 15.

**The story** (`probes/storytext.py`: 22 strings, 14 rows apart, 308 rows
of 40 bytes, 12,320 bytes):
- **Holey DMA, pre-rendered strips** (each strip trimmed to its columns):
  9,488 bytes in 8-row strips, 10,496 in 16-row strips. Holey DMA zeroes
  every other 2K (or 4K) block of `$8000-$FFFF`, so a bank's window holds
  at most 8K of strips, and the block at `$8000` needs cart RAM below it
  zeroed. Too big for one bank.
- **Character mode** (1-byte characters, 4 pixels wide, 14 rows: one text
  line a zone): **250 distinct characters with the blank (under 256), 3,500
  bytes, plus 880 bytes of maps** (22 lines × 40 codes), 4.4K.
  - **The zone grid follows the scroll:** each DLL entry has its own height,
    and the DLL is rebuilt every frame, so the zones stay on the text lines
    as it scrolls. A full zone reads its line's 14 rows.
  - **The top partial zone** (height h) reads offsets h-1 to 0: a
    character's bottom rows, which is what a line scrolling off the top
    shows.
  - **The bottom partial zone** needs the line's top rows instead: a DLI
    there moves CHBASE by 14 - h for it, once a frame.
  - Two indirect objects a zone (40 codes, at most 32 an object).
- **The title** (the logo, "presents", "a game by", "jordan mechner", the
  copyright) is still to be sized as a pre-rendered image: a few hundred to
  2K bytes, static, direct objects.

### The title and the opening scroll in bank 0's MARIA copy: done (2026-10-09)
The user: yes to the plan (bank 0's own MARIA data, the story in character
mode), and: treat cart RAM as MARIA's pseudo-ROM on its way to becoming
fixed ROM, never as the CPU's.

**The data** (`port/titlemaria7800.py`, from the build):
- **Top data re-packed by scene** (`layout7800.TOP_GROUPS`): scenes 0, 3
  and 4 share the first group (196 columns), levels 1 and 6 the second
  (244), level 2 the third (160). The second and third groups' 30 pages
  (`TS_PAGES`, `$8F-$AC`) hold only data for scenes bank 0 is never in for,
  so bank 0's MARIA copy has them for itself. The fighters' packer leaves
  them alone: MARIA's half has 3,042 bytes free (4,662 before).
- **The story:** its 22 strings rendered as the game's `$0780` draws them,
  cut into 250 characters 4 pixels × 14 rows (code 0 blank) at `TS_CB`
  (`$8F`): character k's row r at page `$8F + 13 - r`, column k. Each
  string's 40 codes, its map, in the top 16 pages. 4.4K in all.
- **The title:** its ten objects drawn into two canvases 40 bytes wide (the
  logo's rows, the copyright's), a later object's pixels over the earlier's,
  as MARIA draws them; cut into four chunks of at most 16 rows, each row a
  page lower than the last.

**The lists** (`BuildTs`, `TsZone`, `TsRows`, `TsTitle`: far pieces in
scenes 0 and 4's pages, run with bank 0 in):
- `BuildDllF` sends the title (the buffer's marks) and the story (`S_STORY`
  2) to `BuildTs` instead of the top bank's `BuildDll`. It reads the same
  run description (blank lines, flagged lines, buffer rows), so the game's
  DLIs stay on their lines.
- **The story's zones** follow the scroll. A text line's zone ends at its
  slot's end, at a DLI's line or at the text's edge. It gets two indirect
  objects (20 codes each) reading the line's map, and its CHBASE is `$8F +
  14` less its last row in the slot.
- **The title's zones** are two direct objects (20 bytes each) reading a
  chunk, the high byte for the zone's rows. Rows outside the buffer's marked
  canvases are blank.
- The lists live in `DLS_A`/`DLS_B` from offset `$20` (the row lists use
  about 30 bytes below).
- **The story's step** (`StoryTs`) and **the title's marks** (`TitleLogoF`,
  `TitleCopyF`, now in the fixed bank) no longer go through bank 5. The
  per-picture work in the main program runs with bank 0 or the fixed bank in.

**CHBASE per zone, and the NMI:**
- A zone whose CHBASE differs from the zone of characters before it carries
  a DLI: the game's, if its line has one, else one of ours.
- `TS_CHTV` holds each DLI's CHBASE (A's from `$2101`, B's from `$2120`:
  console RAM `$2100-$213F`, which no one writes). `TS_CHTP` holds whether
  the DLI is ours alone, one entry on, in `DLS_A`'s tail.
- **The NMI begins in console RAM** (`NMI_STUB`, copied with the static
  lists at the boot; the vector points there): `PHA`, then `JMP NmiGo`.
  While the title's or story's list is shown, `TsFirst` (at each vertical
  blank and `Apply`) makes it: `LDA TS_CHTV+n`, `STA M_CHBASE` (17 cycles
  in), `INC` both table operands (29 cycles in), `LDA TS_CHTP+n+1`, and a
  DLI of ours alone is counted and done there.
- **Why so tight** (MAME's MARIA): a zone's DLI comes as MARIA moves into
  the zone, right after the previous line's DMA, and the zone's first line
  is fetched at the next line's start. A text line's DMA (two indirect
  objects, 40 characters) leaves the CPU about 40 cycles of the line. And
  a DLI of ours can come one line after the game's (a 1-line DLI zone
  splitting a text line).
- **Dead ends on the way:**
  1. The first version had the NMI write a value the previous DLI's handler
     had set. The game's DLI one line before was still in its handler, so
     the zone after kept the old CHBASE (doubled rows from step 20).
  2. Each NMI taking its own entry 35 cycles in: still too late after a text
     line (the next DLI nested first; the rows out of order).
  3. A stub writing CHBASE but leaving the next value to the ROM handler:
     the patch came 47 cycles in, after the next DLI.
  4. The self-advancing stub with its flag test after the `INC`s: `BNE`
     tested the `INC`, every NMI looked like ours, `NmiGo` never ran, no
     vertical blank was ever seen and the attract loop froze in
     `ObjBlankWait`. Also from that: `BuildTs` now clears the buffer's
     whole table first. Past the frame's last entry, every NMI then goes on
     to `NmiGo`, whose vertical blank resets the stub.

**Checked:**
- **The title and story as shown** (`probes/p7800-textsnap.lua`:
  screenshots at the title's settled marks and at story steps 5, 20, 60,
  100, 139, 140, 141, 200, 260, 300, 350 and 376): every picture
  identical, pixel for pixel in colour, to `2026-10-09_KEEP_enh-topmaria`.
  The scroll keeps its pace (step 376 at frame 3,840 against 3,859).
- **The bank** (`probes/p7800-tsbank.lua`: every read of `$8F00-$ACFF`
  while the title or story is up, that isn't the CPU's): 26,735,325 of
  MARIA's reads, all with bank 0 in, none with another.
- `checkdl.sh`: scenes 1, 2, 3, 4 and 6 no picture over 300. The attract
  loop has one (picture 190, the story's last frame as the screen goes
  blank). Both builds rebuild the shown buffer's list in place during
  that frame (`ObjBlank`, then `Frame`). The old build's rebuild lands
  later in the frame (3,843 of 3,857 text pixels still shown), the new
  one's earlier (617). A one-frame tear of the hand-off, from timing.
- **The ending** (scene 4's `$B84E`, jumped to at flip 200), still the old
  letters through `BuildDll`: identical at frames 200 and 400; after it
  the attract loop's story scroll draws correctly (a step apart, timing).
- `freecheck.sh`: 0 writes.
- **The text screens' lists** (`p7800-listsize.lua TEXT=1`): at most 198
  bytes a picture (1,460 before), 97 on average (359).

**Room:** bank 0 15,266 bytes used, bank 4 15,339 (the far pieces are in
both), the fixed bank 15,554.

**Freed but not yet given back** (cleanup, last): the title's canvases and
templates in cart RAM; bank 5's `TitleLayout`, `TitleMark`, `StoryStep` and
`StoryBuild`; the far pieces `TitleLocate` and `TitleZoneH`. The ending
still uses `StoryInit`, the glyph pages and `StoryPatch`.

### The ending's text as characters (2026-10-09)
The user: the ending should do what the scroll does, without scrolling.
(Correction to my reply before: scene 4 has its own page, bank 4, not bank
0's. The same holds there: bank 4 is in the window only during scene 4,
so the TS pages are free in its MARIA copy too.)
- **The data:** the ending's ten strings (scene 4 `$6318`/`$6323`), 14
  rows apart from row 0, rendered and cut as the story's are: 188
  characters (2,632 bytes) and 10 maps in bank 4's MARIA copy, at the same
  addresses as the story's in bank 0's (`titlemaria7800.layout`, scene 4;
  the build checks `TS_CB` agrees, and line L's map has the same place in
  both). The far pieces and their tables are the same bytes in both pages,
  so the same code draws either.
- **The code:** `EndText` (scene 4's `JSR $6200`) sets the text's rows (0 to
  `END_BOT`), its line count (`END_N`) and the step at which the first line
  is at row 0 (`STORY_ROW0`), turns on `S_STORY` 2 and forgets both
  buffers' lists. `BuildTs` then makes them; nothing advances the step.
  `TsRows` takes the rows and lines from `S_STOP`, `S_SBOT` and `S_SLN`
  (`StoryTs` sets the story's at its first step).
- **Checked:**
  - the ending jumped to (scene 4's `$B84E` at flip 200): identical to
    `2026-10-09_KEEP_enh-topmaria` at frames 200 and 400;
  - `p7800-tsbank.lua` (now: the scene's page is the bank wanted; `JUMP`
    runs `p7800-jumpto.lua`): 11,188,042 of MARIA's reads with bank 4 in,
    none with another;
  - the attract loop again: 26,739,461 with bank 0, none with another;
  - `checkdl.sh`: scenes 1-4 and 6 none over 300, the attract loop's one
    the story's last frame (above);
  - `freecheck.sh`: 0 writes.
- **Room:** bank 0 15,293 used, bank 4 15,366.
- **Now dead** (cleanup, last): the letter-object machinery: bank 5's
  `StoryInit`, `StoryStep`, `StoryBuild`, `StoryZoneH`, `StoryEmit`,
  `TitleLayout`, `TitleMark`, the glyph tables; the far pieces
  `StoryLocate`, `StoryPatch`, `TitleLocate`, `TitleZoneH`; the text pages
  in cart RAM (glyphs, templates, patched lists, canvases).

### The public toolkit's update, merged locally and reviewed (2026-10-09)
The user: merge the a7800-toolkit update locally and see whether its
improvements help.
- **Merged:** `../a7800-toolkit` (the public Miasmark/a7800-toolkit clone)
  `main` fast-forwarded 63 commits to `origin/main` (789a7fa, PR #4: Round 3
  accuracy fixes, BankSet in the census/disassembly/rebuild, `dmabudget`,
  `zonebill`, the simulator family). Its old branch `toolkit-lessons-from-pp2`
  was already in `main`. Nothing pushed; `a7800-toolkit-local` (the Karateka
  fork) untouched.
- **What helps:**
  - **`probes/dlitimes.lua`** (the beam position from `time_until_pos`,
    which our MAME's Lua lacks as `vpos`): it watches fetches only from
    `$4000` up, and our NMI vector now points at console RAM, so a local
    copy watches from `$1800` (`probes/tmp-dlitimes.lua`). On a story frame
    (1,313, step 60): a DLI after a blank line is fetched 23-26 cycles into
    its zone's first raster line, and one after a text line 87-91 cycles in
    (the text line's DMA comes first). So the stub's CHBASE write (about 10
    cycles after the first fetch) lands about 12 cycles before MARIA fetches
    the zone's first line, and both its INCs finish by the line's end, a
    line before the next DLI can come. **That margin is MAME's model; on
    hardware it is the risk to watch:** a few cycles more DMA or a later
    DLI would draw one line with the old CHBASE at the top of such a zone.
  - **`tools/dmabudget.py`:** MARIA's DMA costs, measured in MAME (a
    fixed-cost loop per display-list shape; a graphics byte about 3 colour
    clocks; zone height and RAM against ROM make no difference). Its holey
    DMA facts, measured: with the 16-line bit a fetch is dropped when
    address bit 12 is set (`$D000`, `$F000`), and the 8-line bit made no
    difference in `$C000-$FFFF`. MAME's timings, "corroboration, not
    silicon".
  - **`tools/zonebill.py`:** bills a frame zone by zone from a console-RAM
    dump. Our lists in cart RAM are walked as empty (a lower bound); it
    becomes useful as the lists move to console RAM.
  - **`tools/mariapix.py`:** its 160B layout (bits 7-6 c0, 5-4 c1, 3-2 p0,
    1-0 p1; the write mode in bit 7 of a 5-byte header's second byte)
    agrees with what the fighters' heads use.
- **What doesn't yet:** `tools/census.py` / `sim.py` run the cart (the
  display list live on 1,193 of 1,200 frames), but the RAM census covers
  console RAM only and its MARIA sampled no ROM at all (not our cart RAM
  lists, not MARIA's half). So they can't replace our cart-RAM and
  MARIA-read probes; extending them would be a public-toolkit change.

### The text's code and data given back (2026-10-09)
The user: no need to trim the text further, but the characters shouldn't
need to be in CPU ROM any more, which should help space.
- **The dead code out** (the letter objects: `TitleZone`, `StoryPatch`,
  `Story`, `TitleLayout`, `TitleMark` and `StoryLocate` pieces; the
  builder's story and title zone hooks; the fixed bank's wrappers,
  `TitleBits`, `BuildDllS`, `StoryInitF`; the build's glyph, advance and
  title-object tables): bank 5 15,854 → 14,481 bytes used, banks 0 and 4
  400 less each, the fixed bank 15,554 → 15,444. The builder's blank zone is
  `ZoneEmitBlank`. `ObjBlank` and `ObjEnd` stay: they make the screen
  transitions.
- **The data given back** (`PAGE_RELEASE`, checked: no instruction, label
  or relocation of any scene in the page inside):
  - the logo's five letter images (scene 0 `$7C00-$7E96`, less `$7C50-$7C55`:
    bank 15's jump for the scene's own enemy, `$7C50` (scene 4's Akuma),
    counts as code in every scene's model; in scene 0 those bytes are a
    letter's image and the jump is never taken there);
  - the second copyright line (scene 0 `$6100-$6206`);
  - the story's strings 5-25 (scene 0 `$79D2-$7BCB`; string 4 is also
    string 3's, so it stays);
  - the ending's ten strings (scene 4 `$620E-$6314`).
  - Bank 0 14,893 → 13,468 used, bank 4 14,966 → 14,703.
- **Kept:**
  - the first copyright line (`$2193-$2275`, the fixed bank's engine):
    scene 4's model has a relocated pointer at `$21F8` inside it;
  - the glyph block (bank 5's `IMG_SPRITES`): the game's own text routine
    still draws "the end" from it (its tenth row is the blitter's).
- **A note on the tools:** the build assembles with
  `../a7800-toolkit/tools/asm.py`, which the merge updated; the pictures
  below are the check.
- **Checked:** the 14 title and story pictures and the ending identical to
  `2026-10-09_KEEP_enh-topmaria`; a game over (flips 200-420, 111 pictures)
  identical to `2026-10-09_KEEP_enh-coverage`; `checkdl.sh` as before
  (scenes 1-4 and 6 none over 300, the attract loop's one the story's last
  frame); `freecheck.sh` 0 writes.

## Level 1 without the blitter (2026-10-09)
The user: remove the blitter on the first level (the cliffs). Use cart RAM
as MARIA's pseudo-ROM, copying the graphics from CPU ROM for MARIA to read;
character mode for the repeating patterns; it scrolls only horizontally, so
the vertical grid stays and only the horizontal place moves: the Midnight
Mutants technique.

### What level 1 draws, per picture (measured)
`probes/p7800-l1draws.lua` (each flip: the game's zero page; each blit's
kind, source, size, mode, row, column and shift at `BlitBankKeep`; each fill
at `RowBase`, by its caller's page; the column routine's calls): scene 1
scripted, flips 191-822, `$4C` 0 throughout. 18,777 blits, 4,407 fills,
about 32 blits and 8 fills a picture.
- **The scenery is a few small images from the scene page, redrawn every
  picture at new places:**
  - the posts: stacks of the 2×2 tiles `$A684` (and `$A703`, `$A85F`,
    `$A68A`), with caps and bases (`$A87B`, `$A6A6`, `$A6C0` at rows
    118-130, `$A6EF` 18×1, `$A877`, `$A6D4`);
  - the fence: rails `$AA11` (8 × 2 bytes, row 69) at every even column,
    its ends `$AA23`/`$AA31` (12 × 1, plain and mirrored, row 65), its edge
    pieces `$A9B8` (4 × 10) and `$A9E2` (3 × 15);
  - the torii: the pillar (`$AB8E` 1 × 4 stacked rows 82-116, `$AB4A`,
    `$AB94` in AND mode, `$AB7C`) and its shadow `$AA7D` (29 × 6, row 117);
  - rarely the mountain (`$A948`, `$A976`) and Akuma's cutscene pieces.
- **The fills:** the fighter-box erases (rows 79-117 and 118-128 over each
  fighter: they erase only what is an object now) and wipes at the
  screen's sides (columns 0-4 and 28-40, the whole height) as the view
  moves.
- **The movement:** the scenery moves 2 pixels a picture as the player
  runs. The column ($05) and shift ($10) of each draw are worked out as
  the game goes. Sampled at a picture's first draw, no zero-page byte (or
  pair) gives every post's place: the best single byte matches 59 of 213
  pictures. (`$52` and `$50` are the player's column and shift, not the
  view's: the note in "The RAM census: correction" calling `$50` the
  scroll's shift is wrong.)
- **Correction, measured at the draw** (`ZPAT=A684`: the zero page at each
  post draw): a post's x is exactly 4 × `$52` + `$50` / 2 (213 of 213).
  But `$52`/`$50` (and `$05`/`$10`, `$51`, `$91`) are that draw's own
  parameters, set for each piece as the game goes. No zero-page byte or
  pair holds the view's place, so the scroll position is in the scene
  code's own variables, not found yet.

### The design proposed
**The game's own draws say where things are; MARIA draws them from cart RAM
as characters and slices; nothing is blitted.**
- **At the scene's load:** the scenery images (above, about 1K) copied
  from the scene page into cart RAM as MARIA's data, the bitmap's pages
  (`$58-$72`) free for it in level 1:
  - the repeating ones as characters: the fence rails (one 8-row
    character a 2-byte step), the post's 2×2 tile stacked (one character
    repeated down a zone), the ground (`$55`);
  - the rest as slices on the band's grid (one byte column in 8 pages):
    the torii's parts, its shadow, the posts' caps and bases, the fence's
    ends and edges.
- **Each picture:** the scenery blits captured at `BlitBank` (column,
  shift, row: as Akuma's are) and dropped, the fills dropped (the edge
  wipes only clean up what the bitmap kept).
- **The lists:** the band zones keep their rows (no new vertical grid).
  Each zone gets one indirect header for its character layer, its x from
  the captured rails' phase (2 bytes in the header move it); one object
  per post and piece crossing the zone, at its captured x; then the
  fighters; then what the game draws after them.
- **Why not a world map scrolled by headers alone:** that needs the view's
  position, which is in the scene code's own state and not found yet, and
  the stretch's layout as the game generates it. The captures give both
  for free, at the cost of a capture a draw.

### Level 1's view position, found (2026-10-09)
The user's hints: the vs fight locks the view, and level 2's camera swings
between the player and the enemy as they close in.
- **The vs fight's patches name the scroll:** among the 40 sites ("The vs
  fight in level 1's page") it skips `INC`/`DEC $52`, `$51`, `$62`,
  `$72`, `$91`, five `STA $46`/`$47` and `JSR $6D0C`.
- **Read at the right moment:** sampled at a picture's first draw, `$52`
  is the draw routine's working copy (each piece's column as it is
  drawn), which is why the first search found nothing.
  `p7800-l1draws.lua` now also logs the zero page at `TopFlip`, when the
  picture is done (`end N zp ...`). There `$52` (and its copy `$E0`) is
  the view's column and `$50` its shift in eighths.
- **The view:** V = 4 × `$52` + `$50` / 2 pixels. Every scrolling piece is
  at V plus a fixed offset of its own, in every picture of a structure
  (`$4C`), from the `RUN=200` run (`playkey.lua RUN=n`: right held from
  flip n; invincible-easy cart, flips 191-1,630):

  | piece | x | fits |
  |---|---|---|
  | post tiles `$A684`, `$A703`, `$A85F`, `$A68A` | V + 28, 36, 8, 8 | all |
  | post bases `$A87B`, `$A6A6` | V + 4, 12 | all |
  | torii `$AB8E`, `$AB7C`, `$AB94`; its shadow `$AA7D` | V + 104; V + 88 | all (`$4C` 0) |
  | `$A000`, `$A2B0` (`$4C` 1) | V + 40, 16 | all |

  In `$4C` 1 the torii's parts follow `$E4` instead, a counter of their
  own.
- **What doesn't scroll:** the fence's rails `$AA11` are drawn at fixed
  screen columns (x 0, 8, 16, ... or 112, 120, ...: their phase against V
  is spread evenly), and its edges and the torii's top (`$A9B8`, `$A9E2`,
  `$AB4A`) at fixed x.
- **The run:** `$4C` 0 (the cliff's start, `$52` 33-48), then `$4C` 1 from
  flip 666, where `$52` falls steadily through 0, wraps (an 8-bit column)
  and comes back down to about 90, then `$4C` 0 again (`$52` 65-91).
- **For the Midnight Mutants scroll:** a structure's scrolling scenery is
  a fixed layout around V, so it can be rendered at build time into a
  character map per structure. Each picture then sets the headers' coarse
  place from `$52` and the fine one from `$50`. The fence and the fixed
  pieces are their own objects at their fixed places. `$51` (the posts'
  wrap) and `$E4` (the torii's in `$4C` 1) say where a repeating piece is
  when the layout repeats.

### The gate's smear is the original's (2026-10-09)
The user saw a glitched gate in the run's pictures (`p7800-l1snap.lua`:
level 1 along the `RUN=200` run, a snapshot at `TopFlip` every `STEP` flips
with `$52`, `$50`, `$4C`, `$E4` logged). After Akuma's cutscene, as the
player walks on through the first gate, the gate stops moving while the
fence scrolls, and its roof picks up vertical bars.
- **The original does it too:** `xe-l1snap.lua` (the same scripted run on
  the XEGS with `xe-easy.lua`) shows the gate smeared from flip 840. So does
  the human playthrough (`xe-01-easy.inp`, `xe-recsnap.lua`: a snapshot every
  150 frames), from frame 3550, right after the cutscene and before any guard
  shows up. So it isn't caused by running past a guard.
- **How:** once the gate's columns pass the screen's left edge the game
  stops drawing it (`$A000`-`$A39C` aren't blitted after flip 845), and its
  side wipes (columns 0-4 and 28-40) don't clear the middle. What it drew
  last stays in the bitmap.
- **The port differs in the detail:** its top rows are objects whose
  capture rules keep the roof whole, while the bitmap below keeps the
  palisade's stripes. The original smears the roof and erases the palisade.
- **Correction: a clean run never smears.** The user recorded one on the
  invincible-easy cart (`inp/karateka7800-invincible-easy-02.inp`, 18,787
  frames, to scene 4). Played back with a snapshot every 120 frames
  (`probes/p7800-recsnap.lua`, the BankSet MAME), the first gate scrolls off
  the left edge cleanly after the cutscene (frames 3000-3120). Each later
  guard comes in by the gate at the right (`$4C` 1, frames 3240, 3840, 4320,
  4800-5160). The gate never stops mid-view. The smear comes from the
  scripted run holding right past the guards (the user's reading), and
  `xe-01-easy.inp` must have done the same. So the bitmap's own rules are
  enough, and nothing needs to keep the gate moving. The user: no smeared
  gates.
- **What does scroll there:** the fence's posts (`$AA23`, every 48 pixels)
  stay at V + a constant (mod 48) in every picture, so V is still the view.
  But the scenery is not one map keyed on V: the game decides what it draws,
  and the mountain's base (`$A9B8`, `$A9E2`) and the rails (`$AA11`) are
  fixed on screen.

### Level 1 without the blitter: the draws as pieces (2026-10-09)
**The plan changed:** not a map per structure keyed on V (see above), but
the game's own draws, as the top rows already work. Each blit's image is in
cart RAM (copied from the scene page), and each blit becomes an object at
the blit's own place. Characters serve the repeating fills and the rails.
The zone grid stays, so the objects only move sideways. Step 0 proves the
rules offline, in Python, against the real framebuffer.

**The log** (`probes/p7800-l1cap.lua`): every draw reaching rows 65-145 in
order (blits as `BlitBankKeep` sees them; fills at `$2CCD`/`$2D03` with
`S_NOFILL`; the column routine at `ScColA`/`ScCol68`; full clears; buffer
copies), and at `TopFlip` both buffers' rows 65-145.

**Model 1, the bitmap** (`probes/l1model.py`): the blitter's semantics on a
model framebuffer. It matches both real buffers in every picture of the
`RUN=200` run (1,254 pictures, flips 191-1,445: the cliff, the run, Akuma's
cutscene, the gate). The rules it proves:
- **A blit** (module B, `$7C00`; disassembled from RAM,
  `probes/tmp-ramdump.lua`) replaces exactly its image's pixels, `[x, x + 4w)`
  for each row, with x = 4 × `$05` + `$10` / 2 (the shift's low bit is
  ignored). It keeps the destination's pixels either side of a shifted image:
  the first byte's left and the spill's right. It clips at pixel 0 and 160.
  Mode `$0F`: positive stores, 0 ORs, negative ANDs.
  - Mirrored (`M`, `$7F82`): the same span, the image's pixels reversed (the
    byte table at `$F500` is a plain pixel reversal).
  - Right-aligned (`AR`, `MR`): `$05` − width + 1 first.
- **A fill** (`$2CCD` rectangle, `$2D03` pattern; bank 15's clip at `$F7A4`):
  - columns `$05` to `$09` and rows `$06` to `$08`, both end-exclusive;
  - a top above row 0 is row 0; a negative left is 0, unless the right is
    past 40 too (then nothing);
  - the rectangle's byte is `$02`;
  - the pattern alternates `$02` and `$12`, with `$02` on the bottom row;
  - `S_NOFILL` set: nothing painted (the fighter-box erases).
- **The column routine:** the caller's piece again every 2 rows, the last at
  the first row at or past the limit. Through `ScCol68` with `$52` negative
  or below `$14`, every piece is its own (logged) blit.
- **A full clear** zeroes the buffer. A copy copies the other buffer.
- **Two dead ends on the way:** the fill's top clamp first caught real rows
  128-145 as wrapped (it's raw `$06` below `$23`, row ≥ `$DD` here). A blit
  probe on `ColA` itself also catches other banks' code at that address (the
  `col src 83A8` lines in `l1draws.log`).

**The user's clean run as a second test** (`inp/karateka7800-invincible-easy-02.inp`,
played back by `p7800-l1cap.lua` with `PLAYBACK=1 END=5300`: level 1's 635
pictures, the cutscene and every guard): model 1 matches it in every
picture too.

**Model 2, objects in draw order** (`probes/l1pieces.py`): each buffer keeps
its draws as pieces (blits and fills), drawn as MARIA would, each opaque. A
piece uses at most 3 colours, so a palette per piece holds all of them and
none needs colour 0. That is the blitter's painter's order, and it matches
both runs except a 1-pixel spot in Akuma's cutscene (its AND/OR figures).
- **The trap:** treating a piece's background-coloured pixels as transparent
  (MARIA's colour 0) lets the pieces under it show through. Every later draw
  hides what is under it, whatever its colour.
- **Keeping the list short:** a draw drops the pieces wholly under it (rule
  a). A redraw of an image in a row drops that image's overlapping copies in
  that row from the buffer's earlier pictures (rule g). Both keep the picture
  exact. A buffer then holds 90-145 pieces, of which about 50-60 matter at
  any moment.
- **Too slow for MARIA as it stands:** the cost per line (toolkit
  `dmabudget.py`: 2.081 cycles an entry, 0.744 a byte) reaches 150-316
  cycles in the worst pictures, against about 100 in a line before the
  fighters.
- **With a perfect clean-up** (`l1oracle.py`, scratchpad: only the pieces a
  picture needs; full-width fills as the row's background): 10-90 pieces a
  picture, and the worst line costs 30-100 cycles. The fence rows (69-76)
  are the worst at 91-104, because the rails are 20 pieces. The band rows cost
  about 35, the floor rows 40-60.

**One world image per structure doesn't work** (`l1wcons.py`, scratchpad:
each world pixel, x − V mod 1024, across the clean run's pictures). Within
a stretch the scrolling scenery is one world image, and only the mountain's
base (and `$AB4A` at x 0) is fixed on screen. But the pieces come back at
other world positions as the level goes on: the game recycles its torii and
posts through its own counters (`$51`, `$E4`). In structure 1 (`$4C`) the view
is held at `$52` = 27 while a guard comes in by the gate. So a map has to
be built from the draws as they come, not at build time.

**Model 3, a tile layer under the objects, fails:** fills and the rails
(byte-aligned) went into a tile layer, the shifted sprites stayed objects
on top. 631 of 635 pictures were wrong, with stale sprites left behind. The
game erases by drawing over (the rails over a post's old place, fills over
old pieces, often only part of them). A tile under an object can't hide it,
so every such erase would have to crop the object. Cropping a shifted
object on byte lines needs its data stored pre-shifted: 4 copies, 18K for
level 1's 3.5K of images, more than the freed bitmap's pages hold.
- **A dynamic tile map holding everything** (the floor-tile attempt) would
  need the tiles' contents read back to draw over them. Cart RAM is
  write-only for the CPU, and console RAM has no room for a copy.

### Level 1 without the blitter: tiles plus objects (2026-10-09)
**The user:** the simpler tiles-plus-objects layering. With no blitter,
nothing needs to be drawn over: the game's erase-by-overdraw needn't be
reproduced. Scroll as Midnight Mutants does, with no tile copied once per
shift; big objects can be sliced.

**The positions** (`l1world.py`, scratchpad, on both runs): against
V = 4 × `$52` + `$50` / 2, each scenery image sits at one place in the world:
- the posts at V+4..36 (plain) and V−12..−40 (mirrored, a second set);
- the torii at V−152, its shadow at V−168;
- the gate at V+16..48 (structure 1);
- the cliff's rocks at V−144..−156.

All of those are multiples of 4 pixels.
- **The fence's posts don't keep a world place:** they sit at V + 13 + 48k
  in the scripted run and V + 4 + 48k in the clean one. They are objects,
  placed where each picture draws them.
- **Fixed on screen:** the mountain's base (`$A9B8`, `$A9E2`), and the rails
  (`$AA11`, the same all along the row).
- **`$AB4A`** is the torii's beam, drawn from x 0 and cut by its AND mask
  `$AB94`: it belongs with the torii.

**Model 6** (`probes/l1tilemodel.py`), the layers from the bottom:
1. each row's background (full-width fills, the rails);
2. screen tiles (partial fills, the mountain's base);
3. the fence posts as objects (a fill over one drops it);
4. world tiles: every other blit, at its place against the view, a pixel
   of the row's background colour transparent.

The rules that keep it right:
- **A view change empties the buffer's tiles.** When V changes the game
  redraws everything it shows.
- **A draw already placed since then is skipped** (`--skip`). The game
  redraws pieces in static pictures (after the fighter-box erases). With
  whole-tile writes those redraws wiped their neighbours' pixels: 209 of 593
  pictures were wrong before this rule.
- **A fill makes what it paints over drawable again.** A full-width fill
  also clears the tiles in its rows.
- **Pieces layer as MARIA objects** (`--transp`): each one's
  background-coloured pixels show what is under it. That gives the same
  result as composing them.

Result on the clean run: 53 of 593 level pictures differ, all at the
cliff on the first screens (pictures 3-55), by at most 53 pixels. The
cutscene's room isn't modelled yet. The scripted run also differs from
picture 818 on (the smear, by design).

**So the build:**
- **Each structure is one or more sliced objects.** The torii with its beam,
  mask and shadow; the posts; the gate; each fill rectangle. Each gets one
  header per zone it crosses, at the hpos where the game drew it. MARIA
  shifts at any pixel, so no image is stored shifted.
- **The data:** each structure's zone slices are in cart RAM, copied from
  the scene page at load. Character mode wherever a pattern repeats (fills,
  the posts' and pillars' tiles, the palisade), each repeat sharing one
  character.
- **Cost:** a zone line carries 6-21 headers. Worst line as direct objects:
  50-120 cycles, the worst in the fence zones (65-80) where no fighter is.
  Folding the rails and the mountain's base into one static 40-byte row
  (2 headers) takes about 25 off.

### Level 1 without the blitter: the data and the plan (2026-10-09)
**The data** (`probes/l1shapes.py`, both logs): 181 shapes: 151 blits
(image, plain or mirrored, row), 11 column stacks, 19 fills.
- **Zone windows:** each blit and stack is cut into windows, one per zone it
  crosses (the zone's lines × its bytes, line g at page T − g, like the
  fighters' pre-cut parts). Its pixels are converted for the rows' background,
  so the one palette a zone object has can show black:
  - over the sky (rows 65-68): colour 2 transparent, black as 2 (palette 2,
    `TOP_PAL1`: black at 2);
  - over black (69-117): as drawn (palette 1);
  - over the floor (118-145): colour 1 transparent, black as 1 (palette 3,
    `TOP_PAL2`: black, sky, white).
  Zone 65-72 mixes sky and black rows, so a piece there gets two windows.
- **Size:** 390 windows, 6,172 bytes once identical ones are shared (7,223
  before). They pack into the bitmap's pages `$58-$72` (bytes 16-255:
  6,480).
- **The fills:** the background-coloured ones paint nothing (they only make
  pieces drawable again). The others are uniform patterns: one character
  each.
- **ROM:** banks 0-6 have 1.0-2.9K free each (bank 1, level 1's page: 1.7K).
  The windows can't sit pre-converted in ROM (6K), so they are generated at
  the level's load from the scene page's own images. The recipe is per shape:
  image, mirror, first row, rows, stack period, and each window's page and
  low byte. That's about 1.8K, and it doubles as the table the emission
  reads every picture. It goes in a bank with room, reached by a bank
  switch as the title's code reaches bank 0.

**Steps** (each checked before the next):
1. Build: the shape inventory (`port/l1shapes.txt`, from the logs), the
   zone windows packed, the recipe/shape table.
2. Load: the generator (mirroring through `$F500`, the colour swap per
   class) into cart RAM. Checked against the build's windows by a cart RAM
   dump.
3. Capture: in level 1, blits, column stacks and fills become per-buffer
   instance lists in console RAM (reset on a view change, redraws skipped).
   Nothing is drawn into the bitmap.
4. Emission: each zone's list carries the background strips, then its
   instances' objects in draw order, then the fighters (all zones of rows
   65-145, not only the band's).
5. The cutscene's room, the opening, scene 6; then checks against the model
   and the hardware.

### Level 1 without the blitter: steps 1 and 2 built (2026-10-09)
**Checkpoint first:** `Karateka-Port-checkpoints/2026-10-09_KEEP_enh-ending`
(title, story and ending as characters; the level-1 work taken out of a copy
of the source, which rebuilt byte for byte as `work/karateka7800.a78`).

**The build** (`port/l1scene7800.py`, called by `build7800.py`):
- **Checks:** level 1's play lists (`$1908`, `$19B3`, scenes 1 and 6) make
  the zones the tables assume. They are the only lists level 1 shows
  (`probes/tmp-dlsample.lua` on the clean run; `$1A5E`/`$1B04` only before
  the level starts).
- **The shapes:** the inventory `port/l1shapes.txt`
  (`probes/l1inventory.py`: 78 blits and 11 columns; the column routine's own
  pieces are its column's), plus the rails (`$AA11`) as one shape 20 bytes
  wide with its 2 columns repeated.
- **The windows:** 423 windows packed into `$58-$72` (6,144 bytes; 336
  free). A column-first scan packs them where a page-first one ran out.
- **The tables:** a record per shape (image address, row, flags, limit,
  width, first part, entries; then (T, C) for each zone part) in bank 3, each
  in any free run, with an index `L1S_R` (bank 3's free space is in pieces).
  The zone parts' table (`L1P_*`: zone 0 twice, its sky and black rows) is
  in level 1's page.
- **The generator's twin:** `l1scene7800.generate` does what the 6502 does,
  step for step. The build fails if it doesn't reproduce the layout.

**The 6502:**
- `L1Load` (main block, from `LoadScene`): `S_L1` (`$1F7F`, the ledger's
  free byte) on in scenes 1 and 6; `L1Gen` run; its RAM cleared.
- `L1Gen`: in level 1's page (the scene page jump table's `ScL1Gen`; 570
  bytes). It reads the tables and the art bank's image rows through
  `L1Fetch` (main block, `SysL1Fetch`), which copies bytes from another bank
  to `L1G_BUF`.
- **Where things couldn't go:**
  - The fixed bank: no run of 555 bytes left.
  - Bank 1 for the tables: too little room beside the code.
  - Banks 0 and 4 for anything run during level 1: their MARIA copies hold
    the title's data where level 1's top pieces are, so they mustn't be in
    the window while level 1 shows.
  - The level-1 page code only sees the build's equates (the jump tables'
    addresses), not the main block's or the far pieces' labels.
- **Its RAM:** `L1RAM` = `$2600`, the fast fill's 369 bytes. `LoadScene`
  copies the fill there for every scene, and level 1 never runs it once its
  fills are taken (step 3). The view per buffer, counts, the generator's
  scratch, and two instance lists of 70.
- **Symbols:** the build now writes `.sym` and `.zp` beside the cart it
  makes (`work/l1wip.sym` for `work/l1wip.a78`), so a test build no longer
  overwrites `work/karateka7800.sym`.

**Checked** (`probes/tmp-l1gen.lua`: cart RAM `$5800-$72FF` dumped at
`TopLoadF` after level 1's load, frame 2,427): every window byte matches the
build's layout.

### Level 1 without the blitter: overlays, MARIA's time, speed (2026-10-09)
**Four-colour parts as a base and an overlay.** 38 shape parts use all four
colours (the posts' bodies in the fence rows). The base shows its least-used
colour clear, and an overlay window draws just that colour (mode 3,
`OVER_OF_PAL`: palette 1 draws colour 1 as 1, palette 2 black as 2,
palette 3 the sky as 2).
- **The overlay has no record of its own.** Its entries follow the base's in
  the base's record (flags bit 2: twice the entries). Separate overlay shapes
  cost 23 more headers, index entries and lookup entries, and bank 3 had no
  room for them.
- **The generator** (`L1Gen`) runs the second half of the entries in mode 3
  for the same parts. `L1Obj` emits the second half at the same place.

**Bank 3's room.** It is level 1's scene bank and nearly full. What made room:
- The shape index is placed before the records. The records go best-fit
  (the smallest run each fits), so the large runs stay free for the code
  pieces. First-fit had cut every run of 200+ bytes into pieces.
- **The records are slimmed** to what the emission reads: flags, width,
  first part, entries; then the entries. The image address, row and limit
  (used only by the generator, at the load) come from the capture's arrays
  in bank 2. The build now places those arrays itself (`L1K_*` are equates,
  like `L1S_R`, so level 1's page code can name them), and adds `L1K_LIM`.
  This saved 372 bytes, plus 93 from dropping past-its-last-row (only the
  capture reads it).
- `L1Bottom` moved to bank 2; it calls `L1Zone` through `L1Call` (nesting is
  fine: L1Call keeps the caller's bank on the stack).
- `L1Part` is a piece of its own: no run fitted `L1Strip` + `L1Obj` +
  `L1Part` together.
- **Not possible:** the fixed bank (no 148-byte run left for a far piece);
  console RAM (only scraps). The title and story lists' RAM (`$2420-$25FF`)
  is idle in level 1, but other screens rebuild it, so it isn't used.

**The rails drew over the gate: MARIA ran out of time.** The gate's post
lost its fence rows (69-72): the rails and black showed where the old build
has the post. Its windows held the right bytes, and its objects were in the
list. Zone 0 (rows 65-72) had 20 objects: the sky and the rails each a
strip 20 bytes wide twice (160 bytes of DMA a line), the posts and the gate
(two objects each, one per zone part) and the overlay. MARIA's DMA for a
line ends before the list does. The gate's sky-row object (14th) was drawn
and its fence-row object (16th) wasn't.
- **Screen and DLL lines:** a MAME snapshot's row is the DLL line less 9.
  Zone 0 is DLL lines 113-120 and snapshot rows 104-111; I first read the
  rows as zone 1 (DLL 108-111 is the top's own 4-line zone).
- **Dead ends:**
  - **Bank 0 or 4 in the window** (the top zones read the selected bank's
    MARIA copy) was ruled out with `probes/tmp-bankwatch.lua`: neither is
    selected while `S_L1` is on.
  - **Dropping the sky strip** (it's the sky's colour) doesn't work: the
    background is the sky only for the top's lines (`NmiSkyOn`/`NmiSkyOff`).
    It is black from the band down, so the strip is what paints rows 65-68.
- **The fix, two parts:**
  - **Whole-zone parts:** a zone with more than one part (by background)
    gets one more, the whole zone (`WHOLE`). A shape whose parts there share
    a palette has one window there, one object instead of two. The windows
    already span the zone's lines (0 outside the part's rows), so the merged
    window is their OR, and the generator makes it in one pass with the
    entry's palette. Windows: 484 down to 461; cart RAM 7,608 bytes.
  - **The sky and the rails as one strip** (`L1_SKYRAILS`, flags bits 3 and
    4: the rails' image from its row, `$AA` from its limit to its row), used
    when both are on. With the whole-zone part it is one object per half.
  - Zone 0 is now 13 objects. Snapshots at flips 240, 315 and 400 match the
    old build's scenery pixel for pixel. What still differs: the status
    bar's arrows and a hit's spark, which are game timing.

**Speed.** The first build ran level 1 at about half the old build's
pace: about 5 flips per 100 frames against 10, so flip 400 never came in
a 5,200-frame run. `probes/tmp-prof.lua` samples the PC (and `S_BANK`)
every 130 µs of emulated time. Above `$8000` its symbol names are
bank-blind, so total by bank. Flips 220-260:

| | samples |
|---|---|
| old build (blitter; a fifth of it in the blitter) | 56,323 |
| first level-1 build | 101,699 (bank 3 emission 37%, bank 2 capture 17%) |
| now | 65,369 (bank 3 19,000; bank 2 4,600) |

- **Emission:** `L1Zone` ran `L1Obj` for every instance in every zone, and
  every zone twice (`BandWrite` counts, then writes). Each shape's zones
  (`L1S_ZA`, past the last `L1S_ZE`, bank 3) now let it skip an instance
  outside the zone with two compares.
- **Capture:** `L1Find` searched all 93 shapes for each draw. The shapes
  are now sorted by their image address's low byte (`inventory`), and
  `L1K_FIRST` (256 bytes, bank 2) gives the first with a given low byte.
- **Still open:**
  - About 16% slower than the old build. Most of it is the count pass: every
    zone's objects made twice.
  - The floor zones with the fighters are unchecked for MARIA's time (the
    floor strip is 40 bytes a line too).

**Probes added:**
- `tmp-zonedump.lua`: the shown DLL's zones and objects after flip `DUMPK`.
- `tmp-bankwatch.lua`: bank 0/4 selections during level 1.
- `tmp-prof.lua`: the PC sampler.

### Level 1: the cliffs broken; the background as a world of tiles (2026-10-09)
**What the user saw:** the cliffs completely broken. At the level's start the
rails run across where the cliff's face is, the floor's salmon covers its
stripes, and only a sliver of stripes is left. Akuma's cutscene is broken
the same way (the room's floor stripes missing, its walls cut, stray
gate-roof pieces at the top: the clean run forced onto this build,
`p7800-stateplay.lua`, flips 150-190).
- **The cause:** the cliff (and the cutscene room) are partial-width
  fills: solid rects and two-value striped patterns over byte columns
  (`l1cap`'s `F` lines; `l1model.fill`: rect = `v02` over columns c0 to c1−1;
  pat alternates `v02`/`v12` by row, the bottom row `v02`; `nofill` paints
  nothing). Level 1's emission keeps only full-width fills (as the sky
  and floor strips, flags) and drops partial ones, and the strips are full
  width. **The user:** "this is why tiles were recommended. it has to stop
  at the cliffs."

**Measured towards tiles** (scratchpad `l1tiles.py`, `l1wpix*.py`,
`l1world2/3.py`; the scripted log `work/analysis/l1capall`, the clean
run's `work/analysis/l1rec`):
- **Screen tiles don't work:** most scenery is blitted at sub-byte shifts
  (`$A684 $A68A $A6A6 $A6C0 $A6D4 $A6EF $A703 $A85F` at shifts 1/3/5/7;
  the column `$AB8E` at 0/2/4/6). It moves pixel by pixel with V, so
  byte-column tiles taken from the screen don't repeat.
- **A world image does:** each picture placed at world x = screen x − V
  (my first try used + V: wrong), per structure (`$4C`), with the game's
  clears and copies. Taken from the game's own buffers (`P` dumps), with
  the posts' and mountain's rectangles masked:

  | world | V | columns | 4-pixel tiles | 8-pixel tiles |
  |---|---|---|---|---|
  | structure 0 (cliff, fences) | 0-1019 | 295 | 117 | 109 |
  | structure 1 (the gate) | 108-260 | 78 | 68 | 61 |
  | the cutscene room (pictures 143-199) | 108 | 66 | 129 | 115 |

  The world pixels that differ between pictures are things that aren't
  background:
  - fighters drawn into the bitmap (falling guards, Akuma);
  - the fills' byte rounding (the game rounds world x to byte columns, a
    spread of up to 4 pixels: the cliff's sky rect ends at world 873-876);
  - the fighter-box erases at columns 28-40 (each row's own colour);
  - in the sky rows, the cutscene (the user: the background goes black
    there).
- **Not world-fixed:** the fence posts (their phase differs between runs)
  and the mountain's base (fixed on screen). They stay objects.
- **MARIA's time** (`scratchpad/dmacost.py` on `tmp-zonedump.lua` dumps:
  4-byte header 8 cycles, 5-byte 10, each direct byte 3, an indirect
  character 3 + 3 a byte):
  - The old build's band zones cost at most 187 a line.
  - The current build's fence zones cost 300-440.
  - MAME dropped the gate's object near 426-440.
  - A full tile row: 1-byte characters (41 for fine scroll) about 276;
    2-byte (21) about 209.
- **Banks in the window during level 1:** 1, 2, 3, 5, 6 (`tmp-bankcount.lua`:
  bank 0 and bank 4 never). `tmp-bankwatch.lua`'s empty log was right, but
  its `scr:vpos()` would have failed silently had anything matched (this
  MAME has no `vpos`); fixed.

**Proposed** (the Midnight Mutants way):
- **The background as one world map per world:** structure 0, structure 1
  and the cutscene room. Two-byte characters, at most 128 a world;
  `CHBASE` per world.
- **Map and characters in MARIA ROM,** at the same address in banks 1, 2,
  3, 5 and 6's MARIA halves. No cart RAM, no console RAM.
- **The build renders the worlds** from the ROM's images and a committed
  placement list (image, world x, row; fills in world coordinates), as
  `l1shapes.txt` is.
- **The scroll is in the headers alone:** each zone's two indirect headers
  get the map pointer (V's coarse part) and hpos (its fine part, 0 to −7).
- **Objects stay** for the posts, the mountain's base, fighters, bodies,
  Akuma and stars. Their world-fixed draws and the fills are no longer
  captured (a fill still unplaces the posts it covers).
- **Open, the rules:** level 1's band lists are in cart RAM (`$7310-$7A`),
  against "display lists only in console RAM". This was there before level
  1's work too (top lists `$4F10`, band lists).

### MAME with the a7800 fork's MARIA timing; level 1's DMA re-measured (2026-10-09)
**The tools:**
- The user updated the private MAME repo (`Miasmark/mame-a7800-bankset`
  90d0a5f, `bankset-full.patch`) and the toolkit (`tools/dmameasure.py`,
  `dmabudget.py --timing fork`). The toolkit's change is on PR branch
  `ccr-c6905fcd-xag9tq` until its self-test finishes; used from a worktree,
  not merged.
- The full patch is for MAME master (0.289 development) and has no `$2006`
  (shared RAM) form, which this cart uses. So only its MARIA timing was
  ported by hand into our 0.287 tree:
  - DMA limit 430 (was 426);
  - 3 clocks for the first hole in a header;
  - 8 clocks of last-line shutdown (was 6);
  - the line buffer cleared at each line's start;
  - each line shown a pixel at a time from the buffer the last DMA filled
    (a mid-line register write shows mid-line).
- `a78.exe` has it; the exe before is kept as
  `mame-src/a78-0287-bs-oldtiming.exe`.
- **Checked:** `dmameasure.py` matches the fork's model (holey zones 2,271 vs
  the model's 2,275, old 1,892; with DLIs 8,101 vs 8,105). The stable-path
  cart's pictures at flips 30, 240, 315 and 400 are identical under both
  timings: our background-colour switches land in opaque lines.

**Level 1's lines against the limit** (`scratchpad/dmacost.py`, now MAME's
own rules: DMA from 16 clocks to 430, so 414 for a line's objects; the zone
dump now covers the whole DLL):

| | worst band zones |
|---|---|
| old build, flip 315 | 265 (floor, 8 objects), 234, 223 |
| current build, flip 315 | 370 (rows 73-77, 15 objects), 315, 266 (floor) |
| current build, flip 400 | **458: rows 73-77, objects 16-17 lost** (the gate's off-screen parts), 329, 301 (floor) |

**What it means for tiles:**
- A full tile row costs:
  - 1-byte characters, 41 with the fine scroll: 2 × 10 + 41 × 6 = 266.
  - 2-byte characters, 21: 2 × 10 + 21 × 9 = 209.
- The floor's strips cost 136 today, so a floor zone with the fighters goes
  from about 301 to 431 with 1-byte characters (over) and to about 374
  with 2-byte ones.
- The fence zones drop to about 209 + posts + the mountain's base (≈ 320),
  since the gate, torii and cliff leave the object lists.
- **Two-byte characters, then.**

### Level 1's background as tiles: built (2026-10-09)
**The user's direction:**
- tiles (character mode) for the background, so it stops at the cliffs;
- two-byte characters everywhere;
- display lists out of cart RAM as soon as possible.

**The worlds** (`probes/l1worldlist.py` → `port/l1world.txt`;
`port/l1world7800.py`).
- **Four worlds:**
  - structure 0 before the cutscene ("0");
  - structure 0 after it ("0b": the game's `$30`, console `$00E9`, is 1 from
    the cutscene on; the gate there is mirrored at world −32 where it stood
    normal at +28);
  - structure 1 ("1");
  - the cutscene's room ("c": screen-fixed).
- **A buffer's world follows what the game draws into it,** which the
  6502 can follow too:
  - the rails' blit (`$AA11`, every level view) sets it from `$4C`/`$30`;
  - the room's floor fill (a pattern over rows 118-145) sets the room;
  - a clear unsets it (nothing shown until a marker);
  - a copy copies it.
  - At every flip a level world follows `$4C`/`$30` though no rails are
    drawn: a later structure-1 visit kept "0b" without this.
  - `$1A0B` (the game's mode: 2 in the cutscene) was a picture late at the
    cutscene's start and still 2 for the level's first pictures after it,
    so it isn't used.
- **The list:** each world's draws in the order of their last occurrence.
  - Blits and column stacks of the scene page's images.
  - Art-bank images only where one holds its place 20+ pictures (the room's
    walls; Akuma's poses come and go).
  - Fills that paint something other than their rows' background.
  - A blit seen in one picture only is animation: the player's climb at the
    start, `$A3C5-$A5DC` (not the rocks I named them before).
  - The rails are also the worlds' rows 69-76 background.
  - Pictures of level 1 only (`$D0` 1): the capture's last picture is level
    2's.
- **Objects, not tiles:**
  - the posts (`$AA23`, `$AA31`, phase per run);
  - the mountain's base (`$A9B8`, `$A9E2`) and the mountain's edge over the
    cliff (`$AB4A`, drawn at the screen's left: screen-fixed; the user: "a
    small portion of the background mountain"), with its AND mask `$AB94`
    after it;
  - Akuma, the climb.
- **Checked against the world images from the game's own pictures**
  (scratchpad `l1wcheck.py`): "0" 0 of 18,556 pixels differ, "0b" 80 of
  82,804 (row 76), "1" 0, "c" 20.

**The tiles:**
- **Two-byte characters, 8 pixels.** 112 characters for all four worlds:
  an index a shorter zone's tile shares with a taller one whose lines from
  the bottom up begin the same (zones of any height read the same line
  pages).
- **Cart RAM** (MARIA's pseudo-ROM, written once at the load, never read):
  - the characters at CHBASE `$64`, line pages `$64-$6D`, each a prefix
    (indices tallest first);
  - first at `$58` (pages `$58-$61`). `tmp-fgwrites.lua` found the front
    boxes' tables (`FtEmitFg`) writing the heads of pages `$5F-$62` in
    level 1, inside those pages, so they moved to `$64`. In level 1 the
    only writes to `$64-$6D` now are the load's (`L1TPut`) and the
    generator's into its windows, in the upper line pages' unused tails
    (`L1GenLK3`, `L1GenZ1`);
  - 48 map rows (2,881 bytes) packed with the objects' 143 windows;
  - 7,417 bytes in all.
- **The load:** a stream (literal and repeat runs, new addresses) in
  pieces in banks 3, 5, 6 and 2 (`L1TSP`), expanded by `L1TLoad` (level
  1's page) through `L1Fetch`. Checked byte for byte in MAME (7,417 bytes).
- **The build is reproducible:** the map rows are placed in a fixed order
  (two builds identical; a set's order had varied between runs).
- **Each zone's list opens with one indirect 5-byte header:** 21
  characters from the view's column, hpos its fine part (0 to −7), K − V
  (the room: K).
  - Trimmed to the row's first and last non-blank columns (`L1T_FB/LB`).
  - Where the view's are all blank, a 160A placeholder off the screen's
    right.
  - So every list starts in 160A and none needs the 160A header at its end
    after 160B parts.
- **CTRL bit 4** (two-byte characters) is set in level 1's lists' DLT
  entries; CHBASE is written at every flip. While S_L1 is on no list uses
  the title's CHBASE table (`FrameChT`).

**The capture:**
- The world's draws aren't instances: the inventory keeps 32 object shapes
  (`l1scene7800.inventory`: the world list's images left out).
- **A fill unplaces an object whose middle it covers** (middle row and
  column).
  - Removing any object a fill touched lost the mountain's edge under the
    cliff's sky.
  - Removing only fully covered ones left figures in the cutscene's room.

**Level 1's lists in console RAM** (the user's rule). Each buffer's band
lists go in its pieces, first fit, a pointer a piece (`L1_SGP`), back to
the list's real end once written. The pieces:
- the title and story's list RAM (`$2410-$24BF`, `$2510-$25FF`: past the
  row lists' 10 bytes);
- L1RAM past its variables (the fast fill's RAM to `$277F`: 60/40);
- the DLL pages' tails past the bottom lists (`$22D7`, `$23D7`);
- A's `$1B4E-$1B7F`, `$1852-$187F`, `$1F00-$1F17`;
- B's `$1F46-$1F77`, `$1E85-$1EB1` (the column routine's and fast fill's
  scratch: level 1 captures those), `$27E7-$27FF`;
- then cart RAM's old area while console RAM is short (kept as a safety
  net).

All measured unused while level 1 runs: `p7800-ramuse.lua` over the clean
run and every scene. `$2040-$20FF` and `$2140-$21FF` only look free: they
mirror the zero page and stack.
- **The bottom lists** (rows 135-144, 145): 16 bytes a zone in the DLL
  tails (`$22B7`, `$23B7`), written as the DLL is built and at the flip.
  - Scene 6 builds its DLL after the flip: its bottom rows were black.
  - `S_SLOT` is a column number for B, not 1: the buffer number was wrong.
- The DLL builder resets the pieces too (`BuildL1Seg`): a leak filled cart
  RAM at every DLL rebuild before.
- **The generator's scratch overlays the pieces** (load only). 24 instance
  slots (the clean run's most: 17).
- **Checked (`tmp-dllcart.lua`, every frame of the clean run forced onto
  the build):** 3,869 level-1 frames, no band or bottom zone's list in cart
  RAM.

**Pictures** (content-matched: each new frame against its best old match
in the same window, `bestmatch.py`, since builds show picture n a frame
apart):
- the cliff 0-2 pixels; the rest of level 1 150-760 (fighters a step
  apart, the status bar);
- the ~9,000-pixel frames were not the hit flash, as I first wrote. They
  are each window's first frame, with palette 1's band colours at the
  screen's top (the sky rows grey) and, before the stripe fix below, under
  the split too. Since that fix they are about 2,000 pixels (the sky rows
  64-68). No frame of the scripted run shows the grey sky (3,258 level-1
  frames, the old, kept and new builds): it comes from the replay, which
  forces the state at the window's start;
- scene 6: 24 pixels (the gate's edge);
- the scripted run's snapshots: 0-2 pixels in the background.

**Speed:** 606 flips by frame 5,600 against the old build's 535 (13%
faster). MARIA's band lines cost 76-351 clocks (trimmed tiles).

**MAME timing:** the fork's MARIA timing hand-ported into 0.287 (DMA limit
430, first-hole 3, shutdown 8, per-pixel display). `dmameasure.py` agrees.
The user's recording plays only on the old exe (`a78-0287-bs-oldtiming.exe`):
its input timing.

**Open:**
- **The cutscene:** the guard who enters through the room's left door
  isn't hidden by its frame. The old build hid him with front boxes; here
  the door's pieces (`$964A`, `$96CE` mirrored) would need to be objects
  after the fighters (a "front" pass, ~100 list bytes).
- **The cliff:** two pixel columns at the screen's left in the sky rows.
  (The stripe row, row 82, was not "a few pixels off": see "Level 1: the
  stripe row's colour".)
- **Level 1 still reads cart RAM:**
  - the top pieces' tables (`TOPL*`, page `$57`: 178K reads; `TopDel`);
  - the top lists (`TOPDL`, `$4F10-$540F`);
  - the fighters' tables (`FS_I` `$7B00`, `FO_HB` `$4E`; `FtSort`,
    `BandWrite`).
- **Every other scene's lists are in cart RAM**
  (`probes/p7800-dlwhere.lua`): the top zones (lines 48-127) everywhere;
  the band in levels 2-4, the title and the ending (198-282 bytes a
  frame).

**Probes added:**
- `p7800-ramuse.lua` (console RAM per scene, MARIA's reads told apart);
- `l1worldlist.py`; `tmp-cartread.lua` (ONLYL1);
- `tmp-l1world.lua`, `tmp-l1n.lua`, `tmp-dllcart.lua`, `tmp-palflip.lua`,
  `tmp-snapframes.lua`, `tmp-chbase.lua`, `tmp-memdump.lua`;
- `p7800-dlwhere.lua` (every scene's lists by place);
- `tmp-zonedump.lua` (`NOPLAYKEY` mode).
- The replay's tap ignores a companion's own reads (`_G.PROBE_PEEK`).

**Checkpoint:** `2026-10-09_KEEP_enh-l1-tiles` (CHBASE `$58`, the stripe
row's fault), then `2026-10-09_KEEP_enh-l1-tiles-pal5` (both fixed). The pre-L1 reference
carts are in `work/ref-preL1/`; `work/karateka7800-invincible-easy.a78` is
now this build's.

### Level 1: the stripe row's colour (2026-10-09)
**The fault:** the cliff's first stripe line (row 82) sometimes showed in
the sky's colour, as the snapshots' "row 82 a few pixels off" (56 and 86
pixels).
- Per frame (`probes/tmp-striperow.lua`: the screen's pixel at the first
  stripe line against the next), the tile build had it in **955 of 1,647**
  frames where both lines are drawn. The old build had it in none (1,539),
  and the CHBASE move changed nothing.

**The cause:**
- The band's colours come from the game's third DLI (its count, `$0F14`,
  at 2). The DLI is on zone (78,1).
- The colour routine (`$1125`/`$1148`, the port's `G_L1148` and
  `ColTail`) waits for a line end, then writes `$28`, `$27`, `$26`, `$25`
  (each the set's value less the fade).
- Only colour 2 changes there: `$9A`, the sky, to `$88`, the stripes (`$08`
  in some views).
- **All the tiles were palette 1,** above the split and below it. So the
  change had one line to land in: row 81, all black.
- `probes/tmp-midwrites.lua` (MARIA register writes by line, estimated
  from emulated time):
  - in the tile build `$26` lands one or two lines later than in the old
    build (estimated 159-160 against 157-159);
  - the tile zones' lines cost MARIA more (indirect characters, 9 cycles
    each), so the CPU is halted longer between the line end and the writes.
- Moving the DLI up a line would put the change on the sky's last row.

**The fix: palette 5 below the split.**
- The tile zones from row 81 on (`L1_PALROW`; zone `L1_PALZ`, 4, and the
  bottom zones) use palette 5 (`L1_PAL`). No list of level 1 used palettes
  5-7 (`tmp-dlldump.lua`'s palette census, frames 700-5,500).
- `ColTail` copies the band's set into palette 5 as well (colours 1-3, the
  same values less the fade), in level 1 at the third DLI only.
- Palette 5 now holds the band's colours from the frame's top, so the
  split's timing no longer reaches the tiles.
- What is left: on a frame where the band's colours change (a fade), rows
  82 to about 84 show the previous frame's for that frame. Everything else
  below the split (fighters, objects) is still palette 1, timed as in the
  old build.

**Checked:**
- the stripe row: **0** of 1,669 frames (it was 955);
- the scripted snapshots against the old build: frames 4 and 5 now 0;
- scene 6 unchanged (24 pixels, the gate's edge);
- the replay: no band or bottom list in cart RAM (3,906 level-1 frames);
  content match 150-750 pixels, and the windows' first frames ~2,000
  instead of ~9,000 (see the correction above).
- `work/karateka7800.a78` and the invincible-easy test cart rebuilt;
  checkpoint `2026-10-09_KEEP_enh-l1-tiles-pal5`.

**Probes added:** `tmp-midwrites.lua` (`FINE`, `VAL`), `tmp-dlldump.lua`
(the DLL and the palettes its lists use), `tmp-striperow.lua` (a pixel
against the one 2 lines down, or `PCOL`: frames where it is a colour; the
screen's y is the snapshots' + 27). `tmp-fgwrites.lua` takes `FGALL` (any
byte of the pages, not just their heads).

### Stage D, level 1: what is still in cart RAM, and console RAM's room (2026-10-10)
**The lists** (`p7800-dlwhere.lua`, `tmp-listmix.lua`, `tmp-topsize.lua`;
the scripted run, the replay and scene 6):
- The band and bottom zones' lists are all in console RAM (since "Level
  1's background as tiles: built").
- **The top zones** (lines 48-112, rows 0-64) are still in cart RAM, in
  `TOPDL`'s 60-byte slots: at most 112-132 bytes a buffer at once (the
  scripted run, the replay), 76 in scene 6. Per zone at most 26 bytes
  (lines 93, 100, 112 and 86 h14); several of the zone layouts' zones are
  always empty (2 bytes).
- Lines 243 (`$605B`, cart RAM) and 253 (`$FD00`, ROM) at the screen's
  bottom.
- **The band at its most** (367 bytes, one buffer): tiles' headers 90, the
  fighters' objects from MARIA's ROM 177 (28 4-byte, 13 5-byte), level 1's
  objects from cart RAM's windows 64, ends 36.
- The mode-8 rows (lines 24-47) are 24 one-line DLL entries, all the empty
  list in level 1 at the frames looked at: 72 bytes of each DLL.

**Console RAM in level 1 is full at its peak** (`tmp-l1seg.lua`, the
replay): buffer B's pieces used 240/240, 88/89, 38/41, 46/50, 42/45 (421
of 490 bytes at once). A fresh census on this build (`p7800-ramuse.lua`:
the scripted run, the replay, scene 6) leaves 263 bytes untouched outside
the pieces in runs of 8 or more: `$2782-$27CC` 75, `$1EB6-$1EE5` 48,
`$1A57-$1A7F` 41, `$24D0-$24E0` 17, `$210F-$211F` 17, `$1812-$181F` 14,
`$2135-$213F` 11, `$1DF6-$1DFF` 10, `$1F1E-$1F27` 10, `$24F6-$24FF` 10,
`$1B44-$1B4B` 8. Both buffers' top lists need about 264 at their peaks:
not enough with any slack, and fixed slots in order (any zone up to 26)
would need about 480.

**The CPU still reads cart RAM in level 1** (`tmp-cartread.lua`, now
leaving out indexed stores' dummy reads, and `crsum.py` by routine):
- page `$57` (the top pieces' tables `TOPL*`, `TOPLD`): `TopDel1` 63K,
  `TopEBox`, `TopEmit*`, `TopCapCover`, `TopRef1`, `TopCover`;
- page `$7B` (`FS_I` and its neighbours): `BandWO1`, `FtSort3`,
  `FtPlaceC`, `BandW0`, `BandWX1`, `ColTK0`, `L1GenS`, `L1Gen`,
  `TsBlanks1`;
- `$4E` (`FO_HB`): `BandWO1`, `BandWO5`;
- `$63`: `BlitBank` 15K, `FtEmit*`, `StarBlit`;
- `$40`: the game's own code (`G_L258D`, 13K);
- `$5B-$5E` heads (the front boxes' tables): `FtEmitFg` 13K;
- `$4F-$53` (the top slots' zone bytes): `TopRefSlot`.
- Before the dummy reads were left out, the indexed stores (`STA (zp),Y`,
  `STA abs,X`) doubled some counts and showed the load's writes as reads.

**Ways on** (not chosen yet):
- the top lists into the 263 bytes, packed, with the cart slot as a
  safety net as the band has: most frames, not all;
- level 1's DLL without the mode-8 rows' one-line entries while they are
  empty: about 63 bytes a buffer, next to the bottom lists;
- level 1's top rows as tile worlds too (about 7 bytes a zone): needs
  characters beyond the 128 a two-byte set holds (a second CHBASE for the
  top) and cart RAM or MARIA ROM for them;
- the CPU's tables need console RAM that isn't there. BankSet's own RAM
  (separate RAM per side) would give the CPU 16K of its own at
  `$4000-$7FFF`; whether the target hardware has it is the user's call.

**Probes added:** `tmp-l1seg.lua` (the pieces' most use; the A figures
mix frames: `L1_SG` changes before the pointers), `tmp-listmix.lua`,
`tmp-topsize.lua`; `tmp-cartread.lua` writes `pp` lines (pc, page).

### The BankSet rules in MAME; one-line zones; the blitter out of cart RAM (2026-10-10)
**The user's rules** (2026-10-10): no display lists and no code in cart
RAM; CPU data may go there for now. The spec's bank-RAM form (`$6002`) is
32K: the CPU's own 16K at `$4000-$7FFF` (MARIA never sees it) and MARIA's
16K, written by the CPU through `$C000-$FFFF` (the CPU can't read it). So
the target is that form, and the shared `$2006` form our carts use now
goes.

**The emulator:** the private repo's `bankset-full.patch` (8afcd93, for
MAME master) refuses display lists fetched from bank RAM (they read 0) and
opcodes fetched from it (they read `$FF`), one warning each. Hand-ported
into the 0.287 tree by `port/mame/mame_bsrules.py` (MARIA's header and DLL
reads through `read_dl`, the graphics' and the indirect maps' untouched; a
read handler on `$4000-$7FFF` for the CPU's SYNC fetches), for our `$6002`
and `$2006` forms. `a78.exe` has it; `a78-0287-bs-norules.exe` is the one
before.
- **Every scene breaks the rules at once** (the load: a list read at
  `$7C01`, code at `$7C0F`), and with them every run stops at the boot
  (`flips 0`, PC `$800C`).

**One-line DLL entries:**
- The mode-8 rows (lines 24-47) were a zone a line, all the empty list
  (the user: they are the background colour).
- `PutEntry` now merges an empty, unflagged line or run into the empty
  zone before it, up to 16 lines (`S_MRG`, from the unused `S_PM8`). A
  flagged line still starts its zone: MARIA raises a zone's DLI as the
  zone starts, so the DLIs keep their lines.
- The blank and mode-8 paths only; the sky's opaque black line isn't
  extended.
- Level 1's lines 0-47: 28 entries down to 6; the scripted snapshots
  identical (9 of 9).
- **Still one line:** the DLIs' zones (23 the sky-on line, 85, 112 the
  sky-off row, 126 the band's colours, 137, 165, 193 the status bar's) and
  line 47 (the merge's leftover).
- **Correction:** my "lists at lines 243-271 in cart RAM and ROM" weren't
  real. The DLL ends at line 243 (`DLL_LINES`); the probes walked on past
  it.

**Code in cart RAM** (`probes/tmp-cartexec.lua`, every scene):
- Only engine part 2's module B (the blitters, the original's
  `$2800-$2BFF`), at `$7C00`, copied there at each scene load.
- Level 1 runs only its entry stubs there: the jump table, the header's
  prologue (`SysBlitBank`: the capture) and the epilogue.
- The other scenes run all of it.
- The fast fill (`;;; RAMFILL`) is in console RAM (`$2600`); the comment
  saying `$7203` is stale.

**Its self-modification** (`probes/tmp-selfmod.lua`): 14 stores, 7 in
each blitter's set-up:
- the combine opcode (`ORA`/`AND`/`NOP NOP` before `STA ($14),Y`, by the
  mode `$0F`);
- the shift routine's `JSR` operands (by the shift `$10`, from the
  tables at `$298D`/`$2991`).

A ROM form is written (`;;; FAR (BlRom)`, the `$289B-$2B19` replacements
in `layout7800.py`, `SysBlSetup`/`SysBlSh`/`SysBlLoopN`/`SysBlLoopM`):
- the set-up keeps the shift routine's address in `BL_SHV` and the mode in
  `BL_MODE` (CPU data in cart RAM, `$7C00`);
- the shifts are `JMP (BL_SHV)`;
- each inner loop is one of three, by the mode: about 5 cycles a byte
  more.

**It doesn't fit:** the fixed bank was at 15,895 of 16,384. The module
(about 830 bytes live) and the loops (210) leave it about 600 over; the
far pieces that lived in the gap it takes have nowhere to go. The
CPU-side banks have 7.6K free in all (bank 0 2,913, 4 1,678, 5 1,253; the
others under 540).
- **Can't go to a bank:**
  - **Sound (module A):** reads its song data through pointers into the
    scene page (`tmp-winreads.lua`: 13 sites).
  - **Module C:** the game's flow and scene loader; it calls common code
    in the window.
  - **The blitter itself:** it reads its sources through the window.
- **Could go to bank 5 behind stubs:** the fills (`$2C00-$2DFF`, about 484
  bytes; entries `$2CC0`, `$2CC3`, `$2CCD`, `$2D03`, `$2D46`), but they
  call level 1's page code through `SysL1Fill`: about 380 net.
- The TIA translation (`TiaSound`, art bank) is about 300 bytes.
- **Console RAM** in scenes 2-4 has 1.6K free, in pieces of 265 at most.

**Probes added:** `tmp-cartexec.lua`, `tmp-selfmod.lua`, `tmp-winreads.lua`,
`tmp-dlldump.lua`; scratchpad `dismem.py`, `modrefs.py` (the linker's
references into a range from outside it). `xesource.py`'s "labels inside
the override" error now names the referencing addresses.

### The blitter in the fixed bank; levels 2-4 hung since the tiles (2026-10-10)
**The blitters' module in ROM** (the user chose the fixed bank over a
console-RAM copy or removing the blitter first):
- **Module B** (the original's `$2800-$2BFF`) is region `engine2` at
  `$EE00-$F1FF`, fixed.
- **Its self-modification,** replaced through `layout7800.replacements`:
  - each blitter's set-up becomes `JSR SysBlSetup`, which keeps the shift
    routine's address in `BL_SHV` and the mode in `BL_MODE` (CPU data in
    cart RAM, `$7C00`);
  - the first byte's shift is `JSR SysBlSh` (`JMP (BL_SHV)`);
  - the normal blitter's inner loop is one of three by the mode
    (`SysBlLoopN`: about 5 cycles a byte more, the indirect jump);
  - the mirrored one's is one loop testing the mode with `BIT`
    (`SysBlLoopM`: about 8 more; it is the rarer one).
- **The engine regions are kept at their size** (the linker maps their
  addresses linearly), so the replacements stay padded. Their NOP tails go
  back to the fixed bank's far pieces (`ENGINE2_PAD_RELEASE`); the set-ups
  jump past them (`EXTRA_LABELS`: `$28CA`, `$2A9C` labelled, through
  `emit_range`'s `extra_labels`).
- **Room made in the fixed bank** (it had 489 bytes free; the module needed
  1,024 and the loops about 150 more):
  - **Into the top bank (bank 5):**
    - `TopSky` and `TopEmitF`, the builder's own, with no stub;
    - `FRec` (`FRecF`: `TopArtCall`, then X and A as it leaves them) and
      `Reset`'s body (`ResetB`, entered by `JMP`: the clear wipes the stack
      page; `ResetTail`, fixed, turns MARIA's DMA on and loads the
      scene).
    - `FtBlack` went there too, then back (a bisection; it fits fixed).
  - **Level 1's part tables** (`L1QTAB`) into bank 3: only its code there
    reads them.
  - **The mirrored blitter's byte table** (`$2BC0-$2CBF`, read only from
    its copy at `$F500`): the original's 256 bytes given back.
    `FIXED_RELEASE` now passes a sprite copy's source, and releases by the
    region's own placing. The resolver sends a copied range to its copy:
    the first try released the live copy at `$F500`.
  - **Far pieces split** where no branch crosses (`FtFixed2b`, `FtStars`,
    `StarM1`, `StarS`, `FtEnds`, `FgStubs`, `BlRomN`, `BlRomM`; `StarM`'s
    branch into `StarM1` a jump), to fit the runs left.
  - The fixed bank is at 16,022 of 16,384.
- **`BlitBankL1`** (level 1's blit kind) compared the returns with the
  module's old pages (`CMP #$7C`, `#$7D`, `#$84`). It now uses
  `TOP_RETA`, `BL_RETAR`, `TOP_RETM`, and the build checks the pages
  stay apart.
- `RowBase`'s and `FgRec`'s caller tests (by the return's page, from
  `G_L2800`, `E2_BPAGES` pages) still hold: only the blitters, the fills
  and the common code's two calls call `RowBase`. Far pieces now sit in
  the module's pages, and none of them does.
- **Checked:**
  - the rules' MAME: no code fetched from cart RAM in any scene;
  - a test build with the old self-modifying module in cart RAM,
    everything else the same (a copy of the project,
    `karateka-enh-bltest`): level 2's 601 pictures identical to this
    build's.
- **Probes added:** `tmp-whojumps.lua` (the first opcode fetch in a
  range). ROM opcode fetches don't reach Lua's read taps (MAME's opcode
  cache), so its ROM ring stays empty. `tmp-stackrun.lua` (the stack's
  return addresses when SP runs low, after the BIOS's frames).

**Levels 2-4 hung in the tile builds** (both `KEEP_enh-l1-tiles` and
`KEEP_enh-l1-tiles-pal5`; the test cart given for the hardware run):
- **The cause:** `BuildL1Seg` wrote `L1_SG` before checking `S_L1`.
  `L1RAM` (`$2600`) is the fast fill's code in every other scene;
  `L1_SG`, `$2611`, is `STY FILL_BLK+2`'s operand. Every DLL build made
  it `STY $2700` or `$2708`, and the fill wrote over its own code.
- **Seen as:** the scripted runs of scenes 2-4 stuck at flip 192, PC
  `$2700`. I took that for the player dying, until scene 4 crashed (a
  stack runaway through the fill's passes, `tmp-stackrun.lua`).
- **Found:** the RAM's copy against its image in bank 5, then the writers
  of `$2600-$277F` (`tmp-selfmod.lua LO=2600`): only `$9060`, the
  builder's `BuildL1Seg`.
- **Fixed:** `S_L1` first. Now nothing but the load's copy writes there
  outside level 1 (scenes 2 and 4 checked).

**The pictures** (`checkdl.sh`'s runs, the kit; scratchpad
`scenecheck.sh`):
- levels 1 and 6 against `pal5`: identical (601 and 176);
- scenes 0, 2-4 against the pre-tiles build (`work/ref-preL1`): none over
  300 pixels. Under it: scene 4 0 of 176, scene 3 2 of 601, scene 0 12 of
  800, scene 2 328 of 601 (6-150 pixels, one line, mostly y166: a floor
  stripe line under a fighter's feet that the pre-tiles build shows black
  and this one draws).
- The same with the old blitter and without the DLL merge. So it comes
  from the tiles work, which nobody could check in scene 2 (it hung).
  **Open:** which change, and which picture is the original's.

**Checkpoint:** `2026-10-10_KEEP_enh-blitrom` (`pal5` hangs in levels 2-4;
the earlier ones are kept).

### Zones on the 8-line grid where nothing needs a line of its own (2026-10-10)
**Why** (the user): MARIA loses 8 cycles at the end of every zone, drawn or
not. So zones are 8 or 16 lines unless a specific use needs otherwise:
24 one-line zones cost 192 cycles a frame where 2 cost 16.

**Done:**
- **The merge** (`PutEntry`, `S_MRG`) now fills the zone before up to 16
  lines and starts a new entry with the rest, instead of starting afresh
  when the two don't fit together. A flagged blank line now takes the 15
  lines after it.
  - **Slip on the way:** I first had it shorten `S_H`, but the callers
    count `S_H` off their own line counts after `PutEntry`, so the lines
    were counted twice and the title never got past flip 2. Only the new
    entry's OFFSET changes now.
- **`space_dlis`:**
  - a music DLI (not the colour ones, `COLOUR_DLIS`) on an empty line moves
    on to the next line that is a multiple of 8, when the lines up to it
    are empty too, `DLI_GAP` above a colour DLI and 4 lines from any other
    (level 1's line 31: line 47 was a zone of its own);
  - empty runs of one kind back to back are joined (`DESCBUF` holds 64
    bytes; a split had made scene 3's 67).
- **The DLLs** (live, in play):

  | Scene | Before today | Now |
  |---|---|---|
  | level 1 | 61 | 37 |
  | 6 | 61 | 37 |
  | 4 | 43 | 32 |
  | 3 | 42 | 33 |
  | 2 | 41 | 35 |
  | 0 | 32 | 30 |

  In level 1 that is 24 zone ends, 192 cycles a frame.
- **Checked:** every scene's pictures identical to the build before (2,955).

**Still one line** (6-9 a scene), all at DLIs or beside them:
- the sky-on line (23) and sky-off row (112), the port's: their objects
  hide the colour switch;
- the band's colour DLI (row 78) and the status bar's (row 145);
- the music DLIs in the top (line 85) and the band (rows 89, 117), and
  rows 116 and 118 beside the last.

The band's flagged row is a zone of its own because `BuildRowsZone` makes
it one (the XE's DLI is on a run's last row). It could start a zone that
carries the rows after it (the DLI comes as the zone starts), and the
music DLIs could go to zone boundaries. That means the zone builder, its
Python twin (`buffer_zones`), level 1's `ZONES` and the fighters' cell
grid: not done yet.

### Levels 2-4's lists in console RAM; the debugger for scripts (2026-10-10)
**The band lists (levels 2-4):**
- Level 1's first-fit allocator (`BandWL1`) serves them too, with pieces of
  their own (`BMSEG_A/B`; `L1SG_*` rows 16 and 24): A `$2414-$24E0`,
  `$2280-$22FF`, `$1852-$187F`, `$1B4E-$1B7F`; B `$2514-$25FF`,
  `$2380-$23FF`, `$1E81-$1EAA`.
- These are the census's free runs in scenes 2-4 (`p7800-ramuse.lua`, the
  kit), less the glyphs' block, the static lists at `$2780` and the DLL
  pages' first `$80`.
- `S_BLPC` (the unused `S_PIDX`, set in `L1Load`) picks the pieces: `$00`
  level 1's, `$10` levels 2-4's, `$FF` none (scene 0: its console RAM is
  all in use, so the old cart RAM heads stay there).
- The allocator's 17 bytes moved out of `L1RAM` (the fast fill's code in
  the other scenes) to `$210F-$211F`.
- **Checked:** about 17,500 frames a level, band lists in cart RAM in 4
  (the scene's start).
- **Correction:** levels 2-4 now match the pre-tiles build exactly
  (1,378 pictures). The 328 small floor-stripe differences in level 2 came
  from the cart-RAM band path (its "already there" shortcut or the page
  heads), which the pieces path doesn't use. So the pre-tiles pictures were
  right.

**The top lists:**
- **How:**
  - each zone's list is still built in its 60-byte slot (CPU data now),
    then copied into the buffer's top pieces (`TPSEG_A/B`, first fit,
    `TpCp`; levels 2-4: A `$1900-$1983`, `$1A4E-$1A7F`, `$182B-$184D`;
    B `$1984-$1A08`, `$1F46-$1F77`, `$1F00-$1F17`);
  - an empty list is `DL_EMPTY`;
  - the DLL entry's address is kept, as the DLL is built, in `TP_DLL` by
    the slot's ordinal (`TP_SO`), so `TopRefresh` can point the entry at
    the new copy;
  - the pieces start afresh with every full write of a buffer's top;
  - no room: the slot's (level 1 has no top pieces yet).
- **Three bugs on the way:**
  - **The DLL address in the slot's last bytes** cost a zone its
    fourteenth object: level 3's roof lost pixels. It went to a table of
    its own.
  - **`TopCopy` was already a label** (the top's part of the buffer copy,
    with `TopCopy1-3`). Pieces are assembled apart, so the clash went
    unnoticed. The buffer copy's stub reached the new routine, which copied
    over the DLL with the builder's pointers: an extra DLI, 10 NMIs a frame
    and the game stuck at flip 397. Renamed `TpCp`, and **the build now
    stops on any label defined twice** across the main block and the
    pieces (tested with a planted duplicate).
  - **Stale slots:** a buffer's slots from an earlier DLL build (another top
    layout) were still refreshed. With the DLL patches, they wrote their
    lists over entries that now belonged to other zones. A DLL build now
    marks all its slots unused first (`TopSlotsOff`), and a failed fit
    points the entry back at the slot.
- **Checked:** every scene's pictures identical to the build before (2,955);
  the top lists of levels 2-4 in console RAM (at most 20 bytes left in cart
  RAM, at the scene's start).
- Found with `tmp-dllwrite.lua` (the first write into a DLL range, with the
  state), `tmp-dllpatch.lua` (`TopRefresh`'s DLL patches), `tmp-toplist.lua`
  (the top zones' list bytes), `tmp-nmicount.lua` (NMIs a frame).
- **A probe pitfall:** a PC in `$8000-$BFFF` names a routine only with its
  bank; the symbol lookup gave `TopCopyC` for another bank's code once.

**MAME** (the private repo's 1a7dc35, 6daa5d9, ported into 0.287 by
`port/mame/mame_bsrules.py`):
- display lists may not come from a BankSet cartridge's ROM either (the
  window is `$4000-$FFFF` for every BankSet form). At boot MARIA now
  reports a list read at `$A1E2`, in ROM.
- **`-debugger script`** (`port/mame/script.cpp`): a debugger with no window
  whose stops hold for Lua. Breakpoints, watchpoints and stepping work from
  our probes (`tmp-bptest.lua`; 0.287's `bpset` needs its condition and
  action given: `bpset(a, "1", "")`). It sees ROM code, which Lua's read
  taps don't (MAME's opcode cache).
- The toolkit's MCP server (`tools/mamemcp.py`) runs MAME this way.
- `a78-0287-bs-rules1.exe` is the exe before.

### Level 1's top lists too: gameplay lists all in console RAM (2026-10-10)
- **Level 1's variables** (`RAM_VARS`, 146 bytes of CPU data) moved to
  cart RAM, `L1VARS` `$7C40`, cleared at the load with L1RAM. The freed
  start of L1RAM (`$2600-$2690`) and the room the merged zones left in the
  DLL pages (`$2270-$22B6`, `$2370-$23B6`) are level 1's top pieces, with
  `$1A57-$1A7F`, `$24D0-$24E0`, `$1EB6-$1EE5`, `$1812-$181F`. The band's
  pieces kept their places; the generator's load-time scratch stays at
  L1RAM's start.
- **Levels 2-4's top pieces** gained `$2100-$210E`, `$27E7-$27FF` and the DLL
  pages' `$2270`/`$2370` tails.
- **Fragmentation, found with a breakpoint** (`tmp-bpcopy.lua`: a stop at
  `TpCpDll` logging the copies left in their slots):
  - level 2's top's last row (row 64, its sky objects) is a 50-byte list,
    and the biggest piece had 48-49 bytes left after the small lists went
    there first;
  - the pieces are now listed smallest first, so first fit leaves the big
    runs to the big lists.
- **Checked:**
  - `tmp-dllcart-pk.lua` (`ANY=1`, from flip 200): in levels 1-4 and scene
    6, no zone's list (top or band) in cart RAM in play, only the 18 frames
    at the jump into the scene (scene 0's lists still shown during the
    load);
  - every scene's pictures identical to the build before (2,955).
- **Left:** scene 0 (the title, the story, the attract mode: lists in cart
  RAM and ROM; its console RAM all in use) and those load frames.

**The MCP server** (`tools/mamemcp.py`) is registered with the user's Claude
Code (`a7800-mame`, user scope). Its self-test passes on our 0.287 build
after the `bpset` fix, but for `mame_input`: 0.287's 7800 driver names its
ports differently.

**Checkpoint:** `2026-10-10_KEEP_enh-lists-gameplay`.

### Scene 0 too: no display list and no code in cart RAM or ROM (2026-10-10)
**Scene 0's console RAM wasn't all in use:**
- "No byte free" was the boot's RAM clear, which `p7800-ramuse.lua` counts
  as scene 0's writes. It now takes `RUSTART` (nothing before that frame).
- With `RUSTART=400`, scene 0 (the title, the story, the demo, 40,000
  frames) leaves about 1,250 bytes in runs: `$1852-$1A08` (439), the DLL
  pages' tails, `$1A4E`, `$1B4E`, `$1F46` and smaller.

**Its ROM lists weren't real either:**
- `tmp-romlists.lua` shows every list read from ROM in the first 16 frames,
  with MARIA's DLL pointer not yet written: the BIOS.
- So "706 bytes of ROM lists" in the title was a probe artifact.

**What scene 0 had in cart RAM:** the attract mode's demo fight, on the old
band and top paths.
- **Its own pieces:** `S_BLPC` `$20`, rows 32 and 40 of both tables
  (`S0SEG_A/B`, `TPSEG_S0A/B`), from runs free in all of scene 0.
- **`S_BLPC` by scene from a table** (`L1L_BLPC`; the fixed bank had no
  room for the longer code).
- **The allocator's bytes** went to cart RAM (`SG_VARS` `$7D40`): the
  title's tables are at `$2100`. Levels 2-4's top A took `$2100-$211F`
  whole.
- **Pictures:** scene 0 now differs from the pre-tiles build in 3 of 800,
  where it was 12: the same floor-stripe line as level 2's, from the old
  path. Level 1 and scene 6 differed from the build before in 2 and 1
  pictures, a move a frame apart (the scripted player at the scene's
  start), identical before and after.

**The last warning:**
- **The cause:** the start-up turned MARIA's DMA on mid-frame (`ResetTail`),
  so it read one list through its stale pointer (`$A1E2`, frame 166:
  `tmp-framecount.lua` prints frames among MAME's warnings).
- **The fix:** `ResetTail` waits for MSTAT's vertical blank first.

**Checked on the rules' MAME** (lists from cart RAM or ROM read as
nothing, code from cart RAM as `$FF`):
- every scene, the kit's checkdl runs: **no warning**, and every picture
  identical to the no-rules run (2,955);
- `tmp-dllcart-pk.lua` over the whole screen: no zone's list outside
  console RAM after the BIOS.

**Left of the user's rules:**
- the 1-line DLI zones (the band's colour splits, the sky's switch);
- MARIA's graphics in cart RAM, heading to MARIA ROM;
- the spec RAM form (`$6002`), which needs the blitter gone from levels
  2-4, the title and the ending.

**Checkpoint:** `2026-10-10_KEEP_enh-rules-clean`.

### No groups of one-line zones: DLIs on a zone's first row (2026-10-10)
**Why** (the user): a one-line DLI zone is fine where a DLI needs that
line, but not a group of them. The groups came from one rule: a buffer
row with a game DLI was always a zone of its own (the XE puts the DLI on
a run's last row). Beside a column's or grid zone's edge, that left
one-row neighbours: rows 116-118 were three one-line zones in every
scene, rows 89-91 in scenes 2-4.

**Done:**
- **A run's DLI on its first zone** (`DLI_FIRST`, kind bit `$40`): the
  zone builders (`BuildRowsZone`, `BuildTsRows`) flag the run's first
  zone. MARIA raises the DLI as that zone starts, on the same line as the
  old one-line zone, so the timing doesn't change; the zone just runs on
  to the end of its grid cell.
  - The runs' kinds are read with `AND #$3F` now (`BuildKind0`,
    `TopSkyOnRun`, `BuildTs3`); `S_DLI1` holds the flag (the unused
    `S_STEP`'s byte: the system variables were full).
- **`space_dlis`** works line by line after its two old steps:
  - every buffer-row DLI becomes `DLI_FIRST` on its line;
  - **the colour DLIs** (`COLOUR_DLIS`) keep their lines;
  - **a music DLI** moves to the nearest row that begins a grid zone
    (`TOP_ZONE` in the top, `BAND_ZH` in a column to `BAND_ZEND`):
    `DLI_NEAR` (12) lines from the DLIs round it, `DLI_GAP` above a
    colour DLI and above the top's last row (the sky's end);
    - level 1's top one goes 85 → 78 (row 30), the band's 165 → 164 (row
      116), scenes 2-4's 138 → 137 (row 89);
  - then the lines are joined into runs again: contiguous rows join, so
    the split `space_dlis`' gap step had left at row 133 is gone;
  - a music DLI on blank lines may now also go back to the multiple of 8
    above it (scenes 3 and 4: line 84 → 80, one zone fewer).
- **BuildTs** (title, story, ending): blank zones join the empty zone
  before them, up to 16 lines (`S_MRG`, as `PutEntry` does). The flagged
  blank line and the vertical blank's stand-in had been zones of one
  line, and the mode-8 lines a zone each.
- **Level 1's zones:** 18 → 13 (`l1scene7800.ZONES`, the build checks it
  against the lists). Two places had the old count built in:
  - `L1Bottom` and `RowsEmitPlain` wrote zones 16 and 17 for the bottom
    rows: they use `L1_ZBOT` (11) now. The first run showed rows 135-145
    black in every level-1 picture.
  - `L1Tiles0` indexed the tile rows by world × 18: it is × 13 now, and
    `l1scene7800.py` asserts the count.

**The DLLs** (live, the same frames, rules-clean checkpoint vs now):

| Scene | Zones before | Zones now | One-line zones before → now |
|---|---|---|---|
| 0 (title/story) | 32 | 24 | 8 → 0 |
| 1 (level 1) | 37 | 27 | 9 → 1 |
| 2 | 36 | 28 | 10 → 2 |
| 3 | 32 | 27 | 6 → 2 |
| 4 | 32 | 27 | 6 → 2 |
| 6 | 37 | 30 | 9 → 3 |

Level 1 saves 10 zone ends, 80 cycles a frame.

**The one-line zones left are single DLIs, each for a line:**
- the status bar's colour DLI (line 193, row 145: the last buffer row,
  with blank lines after it);
- levels 2-4's band colour DLI on the top's last row (line 112);
- level 1's sky switches (line 23 on, line 112 off).

**Checked on the rules' MAME:**
- no warning in any scene;
- 2,949 of 2,955 pictures identical to the rules-clean build. The other 6
  are timing: MARIA takes fewer cycles, so the CPU runs a little ahead.
  - Scenes 1 and 6 (2 and 1): the scripted player's move a frame apart at
    the scene's start, as noted before.
  - Scene 0's 190: the story's last line caught at another point of its
    wipe.
  - Scene 0's 678-679: a stray black line on the demo fighter, in the old
    build only.

**Checkpoint:** `2026-10-10_KEEP_enh-zones` (`enh-rules-clean` kept for the hardware test).

### MARIA's graphics and the CPU's ROM (2026-10-13)
**The user:** how much of MARIA's graphics is still in the CPU's fixed
bank, or anywhere in the CPU's ROM?

**MARIA reads none of it.** Under BankSet MARIA fetches only from its own
half (`mspace` in `build7800.py`: the top data, the fighters' parts, the
title and story), never from the CPU's. What the CPU's ROM holds for MARIA
is data the CPU copies or draws into cart RAM, which MARIA then reads.

**How measured:** `probes/tmp-romreads.lua`, every CPU data read of
`$8000-$FFFF` (effective address decoded as `p7800-cpureads.lua` does;
opcode fetches left out), by byte and reader. Runs: the attract loop
14,000 frames, scenes 1-4 and 6 scripted 10,000 (the invincible-easy cart).
Each byte read is named by what the build placed there (`karateka7800.map`).
The fixed bank's 16,128 bytes read from console RAM at `$2404` are the
BIOS's signature check, left out.

**Cart RAM, the same runs** (`p7800-ramclass.lua` + `p7800-cpureads.lua`,
`cartuse.py`): no display list. MARIA's graphics there: the bitmap (`$58-$72`),
level 1's windows and the captures (`$41-$4D`), a few page-head bytes.

**What the CPU's ROM holds for MARIA:**
- **Already in MARIA's format:** only level 1's tiles (characters and map
  rows), a 2,003-byte stream in banks 2, 3 and 6, which `L1Load` copies into
  cart RAM. **None in the fixed bank.**
- **The game's own images** (the XE's format), which the blitter (levels
  2-4, the title, the ending), level 1's loader and its shape converter turn
  into MARIA's pixels: **11,512 bytes read in these runs**, a lower bound
  (no ending, no game over):

  | Where | Bytes read |
  |---|---|
  | scene data (`sdata`), banks 0-3 | 4,789 |
  | bank 6's sprite copies (scene and art bank) | 2,530 |
  | the art bank (bank 6) | 1,237 |
  | level 1's tiles' stream (2,003 placed) | 1,261 |
  | scene code areas and common (`scode`, `common`) | 1,270 |
  | level 1's shape records (bank 3) | 168 |
  | **the fixed bank** | **202** |

  - **In the fixed bank:** 108 bytes of the sprite copy (scenes 2-4's
    sprites at `$F500`), 78 in bank 15's data, 16 in engine part 2.

**Not graphics, but read for MARIA's sake:** the fighters' part records
(2,688 bytes read, bank 6): the CPU's tables for the parts in MARIA's ROM.

**So:** the fixed bank holds about 200 bytes of image data, all the game's
own, for the blitter. The XE-format images can leave the CPU's ROM only
when the scenes drawing them stop using the blitter, as level 1 has.

### Levels 2-4 without the blitter: the data and the plan (2026-10-13)
**The user:** carry level 1's way (no blitter) on to levels 2-4.

**The data** (`p7800-l1cap.lua` alongside `p7800-stateplay.lua` on this
build: the clean run, `cref`, levels 1-4's start, 2,089 pictures; the level
3 recording, `strec`, level 3 and the finale, 2,725; scratchpad
`lvstats.py`, `capview.py`):

| Scene | Pictures | Blits | Fills | Clears | Images | Views ($52 $50 $4C $E4) |
|---|---|---|---|---|---|---|
| level 2 | 587 | 6,174 | 2,966 | 10 | 61 | 337: it scrolls |
| level 3 | 2,023 (+619) | 12,364 | 10,929 | 22 | 27 | $52 always $E0 |
| level 4 (finale) | 702 (+251) | 5,080 | 4,054 | 15 | 45 | $52 always $E0 |

- **Correction to the probe:** `p7800-l1cap.lua` named blit kinds by
  module B's entries in cart RAM (`$7C50`...). Since module B moved to the
  fixed bank they are `$EE50` (A), `$EFC4` (AR), `$F184` (M), `$F18D` (MR);
  both sets are in its table now (a mirrored blit's x depends on it).
- **Level 2 scrolls like level 1.** The palisade's stakes (`$A4F0`,
  `$A4D8`, 1x22 at row 45) repeat every 32 pixels in world x; the gates
  (`$A103`, `$A12D`, `$A1EC`, `$A000`) hold world places per structure;
  `$A0FC`, a 5-byte line drawn row by row (rows 80-122), is the portcullis
  moving; the art bank's `$964A`-`$9FC4` near world x 1,028-1,160 are the
  princess's cell. So level 2 needs level 1's tiles (worlds by `$4C`) and
  objects.
- **Levels 3 and 4 are rooms** (no scroll: V is always 896). A room is a
  handful of blits and fills:
  - the side walls, the same art-bank images as level 1's cutscene room
    (`$964A` 2x65, `$96CE` 1x77, `$9743` 1x6; plain on the right, mirrored
    on the left), a door (`$9980` 2x75), the walls' foot (`$971D` 4x8);
  - the stairs (`$A000`, 10x92, scene 3's page);
  - level 4's furniture (`$B700`, `$B7C8`, `$B9BE`, `$BABF`, `$BAD0`) and the
    princess (`$B5xx`, `$AE5C`: AND masks, mirrored, scene 4's page);
  - the floor: pattern fills (`AA`/`00` by row) over rows 118-145.
  - **The walls are redrawn in every picture** (2,013 draws in 2,023
    pictures): the game's fighter-box erases (black rects over rows 79-118,
    floor patterns over 118-129) cut into them. With the fighters as
    objects those erases and redraws are wasted work.
  - So levels 3 and 4 need no tiles: their rooms are objects (level 1's
    windows) plus the floor as strips.

**The plan:**
1. **Generalise level 1's machinery from "level 1" to "this scene's
   object set".** `S_L1` becomes the scene's set number; the records,
   zones, row backgrounds, windows and inventory are per set; the code is
   shared. The tiles stay optional (levels 1 and 2).
2. **Levels 3 and 4 first** (objects only): their inventories from these
   logs, their windows in the bitmap's pages (free once nothing blits
   there), the floor strips, the fighter-box erases ignored, the capture
   and emission as level 1's.
3. **Level 2** (tiles and objects): its worlds (structure `$4C`), rendered
   as level 1's are.
4. **Then** the blitter is left only in the title's marks and the ending's
   text; once they go, module B, the fast fill and their RAM can go.

**The binding limit is ROM:** about 7.6K free over the CPU's banks (bank 2
350 bytes, bank 3 200, bank 4 1.7K, bank 0 2.9K, the fixed bank 350).
Level 1's records went best-fit into bank 3's scraps. The other sets'
records and the shared code must fit in what's left, so the code is made
shared, not copied, and each set's records go in a bank its scene can
reach through `L1Call`.

### Levels 2-4 without the blitter: room in the art bank, level 1's code moved (2026-10-13)
**Room in the art bank** (`layout7800.ART_RELEASE`): the art bank's
`$8000-$95FF` and `$9A74-$9EB7`, 6,724 bytes, given back.
- **Why they're dead:** `tmp-romreads.lua` over every scene's scripted
  run, the attract loop, the clean run and the level 3/finale recording:
  the CPU reads 1,237 of the art bank's 8,192 bytes, all in `$9600-$9FEB`
  (the room walls, the door, the princess's cell). The rest are the
  fighters' original images, drawn from their pre-cut parts in MARIA's ROM
  since "The fighters as objects: step 4", and cell pieces no picture
  draws.
- **What the build checks:** no scene has an instruction or relocation
  there. The pose tables' pointers to them are labels: the code reads
  them but doesn't follow them.
- **Checked:** MARIA's half is byte for byte the build before's (its parts
  come from the game's images, not the bank). All 2,955 pictures identical,
  no rule warning.

**Level 1's machinery in bank 6** (`L1_HOME`, `L1_CAP`: banks 3 and 2
before, levels 3 and 2's pages, 200 and 350 bytes free):
- the records, the capture's arrays and code, the emission;
- **the window generator and the tiles' loader** (`L1GenA`, `L1TLoadP`,
  `L1GenTab`, `L1GenLn`, `L1PTAB`): FARL1 pieces now, out of level 1's page.
  `L1Load` calls `L1Gen` through `L1Call`. `L1Fetch` goes back to its
  caller's bank, not the scene page's. The scene pages' `ScL1Gen` entry
  is an `RTS` stub that keeps the table's layout.
- **ROM:** bank 1 1,078 bytes freed, bank 2 1,487, bank 3 1,156; bank 6
  has 3.5K free.
- **Checked:** all 2,955 pictures identical, no rule warning.

So the machinery can serve any scene: next, the per-scene sets.

**Tools added:** `port/scenecheck.sh` (every scene's pictures for a kit
cart: it lived in the scratchpad, which was emptied), `port/replay.sh` (a
recording forced onto the build with a companion probe: `clean` or `l3`),
`probes/tmp-romreads.lua`.

### Levels 3 and 4: the object sets and the canvas, version 1 (2026-10-13)
**Object sets** (`l1scene7800.SETS`): level 1's machinery serves any scene
page. A set is a scene page's zones, rows' backgrounds, shapes, windows' cart
RAM, and tiles (level 1) or the canvas (rooms). Level 1 is set 0 (scenes 1
and 6), scene 3 set 1, scene 4 set 2; scene 2 has none yet.
- **Sets per scene page, not per level:** the capture matches a draw by its
  image's address, and one address is a different image in another page
  (`$A000`: a level 2 gate piece, level 3's stairs).
- **One table for all:** the shapes in their images' low bytes' order
  (`L1K_FIRST`), each with its set (`L1K_SET`, checked by `L1Find` and
  `L1Gen`); the zone parts and zones numbered on from the sets before
  (`L1_ZB`, the set's first zone, added in `BandL1Arg`; `L1_ZBT` its
  bottom zones). `L1Load` (now in the top bank, through `L1Call`: the
  fixed bank's room) takes the scene's set from `L1L_SET` and its flags
  (`L1_SF`: bit 7 the canvas, bit 6 tiles).

**The rooms' data** (`probes/objinventory.py` → `port/s3shapes.txt`,
`s4shapes.txt`, from both replays' captures, a draw's own bank: the scene
before's last picture's draws left out): scene 3 23 shapes, scene 4 45.
**As level 1's objects they don't fit:** 3.6K and 4.8K of windows, 8 and 10
lines tall, against pages `$40-$4D` (14 pages; the bitmap's pages are taken,
`$73-$7A` hold Akuma's and the hawk's captures).

**The canvas** (scratchpad model `probes/roommodel.py`, against the game's
own buffers in the captures):
- **Fills only write** the bitmap; so does **a store at a whole byte**. The
  blitter's only reads of the screen are a row's edges: its first byte
  (`$2911`, `$2AED`: the pixels left of the image kept) and its spill
  (`$2937`, `$2B1F`: those right of it). With no shift both keep nothing.
- So in the rooms the bitmap stays, as a canvas the fills and stores draw
  into, and only **OR and AND blits** become objects over it (the door,
  `$9980`; the princess's and Akuma's masks): scene 3 2 shapes (108 bytes
  of windows), scene 4 17 (888).
- **Rules from the model:**
  - a blit of an image moves its instance (the rooms scroll by redrawing
    their walls 2 pixels further each picture: without this rule 127
    instances piled up);
  - a fill takes out the instances whose middle it covers (as level 1);
  - an AND mask's 0 **and 1** pixels are black (in the canvas: the floor's
    stripes are colour 2, and 2 AND 1 is 0; with 0 alone, 2-22 pixels
    showed the stripes through Akuma's robe in most finale pictures);
  - an OR or AND blit not in the set's inventory is drawn by the blitter as
    before (Akuma's masks his own capture leaves).
- **The model's numbers:** shifted stores written without reading, their
  edges black: in scene 3 a black line across the floor beside the stairs
  while the room scrolls; with the row's background on the edges (the
  floor's stripe on its even rows) 91 pictures of 2,023 differ, by at most
  41 pixels, all in room scrolls.

**Version 1 as built:** OR and AND blits objects; fills and stores drawn by
the game's code as before (the edges still read: no fixed-bank room for the
background-edge code, about 100 bytes); clears clear the canvas too; a copy
copies it as the game's (it reads; level 3's start only: 1 fill and 5 stores
in the source). In the canvas, band zones list the bitmap's two objects, then
the instances (`BandWCv`), keep their front boxes and their closing 160A
header; the bottom zones are the bitmap's (`L1Bottom` writes nothing there:
its `$22B7` is in the levels' band-list pieces). `L1Gen`'s scratch is the
fast fill's RAM: in the canvas the fill is copied in again after it
(**the first build hung at flip 191 in scenes 3 and 4**: the next fill ran
cleared RAM).

**Checked:**
- all 2,955 scripted pictures identical; no rule warning;
- the level 3/finale recording forced onto this build and the one before
  (snapshots every 10 flips, `port/replay.sh` with `SNAPF`, `BUILD` for
  another build's symbols): the differences are the fighters a step apart
  (this build's speed), and three finale pictures where the fallen Akuma
  lies: 34-54 pixels, the old build showing the floor's stripes through the
  player's trouser leg, the new a solid leg (an OR blit's merge objects
  can't make).
- **Speed** (flips by the scripted runs' last frame): scene 3 2.3% fewer
  (the door's capture and emission each picture), level 1 0.7% fewer (the
  set checks), the others the same.

**Left for the rooms' reads:** the shifted stores' edges (the background
rule above, when the fixed bank has room) and the copy (a replay of the
source's fills and stores: an 8-entry record a buffer is enough).

**Also:** `kitopt.py --cart` (a cartridge built elsewhere, its patch sites
beside it as `CART.sites.json`).

### The fixed bank: room (2026-10-14)
**The user:** do a pass to free fixed-bank space. **Result: 324 bytes free
before, 818 now** (16,060 → 15,566 used), pictures unchanged.

**How measured:** `probes/tmp-fixcov.lua`, the CPU's own use of
`$C000-$FFFF`: instruction bytes at the PC and data reads at the
instruction's effective address. `p7800-coverage.lua` can't be used for this
any more: in the BankSet MAME, MARIA's fetches from its half's fixed bank (the
fighters' parts) go through the same address space, so they marked bank 15
nearly all read (55 bytes of 8,319 untouched). Runs: every scene scripted,
the attract loop, a game over, both recordings forced on.
`probes/fixcov.py` lists the unused bytes by what the build placed there and
by routine.
- **The CPU uses 14,159 of the fixed bank's 16,384 bytes.** About 1.9K of
  the game's own code and data is never used in these runs (bank 15 924,
  the engine's parts). As on 10-09, untouched game code is kept: coverage
  alone doesn't prove it dead (two-player paths, the keyboard's, rare moves).
- The port's own code is nearly all used.

**What was given back:**
- **The replacements' dead remains** (`layout7800.DEAD_RELEASE`, 255 bytes):
  bytes inside a replacement that nothing can reach and no run reads. The
  build checks each lies inside one replacement.
  - bank 15's buffer copy's old set-up (`$AD8F-$ADB2`). Kept clear of
    `$ADBB-$ADC3`, which some run reads, likely as an image.
  - engine part 1's swap jump's tail (`$115C-$1168`);
  - the pattern fill's old store block (`$2D19-$2D3D`, now in RAMFILL);
  - the row address's old buffer base and the multiply (`$2D49-$2DA0`).
    Their entries are `$2D53`, inside a replacement, and `$2CC6`, the
    engine's table, which no code in any scene refers to.
  - the scene loader's jump's tail (`$2F69-$2F89`). `$2F5A`'s tail is not
    dead: it falls into `$2F66`.
- **The port's dead code:** `ScnIn`, `ScnOut`, `ScnRead`, `FtRead3` (no
  callers); `FgCol`'s column front box, which only the column routine's
  pre-object path calls (`ColA0`, with `S_L1` off: never in level 1), now an
  `RTS`, and its top-bank half `FgColB`.
- **The health arrows' copy** (`$FF12`, 19 bytes): no run reads it since the
  status bar's arrows are objects from MARIA's ROM.
- **LoadScene's RAM set-up** (about 160 bytes, the fighters', Akuma's and
  the lists' state at a scene's load) into the top bank: `LoadInit`,
  through `TopArtCall`.

**Looked at and left:**
- `AkCap` (240 bytes): reads the scene page's page map and its blitter's
  return addresses at fixed stack offsets. It needs a fixed half anyway.
- `Frame` (340) reads the scene page's list tables.
- `ZpSwap` and `ZpClear` read their tables in the scene pages, and may be
  called where `TopArtCall` isn't safe.
- `Inputs` and the DLI code run in the NMI.
- The note table at `$2300` is partly unread (notes no run played).

**Checked:** 2,954 of 2,955 scripted pictures identical; the other is
scene 0's picture 190, the story's wipe caught at another point (timing, as
on 10-10). The level 3/finale replay differs only in the fighters (a step
apart). No rule warning.

### Towards no cart RAM: what's in it, and the backgrounds (2026-10-14)
**The user:** how close are we to cart RAM becoming more cart ROM? Then:
keep going.

**Without RAM** (BankSet type `$2002`): `$4000-$7FFF` shows the
second-to-last bank (bank 6) on both halves, fixed (MAME's
`a78_rom_bankset_sg_device::rom_40xx`). Not more ROM (the cart stays 2 x
128K), but a second always-visible 16K: if the CPU never selects bank 6 into
the window while MARIA draws, her bank-6 copy is 16K of her own, beside the
3K free in the shared window block. The CPU sees its bank 6 (the art bank,
level 1's code and tables) at `$4000` without switching.

**What cart RAM holds today** (`p7800-ramclass.lua` + `p7800-cpureads.lua`,
every scene, the attract loop, the level 3/finale recording):
- MARIA's graphics, about 9K: the bitmap (`$58-$72`, 6.6K: the canvas of
  levels 2-4 and the ending, level 1's windows and tiles), the rooms' and
  level 1's windows (`$40-$4D`, about 1K), Akuma's and the hawk's captured
  slices and the black block (`$73-$7A`, 1.3K);
- the CPU's data, about 1.5K: the top lists' slots (`$4F-$53`), the top
  tables (`$57`), the fighters' tables (`$4E`, `$7B`), the front boxes'
  tables (the bitmap's page heads), level 1's variables and the lists'
  allocator (`$7C-$7D`), the story's variables;
- no lists, no code.

**The order:** level 2 without the blitter; the rooms as tiles; the ending's
and game over's text as characters; Akuma's and the hawk's frames pre-cut;
the front boxes from ROM; the CPU's data in console RAM; bank-6 discipline;
the header.

**Backgrounds can't be objects** (`probes/spanmodel.py`): every blit and
every fill (a span: rows, byte columns, value or pattern) an object in the
game's order, a wholly covered one dropped, a blit drawn again moved.
- **The pictures:** level 4 0 of 702 differ, level 3 12 of 2,023 (69
  pixels, as before), level 2 283 of 587 (mostly under 100 pixels).
- **The objects:** a zone row holds 11-27 at the median, up to 44, mostly
  fills: each picture's erases (the princess walking: a black rect over
  rows 79-117 and the floor's stripes below, a column further each step) stay,
  since when each is drawn the wall it cuts is still there from the picture
  before. A span is 11-32 bytes wide: up to about 100 of MARIA's 414
  cycles a line each.
- Dropping a fill that paints what is already there (black over nothing,
  stripes over the same stripes) barely helps (median 27 to 27, 11 to 9).
- **So a background drawn by fills is a bitmap or tiles.** Without a bitmap,
  it is tiles: each room's and each level's background pre-rendered as a
  world (level 1's way), only what moves an object.

**Level 2** (`probes/lvworld.py`, `l2model.py`; the clean run):
- structure 0 almost alone (585 of 587 pictures), V 0-1,023;
- its band rows: black above row 118, the floor's stripes ($55 on odd rows,
  drawn once: it looks the same wherever the view is), the gate's pieces
  (`$A103`, `$A12D`, `$A1EC`, the OR `$A000`, `$A274`: world x 232-348), the
  end walls (`$A602`, `$A546`: world 0 and 1,012), the stakes' and spikes'
  last rows (65-66: their places follow the view, as level 1's posts do),
  the guards (AND masks `$AC8D`, `$ACA8`; stores `$AAC5`, `$AB2B`, `$AB64`,
  `$AC0D`, `$ACD7`, `$ABB1`), the portcullis (`$A0FC`, a line at a time,
  rows 80-124, OR);
- **the princess's cell** (pictures 688-715) is drawn at V 1,016, the same
  view as the fortress's end: a world of its own (as level 1's cutscene
  room), marked by its left wall.

**Correction (found in the next section's work):** `$AAC5`, `$AB2B`,
`$AB64`, `$ABB1`, `$AC0D`, `$ACD7` are the hawk's frames and `$AC8D`,
`$ACA8` its shadow's AND masks on the floor, not guards: in level 2 the
hawk flies over the fortress, drawn by the blitter (store mode, so
`AkCap` leaves it alone).

### Level 2 as tiles (2026-10-14)
**The user:** keep going (the plan's first step: level 2 without the
blitter). **Result:** level 2 is level 1's machinery, a tiles set: its
background three worlds of characters, what moves objects. No bitmap in
level 2; its cart RAM is the windows' and the tiles' (6,709 bytes, 2,907
free). Pictures checked against the bitmap build under the clean
recording's forced state; level 2 within 1% of its speed.

**The worlds** (`probes/l2worldlist.py` to `port/l2world.txt`):
- **V wraps:** the level starts at V 0, which is 1,024; then it runs 1,023
  down to 112 (the gate). V under 64 counts as V + 1,024.
- **The fortress's own images** (`WORLD_IMAGES`): the gate's pieces and the
  end walls. Every other image of the scene page is an object.
- **The rooms** (the cell "2c", the princess's room "2p") are decided at the
  picture's end and take the draws since the clear (the cell's floor came
  before its marker). The bed marks the princess's room: before that, the two
  rooms were one world.
- **The rooms' figures are objects** (`FIGURES`: Akuma's pieces, whose arm
  changes pose; the princess's). In the world, the first pose stayed under the
  next.
- **A fill painting the base is kept when it covers a draw kept before it.**
  The gate's black fill (rows 18-117) wipes the beam (rows 65-66). The game
  paints the beam back with a fill equal to the base, which the list had
  dropped: a black gap 40 pixels wide over the gate.
- **Overlapping draws are ordered as most pictures draw them**, with the
  last occurrence for the rest. The portcullis's drop draws the gate's tips
  (`$A000`) last of all, which had put them under the gate's pieces.
- Lists: fortress 29 draws, cell 11, princess's room 10.

**The model** (`probes/l2tilemodel.py`): the runtime's rules (world markers,
the tiles under the instances, level 1's instance rules) against the game's
own buffers:
- the fortress within about 30 pixels a picture (the beam's notches, below);
- the cell within 40;
- the princess's room exact;
- at most 23 instances a buffer (24 allowed).

**Characters:** the three worlds need 123 characters (246 bytes a line page),
so one set does. The fortress's rows are one character for 125-133 of their
135 columns.
- **Dead end:** two character sets (159 characters), from before the
  figures were objects.
- **The set's place:** at `$64` (level 1's) it split the windows' block, and
  the 135-byte map rows had no room. At `$69-$72` (the band zones' list
  heads, unused with tiles, like level 1's `$64-$6D`) it fits, with `$58-$68`
  one block for the windows.

**Map rows cut** (`Tiles.short`, every tiles set): a row's longest run of one
character is cut to the view's 21 when that saves 16 bytes or more.
- `L1Tiles` maps the view's first column c0 with `L1T_CL` (the run's start)
  and `L1T_CD` (the cut): before the run as it is; in the run's first CD
  columns the run's start; past them c0 - CD.
- The fortress's 1,620 map bytes become 359. **Level 1's rows shrink too:**
  1,002 bytes of cart RAM freed, its pictures identical.

**The runtime, table-driven where it was level 1's:**
- **World markers** (`L1MK_*`, `L1Blit`; a set's `markers`):
  - level 1's rails go to `L1Mark`;
  - level 2's stakes (both images: the level's first picture draws `$A4F0`
    before its clear and only `$A4D8` after) mark the fortress;
  - the cell's left wall marks the cell, out of a room only;
  - the bed marks the princess's room.
- **The rooms' floor fill** marks the set's room world (`L1_RW`).
- **Per world** (`L1T_*`):
  - its rows: `L1T_WB` plus the zone, in place of world × 13;
  - flags: bit 7 a room (not scrolled), bit 6 level 1's structure (`L1Mark`
    at the flip);
  - CHBASE, set at the flip from the buffer's world;
  - the zone where the palette `L1_PAL` starts (`$FF` for level 2: no split).
- **Per set:** the view's wrap (`L1_SF` bit 5) and the tiles' stream's
  first piece (`L1L_TS`, `L1G_TS`).
- **The play lists' CTRL** has two-byte characters for every tiles set's
  play lists, not just level 1's. **Before that, the screen showed half the
  floor:** one-byte characters, 21 × 4 pixels.
- **The band lists' pieces** of levels 2-4 (`BMSEG_A/B`) no longer cover
  `L1Bottom`'s lists at `$22B7`/`$23B7`.

**The hit star left in the air:** in bitmap mode a fill over an earlier
picture's hit star erases it (`RowBase` → `FgRec` → `FgStale`). A tiles set's
fills are captured and never reach `RowBase`, so at the gate a star stayed
for good.
- `FgRecF` (from the fill hook, after the game's clip, and for fighter-box
  erases) gives the fill's box to `FgRecFB`, which erases the buffer's earlier
  hit star only.
- **First try, the whole `FgStale`:** fighters vanished (a cutscene guard,
  the player in level 1). Level 1's fills had never gone through it.
- **Level 1 changes with it:** a hit star there now goes when a fill covers
  it, as in bitmap mode. The scripted level 1 pictures differ from 296 on,
  and the run's timing then diverges.

**The portcullis's drop** (`$A0FC`, one line at a time over three pictures,
44 lines): two column shapes of level 1's kind (OR, every 2 rows: 81-123 and
82-124). The drop's lines at rows 81 and 82 add them (marker action
"column": `L1Blit` looks the draw up as a column), and its other lines are
dropped.
- The portcullis shows closed from the drop's first picture, where the game
  takes three. After that it matches.

**Speed** (the clean recording forced onto this build and onto the fixed-bank
checkpoint, frames between flips, `FLIPLOG`; `FLIPN` added to
`p7800-stateplay.lua`):
- **First build: level 2 13.5% slower overall, 25-40% slower while the view
  scrolls.** Without the stakes' band rows, the scrolling stretch took the
  same time as the bitmap build (2,752 frames against 2,748).
- **The stakes are two images at a place**, `$A4D8` stored over `$A4F0`. In
  the band (rows 65-66, over the beam) `$A4F0`'s pixels are the beam's own
  colour 2, so it's left out (`L2_UNSEEN`). That also keeps a scroll step's
  old and new stakes within the 24 instances; before, some were dropped
  until the flip.
- **Now** (flips 637-1210, the cell to the gate): 4,454 frames against 4,416
  (+0.9%). The scrolling stretch is 3,122 against 2,748 (+13.6%), the
  cutscene and the gate faster. Level 1 is 0.8% faster (the shorter rows).
- **What scrolling costs:** every picture rewrites every band zone's list,
  fighters included, since each tiles header moves with the view. A view-only
  update of the headers would be the next saving.

**Checked:**
- the scripted pictures: scenes 0, 3, 4 and 6 identical; level 1 identical
  but for the hit stars above; level 2's run diverges (its timing);
- the clean recording, flips 630-1226 every 2, against the bitmap build: the
  scenery matches, cell and princess's room included. The differences are the
  fighters a step apart, and the drop's first two pictures.

**Known gaps:**
- the beam's notches (the stakes' bottom bytes left by the game's half-pixel
  rounding: about 7 pixels a picture);
- the cell's moving floor-line gap (a fill on row 126 that walks with a
  figure: about 30 pixels);
- the portcullis closed a picture or two early.

**Tools added:**
- `probes/l2tilemodel.py` (the runtime's model);
- `tmp-zonedump.lua ZDRAM=1` (cart RAM as written, and CHBASE: Lua reads
  cart RAM back as `$FF` in this MAME);
- `tmp-shares.lua`;
- `nop.lua` (a companion for `replay.sh`);
- `tmp-prof.lua` as a replay's companion (`NOPLAYKEY`, `PROFN`).

**Checkpoint:** `2026-10-14_KEEP_enh-l2tiles-v1` (before the speed and drop
work).

### Levels 3 and 4 as tiles; things in front of the fighters (2026-10-14)
**The user:** not worried about performance yet; keep moving to cart RAM
effectively 0. **Result:** the plan's step 2 is done. Levels 3 and 4 are
tiles sets like levels 1 and 2, the canvas is gone, and no gameplay scene
draws into the bitmap any more (scene 0's attract demo still does). Pictures
match the canvas build: the scripted runs have no picture over 300 pixels in
levels 3 and 4, and the finale recording matches but for the fighters a
step apart.

**The worlds** (`probes/worldlist.py`, generic now, its settings in
`port/worldcfg.py` for the build too; level 2's list is the same as before):
- **Level 3** (`port/l3world.txt`):
  - "3s", the first room, scrolled: the stairs (`$A000` at world -1,024),
    the corridor, the right door frame at -764, V 1,024 down to 896. Its
    floor stripes are its base: the game draws them once and never again as
    it scrolls, since they look the same at any view;
  - "3r", the rooms with both door frames, all alike, at V 896: a room
    (fixed), marked by the left frame;
  - "3p", the princess's room's cutscene.
- **Level 4** (`port/l4world.txt`): "4r", Akuma's room (the right frame
  marks it), and "4p", the princess's room. Both are fixed (V is always
  896).
- **Rooms take only their own images** (`world_images`: the frames, the
  princess's room's furniture). Without that, level 4's rooms took Akuma's
  pieces and shadow masks.
- **The model** (`probes/tilemodel.py`, generic): level 3's rooms exact; its
  first room exact but 19 pictures in 2,600 where the right frame is drawn a
  pixel off while the view settles (the game's half-pixel rounding, as level
  2's stakes); level 4 under 100 pixels.
- **AND masks in the rooms:** black where the mask is 0 or 1 (the canvas's
  rule: the floor is colour 2), a set flag now (`mask01`, `L1_SF` bit 4).
  With level 1's rule (0 only), level 4 differed in 392 of 579 pictures.

**One character set for levels 3 and 4:** together they need 90
characters, the same as level 3 alone, and level 4's map rows are all
level 3's. Both sets load one stream (the build shares identical streams);
each world's row tables belong to the set that shows it (`ObjSet.own`).

**In front of the fighters** (the canvas did it with front boxes):
- **What the game draws after the fighters**, measured with
  `p7800-l1cap.lua`'s blit lines, which now end with `FT_SEEN`, on the
  10-13 capture carts:
  - levels 2-4: the door frames' outer posts (`$96CE`, both sides), always;
  - the door (`$9980`, an OR);
  - level 2's gate post (`$A1EC`), the gate's tips (`$A000`), the
    portcullis (`$A0FC`);
  - level 4's bed foot (`$BAD0`, all black).
  - Level 1 draws nothing after them.
- **Front shapes** (`Shape.front`, `L1K_W` bit 7): `L1Zone` writes a zone
  in passes: 1, the tiles and the instances behind; 2, those in front, after
  the fighters (`BandWFr`, from `BandWFrP`). Pass 2 runs only if pass 1
  passed one by (`L1_FS`). The bottom zones, which have no fighters, write
  all at once.
- **A front shape is captured only when drawn after the fighters**
  (`FT_SEEN`); otherwise its world's tile shows it.
- **Posts with colours** (`FRONT_OR`: `$96CE`, `$A1EC`) stay in their world,
  and their front copy is an OR in palette 1. Stores use palettes 2 and 3,
  which hold the top rows' colours, and in the rooms those aren't the band's:
  the first build showed orange marks on the posts. The bed foot, all black,
  is a store (palette 2's black is always black).

**Faults found on the way:**
- **A black bar across the door:** a fighter's 160B head (a 5-byte header)
  switches MARIA's write mode, and the front objects after it are 4-byte
  160A headers. A tiles set's list skipped the closing 160A header because
  the next zone's tiles header resets the mode; it's always written now.
  Found with `probes/zdrender.py` (the band rendered from a zone dump and
  cart RAM as written), which showed the data was right.
- **A post in mid-air in level 3's first room:** the right frame is drawn at
  x 272, off the screen, while the stairs show, and the instance kept x's low
  byte, 16. `L1Place` now refuses columns 40 on and before -14 (C set). Its
  first version returned C clear: after `CMP #$F2` with A below it, C is
  clear.
- **The floor and Akuma's legs missing in the cell:** two zones got the
  empty list, since levels 2-4's band-list pieces ran out of room with the
  front objects. They now also take the fast fill's RAM, `$2600-$277F`, as
  level 1's do: a tiles set's fills are captured, so the fill never runs.
  The bottom zones' lists are 24 bytes (the posts reach row 136): `L1BOT_N`.
- **The ending's text was garbage** (jumped to with `p7800-jumpto.lua`). It
  had been since the canvas (10-13; the 10-10 build is right): the ending
  runs in scene 4 with its set on. `EndText` now turns the set off (`S_L1`,
  `L1_SF`), and the frame drops the two-byte characters' CTRL bit with no
  set on. The text is the 10-10 build's in all 21 pictures.

**ROM:**
- **Shapes:** 127 in the four sets, the generator's limit (the shape's index
  shares a byte with the drawn mark). Level 2's `$A000` row 87 and `$A02C`
  row 101 are left out: each is drawn once, in the portcullis's drop. Raising
  the limit is for later.
- **Bank 6 was ~1K short:**
  - the capture's first-shape index cut from 256 bytes to 32 (`L1K_F32`, by
    the low byte / 8, then past the lower ones);
  - the front flag folded into `L1K_W`;
  - the map rows' tables keep distinct rows only (`L1T_IX`);
  - the canvas's code removed (`BandWCv`, the canvas's move rule, its
    checks).
- **The tiles' streams** go in banks 3, 2, 1, then 0, then 6; a run may hold
  several sets' pieces. Bank 0 is allowed for them: MARIA shows the blank
  list while `L1Load` runs (`probes/tmp-loaddll.lua`), so its title data in
  MARIA's copy doesn't matter then. Not bank 4 (the FAR04 pieces' room) or
  bank 5.

**Speed** (frames between flips, the recordings forced, `FLIPLOG`):
- levels 3 and 4: 25-28% faster than the canvas build (finale recording),
  24% in the clean run;
- level 1: 3.6% slower than the fixed-bank checkpoint, level 2: 11.7%.
  Before the front pass was skipped when empty, 11% and 14%. Left for later,
  as the user said.

**Not checked:** a game over in levels 2-4 (`QUIET` runs walk away and
aren't beaten; the pictures match the 10-10 build's); hardware.

**Tools added:**
- `probes/worldlist.py`, `probes/tilemodel.py`, `port/worldcfg.py`;
- `probes/zdrender.py`, `probes/capshow.py`;
- `probes/tmp-loaddll.lua`, `probes/tmp-framesnap.lua`.

**Not fixed:** "the end" loses its tenth row (row 65) in the tiled levels.
Left as cosmetic for now.

## Akuma and the hawk pre-cut at load (2026-10-14)

The goal (the user's): cart RAM holds only what a scene's load writes and
MARIA alone reads, like ROM. Akuma and the hawk broke that: `FtEmitAk`
copied their slices into the slice pages at every emission. Now their poses
are cut once, at the load.

**The poses** (`port/akposes.txt`, made by `probes/akposes.py` from
`probes/tmp-aklog.lua`'s logs of the capture runs):
- 89 poses: 32 for the hawk (level 3), 57 for Akuma (level 4);
- a pose's key: image, mask (a pair's `$14/$15`, else 0), flags
  (`S_FMIR`), row (`FP_ROW`);
- its cells follow the fighters' grid (`fighters7800.ZONES`, rows 65-134),
  each the cell's lines x the image's width.

**How it works** (`port/akpose7800.py`):
- **The build** reserves each pose's cells in its set's cart RAM. The slice
  pages' columns 120-239 (`AK_COLS`) come first. Runtime slice copies now
  stay below column 120 (`AKP_COLS`).
- **The load** (`AkPre`, from `L1Load`) draws every pose with the game's own
  code, `FtPlain` and `FtObj`, in render mode (`AKP_REND`). `FtObj` copies
  each cell to its place and makes no object.
- **At play,** `AkLook` (before `FtPlain` in `FtEmitAk3`) builds the key and
  calls the set's search (`AkFind`) through `L1Call`. If the pose is found,
  `FtObj` points the objects at its cells (`AKP_ON`, `FP_NOCP`: no copy).
  If not, the pose is copied as before.

**The table:** chunks of up to 60 bytes, each with a 3-byte header (poses,
the next chunk's address). Per pose: image, mask, flags, row, the image's
bank, the number of cells, then each cell's (T, C).
- The hawk's table, 470 bytes in 9 chunks, and its search are in bank 0
  (`FARL0`). Akuma's, 786 bytes in 15 chunks, are in bank 4 (`FARL4`).
  `AKP_PB` holds each set's bank; `AKP_FL/FH` hold its search's address.
- Both banks are safe to switch in during levels 3 and 4. Their MARIA copies
  differ from the others only in levels 1 and 2's top data.

**Dead ends:**
- **The first version read the table through `FtRead`** (a bank switch per
  byte) from bank 5's code. The pictures were right, but it was slow, so the
  search moved into the tables' bank.
- **One bank for both tables didn't fit:** bank 4 had no room for a 49-byte
  piece, and bank 0 none for a 51-byte piece (it also holds the load code,
  below). Each set got its own bank instead.
- **The chunk size went 200, 100, 60:** the banks' free runs are short.

**Load code moved to bank 0** (`FARL0`, `L1_GEN = 0`), to make room in bank
6: `L1Gen`, `L1Conv`, `L1PTAB`, `L1TLoad`, `L1G_KSET`. Bank 0 holds scene
0's page, wrong for MARIA during levels 1 and 2, but every load runs under
the blank list (`probes/tmp-loaddll.lua`). All scenes were identical to the
build before.

**Checks:**
- **Every emission found its pose** (`probes/tmp-akhit.lua`, a replay
  companion counting `AKP_ON` at `AkLookE`): the hawk 803, Akuma 1,626,
  no misses, in the level 3 recording.
- **Pictures:** the level 3 and finale replay against the rooms-tiles
  checkpoint (272 pictures) differs in 52, all in the fighters' band. They
  are fighters caught a step apart, since the pictures land at other frames
  as the speed changes. Akuma's striped robe in his kick is the original's:
  the reference has it too.
- **Scenes** (`scenecheck.sh`, against the last build): identical but one
  attract picture, which catches a line of text being drawn, as the old one
  does too. Only how far the draw got differs.
- **Speed** (`FLIPLOG`, the level 3 recording): frames in the hawk's
  pictures -7.9%, Akuma's -9.7%, the whole run -2.8%.

**Tooling slip:** `replay.sh aknew` wrote into the old `akNew` folder
(Windows paths ignore case), so its snapshots were offset by that run's 272.

**Tools added:** `port/akpose7800.py`, `probes/akposes.py`,
`probes/tmp-aklog.lua`, `probes/tmp-akhit.lua`.

### What still writes cart RAM during play (2026-10-14)
Measured with `probes/tmp-cramw.lua` (a replay companion: every write to
`$4000-$7FFF`, by page and PC, and in how many pictures) on the clean and
level 3 recordings. A page written in only a few pictures is a load's.
- **Load only now:** the slice pages `$73-$7A` (`FtBlk2`, 5 pictures in
  the clean run, none in the level 3 run). Akuma's and the hawk's copies are
  gone.
- **Every picture, the CPU's data:**
  - `$7B-$7D`: level 1's variables, the fighters' sort and tables, the
    lists' allocator, `L1Call`'s state;
  - `$57`: the top tables (`TopStale`, `TopRef`, `TopCapCover`);
  - `$4F-$52`: the top lists' slots (`TopEmit`). They are built there and
    copied to console RAM, so the CPU also reads them;
  - `$4E`: `FO_HB` (`L1Src`);
  - `$5F-$62`: the front boxes' tables (`FtEmitFg` copies `FGR_*` to
    `FG_*`), and `$63`: the fighters' records (`FRec0`, `FtEmitNew`).
- **The game's own writes to its old framebuffer:** `$40` (`$258D`, 865
  pictures of 2,000) and `$43` (`ColL1`, 264). Nothing shows those rows.
- **The front boxes** are recorded and copied every picture, but no tiles
  set draws them (`BandWXC` skips them unless the set has a canvas, and none
  has one now). Only scene 0's attract demo, still in the bitmap, uses them.

**Console RAM has no room for the CPU's data:** the free-RAM ledger
(`FREE_RAM`, `freecheck.sh`: clean) holds only some page heads. The CPU's
data in cart RAM is about 1.5K, plus the slots. The other way is the
spec's split RAM (`$6002`): the CPU has its own 16K at `$4000`, and
MARIA's 16K is written through `$C000`. There, the CPU's data and the game's
dead framebuffer writes stay where they are, in the CPU's half. MARIA's half
gets only the loads.

**The user chose console RAM** (not the split RAM), and asked whether that
data, or any console RAM data, could be ROM.

### Could it be ROM? (2026-10-14)
Measured with `probes/tmp-romable.lua` (every scene: the attract loop to
frame 14,000, scenes 1-4 and 6 scripted to 12,000), merged by
`probes/romable.py` with `p7800-ramclass.lua`'s marks of what MARIA reads.
The probe records, per byte and scene:
- the writes while the blank list shows (a load) and in play;
- the play writes that changed the byte;
- the values written;
- the CPU's data reads (decoded from the instruction, as
  `p7800-cpureads.lua` does).

| class | console RAM | cart RAM |
|---|---|---|
| lists (RAM by the rules) | 1,947 | 0 |
| MARIA's graphics, loaded only | 20 (`TOPSKYROW`) | 5,371 |
| MARIA's graphics changed in play | 0 | 2,452 |
| the CPU's data changed in play (RAM) | 790 | 882 |
| never changed in play: one value everywhere | 82 | 249 |
| one value a scene | 10 | 12 |
| read, never written (always 0) | 73 | 68 |
| written, never read (dead) | 547 | 2,552 |

**What each class holds:**
- **Graphics changed in play:** scene 0's bitmap (`$5C-$72`, the attract
  loop), plus 8-10 bytes a page in `$44-$4A`.
- **Real RAM, 1,672 bytes:**
  - console RAM: the fighters' tables (`$1B-$1D`), the system variables
    (`$1E`), the scene carves;
  - cart RAM: `FO_HB`, the top lists' slots (`$4F-$52`, 416), the top
    tables (`$57`, 82), the band-list tails (`$7B`), level 1's variables and
    the allocator (`$7C-$7D`).
- **"Never changed" is mostly not constants:**
  - Page `$57`'s 144 are table entries past the count, written 0 and read,
    in every run: unused capacity being cleared.
  - The front boxes' tables (`FG_*`, `FGR_*`): no tiles set records boxes.
  - Akuma's old capture tables (`AK_*`, `$1AA1`, the "always 0" ones): the
    pre-cut poses replaced them.
  - So few real constants are left: `TOPSKYROW` (20, graphics), some
    scene carves, a few mode bytes per scene (`L1_SET`, `S_BLPC`,
    `S_STUBBK`).
- **Dead:**
  - the fast fill's patch bytes (`$2626-$2770`, 195): the fill no longer
    runs;
  - the fighters' tables' unused slots (5-10 bytes at each table's stride);
  - Akuma's old page tables;
  - the game's writes to its old framebuffer (`$40-$4D`);
  - the slice pages' columns 120-239 (`$73-$7A`) are Akuma's pose cells,
    dead only because no scripted run reaches the finale.
  - **Correction to the table:** `$27D0-$27E5` is the NMI stub's code. The
    probe counts operand fetches as neither reads nor code.

**So console RAM's budget:**
- lists 1,947 + zero page and stack 384 + the CPU's real RAM 1,672 = 4,003
  of 4,096;
- the top lists' slots (416) exist only to be copied into console lists.
  Built in place, the total is about 3,590.
- ROM takes little: the real constants are tens of bytes. Dropping dead and
  never-used data, and building the top lists in place, matter more.

**Not covered by these runs:** the ending, a game over, pause, two players,
the finale's fight (scene 4's script doesn't reach it). A byte that changes
only there looks constant or dead here, so each move gets checked there
first.

**Tools added:** `probes/tmp-cramw.lua`, `probes/tmp-romable.lua`,
`probes/romable.py`. The first `tmp-romable.lua` hung at frame 100: its
taps read addresses inside their own ranges (`S_SCENEBANK`, a byte's old
value) and re-entered. It has a guard now.

**The fast fill's RAM** (`$2600-$277F`): its code is still copied in at
every load (`CopyFill`), but no covered run executes it: tiles sets capture
their fills, and the attract loop doesn't reach it. Its other writes come
from the BIOS at boot (its signature check runs there). It goes when no
scene fills the bitmap any more.

### The top lists written in place (2026-10-14)
The top zones' lists were written in cart RAM slots (`$4F10-$540F`, 20 of
60 bytes) and then copied into console RAM's top pieces (`TpCp`). Now
`TopEmit` runs its piece loop twice:
1. it counts the list's bytes;
2. it takes room in the first piece that fits (`TpPlace`) and writes the
   list there.

An empty list, or no room, gives `DL_EMPTY`. Before, no room meant the slot
in cart RAM. A slot keeps only its zone, by ordinal (`TOPZ_ARG`, `TOPZ_H`,
in slot A's old place for now, `$4F10`; `TP_EK`, `TP_PASS` and `TP_T0-2`
beside them). `TopRefresh` reads the zone from there.
- **Pictures:** `scenecheck.sh` identical in all six scenes.
- **Cart RAM:** pages `$50-$53` are written in one picture of the clean
  run (the load); `$4F` only in its first 45 bytes.
- **Speed:** the clean run takes 1.1% more frames (the count pass, run when
  a top changes).

### The CPU's data into console RAM: the room (2026-10-14)
**What's left in cart RAM** (named blocks, allocated sizes; about 600 of
the bytes are used):
- level 1's machinery: `$7C40-$7CFF` (192: variables, the generator's
  entries, the pose search's state) and the allocator `$7D40-$7DFF` (190);
- `$7B`: the fighters' sort (`FS_I`, `FC_*`) and the band lists' tails
  (`BANDX_A/B`), 256;
- `$57`: the top tables (`TOPLI`, `TOPLX`, `TOPLK0`, `TOPLK1`: 56 each, two
  buffers of `TOPL_MAX`; `TOPLN`, `TOPLBG`, `TOPLD`), 240;
- `FO_HB` (96), the `TP_*` group with the slots' zones (about 110), the
  blitters' `BL_SHV`/`BL_MODE` (3), the story's variables (`$4300`, 15), the
  front boxes' tables (`$5B-$62` heads, `$6300`).

**Console RAM's room, scene by scene** (`romable` and `ramclass` runs):
untouched by the CPU and MARIA in every gameplay scene, about 450 bytes. Nearly all of
it is list pieces' tails the allocator didn't need in these runs
(`L1SEG_*`, `BMSEG_*`, `TPSEG_*`). Bytes no piece, variable or list owns
are a few dozen. So the move doesn't fit by rearranging. Room has to come
from what's dead:
- **the fast fill's RAM**, `$2600-$277F` (384): free in every scene once no
  scene fills the bitmap. Only the attract loop still could;
- the front boxes' tables and code: the attract loop's only;
- the fighters' tables' unused slots (about 150, at each table's stride);
- the old fill patch writes, the story's dead buffers.

**The user:** the attract loop first; it frees the fast fill's RAM.

### The attract loop: what it draws (2026-10-14)
Scene 0 (`$D0` 0 throughout; the earlier "scene 1 in the attract" was
playkey's first key starting a game) with no set: everything after the
story goes through the blitter into the bitmap. Captured with
`probes/tmp-s0cap.lua`, which runs `p7800-staterec.lua` and
`p7800-l1cap.lua` together, with no input, 297 pictures to frame 9,000:
- pictures 2-56: a room with door frames (`$964A`/`$96CE` posts, the art
  bank's figures `$9743-$9FC4`);
- 57-116: the princess's room (`$B4C4-$BAD0`: floor, bed, bed foot), then
  Akuma's poses (`$AD30-$B029`);
- 117-295: level 1's cliff and the gate fight, scrolled (V 108-192). Its
  images (`$A3C5-$AB94`, `$A684-$A87B`) are level 1's: scene 0's pages
  `$A4-$AB` are byte for byte level 1's.

**Phases in cart RAM** (`probes/tmp-cramph.lua`): the title clears; the
story writes only its variables (`$4300`); the room scenes and the fight
draw the bitmap (`$58-$72`) with the front boxes, the top tables and the
band.

**Tool fixes on the way:**
- `p7800-l1cap.lua` logged no blits: `FT_IN` (`$6306`, a bitmap page's
  head) holds `$FF` in scene 0, and the probe wanted 0. `BlitBank` treats
  anything but 1-3 as no fighter; the probe now does too. `GLYOK=1` keeps
  blits with the glyphs in (scene 0 keeps them in after its story).
- `p7800-staterec.lua`: `ANYSCENE=1` records with `$D0` 0.
- Two probes in one run: both name a tap `T1`, and the second replaced the
  first. The wrapper keeps the first's.

### More shapes (2026-10-14)
The four sets used all 127 shapes: an instance's byte holds the shape's
index and the "drawn" mark (bit 7). Scene 0's set needs more.
- **Shapes by set:** the build orders them by set, then by the image's low
  byte. Each set's run is contiguous (`L1L_KB`, `L1L_KE`), and `L1K_F32` has
  a 32-byte block a set (`L1_KF` = set x 32).
- **An instance keeps its shape less its set's first** (`L1_KB`): `L1Add`
  subtracts it, and `L1Col`, `L1FillI1` and `L1Zone` add it back before a
  lookup. So 127 shapes a set, 255 in all.
- **`L1Find`** looks in its set's block and stops at its end (`L1_KE`), so
  no set check any more (`L1K_SET` and `L1G_KSET` are gone).
- **`L1Gen`** walks only its set's shapes (`L1G_S` from `L1L_KB`, to
  `L1G_KE`). Its record address keeps the carry of 2 x the shape.
- **Checks:** `scenecheck.sh` identical in all six scenes. The level 3
  replay differs from the pose build's only in the fighters' band (a step
  apart: the in-place top lists changed the timing).

**Also found:** `L1SEG_CART` (`$7310-$78FF`, level 1's band lists'
overflow into cart RAM) overlaps the slice pages where levels 3 and 4 now
keep Akuma's and the hawk's cells. Different scenes, so no clash today. No
run overflowed into it. It has to go for the rules anyway.

### The attract loop as tiles (2026-10-14)
**Result:** scene 0 has a tiles set (set 4, "attract"). After its load,
nothing in the attract loop draws or writes the bitmap: the blitter, the
fills and the fast fill are gone from every scene that plays.
- **The set:** level 1's play lists, zones, row backgrounds and window
  blocks: the attract shows its cell, the princess's room and the gate
  through `$1908`/`$19B3`, level 1's lists (`probes/tmp-dlidx.lua`).
  - Its worlds (`port/worldcfg.py` `CFG[0]`, `port/s0world.txt`): "0g",
    level 1's world 0's images, scrolled, V 108-192, no wrap; "0c" the cell
    (the right door frame, `$964A` A row 60, marks it); "0p" the princess's
    room (`$B7C8`). The gate's markers: `$A68A`, `$AA11`, `$AA7D`.
  - 58 shapes, 282 windows, 7,350 bytes of cart RAM, all written at the
    load.
- **The world list's fixes** (each a `CFG[0]` setting):
  - `drop_fills`: the gate's first clear (rows 76-118 black) and the
    fighters' box erases (77-118 black). They paint the base only, and the
    world list placed them over the sea and the fence.
  - The rails (`$AA11`, drawn every 8 pixels at row 69 as the view moves:
    each place seen once) are the base's rows 69-76, as level 1's rails are
    its buffer's background.
  - `front_cols`: the fight's left post (`$A684`) is drawn piece by piece,
    rows 65-135, after the fighters: one column shape in front, its first
    piece's draw the column's (a "column" marker). `tiles_inventory` and
    `probes/tilemodel.py` take columns now.
  - The model: every picture within 100 pixels (the worst 44).

**Faults found on the way:**
- **The door frames broke in levels 2-4:** the records lost their width
  (below), and `L1Obj` and `L1Gen` took it from `L1K_W`, whose bit 7 marks
  a front shape. Masked now.
- **The story and the title were garbage:** `FrameChT` drops the lists'
  CHBASE table when a set is on (level 1's tiles set CHBASE at each flip).
  It keeps it now while the title's or story's text shows. `L1FlipF` also
  waits then, so the window keeps bank 0, whose MARIA copy holds the
  text's characters.
  - **Dead ends:** the story's CTRL copy (`S_SSH`): it is only compared,
    never written to CTRL. A guard in `L1Call` itself: right, but it cost
    2% of level 1's frames. On the flip alone it costs nothing (the clean
    run's frames are the same as before).
- **A strip of rows missing in the cell:** scene 0's band pieces
  (`S0SEG_*`) ran out with a tiles set's lists. They now leave the bottom
  zones' lists alone (`L1BOT`, `L1BOTB`) and take the fast fill's old RAM,
  as levels 2-4's do.

**ROM was the hard part** (scene 0's tables, records and stream, about 3K):
- **Shapes 128 on:** `L1Rec`'s 2 x the shape lost its carry; a second path
  reads the index's second page now.
- **Records lost their flags and width** (370 bytes in bank 6): `L1Obj`
  and `L1Gen` read `L1K_FL`/`L1K_W` instead. `L1Gen` fetches the six
  arrays first (`L1GenKB`: each one's bank); the generator's variables are
  reordered for it.
- **Load-only data to bank 4** (`L1_LDB`): `L1K_LIM`, `L1TSP`.
- **The fast fill's image is gone** (`CopyFill` too): every scene that plays
  has a set, which captures its fills, and `L1Gen` cleared the copy anyway.
  Its code is still assembled, for the symbols the game's patched fill
  entries name. They are never reached.
- **Pieces split** for short runs: `L1ConvP` out of `L1Gen`'s lines (bank
  0), `AkLookP` and `FtAkPairP` out of the fighters' top-bank piece.
- **The tiles' streams' placement:** banks 3 and 2; bank 1 but its largest
  run (level 1's page code takes it after); bank 0's runs of 260 bytes or
  less and bank 4's of 130 or less, ranked last (the `FAR04` pieces, at one
  address in both banks, the load's code and Akuma's poses' table come
  after); not banks 5 or 6. Each other order tried left one bank short:
  bank 1 (level 1's page code), bank 0 (fragmented for the load's code),
  bank 6 (level 1's tables and play code) or bank 4 (Akuma's table).

**A probe pitfall:** under the rules build (`a78.exe`), a Lua read of cart
RAM in a cycle where the CPU fetches an opcode reads `$FF`: the rule that
refuses code in cart RAM can't tell Lua's read from the CPU's. So a tap on
an instruction fetch saw `FT_IN` `$FF` and `p7800-l1cap.lua`'s buffer rows
blank. Captures that read cart RAM run on `a78-0287-bs-norules.exe`.
- Probe changes: `p7800-l1cap.lua` `GLYOK=1` (blits with the glyphs in);
  `p7800-staterec.lua` `ANYSCENE=1`; `probes/tmp-s0cap.lua` runs both in
  one MAME.

**Checks:**
- `scenecheck.sh`: scenes 1-6 identical to the build before; scene 0 2 of
  800 pictures over 300 pixels, the demo fight at another step (its play
  follows the speed).
- The rules build: no warnings in any scene.
- The clean recording forced: the same frames as the build before.
- Cart RAM in the attract (`tmp-cramph.lua`): the bitmap's pages only at
  the load; then the CPU's data, and pages `$44-$4A`' heads (bytes 0-9)
  once.

**Left:** the front boxes are recorded and copied every picture
(`FtEmitFg`), but no scene draws them any more; the fast fill's RAM is free
for lists in every scene; the CPU's data into console RAM.

**Tools added:** `probes/tmp-s0cap.lua`, `tmp-cramph.lua`,
`tmp-dlidx.lua`, `tmp-storydbg.lua`, `tmp-ramsnap.lua`, `tmp-peekcart.lua`,
`tmp-bbcount.lua`; `BANKMAP=1` (build7800: a bank's map when a piece has
no room).

### The front boxes gone (2026-10-15)
No scene draws the bitmap any more, so nothing is drawn in front of the
fighters but a tiles set's front shapes. The front boxes' recorder
(`FgRec`, `FgRecB`, `FgBox*`, `FgSide*`), the copy of the recorded boxes
to the shown ones (`FtEmitNew`'s `FtEmitFg`, `FtCopyRec`'s), `FtSame`'s
comparison of them and the band's front-box writer (`BandWXC`'s count,
`BandWFront`) are removed. Kept: `FgRecF`/`FgRecFB` (a tiles set's captured
fill erases a stale hit star), `FgStale`, `FT_SEEN`, `FT_IN`.
- **ROM:** the top bank 1,225 bytes free (was about 120).
- **Cart RAM:** the boxes' tables (`FGR_*`, `FG_*`: the bitmap pages'
  heads `$5B-$62`, `$6300-$6303`) are no longer written or read.
- **Pictures:** `scenecheck.sh` scenes 1-6 identical; scene 0 4 of 800
  differ, the story's line being drawn and one row at the sea's top in the
  first gate picture (50-135 pixels: timing).

**The toolkit and the MAME patch updated** (the user, 2026-10-15): the
local `a7800-toolkit` (d4bbd1b) and `mame-a7800-bankset` (cac5c57) clones
fast-forwarded. The patch now gives MARIA its own address space (`dma` on
`:maria`): taps on the CPU's space see only the CPU. Not yet ported into
our 0.287 build (`port/mame/`). It would make the read probes exact, and
Lua could read cart RAM through MARIA's space without the rules build's
`$FF`.

### Console RAM for the CPU's data: the lists' room (2026-10-15)
**The lists' pieces' use** (`probes/tmp-pieceuse.lua`: the allocators'
pointers at each frame's end; `probes/pieceuse.py`; every scene, the
scripted runs, the no-rules build):

| group | band pieces | band used | top pieces | top used |
|---|---|---|---|---|
| level 1 (rows $00/$08) | 2,409 (1,504 in cart RAM) | 548 | 447 | 222 |
| levels 2-4 ($10/$18) | 1,123 | 475 | 513 | 392 |
| scene 0 ($20/$28) | 1,078 | 943 | 350 | 272 |

- Level 1 fills its first two band pieces a buffer and never reaches the
  rest. Its cart RAM pieces (`L1SEG_CART`, `$7310-$78FF`) were never used.
- **Console RAM now** (`romable.py` on this build): lists 2,315 bytes,
  the union over the scenes; the CPU's data changed in play 722, never
  changed 188, one value a scene 7; graphics 26; dead 369; about 80
  untouched.
- **So:** the groups never show together, but each has its own pieces
  scattered over console RAM. One area for every group's lists, as large
  as the largest group needs (scene 0's 943 + its top 272, with a margin:
  about 1.4K), would free about 900 bytes: room for the CPU's data in cart
  RAM (534 bytes changed in play, about 185 read but constant).
- The runs are scripted ones. Heavier play can need more list room, so the
  area needs a margin; the allocator drops a zone's list when it is full.

### MARIA's own address space in our MAME (2026-10-15)
The patch's change (`mame-a7800-bankset` cac5c57) ported by hand into the
0.287 tree: `port/mame/mame_mariaspace.py`, run after `mame_bankset.py`
and `mame_bsrules.py`.
- **MARIA** has a `dma` space (`AS_DMA`); with `set_own_dmaspace(true)`
  its three fetch paths (`write_line_ram`, `draw_scanline`, `startdma`)
  use it, not the CPU's program space.
- **The driver:** the RAM is shared (`ram_2000`, `ram_1800`, `ram_2200`);
  `maria_mem` is the CPU's read map (TIA, MARIA and RIOT reads, RAM, the
  cartridge's `read_40xx`, `bios_or_cart_r`); the extra cartridge handlers
  (HSC, POKEY boards) are installed in both spaces. The rules' handler on
  `$4000-$7FFF` (no code fetched from cart RAM) stays on the CPU's space.
- **Lua:** `manager.machine.devices[":maria"].spaces["dma"]`. A read
  there isn't the CPU's, so the rules build's `$FF` for reads during an
  opcode fetch doesn't touch it: cart RAM read through MARIA's space is
  always what is there.
- **Checks** (`probes/tmp-mariaspace.lua`): level 3, 100 frames: MARIA's
  space 196,000 console RAM reads (its lists), 6,200 in cart RAM, 25,900
  in the window; the CPU's space 4,000 in cart RAM, its own. `scenecheck.sh`
  with the new `a78.exe`: every picture identical to the build before
  (`a78-0287-bs-rules-beforemaria.exe`), no rules warnings.
- **Not ported to** `a78-0287-bs-oldtiming.exe`, the replays' MAME (the
  recordings' input timing).

### Console RAM for the CPU's data: the budget (2026-10-15)
**Console RAM by byte** (`probes/consolemap.py`, this build's `romable`
classes and the pieces' symbols): list pieces 1,843 (every group's,
united), other lists and DLLs 511, the CPU's data 919, dead 266 (mostly the
fighters' tables' unused slots, `$1B80-$1DF5`), graphics 20, zero page and
stack 384, untouched 153.

**The cart RAM to bring over** (this build): 719 bytes the CPU reads.
Their blocks, as allocated: the top tables `TOPL*` 240; level 1's
variables, `TP_*` and the blitters' `BL_*` (`$7C`) about 250; the fighters'
sort `FS_I`, `FC_*` and 9 bytes of `BANDX_A` (`$7B`) 79; `FO_HB` 80; the top
slots' zones `TOPZ_*` 45; the allocator's `L1_SG*` 17; the story's
variables 15; `FT_SEEN`/`FT_IN` 4; the game's own at `$4000-$4007` 8. About
740 in all.
- **Dead blocks found:** `BANDX_A/B` and `BAND_HEADS` are the old band
  writer's overflow into cart RAM (the bitmap's page heads and page
  `$7B`'s tail), taken only with `S_BLPC` `$FF` (no scene that plays);
  `L1_SGK` is one byte (the 176 after it unused); `TP_T2`'s 196 are the old
  slots' page, unused.

**Where it could go:**
- the list pieces moved into four regions every group shares
  (`$1852-$1A08`, `$2410-$24FF`, `$2510-$25FF`, `$2600-$277F`, and the DLL
  pages' tails: about 1,500 bytes) frees the scattered ones, about 380;
- the untouched bytes, about 150;
- the fighters' tables' dead slots, up to about 250 (their layout
  changed);
- console RAM's constants to ROM, about 190.

**The cost:** the heaviest group's lists (the attract's, 1,335 at their
measured peak, band and top) in about 1,500 bytes: about 10% over the peak,
where the scattered pieces leave about 40% now. A list that doesn't fit is
dropped (a zone shows nothing that picture).

### One set of list pieces: a dead end (2026-10-15)
**The user:** move the CPU's data in, a 10% margin for the lists. **The
idea:** every scene takes scene 0's pieces (`L1L_BLPC` `$20`), the groups
never show together, so the other groups' pieces free up (about 415 bytes
by the pieces' union). **What happened:**
- Level 1 and the vs fight lost band zones: scene 0's band pieces include
  `$1900-$1A08`, where level 1's and scene 6's scene variables are carved
  (`CARVE_SDATA`; scene 0 carves there too, but its are dead after the
  load). Level 1 and scene 6 then needed their own set, and with no
  `$1900-$1A08` it took the text's list RAM (`$2410-$24C0`,
  `$2510-$25A3`), which scene 0's title and story need, so scene 0 can't
  have it.
- Levels 2-4's top lists outgrew scene 0's top pieces (198 and 194 a
  buffer measured, more over the scene check's 30,000 frames: one top zone
  dropped, a whole line black at the band's top) and need a piece longer
  than a list (58 bytes) in each buffer; widening them took room from
  scene 0's band B, which then dropped objects in the attract.
- **The union of the pieces in use went from 1,843 to 1,800 bytes:** the
  sets differ where each scene's own data differs, so sharing frees almost
  nothing. Reverted: the cart is byte-identical to
  `2026-10-15_KEEP_enh-nofrontboxes` again.
- `probes/consolemap.py` takes `ACTIVE` (the piece sets in use).

**The real budget** (this build, `romable`/`consolemap`):
- console RAM less zero page and stack (384), the DLLs and the other
  fixed lists (511), graphics (20): 3,181 bytes for the pieces and the CPU's
  data;
- the CPU's data: console RAM's 947, its dead slots 301, cart RAM's 740:
  about 1,690 with the dead slots reclaimed (the fighters' tables laid out
  again), about 1,990 without;
- the lists: the attract's peak 1,215 (14,000 frames), more over longer
  runs; each scene's lists must avoid that scene's live data (carves,
  text), so the pieces can't simply be shared.
- So it only fits with a console RAM laid out scene by scene, the
  fighters' tables compacted and some constants in ROM, about 150-250
  bytes spare. A large re-layout with thin margins.

### Console RAM laid out scene by scene: the measurement (2026-10-15)
**The user:** the full re-layout. **The tool:** `probes/tmp-ramlive.lua`
(per byte, per scene bank and phase, L the load under the blank list, T the
title's or story's text, P play: the CPU's data reads, its writes, MARIA's
reads, these from MARIA's own space now) and `probes/ramlive.py`; the scene
check's full lengths, every scene.

**Each scene's room** (bytes it uses for nothing but its own list pieces,
in play and text; a load's writes count only if read later):

| scene | other use | its lists | room |
|---|---|---|---|
| 0 | 1,869 | 1,215 | 1,843 |
| 1 | 1,688 | 1,006 | 2,024 |
| 2 | 1,600 | 855 | 2,112 |
| 3 | 1,602 | 611 | 2,110 |
| 4 | 769 | 500 | 2,943 |
| 6 | 1,053 | 606 | 2,659 |

- **Scene 0's text and play don't overlap:** no list is written into a piece
  while the text shows (only MARIA reads old band lists in the text's
  first frame), and the 316 bytes only the text uses are all rewritten each
  time it runs. So scene 0's play lists may share them: its room in play is
  2,159.
- **Free of other use in every scene:** 1,287 bytes; less the DLL pages'
  tails (a longer DLL reaches `$226F`/`$236F`), the bottom lists' slack and
  the generator's load scratch, about 1,140.
- **The lists by row** (band A, band B, top A, top B; bytes touched): scene
  0 448, 495, 136, 136; level 1 295, 304, 204, 203; level 2 234, 232, 207,
  182; levels 3 and 4 less.
- **The fighters' tables** hold little dead room: `ZT_BLO` and `ZT_BHI` (the
  old band writer's, 64 bytes) are almost never read; the zone tables use
  11 of each buffer's 16 slots (about 30 more). The rest is used.
- **The blocks to move,** exactly: the fighters' sort (A at +0, B at +$80:
  a 207-byte span with a 49-byte gap), level 1's variables 185 (cleared as
  one), the allocator 17, the `TP_*` group with `BL_*` 60, the top tables
  230, `FO_HB` 80, the slots' zones 45, the story's scratch 16,
  `FT_SEEN`/`FT_IN` 4: about 800. Then the game's own `$4000-$4007` and
  `$4A00` (in its old framebuffer; carves).

**So:** the blocks take about 800 of the 1,140 free everywhere; scene 0's
lists get the other 340 and the 870 only scene 0 leaves: about 1,210 for a
peak of 1,215. No room to spare for the attract (its demo is the same each
time, so its peak is its peak). Freeing `ZT_BLO`/`ZT_BHI` (64) and the sky
row's 20 bytes into ROM would give about 7%.

### Console RAM laid out scene by scene: the attempt, and the stop (2026-10-15)
**The user:** all of it, about 7% for the attract. **The result:** it
doesn't fit without lists dropping in play. The CPU's blocks stay in cart
RAM, at their old addresses; the cuts made for the move stay.

**The cuts (kept, all checked against the front-box build):**
- `ZT_BLO`/`ZT_BHI` (64 bytes, the old band writer's) gone from the
  fighters' tables.
- The sky row's 20 bytes of `$AA` in ROM: the build finds a 20-byte window
  in the block every bank's MARIA copy shares (`mspace.window`, landed at
  `$B5C9`), `TOPSKYROW`; `TopLoadSky`'s copy gone.
- The fast fill's image no longer placed.
- L1Gen's clear: only level 1's variables (`L1VARS_N`, `CPX`), not three
  pages.
- The sort's B half at `+FS_BOFF` rather than a literal `+$80` (`FtSort`,
  `BandW0`, `FC_N+FS_BOFF`). 80 would do in console RAM. Back in cart RAM
  it's `$80` again: scene 5 (`S_BLPC` `$FF`) still uses the old band
  writer, whose overflow goes into the page's tails (`BANDX_A`
  `$7B46-$7B7F`, `BANDX_B` `$7BC6-$7BEF`). At 80 they were 10 bytes.
  **Correction (same day):** I first called scene 5 the ending. The ending
  is in scene 4; scene 5 (scene 0's banks) has appeared in no run and may
  be unused. If it does run, its band lists are in cart RAM (the page
  heads, `$5410-$56FF`, these tails).

**The plan module:** `port/consoleplan_out.py` holds every block's address
(`SORT_AT`, `L1VARS_AT`, `TPB_AT`, `TPDLL_AT`, `TOPZA/H/T_AT`, `SGV_AT`,
`OBJV_AT`, `FTS_AT`) and each scene group's list pieces (`G20_*` scene 0,
`G00_*` level 1 and the vs fight, `G10_*` levels 2-4; band A/B, top A/B);
`layout7800.py` and `l1scene7800.py` read it. `probes/consoleplan.py
SYM PREFIX --write port/consoleplan_out.py` makes one from
`tmp-ramlive.lua`'s runs. It now holds the old layout by hand: the blocks
in cart RAM, the pieces the front-box build's, less level 1's two cart RAM
pieces (never used). Checked against the cut build: identical but for
scene 0's four timing pictures (a line at y 121 changing colour a frame
later), no rules warnings.

**What went wrong, in order:**
1. **The full move:** after the sort (160), level 1's variables (185) and
   the small blocks, the 230 bytes of top tables and `FO_HB` (80) found no
   run: the free-everywhere bytes are in pieces of 14-71. So **HYBRID**:
   the top tables and `FO_HB` stay in cart RAM; the rest (487 bytes) goes.
2. **Levels 2-4 dropped a band zone** (rows 155-174, then 13-18 pictures
   near level 2's gate; 492 in level 3 at first). Not `DESCBUF` (kept
   `$1A2C-$1A4D`; no change), not the bottom lists' tails (kept; no
   change). A DLL walk at the drop: three fighter objects missing from
   mid-band zones. `tmp-bandest.lua`: in play only level 2 drops, 7 times,
   all in band B; the estimates (`S_FL0`, up to 83 bytes) are at most 9 over
   a list's real size.
3. **The measure was wrong.** Bytes touched (`tmp-ramlive.lua`) undercount
   what a row needs: a list takes its estimate's room when placed, and the
   pointers at a frame's end are what matter. `probes/tmp-pieceuse.lua`
   (each row's pointers summed, its largest) on the front-box build:

   | group | band A | band B | top A | top B |
   |---|---|---|---|---|
   | scene 0 | 411 | 411 | 116 | 116 |
   | level 1, vs | 308 | 302 | 116 | 116 |
   | levels 2-4 | 401 | 407 | 166 | 166 |

   Touched had said 448/495 for scene 0 (over) and 234/232 for level 2
   (well under: its buffer B reached 407).
4. **With the true peaks** and margins (attract 6%, levels 12-15%), the
   hybrid plan fits on paper: 487 bytes of blocks, the groups 250, 215 and
   18 bytes left. **Built, it drops more:** scene 0 29 pictures, level 2
   18.

**Why: the pieces.** A list goes whole into one piece, and only if the
piece has room for its estimate. So each piece wastes up to an estimate
(30-80 bytes) at its end, and a row's pointer peak is not its need. The
old layout's pieces are few and long (192, 270 bytes); the plan's are the
room scenes leave, in slices of 22-60 bytes, several barely one list. The
peak plus a margin can't cover a waste of up to about 60 bytes for each of 5-7
pieces. The room there is (about 1,140 free in every scene, about 870 more
only scene 0 leaves) is the right size but in the wrong shape.

**Not tried (each a change with costs):**
- splitting a list over pieces (the band writer can't: one pointer, one
  list);
- estimates closer to the real size (a second counting pass: CPU);
- compacting the fighters' tables and the game's sprite region into long
  runs (most of the "dead" 301 bytes are slack heavier fights use; the
  sprite region is the game's own);
- keeping the CPU's blocks in cart RAM but writing them only at load
  (they're written every frame: they're variables).

**So:** cart RAM stays as it is after these cuts: MARIA's data written at
a scene's load, plus the CPU's blocks (about 800 bytes: the sort, level
1's variables, the allocators, the top tables, `FO_HB`, the slots' zones)
written in play. The checkpoint: `2026-10-15_KEEP_enh-cuts`.

### Console RAM: the lists replayed (2026-10-15)
**The user:** the goal is all of the RAM in console RAM's 4K, so that cart
RAM can become fixed-bank ROM. Then: go ahead with (1) exact list sizes and
(2) smaller blocks.

**The tool:** `probes/tmp-listseq.lua` records every rebuild of every row's
pieces, with the lists placed in it in order:
- band lists: the estimate (what a piece must have room for) and the real
  size;
- top lists: the exact size;
- each rebuild tagged with its phase and scene (`G_ZD0`).

`probes/listsim.py` replays them first-fit in any layout's pieces, as
`BandWL1` and `TpPlace` do.
- **Checked against the game:** the current layout fits everywhere, and its
  peaks equal `tmp-pieceuse.lua`'s (band 308/302, 401/407, 411/411; top
  116, 166, 116). The hybrid plan that dropped lists in the build fails in
  exactly those rows: scene 0's band B, level 2's top B.
- **Three probe traps, all now handled:**
  - The routines are in banked ROM: another bank's code at the same
    address fires the tap. Each tap checks its own operand bytes.
  - A display-list interrupt landing on a routine's first instruction makes
    the CPU fetch that opcode again after the RTI, so an entry tap fires
    twice. Top lists are counted at the placement (`TpPlF`), not the entry.
  - Some top rebuilds' starts went unseen over long runs. A rebuild also
    starts wherever the row's pointers are all at their pieces' starts.

**(1) Exact band sizes: no help.** 79% of band estimates are exact and the
rest are 4-9 over. Replayed with real sizes, the hybrid plan fails just as
often (scene 0's band B, 75 rebuilds). The waste is each piece's unused end.
**Correction:** I had said exact sizes would remove what broke the plan.

**A bug found on the way (fixed):** some band lists were longer than their
estimate: 7 estimated, 15 written; 59 and 63. `L1_FP` (the tiles engine's
pass: 0 all, 1 behind the fighters, 2 in front) stays 1 after a zone with
nothing in front. The next zone's count then skipped its own front
instances. In a tight piece the list would write past the piece's end.
- **Fix:** `BandWrite` counts with `L1_FP` 0.
- **Checked:** `probes/tmp-bandover.lua`, every scene: no list longer than
  its estimate. Scene check identical to the cut build, but for scene 0's
  one-line timing pictures.

**(2) Smaller blocks: mostly not possible.**
- **Top entries:** the scripted runs reach 13 of `TOPL_MAX` 28, but the
  user's clean recording reaches **25**. The tables stay at 28.
- **Fighter objects:** 31 of 40 in the scripted runs, **34** in the level 3
  recording (Akuma, the hawk). A capacity of 36 would leave 2.
- **Level objects:** 21 of 24.
- **Akuma's pose search state** (`AKP_*`): `FtObj` reads it in play while
  Akuma or the hawk is drawn; it is only back to 0 by a frame's end. Not
  load-only.
- **Akuma's capture tables** (`AK_*`, `$1AA1-$1B4E`) are live: level 2's
  fights use them.
- The status lists (`$1F80-$2017`, 76 bytes a buffer) are what they
  reserve.
(`probes/tmp-tabmax.lua` scripted and under `port/replay.sh`. The level 3
recording's state record `strec` had to be made again: `p7800-staterec.lua`
on the old-timing MAME, 2,725 flips as before.)

**The plan:** `probes/consoleplan2.py`.
- The blocks are placed at run ends, outside the tightest group's long runs.
- Each row then takes runs until the replay of all its rebuilds passes with
  every list grown by the margin.
- The list demand comes from the scripted runs and both recordings'
  replays.

Results (bytes left; margins attract / level 1 / levels 2-4):

| case | attract | level 1, vs | levels 2-4 |
|---|---|---|---|
| all blocks, top tables 28 (7/10/10%) | no | 234 | no |
| margins 0% | 74 | 234 | no |
| fighter capacity 36, margins 0% | 84 | 246 | no |
| top tables at 16 (impossible: 25 seen), capacity 36, scripted demand only | 115 | 384 | 0 |
| 118 bytes elsewhere (`TOPLK0/1`, `TOPLN/BG/D`) | 117 | 373 | no; 18 at 5% |
| 310 bytes elsewhere (the top tables, `FO_HB`) | 359 | 599 | 236 |

**Also tried:**
- **A fourth group** (level 2 alone): level 2 is itself the tight one. Its
  room equals levels 2-4's (1,410). Scenes 3 and 4 alone would have 514 to
  spare.
- **Lists over Akuma's tables:** level 2 uses them.

**So:** with this display design the lists and the CPU's blocks don't both
fit in console RAM. Levels 2-4 fail even with no margin. The blocks stay in
cart RAM. What would change it:
- about 310 bytes of CPU-only RAM elsewhere. The RIOT's 128 bytes
  (`$0480-$04FF`) are CPU-only, but whether they can be used in 7800 mode
  needs checking on hardware, and they cover only part of it;
- or less list RAM: lists in one buffer instead of two, or cheaper lists.

**Tools added:** `probes/tmp-listseq.lua`, `probes/listsim.py`,
`probes/consoleplan2.py`; `probes/tmp-topfail.lua`, `tmp-tptrace.lua`,
`tmp-bandover.lua`, `tmp-tabmax.lua` (debug).

### What in RAM is redundant (2026-10-15)
**The user:**
- The RIOT's RAM is unreliable in 7800 mode.
- A redesign of the lists (one buffer) is out.
- Is there RAM that can be consolidated, or inferred from other RAM? And
  the fixed ROM's plan may make some RAM unnecessary.

**The inventory:** `probes/raminv.py` merges, per byte:
- `tmp-romable.lua`'s CPU classes: every scene scripted, and both
  recordings under `port/replay.sh`;
- `tmp-ramlive.lua`'s MARIA reads: the scripted runs only. The old-timing
  MAME the replays need has no MARIA space.

It then sums the classes by variable.

| class | console RAM | the CPU's blocks in cart RAM |
|---|---|---|
| MARIA reads it (lists, graphics) | 2,205 | |
| real RAM (changed in play) | 877 | 677 |
| constant in play | 154 | 70 |
| dead (written, never read) | 110 | |
| never touched | 354 | |

The constants and the never-touched bytes are mostly the tables' unused
capacity:
- the fighter tables' last 15 entries each, the zone tables' last 10;
- the DLLs' and bottom lists' tails;
- 84 bytes past `LS_50` (`$1DAC-$1DFF`);
- entries past a table's count, cleared and read.

The real constants are a few dozen bytes.

**Copies:** the port keeps two of most things, one per picture buffer. The
question is which pairs it really needs both of.
`probes/tmp-abshare.lua` tracks, for each A/B pair and each offset, which
half wrote last. It flags a CPU read of one half whose offset the other
half wrote later: with one copy, that read would see the other buffer's
value.
- It counts only the instruction's own effective address, decoded as
  `tmp-romable.lua` does. Stores are left out: an indexed `STA` reads its
  target first.
- Its taps are kept in a global: a local table of taps is collected, and
  the taps go with it.

Over every scene and both recordings:

| pair | conflicts |
|---|---|
| `FO_CELL`, `FO_X`, `FO_PW`, `FO_LO`, `FO_HB` (the fighter objects) | **none**, in over 1.5 million reads |
| the sort (`FS_I`, `FC_*`) | only in `BandWrite` (`$8949`, `FC_N`), in the frames just after a scene starts (676-677 in every run; scene 0's restarts) |
| the status lists | only `CopyStAB`, which copies one into the other: they are kept the same on purpose |
| the zone tables, level objects, top tables, top slots | many frames: both copies are needed |

**Why the fighter objects can share:** `FtEmit` records a buffer's objects,
sorts them and rewrites its band lists in one go (`FtSort`,
`BandRefresh`). A DLL build for a buffer comes at its flip, after its own
`FtEmit`. Nothing reads one buffer's objects once the other's are written.

**The plan with copies shared** (`probes/consoleplan2.py`, `SHARE`; the
measured use remapped as the shared layout would have it; top tables at 28,
fighter capacity 40; margins 7% attract, 10% levels):

| shared | attract left | level 1, vs | levels 2-4 |
|---|---|---|---|
| none | no | 234 | no |
| fighter objects (160 bytes of console RAM, 40 of `FO_HB`) | 221 | 455 | 66 |
| + the sort (80) | 299 | 535 | 179 |
| + the status lists (76) | 364 | 608 | 286 |

So the move fits once the fighter objects and the sort have one copy each.
- **Still to check:** the sort's conflict at a scene's start is a load's
  rebuild (to confirm in the scene check).
- **The status lists:** one copy means writing a list MARIA is showing (the
  health arrows). It needs the write in the vertical blank, or one frame's
  tear accepted. It isn't needed for the fit.

**The fixed ROM's part:** two RAM items exist only because their source
isn't always mapped:
- `DESCBUF` (64 bytes): the builder's copy of the game's list description.
  From the fixed bank it could be read in place.
- The NMI stub (about 26 bytes of code at `$27CD`, patched for the title's
  and story's DLIs): two pointers in RAM and code in the fixed bank would
  do.

Neither is needed for the fit.

**Tools added:** `probes/raminv.py`, `probes/tmp-abshare.lua`;
`consoleplan2.py`'s `SHARE`, `ELSEWHERE`, `FT_FON`, `TOPL_MAX`, `GROW20`,
`GROW10`, `SPLIT` what-ifs. `tmp-romable.lua` and `tmp-ramlive.lua` no
longer load `playkey.lua` under `port/replay.sh` (`PLAYBACK`).

### The CPU's data out of cart RAM (2026-10-15)
**The user:** go for it: one copy where two aren't needed, then the CPU's
data into console RAM.

**Result:** outside loads, the CPU no longer writes cart RAM in any run: the
six scenes scripted, and both recordings replayed (the clean run, levels
1-4; level 3 and the finale). Every block is in console RAM. Margins: 7%
attract, 10% levels, the top tables at 28. Scene check identical to the cut
build, but for scene 0's timing pictures (190; the one-line colour change at
y 121), with no rules warnings. Checkpoint: `2026-10-15_KEEP_enh-cpuout`.

**What it took:**
1. **One copy for both buffers:**
   - The fighter objects (`FO_CELL`, `FO_X`, `FO_PW`, `FO_LO`, `FO_HB`): B's
     are at `FO_BOFF` 0, over A's (`FtSort`, `FtObj`). The fighters' tables
     are 160 bytes shorter (end `$1D0C`).
   - The sort (`FS_I`, `FC_*`, the cells' next places): B's are at
     `FS_BOFF` 0. Scene 5's old band writer (`S_BLPC` `$FF`) loses its
     overflow room: it would drop objects.
   - Its scene check alone was identical too. So the sort's conflict at a
     scene's start is not seen.
2. **The small-sprite block** (`$1B80-$1DF5`, `LEN_SPRITES` 630) holds the
   text's glyphs whenever text is up, a level's "the end" included. The
   fighters' tables live there in play because nothing reads them while
   the block is in (`S_GLYIN`).
   - The sort and `FO_HB` have the same life (`FtEmit`'s), so they go after
     the tables there (`$1D0C`, `$1D5C`).
   - No list or other block uses the block.
3. **Smaller:**
   - `TP_DLL` keeps the low bytes only; the page is the buffer's DLL's
     (`TpDll`). 20 bytes.
   - The status lists are 57 bytes each (`StBuild`'s 11 objects of 5 and
     the end), B right after A.
4. **Level 1's variables in three blocks:**
   - The instances' four tables as one, `L1OBJ` (96). B's are reached at
     A's + 2 x `L1_NMAX`, so they stay together. They need no clear: every
     read is below the count (`L1_E`), and `L1Copy` copies the counts too.
   - The rest in two halves of 45 (`L1VARS`, `L1VARB`), one clear loop.
   - With one 185-byte block, only one free run took it, and it cut levels
     2-4's long run in two.
5. **The game's own data in cart RAM, carved into console RAM**
   (`CARVE_ENGINE1`):
   - the sound's zero-page swap (`$258D`'s routine swaps `$00-$07` with XE
     `$3000-$3007`, every frame): `GSWAP`, `$1DF6`;
   - a state save of 15 variables (XE `$47F7-$4806`, between the buffers:
     `$B9C4` saves, `$BA1D` restores): `GSAVE`, `$1FF2`.
   - **Correction:** I first carved `$30FF-$310E` for the save, reading
     7800 `$40FF` back as XE `$30FF`. `fb_home` isn't an offset: inverted,
     7800 `$40FF` is XE `$47F7`.
6. **The status bar's arrow strips in MARIA's ROM:** `StInit` made them at
   the first clear (7 rows of 10 bytes at cart RAM's page heads `$44-$4A`).
   It also read `ST_PS` (`$4A00`) at every status draw to see whether they
   were made. Now the build places them as a 10 x 7 window in the block
   every bank's MARIA copy shares (`mspace.window`, like `TOPSKYROW`):
   `ST_HI` `$AF`, `ST_PLO` `$37`, `ST_FLO` `$3C`. `StInit` is gone.

**A dead end on the way:** the first full build broke levels 2-4: no floor,
and the fighters elsewhere (the game's own state).
- The blocks sat on bytes used at loads: the zero page's swap buffer
  (`$1880-$18FF`, level 2's loads) and scene 0's load scratch
  (`$1900-$190A`).
- The planner had subtracted the measured build's list pieces from the
  load-time use too, and those pieces held the swap buffer at loads.
- Blocks live through loads, so they now avoid all load-time use. Lists
  may share it: they are rebuilt after a load.

**Not taken: one status list.** The two lists differ on purpose: a
fighter's arrows below 3 blink, shown in A and not in B. `tmp-abshare.lua`
watches the CPU's reads only, so it missed that MARIA reads both.

**The plan:** `probes/consoleplan2.py`,
`SHARE=fo,sort,tpdll,stsize,l1split,gram`.
- **Demand:** the scripted runs and both recordings.
- **Use:** `tmp-ramlive.lua`, plus the recordings' `tmp-romable.lua`
  (`ROMABLE`).
- **Placement:** a load's use kept apart from the blocks.
- **Result:** blocks 562 bytes; bytes left: attract 154, level 1 and the vs
  fight 438, levels 2-4 38.
- **Replayed** (`listsim.py`) against the built pieces, every rebuild
  recorded: no failures as recorded, none with every list 7% longer, and at
  10% only the attract's (its margin is 7%).

**What the CPU still does with cart RAM** (`probes/tmp-cramuse.lua`: its
writes and its own reads, by phase, page or address, and PC; `CURPC` gives
the same PCs as `PC`):
- **At loads, it writes MARIA's data** (the pseudo-ROM): the tiles
  generator (`L1GenLK3`, `L1TPut`, `L1GenZ1`, pages `$40-$7A`), the
  fighters' slices and Akuma's and the hawk's pre-cut poses (`FtRow*`,
  `FtClr*`, `FtBlk2`, `$58-$7A`). That is the next step: the data into ROM.
- **Outside loads, five single reads,** each once or a few times in all the
  runs: `$711E` (PC `$9165`), `$70xx` (`$8F97`), `$6Axx` (`$A434`), `$5555`
  (`$9129`), `$543E` (`$BB15`). Banked PCs: the symbol names at those
  addresses may be another bank's. Reads of load-time data, not CPU data.
- **A false alarm:** the clean recording's replay with `tmp-cramuse.lua`
  ended at 10,867 frames, against 16,956 before. With the same light
  companion (`tmp-tabmax.lua`) both builds take 16,956 frames: the move
  changes no speed.

### The ROM by scene: the plan (2026-10-15)
**The user:**
- the graphics left in the CPU's ROM go to MARIA's;
- the shared code and data go in the CPU's fixed banks, the shared graphics
  in MARIA's;
- each scene's code, data and graphics go on its own page, each side;
- the game stays on that page through the scene.

**The cartridge allows it as it is.** On a BankSet cartridge without bank
RAM, the second-last bank is fixed at `$4000` on each side (the a7800 fork's
`bankset.cpp`, modelled in the toolkit: `docs/cartridges.md`). With the RAM
bit dropped, each side is:
- banks 0-5 in the window at `$8000`;
- bank 6 fixed at `$4000`;
- bank 7 fixed at `$C000`.

So 32K is fixed on each side and 16K is a page. No bigger cartridge.

**Measured** (`probes/tmp-romuse.lua`, `probes/romuse.py`, `probes/tmp-banksw.lua`;
the six scenes scripted, both recordings replayed; from the port's boot clear
on, since the BIOS reads the fixed bank for its signature check):
- **Bank switches in play:** about 50 a frame. Each scene goes between its
  own bank, bank 5 (the top-bank system code) and bank 6 (level 1's
  engine, the fighters' records); level 1: 170K, 159K and 147K over 9,565
  frames.
- **MARIA reads its window through the CPU's bank:** in every scene MARIA
  fetched from banks 5 and 6 (mid-frame switches). That is why each MARIA
  window bank is the same copy today: 32K of MARIA's ROM is shared, 2,952
  bytes free.
- **The CPU's banks in play** (bytes executed or read; "never": not in any
  run, which are all invincible: no death, no game over, pause, two players,
  scene 5):

  | bank | play | loads only | never |
  |---|---|---|---|
  | fixed (7) | 6,661 | 346 | 9,552 |
  | 5 (top bank) | 5,796 | 356 | 8,924 |
  | 6 (art bank) | 14,808 | 3,474 | 4,803 |
  | scenes 0-4 | 2,654-6,027 each | 2,708-5,154 | about 10-11K |

  (Bank 6's "art" is counted wrongly here: level 1's code and tables sit
  over the art bank's released part, and `romuse.py` credits every item a
  byte is under. Its reads in play are `L1Obj`, `L1Rec`, `L1BlitK`.)
- **Each scene's load-time MARIA data** (now built in cart RAM): level 1
  5,725 bytes, level 2 6,829, level 3 7,005, level 4 9,315, the attract
  7,282 (the tiles' windows), plus the slice pages (`$73-$7A`) and Akuma's
  and the hawk's poses.

**The cycle:**
1. A scene's own graphics can only be in its MARIA page once play stops
   switching banks: MARIA reads through the CPU's bank.
2. Play can only stop switching once the shared code is in fixed banks: the
   CPU's fixed bank has 0.8K free, and the second fixed bank (`$4000`)
   exists only once cart RAM is gone.
3. Cart RAM can only go once the load-time data is in MARIA's pages.

So the last steps land together, in one build, behind a build switch: the
current layout keeps building.

**The steps:**
1. **The load-time data from the build.** The build has the tiles' windows
   (it streams them now), the slices and the poses. It writes them as
   images, and a probe compares them byte for byte with cart RAM after each
   scene's load. No change to the game.
2. **Every item placed by its use:**
   - shared in play: the CPU's `$C000` and `$4000`;
   - one scene's: its page;
   - load-only: its page (a load may switch: the screen is blank);
   - never seen: beside its callers.

   A coverage pass first, to shrink "never": the plain cartridge scripted
   (deaths, game over), pause, the ending.

   The budget: the shared code is about 38K for 32K (fixed 16.5K, bank 5's
   code 13.7K, level 1's engine and tables, the fighters' records). So it
   needs:
   - the dead port code out (the blitter era's, in bank 5's 8.9K never
     run);
   - the generator's code out (step 1 makes it build-time);
   - the game's common code (2.3K) left copied in each page.
3. **The new layout** (`--rom v2`):
   - MARIA: the shared graphics (the fighters' parts and heads, the stars,
     the sky row, the status strips) in banks 6 and 7; each scene's tiles'
     characters and windows, its top data, its text, its poses and slices
     in its page.
   - The CPU: far calls in play become plain calls.
   - The header loses the RAM bit.
4. **Checks:**
   - rules MAME: any cart RAM write now hits ROM;
   - the scene check against today's build;
   - both recordings;
   - `tmp-banksw.lua`: no switch in play;
   - the speed (50 fewer switches a frame).
5. **Then** what's left of the fixed banks is the room the user wanted.

**Tools added:** `probes/tmp-romuse.lua`, `probes/romuse.py`,
`probes/tmp-banksw.lua`, `probes/tmp-artread.lua` (debug), `probes/tmp-cramuse.lua`.

### The ROM by scene: step 1, the loads' data from the build (2026-10-15)
**The user:** yes, start.

**Result:** the build knows every byte of each scene's load-time MARIA data,
and it matches cart RAM after the load, byte for byte, in every scene. The
6502 code that makes it at the load can go once the data is in MARIA's
pages.

| scene | the build's bytes | of which poses | match |
|---|---|---|---|
| 0 (attract) | 7,570 | | all |
| 1 (level 1; scene 6 the same set) | 6,013 | | all |
| 2 | 7,117 | | all |
| 3 | 7,293 | 3,882 | all |
| 4 | 9,603 | 4,286 | all |

**How:**
- The build writes `<cart>.loadimg`: each scene's cart RAM after its load,
  16K of bytes and 16K of flags (1 tiles, map rows and windows; 2 a pose's
  cell; 3 the black block).
  - The tiles' part comes from each set's `Pages`, the bytes it took, and
    its reserved characters (`Pages.reserved`: a reserved character byte
    may be 0, so "used" alone can't tell it from a byte outside the
    blocks).
  - The build already checked its windows against `generate`, the twin of
    the 6502 generator.
- **The poses:** `akpose7800.cut`, a twin of the load's cutting (`AkPre`:
  `FtPlain` in render mode, `FtObj`'s place from the table, `FtCopy`, and
  `FtRow`/`FtRowM`/`FtRowK`/`FtRowP2`: a pair's merge for Akuma's and the
  hawk's). `FT_MIR` ($F500) is the pixels' reversal, checked against the
  cart.
- `probes/tmp-loadcap.lua` saves cart RAM at the end of the first frame
  after each scene's first load (no-rules MAME). `probes/loadcmp.py`
  compares, and counts what MARIA fetched from cart RAM
  (`tmp-romuse.lua`'s "C") that the build has no byte for.

**On the way:**
- **Scene 1's 23 "differences" were my export's:** two sets list scene 1,
  and copying a set's whole blocks let the second set's zeros overwrite the
  first's characters. Only the bytes a set took count now.
- **MARIA's only fetches outside the build's bytes:** the first byte of
  pages `$7A-$7F`, every scene. It is `L1Tiles`'s mode header (`00 40 7A 1F
  A0`: 160A, width 1, at x 160, off the screen's right), there so a list
  starts in 160A whatever the zone before ended in. The byte is fetched,
  not seen: any ROM byte does.
- **The black block** (`FtBlack`: `$AA` in columns 240-255 of the slice
  pages, the front boxes' underlay) is read by MARIA in no scene: dead
  since the front boxes went. `FtBlack`'s clear of the cells' counts stays.
- Scene 6 has no capture of its own: its load ends with `G_ZD0` 1 (level
  1's set, the same bytes).

**Next, step 2:** a coverage pass (the plain cartridge's deaths and game
over, pause, the ending), then every item placed by its use.

### The ROM by scene: step 2, the ledger (2026-10-15)
**Coverage:**
- The six scenes scripted on the invincible kit, both recordings
  replayed, and the plain cartridge scripted in levels 1-4 (deaths, game
  over: the scripted player dies in levels 2 and 3 and starts again).
- The plain cartridge adds little: 17-55 bytes of code a kind.
- **Never reached:** the ending (`EndText`, banks 0 and 4, ran in no run:
  the level 3 recording stops before it), pause, two players, scene 5.
  Their code is placed by where it lives and what it calls, not by
  measurement.

**Tools:**
- `probes/romroutines.py`: each label of `sys7800.asm` by its piece
  (`FAR` and the main block: the fixed bank; `FARART`: the top bank;
  `FARL1`/`FARL2`: bank 6; `FARL0`: bank 0; `FAR04`: banks 0 and 4;
  `SCENEPAGE`; `LEVEL1PAGE`), its bytes to the next label, run in play,
  at loads only, or never.
- `probes/romplan.py`: each map item's bytes, a byte belonging to the
  smallest item over it. **Correction:** `romuse.py` credited every item
  over a byte, so level 1's code over the art bank's released part showed
  as "art read in play".

**The port's code, per routine** (bytes to the next label):

| piece kind | play | loads only | never |
|---|---|---|---|
| `FARART` (bank 5) | 8,977 | 233 | 1,225 |
| main block | 2,308 | 92 | 267 |
| `FAR` (fixed) | 583 | 471 | 286 |
| `FARL1`, `FARL2` (bank 6) | 1,669 | 0 | 91 |
| `FAR04` (banks 0, 4) | 1,329 | 0 | 15 |
| `LEVEL1PAGE` | 1,416 | 1 | 466 |
| `FARL0` (the generator) | 946 | 0 | 66 |

So bank 5's "never" (7,812 bytes) is mostly its generated tables and
padding, not code. The fixed bank's never-run code is mostly the blitters
(`BlRom*`, `RowBase`): no scene uses them now.

**The ledger** (bytes used in play by more than one scene, by one, only at
loads, never):
- **Fixed today:** the game's bank 15 code 3,458 / 713 / 2 / 4,077; engine
  part 2 667 / 235 / 5 / 2,007; system code and tables 911 / 95 / 48 /
  1,616; far system code 265 / 28 / 215 / 955.
- **Bank 5:** the top-bank code 4,547 / 1,189 / 166 / 7,812; the glyph
  image 630 shared.
- **Bank 6:**
  - the fighters' part records 2,589 / 181 / 0 / 224;
  - level 1's shape records 271 / 1,893 / 378 / 0;
  - level 1's tables (`L1K_*`, `L1T_*`, `L1S_*`): each a few dozen bytes
    shared and over a hundred in one scene each;
  - the art-bank sprite copies 0 / 1,210 (the attract) / 594 / 37;
  - the art 993 / 72 / 34 / 378.
- **The scene pages:** each scene's own code and data read in play: 0.8-2.5K
  of its scene data, 0.1-0.6K of its scene code, 0.3-0.4K of the game's
  common code. The rest is loads' or never.

**The budget for the fixed banks** (`$4000` and `$C000`, 32K): today's fixed
bank 16.5K, bank 5's code 13.7K, the glyphs 0.6K, the fighters' records and
heads 3.5K, level 1's engine 2.1K, the art read in play about 1.4K: about
38K. So 6K must come out:
1. **Each tile set's own data on its scene's page:** level 1's shape
   records, index and tables (about 5K) split by set. Each set's are read
   in play by its scene only; the shared part is the few bytes of their
   indexes. The attract's sprite copies (1.2K) too.
2. **The load's code in a loader bank:** with bank 5 free (the scenes need
   pages 0-4), the load-only code (`FAR` 471, `FARART` 233, the main
   block's 92, `L1Load`, `LoadInit`, `TopLoad`, `ResetB`) runs there under
   the blank list. A switch then is safe: nothing shows.
3. **The dead blitter-era code:** the blitters and `RowBase`
   (`BlRom`, `BlRomN`, `BlRomM`), the bitmap's clears and copies, the old
   slice copy, the fast fill (`RAMFILL`, already not placed), each checked
   against the uncovered paths first.
4. **Bank 5's generated tables:** by scene where they are a scene's
   (`TOPSCN_*`), on that scene's page.

Items 1 and 2 alone are about 6.5K.

**MARIA's side:** each page holds its scene's windows and characters
(5.9-9.6K), its group of top data (15 pages, about 2.4-3.7K) and its text
(the attract's title and story 3.5K, level 4's ending 2.6K). Level 4's page
is the tight one, close to 16K. The shared graphics (the fighters' parts and
heads, the stars, the sky row, the status strips) go in banks 6 and 7.

**Correction to the ledger (same day):** `tmp-romuse.lua` marks an opcode's
fetch only: an instruction's operand bytes are neither executed nor read,
so `romplan.py` counted about half of every code byte as never used.
`romplan.py` now gives an executed opcode its instruction's length, read
from the cart. Corrected:
- bank 5's top-bank code: 9,423 shared, 1,408 one scene's, 339 loads', 2,544
  never;
- the game's bank 15 code: 6,114 / 1,167 / 4 / 965;
- engine part 2: 1,090 / 149 / 7 / 1,668 (the blitter's inner parts);
- system code and tables: 2,051 / 209 / 113 / 297;
- far system code: 580 / 69 / 471 / 343;
- level 1's engine code: 1,880 / 131 / 0 / 133.

The budget was a sum of whole items, so it stands: about 38K for 32K. The
never-run code is about 2.5K in bank 5 and 3.4K in the fixed bank (mostly
the blitter's). `romroutines.py`'s per-label view was right: a label counts
as run when any of its bytes is.

### The ROM by scene: step 3, the new layout begun (2026-10-15)
**The user:** go for it, moves 1-3. The ending's text and "the end" may
switch banks (the game is over then; even the intro text's bank will do).

**Built so far** (`V2=1`; today's layout byte for byte unchanged, checked
after each change):
- **Plumbing:** `layout7800.V2`; the source filter (`v_filter`: a line
  tagged `#V1` only in today's layout, `#V2` only in the new one); output
  to `work/v2`; the header `$2002` (no cart RAM: bank 6 fixed at `$4000`
  on each side).
- **Bank 6 assembled at `$4000`:** `Image.find` takes a window range as the
  bank's own 16K; level 1's and the records' searches use the bank's base.
  `TOP_BANK` and `IMG_BANK` are bank 6; `LOADER_BANK` is 5.
- **Gone from the cart:** the art, the art-bank and below-`$C000` sprite
  copies (read only by the loads' generators). They are kept in a shadow
  image (`art_src`) the build reads to make the windows and poses.
- **The load:** `L1Load` calls `L1Init` (`L1Gen`'s end: the variables
  cleared, the views unknown) instead of `L1Gen`, and no `AkPre`. The
  tiles' stream is not placed.
- **Released:** every scene-page byte the build reads to make the windows
  (`l1get`'s reads), unless a scene there has an instruction, label or
  relocation in it: 7,302 bytes. The pages then have 3.5-5.8K free each.
- **Level 1's shape records** in their set's scene page; the index stays
  in bank 6, each entry pointing into its set's page (the window holds it
  whenever the set plays). Bank 1's largest run (640 bytes) is kept for
  level 1's page code, `LEVEL1PAGE`, placed after.

**A dead end: the arrays by set.** Each array indexed by shape (`L1K_*`,
`L1S_ZA/ZE`) with one base and each set's slice in its own page needs, at
one base, free bytes at staggered offsets in five pages at once. The
pages' free space is many small holes after the release, and no base fits
even the first array. (`V2SLICE=1` still tries it.) Kept in bank 6: about
2K.

**Where it stops:** the shared code doesn't fit. Bank 6 holds about 15.4K
placed (the top-bank code so far, the fighters' records, level 1's arrays,
the glyphs, the sound tables), with 5,741 bytes of top-bank code and 2,144
of level 1's code still to place: about 23.3K for 16K. The fixed bank has
0.8K free. **The shared code needs about 39K for the fixed banks' 32K.**

**Per piece** (`romroutines.py --pieces`: bytes run in play by more than one
scene, by one, loads only, never), the top-bank code is shared almost
throughout: `FtAkPairP` (the band writer and the fighters) 2,931 shared,
`Builder` 1,303, `FtEmit` 748, `ClearCopy` 622, `TopEmit` 638. One scene's
code is small (`TopErase` 192 in level 2, `ObjBlank` 31 in the attract);
load-only is small (`AkLookP` 233, `FtFixed2b` 471: the pose cutting, dead
in the new layout).

**What closes the gap, and what it costs:** the dead code in the new layout
(the pose cutting, the blitters, `RowBase`, never-run code: about 2.5K); the
loads' code in the loader bank (about 0.4K); per-page copies of large shared
pieces (each page has room for one or two: the builder, 1.45K, through the
scene page's jump table). That fits, just, but **both fixed banks end up
full**: play with no bank switch leaves no spare fixed ROM.

**On (same day; the user: finish the new layout, then find room):**
- **The loader bank:** a new piece kind, `FARLOAD` (`LoadInit`, `L1Load`,
  `TopLoad`, `ResetB`, `FtBlack`). Today's layout treats it as `FARART`;
  the new one places it in bank 5 and calls it through `LoaderCall` (a load
  shows the blank list; "the end" may switch, the game being over). `Reset`
  enters `ResetB` in the loader bank. 636 bytes out of the fixed banks.
- **The switches in play** (V2): the 17 three-line switches to `#TOP_BANK`,
  `#ART_BANK` or `FT_SRCB` are today's layout's only (`#V1`); `L1Call`
  skips the switch for bank 6. The scene bank's re-selections (`NmiGo`,
  `FrameGo`, the restores) stay: they change nothing.
- **Dead in the new layout:** the pose cutting (`AkPre`, 79 lines) and the
  slice copy (`FtCopy` through the pair's row: 257 lines; `FtPairNext`
  stays, `FtPlain` steps the pair's pointers with it). A missed pose (none
  in any run) would show its cells wrongly for a frame.
- **Engine part 2's blitter module** (XE `$2800-$2BFF`): every scene
  captures the game's draws, and no run executed or read 864 bytes of it
  (`V2_DEAD_RELEASE`, released in the new layout only).
- **The top-bank pieces overflow into the fixed bank** in the new layout:
  both are fixed.
- **Where it stands** (`V2ALL=1` lists every miss): 2,304 bytes of top-bank
  pieces unplaced (`TopErase` 691; eleven of the `TOP_*` tables, 109 bytes
  each; `TOP_NTHI` 209; `TopClear` 98; `TopColours` 83; `TextIn` 67;
  `ObjBlank` 66), then level 1's code, 2,144. Bank 6 full; the fixed bank
  about 0.35K beyond its main block. **About 4.1K short.**
- **Next:**
  - the per-page copies (the builder, 1.45K: each scene page a copy, the
    scene page's jump table per page);
  - the port's never-run code dropped in the new layout (scene 5's old
    band writer paths, the bitmap's clear and copy loops, the front boxes'
    `FgStale`, `RowBase`, `RowAddr`, `BlitBank0A`: about 1K);
  - the `TOP_*` tables by scene (each scene's top pieces are one range).
- **More room (same day):**
  - **The scene pages' untouched data** (`V2_PAGE_RELEASE`, scenes 0-3;
    scene 4's page left out: its ending no run reaches): stretches of 16 or
    more no run touched (the CPU or MARIA), given back byte by byte where
    no scene in the page has an instruction, label or relocation. 404,
    2,382, 1,331 and 2,271 bytes. The build reads the pages' images from a
    snapshot taken before any release (`page_src`).
  - **The scene pages' common block:** `$9420-$96E7` is the scene pages'
    system code and free at one address in every page. A new piece kind,
    `FARCOM` (`TopClearCopy`, `TopColours`, `TextIn`, `ObjBlank`), joins it
    in the new layout: 611 bytes, called as it is. It takes two passes, as
    the main block does: the far labels at a placeholder, then the real
    ones, rewritten in every page.
- **Where it stands:** 1,990 bytes of top-bank pieces unplaced (`TopErase`
  691 and eleven `TOP_*` tables) plus level 1's code, 2,144. **About 3.8K
  short.** Free at one address in every page now: 142 bytes.
- **What's left, each with its risk:**
  - the never-run top-bank code (about 1.2K: scene 5's old band writer,
    the bitmap's loops, the front boxes' remains), which means cutting
    branches inside routines that run;
  - per-page copies through vectors in the common block (`TopErase`, the
    builder), with the pieces split: scene 4's page has no run past 263
    bytes;
  - the `TOP_*` tables by scene (the slicing that failed for level 1's
    arrays);
  - the game's own scene-0-only code (about 0.9K of bank 15) moved by the
    linker.

**Closing the gap (2026-10-15, the user: "drop never-run code, per-page
copies, move scene 0's game code"):**
- **The blitter era's dead code, out of the new layout's source** (`#V1`):
  the main block's `RowAddr`, `RowNext`, `RowNextC`, `RowWrap`, `BlitDone`;
  the far pieces `RowBase`, `BlRom`, `BlRomN`, `BlRomM`, `L1FillCv`; level
  1's page's blitter columns (`ColC0`, `ColA0` to `ColTEnd`, `ColPiece`,
  `ColRow`: level 1 always takes `ColL1`). Their jump-table entries
  (`SysRowBase`, `SysBlSetup`, ...) stay at their addresses, as `JMP OsStub`
  (an `RTS`): only engine part 2's dead blitter calls them.
- **The bitmap's and scene 5's paths:** the builder's bitmap rows
  (`RowsEmitPl1`: every scene is a tiles set; the ending's text goes to
  `BuildTs`), `FgStale` (no caller left), `ClearBuf`'s and `CopyBuf`'s
  bitmap loops (no cart RAM in V2), scene 5's old band writer (`BandWE0B`,
  `BandW2C` to `BandWX`, `BandWFit`: `S_BLPC` `$FF`, its overflow in cart
  RAM's tails), `FtObj0` (a pose not pre-cut: `FtCopy` is gone; such a
  part is now not shown).
- **Not dropped:** paths a run just didn't take but play can (`TopEPRRight`,
  `FtPlR1`, `BuildRowsLast1`). And `romroutines.py`'s "never" for a table
  (`TPSG_*`, `L1SG_*`) is wrong: they are read. Its read marks miss tables
  in banked code. Code only.
- **Per-page copies** (`FARPG`): `Builder`, `TopEmitF`, `TopSky`, `TopErase`
  (2,226 bytes) in every scene page, reached through vectors at the end of
  the scene pages' block (`PgBuildDll`, `PgTopErase`: `JMP` to that page's
  copy, the block assembled once a page). The build splits a piece into
  parts (`split_parts`: at a label after `JMP`/`RTS`/`RTI` where no branch
  crosses), so a page's short runs take it.
- **Level 1's code:** no generator in V2 (`FARL0` left out), its pieces in
  parts too, into the fixed bank where bank 6 is full. `L1Tiles` had no cut;
  one `BCS` became `BCC`+`JMP` (3 bytes) to give it one.
- **The poses' tables in their scene's page:** the hawk's search and table
  (scene 3) were in bank 0, which meant a switch in play. In V2 they go in
  bank 3 (`FARL3`), and `L1Call` skips the switch for the scene page as
  well as for bank 6.
- **Dead end: the `TOP_*` tables at one base.** Each scene group reads only
  its own range, so each page needs only its slice. With the original
  numbering every page's window is at a fixed offset, and only `TOP_SRCLO`
  found a base. Numbering each group from its own first index (`TPG<page>`:
  the groups are in different pages, so their numbers may overlap) and
  searching a base a table (`FARSL`) got four tables placed, then none: bank
  4's runs (263 at most) can't hold a pattern 469 bytes wide. **It works once
  the pages have room (below).**
- **The pages' untouched data in their code too** (`V2_CODE_RELEASE`): the
  scene code and common code (XEGS `$1203-$22FF`, `$06E8-$0FFF`) hold data no
  run touched, the XEGS display lists at `$1908` first (the builder reads
  their descriptions, `SP_DESC`). The same byte test as `V2_PAGE_RELEASE`
  (no instruction, label or relocation of any scene in the page) gave back
  pages 0-3 another 2-3K each: bank 0 2,681 → 5,153 bytes free. Scene 4's
  page is left out (its ending is in no run).
- **Where it stands:** every far piece placed and the `TOP_*` tables by
  scene group, but bank 4 (Akuma's poses' tables, 581 bytes, after the
  slices) is about 0.6K short. Next: a run through the ending
  (`probes/tmp-romuse-end.lua`: `tmp-romuse.lua` with `p7800-jumpto.lua`,
  scene 4's `$B84E` at flip 200) so scene 4's page can give back its
  untouched data too.

### The user's run on the cpuout cart: the gate hang and the ghosts (2026-10-15)
The user's recording `inp/karateka7800-invincible-easy-03.inp` (170 s, on
`2026-10-15_KEEP_enh-cpuout`'s invincible-easy cart, made on the new
`a78.exe`, `inp/...-03.mame.txt`) reported: the crushing gate without
graphics and a likely crash at the gate's death; off-screen fighters left
as fidgeting ghosts (level 1: the player at the first guard's gate while the
view shows the guard; level 2 likewise); dead bodies moving with the camera.

**The hang (fixed):** at the gate's death the CPU ran bank 15's routine at
`$D2E7` into `$D2EF`: `A9 | A9 4A A2 92 20 C9 F4`. The first `$A9` is the
game's, the rest a far piece's (`LDA #$4A / LDX #$92 / JSR TopArtCall`), so it
called `$9254` in the top bank, ran into RAM (`$02D0`, then BRKs through
`$17xx`) and stopped on a JAM (`$02`) at `$D92F`. `FIXED_RELEASE` gave back
XEGS `$B2F0-$B2FF` (and `$AD59-$AD74`) as bank 15's zero padding at the
plain offset (`$D2F0`, `$CD59`). Bank 15 is reassembled, and a byte with no
instruction resolves by the region's plain offset, wrong past any routine
that changed length; the real padding was at `$D361` and `$CD94`, and live
code (the gate death's) at `$D2F0`. Since 2026-10-09's coverage pass the far
pieces placed there overwrote it. Now: a bank-15 release is placed from the
last instruction before it (not a replaced range's), and the build refuses
any release whose bytes are not the original's.
- Only the gate's death ran that routine, so no run caught it. The gate is
  drawn (its bars came down in the replay); the picture just froze first.

**The ghosts (fixed):** in level 1's first cut (the view alternates between
the player at `$0016` and the guard running in at `$006C`), no clear and no
copy happen, and the fighter not drawn kept its record (`FR_V` 1, "an
earlier picture's") at its old columns, shown in the other view. The XEGS
scrolls nothing: a new view is a new picture, its background drawn again
over the old fighters, and the game draws again those still in view.
`L1Flip` already dropped a buffer's scenery instances not drawn when its view
(`L1_V`) changed; now `FtViewGone` (a far piece, 52 bytes) does the same for
that buffer's fighters, hit star and Akuma (`AND #$FE`: 1s cleared, 2s, this
picture's, kept). Checked:
- the recording's own inputs on the fixed cart stay in step through level 1
  (to about frame 4,740): at the cut only the guard shows, then only the
  player, as the user described the original;
- level 2 in real play on that cart (after the runs part): no ghost guard,
  windows whole;
- the state-forced replay (`port/replay.sh r03`, record `r03rec`, new
  `PASTEND=1` to go on past the records) through the gate's death: no hang.

**Replay lessons:**
- `work/gamestate.txt` (made before the CPU's data moved) forces `$1880-$18FF`,
  where the top lists are now: a build whose lists differ there gets the old
  cart's bytes written over them. `replay.sh` takes `SKEXTRA` (more addresses
  not forced). Even so, forced replays showed broken top lists in level 2 on
  the fixed build that real play on it doesn't: judge level 2's pictures by
  real play, not forced state.
- `p7800-stateplay.lua`'s `SNAPF` snapshot is taken inside a tap, partway
  through a frame: half-drawn pictures (black bands) there are not real.
  `probes/tmp-snapn.lua` snapshots whole frames after a flip.
- `run7800.sh`'s `EXTRA` splits at spaces: put an `.inp` in the run's folder
  and use `-input_directory .`.
- Probes added: `tmp-recsnap.lua`, `tmp-snapat.lua`, `tmp-snapn.lua`,
  `tmp-ghost.lua`, `tmp-ghost2.lua`, `tmp-dldump2.lua`, `tmp-wwho.lua`,
  `tmp-romuse-end.lua`.

**Not changed:** at flip 190 of the run the player shows as a sliver at the
gate post in the old cart too (separate, not looked at).
Checkpoint `2026-10-15_KEEP_enh-gateghost`; test cart
`work/karateka7800-invincible-easy.a78`.

### The princess room's sound (2026-10-16)
The user's run `inp/karateka7800-invincible-easy-04.inp` (488 s, the
`gateghost` cart: through the whole game) let the attract play: the princess
room's music was "a mess of sounds". `probes/tmp-tialog.lua` (the TIA's
sound registers a frame) and `probes/tmp-pokeylog.lua` (the game's POKEY
shadow beside them) showed voice 1's AUDC climbing `$AD`, `$AE` ... `$BF`,
`$A0` ...: its volume counting through 15 into the distortion bits, a
buzzing sawtooth. The conversion to the TIA followed it faithfully; the game
wrote it.
- **The cause:** the envelope (engine part 1, XEGS `$1097-$10C0`, `$F297` in
  the cart) counts a note's attack up by one a call till the volume
  (`$1A0E,X` here) *equals* the target (`$1A1E,X`). A note begun while its
  voice is still above the target (the last note not yet decayed: here at
  `$0C`, the new target 8) counts on through `$FF` and round. The cutscene
  plays its music from its own wait loops (`$DD41`, eight sound calls a
  call; the sequencer every other call), its events by flips, so where a
  note falls against the picture depends on the build's speed: the
  checkpoints from 10-02 to 10-09 and since 10-14's attract tiles hit it,
  10-10 to 10-14 didn't, the stable port doesn't. The XEGS's timing never
  hits it.
- **The fix** (layout7800 replacement at `$10BC`): `BCS` for `BEQ`, the attack
  stops at or above its target. The attract: no wraps, 333 register changes
  (the builds that missed it: about 350; the stable port 268, slower).
- `probes/tmp-tialog.lua` with no input compares the attract's sound across
  builds (it is the same each run); `tmp-pokeylog.lua` shows the game's side.
Checkpoint `2026-10-16_KEEP_enh-envfix`; test cart
`work/karateka7800-invincible-easy.a78`.

### Coverage from the user's full runs, and the princess's kick (2026-10-16)
- **The runs:** `inp/karateka7800-invincible-easy-04.inp` (the whole game,
  attract to the ending's text, 488 s), `-05`, `-06` (versus mode, a few
  rounds). `probes/tmp-romuse.lua` on each, on its own cart (`ru04`, `ru05`,
  `ru06`).
- **tmp-romuse.lua never stopped under `PLAYBACK`** and wrote its log only at
  each 2,000th frame: a run's last frames (up to 1,999) were never logged.
  Now it stops at `END` and writes at MAME's stop (`-exit_after_playback`).
  The earlier runs' coverage may lack their last half minute.
- **The princess's kick** (walking up to her in the fighting stance: the one
  ending no run reaches; the user: its death goes to the same "the end" as
  every other). `probes/tmp-kickinject.lua` answers the game's stick and
  fire reads (SWCHA, INPT4) over a playback from `KFROM`: recording 04 to
  frame 25,850 (Akuma down, walking to her), then fire 6 frames (the
  stance) and right held. She kicks at frame 26,007, he falls, "the end"
  at 26,037, the title at 26,490. Coverage of it: `rukick`.
- **Seen in it (visual, for later):** a piece of her kicking leg stays in the
  air for about 15 frames after she stands again (26,016-26,031); one
  garbled frame before "the end" (26,034).

### The ROM by scene: step 3, the CPU's side built (2026-10-16)
- **The release tables from all the coverage** (`probes/v2release.py`, with
  `--write` into layout7800): the earlier runs plus `ru04`, `ru05`, `ru06`,
  `ru4e` (the ending jumped to) and `rukick` (the princess's kick).
  - **The check found five stretches already given back that the new runs
    touched:** scene 1's common code `$0904-$0931`, `$093C-$095F` (versus
    mode: the census missed `$0900` before too), scene 3's data `$6853-$6875`,
    `$74D0-$74FF` and common code `$0D55-$0D81`. Regenerated, they stay.
  - **Only the CPU's own executes and reads count now.** In BankSet MARIA reads
    its own half, so its fetches say nothing about the CPU's. The old
    `V2_PAGE_RELEASE` counted them: scene 0's data went 404 → about 2.9K.
  - **Scene 4's page is in now** (the ending and the kick covered): 3,372
    bytes. Free after the releases: banks 0-4 10.2K, 8.9K, 10.4K, 10.8K,
    9.1K.
- **The `TOP_*` tables by scene group placed** (a base each, the groups' first
  indexes 17, 0, 0, 0, 17), with the room.
- **The per-page copies in short parts:** `split_long` cuts a part longer
  than 36 lines where it costs least (at a label after `JMP`/`RTS`/`RTI` near
  its middle), each relative branch across the cut made an inverted branch
  over a `JMP` (3 bytes), and a long branch (40 lines or more) over one made
  long too. 2,409 bytes in 54 parts; bank 4's runs (75 bytes at most by
  then) take them.
- **The V2 build completes** (`work/v2/karateka7800.a78`, `.pgsym`: each page's
  copies' labels): the fixed bank 932 bytes spare beyond its main block,
  the pages 2.9-6.7K.
- **A splitter bug, found by booting:** a cut was allowed at a label right
  after another label that followed a `JMP`, so the first label ended its
  part and ran on into whatever was placed after it (the builder's
  `RowsZoneH` into `BuildKind1`: a `JSR` never returned, the stack wrapped,
  the CPU ran into zero page). A label now ends the "after an unconditional"
  state (both `split_parts` and `split_long`).
- **V2 boots and runs the attract** with bank 0 in throughout (no switch).
  The title and story are right (bank 0's MARIA half); the princess room is
  garbage: its tiles, windows and poses were cart RAM, written at its load.
  **Next: the MARIA side** (each scene's load image, `.loadimg`, into its
  MARIA page; its pointers there).

### The ROM by scene: the MARIA side, and V2 runs (2026-10-16)
**The layout:** MARIA's two fixed banks in V2 (bank 6 at `$4000`, bank 7 at
`$C000`: 32K) hold what every scene shares; each scene page's window
(`$8000-$BFFF`, MARIA's half of that bank) holds its own.
- **Shared:** today's 16K window block moved whole to `$4000` (the top data's
  3 groups from `TOP_MPAGE` `$40`; the fighters' parts, the sky row, the
  status strips packed around them), with the fixed bank's 16K as before.
  `fighters7800.MariaSpace` takes page ranges now (v1 `$80-$FF`, V2
  `$40-$7F` and `$C0-$FF`: no window across the gap). 4.6K of the 32K free.
- **Each scene's own:** its set's windows, tiles' characters and map rows
  and its poses' cells, laid out by `l1scene7800.Pages` over the whole
  window (`V2_BLOCKS`; `WIN_BASE` `$80`: a record's 6-bit page plus it;
  `L1_WBASE` in the asm, `$40` in v1), the characters at their CHB + `$40`.
  The text first in banks 0 and 4 (`TS_PAGES` `$80-$9D`: the title's and
  story's, the ending's), its every byte taken (`titlemaria7800.TAKEN`, zeros
  too) before the set's (`PRE_USED`). The poses' cells cut by the build
  (`akpose7800.cut`), as the load did. Used: the attract with the title
  13.9K of 16K, level 4 with the ending 12.5K, the others 5.9-7.2K.
- The load image export (`.loadimg`) is V2's window too (base `$8000`); the
  build checks each scene's bytes against its text and its bank's others.

**Faults found by running it, fixed:**
- **TopLoad is not load-only:** TopCapture's `TopSwitch` loads a scene's other
  top set in play (`JSR TopLoadSet`). In the loader bank, the call ran bank
  0's text builder, which wrote MARIA's background (blue) through a stray
  DLL pointer. It is a FARART piece again in V2 (`TopLoadF` calls it as v1
  does). The only play-time reference to a FARLOAD piece.
- **Akuma's body smeared:** `FtPlain` reads a pose's image header (rows,
  width, a pair's mask's rows) in play; V2's release of the images the
  build turned into windows gave those bytes back. Kept (`keep_hdr`): 80
  bytes. (Every Akuma's and hawk's image is in its scene's own page, so no
  switch is needed.)
- **The patch sites** (`.sites.json`) and `.free` were written to `work/`
  whatever the build: a V2 build overwrote v1's. Now beside the cart
  (`kitopt --cart` reads them there).

**Checks** (`work/v2`, invincible-easy kit; v1 byte-identical throughout):
- the attract (the princess room with its tiles, the title, the story);
- recording 04's inputs (they part from the run in level 1): levels 1 and 2
  in real play, windows whole;
- recording 04 forced (`port/replay.sh r04`, `SKEXTRA` `$1880-$18FF`, both
  carts, 79 flips): 55 identical; level 2's top lists differ only under
  forcing (real play is right); Akuma identical after the fix; the ending's
  text (`PASTEND`) from bank 4's window;
- recording 06's inputs: versus mode;
- a scripted level 2 on the plain cart: game overs, "the end", the title;
- `probes/tmp-banksw.lua`: no switch in play but the scene hand-over (the
  old page while the new scene's number is set) and the loads' LoaderCall.
- Not checked by input: the princess's kick on V2 (the coverage keeps its
  data).
- Left (harmless, cleanup): V2 still clears cart RAM at boot (`ClrCart`) and
  fills the black block (`FtBlack`): writes to ROM now, lost; the game's own
  bitmap writes at the attract's end likewise.
- Probes added: `tmp-romwrites.lua`, `tmp-bgwrites.lua`, `tmp-akstate.lua`,
  `tmp-playsnap.lua`, `tmp-snapn.lua` (`SNAPK0`); `tmp-banksw.lua`'s
  playback end. Checkpoint `2026-10-16_KEEP_enh-v2`.

### V2: the find-room pass (2026-10-16, the user: "find room, including getting rid of any cart RAM routines")
- **Level 1's per-shape arrays by set** (`L1K_SLO/SHI/ROW/FL/ROWE/W`,
  `L1S_ZA/ZE`: `slice_place`, one base, each set's slice in its page; the
  what-if that found no base on 10-15 fits now the pages have room): the
  fixed bank 856 → 2,330 bytes free (beyond its main block 2,338; runs 419,
  369, 300, 253, 220, 192 ...). The per-page copies' parts at 24 lines
  (`split_long`): bank 4's runs are cut shorter by the slices.
- **Tried, not kept:**
  - the shape index `L1S_R` sliced (2 bytes a shape): no base;
  - the map rows' tables, the world-and-zone index and the capture's blocks
    by set (`L1T_*`, `L1T_IX`, `L1K_F32`; `V2BYSET=1` keeps the what-if):
    they cut bank 4 into runs of 25 bytes or less and the per-page copies no
    longer fit, for 104 bytes of fixed room;
  - keeping bank 4's largest runs for the per-page copies (`KEEP_PG`, now 0):
    the slices need those runs to line up across the pages.
- **No cart RAM routine left in V2:** the boot's clear (`ClrCart`, its label
  kept: the probes' boot gate reads it) and the black block's fill
  (`FtBlack` keeps the cells' counts) are `#V1`. `tmp-romwrites.lua`: no
  write to `$4000-$7FFF` over the attract, level 1 and level 2. (Left in the
  source, never run or unplaced in V2: RAMFILL, assembled but not placed;
  scene 5's band areas' addresses; BandZone's bitmap-row address, in the
  per-page copies.)
- **Checks:** v1 byte-identical; the attract; recording 04 forced, 52 of 78
  flips identical as before (level 2's forcing artifact, a few small ones).
- **Room left** (V2): the fixed banks 2,330 + 10 bytes; the pages' CPU side
  3,919 / 3,863 / 6,100 / 6,502 / 2,548, the loader bank 15.8K; MARIA's
  fixed 4,572, its windows 2,482 / 10,499 / 9,395 / 9,219 / 3,877.
- **Next candidates:** scene 0's own bank-15 code (882 bytes run by the
  attract only, 772 in stretches of 16+ around `$DB70-$DFxx`, called from
  scene 0's page) into its page: needs the linker to place part of the
  shared bank 15 in one scene's page and give the original back; bank 15's
  795 never-run bytes (540 in stretches of 16+) are unidentified (pause, two
  players' options?) and stay.
  Checkpoint `2026-10-16_KEEP_enh-v2room`.

### V2: bank 5 the ending's page (2026-10-16, the user: "each scene should have its own data if possible"; "using bank 5 for the ending is fine")
- **The layout:**
  - Bank 5's CPU half is bank 4's, byte for byte. The copy is made after the
    per-page rewrite, so the ending runs scene 4's code at the same
    addresses.
  - Bank 5's MARIA half holds the ending's text (the `ts_win` key is
    `ENDING_BANK`).
  - `EndText` switches `S_SCENEBANK`, `S_BANK` and `BANKSEL` to
    `ENDING_BANK` (`#V2`, 11 bytes in `FAR04`, banks 0 and 4). The next load
    sets the scene's page again.
  - The kit's `sites.json` gives every bank-4 site a bank-5 twin.
- **What it frees:** level 4's MARIA window goes from 3,877 to 6,909 bytes
  free, now that the ending's text is no longer in it.
- **The loader moved to bank 3** (`LOADER_BANK = SPARE_BANK = 3` in V2).
  Bank 3 is scene 3's page, the one with the most room. A load needs no
  page in the window: the blank list shows, and the NMI puts the scene's
  page back in itself.
  - The `FARLOAD` pieces are cut with `split_long(..., make=True)` and
    placed best fit (`l1find`), 538 bytes in all.
  - The cuts' labels go into `far_names`.
  - The pose tables (`AKP_T1_*`) in banks 3 and 4 are placed best fit too.
- **The boot's display-list image** (102 bytes) moved to the fixed bank
  (`fixed_room`). `ResetB` copies it whichever bank is in. The NMI stub's
  patch follows it (`eq["IMG_SMALLDL"]`). v1 keeps it at `$8000` of
  `SPARE_BANK`.
- **Dead end, then the fix: the loader in bank 4, overlaid in bank 5.**
  This was tried first. Bank 4's free space is mostly 1- and 2-byte holes,
  and the boot's image needs 102 bytes in one run, so it was dropped for
  bank 3.
- **A cost found and given back:** `split_long`'s made cuts (a `JMP` to a
  new `SplitJ` label in straight code, written for the loader's
  unsplittable pieces) had also reached the per-page copies. That made
  90 parts instead of 70, 66 bytes more on every scene page. Made cuts are
  now opt-in (`make=`), for the loader only.
- **Checks:**
  - v1 is byte-identical to the envfix and v2room checkpoints.
  - The boot and the attract work.
  - Recording 04, forced: 53 of 79 flips identical to v1, the same as the
    v2room checkpoint (52 of 78). Against the checkpoint, the differences
    are level 2's forcing artifact and a few fighter poses one frame apart.
    These move between runs: it is the forced replay's timing jitter.
  - The ending (`PASTEND`): the text shows from bank 5's window, and the
    game stays in bank 5 (`SCB=5`).
  - Fire on the ending's text (`tmp-kickinject.lua`, `KDIR=255`) changes
    nothing on v1 or V2: the ending holds until the console is reset, the
    same in both.
  - `tmp-banksw.lua`: bank 5 is selected only on the ending's text, and
    bank 3 only around the loads (`LoaderCall`). Otherwise there is no
    switch in play but the known scene hand-over: the old page stays in
    while the new scene's number is set, 1,328 frames at level 4's start,
    the same on the checkpoint.
- **Room left** (V2):
  - The fixed bank: 2,228 bytes (the boot's image took 102).
  - The pages' CPU side (banks 0-4): 3,908 / 3,863 / 6,100 / 5,964 / 2,537.
    Bank 3 holds the loader; bank 5 is bank 4's copy.
  - MARIA's fixed space: 4,572 bytes.
  - The MARIA windows: 2,482 / 10,499 / 9,395 / 9,219 / 6,909. Bank 5's
    window holds only the ending's 2,632 bytes of text.
  Checkpoint `2026-10-16_KEEP_enh-v2end5`.

### V2: the top data in each scene's own window (2026-10-16, the user: "move the top-of-screen data")
- **Before:** the top rows' pieces' data (the sky, the mountain, the fence,
  the gates and doors above the cut) sat in MARIA's fixed space ($4000 on):
  three groups of 15 pages (196, 244 and 160 columns), about 9K.
- **Now (V2):** each scene's set goes in its own page's MARIA window. It is
  placed with the set's level graphics by the window allocator itself
  (`l1reserve`'s `pre`, after the tiles' characters, before the map rows):
  `Pages.put(15, width, rows)`. Its layout is the top data's own: line g at
  page T - g, one column range. `T` becomes the scene's `TOPSCN_PB` (or
  `TOPSCN_PBA` for the other set), and every piece's zone columns move by
  the set's column (`top_vplace`). The tables are emitted after the windows
  (`top_src()`; v1 at the old place, byte-identical).
  - The runtime needed nothing: `TopLoadSet` reads the page from
    `TOPSCN_PB` by scene, and the columns come from the piece tables.
  - Placed: attract 87 + 21 columns, level 1 223 + 21, level 2 160,
    level 3 53, level 4 35.
- **Room:** MARIA's fixed space goes from 4,572 to 13,572 bytes free. The
  windows go to 862 (attract) / 6,839 (level 1) / 6,995 (level 2) / 8,424
  (level 3) / 6,384 (level 4) free.
- **Checks:** v1 byte-identical. Recording 04 forced: as before; the
  differences are fighters' poses a frame apart and level 2's forcing
  artifact. Real play: level 1 (recording 04's inputs) and level 2 (the
  kit's `start-level2`, `tmp-kickinject.lua` holding right) show their top
  rows whole.

### V2: page switches under the blank list (2026-10-16, the user: "ensure the display lists are cleaned before swapping a page")
- **The fault:** MARIA draws a frame through the list it began with
  (DPPH/DPPL are read at the frame's start), but a page switch takes effect
  at once. `LoadScene` switched to the new scene's page, and `EndText` to
  bank 5, while the old scene's lists were still on screen. The rest of that
  frame drew the new page's graphics through them. Frame then went on
  building the old scene's lists from the new page's tables.
  - `LoaderCall`'s comment ("only at a load, the blank list") was wrong:
    the game asks for the blank list just before, but it is only pending.
  - Frames are mostly black at those moments (the game's fade), so this
    showed as stray pixels, or a whole garbled frame where the palette was
    not black.
- **Seen with** `probes/tmp-pageswap.lua` (new). It logs every write that
  changes the bank, with the frame, the lines since the last frame's end
  (`M.time`: this MAME's screen has no `vpos`), the list last written and
  the list the frame began with. It snapshots those frames, except switches
  under the blank list (`BLANK=2782`).
  - On recording 04 forced: the level 1 to 2 load at f8927 switched with
    the blank list only pending. The scene hand-overs at f12285, f17075 and
    f23043 switched late in a frame under the play list `$2200` (f12285
    shows the stray pixels from line ~154 down). `EndText` at f26291
    switched at line 33 under level 4's list `$2300`.
- **The fix** (V2, in the fixed bank, 75 bytes):
  - `PageBlank` puts up the blank list as the pending frame (FrameBlank's
    values), keeps Frame out (`INC S_BUSY`), waits for the NMI's `Apply`
    (`S_PEND` 0), then for one more vertical blank (`S_FRAMES`), so that
    the frame being drawn began with the blank list.
  - `PageShow` lets Frame back in (`DEC S_BUSY`) and has it choose afresh
    (`S_CHOSEN+1` $FF).
  - `LoadScene` calls `PageBlank` before its switch and ends through
    `PageShow` (after `TopLoadF`), so the whole load runs under the blank
    list and the new scene's lists are built only once its page is in.
  - `EndText` wraps its switch the same way.
- **Checks:**
  - `tmp-pageswap.lua` on recording 04 forced (through the ending) and on
    its inputs in real play (several loads, a game over, the title again,
    level 2): every switch is under the blank list. The one exception is
    the reset's first, under the BIOS's own list.
  - The ending, frame by frame: the princess room, three blank frames, then
    the text.
  - No hang. v1 byte-identical.
  - Recording 04 forced: 51 of 79 flips identical to v1. The rest are
    fighters' poses a frame or two apart (each load is now up to two frames
    longer) and level 2's forcing artifact.
- **Not settled:** the garbled frame before "the end" that the user saw was
  on a v1 cart, which makes no page switch there. It may have another cause;
  it is for the visual-bugs pass.
- **Room left** (V2):
  - The fixed bank: 2,150 bytes.
  - The pages' CPU side (banks 0-4): 3,903 / 3,863 / 6,100 / 5,964 / 2,532.
  - MARIA's fixed space: 13,572 bytes.
  - The windows: as above.
  Checkpoint `2026-10-16_KEEP_enh-v2topwin`.

### The ghost player in the embrace (2026-10-16, the user: "the ghost player in the princess embrace ending")
- **Seen:** in the embrace, beside the hug (Mariko's pose with the hero in
  her arms), the player's last running pose stays on screen, a half-kneeling
  figure to her left. It is on v1 and V2 alike. The original
  (`xe-01-easy.inp`, `probes/xe-snapplay.lua`, f26393 on) shows the hug
  alone.
- **What the game does** (the original: `probes/xe-fighterdraw.lua`, new,
  bank 15's `$A815` and the box erases; the port in real play: recording 04
  on its own `gateghost` cart, `probes/tmp-embrace.lua`):
  - Until the embrace, each picture erases both fighters' boxes (`$A78C` the
    player's, `$A780` the enemy's), then draws both.
  - From the embrace on, the player's box is still erased each picture, but
    he is no longer drawn; Mariko is drawn by scene 4's own code (`$4D` 2).
  - Then the game holds the picture: `$0AFC/$0AFD` = `$015A` (346 vertical
    blanks, one a frame: `LDA #$FF / STA $0AF6`, wait for the vertical blank
    to clear it, count down). Then "the end".
- **Why the port showed him:** a fighter's record (`FR_V`) is kept until he
  is drawn again, or the buffer is cleared or copied. Level 1 drops a
  record its fills cover (`FgStale`), but the scene sets' fills (levels
  2-4, the attract: `FgRecFB`) erase only hit stars, never fighters. In play
  both are redrawn every picture, so it never showed. A fighter the game
  stops drawing stays as he was in each buffer. At f26153 the full clear
  emptied A's record; B's stayed, and B's picture was the one held.
- **The fix** (`ErDec`, both builds, fixed bank, 16 bytes): the game's own
  box erase of a fighter (`ErP`, `ErE`) drops that fighter's record from an
  earlier picture in that buffer (`AND #$FE`, as `FtViewGone`) and marks the
  buffer's objects to be made again (`FT_DIRTY`). The game erases, then
  draws, so a fighter drawn again has his record back at once.
- **It also fixes the dead guard following the camera** (the user's report
  from recording 03; `FtViewGone` covered level 1's cuts): on the way to
  Akuma (recording 04 forced, level 4's flips 47-89, flips 2060 and 2090 of
  the snapshot set) the last guard's body showed in each new room. Now it
  stays where he fell, and the rooms after are empty.
  - Showing that stale body took the game 2 more frames a picture there (8
    against 6). The forced replay reaches the ending 105 frames sooner; the
    embrace itself is the same 346 frames.
- **Checks:**
  - Recording 04 forced (V2): the embrace has the hug alone. 70 of 78
    flips are identical to before the fix; the rest are the dead body gone
    and fighters' poses a frame apart. A body in the room where its guard
    fell stays (flip 1310).
  - Level 2 in real play (`start-level2`, holding right into a guard): both
    fighters in every frame. The fight goes differently, from the changed
    timing.
  - v1 changes too (the fix is in both builds): the new v1 baseline is
    `75c2f2a2040f7e4cd475cc5c197e587c`.
- **Dead ends and corrections:**
  - `tmp-ghost.lua`, `tmp-embrace.lua` and `tmp-l1blits.lua` read `FROM`,
    which `p7800-stateplay.lua` also reads as the flip it starts forcing
    from: those "forced" runs forced nothing ("0 forced") and drifted. They
    showed the player drawn each picture with `$4D` 0, which real play
    never does. They take `PFROM` now.
  - A rebuild of the `gateghost` checkpoint (to play recording 04 in step
    with the fix) differs from its cart in 135 bytes and doesn't boot. Not
    followed further.
  - The wait loop's PC (`$D6B0`/`$D6B3`) is the cart's `LDA $1A80 / BMI`
    (the flip wait), not the code at those addresses in the V2 cart's
    listing.
- **New probes:**
  - `xe-fighterdraw.lua`: the original's fighter draws and box erases, with
    return addresses.
  - `tmp-l1blits.lua`: the set's blits, fighter draws and flips.
  - `tmp-pccount.lua`: an instruction's runs a frame.
  - `tmp-pchist.lua`: where the CPU runs.
  - `tmp-wwatch.lua`: writes to given addresses.
- **Room left** (V2): the fixed bank 2,126 bytes.
  Checkpoint `2026-10-16_KEEP_enh-v2ghost`.

### Recording 07: Akuma's body, a V2 crash, the cutscene guard, the switch frames (2026-10-16)
The user's `inp/karateka7800-invincible-easy-07.inp` (315 s, the whole game)
was made on the **v1** cart (`work/karateka7800-invincible-easy.a78`: both
carts have that name; the record script copies the one dragged onto it).
Their notes: a corrupt screen around the first cutscene ("the background
colour not set correctly for the first frame"), fighters not hidden behind
doorways and walls at the levels' edges, the dropping gate's graphics
missing, most of Akuma's body following the player through the rooms after
his, the bottom band of the staircase at the inner fortress's start not
scrolling with the rest, and the cutscene guard leaving a standing ghost.
- **Tools:**
  - state record `r07rec` (2,509 flips, `p7800-staterec.lua` on its own
    cart); `port/replay.sh r07`;
  - `MOEXTRA` passes MAME options through `replay.sh`;
  - coverage `ru07` (`tmp-romuse.lua`);
  - new probes: `tmp-akdump.lua` (Akuma's captures at each flip),
    `tmp-pcring.lua` (a ring of executed addresses, written when the CPU
    reaches zero page), `tmp-crashtrace.lua` (MAME's trace under `-debug`:
    it moved the crash away, so `tmp-pcring.lua` instead),
    `tmp-erasetrace.lua` (the box erases' path to level 1's fill), and
    `tmp-l1blits.lua` now logs fills, erases and clears too.

**Akuma's body in the next rooms** (both builds):
- After his fall the game draws his body each picture (3 blits). At the cut
  to the next room (f16865: the player from columns 31-35 to 2-6) it stops;
  his last captures (`AK_V` 1) stayed and showed in every room. On the
  original the room's repaint wipes them.
- **Fix:** `FgRecFB` (the scene sets' fill check) drops the buffer's Akuma
  from an earlier picture whose box (`FR_C0`... 6 + buffer) a fill covers,
  as it does a hit star (`FgRecFA`).
- Forced run 07 on V2: the next rooms empty, his room with him again when
  the player walks back.
- **Seen only under forcing:** a black silhouette where his body was. The
  forced state has the game not redrawing him while on screen, which real
  play (v1) never does: there he is redrawn each picture while in view.

**A V2 crash, and the releases' reach:**
- Forced run 07 crashed V2 (both today's and v2ghost's) at f6407 in level
  2: execution went `$D3E0` → `$BAB4` → `$B580-$B5DA` (level 2's own code,
  the original's `$7580`) → `$FFFF` → zero page. Bytes inside that code
  (`$B5C7`, `$B5CA`...) had been released ("no run touched") and reused.
- Run 07's real play never took that path (its coverage touches no
  released byte): the forced state led the game into a branch no run had
  taken. But it is the game's own code, so a player could take it.
- **Fix:** `probes/v2release.py --closure --trim`.
  - `--closure`: from every instruction the runs executed, everything it
    can reach is kept too: fall-throughs, both ways of every branch,
    `JSR`/`JMP` targets; a call from the fixed bank into the window into
    every scene page; documented opcodes only.
  - `--trim`: today's tables less what is kept (stretches of 16 or more).
    The run list behind the tables was never written down, so they are
    trimmed, not remade.
  - Over all 17 coverage folders (`ru-t`, `ru0`, `ru04`-`ru07`, `ru1`-`ru6`,
    `ru4e`, `rukick`, `rup1`-`rup4`), the reach kept 932 / 854 / 408 /
    418 / 1,440 more bytes in banks 0-4 (scene 4's finale code; common code
    `$0800-$0AFF` the fixed bank can call in any scene but only scenes 0
    and 1 ran).
  - Forced run 07 on V2 now plays to the end (2,509 flips, the ending's
    text in bank 5). Bank 4 has 2,113 bytes free (was 2,537).

**The cutscene guard's ghost** (both builds):
- In the cutscenes in Akuma's room, the guard waits at the left door drawn
  as a fighter in the **player's** slot (records 0 and 2, columns 6-10).
  When he turns, the game draws him walking out in the **enemy's** slot and
  stops drawing the player; only the enemy's box erase runs, and the
  player's earlier picture stayed: the standing ghost. On the original the
  enemy's box erase (columns 1-12) wipes him.
- **Fix** (`ErDec`, 39 bytes): a fighter's box erase also drops the other
  fighter's record from an earlier picture in that buffer when their boxes
  overlap. In a fight both are erased before either is drawn, so they come
  straight back. Y kept, as the game's entries need.
- **Dead end:** first read as a set shape (the cutscene's figures, `$9908`
  and `$9956` at row 89, in level 1's set). An `L1K_W` bit-6 figure flag and
  a figures-only `L1Fill` pass for box erases were built (V2 only; v1's bank
  6 had 83 bytes too few). The dump of the buffers' instances
  (`tmp-erasetrace.lua DUMPI=1`) showed no figure at the door: taken out
  again.
- **Checks:**
  - Forced run 07 on V2: the doorway empty after he leaves.
  - Recording 04 forced: 58 of 78 flips identical to the build before;
    the rest are poses a frame apart and level 2's forcing artifact.
  - The new v1 baseline is `ce8b3c47375545ffa42d3dd7d8686985`.

**The switch frames around the cutscenes** (not fixed yet):
- **The original** (`xe-01-easy.inp`, f3173-3175 and f3444-3446) changes
  picture and colours in the same frame.
- **The port** (v1 real play, run 07):
  - into the cutscene: 4 frames of the play picture with the sky grey
    (f1652-1655), then the room, then 3 frames with Akuma black
    (f1660-1662);
  - out of it: 3 frames of black Akuma, a room frame with the sky's light
    blue on the posts, then a few play frames with a purple or grey band
    along the fence.
- **Why** (`tmp-wwatch.lua` on `$0F0C`, `S_DLIST`, `S_SKY`, DPP;
  `tmp-pccount.lua` on `NmiDliRun`, `NmiDliNot`, `FrameGo`, `NmiVbiRun`):
  - At f1651 the game switches its colour scheme (`$0F0C` 1 → 2) and asks
    for the room's list. `S_SKY` takes the new colour at once.
  - The switch invalidated the buffers' lists, so `FrameGo` rebuilds each
    whole (`BuildDllF`), inside the game's vertical blank. It takes about
    3 frames for the cutscene room: the new list is shown at f1655.
  - During the build every game DLI is dropped (6 a frame, 0 run) and
    the game's vertical blanks too. So the old picture shows the new sky,
    and the zones' palettes the game's DLIs set are not set (black Akuma
    during the second buffer's build, f1660-1662).
- **The fix it needs:**
  - build a changed list outside the NMI (e.g. in the game's wait for its
    flip, `LDA $1A80 / BMI` at `$D6B0`, the main program's idle time,
    Frame kept out by `S_BUSY`), so the DLIs and vertical blanks keep
    running;
  - take the sky's colour from the scheme shown, not the one being drawn.
- **Also seen** (forced V2): the guard entering the room is drawn left of
  the door post, outside the room (the user's doorways and walls item).
- The dark blue block at the left of level 1's first frames is the cliff:
  the original shows it too.
Checkpoint `2026-10-16_KEEP_enh-v2r07`.

### The portcullis as one image; the stairs' foot; fighters behind the doorways (2026-10-16, run 07's open items)

**The portcullis** (level 2's gate; V2 only, v1's bank 6 has no room):
- **What the game does** (run 07, v1 real play, `tmp-l1blits.lua`): every
  picture it draws the gate's frame (`$A103`, `$A12D`, `$A1EC`), then
  `$A0FC`'s bar line row by row from the lintel's (row 80) down to the
  portcullis's bottom, then a bottom piece under the last bar: `$A000` (rows
  81-89), `$A016` (90-97), `$A02C` (98-104), `$A04C` (105-112), `$A07B`
  (113-119), `$A0B4` (120-125), the bars' ends in perspective. It drops
  in three pictures (80 → 86 → 100 → 124), rises a row a picture as the
  player comes (124 → 80, about 40 pictures), drops again behind him.
- **What the port did:** two full-length column shapes (81-123, 82-124),
  added by the bar lines at rows 81 and 82. Shapes for the other lines and
  for most bottom pieces didn't exist (the capture recordings had only seen
  the drop). So the portcullis showed fully down whenever any bar below
  the lintel was drawn, and not at all once fully raised (only row 80).
- **Now:** one object per buffer.
  - The capture: `PcCap`, called from `L1Blit` in scene 2. Bar lines and
    bottom pieces are taken (C set, not shapes); the lintel's line at row
    80 stays a shape and starts the picture's portcullis afresh. The record
    is `PC_V` (2 this picture, 1 an earlier one's), `PC_ROW` (the last bar
    row) and `PC_TIP` (which bottom piece), aliased into Akuma's capture
    arrays' last entries: scene 2 never fills them.
  - The images: `pc_bar` (the bar line 44 rows) and `pc_0`-`pc_5` (the
    pieces), tall images in MARIA's ROM like the hit stars', palette
    `PAL_GAME`. One 58-row image didn't fit: a tall image needs its rows
    plus 14 zero rows in one run of pages, and MARIA's fixed space comes in
    runs of 64.
  - The emission: `FtEmitPc` (after the hit star, so over the fighters) puts
    the bars ending at `PC_ROW` and the piece under them, at column 32,
    through `FtTall`'s new clip entry `FtTallC`. The top clip `PT_T` (a
    v1-only pair temporary, free in V2) is row 81, a band cell's first,
    under the lintel.
  - The record's handling, as the hit star's: Akuma's box slot (6 + buffer)
    and reuse key (10 + buffer); dropped by a fill over the box (`FgRecFB`),
    a view change (`FtViewGone`) or a clear (`FtForget`); copied as an
    earlier picture's (`FtCopyRec`); a picture with one is always made again
    (`FtSame`); none at load.
  - The column shapes and their row 81/82 markers are out (`L2SET`,
    `tiles_inventory`, V2).
- **Checked** (run 07 forced on V2): the portcullis rises a row at a time
  with the bottom piece of each depth, stands raised with its bars down to
  the crossbar as the original's does, the player walks under it, and it
  drops behind him.

**The stairs' foot** (level 3's first room; V2):
- The stairs' image `$A000` (92 rows, 10 bytes) includes the left post. The
  post's foot is in the bottom zones (rows 135-144 and 145: not band zones,
  written by `L1Bottom`). `L1Flip` rewrote them only when the buffer's
  instances changed (`L1_DIRTY`). A scroll alone moves the band zones'
  tiles but left the bottom zones at the old view: the foot stayed on
  screen as the stairs scrolled away.
- **Fix:** `L1Flip` marks the buffer dirty when its view changes (5 bytes,
  bank 6), so the bottom zones are written with the scroll.
- **Not a fault (corrected):** the striped post going (only a thin white
  line left) as the player walks under it was taken for a bug. It is the
  stairs image's leftmost byte and a half, and the game draws the stairs at
  column -1, then -2, as the view scrolls (`probes/tmp-l1del.lua`: no
  instance is deleted there). At -1 only the post's second byte, its white
  `33`, is still on screen. The original (`xe-01-easy.inp`, f9460 on) loses
  it the same way at its first scroll step. The earlier comparison set
  frames of two runs side by side that weren't at the same point.

**Fighters behind the doorways** (V2):
- **On the original** each room picture fills columns 0-3 and 37-40
  (rows 95-173) black *after* the fighters, then draws the door frames'
  outer posts. Anything at the screen's edges is hidden: the cutscene guard
  shows only inside the doorway.
- **The port** took those fills only as erasers, so the fighters showed left
  of the outer post (the cutscene guard outside the room, the hawk at the
  right edge).
- **Fix:** `FgRecFB` records a black fill made after the fighters
  (`FT_SEEN`) that starts at a screen edge, reaches less than halfway and
  covers the fighters' rows ($06 ≤ 114, $08 ≥ 163). It is kept as the
  buffer's mask, `FT_ML` (the left edge) or `FT_MRI` (40 less the right).
  `FtObjV` cuts every fighter object to them (it cut at 0 and 40), which
  covers fighters, Akuma, the hit star and the hawk. The masks are reset
  after each emit (`FtEmitPc`).
  - Zero means no mask, so the load's clear of these tables needs no
    special case.
  - The bytes are in the small-sprite block after the fighters' tables
    (`$1D84`-`$1D87`), with their lifetime.
- **A wrong turn:** `$1B4E`-`$1B7F`, past Akuma's arrays under their
  `$1B80` limit, looked free. It holds level 1's variables (`L1VARB`:
  `L1_SET`, `L1_SF`...) and `AKP_*`, placed later; the block's assert
  guards Akuma's arrays only. Writing there wiped the band (the room's walls
  and floor gone, portcullis bars in level 1). Check the symbol file
  before taking "free" RAM.
- **Checked:**
  - run 07 forced: the cutscene guard comes in through the doorway as on
    the original and leaves with only a foot in the doorway, no ghost;
  - recording 04 forced against the build before: the differences are the
    guard hidden at the door (flip 740), the stairs' foot gone (1250,
    1280), the hawk hidden behind the right edge (1670-1880), and poses a
    frame apart;
  - run 07 forced plays to the end (2,509 flips).
- v1 is unchanged by all three (`ce8b3c47375545ffa42d3dd7d8686985`).
- **Room left** (V2): the fixed bank 1,609 bytes; bank 6 4; MARIA's fixed
  space 12,867.
Checkpoint `2026-10-16_KEEP_enh-v2gate`.

### 160A pairs that could be 160B (2026-10-16, the user's question)
The user asked whether some 160A objects lie exactly on one another and could
be one 160B object instead.
- **Measured:** recording 04 forced on V2, the lists MARIA shows at every
  50th flip from the attract to the ending (`tmp-dldump2.lua`, 46 frames,
  1,288 zones, 3,288 objects). Direct 160A objects only; the write mode a
  5-byte header sets carries on to the 4-byte headers after it.
  `probes/dloverlap.py` counts exact overlaps (one zone, the same x and
  width, different palettes); `probes/dloverlap2.py` counts any overlap.
- **Exact overlaps are rare:** 43 pairs in the 46 frames, about one a frame.
  - Palettes 1+4: a fighter part's colours and its black layer. Palette 4
    is in the other half of MARIA's palettes (4-7), so a 160B object (one
    half) can't hold both as they are.
  - Palettes 1+3 and 2+3 (and 1+4 in the window): Akuma's and the hawk's
    masks and sprites, and the scene sets' bases and overlays.
- **Partial overlaps are common but not mergeable:** 591 pairs, 492 of them
  overlapping by half or less.
  - 351 are the scene sets' own scenery pieces (stores, palettes 2+3);
  - 139 are fighter parts and their black layers (1+4), the black outline a
    pixel wider than the colours.
  - 160B holds 2 pixels a byte against 160A's 4, so one object over their
    union fetches more bytes than the two do unless they cover nearly the
    same pixels.
- **What a merge saves:** one header in the zone, 4 bytes of list RAM and
  its DMA on each of the zone's lines. Against that, a 160B object needs a
  5-byte header (the write mode), and the next 160A object needs one too to
  switch back (the "black bar across the door" fault). The data fetched is
  the same bytes for an exact pair.
- **The one place it could pay:** the fighters' pre-cut parts, merged with
  their black layer the way the heads already are (160B: colours in palette
  1, the black as palette 3's colour 1, which TopColours keeps black). That
  would take one object a part and cell off the buffer's 40 (`FT_FON`) and
  the band lists' room. It would cost the conversion of every part to 160B
  (twice the bytes in MARIA's ROM: about 12.9K free) and the mode switches.
  Worth it only if objects are being dropped for room; nothing measured so
  far shows that.
- **Probes:** `tmp-l1del.lua` (the set's deletions with their shape, read
  while its bank is in), `dloverlap.py`, `dloverlap2.py`.

### More colour for the fighters: the room (2026-10-16, the user's question)
The user wants the fighters' grey back, belt colours by progress (the karate
belt order) and highlights, and red highlights for Akuma. The grey went
where a part's slice needs black: its 160A palette is the black palette
(P4: skin, black, white), and 160A holds three colours (the user's earlier
decision).
- **Palettes:** in recording 04's 46 dumped frames, P6 and P7 are used by
  no object in any scene; P5 only by level 1's tiles below the split; P0 by
  the 160B heads and some tiles. A 160B object picks per pixel among the
  four palettes of its group, so a fighter in the 4-7 group could take P4
  (skin, black, white), P6 (the player's grey, belt, highlight) and P7 (the
  enemy's, and Akuma's red in scene 4). The game's DLIs never write P6 or
  P7, so they would be set once a fight.
- **MARIA's ROM** (fixed space, 12,867 bytes free in V2): the fighters'
  pre-cut parts are 11,678 bytes (488 distinct windows, both mirrorings),
  the tall images (heads, already 160B, and the stars) 6,917.
  - 160B holds 2 pixels a byte against 160A's 4, so all the parts as 160B
    would take about 11.7K more: it fits, with about 1.2K left.
  - Only the black-palette slices (the ones that lost the grey) would be
    about 6-7K.
  - Small 160A overlay objects carrying only the belt or highlight pixels
    in P6 or P7 would cost far less ROM, but add objects (40 a buffer,
    `FT_FON`) and headers to the lists.
- **DMA** (an estimate from the dumped lists: a 4-byte header 8 cycles, 5
  bytes 10, a direct byte 3, a character 6, about 430 a line): the band
  zones' median is about 184 cycles a line and the heaviest about 331.
  Fighter-palette bytes reach 40 in one line, so doubling them could add
  about 120 cycles there. The heaviest zones would need measuring on the
  emulator or hardware first.
- **The art:** belts and highlights aren't marked in the game's images (the
  belt is black, the gi white). It needs rules (e.g. the black band at the
  torso's waist rows) or hand-painted masks per pose.
- Akuma's poses are cut into scene 4's own window (6,384 bytes free), so
  his red comes from that budget, not the fixed space.

### The fighters coloured (2026-10-16, V2 only)
The user: give the grey back where the black palette took it, then colour
the guards as the player goes on, in the karate belt order, on the belt
and on the gi's edge at the hands, feet and neck. Guard strength should be
one of the things that sets it. The player stays much the same, with blue
highlights but not a blue belt. Make sure no guard type is skipped.
- **How the guards advance** (the XEGS code, `xe-fighterdraw`,
  `tmp-guardram`):
  - `$3E` (port `G_Z3E`) is the guard's type. It goes up by one a guard,
    and no type is skipped:
    - level 1: 0 to 5 (the cutscene messenger borrows 1);
    - level 2: 1 to 5;
    - level 3: 3 to 6;
    - level 4: 6, then 7 for Akuma.
  - `$B0` (`G_ZB0`) is the strength. Each level starts it at 14, 12, 10
    and 8. A guard's defeat lowers it by one only while it is 10 or more
    (level 1's `$78F0`: `CMP #$0A / BCC / DEC $B0 / INC $B1`). Lower means
    stronger.
- **The colours** (`FtColours`, called from `Frame` every frame, less the
  game's fade `G_L0F12`):
  - The guard's belt goes by strength: index 14 − `$B0`, clamped 0 to 7,
    into `FtBeltTab`: white $0F, yellow $1E, orange $2B, green $C8, blue
    $86, purple $56, brown $F3, black $00. So level 1's guards go white
    to purple, level 2's start at orange, and level 4's are brown.
  - The guard's trim goes by type (`FtTrimTab`): cyan $A8, red $46, lime
    $D8, lilac $6A, teal $B8, gold $1C, coral $36, and Akuma's deep red
    $44. None of these is a belt colour or the player's blue.
  - The player has a black belt and a blue trim ($86).
  - The grey (palette 1's colour 1, less the fade) goes into P6C1 and
    P7C1 from `ColTail`.
  - The type and strength are latched in `PCL_T`/`PCL_S` ($1D88/$1D89)
    when the type changes, and again when the strength rises, so that a
    belt stays put through a fight.
- **The parts** (`fighters7800.maria_parts(colour=True)`):
  - Lower bodies and torsos are classed as skin, grey, white, black, belt
    and trim (`colour_classes`).
    - The belt is the lower body's belt gaps (the pixels `lower_pixels`
      fills in).
    - The trim is white pixels within one of skin that touches the
      background: the cuffs, the hems and the collar, not the chest's
      opening.
  - A cell holding black, belt or trim becomes 160B in the upper group,
    with header palette 5 (`PAL_C` $A0, the band writer's mark):
    - P4 holds skin, black and white;
    - the player's P6 or the guard's P7 holds grey, belt and trim.
  - Other cells stay 160A in the game's palette (skin, grey, white), at
    half the bytes.
  - Heads stay as they were (see below).
  - The code that handles the new parts: `FtObjDb` doubles the width for
    $20 and $A0; `FtObjP` writes the header palette; `PwIsB` marks
    palettes 0 and 5 as 160B for the band writer.
- **Bug: whose part is it?** The first runs gave the player a green belt
  in his stance. A lower body is drawn mirrored when the fighter is the
  enemy XOR the pose is one of 28 to 32 (`$A2BE`, "The enemy's mirrored
  poses"). So for those poses, the plain image is the guard's. The palette
  now follows the fighter, not the mirroring:
  `mir ^ bool(m[0xA2BE + x])`. Torsos are mirrored for the enemy only, so
  they needed no change.
- **Bug: the first guard's belt was black.** The type latch didn't fire,
  because type 0 hadn't changed since before the level. Fixed by also
  latching when the strength rises.
- **Bug: trims matched belts.** At first the trims reused belt colours,
  so one guard had a purple belt with purple trim, and type 6's trim was
  the player's blue. The trims now have hues of their own.
- **Dead end: coloured heads** (the helmet's tips). As 160B they didn't
  fit ("no room in MARIA's ROM for a 10 x 7 window"). Even with the
  plain cells left as 160A, the heads went back to how they were.
- **Room:** MARIA's fixed space has 3,695 bytes free (the pre-cut parts
  are about 19.9K). The fixed bank has 15,187 of 16,384 bytes used. v1 is
  byte-identical (`ce8b3c47…`).
- **Checked:** run 07 forced on V2, 12 frames across the game
  (`work/analysis/col4/`). Level 1 shows the grey back, bluish as on the
  original.
- **Still open:**
  - the hat and helmet tips;
  - Akuma's red, which needs his own pre-cut poses in scene 4's window
    (6,384 free);
  - a DMA check of the busiest lines, now that more cells are 160B;
  - the cutscene switch frames.

### Level 2's window posts: a forced-replay artifact (2026-10-16)
The user saw problems with the bars in the background of level 2, the
level with the crushing gate. The pictures in question were the forced
replays of run 07 (`col2`-`col4`, `fbv1`/`fbv2`): some posts doubled, some
missing their lower half, some windows wider than the others, mountains
split.
- **Not a V2 fault:** forced v1 and forced V2 give identical window bands
  at the same flip (`SNAPF` every 10 flips, 500-1480). Older checkpoints
  (`cuts`, `topinplace`, `l2tiles-v2`) show the same kind of fault, in
  different places.
- **Real play is clean.** I measured post spacing at the panes' top row
  (scratch `posts.py`):
  - recording 07 on its own cart (v1), frames 6800-8850: 42 of 42 frames
    have posts every 64 pixels, each 8 pixels wide;
  - the same inputs on the V2 cart, not forced (the game runs its own
    way), frames 3000-12000: 85 of 85;
  - the original (`xe-01-easy.inp`): 19 of 19.
- **The cause is the forcing:** `DIFFLOG` shows the forced flips where
  the build's view differed from the record (flip 1043: `$49`, `$50`,
  `$53` 2 apart; flip 1051 back). The game wipes the old posts where its
  RAM says they were (`$64F0`, "level 2's wall"). Once its RAM has been
  overwritten with the record's, the top pieces at this build's places
  are not the ones wiped. This is the "level 2 forcing artifact" noted
  in earlier checks.
- **Lesson:** don't judge level 2's band from a forced replay. Use real
  play, the recording on its own cart, or an unforced run.
- **Gate checked too** (V2 unforced, raised, against the original): the
  same. There is one stray white dot beside the right post, in v1 as
  well, that the original doesn't have (not looked into).

**The gate down** (the user: "but what about when the gate is down?"):
- **What forced runs show:** with the portcullis down, every other picture
  (one buffer) loses a strip of the gate across the window band's rows
  (game rows 45-66, lines 93-112): the frame's left post, the bars' tops
  and the lintel's lower part. The list dump (`tmp-dldump2.lua`, released
  at flip 1250) shows that buffer's gate-building piece (`$6602`, top
  piece "one", palette 2, 10 bytes at x 120) stopping at line 92, while
  the other buffer's carries on to line 112. It is the same on forced v1
  and forced V2.
- **Real play:** recording 07 on its own cart (v1), frames 8700-9600 every
  30 (the gate down, the player in front of it): the gate is whole in all
  31.
- **Why forcing does it** (`DIFFLOG`): at flip 1226, as the gate comes
  into view, the build's view is a step off the record's (`$52` 20/1F,
  `$50`, `$53`). And on every flip `$1A1C`/`$1A1D` (per-buffer bytes) are
  forced the opposite way to the build's own. So the game's idea of what
  each buffer holds is the other buffer's, and a piece it doesn't redraw
  (the view standing still at the gate) stays cut in one buffer. Released
  from forcing (`UNTIL`, new in `p7800-stateplay.lua`: the last flip
  forced), the build keeps that buffer as it was until something redraws
  it.
- **V2 in real play: not checked yet.** The recording's inputs drift out
  of step on V2, so its unforced run never reaches the gate. My hand play
  in MAME (start-level2, easy) stalled: walking in fighting stance doesn't
  scroll, and poking `$3E` or `$B7` made guards keep coming. V2's top
  capture is v1's. Its portcullis change (`PcCap`/`FtEmitPc`) only covers
  the bars, and those show right in the strip pictures.

### The hawk's blue (2026-10-16, the user: "why is the bird blue in that level?")
- **Why:** the hawk is drawn in palette 3 (`TOP_PAL2`, "the hawk as
  objects": `FtRowPH`, black as colour 1, the sprite's grey and white
  kept). That palette was chosen for level 3, where `TopColours` fills it
  from the top's colour set as black, grey `$08` and white. In level 2 the
  top set is the windows' (`$9A` blue, white), and nothing rewrites
  palette 3 lower down. So the hawk's grey showed the window blue there,
  in v1 too. The original's hawk is grey in level 2 (`xe-01-easy.inp`).
- **Level 2's colour changes** (`probes/tmp-palline.lua`, new: palette
  writes with the scan line and `$0F14`, run 07 forced): the top's (`$0F14`
  0: palette 1 `3A 9A 0E`), the band's (3: `3A 08 0E`), the floor's (6:
  `38 88 0E`). Palette 3 is written once, in the vertical blank:
  `00 9A 0E`.
- **Fix** (both builds, `ColTail`, the end of the game's colour routine
  at each change): in scene 2, for the sets below the top's (`$0F14` not
  0), palette 3 becomes black, the set's grey and its white, less the
  fade. The windows above the band keep the top's palette.
- **Checked** (run 07 forced, V2, flips 500-1180 every 10, against the
  build before): only the hawk changed, blue before, grey after, as on the
  original. Nothing else in those flips changed, the windows included
  (one picture's fighter pose a frame apart, the replay's timing).
- The new v1 baseline is `b44b59d564e9dcb6cdcd0e601978b2d1`.

**160B for the hawk? Not needed** (the user: "can we make the bird 160B so
it can have its color back?"):
- **Level 2's hawk isn't the hawk capture.** `HawkW` and its pre-cut
  poses are level 3's only. In level 2 the hawk's images (`$AAC5`,
  `$AB2B`, `$AB64`, `$ABB1`, `$AC0D`, the shadow `$AC8D`) are shapes of
  the tiles set (`s2shapes.txt`).
  - A stored shape's part shows a colour it doesn't use as clear. With all
    four colours it gets an overlay object for the least-used one
    (`with_overlays`).
  - So the hawk's talons already come in skin, on palette 1's overlay. Its
    grey and white are in palette 3, with black in colour 1.
- **What was still wrong: the top rows** (thin feather streaks, two or
  three lines) were still blue after the first fix.
- **Measured** (`probes/tmp-dlitime.lua`, new: each NMI and colour write in
  lines from the frame's first NMI):
  - level 2's band colour DLI is the 4th NMI, at line 112, right after the
    windows;
  - the game's handler writes palette 1 9 lines later, and ColTail's
    palette 3 13-14 lines later;
  - the reason is MARIA's DMA on those lines, which leaves the 6502 a few
    cycles each.
  - The original changes before the hawk's first row: its hawk is grey
    all through, the same distance below the windows.
- **Fix (V2):**
  - ColTail, at the band's set (`$0F14` 3) in scene 2, stores the NMI's
    number and the band's grey (`P3E_N`, `P3E_G` at `$1D8A`/`$1D8B`,
    free in play; only the BIOS's RAM test and the boot's clear touch
    them, checked over run 07).
  - In other scenes it stores 0.
  - Next frame, `NmiDli` waits 4 lines (`WSYNC`) at that NMI, then writes
    the grey into palette 1's colour 2, palette 3's colour 2 and palettes
    6 and 7's colour 1. Those are the only colours the band's set changes
    from the top's (`3A 9A 0E` to `3A 08 0E`).
- **First try: no wait.** The write landed on the windows' last 4 rows,
  whose mountain lost some blue in every picture.
- **v1:** the fixed bank has no room, so v1 keeps only the first fix
  (palette 3 written in ColTail).
- **Checked** (run 07 forced, flips 500-1180 every 10, against the build
  before):
  - the hawk is grey from its first row;
  - the windows are unchanged;
  - the other differences are fighter poses a frame apart (the NMI's few
    more cycles shift the forced replay's timing).

### The hawk in 160B (2026-10-16, V2; the user: "yes", to giving level 3's hawk its colours back)
Level 3's hawk (`HawkW`, its blits captured as Akuma's, pre-cut poses)
was drawn in palette 3 with its skin made grey (`FtRowPH`), which the
user accepted on 2026-10-03. Level 2's hawk is tiles-set shapes, which
already show the skin through an overlay.
- **Now:** the hawk's pairs (a sprite and its mask, flags bit 4: 27 of
  scene 3's poses) are cut in 160B in the upper palette group, as the
  fighters' coloured parts are:
  - skin (1, palette 4), black where the mask clears and the sprite has
    nothing (2, palette 4), white (3, palette 4);
  - grey (colour 1 of palette 6, the band's grey that ColTail writes for
    the player);
  - the mask's kept pixels transparent.
  - Mirrored poses are the row's pixels reversed.
- **The changes:**
  - `akpose7800`: `coloured()`; `reserve()` makes those cells twice as
    wide; `cut()` takes their rows from `row_160b()`.
  - `FtEmitAk`: their `S_FPAL` is `$A0` (V2) instead of `TOP_PAL2B`. The
    rest was already there for the fighters: `FtObjDb` doubles the offset
    and width, `FtObjP` puts palette 5 in the header, the band writer's
    `PwIsB` makes it 160B.
- **Room:** level 3's window has 5,332 bytes free (8,424 before: the
  hawk's cells take about 3.1K more). The fixed bank is unchanged. v1 is
  unchanged (`b44b59d5…`).
- **Checked** (run 07 forced on V2, level 3, flips 1345-1955 every 3):
  the hawk shows its white head, grey body and skin talons, and its black
  mask is opaque. It is cut at the doorway as before.

### Speed: the first savings (2026-10-16, the user: "any performance efficiency we can find?")
**Measured** (run 07 forced, frames between flips by level, `FLIPLOG`;
`probes/tmp-prof.lua` as the replay's companion, `NOPLAYKEY=1`, PC samples
by symbol, flips 300-500, 900-1100, 1500-1700 and 2000-2200):

| level | v1 frames | V2 frames | V2/v1 |
|---|---|---|---|
| 1 | 4,029 | 4,156 | 1.032 |
| 2 | 5,202 | 5,463 | 1.050 |
| 3 | 4,528 | 4,550 | 1.005 |
| 4 | 3,110 | 3,140 | 1.010 |

- **Where V2's time goes** (share of samples):
  - the flip wait (`$B60F`): 5-11%. The CPU is nearly always busy, so
    the speed is the work a picture.
  - the game's DLI work (`$101F`, the music; `$1148`, the colour routine,
    which waits for a line end before its writes as on the original):
    10-12%;
  - the port's NMI wrapper (`Nmi`, `NmiDli`, `NmiQuit`, `DliExit`): about
    5%;
  - level 2's top pieces (`TopEBox`, `TopVis`, `TopCover`, `TopDel`,
    `TopEmit*`): about 14%. Each capture and erase works out every
    entry's box again;
  - the tiles sets' zone lists (`L1ZoneI1`): about 4%. Every zone, pass
    and phase scans every instance;
  - the hawk fix's 4 `WSYNC` lines in level 2: about 1%.
- **Done:**
  - `TopDel` moves only the entries in use (past the list's last,
    `S_TTMP`), not all `TOPL_MAX` (28) of the buffer's. Both builds.
  - `L1ZoneI1` passes over an instance not in the zone with X alone (no
    `L1_I` load and increment). V2 only: v1's bank 6 was a byte short.
- **Result** (frames per level, before → after):
  - V2: level 1 4,156 → 4,054 (−2.5%), level 2 5,463 → 5,214 (−4.6%),
    level 3 4,550 → 4,450 (−2.2%), level 4 3,140 → 3,078 (−2.0%);
  - v1: 4,029 → 3,994, 5,202 → 5,165, 4,528 → 4,354, 3,110 → 3,012.
  - V2 is now about as fast as v1 was before (level 2 within 0.2%).
- **Checked:** run 07 forced, flips 100-2500 every 100, against the
  `v2hawk` checkpoint. The top band is identical at every flip but 300 and
  500. At those two, and at four flips in the fighters' rows, the same
  picture was caught a scroll step or a pose apart (the timing).
- The new v1 baseline is `d7978e2a5108421d34c5a373f06fba6f`.
- **Next candidates** (not done):
  - the top pieces' boxes: worked out for every entry at each capture and
    erase. Keeping each entry's box or a cheap row/column reject first
    could save much of level 2's 14%;
  - the zone lists: instances bucketed by zone, or the counting and
    writing phases merged;
  - the hawk's early write only while the hawk is up;
  - the NMI wrapper's entry and exit.

### Speed: the top boxes (2026-10-16, V2)
- **The cost:** every capture (`TopCover`) and fill (`TopEraseList`) of
  the top rows worked out every list entry's box again (`TopEBox`, then
  `TopVis`: 16-bit pixels, clamped to the screen; about 190 cycles). In
  level 2 that is about 170 boxes a picture, about 10% of its time.
- **The cache:**
  - **What it holds:** each entry's shown pixels (`TBC_X0`, `TBC_X1`:
    `$FE` not known, `$FF` none shown), for the buffer being drawn only
    (`TBC_TAG`). Captures and fills only ever touch that buffer.
  - **Where:** `$0140-$0178`, the stack page's bottom. Play's stack never
    went below `$01B8` over run 07 (`probes/tmp-stacklow.lua`, new; the
    boot's RAM test aside), so the margin is 63 bytes. The free run at
    `$1D8C` was too short for both buffers' (112 bytes).
  - **Use:** `TopEBoxC` takes the pixels from the cache and the rows from
    the piece's table, about 75 cycles. An unknown entry gets the full
    `TopEBox` and is stored.
  - **Kept in step:**
    - `TopDel` moves the cache's slots with the list's;
    - an entry made (`TopCapture`, `TopFillAdd`) or overlapped by a fill
      (`TopErasePart` may trim it) is marked not known (`TbcStale`);
    - `TopClear`, `TopCopy` and `TopLoadSet` drop the cache;
    - `TbcCheck` (at `TopCover` and `TopEraseList`) drops it when the
      buffer changes.
  - A fill's overlapping entry still gets the full box: the trimming
    needs `S_TL`.
- **Result** (frames per level against "the first savings"): level 1
  4,054 → 4,065 (+0.3%), level 2 5,214 → 5,020 (−3.7%), level 3
  4,450 → 4,408 (−0.9%), level 4 3,078 → 2,994 (−2.7%).
  - Against V2 before any of this: −2.2%, −8.1%, −3.1%, −4.6%.
- **Checked:**
  - **Level 2, run free** (`UNTIL=760`, forced only up to flip 760, then
    the game on its own; flips 762-1400 every 2): posts every 64 pixels
    in all 301 window-band pictures, as with the build before (300 of
    300).
  - **Levels 3 and 4, forced** (every 50 flips against `v2speed1`): the
    top band is identical, except the princess's room from flip 2436.
    There one buffer keeps the right door frame of the room before.
  - **That door frame is a forcing artifact:**
    - `probes/tmp-topdel.lua` (new) shows the game clearing that buffer
      (`TopClear`) twice in the old build's forced run and once in the
      new one: its own logic a picture apart.
    - v1 with only `TopDel`'s change, which has no cache, keeps the same
      frame when forced.
    - Recording 07's real play on its own cart enters the room with the
      left frame only, as the original does.
- **Probe lesson:** a probe's taps must be held in globals. A local table
  is collected and the taps stop (the first `tmp-topdel.lua` logged
  nothing).

### Speed: what didn't pay (2026-10-16)
- **Profile after the top boxes** (V2, run 07 forced):
  - `L1ZoneI2` (the zone lists' instance scan): 3.6-5.4%, the port's
    largest item;
  - level 2's top: `TopEBC2`/`TopCover1`/`TopEBoxC` about 6%,
    `TopEmit*` about 4%;
  - the NMI wrapper: about 5%;
  - the game's own DLI work: about 10%.
- **Dead end: the zone ranges.** Each instance's zone range (`L1S_ZA`,
  `L1S_ZE` by its shape) was made once a `BandRefresh` (`L1ZC_A`/`E` at
  `$1D8E`, 96 bytes), so passing over an instance not in the zone was a
  two-byte compare.
  - **Result:** no gain (level 2 −0.5%), and levels 3 and 4 slower
    (+2.2%, +1.8%; level 3's samples +4%).
  - **Why:** most instances are in the zone being written, so the old
    scan's rejections were never the cost. Each match then paid for the
    trip back into the fast loop and its buffer check.
  - Reverted. The V2 cart is the `v2speed2` checkpoint's again
    (`83a7ab9e…`).
- **Not done: the hawk's early write only while the hawk is up.** No game
  byte separates the hawk's pictures in level 2 from the others (run 07's
  records, flips with and without the hawk). Its shapes are tiles-set
  instances, and finding them would take a scan each frame. The gain would
  be about 1% of level 2.
- **Not worth it: the NMI's bank save and restore.** V2 never switches
  banks in play, so it could be skipped, but only about 6 cycles an NMI.
- The pace moves in whole frames a picture: `$B60F`'s wait (5-12%) is
  the rest of the frame a finished picture waits out, so a saving shows
  only when it moves pictures across a frame.
- **Done after that: the cached pixels tested inline** (V2). `TopCover`
  keeps an entry at once when its cached first pixel is left of the
  rectangle or right of its end. The fill pass keeps one at once when the
  cached pixels don't overlap. Only the rest go through `TopEBoxC`.
  - **Result** (against the top boxes' build): level 1 −0.5%, level 2
    −2.0% (5,020 → 4,921), level 3 −0.4%, level 4 0.
  - **Checked:**
    - level 2 run free from flip 760: posts every 64 pixels in all 292
      window-band pictures;
    - forced, every 25 flips: the top band is identical outside level 2's
      known forcing artifact and the princess room's (above).
- **V2 in all, against where this began** (frames per level): level 1
  4,156 → 4,044 (−2.7%), level 2 5,463 → 4,921 (−9.9%), level 3
  4,550 → 4,391 (−3.5%), level 4 3,140 → 2,993 (−4.7%).

### Mt Fuji (2026-10-16, V2; the user: "Could we enhance Mt Fuji?")
- **The original:** two top pieces a level: level 1 and the attract
  loop's `$6948` (11 rows × 16 pixels) over `$6976` (8 × 32); level 2's
  `$6592`/`$65B8` (9 rows each, split by the window bar). They are white
  with black specks and sky-coloured gaps, on the sky (level 1) or the
  window panes (level 2).
- **The design** (mockups in the console's NTSC colours, from MAME's
  `a7800.cpp` table, `work/analysis/fuji_mock.png`/`fuji_mock2.png`):
  - The user chose "keep it white, add shading" over the coloured
    options (violet-blue, slate, dusk).
  - Chosen: white `$0E`, the right flank in a pale periwinkle shade
    `$8C`, and four thin broken gullies fanning down from below the
    summit in soft blue-grey `$8A`, where the black specks were. The
    crater is kept.
- **How** (`port/fuji7800.py`; pieces marked `"fuji"` in `TOP_PIECES`,
  V2):
  - The build redraws each piece from its own silhouette, centred on the
    peak, its rows counted from the summit's (row 46).
  - Its sky or pane colour becomes transparent: level 1's sky shows
    through, and in level 2 the wall's pane behind it. Its palette is 5
    (`PALW`).
  - Palette 5 (`L1_PAL`, level 1's tiles below the split) is free above
    the band's colour DLI. `FtColours` (every frame, in the fixed bank)
    sets it to the three colours less the fade, and ColTail's band set
    makes it the tiles' again lower down.
  - The first try, in `TopColours`, didn't fit bank 4's per-page copies.
- **Checked** (run 07 forced, V2, flips 100-1000): levels 1 and 2 show
  the new mountain. The fence's rails cross its base in level 1 and the
  window's bottom band in level 2, as before. Not checked: the attract
  loop's demo.
- **The user's other idea: a 320 object.** MARIA's read mode (160 or 320)
  is CTRL's and holds for every object on a line. An extended header's
  write-mode bit only picks between that mode's two formats. So a 320
  mountain would need:
  - a DLI to switch CTRL for its lines and back;
  - every other object on those lines in a 320 format too: level 1's
    torii, posts, fence and sky pieces, level 2's panes and posts.
  - The band's colour DLI already lands up to 9 lines late here
    ("The hawk's blue"). The 320 formats also trade colours for
    resolution.

### The torii in front (2026-10-16, V2; the user: "Torii in the foreground should block the fighter view from the camera")
- **The original** (`xe-01-easy.inp`; the smeared gate in mid-screen in
  some of its pictures is from walking past a guard while invincible, the
  user's note): the gate structure's right post is drawn over the player
  as he walks under it.
- **The port:** level 1's posts were in its world tiles, behind every
  fighter. Since "The front boxes gone" (2026-10-15) only a tiles set's
  front shapes draw over the fighters, and level 1's set had none (levels
  2-4 and the attract loop list theirs in `worldcfg`).
- **Measured** (`probes/tmp-l1front.lua`, new: each level 1 blit and column
  with `FT_SEEN`, and at the picture's end whether fighters followed; run
  07 forced, flips 240-740):
  - always after the fighters, whenever any are drawn: the white torii's
    front post (column `$A684`, rows 37-135), the gate structure's front
    post (column `$A000`, rows 64-112) and its foot (`$A2DE`, row 114);
  - always before them: `$A2B0`, `$A68A`, `$A703` (the back posts).
- **Fix** (V2, `l1scene7800.L1_FRONT`): those three are out of level 1's
  world tiles (`l1world7800.load(drop=)`, `l1world.txt` only) and are
  front shapes (pass 2, after the fighters).
- **Bug found on the way:** in `l1shapes.txt` a column's seventh field is
  the times it was seen, not a mode as in `worldcfg`'s `front_cols`.
  `Shape` read 192 as an AND mask, so the posts showed black (a missing
  middle). Level 1's columns had never been shapes before. `inventory()`
  now keeps a column's first six fields.
- **Checked** (run 07 forced, flips 200-740 every 4):
  - the player walks behind the gate's right post as on the original;
  - the white torii's post is unchanged;
  - 85 of 136 pictures are identical to the build before. The rest are
    fighters a frame apart, and the gate post's foot: the old tiles had a
    one-pixel white line across the post (the foot's top row), which the
    original doesn't have.
- **Cost:** level 1 takes 4,343 frames for run 07's flips 2-742, against
  4,044 (+7.4%). The posts are now objects in every band zone they cross,
  not tiles.
  - Stopping the front pass after the zone's last front instance (pass 1
    counts them in `L1_FS`) brought it to 4,333. That's kept, but the
    scan was not the cost.
- **Possible saving:** keep the posts in the tiles and draw their front
  copies only while a fighter's box overlaps their columns.
- **Then (the user: "Go for it"): the posts back in the tiles, front copies
  only over a fighter.**
  - The three images stay in level 1's world tiles (`L1_DROP` empty) and
    are still front shapes. `L1FrHit` checks whether the instance's columns
    meet a box of its buffer's fighters (records 2B and 2B + 1: `FR_V`
    shown, `FR_C0`-`FR_C1`), columns + 64 so that those left of the screen
    stay positive (`L1FH_A`/`B` at `$1D8C`).
  - Pass 1 counts only the front instances that meet a fighter (`L1_FS`),
    so with none the zone has no pass 2. The emit draws a front instance
    only when it meets one, in any pass.
  - **Frames for level 1** (run 07, flips 2-742): 4,044 before the torii
    change; 4,333 with the posts as objects; 4,286 with copies only over a
    fighter; **4,161 with the check in pass 1 (+2.9%)**. What's left is the
    capture: the game's post draws now become instances each picture.
  - **Checked:** the crossings are as before (the gate's post over the
    player). 109 of 136 pictures are identical to the overlap-only build;
    the rest are fighters a frame apart or the view a scroll step apart
    (timing). The tiles' one-pixel line on the gate post's foot is back
    where no fighter is near (it's the tiles' own, as before the torii
    change).

### The music's records released (2026-10-16; found comparing with the stable port)
- **Symptom:** V2's level 4 got slower after "The torii in front": run 07's
  flips 2057-2156 took 920 + 654 frames, against 296 + 293. The profile
  was nearly all `AkF2_*`, Akuma's pose search, with Akuma not on screen.
  Buffer B's `AK_N` read 141, and the emit searched 141 blits.
- **Why:** the game's sound start (`$0C66`, relocated `$9C66`) reads its
  sound's record through the table at `$0D03`. Its first byte is the
  channel count less one, X for `STA $2416,X`, carved to `$1A16 + X`.
  - In V2, `V2_CODE_RELEASE` had given back `$0D79-$0D8B` (sounds $0C and
    $0D) in pages 0, 1, 2 and 4, and `$0D43-$0D70` in page 4: no coverage
    run started those sounds there. Code was placed over them.
  - Run 07 starts sound $0D in level 4 (flip 2074). The driver read placed
    code as the channel count: `$1E` before the torii change, which wrote
    up to `$1A34`; `$8E` after it (the code moved), which wrote `$1AA4`
    (`AK_N`) and `$1AA2` (`AK_V`).
  - This is not a forcing artifact: the forced addresses end at `$1AA0`.
    `tmp-wwatch.lua` showed the writes coming from `$9C81`/`$9C9F`.
- **Second fault:** the table's own relocation was incomplete in every
  build, v1 included. The census relocated only the entries its runs used,
  so sounds 4, 8, 9 and $0C still pointed into XEGS `$0Dxx`.
- **Fixes:**
  - `V2_CODE_KEEP` (`$0D03-$0D8B`) is subtracted from every page's release.
  - `reloclist.py`'s `MANUAL_TABLES` gets the table (14 entries,
    interleaved, null ones skipped). `reloc.txt` was regenerated and
    gains exactly `$0D0C`, `$0D14`, `$0D16` and `$0D1C`. Before that, the
    generator was checked to reproduce the old file byte for byte.
  - The kept bytes left bank 4's 27-byte per-page part no run of its size:
    the per-page copies are now cut at 18 lines (`PG_MAXLINES`), 82 parts.
  - The driver's jump table at `$0C40` is not kept: only its first `JMP`
    is relocated, so the port never uses the others.
- **Checked:** the table and records are intact in all five V2 pages and
  in v1's. Run 07's level 4 is back to 2,581 frames (`v2speed3`: 2,513).
  New v1 baseline: `f1714f5ae3b9b4814ca238330d95b0c5`.
- **Lesson:** a coverage-based release must keep any data the code reaches
  by an index the runs may not have tried, like these tables.
- **New probes:** `tmp-songcall.lua` (the sound start's calls),
  `tmp-akcount.lua` (Akuma's pose searches), `tmp-none.lua` (an empty
  companion).

### Speed: V2 against the stable port (2026-10-16)
**How:** run 07 forced on the stable port's cart
(`Karateka-Port/work/karateka7800-invincible-easy.a78`, 2026-09-30). The
replay hooks `TopFlip`, which the stable port doesn't have, so its symbols
take an alias at `$D6DE`: `G_LB60F`, the game's flip routine, whose first
instruction is where `TopFlip` is called in V2. The game's RAM and zero
page are at the same addresses in both builds. The stable port made 2,309
of the 2,509 flips by frame 18,900, so its level 4 is partial.

| frames | stable | v1 | V2 | V2 vs stable |
|---|---|---|---|---|
| level 1 (flips 2-742) | 5,072 | 3,994 | 4,200 | −17.2% |
| level 2 (743-1341) | 4,701 | 5,165 | 4,953 | +5.4% |
| level 3 (1342-1956) | 5,633 | 4,354 | 4,464 | −20.8% |
| level 4 (1957-2308) | 3,038 | 2,536 | 2,581 | −15.0% |
| all (2-2308) | 18,444 (307.8 s) | 16,049 (267.8 s) | 16,198 (270.3 s) | −12.2% |

- V2 is faster than the stable port in levels 1, 3 and 4, and 5% slower
  in level 2, the window band's objects against the stable port's bitmap.
- V2 against v1: level 1 +5% (the torii's front copies), level 2 −4%
  (the top boxes' cache), levels 3-4 about +2%.
- **The stable port** (the user: "Did the stable port have the sound
  issue?"; `Karateka-Port/work/karateka7800-invincible-easy.a78`, the
  table found in all six banks at `$9D03`):
  - **The released records: no.** Its records `$0D1F-$0D8A` are intact
    everywhere; the release was V2's.
  - **The unrelocated entries: yes, the same four.** Its `reloc.txt` has
    the same eight entries ours had. But the gap is latent: a scan of
    every scene's code for the driver's callers finds only these sounds
    started:
    - 0, 3, 7 and `$0D` by immediate (5 takes `$0C51`'s other path, the
      engine's tune `$19`);
    - 1-3 from `$F1` (the hit sounds, `$B500`'s table);
    - `$0A`/`$0B` from `$0CE4` (by the fighters' poses, called from bank
      15's `$B71A`).
    - Never 4, 8, 9 or `$0C`. Run 07 started exactly 0, 1, 2, 3, 7, `$0A`,
      `$0B` and `$0D`.
  - **The driver's jump table** `$0C40-$0C4B` is used only through its
    first entry (scenes 1, 2 and 6: `JSR $0C40`, relocated). Scenes 2 and
    3's `JMP $0C49` at `$1C40` sits in a block nothing calls (with C64
    `$DD00` stores beside it).

### The V2 release audit (2026-10-16; the user: "Yes", to auditing the releases)
**Why:** V2 gives back page data byte by byte where no coverage run
executed or read it (`V2_PAGE_RELEASE`, `V2_CODE_RELEASE`). Data the code
reaches by an index or a pointer can be missed by the runs, as the sound
records were ("The music's records released").

**How:**
- `probes/v2audit.py` lists every indexed read (`$nnnn,X`/`,Y`) whose table
  (to the next instruction or label, at most 256 bytes) and every relocated
  pointer whose target (at most 64) holds released bytes: 200 candidates,
  read by hand. Most are pointers into the windows' and images' sources
  that V2 no longer draws from.
- `probes/v2music.py` walks the tunes structurally (table, lists,
  patterns, streams, headers).

**Kept** (`layout7800` `V2_CODE_KEEP`, `V2_KEEP_BY_SCENE`, subtracted from
both releases):
- every page: the small-sprite tables by character (`$06F4-$0773`),
  joystick 2's (`$0960-$0975`), the sounds' table and records
  (`$0D03-$0D8A`);
- per page, each table's slice from its index's real range:
  - pages 0 and 1: the cliff fall's `$6C33-$6C3E`;
  - page 0: `$795A-$7981` and `$7BCC-$7BE5`;
  - page 1: `$7603-$7682`;
  - pages 1 and 2: `$7FE1-$7FF4`;
  - page 4: `$1D0F-$1DA2` and `$6318-$632D`;
  - and the tunes' bytes no run played (pages 0-3).
- The index ranges, from the code:
  - `$793E` reads `$795A`/`$7962`/.../`$797A`,X with X 7 down to 0.
  - `$7983` reads `$7BCC`,X (the low half). The high half `$7BE6` is
    relocated bytes, never released.
  - `$7683` reads `$7603`/`$7623`/`$7643`/`$7663`,X with X from `$99`:
    `$0C` to `$18`.
  - Bank 15's `$ABCB`-`$AC48` read `$7FE1`/`$7FE6`/`$7FEB`/`$7FF2`,X with X
    7-11 (`$33`), so `$7FE8-$7FFD`. Only up to `$7FE6` was ever released;
    all five pages hold the original bytes.
  - Page 4's two groups are tables spaced one length apart: 37 entries
    and 11.
- **Correction, the cliff fall:** the first keep was `$6C13-$6C1E`,
  assuming the index starts at 0. `$6C52` reads `$6C13`/`$6C17`/`$6C1B`,X
  with X = `$A1`+1. `$A1` is only ever 0 or `$1F` (`$7918`: driven over the
  edge), so X runs `$20`-`$23` and the bytes are `$6C33-$6C3E`. In
  `v2music`'s cart, scene 0's page had them overwritten (scene 1's, where
  play happens, was intact). Invincible runs never fall, so no replay
  would have shown it.
- **The windows' sources' release** (`l1read`, a separate pass) ignored
  the keeps: it gave back `$6C1A`/`$6C1C`/`$6C1E`. It now honours them
  (4,531 bytes given back, now 4,525).

**Room:** with the keeps, bank 4 couldn't place its per-page copies. 221
bytes in 19 parts were left over, against 2,067 bytes free, all in runs
under 17 bytes.
- **Dead ends:**
  - `PG_MAXLINES` 14/12/10, `CHUNK` 40/30/20 and `PG_MAKE` all still
    failed.
  - Reserving bank 4's largest runs early (`KEEP_PG`) at 1,200-1,600 bytes
    starved a 282-byte FAR04 piece; at 1,800 and up it starved
    `L1K_ROWE`'s common base.
  - Best fit alone was still 273 bytes short.
- **Fix:**
  - `AKP_TO_FIXED = 400`: bank 4's Akuma pose tables go to the fixed
    bank's spare room, up to 400 bytes (6 chunks, 360 bytes). They are
    chained by pointers and read through `FtRead`, with the fixed bank
    always in.
  - The per-page parts are placed best fit (`l1find`).
  - Bank 4 then has 2,206 bytes free; the fixed bank has 399 beyond its
    main block.
  - The failure message now lists the parts left.

**Checked:**
- Every kept range in every page's ROM equals the original, apart from
  relocations and 5 tune bytes (`$217B`-`$218B`) that the port itself
  rewrites, the same in v1. `v2music`'s cart differed in 118 of page 0's
  128 small-sprite bytes, 81 tune bytes and more.
- v1 is unchanged: `f1714f5ae3b9b4814ca238330d95b0c5`. V2:
  `27641b23116db0ee491fa1aaa3adbde8`.
- **Run 07 forced:** 25 snapshots (every 100 flips) are identical to
  `v2music`'s. Frames: 17,590 against 17,591 (levels 4,165 / 4,893 /
  4,445 / 2,610).
- **The real-play attract** from power-on, 1,066 flips, is identical to
  `v2music`'s.
- **Run 04 forced:** flip 15 showed garbage, three flips in one frame, and
  later snapshots drifted.
  - A bisect showed it is the forced state, not the build. It appears as
    soon as bank 4's per-page code moves, even with only `AKP_T2_0`
    moved to `$F749`, which nothing reads in the attract
    (`tmp-rwatch.lua`).
  - The two carts' real-play attracts are identical.
  - Same lesson as before: forced state carries the old cart's bytes, so
    judge pictures by real play.

**New probe:** `tmp-rwatch.lua` (every read of a range in some flips: the
address and PC). Checkpoint `2026-10-16_KEEP_enh-v2audit`.

### Two buttons: punch and kick (2026-10-16, V2; the user: "button 1 for punches and button 2 for kicks")
**The game's control:** the XE has one button. The frame routine
`$0FAC-$0FFA` (common code, every page; its one caller `$0F30`) times
each press in `$DB`:
- let go under 20 frames: a punch (`$47` = `$FF`);
- held 20 frames: a kick (`$46` = `$FF`), again every 44 frames held;
- `$DC` is non-zero while the button is down (the title's start, `$77E9`,
  tests it).

**The 7800's two buttons:** RIOT port B bit 2 an output (`CTLSWB`), driven
low (`SWCHB`). Then `INPT1` bit 7 is button 1 and `INPT0` bit 7 button 2,
as MAME's a7800 wires them, and `INPT4` no longer sees them.

**V2:**
- The boot (`Reset`, DMA off) sets the mode.
- The fire routine becomes `JMP SysButtons` (layout7800, `0x0FAC`, NOP
  padded to its size). `Buttons` is in the main system block:
  - button 1's press punches and button 2's kicks, once a press;
  - with both pressed, the punch;
  - the game's guards are kept (no punch while a kick waits, and the
    other way round; nothing while `$C4` is set);
  - with neither down, the XE's timing on `INPT4`, for a one-button stick
    (not known to read in this mode on hardware).
- **First try in the wrong place:** `Buttons` went in after `ReadStick`,
  which is inside `;;; SCENEPAGE`, the code at `$9420` in every page. That
  section is full ("overlaps something at $96E8"). It belongs before that
  marker.
- **V2 only:** with it, v1's fixed bank had no gap for a 515-byte far
  piece. The routine, the boot lines and the jump table's entry are
  `#V2`, and `SYS_ENTRIES` adds `SysButtons` only in V2. v1 is
  unchanged: `f1714f5ae3b9b4814ca238330d95b0c5`.
- **Room:** V2's fixed bank has 420 bytes free. `AKP_TO_FIXED` now finds
  room for 3 pose tables, not 6, and bank 4 keeps 2,023 bytes free after
  its per-page copies.
- V2: `ef6c18fb1a444d7bc20bd5bcfc15266c`.

**Checked** (`probes/tmp-buttons.lua`: presses either button and logs
`$DC` and the `$46`/`$47` writes, with snapshots):
- On the title: button 1 sets `$47`, button 2 `$46`, both `$47`. A
  60-frame hold gives one punch.
- At the cliff in play: button 1 punches, at full reach 16 frames on;
  button 2 kicks, 8 frames on.
- **Not checked:**
  - the one-button fallback (MAME's `INPT4` reads nothing in two-button
    mode);
  - hardware.
- **Old recordings:** MAME's button 1 now punches at once, so long-press
  kicks in recordings made before become punches when played without
  forcing.

**The stable port** (the user: "push it as an option for the stable
port"): Karateka-Port `5dc16ea` adds the kit option `two-buttons`:
- The default cartridge keeps the one-button control. Its boot always
  writes the mode, `LDY #$00 / STY CTLSWB`, and the option makes it `$04`.
- The fire routine's `LDA $C4 / BNE` becomes `JMP SysButtons` (`$E128`) in
  all six pages. The same `Buttons` routine is in its system block.
- `mkkit` proves the option. Its FINDINGS has the details.

### The switch frames: built outside the NMI (2026-10-16, V2; the user: "cutscene switch frame it is")
**The fault** ("Recording 07", the switch frames):
- When the game changes its colour scheme (`$0F0C`) and asks for a list
  not built yet, `Frame` builds the whole list inside the game's vertical
  blank. A cutscene's room takes about 3 frames.
- Meanwhile every DLI and vertical blank is lost. In v1 real play of run
  07, 16 frames had no vertical blank.
- So the old picture showed with the new scheme's sky, Akuma went black,
  the posts took the sky blue, and a purple band ran along the fence.

**The game's flip:**
- The main program sets `$0AF6` = `$FF` and waits. There are three wait
  loops, `LDA $0AF6 / BMI`: the common flip's `$0872` and bank 15's
  `$B627` and `$B639`.
- Its vertical blank (`$0F66`) releases the wait. In the same pass it
  copies the next scheme `$0F0D` to `$0F0C` and the next list's index to
  `$0F09`, and `$0F87` writes the list (`SetDlist`, then `Frame`).
- Its colour routine `$1125`, run from the vertical blank and the DLIs,
  sets the zones' colours from `$0F0C`.

**The fix (V2):**
- **`FrameDefer`:** in the NMI, in play (a tiles set on, not the title's
  or story's text), a list that needs building is held instead:
  - `HOLD_N` counts the held frames;
  - `S_CHOSEN+1` = `$FF`, so `Frame` chooses it again;
  - `$0AF6` = `$FF`: the game waits on, and its vertical blank releases it
    again next frame;
  - `$0F0C` goes back to the scheme on screen (`HOLD_SCH`, latched before
    the game's handler), with the top's colours (`TopColoursF`). The scheme
    the game set is kept in `HOLD_NEW`.
  - While `HOLD_N` is set, `Frame` puts the scheme back every frame, and
    `NmiVbiDone` keeps `$0AF6` at `$FF`.
- **`FlipWait`:** the three wait loops become `JSR SysFlipWait / BMI`.
  With a list held, `Frame` builds it there, in the main program, with
  the NMI running. Then it reads `$0AF6` as the game did.
- **`FramePend`:** a held list the main program built is not applied at
  once, even in vertical blank. It waits for the next vertical blank's
  start, before the game's handler sets the colours.
- **`Apply`:** when it shows a held list, it puts the game's scheme back
  (`HOLD_NEW`), recomputes the top's colours, and clears the band's
  latched grey (`P3E_N`: the hawk fix's early write would put the old
  scheme's grey on the fence).
- **Safety net:** held `HOLD_MAX` (3) frames with no hooked wait to build
  it, the NMI builds it as before.
- RAM: `HOLD_N`, `HOLD_SCH`, `HOLD_NEW` at `$1D8E-$1D90`, after the
  fighters' tables.

**Corrections on the way:**
- **The first version's attract start** (flip 500) showed the new picture
  in the old scheme's grey. The safety net had built in the NMI after the
  game's release, so the scheme put back stayed. Fixed by `HOLD_NEW` in
  `Apply`.
- **Next, one grey row along the fence.** The band's latched grey came
  from the old scheme. Fixed by clearing `P3E_N`.
- **Then the fence's palette 1 grey** for one frame. The main program's
  build ended inside vertical blank, after the game's colour routine had
  run, and `FramePend` applied it at once. Fixed by applying held lists
  only at a vertical blank's start.
- `probes/tmp-bgwrites.lua` (new) found the last two: every palette write
  in a frame, with its time.

**Room:**
- The fixed bank lost about 140 bytes, and bank 4's per-page copies didn't
  fit (97 bytes short).
- Akuma's pose tables are now cut in chunks of 40, not 60 (`akpose7800`
  `CHUNK`, V2 only; v1's bank 0 needs its 60). Chunks of 30 and 24 didn't
  fit.
- Bank 4 has 2,011 bytes free, the fixed bank 239 beyond its main block.

**Checked:**
- **Run 07, real play on V2** (`probes/tmp-switch.lua`: the scheme, the
  hold, the list, and DLIs and vertical blanks counted each frame):
  - no frame without a vertical blank, 6 DLIs every frame in play;
  - 7 holds of 2-7 frames each;
  - into the cutscene (f2574), the play picture with its own sky until the
    room, Akuma in colour;
  - out of it (f2895), the room until the play picture, with no black
    Akuma, blue posts or purple band.
  - (v1 at the same moments: 3 black-Akuma frames, a blue-posts frame and
    the purple band.)
- **The attract** in real play: all 1,066 flips identical to
  `v2audit`'s.
- **Run 07 forced**, against the two-buttons build:
  - frames −2.8 / +0.9 / +0.5 / +0.6% by level, −0.2% overall;
  - 8 of 25 snapshots differ, all poses a frame or two apart (the held
    flips move the timing).
  - One old-build snapshot caught Akuma's body black, a lost-DLI frame.
- v1 unchanged: `f1714f5ae3b9b4814ca238330d95b0c5`. V2:
  `8c00664fa9b58a241e4cb19cc58d4b57`.
- **Not checked:** hardware; and the safety net's own path in play (the
  attract's start takes it).
- The doubled torii and black ground after the cutscene are the game's
  own: v1 shows them too.

**New probes:** `tmp-switch.lua`, `tmp-bgwrites.lua`. Checkpoint
`2026-10-16_KEEP_enh-v2switch`.

### Run 10 (2026-10-16, V2; the user's `karateka7800-invincible-easy-10.inp` on the `v2switch` cart)
The user's notes on this run, in order: a bad frame before the first
cutscene; a ghost of about 2 frames at the second; the enemies' belt tips
not matching their gi's highlights; a few rows of bad colour midway, most
visible on the torii; Akuma bleeding through the black area past the
doorway; and the gate shutting and the hawk attacking on the gate level.
The run plays back exactly on its own cart (`inp/...-10.a78` =
`v2switch`'s), and `port/replay.sh r10` forces it onto later builds (state
record `r10rec`, 2,163 flips, made with `p7800-staterec.lua`).

**The switches** (`probes/tmp-switch.lua`, now with `AUTOSNAP=n`: n
snapshots from every scheme change, and the list MARIA was given):
- **The level ends.** The game turns its DLIs off (`NMIEN` `$C0` → `$40`) for
  about 18 frames with its screen cleared, before the load. The port kept
  showing the play list. Without the game's DLIs, level 1's tiles drew a row
  of junk (rows 139-166) for 18 frames. This predates the hold: `v2buttons`
  shows it too.
  - **Fix:** `FrameKey` treats the DMA bit as off in play (a tiles set, not
    the title's or story's text) while the game's DLIs are off, so the
    blank list is shown.
  - **Fix:** `NmiDliOff`: in the frame they go off (the list can't change
    mid-frame), a DLI blacks every palette for the rest of it.
  - The same 18-frame stretch comes before play (f218-234) and at each
    level's end.
- **Level 2's cutscene, one frame of ghost** (f4898). That room's list was
  already built, but the game's vertical blank ran past MARIA's, so the
  list could only show a frame late. Meanwhile the new scheme coloured the
  old picture (grey windows, no status bar).
  - **Fix:** `FrameLate`: a list the NMI chooses late, with the scheme
    changed, is held for that frame like a held list (`HOLD_SCH` back,
    `HOLD_NEW` kept; `Apply` restores it).
- **Level 4's start: the fighters on black, 4 frames.** Scene 3's hand-over
  keeps the room on the XEGS's screen while scene 4 is drawn
  (`xe-01-easy.inp` f24549: the room throughout, `probes/xe-scenesnap.lua`,
  new). The game then puts its first picture in buffer B over that room.
  The load had cleared B (`L1Init`: its view `$FF`), so B showed only the
  fighters.
  - The old builds never showed B there (their in-NMI build swallowed that
    flip); the hold exposed it.
  - **Fix:** `FrameUnseen`: in play, a buffer whose view is still unknown
    isn't shown. The blank list stays, and the list is chosen again next
    frame.
- **Checked:**
  - forced run 10 on the final build: every switch clean (17 scheme
    changes, 8 frames each), no frame without a vertical blank;
  - the same on `v2buttons`: white ground and grey fence at level 1's room,
    black Akuma, grey windows at level 2's;
  - the real-play attract, all 1,066 flips correct.
- **The "bad frame before the first cutscene"** wasn't pinned to a single
  frame. These four are the candidates the run shows, all fixed.

**The rows of bad colour midway** (the torii; also the cutscene room's
posts):
- **Not the sky's end.** I first moved the sky-off DLI a row up. That drew
  a dark line across the posts at the fence rail; reverted.
- **The real cause** (`probes/tmp-bgwrites.lua`, new: every palette write
  in a frame, with its time): palette 5 holds Mt Fuji's colours above the
  split and the tiles' colours below it. The band's DLI (`ColTail`, set 3)
  writes the tiles' colours (`L1_PAL`) about 20 lines late. So the first two
  tile rows below the split (rows 120-121) were Fuji's shade `$8C`: a pale
  blue band across the left pillar's front copy.
- **Fix:**
  - `ColTail` keeps the colours it writes (`L1PE`, 3 bytes) and, in every
    scene, the band's grey (`P3E_G`), as level 2's hawk fix did.
  - `NmiDli` writes them at once at that DLI: palette 5 from `L1PE` (not in
    level 2, whose DLI comes before the windows' last rows, which use
    palette 5), and the grey to palettes 1, 6 and 7.
  - Level 2 keeps its 4 `WSYNC`s and its palette 3 write. The other scenes
    write at once.
- **A trap on the way:** `P3E_N`, the DLI's number, was taken at the end of
  the game's handler. By then the next NMI may already be counted: it
  alternated 5/6 frame by frame in level 1, so the early write missed.
  - `NmiDliRun` now notes each handler's own number (`DLI_NUM`), and the new
    path latches that.
  - Level 2's path keeps the old count: its early write was tuned to fire
    one NMI later. With `DLI_NUM` there, its windows went black.
- **A first slip:** the scene test in the NMI used Y, which is the
  interrupted code's there. Rewritten to use A only.

**Akuma past the doorway:**
- **On the original** (`xe-01-easy.inp`, f25720-25800) Akuma stays between
  the posts, hidden by the outer post, with nothing past it.
- **On the port** the outer post is in front, but his robe showed at x
  294-301, past it. The right mask (`FT_MRI` 3) cuts objects at byte 37,
  but Akuma's objects are shifted right by up to 3 pixels (`S_FSUB`), so his
  last kept byte's pixels carried past the edge.
  (`probes/tmp-akmask.lua`, new: the masks and Akuma's blits at each emit.)
- **Fix:** `FtObjV` cuts one byte more at a right mask when the object is
  shifted (`MRI_E`). That byte is under the outer post.
- Forced run 10, flips 1930-1948: no pixel past x 296; the build before had
  46 at flip 1940.

**The belt tips** (the user: they "do not seem to match the highlights on
the gi"):
- The guard's belt colour (`MP7C2`, by strength, `FtBeltTab`) shows only at
  the belt's tips. Level 3's guard had blue tips and purple trim. Now both
  come from his trim by type (`FtTrimTab`).
- `FtBeltTab` and the strength latch are gone. `PCL_T`/`PCL_S` are unused
  now (cleanup).

**The gate and the hawk** (real play, f5960-6020 and 7520-8150): the hawk
comes in grey and the portcullis comes down with its bars drawn. Nothing
wrong seen.

**Room:**
- The fixed bank filled up: a 270-byte piece didn't fit. `Buttons` and
  `FlipWait` moved to every scene page (a `FARPG` piece) behind two new
  scene-page table entries, `ScButtons` and `ScFlipWait` (link7800
  `SCENEPAGE_ENTRIES`, V2). The game's patches jump there; the fixed jump
  table lost `SysButtons`/`SysFlipWait`.
- Bank 4 (scene 4's page) gets a stub for the top's sky in its per-page
  copies (`NO_SKY_PAGES` {4}). Run 10's real play shows `TOPLBG` only 0 in
  banks 2-5; a sky top is level 1's. This saves 198 bytes.
- Per-page parts may use the free tail of the scene-page code's reserve,
  in bank 4 only (`pgfind`, which also prefers a place within one page).
- The build places per-page copies per bank (`pg_setup`).
- Now: fixed bank 258 bytes free, bank 4 2,000.

**Speed:**
- Forced replays swing 4,015-4,501 frames for level 1 across these builds.
  `v2switch`'s fast stretch (flips 552-652, 399 frames against 515-550)
  was it drawing garbage: a broken band, white ground, the player missing.
  The profile there showed level 1's tiles code doing a third of the work.
  Don't judge speed by a forced replay's total.
- **In real play** (the attract, input-free) the final build matches
  `v2audit`: flips 100-500 4,084 frames against 4,086; 600-1,060 +0.35%.
- The early write's 4 `WSYNC`s cost about 1% when every scene had them;
  they're level 2's only now.

**Checks, final build** (V2 `7c43f4ace9beae3aa747b1b5c77ecbb3`; v1
unchanged, `f1714f5ae3b9b4814ca238330d95b0c5`):
- forced run 10: all switches clean, no lost vertical blank;
- 43 snapshots against the build before the colour changes: the posts'
  rows fixed, the rest poses a frame apart;
- the two buttons;
- the real-play attract.

**Tools:**
- new probes: `tmp-memlog.lua` (named bytes each frame), `tmp-dppdump.lua`
  (list and bank writes, a RAM dump), `tmp-bgwrites.lua`, `tmp-akmask.lua`,
  `xe-scenesnap.lua`, `tmp-switch.lua` (`AUTOSNAP`, `dll`);
- the bisect tree `Documents/Atari 7800/enh-bisect` (v2switch's sources
  rebuilt byte for byte, then the changes one by one) is to delete at
  cleanup.
- MAME write taps must return the value, or the write is swallowed.

Checkpoint `2026-10-16_KEEP_enh-v2r10b`.

### Recording 02 (2026-10-17, V2; the user's `karateka7800-02.inp` on the plain `v2r10b` cart)
The user: the cliff fall's animation is broken; the last row of pixels of
"the end" doesn't show; flickery bars on top of the wall; a single frame with
2 guards in the cutscene. The recording plays back exactly on its own cart
(`inp/karateka7800-02.a78` = `v2r10b`'s V2); `port/replay.sh r02` forces it
onto later builds (state record `r02rec`, 536 flips; pass the plain cart as
CART). In it: a first game where the player walks off the cliff (f250-455,
"the end" at f455), then a second game through level 1's cutscene
(f2540-2860) to a game over.

**The cliff fall:**
- **Seen:** the player walks to the edge and is gone. No figure falls.
- **The original** (`probes/xe-cliffwalk.lua`, new: fire to start, then hold
  left): two pictures of him tumbling down the cliff face, then the empty
  cliff, then "the end". v1 showed nothing either: level 1 has been tiles
  since 2026-10-09.
- **Why:** the fall is drawn by `$6C52` (the table re-kept in the audit,
  X `$20-$23`), blits of images `$1E00`/`$1E4E`/`$1EB9`/`$1ED3`. Level 1's
  draws are captured as tile instances, and a draw whose image isn't in the
  set's inventory is dropped. No recording had ever fallen, so these were
  never inventoried.
- **A first try with the page addresses failed:** `$8E00`... in bank 1.
  The load carves `$1E00-$1F08` into console RAM at `$1900`
  (`CARVE_SDATA`), so the blits read from `$1900`, and the capture's lookup
  asks for `$1900`/`$194E`/`$19B9`/`$19D3` (`probes/tmp-l1find.lua`, new:
  every `L1Find` with its key and outcome).
- **Fix:**
  - `l1shapes.txt` gets the four shapes, by hand: `B 1900 1 0 97 1`,
    `194E 116`, `19B9 120`, `19D3 132`. Rows are `$06` - `$23` from the
    table, mode 1.
  - They're V2's only: a new `V2 ` line prefix that
    `l1scene7800.inventory` honours. v1's bank 6 has no room.
  - `build7800.l1get` maps a carved RAM address back to its page source to
    read the image.
- **Checked:** real play on the new cart: the two falling pictures, then
  the empty cliff, as on the original.
- ~~**Not fixed:** on the original the sea under the cliff turns from grey
  to blue after the fall (scheme 0 throughout; a draw, probably a fill).
  The port's stays grey.~~
- **Correction:** no such change. The sea is the same on both, before and
  after the fall: one-pixel rows alternating black and blue
  (`107,131,244` on the original, `110,129,246` on the port). The pixels
  were sampled in every picture of the original's f690-800 and of the
  port's (v1) fall.
  - The "grey" was a viewing artifact. The montage of the original's fall
    was shrunk for display, and the one-pixel rows alias to grey or blue
    depending on where a tile lands.
  - The original's colour writes are also the same every frame across the
    fall (`$D016`-`$D01A` from `$1152`).
  - Lesson: judge thin stripes by sampled pixels, never by a shrunken
    montage.

**"The end"'s last row:**
- The original's text is 10 rows, the port's 9. The text routine draws
  five 10-row glyphs at row 56 (`$2EAE`: `$06` = `$5B`), so rows 56-65.
- Rows 56-64 are the top's pieces (`_END`). Row 65 is the band, which V2
  draws only from tiles: the letters' feet were lost.
- **Fix (V2):** both a row up. `_END` is at row 55, and the game's `$2EAE`
  `LDA #$5B` becomes `#$5A` (all levels share it). Now 10 rows, all in the
  top's. A one-row shift on a cleared screen.

**The cutscene's two guards:**
- f2785-2798: as the guard turns to leave, his standing pose stays beside
  him for two pictures. The original (`xe-01-easy.inp` f3330-3460) never
  shows two.
- **Why:** `ErDec` (the earlier fix, "The cutscene guard's ghost") drops the
  other fighter's earlier record when their boxes overlap. It tested this
  fighter's own record. The first time the guard is drawn in the enemy's
  slot, that record is still empty in this buffer, so nothing overlapped.
- **Fix (both builds):** the overlap is tested against the erase's own
  columns, as the game's fill wipes them: the enemy's from `$E5` - 6, the
  player's from `$E3` - 3, 11 bytes. The rows (114-153) cover every
  fighter.
- **Checked:** forced r02 at flips 321-326: one guard throughout; the build
  before shows the double in two pictures.
- **v1 changes:** `5f2fa41c1efb7d9eae7c9019a3cf9ee6`.

**The flickery bars on top of the wall:**
- From f2039 to f2330 the fence (rows 104-116) alternates every picture.
  One buffer showed each post with an extra black edge: the post twice, a
  pixel apart (the original's post is 4 black, 2 white, 2 black: the other
  buffer's).
- **Why** (`probes/tmp-l1inst.lua`, new: both buffers' instances each
  frame):
  - `L1Flip` drops a buffer's instances not drawn in a picture only when
    the view changes.
  - The view is `V = 4 x $52 + $50 / 2`. At f2014 and f2030 buffer A had
    the same V (`$6C`) with `$50` 1 and then 0, but the game drew the
    posts at 105 and then 104.
  - So A kept both, 11 instances against B's 7.
- **Fix (V2):** a buffer's `$50` bit 0 is kept (`L1_VP`). A change of it
  counts as a view change too, and `L1_V`'s units stay as they are.
- **Checked:**
  - forced r02, f2150-2260: both buffers' instances identical at every
    picture's end;
  - the fence's picture-to-picture alternations fell from 59 to 11. The
    rest are forced-replay band artifacts: a junk row and the pillar's
    foot, in alternate pictures, where the instances are identical.
  - Real play on the new cart drifts from the recording (an earlier game
    over), so it doesn't reach that stretch; no alternation where it went.

**Tools:**
- new probes: `tmp-l1find.lua`, `tmp-l1inst.lua`, `tmp-cliffwalk.lua`
  (v1 + `p7800-l1cap.lua`), `xe-cliffwalk.lua`;
- `replay.sh r02`.
- `tmp-pccount.lua` doesn't stop MAME at the end of a recording: give it
  `PTO` and kill MAME, or use `tmp-memlog.lua`.

Checkpoint `2026-10-17_KEEP_enh-v2r02`.

**The cliff fall in v1 too** (2026-10-17, the user: "could you fix the cliff
fall for V1 as well?"):
- The four shapes are now both builds' (the `V2 ` prefix taken off; the
  reader keeps it for later use).
- v1's bank 6 (`L1_CAP`, its level-1 tables and code) was about 80 bytes
  short with them.
- **Fix:** v1's bank-6 level-1 pieces may go to the fixed bank when bank 6
  is full, as V2's top-bank ones do: `L1Call` has bank 6 in, so a piece
  there reads its tables all the same. `L1Clear`/`L1Copy` (112 bytes, RAM
  only) went to `$FED4`.
- **Checked:**
  - v1 with `probes/tmp-cliffwalk.lua` (fire, then hold left): the two
    falling pictures (f841, f844), then the empty cliff;
  - V2 byte-identical (`83b5335785033c9ced0db19deadda392`);
  - v1 now `4d1f07f108e5248312f2e725ebae7f0f`.
- **Seen, old, v1 only:** one frame with a white sky just before "the end"
  (the level-end moment V2's `FrameKey` blanks). The previous v1 cart has
  it too. Not fixed.

### Akuma's red: the options (2026-10-17, V2; the user picked E: below)
The user (2026-10-16): "Akuma maybe could get some red highlights to make
him seem more brutal."
- **Not a fault:** the port's Akuma matches the original's: a skin-coloured
  hakama, a white top, grey at the hands and feet (the original from
  `xe-01-easy.inp` f25600-26200 via `xe-snapplay.lua`, `work/analysis/xeak`;
  the port from forced run 10, flips 1900-2160, `work/analysis/akr`).
- **The palette is ready:** in scene 4 the guard's type (`G_Z3E`) is 7, so
  `FtColours` already puts `FtTrimTab`'s deep red `$44` in P7's colours 2
  and 3, and `ColTail` puts the grey in colour 1.
- **The cells aren't:** Akuma is cut at build time into scene 4's window
  (`akpose7800.cut`) in 160A, through palette 4 (skin, black, white). His
  sprite's grey (value 2) becomes white there.
  - Only 13 of scene 4's 57 poses are pairs (a sprite and its mask, one
    object). The other 44 are separate blits, mask (flags `$20`, black) and
    sprite, so a colour scheme must cover both kinds.
  - Each pose is one piece of him: the robe's halves, the torso, the head,
    a fist. The robe's pieces hold only robe, so its skin pixels can be
    told from the face's and hands' by piece.
- **Room:** his cells are 4,286 bytes in scene 4's load image; as 160B
  about 4.3K more, against level 4's window's 6,384 free (if the doubled
  windows pack).
- **Code:** `FtEmitAk` gives the hawk's pairs `$A0` (160B, palette 5) and
  `FtObjDb` doubles the width for it. Akuma's blits would take the same, and
  a pose `AkLook` doesn't find would need `FT_PALB` back (its copy is 160A).
- **Two rules tried on the pieces and dropped** (`akred.py`, scratch):
  - the guards' trim rule (white within 1 of skin that touches the
    background): it barely touches him;
  - his grey turned red: red fists and feet, not highlights.
- **Mock-up** (`work/analysis/akmock.png`, run 10's flip 1938 recoloured):
  A as now; B red cuffs and collar; C the robe edged dark red; D a red
  robe; E B + C. Sent to the user to choose. D is the simplest: the robe
  pieces' skin turns red, no edge rule.

### DMA: the busiest lines (2026-10-17, V2)
The open item from "The fighters coloured": now that more cells are 160B,
does any line's list need more DMA than MARIA has?
- **The probe** (`probes/tmp-dmaline.lua`, new, a companion of the forced
  replay): every 4th flip, each zone's list as shown, priced per line in
  MARIA cycles:
  - a 4-byte header 8, a 5-byte header 10;
  - a direct byte 3; a character byte 6, or 9 with two-byte characters
    (CTRL bit 4, which `FrameFound` sets for level 1's tiles).
- **MAME's count** (`maria.cpp`, the fork's measured numbers): a line
  starts at 16 cycles, and drawing stops at 430 (the scanline's 454 less
  the DMA start). An object whose header starts under 430 loads its
  header, then loses its bytes past it.
- **Runs:** forced runs 10 (levels 1-4) and 02 (the cliff, level 1's
  cutscene) on V2, 18,881 zone lines.
  - Most lines cost 200-350 cycles. On MAME's count, 6 more cost 416-422
    (run 10, zone 18, lines 167-174).
  - **One goes over:** level 1's zone 12 (lines 121-125), early in a game
    (run 10's flip 40, run 02's flip 80), at 438. Its list:
    - the tiles' 21 characters (two-byte: 199 cycles);
    - 7 fighter and band objects (160A, 49 bytes with the rest);
    - the 160B piece at x 156;
    - last, a one-byte 160A object at x 160, off screen.
  - Only that last object's byte is cut. Its header still loads. The 160B
    piece before it ends at 425, inside the limit.
  - **No visible object is cut** in either run. The margin there is 5
    cycles.
- **A dead end on the way:** the first pass showed lines of 465-796 cycles
  in run 02 (zones 13-14, lines 126-136, 142 direct bytes, the same widths
  over and over). The forced state still writes `$1880-$18FF` (see
  `replay.sh`), where the top's and band's lists now live, so the dumped
  lists were the recording's old bytes. With that range in `SKEXTRA`
  (not forced) they are gone.
  - Lesson: for anything that reads the lists in a forced replay, pass
    `SKEXTRA=1880,...,18FF`.
- **Not measured:** hardware's own limit. MAME's 430 is the fork's
  measurement. A line that is fine in MAME by 5 cycles is the place to look
  first if hardware shows a missing fighter edge at lines 121-125 of
  level 1.

### Mt Fuji in the attract demo: checked (2026-10-17, V2)
The open check from "Mt Fuji": the attract loop's demo.
- **Real play**, V2, no input (`work/analysis/attfuji`, a snapshot every
  10th flip): the demo shows the new mountain at the cliff and past it.
- **Further on**, with the torii in view, black and white rows cross the
  mountain's base: the distant fence's rails. Level 1 in play shows the
  same rows at the same view (forced run 10, flips 52 and 124,
  `work/analysis/l1tor`), as "Mt Fuji" recorded. Not a fault.
- **The original's demo** couldn't be compared: MAME's `xegs` shows a
  magenta screen from just after the demo starts (f4700 on, with no
  input; `work/analysis/xeatt`, `xeatt2`).

### Level 1's gate post: the white line not seen now (2026-10-17, V2)
The open note from "The torii in front": the tiles drew a one-pixel white
line across the gate post's foot (level 1's end) where no fighter was near,
which the original doesn't have.
- **Looked for** on the current V2:
  - forced run 07's same stretch, flips 200-740 every 4 (126 level 1
    pictures, `work/analysis/l1t07`);
  - forced run 10's level 1 (55 pictures, `l1tor`, `l1gate`);
  - with `$1880-$18FF` unforced (see "DMA: the busiest lines").
- **Found:** no white row across a post's stripes in any picture (a scan
  for a white run of 5 or more with the post's stripes above and below).
  By eye, the gate matches the original's (`xe-01-easy.inp` f2720-3040,
  `work/analysis/xetor`): both posts' white lower parts and the right
  post's black notch.
- **Probably** (not proven) gone with "Recording 02"'s view fix
  (`L1_VP`). A buffer used to keep instances drawn a half pixel apart, and
  a post's copy a row off would look like this line.
- Closed unless it shows again in real play.

### Akuma's red: built (2026-10-17, V2; the user's option E)
The user picked E from the mock-up (`work/analysis/akmock.png`): red cuffs
and collar, the robe edged dark red.

**The cells** (`akpose7800`):
- `akuma(pose, scene)`: in scene 4 a pair or a sprite alone is coloured. A
  mask alone (flags bit 5, no mask) stays his black. `coloured()` takes the
  scene.
- `akuma_rows` classes a whole pose (a neighbourhood rule needs the whole
  image, not a row):
  - the sprite's skin, grey and white;
  - a pair's black (the mask clear where the sprite has none);
  - **red** (P7 colour 3): white above the waist (screen row 106) next to
    skin or grey, horizontally within 2 or just above. These are the cuffs,
    the collar and the gi's opening.
  - **dark red** (P7 colour 2): skin from the waist down next to black or
    nothing: the robe's outline and its folds. The poses lying on the floor
    (row 118 on) have none.
  - Packed as 160B: P4 skin, black and white; P7 grey and the two reds.
    Grey is back on his pairs too: 160A palette 4 had turned it white.
- `cut()` takes each row from it by the image's row.
- Level 4's window: 6,384 bytes free before, 2,684 now.

**The emit** (`FtEmitAk`, bank 6):
- In V2 every pair takes `$A0`. All of scene 3's pairs are the hawk's
  (flags bit 4), so pair 1 is Akuma's alone.
- A sprite alone takes `$A0` unless it's the hawk's (flags bit 4: scene 3
  has five).
- A mask alone keeps `FT_PALB`.
- No scene test is needed: in V2 a pose not in its scene's table isn't
  drawn at all.

**The colours** (`FtColours`): type 7's trim is blood red `$34`, in P7
colours 2 and 3 as every type's. Then type 7 alone puts `$32` in colour 2,
for the robe's edge. (The old `$44` was a crimson; the mock-up's red was
nearer `$34`.)
- Akuma is drawn only in his fight, with type 7 (forced run 10: 6 blits
  from f13668). The single blit counted from level 3's end to then is a
  stale count, not a drawing (`probes/tmp-memlog.lua`: `G_ZD0`, `G_Z3E`,
  `AK_N`).

**Checked** (forced run 10, flips 1955-2150, `work/analysis/akr2`,
`akr3`): the robe edged dark red, red at the cuffs and collar, the lying
poses plain. It matches the mock-up.

**The DMA it cost, and a duplicate it showed:**
- Run 10 priced again (`tmp-dmaline.lua`, every 2nd flip): Akuma's lines
  167-174 rose from 402 to 449 cycles (MAME's count), past the 430.
  - The objects past it were the doorway posts' feet, the list's last
    (front instances).
- **The same list drew one object twice:** `(B0AE pw7B x152)` in zones 16
  and 17 (lines 164-174), 23 cycles a line.
  - `probes/tmp-wwhost.lua` (new: each write to a list range with the
    band emit's state) caught `L1PartW` writing it for instances 0 and 1.
  - Those are two of the dead hawk's shapes (148, 20, 149...), both at
    x 152, with the same window and palette in those zones.
    `L1Add` refuses only the same shape at the same place, so both are
    kept. Each is a real draw, but the second object repeats the first's
    bytes.
  - Only in Akuma's room: no other run 10 list has a duplicate
    (`dmadup`, every 40th flip).
- **Fix (V2): `L1PartDd`.** After `L1PartW` writes an entry, it is dropped
  when the entry before it is `L1PartW`'s too and the same 4 bytes:
  - "`L1PartW`'s too" means it ended where this one starts: `L1_LW`, which
    `L1Zone` clears;
  - so it never compares against a 5-byte header's tail;
  - a third copy goes the same way.
  - `L1_LW` takes `PCL_T`'s byte (`FO_HB + FT_FON + 4`; the guard's colour
    latches have been unused since "Run 10"; `+5` is free).
- **Checked:**
  - forced run 10, every 2nd flip: Akuma's lines at 426;
  - `probes/tmp-l1drop.lua` (new: an opcode tap on the drop path): drops
    only in scene 4, flips 1929-2105, 178 of them. The other levels' lists
    are unchanged.
  - Two lines in level 1 (121-125, flips 42 and 90) come to 444 and 432
    on MAME's count. Both were there before (sampling every 4th flip had
    missed them).
    - At flip 42 only the trailing one-byte off-screen mode reset is lost.
      Every zone's list starts with its own 160A header, so nothing changes.
    - At flip 90 every object finishes under the limit.

**Room** (the build was short by about 70 bytes in all, three times over):
- The check in `L1PartC`'s piece made it 48 bytes. Bank 6 had 22 free and
  the fixed bank's runs within reach are at most 47.
  - In V2 the bank-6 level-1 pieces may now fall back to the fixed bank
    (bank 6 is always at `$4000`). That still left the 48.
- In the main block it fit. But the main block's growth pushed a pose-table
  chunk out of the fixed bank into bank 4, and bank 4's per-page parts
  failed: about 1,970 bytes free there, but nearly all in runs under 8,
  the gaps between MARIA windows.
- **Dead ends:**
  - `CHUNK` 32 (more chunks, worse);
  - `PG_MAXLINES` 8-14 for bank 4 (8 recurses; the others still leave
    11-13-byte parts with no run);
  - `KEEP_PG` 80-160 (the runs held back weren't the missing ones; still
    0).
  - Leaving 160A the poses with no red saves nothing: 39 of 45 have some.
- **What worked:**
  - **the emit trimmed:** 15 bytes back in bank 6;
  - **a new piece kind, `;;; FARL9`**, placed after every other level-1
    piece, the pose tables included, in what is left. `L1PartDd` is
    written in three parts (21, 22, 11 bytes) joined by `JMP`s. They went
    to the fixed bank's `$F6A8` and `$F4EA` and bank 6's `$7FF4`. Nothing
    else moved.
    - `build7800`: `textsl9`, excluded from the generic `texts`.
- The fixed bank has 217 bytes free beyond its main block, bank 4 1,941.

**Cost:** the real-play attract (no input, `work/analysis/attnew`): 1,066
flips in 11,886 frames, against 11,871 for the `v2r02` checkpoint (+0.1%).
4 pictures differ, all the attract's Akuma-and-hawk scene an animation step
apart.
- Forced run 10's level 2 window band differs from the checkpoint at flips
  910-1120: posts at other x positions, Mt Fuji elsewhere. That's
  "Level 2's window posts: a forced-replay artifact" (the view moves with
  timing); the drop count shows the check did nothing there.

**Probes:** `tmp-wwhost.lua`, `tmp-l1drop.lua`; scratch `akred.py` (the
pose sheets), `dupparts.py` (the layout's base/overlay part pairs: none
alike).

V2 `cf6ff542598805f28dad7ab74852dd84`; v1 unchanged
(`4d1f07f108e5248312f2e725ebae7f0f`). Checkpoint
`2026-10-17_KEEP_enh-v2akred`.

### Cleanup, and v1's white-sky frame (2026-10-17)
The user: "finish the cleanup on V1 and give me a V1 and V2 rom for hardware
testing".

**Done** (neither cartridge changed by a byte: v1
`4d1f07f108e5248312f2e725ebae7f0f`, V2 `cf6ff542598805f28dad7ab74852dd84`):
- the bisect tree `Documents/Atari 7800/enh-bisect` (51 MB) deleted;
- `PCL_T`/`PCL_S`: `PCL_T`'s byte is `L1_LW` now, `PCL_S`'s is free (see
  "Akuma's red: built");
- `fighters7800.py`: the old converters' black layers removed
  (`black_images`, `head_black`, `plain`, `trim_rows`, `report`). Its own
  report prints the lower bodies' blobs only. `lower_blobs` and its
  helpers stay: `probes/poses.py` uses them.
- `MODE8_ROWS` (layout and the build's equates): nothing has read it since
  "The top rows' flicker".

**Checked and already gone:** `M8NIB_*`, `S_M8COPY`, `ObjBlankM`, `DL_M8`,
`S_PM8`, `S_PIDX`, the letter-object machinery (`StoryBuild`, `StoryZoneH`,
`StoryEmit`, `StoryLocate`, `StoryPatch`, `TitleLocate`, `TitleZoneH`).
V2's `ClrCart` and `FtBlack` are already no-ops there.

**Kept on purpose:**
- `S_STW` (a byte of the status bar's scratch): taking it out moves every
  RAM variable after it, in v1 too, just before a hardware test.
- Older test carts in `work/v2` (`-l2`, `-l2e`, `l2test`, `newcart`,
  `rec02`): build output from earlier rounds, not in the repository.

**v1's white-sky frame before "the end"** (the cliff walk,
`tmp-cliffwalk.lua`, every frame f820-1300; scratch `cliffrun.sh`):
- **What it is:** two frames (f912-913 on the `v2akred` checkpoint's v1)
  showing the cliff picture in "the end"'s colour scheme: white sky, black
  mountain, white sea. Then "the end".
  - It's a scheme switch landing one picture before its list, the kind V2's
    hold machinery handles ("The switch frames: built outside the NMI",
    `FrameLate`). V2 shows no such frame at the same point.
- **Tried:** V2's `FrameKey` and `NmiDliOff` made common to both builds
  (50 bytes of v1's fixed bank, 437 free after). V2 stayed byte-identical.
  - The white frames are unchanged (f906-907, the run a few frames ahead).
  - v1's start of play shows no junk without it either (every frame
    f150-320 against the old v1: only timing differences).
  - **Reverted:** it changes v1 and fixes nothing seen there. v1 goes to
    hardware as it was.
- **Not fixed:** the scheme switch would need the hold (`HOLD_*`,
  `FrameDefer`, `FrameLate`, `Apply`) in v1, a large part of V2's frame
  code. Left as v1's known cosmetic frame.

**For hardware** (`dist/hardware-2026-10-17/`):
- v1 and V2, each plain and invincible-easy (`kitopt`);
- V2 has the two-button control (button 1 punches, button 2 kicks); v1
  has the one button;
- V2 has the coloured fighters, Akuma's red and the rest of V2.

### Speed: V2, v1 and the stable port (2026-10-17, the user's question)
**Carts:**
- the stable port: `Karateka-Port` at `5dc16ea`, its default cart (`81aa6570…`), kit `invincible easy` by its own `kitopt`
  (`490e9de1…`);
- v1 `4d1f07f1…` / kit `da778b96…`;
- V2 `cf6ff542…` / kit `134abaec…` (the hardware carts).

**Forced run 07** (the whole game, `replay.sh r07`, `FLIPLOG=1 FLIPN=3000`:
each flip's frame):
- The stable port takes the `TopFlip` alias at `$D6DE` (see "Speed: V2
  against the stable port").
- v1 and V2 have `$1880-$18FF` unforced (`SKEXTRA`). Their lists live
  there, and forcing them draws garbage ("DMA: the busiest lines").
- On the stable port that range is the game's own RAM, so it's forced as
  ever.
- All three made the 2,509 flips.

| frames | stable | v1 | V2 | v1 vs stable | V2 vs stable | V2 vs v1 |
|---|---|---|---|---|---|---|
| level 1 (flips 2-742) | 5,071 | 4,026 | 4,224 | −20.6% | −16.7% | +4.9% |
| level 2 (743-1341) | 4,716 | 5,172 | 5,097 | +9.7% | +8.1% | −1.5% |
| level 3 (1342-1956) | 5,624 | 4,367 | 4,501 | −22.4% | −20.0% | +3.1% |
| level 4 (1957-2308) | 3,021 | 2,529 | 2,685 | −16.3% | −11.1% | +6.2% |
| the ending (2309-2509) | 1,823 | 1,410 | 1,468 | −22.7% | −19.5% | +4.1% |
| all (2-2509) | 20,277 (338.4 s) | 17,527 (292.5 s) | 17,998 (300.4 s) | −13.6% | −11.2% | +2.7% |

**Real play, the attract's demo fight** (no input, a snapshot every flip;
from its first picture with sky to its last):
- stable 2,785 frames, v1 2,376 (−14.7%), V2 2,343 (−15.9%).
- The stable port flips more often there (224 flips against 178), so only
  frames compare.

**Reading:**
- Both 7800 builds are faster than the stable port everywhere but level
  2, where the window band's objects cost more than the stable port's
  bitmap.
- V2 against v1: slower where its colour costs DMA (level 1's torii front
  copies and the coloured 160B fighters; level 4 most, +6%, Akuma's 160B
  cells). Faster in level 2 (the top boxes' cache).
- Against "Speed: V2 against the stable port" (2026-10-16), the stable
  port's numbers agree within a few frames. V2's level 4 is up 4% since,
  Akuma's red; level 2 up 3%, from recording 02's fixes and the method
  (the lists unforced now).
- Forced replays are timing-approximate; the demo is real play.

### Level 2's windows: where the time goes (2026-10-17, V2; the user: "make the windows drawing on level 2 better optimized by using larger slices or something")
**The band** (forced run 10, flip 900, `tmp-dldump2.lua`): zones 7-9
(lines 93-112), the top's pieces, 12-13 objects a zone:
- the wall's colour bands as four wide objects (`wall2`, 9-12 bytes);
- the joints, one 1-byte object each (7 a zone);
- Mt Fuji's two pieces (palette 5);
- the gate building's side at x 120.

**The top lists** (`probes/tmp-toplist.lua`, new: both buffers' entries
at chosen flips): pieces 58 (`wall2`), 61/62 (the joint `$64D8`, plain and
mirrored), 63/64 (Mt Fuji), 55 (the gate).
- The joints are 32 pixels apart, plain left of the screen's middle and
  mirrored right of it.
- 10-13 entries a buffer in a steady picture. In the forced replay up to
  27: joints left a pixel off by the forced view, which the wall's paint
  (`$64F0`, an erasing piece) no longer covers wholly. That's the
  forced-replay artifact of "Level 2's window posts".

**The CPU** (PC samples by symbol, level 2):
- **Real play** (`probes/tmp-proff.lua`, new: `tmp-prof.lua` counting
  frames, for a recording's playback; run 10 on its own cart, f5700-7400):
  - the tiles below (`L1*`) 24.9%;
  - the game's own code 23.7%;
  - the NMI and frame code 19.0%;
  - **the top pieces 15.7%**: writing the zones' lists (`TopEmitLo`,
    `TopEmitMore`, `TopEmitMeets`) about 6%, the cover tests (`TopCover1`,
    `TopEBoxC`) 3.2%, the captures (`TopCapFind`, `TopCapL1`, `TopVis`)
    3.3%;
  - the fighters 6.5%; the flip wait 3.2%.
- **Forced run 10** (flips 800-1000): the top pieces 18.2% (the longer
  lists).

**The most there is** (an experiment build, not kept: scene 2's
`TopCapture` ignores pieces 59-62, the joints and their erasers; forced run
07):
- level 2: 5,097 → 4,489 frames (−11.9%), against the stable port's
  4,716;
- the other levels within 1% (timing).
- That is with no joints drawn at all. Each picture the game paints the
  wall over the 6-7 old joints and draws 6-7 new ones. Each of those 13
  captures runs a cover test over the whole list, and then all three zones'
  lists are written again.

**What a wider slice alone would do:** a joint strip as one wide object
per half-screen costs MARIA more than the seven 1-byte joints (about 150
cycles a line against 77). It saves CPU only if it also replaces the
per-joint captures.

**Options:**
- A: the joints as one entry, expanded when the zones' lists are written;
- B: the old joints dropped once a picture, and no cover tests for the
  joints;
- C: a pre-drawn joint strip.
The user chose A: "Level 2's windows: the joints as one entry", below.

### Level 2's windows: the joints as one entry (2026-10-17, V2; the user chose option A)
**The game's joints** (`probes/tmp-jointcap.lua`, new: every capture's
piece, column, shift and mirroring; run 10 played back on its own cart,
f5700-7400):
- 8 columns (32 pixels) apart, all with the picture's shift;
- plain to column 20 (pixel 83), mirrored from 21;
- the erasers (`$64F0`) only on the mirrored side: the plain old joints go
  under the wall's fills.

**The change** (V2):
- **The pieces** (`layout7800._T2`): the joints are of a new kind,
  `"joint"` (`TOP_FLAGS` `$0C`). Their erasers are no piece at all: a draw
  matching nothing is ignored. Only level 2 ever had `"erase"` pieces, so
  `TopCapture`'s erase path is `#V1` now.
- **One entry a buffer:**
  - It is of the plain joint's piece, a box like any other: its left pixel
    the leftmost joint's, its bytes 0 to the last joint's first + 1.
  - So the fills trim it as they trimmed the joints, and the gate's covers
    leave it.
  - `L2Joint` (from `TopCapture`):
    - a joint while the list's last entry is the joints' widens it;
    - one off its 32-pixel grid (a new view) starts it again;
    - otherwise the old entry goes (`TopOne`) and a new one is put at the
      end, after Mt Fuji and before the gate, as the game draws them.
- **The zones' lists:**
  - The joints' piece's slices are `$FE` (the build: `joint_at`). Its real
    columns, and the mirrored joint's, go to `L2JZT` as `J_*` equates.
  - `TopEmitLo` jumps to `L2JEmit` on `$FE`. It writes one 1-byte object
    a joint, as `TopEmitLo` writes a piece's, the room check per object,
    and goes back to `TopEmitSkip`.
  - So MARIA reads what it read before.
- **Where the code is:** a new section, `;;; LEVEL2PAGE`, placed in bank 2
  only (353 bytes in two parts).
  - Its labels go to the far pieces (`far_eq`, `far_ph`).
  - It calls far routines (`TopOne`, `TopBufY`, `TbcStale`, `TopStale`),
    so it is placed with those labels at a placeholder and assembled again
    in the far pieces' second pass (`placed`).
- **Shared code:** the hooks are about as many bytes as the dead erase path
  they replace. Bank 4's per-page copies fit as before (1,941 free).
  - A first version (the erasers kept as a kind, a `JSR` and a `JMP` at
    each hook) put `TopCapture`'s off-screen branch out of range (141) and
    left bank 4 70 bytes short again.

**Checked:**
- `probes/tmp-jointchk.lua` (new: at each flip, a buffer's joints entry
  against the joints the game drew into it, and each joint's mirroring
  against the pixel-84 rule), forced, `$1880-$18FF` unforced:
  - run 07: 330 buffer pictures, none wrong;
  - run 10: 252, none wrong.
- Forced run 07's level 2 window band: joints even, over Mt Fuji, the gate
  over them.
- v1 byte-identical (`4d1f07f1…`).
- Run 10 played on the new cart drifts in level 1 (timing), so it gives no
  real-play pictures of level 2.

**Speed** (forced run 07, frames):
- level 2 5,097 → 4,771 (−6.4%; the experiment's ceiling was −11.9%);
- the other levels within 1%; all 17,998 → 17,777.
- Level 2 is now 1.2% behind the stable port's 4,716, against 8.1% before.
- What's left of the experiment's saving: the joints' objects are still
  written each picture (and read by MARIA). The other entries' lists are
  as before.

V2 `56b9ab1731a2165bd3459d134f90bbf0`. Checkpoint
`2026-10-17_KEEP_enh-v2l2joints`.

### The hardware test (2026-10-17/18; the user's own openFPGA 7800 core on the Analogue Pocket, `Miasmark/openFPGA-7800`; cart `dist/hardware-2026-10-17b` V2)
The user's notes:
- the attract demo: flickering first frames; a post hanging mid air where
  there is no wall; the torii missing its foreground piece (a screenshot:
  only a thin line where the front post should be);
- level 2: a frame corrupts before the cutscene after the first guard; the
  first hawk after the cutscene nearly invisible; the hawk leaves a ghost at
  the screen's edge for a few frames; the gate's tips stationary on the
  screen, not where the gate is, right only when scrolled fully;
- level 3: the health arrows flicker;
- the ending: if the princess kicks the player, her leg stays.

**MAME first:** the attract notes all show in MAME (the real-play attract,
`attract.sh`), so they are the port's.

**The torii's front post missing in the attract** (since "The torii in
front", 2026-10-16):
- That change made level 1's torii posts front shapes drawn only over a
  fighter (`FR` 3, `L1FrHit`), on the grounds that the tiles draw them
  otherwise.
- The rule went by image (`L1_FRONT`), so it reached the attract loop's
  set too. There the white torii's front post (`$A684`) is a front column
  of its own (`worldcfg` `front_cols`), not in its tiles, so it was drawn
  only over a fighter.
- **Fix:** `FR` 3 in level 1's set only (`l1scene7800.tables`,
  `CUR.sid == 0`).

**The flicker: the fence's posts every other picture** (since "Recording
02"):
- From the demo's start (picture 500), one buffer lacked the fence's posts
  and the rails across Mt Fuji's base. The fence's black pixels alternate
  788/660; `v2r10b` was steady at 788.
- `probes/tmp-l1inst.lua`:
  - at f5620 the view's half pixel (`$50` bit 0) changes;
  - the game redraws the posts into B;
  - A gets them by the game's buffer copy (`L1Copy`).
- `L1Copy` copied the instances and the view, but not `L1_VP` (recording
  02's half pixel). So A's next flip took it for a view change and dropped
  what it was given.
- **Fix (V2):** `L1Copy` copies `L1_VP` too.
- Checked: the attract's fence steady from the demo's start. Against
  `v2r10b`, 80 of 600 pictures differ:
  - the torii's front post now drawn (523 on);
  - the Akuma-and-hawk scene a step apart (437-441).

**The post "hanging mid air"** (a post's top, two small pieces, just left
of the wall's start over the sea at the demo's start): in v1 too, so older.
Not looked into yet.

**Room** (the `L1Copy` fix's 6 bytes broke the build: bank 4's per-page
parts 70 bytes short, as twice before):
- **Freed:**
  - `AkTab`, `AkChunk`, `AkMore`, `AkCells`, `AkNext` (the pose tables'
    walkers): only v1's `AkPre` uses them, so in V2 they are `#V1`.
  - The pose entries' image-bank byte: `AkFind` never read it, only
    `AkPre` did. V2's entries are 7 + 2n bytes (`AKP_NOFF` 6, v1's 7):
    Akuma's table 786 → 729 bytes, the hawk's 470 → 438.
- `AKP_TO_FIXED` 400 → 300: otherwise the pose tables took the fixed
  bank's last runs before `L1PartDd`'s parts.
- Bank 4 now keeps 2,161 bytes after its per-page copies (1,941 before).
- **Dead ends kept as options:**
  - `PG_HOLD`: bank 4's per-page parts held at best fit before the
    level-1 pieces (it works, but then the pose tables are short), now ().
  - A finer-cut retry with made cuts: many parts can't go under 11-13
    bytes, and bank 4's free runs are nearly all under 8 (the release's
    holes). Taken out.
- Checked: forced run 10, every 4th flip, against `v2l2joints`. 53 of 540
  pictures differ, all fighters a frame apart. Akuma and the hawk are drawn
  (the pose search with the new entries).
- v1 byte-identical.

V2 `8bd6a2fee09e8dced579a44d963c1369`.

**Still open** (not reproduced yet):
- Level 2's notes. In MAME's forced run 07 the hawk after the cutscene is
  grey and plain (flips 820-850).
- Level 3's arrows.
- The princess's kick (never played in any recording).
- They may be the core's (its DLI and DMA timing: the hawk's grey is
  written early by `NmiDli` after 4 `WSYNC`s), or real play's.

### The hardware test, round 2: the user's MAME recordings (2026-10-18)
`inp/karateka7800-v2-01.inp` (the plain cart, 11,364 frames) and
`...-v2-invincible-easy-01.inp` (15,368 frames), both on `v2hw1`'s carts
(`8bd6a2fe…`, `4c1971b5…`), so they play back exactly. The user: the kick
button seemed to lock up after rapid presses (the first); the first hawk
on level 2 invisible, the floating gate tips (the second); no flicker of
the arrows seen in MAME (whose frame blending hides it); the princess's
kick leaving her leg.

**The invisible first hawk:**
- At f5300-5390 its shadow crosses the floor, and the band's lists hold no
  hawk at all.
- `tmp-l1find.lua`: the hawk's draws were mirrored, `$AB2B`/`$AB64` at row
  95 and `$AAC5` at row 86. None was in level 2's inventory (`s2shapes.txt`,
  from earlier runs), so the capture dropped them. The second hawk flew
  plain and showed.
- **Fix (V2):** the inventory gets the hawk's six images at all their rows
  (level 3's table, `akposes.txt`, shows three a picture), both ways: 17
  shapes, level 2 64 of the 127.
  - As `V2 ` lines: v1's level 2 has no cart RAM for them.
    `tiles_inventory` reads the prefix now.
- Not seen in play yet: the recording drifts on the new cart (still at the
  first guard at f5260).

**The gate's tips floating:**
- At f7900-7996 the portcullis's bottom row stands at the screen's right,
  where the gate will be, while the gate is still off screen. They join
  only when it is in place.
- `FtEmitPc` drew the portcullis at column 32 always (where it is in
  place), and `PcCap` kept only its rows.
- **Fix (V2):** `PcCap` keeps the bar line's column and shift (`$05`,
  `$10`) in `PC_COL`/`PC_SH` (Akuma's capture arrays' last entries, as
  `PC_V` does), `FtCopyR` copies them, and `FtEmitPc` draws there
  (`FtPcCol`).
- Checked: forced run 07, the gate scrolling in (flips 72-75 of the
  sample): bars and tips inside its frame. In forced run 10 the floating
  tips (flip 1000) are gone.

**The hawk's ghost at the edge:**
- After the second hawk flies out at the right (f5770-5780), two grey
  pixels stay at x 318-319, row 149, until well past f5838.
- `L1Fill` drops an instance whose middle a fill covers. The hawk's middle
  was past the screen's right, the fill (the game's erase) clipped to it.
  The left edge already had its rule ("still left of 0: covered by a fill
  from 0").
- **Fix (V2):** a middle past 160 counts as covered by a fill reaching the
  right edge.

**The princess's leg:**
- Her kick is two shapes, `$A2EE` (the leg, column 21) and `$BB29`
  (column 23). Standing she is `$B430` and `$A280` at column 24
  (`probes/tmp-l1add.lua`, new: every instance added, with the game's
  column).
- The game's fill for her covers columns 23-32 (`probes/tmp-l1fill.lua`,
  `tmp-l1fillgo.lua`, new), which takes out `$BB29` but misses the leg's
  middle.
- On the original the leg goes under the player's fighter-box erase
  (columns 16-27, he falls right there). The port passed fighter-box
  erases over for the instances.
- **Fix (V2):** a fighter-box erase now goes through `L1Fill` too
  (`L1FillGo`'s `S_NOFILL` path jumps to `L1FillC`). There it takes out
  only the rooms' figures, `L1K_W` bit 5:
  - `worldcfg`'s `figures` plus a new `fbox` set: the princess's kick,
    `$A2EE` and `$BB29`;
  - `l1scene7800` `sh.fbox`, `tables()` `FB`.
- Not seen in play yet (the recording drifts on the new cart). By the log,
  the erase at f14858 covers the leg's middle.

**The enemy's arrows flickering** (probably the user's level 3 flicker on
the Pocket):
- Forced run 10 shows them grey in some pictures and blue in others, in
  both builds (pictures 129 and 213 of the comparison).
- `probes/tmp-palline.lua` (new: every palette write with the frame's NMI
  count; this MAME's Lua has no beam line):
  - the band's grey `$08` goes into P1C2 at the count-5 NMI;
  - the status bar's blue `$88` at the count-8 one.
  - In some frames (one in four at flips 520-521) the count-8 writes are
    missing. Once the band's set came at count 6: the frame's NMI count
    slipped by one, so the status bar's handler didn't run and the arrows
    kept the band's grey.
- Not fixed yet. It looks like the open item "the NMI's list building
  drops DLIs".
- **Correction** ("The flickering arrows", below): the count didn't slip.
  The forced replay wrote the game's own DLI counts back at `TopFlip`,
  mid-frame. Left alone, MAME's arrows are blue in every frame. The
  Pocket's flicker is a late status set.

**The kick button "locking up"** (the plain recording,
`probes/tmp-btnlog.lua`, new: both buttons and `$46`/`$47`/`$C4`/`$DB`/
`$DC` each frame they change):
- 181 presses of button 2. Each one either made a kick request (`$46`
  `$FF`) or found one waiting.
- Every request was taken by the game (`$FF` → `$80`) within 1-79 frames,
  and the pictures show kicks through every burst (f1360-2000,
  f6440-6920, f7470-7720, f8260-8620).
- No press is held long (the longest 39 frames).
- So nothing lost in the port's button code in this recording. Asked the
  user when it happened.
- The port's own rule refuses a kick while a punch waits, as the game's
  routine did.

**Room** (the new code: `AKP_TO_FIXED` 300 → 160; bank 4 2,012 bytes after
its per-page copies).

v1 byte-identical (`4d1f07f1…`). V2 `d741b03c2ddd5759b7a478166b920631`.

**The kick button "locking up": MAME's Left Alt** (the user: "after the
first few guards and the second run, maybe it's a problem with using alt"):
- In the plain recording's second game, the fight at f7284-7476 has punches
  but no button-2 press at all until f7476, then kicks again.
- A recording holds only what MAME received. Under Windows, a lone tap of
  Left Alt (MAME's default for button 2) in a window opens the window's
  menu, and the keys go there until the next tap.
- So the presses never reached MAME; the port's button code is not
  involved.
- **Fix (the tooling):** `mame-ctrlr/karateka7800.cfg` maps P1 Button 2 to
  Space or Left Shift. "Record Karateka 7800.bat" passes `-ctrlrpath
  mame-ctrlr -ctrlr karateka7800`.
  - Checked: MAME reads it (P1 Button 2 = `KEYCODE_SPACE OR
    KEYCODE_LSHIFT`).
  - Recordings store the buttons, not the keys: the old ones play back the
    same.

### The flickering arrows (2026-10-18, V2; the Pocket's level 3 note)
The user saw the enemy's health arrows flicker on the Pocket in level 3,
not in MAME.

**The game's two counts.** The game's DLI handler (`$1026`) counts its
calls in `$0F14` (the port's `$1A9A`). The third and sixth set colours
(`$10F4`), and those count again in `$0F0E` (`$1A94`), which picks the set:
1 is the band's, 2 the status bar's.
- The status set puts palette 1's colours in `$25`-`$27`. The enemy's
  arrows are colour 2 (`$26`): blue `$88`, against the band's grey `$08`.

**A dead end: the forced replay.** Forced run 10 showed the arrows grey
in some frames.
- `probes/tmp-nmiseq.lua` (new: each frame's NMIs in order, P1C2's
  writes, and the counts' writes with the PC) found `$E07F` (`TopFlip`)
  writing both counts.
- `TopFlip` is where the stateplay probe writes each flip's recorded game
  state back, mid-frame. That restarted the game's counts, so its colour
  sets came at the wrong DLIs.
- With `$1A94` and `$1A9A` not forced: in flips 300-1100, all 1,957
  level 3 frames write the status bar's blue.
- **Fix (the tooling):** `port/replay.sh` now leaves both counts alone by
  default.

**The cause: a music DLI running into the status bar's.**
`probes/tmp-dlimargin.lua` (new) times each NMI's arrival and each game
handler's start and end, in lines after the vertical blank's NMI. It uses
machine time, because this MAME's Lua has no beam line.
- Level 3 (the sky's lists): the count-7 handler (music) starts at line
  ~186 and ends as late as 213.6. The status bar's DLI (count 8) arrives at
  214.4: a margin of 0.9 lines.
- The scenes without a sky: count 5's music handler ends as late as 216.4,
  past the status DLI's arrival (214.6). There MAME already puts it off
  now and then.
- The game's handler writes the status colours after its own `STA WSYNC`
  (`$1143`): at line 218.85 when on time.
- A DLI that comes while another runs waits for it (`S_DLIPEND`). If the
  music tick runs a few lines longer, as on a slower core, the status set
  comes late and the arrows' top rows keep the band's grey. That's the
  "Late colours" fault of 2026-09-29, on the status bar.

**Fix (V2): the status bar's colours written in the NMI when the game's
handler can't come on time.**
- `ColTail`, at the status set (`G_L0F14` 6), keeps palette 1's three
  colours (less the fade `$0F12`) in `P6E` and the NMI's number in
  `P6E_N`. It does this at its end, after its own writes, so their timing
  stays as it was.
  - (Placed after `STA FT_PALR` at first, the capture pushed `$32`-`$3D` a
    line later, and row 184, the floor's last line, changed colour.)
- `NmiVbi` latches `P6E_N` into `P6E_A` and clears it, so only last
  frame's set counts. The game's handler not running (DLIs off, the blank
  list) leaves none.
- `NmiDli`, at count `P6E_A`: if a DLI handler is still running
  (`S_INDLI`) or the vertical blank's is (`S_INVBI`), it waits four line
  ends and writes `P6E` to `$25`-`$27`, on the line the game's handler uses
  when on time. Otherwise it leaves them to the game.
  - Written at once, or after one or two `WSYNC`s, the colours reached the
    floor's last line (row 184).
  - Written every frame (four `WSYNC`s), the game's handler ran four lines
    later, and with it palettes 3, 4, 6 and 7.
- Room: `AKP_TO_FIXED` 160 → 100 (the level-1 pieces didn't fit).

**Checked:**
- Against the build with the write off, over run 10 at flips 300-1100 (one
  picture every 8 flips): 6 of 101 pictures differ, all fights at another
  moment (forced replays drift on any new cart). None on row 184.
- A test build slowed count 7's handler by 20 lines, as a slower core
  would (`slowdli.py` in the session's scratch, not kept). Flips 400-700, a
  picture every flip:
  - without the fix, 1 of 133 pictures with the enemy's arrows had their
    top rows grey;
  - with it, 0 of 136.
  - The log shows the early `w8=88` before the put-off handler (`P8`).
- All of run 10 (2,163 flips) plays through. A picture every 100 flips
  looks right.
- Not seen on the Pocket yet.
- v1 byte-identical (`4d1f07f1…`). V2 `3013468cbc3c1442161e89c5ed2ff21a`,
  invincible-easy `9be42d69c5b0a41dbd182468be6f9697`.

**Seen on the way, not followed yet:** the build with the early write off
(timing only differs) showed at flip 684 (picture 48) the level 2 windows'
third and fourth panes without their joints, and a joint standing inside
the third. The other carts were at a slightly different moment there. So
it looks like a timing-dependent fault in the joints as one entry. Open.

### The messenger's trim (2026-10-18, V2; the user: "in the cutscene the guard reporting has one accent color coming in and a different one leaving")
- `probes/tmp-typelog.lua` (new: the guard's type `$3E`, the scene, the
  strength and both buffers' world `L1_WLD`, each time one changes): in run
  10, `$3E` is 1 for the whole cutscene (flips 178-216). So the type isn't
  the cause.
- The pictures, a flip each: coming in, the messenger's trim is the
  player's blue `$86` (palette 6). Leaving, it's type 1's red `$46`
  (palette 7).
- The coloured parts are 160B, and each pixel picks palette 4-7 itself,
  so P6 against P7 is in the pre-cut art. It goes by the fighter as the
  builder deduces it from the mirroring ("The fighters coloured": a plain
  image is the player's, except poses 28-32).
  - The messenger runs in facing right, unmirrored like the player, so he
    has the player's parts. He leaves facing left, in the guard's.
- Akuma in that room is the tiles' (the game's colours), not a coloured
  fighter, so palette 7 is the messenger's alone.
- **Fix (V2):** `FtColours`: while both buffers show the cutscene's room
  (world 3, the only time there's no player), palette 6's colours 2 and 3
  take the guard's trim, as palette 7's do.
  - World 3 shows up only in level 1's cutscene in run 10. Both buffers
    from flip 180 to 216; the messenger is on screen from 188 to 210.
  - The guard's trim stays in Y from palette 7's lines; `CMP #$03` leaves
    carry set, so `BCS` makes the branch.
- Room: `AKP_TO_FIXED` 100 → 80.
- **Checked** (run 10, a picture every flip 176-240): the messenger's trim
  is red coming in (188-204) and leaving (206-208). After the cutscene
  the player has his blue again (216-232), and the next guard is red.
- v1 byte-identical (`4d1f07f1…`). V2 `847a9051dd0d1b11e625f0f657037547`,
  invincible-easy `11dcee9743beb8e50c6d7159e7f92c4f`.

**Checkpoint and carts:** `Karateka-Port-checkpoints/2026-10-18_KEEP_enh-v2arrows`
(source, probes, FINDINGS, `work/v2`'s carts and maps). For the Pocket:
`dist/hardware-2026-10-18c` (V2 `847a9051…`, invincible-easy `11dcee97…`).
Run 10 replayed whole on it: 2,163 flips, the status bar's blue in all
1,502 level 3 frames of flips 400-700.

### Speed: the release carts (2026-10-18)
Forced run 07 again (`replay.sh r07`, `FLIPLOG=1 FLIPN=3000`), on the
final carts, all three under `replay.sh`'s new defaults (the game's DLI
counts `$1A94`/`$1A9A` unforced, "The flickering arrows"; they're the same
two bytes on the stable port, whose `$0F17` is at `$1A9D`):
- stable `5dc16ea`, cart `81aa6570…`, kit `invincible easy` `490e9de1…`
  (`END=21500`: the stable port needs about 20,300 frames, past `r07`'s
  default 18,900, which stopped it at flip 2,310);
- v1 `4d1f07f1…`, kit `da778b96…`;
- V2 `847a9051…`, kit `11dcee97…`.
- v1 and V2 with `$1880-$18FF` unforced (`SKEXTRA`), as before. All three
  made the 2,509 flips.

| frames | stable | v1 | V2 | v1 vs stable | V2 vs stable | V2 vs v1 |
|---|---|---|---|---|---|---|
| level 1 (flips 2-742) | 5,075 | 4,031 | 4,358 | −20.6% | −14.1% | +8.1% |
| level 2 (743-1341) | 4,715 | 5,244 | 4,897 | +11.2% | +3.9% | −6.6% |
| level 3 (1342-1956) | 5,612 | 4,349 | 4,650 | −22.5% | −17.1% | +6.9% |
| level 4 (1957-2308) | 3,035 | 2,538 | 2,729 | −16.4% | −10.1% | +7.5% |
| the ending (2309-2509) | 1,823 | 1,405 | 1,514 | −22.9% | −17.0% | +7.8% |
| all (2-2509) | 20,282 (338.3 s) | 17,590 (293.4 s) | 18,173 (303.1 s) | −13.3% | −10.4% | +3.3% |

Against the 2026-10-17 table:
- the stable port and v1 agree within 1%;
- V2's level 2 is 3.9% faster (5,097 → 4,897: the joints as one entry);
- its levels 1 and 3 are about 3% slower (4,224 → 4,358, 4,501 →
  4,650), and level 4 and the ending 2-3%. That's the Pocket rounds' fixes
  (the hawk's shapes in the inventory, the fighter-box erases through
  `L1Fill`, the portcullis's column) and the status set's capture in
  `ColTail`. Not split further.

### The release: build from a clone, the options checked (2026-10-18)
**Build from a clone** (as the stable port's `f427648`/`7c572c9`):
- `build7800.py --car` (else `KARATEKA_CAR`, else `Karateka.car` in the
  top folder, else `../karateka/Karateka.car`).
- `--v2` builds V2. It's the same as `V2=1`, which is awkward from
  Windows' `cmd`.
- The unused `--bankset` flag is gone: every build is BankSet.
- `census/` holds what the build reads from the census (`port/mkcensus.py`
  from `work/analysis`). It came out byte-identical to the stable
  repository's, `reloc.txt` included.
- The toolkit is the `a7800-toolkit` submodule, else a checkout beside
  the folder.
- `sndconv.py` keeps its own TIA periods instead of
  `a7800-toolkit-local`'s `tracker.py`.
- `mkkit.py` imports `abp` only to make a kit.
- An audit hook on every file the builds open: they read only the
  cartridge, `census/` and `port/`'s text tables (addresses, rows and
  counts the probes saw, no cartridge bytes). A scan for literal byte runs
  in everything that goes in the repository found only opcode sets,
  address ranges and checksums.
- Both builds unchanged: v1 `4d1f07f1…` (SHA-1 `071d95f8…`), V2
  `847a9051…` (SHA-1 `bbf38030…`).

**The options on both builds** (`kitopt.py`; `playkey.lua` playing, a
picture at flips 500 and 800):
- `start-level2` and `start-level3` reach their level and play (`$D0` 2 or
  3), in v1 and V2.
- `invincible easy` plays level 1.

**A false alarm in the rules MAME:** on v1 started at level 2 or 3 (and in
the 10-17 cliff-fall runs), `a78.exe` printed "the CPU fetched an
instruction from bankset cart RAM ($7210)".
- `probes/tmp-bp7210.lua` (new: debugger breakpoints at every address
  `$7000-$73FF`, and MARIA's own reads of `$7210` through her DMA space)
  found no instruction run there.
- MARIA read `$7210` 230 times, from frame 2,668.
- So `bankram_window_r` (`port/mame/mame_bsrules.py`) saw a MARIA read
  without her DMA flag (the read path `mame_mariaspace.py` added) while
  the halted CPU's SYNC was up. The cartridge is fine; the check is wrong.
  Not fixed in the MAME build.
