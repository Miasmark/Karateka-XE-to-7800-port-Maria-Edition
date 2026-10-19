; sys7800.asm -- the 7800 side of the XEGS Karateka port (fixed bank).
;
; Assembled by port/build7800.py, which puts equates for every address used
; here in front of this file (hardware, system variables from layout7800.py,
; the game's relocated symbols as G_*, table and image addresses) and the
; generated tables after it. The jump table must stay first: the game is
; linked against its addresses (link7800.py SYS_ENTRIES, in the same order).
;
; Conventions kept from the XEGS: the game's vertical-blank handler expects
; A, X, Y pushed (it ends PLA/TAY/PLA/TAX/PLA/RTI); its display-list handler
; saves its own registers. Both are entered as interrupts, with a return
; frame to our epilogue pushed first, so their RTI comes back here.
;
; ZP_P1 and ZP_P2 are the game's $00/$01 and $02/$03 (the XEGS loader used
; them too). Code that runs inside the NMI saves and restores them.

; ------------------------------------------------------------ jump table
SysZpSwap:
    JMP ZpSwap
SysZpClear:
    JMP ZpClear
SysLoadCommon:
    JMP LoadCommon
SysLoadScene:
    JMP LoadScene
SysWaitLine200:
    JMP WaitFrame
SysReadStick:
    JMP ReadStick
SysBlitBank:
    JMP BlitBank
SysBlitDone:
    JMP BlitDone  ; #V1
    JMP OsStub              ; (V2: never run: every scene's draws captured) #V2
SysSetVBV:
    JMP SetVBV
SysOsStub:
    JMP OsStub
SysCommonTail:
    JMP CommonTail
SysSound:
    JMP Sound
SysSetDlist:
    JMP SetDlist
SysRowBase:
    JMP RowBase  ; #V1
    JMP OsStub              ; (V2: never run: every scene's draws captured) #V2
SysDliExit:
    JMP DliExit
SysRowNext:
    JMP RowNext  ; #V1
    JMP OsStub              ; (V2: never run: every scene's draws captured) #V2
SysRowNextC:
    JMP RowNextC  ; #V1
    JMP OsStub              ; (V2: never run: every scene's draws captured) #V2
SysClearBuf:
    JMP ClearBufF
SysCopyBuf:
    JMP CopyBufF
SysRowAddr:
    JMP RowAddr  ; #V1
    JMP OsStub              ; (V2: never run: every scene's draws captured) #V2
SysRowWrap:
    JMP RowWrap  ; #V1
    JMP OsStub              ; (V2: never run: every scene's draws captured) #V2
SysStoryStep:
    JMP StoryStepF
SysTitleLogo:
    JMP TitleLogoF
SysTitleCopy:
    JMP TitleCopyF
SysEndText:
    JMP EndText
SysTopFlip:
    JMP TopFlip
SysTopColumn:
    JMP TopColumnF
SysFwLo:
    JMP FwLo
SysFwHi:
    JMP FwHi
SysTextIn:
    JMP TextInF
SysFRec:
    JMP FRecF
SysColTail:
    JMP ColTail
SysFtEnd:
    JMP FtEnd
SysFtEnd2:
    JMP FtEnd2
SysFgCol:
    JMP FgCol
SysMaskP:
    JMP MaskP
SysMaskE:
    JMP MaskE
SysFlip0:
    JMP Flip0
SysStarM:
    JMP StarM
SysStarS:
    JMP StarS
SysAkW:
    JMP AkW
SysHawkW:
    JMP HawkW
SysNoFill:
    JMP NoFill
SysNoPat:
    JMP NoPat
SysErE:
    JMP ErE
SysErP:
    JMP ErP
SysL1Fetch:
    JMP L1Fetch
SysL1Col:
    JMP L1ColF
SysL1Fill:
    JMP L1FillF
SysL1Pat:
    JMP L1PatF
SysBlSetup:                 ; (the blitters in ROM: ;;; FAR (BlRom))
    JMP BlSetup  ; #V1
    JMP OsStub              ; (V2: never run: every scene's draws captured) #V2
SysBlSh:
    JMP (BL_SHV)
SysBlLoopN:
    JMP BlLoopN  ; #V1
    JMP OsStub              ; (V2: never run: every scene's draws captured) #V2
SysBlLoopM:
    JMP BlLoopM  ; #V1
    JMP OsStub              ; (V2: never run: every scene's draws captured) #V2


; ------------------------------------------------------------------ boot
Reset:                      ; (the rest in the top bank: ResetB, then ResetTail)
    SEI
    CLD
    LDA #$07
    STA INPTCTRL            ; lock: MARIA on, BIOS off
    LDA #$7F
    STA CTRL                ; DMA off while we set up
    LDX #$FF
    TXS
    LDA #$04                ; the left joystick's two buttons: port B bit 2 an  #V2
    STA CTLSWB              ; output, low (the right one stays one-button: the  #V2
    LDA #$00                ; vs fight's player 2)  #V2
    STA SWCHB  ; #V2
    LDA #TOP_BANK           ; #V1
    LDA #LOADER_BANK        ; (V2: the boot's body is the loader bank's) #V2
    STA BANKSEL
    JMP ResetB
ResetTail:
    BIT MSTAT               ; (in the vertical blank: MARIA mid-frame would read
    BPL ResetTail           ; one list through its stale pointer)
    LDA #$40
    STA CTRL                ; DMA on, 160A; it stays on (a blank list stands in for "off")
; the XEGS boot ($B7B1): scene 0, all banks, then the title's main entry
    LDA #$00
    STA G_ZD0
    STA S_SCENEBANK
    JSR LoadCommon
    JSR LoadScene
    CLI
    JMP G_ENTRY0

; -------------------------------------------------------------- the NMI
; MARIA raises it at the end of a zone whose DLL entry has the DLI bit set:
; the game's six display-list interrupt lines, then line VBI_LINE (241) of every
; list, which stands in for the XEGS vertical blank (ANTIC's comes at the same
; display-list line). They are told apart by count, and the count cannot drift:
; every list has the same seven NMIs (the blank list in ROM carries six dummy
; DLIs to match; MARIA reads the list's address only at the start of a frame,
; so a switch never changes the frame under way). As a safety net the vertical
; blank is confirmed by MARIA's own flag: line 241 ends two lines before
; vertical blank, so the NMI the count names waits (up to VBI_SPIN turns, about
; 12 lines) for MSTAT to show it; if it never does, the NMI was mid-screen, is
; taken for a DLI, and the count is set so the next NMI is the vertical blank.
; (RIOT's timer did this for a while; RIOT is not safe to use while MARIA
; halts the 6502, so it is not used: FINDINGS "Palette", "No RIOT timer".)
; The NMI begins in console RAM (NMI_STUB, copied with the static lists at
; the boot; the vector points there): PHA (the interrupted A), then either
; JMP NmiGo, or, while the title's or story's list is shown (TsFirst):
;   LDA TS_CHTV+n / STA M_CHBASE    this NMI's zone's CHBASE, 17 cycles in
;   INC, INC (the two operands)     the next NMI's entries, 29 cycles in
;   LDA TS_CHTP+n+1                 ours alone? (the flags a place on)
;   BNE: INC S_NMICOUNT, PLA, RTI   ours alone: counted and done
;   JMP NmiGo
; A zone's DLI comes as MARIA moves into it, and MARIA reads its first line
; at the next line's start: a text line's DMA leaves the CPU about 40 cycles
; of the line, and a DLI of ours can come a line after the game's (FINDINGS
; "The title and the opening scroll in bank 0's MARIA copy")
Nmi:
NmiGo:
    LDA S_BANK
    PHA                     ; the bank the interrupted code had
    LDA S_SCENEBANK
    STA S_BANK
    STA BANKSEL             ; the handlers live in the scene page
    INC S_NMICOUNT
    LDA S_NMICOUNT
    CMP S_NMIVBI
    BCC NmiDli
    JMP NmiVbiCheck
; A DLI. The game's handler ($1026) saves X and Y itself and leaves through
; DliExit (its ending, $1034, patched), so the stack holds only A and the
; bank here, and X and Y are still the interrupted code's.
; The game's DLI and vertical-blank handlers save their working bytes ($14/
; $15, $03/$04) in the same place, so none may run inside another; on the
; XEGS they are lines apart. Two DLIs can be as little as 3 lines apart
; (scene 0's own $19B3), less than the handler takes here, and a DLI inside a
; DLI saved the outer one's pointer as the blitter's: the blitter then drew
; into the engine (FINDINGS "Drawing below the screen"). So a DLI that
; arrives during another runs as soon as that one ends. A vertical blank
; that arrives during a DLI waits for it to end; one that arrives while the
; last is still running (it built a list, which can take more than a frame)
; is dropped, as a late XEGS vertical blank would have been; a DLI during the
; vertical blank is dropped, and so are the blank list's dummy DLIs (the
; XEGS gets none with DMA off).
NmiDli:
    LDA S_NMICOUNT
    CMP P6E_A               ; (the status bar's colour DLI: palette 1 as #V2
    BEQ NmiDliS             ; last frame's set made it, at once: a music #V2
                            ; DLI's handler can run into it; FINDINGS "The #V2
                            ; flickering arrows") #V2
    CMP P3E_N               ; (the band's colour DLI: the colour 2 its set #V2
    BNE NmiDliG             ; changes in palettes 1, 6 and 7, and a tiles #V2
    LDA G_ZD0               ; set's palette 5 below the split, at once, as #V2
    CMP #$02                ; last frame's; the game's handler is lines late: #V2
    BEQ NmiDliW             ; FINDINGS "The hawk's blue", "Run 10". A only: #V2
    LDA S_L1                ; X and Y are the interrupted code's) #V2
    BEQ NmiDliE             ; #V2
    LDA L1PE                ; #V2
    STA L1_PALR             ; #V2
    LDA L1PE+1              ; #V2
    STA L1_PALR+1           ; #V2
    LDA L1PE+2              ; #V2
    STA L1_PALR+2           ; #V2
    JMP NmiDliE             ; #V2
NmiDliW:                    ; (level 2: past the windows' last rows first, #V2
    STA WSYNC               ; before the game's handler gets its few cycles #V2
    STA WSYNC               ; a line: the hawk's and the fighters' top rows; #V2
    STA WSYNC               ; its windows' palette 5 left to the handler, #V2
    STA WSYNC               ; and palette 3 its own) #V2
    LDA P3E_G               ; #V2
    STA TOP_PAL2R+1         ; #V2
NmiDliE:                    ; #V2
    LDA P3E_G               ; #V2
    STA MP1C2               ; #V2
    STA MP6C1               ; #V2
    STA MP7C1               ; #V2
    LDA S_NMICOUNT  ; #V2
    BNE NmiDliG             ; (always: the count is 1 or more here) #V2
NmiDliS:  ; #V2
    LDA S_INDLI             ; (only when the game's handler can't come on #V2
    ORA S_INVBI             ; time: put off behind another DLI's, or #V2
    BEQ NmiDliS1            ; dropped in the vertical blank's) #V2
    STA WSYNC               ; (on the line the game's handler writes them #V2
    STA WSYNC               ; on time: the floor's last line keeps the #V2
    STA WSYNC               ; floor's colours) #V2
    STA WSYNC  ; #V2
    LDA P6E  ; #V2
    STA MP1C1  ; #V2
    LDA P6E+1  ; #V2
    STA MP1C2  ; #V2
    LDA P6E+2  ; #V2
    STA MP1C3  ; #V2
NmiDliS1:  ; #V2
    LDA S_NMICOUNT  ; #V2
NmiDliG:  ; #V2
    CMP S_NMIPD1            ; the top's sky (FINDINGS "The top rows as
                            ; objects"): on for its lines, off below them
    BEQ NmiSkyOn
    CMP S_NMIPD2
    BEQ NmiSkyOff
    LDA S_INDLI
    ORA S_INVBI
    ORA S_SHOWBLANK
    BNE NmiDliNot
    BIT S_NMIEN
    BPL NmiQuit             ; display-list interrupts off  #V1
    BPL NmiDliOff           ; display-list interrupts off  #V2
NmiDliRun:
    INC S_INDLI
    LDA S_NMICOUNT          ; (V2: its own number, for ColTail's latch: by the #V2
    STA DLI_NUM             ; handler's end another NMI may be counted) #V2
    JMP (S_VDSLST)          ; the game's handler, out through DliExit
NmiDliNot:
    LDA S_INDLI
    BEQ NmiQuit             ; in the vertical blank, or the blank list's
    INC S_DLIPEND           ; the last DLI is still running: after it
NmiQuit:
    PLA
    STA S_BANK
    STA BANKSEL
    PLA
    RTI
NmiSkyOn:                   ; (into the flagged line, which is opaque: the
    LDA S_SKY               ; moment within it doesn't show; FINDINGS "The
    STA WSYNC               ; top rows as objects")
    STA WSYNC
    STA BACKGRND
    JMP NmiQuit
NmiSkyOff:
    LDA #$00                ; (the game's background: always black)
    STA WSYNC
    STA WSYNC
    STA BACKGRND
    JMP NmiQuit
; (V2) a DLI with the game's off: in play, its pause between scenes, its  #V2
; screen cleared; this frame's list is still the play picture's (the blank  #V2
; list comes next frame: FrameKey), and without the game's DLIs level 1's  #V2
; tiles showed a row of junk: every palette black for the rest of the frame  #V2
; (the game's colours come back with its vertical blank and DLIs)  #V2
NmiDliOff:  ; #V2
    JSR FrameKey  ; #V2
    BNE NmiQuit             ; (not in play)  #V2
    TXA  ; #V2
    PHA  ; #V2
    LDX #$1F  ; #V2
NmiDliOff1:  ; #V2
    TXA  ; #V2
    AND #$03  ; #V2
    BEQ NmiDliOff2          ; (not a palette's colour)  #V2
    LDA #$00  ; #V2
    STA BACKGRND,X  ; #V2
NmiDliOff2:  ; #V2
    DEX  ; #V2
    BNE NmiDliOff1  ; #V2
    PLA  ; #V2
    TAX  ; #V2
    JMP NmiQuit  ; #V2

; the end of a DLI handler: its Y, X and A copy on the stack, above our bank
; and A. X and Y are the interrupted code's again after these pulls.
DliExit:
    PLA
    TAY
    PLA
    TAX
    PLA
    DEC S_INDLI
    LDA S_DLIPEND
    BNE DliAgain
    LDA S_VBIPEND
    BEQ NmiQuit
    LDA #$00
    STA S_VBIPEND
    TXA                     ; the vertical blank that waited: it keeps X and
    PHA                     ; Y on the stack as well
    TYA
    PHA
    JMP NmiVbiRun
DliAgain:
    DEC S_DLIPEND
    JMP NmiDliRun           ; the one that came in meanwhile, a little late

; The NMI the count names as the vertical blank: confirmed by MSTAT, or
; after all a DLI (then X is put back first, as the DLI path needs it).
NmiVbiCheck:
    TXA
    PHA
    LDX #VBI_SPIN
NmiVbiWait:
    BIT MSTAT
    BMI NmiVbi              ; in vertical blank: confirmed
    DEX
    BNE NmiVbiWait
    LDX S_NMIVBI            ; mid-screen after all: a DLI, and the next NMI
    DEX                     ; is the vertical blank
    STX S_NMICOUNT
    PLA
    TAX
    JMP NmiDli
NmiVbi:
    TYA
    PHA                     ; the stack: A, bank, X, Y
    LDA P6E_N               ; (the status bar's DLI as last frame's set saw #V2
    STA P6E_A               ; it: none if the game's handler didn't run) #V2
    LDA #$00
    STA S_NMICOUNT
    STA P6E_N  ; #V2
    JSR TsFirst             ; (the title's or story's: the first DLI's entry)
    INC S_FRAMES
    LDA S_INVBI
    BNE NmiDone
    LDA S_INDLI
    BEQ NmiVbiRun
    INC S_VBIPEND
    JMP NmiDone
NmiVbiRun:
    INC S_INVBI
    JSR Apply               ; a list chosen too late last frame
    LDA G_L0AF6             ; (the game waiting for its flip: $0AF6 negative)
    STA S_VWAIT
    JSR Inputs
    JSR TiaSoundF           ; last frame's POKEY writes, played on the TIA
    LDA G_L0F0C             ; (the colour scheme on screen, before the game's  #V2
    STA HOLD_SCH            ; vertical blank can change it)  #V2
    LDA S_NMIEN
    AND #$40
    BEQ NmiOwnFrame         ; vertical-blank interrupts off
    LDA #>NmiVbiDone        ; the game's handler picks its list (SetDlist)
    PHA
    LDA #<NmiVbiDone
    PHA
    PHP
    PHA                     ; the A, X, Y the OS would have pushed
    PHA
    PHA
    JMP (S_VVBLKI)
NmiOwnFrame:
    JSR Frame
NmiVbiDone:
    LDA HOLD_N              ; (a list held: the game waits on, its vertical  #V2
    BEQ NmiVbiDone0         ; blank releases it again next frame)  #V2
    LDA #$FF  ; #V2
    STA G_L0AF6  ; #V2
NmiVbiDone0:  ; #V2
    LDA S_PEND              ; the game's handler ended its flip's wait ($0AF6)
    BEQ NmiVbiDone1         ; but chose the new list past MARIA's vertical
    BIT S_VWAIT             ; blank, so it shows a frame late: the game waits
    BPL NmiVbiDone1         ; that frame too (else it draws into the buffer
    LDA #$FF                ; still on screen; FINDINGS "Step 1: a flip shown
    STA G_L0AF6             ; a frame late")
NmiVbiDone1:
    LDA #$00
    STA S_INVBI
NmiDone:
    PLA
    TAY
    PLA
    TAX
    JMP NmiQuit

; before the game installs its own handler: the part of the OS's vertical
; blank that matters here (copy the display shadows), then its exit
VbiDefault:
    LDA S_SDMCTL
    STA S_DMACTL
    LDA S_SDLST
    STA S_DLIST
    LDA S_SDLST+1
    STA S_DLIST+1
    JSR Frame
    PLA
    TAY
    PLA
    TAX
    PLA
Irq:
    RTI
; before the game installs its own: a DLI handler that does nothing, and
; leaves the way the game's does (A, X, Y pushed, out through DliExit)
DliDefault:
    PHA
    TXA
    PHA
    TYA
    PHA
    JMP DliExit

; ------------------------------------------------------- once per frame
; XEGS console keys from the 7800 switches (active low), by retail
; convention: START (restart) from RESET, SELECT (the game's pause) from
; PAUSE, OPTION (title or scene 6) from SELECT. And the quick-stick latch: the
; latest push of stick 1, handed over by ReadStick when the game next looks.
; Runs in the NMI, so no shared scratch (S_TMP is the loaders' counter).
Inputs:
    LDA SWCHA               ; RIOT, read once a frame in vertical blank (it is
    STA S_RSWCHA            ; not safe while MARIA halts the 6502); ReadStick
    LDA SWCHB               ; uses these
    STA S_RSWCHB
    AND #$08                ; PAUSE -> SELECT
    LSR A
    LSR A
    ORA #$08
    STA S_CONSOL
    LDA S_RSWCHB
    AND #$02                ; SELECT -> OPTION
    ASL A
    ORA S_CONSOL
    STA S_CONSOL
    LDA S_RSWCHB
    AND #$01                ; RESET -> START
    ORA S_CONSOL
    STA S_CONSOL
    LDA S_RSWCHA
    LSR A
    LSR A
    LSR A
    LSR A                   ; stick 1, in the XEGS PORTA bit order
    CMP #$0F
    BEQ InputsDone
    STA S_LATCH
InputsDone:
    RTS

; the game's $0F93 (STA DLISTH / RTS): note it, pick the MARIA list now,
; as ANTIC would have taken the new list at the next frame
SetDlist:
    STA S_DLIST+1
    PHA
    TXA
    PHA
    TYA
    PHA
    JSR Frame
    PLA
    TAY
    PLA
    TAX
    PLA
    RTS

; Frame: choose the list for the next frame from the game's DLIST (building
; it when it changed), then Apply it: at once while MARIA is in vertical
; blank, since MARIA reads DPPH/DPPL only at the start of a frame; past it
; (from the main program mid-frame, or the game's vertical blank running
; late), at the next vertical blank. (Applying only
; in MARIA's own vertical blank showed every new frame one frame late, with
; the game already drawing into it: flicker; FINDINGS "Flicker".) Never
; re-entered.
Frame:
    LDA HOLD_N              ; (a list held: the picture on screen keeps its  #V2
    BEQ Frame0              ; colour scheme, for the top's colours and the  #V2
    LDA G_L0F0C             ; game's DLIs; the held list's, as the game's  #V2
    STA HOLD_NEW            ; vertical blank set it, for when it is shown)  #V2
    LDA HOLD_SCH  ; #V2
    STA G_L0F0C  ; #V2
Frame0:  ; #V2
    JSR TopColoursF         ; (the top's sky and pieces' palette)
    JSR FtColours           ; (V2: the fighters' belts and trims) #V2
    LDA S_BUSY
    BEQ FrameCheck
    RTS
; the game's vertical blank asks for its list every frame, and a new picture
; comes only every 13-17 frames: the same list with the same DMA state is
; already chosen (the game never writes into the buffer on screen), so
; there is nothing to do. This was about 1,100 cycles a frame, most of it
; the mode-8 rows' widening, since gone (FINDINGS "The NMI's cost").
FrameCheck:
    LDA S_DLIST
    CMP S_CHOSEN
    BNE FrameGo
    LDA S_DLIST+1
    CMP S_CHOSEN+1
    BNE FrameGo
    LDA S_DMACTL  ; #V1
    AND #$20  ; #V1
    JSR FrameKey            ; #V2
    CMP S_CHOSEN+2
    BNE FrameGo
    RTS
FrameGo:
    LDA S_DLIST
    STA S_CHOSEN
    LDA S_DLIST+1
    STA S_CHOSEN+1
    LDA S_DMACTL  ; #V1
    AND #$20  ; #V1
    JSR FrameKey            ; #V2
    STA S_CHOSEN+2
    INC S_BUSY
    LDA #$00
    STA S_PBLANK
    LDA ZP_P1               ; keep the game's $00-$03
    PHA
    LDA ZP_P1+1
    PHA
    LDA ZP_P2
    PHA
    LDA ZP_P2+1
    PHA
    LDA S_BANK              ; the scene page in for its tables (the NMI may
    PHA                     ; have come in the top bank's code: FINDINGS "RAM
    LDA S_SCENEBANK         ; and fixed ROM: step 3")
    STA S_BANK
    STA BANKSEL
    LDA S_DMACTL  ; #V1
    AND #$20  ; #V1
    JSR FrameKey            ; #V2
    BEQ FrameBlankJ
    LDX #$00
FrameFind:
    CPX SP_NDL
    BCC FrameFind1
FrameBlankJ:
    JMP FrameBlank          ; a list this scene does not have: blank
FrameFind1:
    LDA DLT_LO,X
    CMP S_DLIST
    BNE FrameNext
    LDA DLT_HI,X
    CMP S_DLIST+1
    BEQ FrameFound
FrameNext:
    INX
    BNE FrameFind
FrameFound:
    STX S_DLIDX
    LDA DLT_CTRL,X
    LDY S_L1                ; (two-byte characters: a tiles set's, with its set
    BEQ FrameFound0         ; on; not the ending's text in scene 4's lists,
    LDY S_STORY             ; nor the title's and story's over scene 0's)
    BNE FrameFound0
    LDY S_TITLEA
    BNE FrameFound0
    LDY S_TITLEB
    BEQ FrameFound1
FrameFound0:
    AND #$EF
FrameFound1:
    STA S_PCTRL
    LDA DLT_BUF,X
    JSR FrameUnseen         ; (C set: its buffer has no picture yet)  #V2
    BCS FrameBlankJ  ; #V2
    BNE FrameB
    LDA S_DLIST_A
    CMP S_DLIST
    BNE FrameBuildA
    LDA S_DLIST_A+1
    CMP S_DLIST+1
    BEQ FrameShowA
FrameBuildA:
    JSR FrameDefer  ; #V2
    BCC FrameBuildA1  ; #V2
    JMP FrameDone  ; #V2
FrameBuildA1:  ; #V2
    JSR BuildDllF
FrameShowA:
    LDA S_CHONA             ; (the title's or story's: its CHBASE table;
    JSR FrameChT            ; level 1's: none, its tiles' CHBASE stays)
    STA S_PCHT
    LDA #$00                ; (its top's pieces, if changed)
    JSR TopRefreshF
    LDA #<DLL_A
    STA S_PDPPL
    LDA #>DLL_A
    STA S_PDPPH
    LDA S_PDA1
    STA S_PPD1
    LDA S_PDA2
    STA S_PPD2
    LDA S_VBI_A
    JMP FramePend
FrameB:
    LDA S_DLIST_B
    CMP S_DLIST
    BNE FrameBuildB
    LDA S_DLIST_B+1
    CMP S_DLIST+1
    BEQ FrameShowB
FrameBuildB:
    JSR FrameDefer  ; #V2
    BCC FrameBuildB1  ; #V2
    JMP FrameDone  ; #V2
FrameBuildB1:  ; #V2
    JSR BuildDllF
FrameShowB:
    LDA S_CHONB
    JSR FrameChT
    STA S_PCHT
    LDA #$03
    JSR TopRefreshF
    LDA #<DLL_B
    STA S_PDPPL
    LDA #>DLL_B
    STA S_PDPPH
    LDA S_PDB1
    STA S_PPD1
    LDA S_PDB2
    STA S_PPD2
    LDA S_VBI_B
    JMP FramePend
; (level 1: no list's CHBASE table: the NMI's stub would set CHBASE at its
; DLIs, and level 1's tiles read theirs, L1_CHB, set at each flip)
FrameChT:
    LDX S_L1
    BEQ FrameChT1
    LDX S_STORY             ; (but the title's and story's text: theirs, with
    BNE FrameChT1           ; scene 0's set on)
    LDX S_TITLEA
    BNE FrameChT1
    LDX S_TITLEB
    BNE FrameChT1
    LDA #$00
FrameChT1:
    RTS
FrameBlank:
    LDA #$00                ; (no port DLIs)
    STA S_PCHT
    STA S_PPD1
    STA S_PPD2
    LDA #<BLANK_DLL         ; the blank list, in ROM
    STA S_PDPPL
    LDA #>BLANK_DLL
    STA S_PDPPH
    LDA #$40
    STA S_PCTRL
    LDA #$01
    STA S_PBLANK
    LDA #VBI_NMI
FramePend:
    STA S_PVBI
    LDA #$01
    STA S_PEND
    LDA HOLD_N              ; (a held list the main program built: shown at  #V2
    BEQ FramePend1          ; the next vertical blank's start, before the  #V2
    LDA S_INVBI             ; game's handler sets its colours from the  #V2
    BEQ FrameDone           ; scheme)  #V2
FramePend1:  ; #V2
    BIT MSTAT               ; past MARIA's vertical blank (mid-frame from the
    BPL FrameDone           ; main program, or the game's vertical blank ran  #V1
    BPL FrameLate           ; (V2) #V2
FrameNow:                   ; late: NmiVbiDone): at the next one
    JSR Apply
FrameDone:
    PLA
    STA S_BANK
    STA BANKSEL
    PLA
    STA ZP_P2+1
    PLA
    STA ZP_P2
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    DEC S_BUSY
    RTS
; A a list's buffer (0 A, else B): C set if in play its view is unknown  #V2
; ($FF: L1Init at the load; the game's first picture there not done), and  #V2
; the list chosen again next frame; A and Z as they came. Scene 3's  #V2
; hand-over to scene 4 keeps the room on the XEGS's screen while scene 4 is  #V2
; drawn, and the game's first picture goes into buffer B over it: here the  #V2
; load cleared B, so B was the fighters on black (FINDINGS "Run 10")  #V2
FrameUnseen:  ; #V2
    PHA  ; #V2
    LDA S_L1  ; #V2
    BEQ FrameUnseenN  ; #V2
    LDA S_STORY  ; #V2
    ORA S_TITLEA  ; #V2
    ORA S_TITLEB  ; #V2
    BNE FrameUnseenN  ; #V2
    PLA  ; #V2
    PHA  ; #V2
    BEQ FrameUnseenA  ; #V2
    LDA L1_V+3  ; #V2
    CMP #$FF  ; #V2
    BCS FrameUnseenY  ; #V2
    BCC FrameUnseenN  ; #V2
FrameUnseenA:  ; #V2
    LDA L1_V+1  ; #V2
    CMP #$FF  ; #V2
    BCC FrameUnseenN  ; #V2
FrameUnseenY:  ; #V2
    LDA #$FF  ; #V2
    STA S_CHOSEN+1          ; (chosen again)  #V2
    PLA  ; #V2
    SEC  ; #V2
    RTS  ; #V2
FrameUnseenN:  ; #V2
    PLA  ; #V2
    CLC  ; #V2
    RTS  ; #V2
; a list the NMI chose past MARIA's vertical blank: shown at the next one.  #V2
; If the game's vertical blank changed the scheme meanwhile, the picture on  #V2
; screen keeps its own for that frame (as a held list's; Apply puts the new  #V2
; one back): the old picture in the new colours was a frame's ghost  #V2
FrameLate:  ; #V2
    LDA S_INVBI  ; #V2
    BEQ FrameLateX  ; #V2
    LDA G_L0F0C  ; #V2
    CMP HOLD_SCH  ; #V2
    BEQ FrameLateX  ; #V2
    STA HOLD_NEW  ; #V2
    LDA HOLD_SCH  ; #V2
    STA G_L0F0C  ; #V2
    LDA #$01  ; #V2
    STA HOLD_N  ; #V2
    JSR TopColoursF  ; #V2
FrameLateX:  ; #V2
    JMP FrameDone  ; #V2

; show the chosen list (in vertical blank only)
Apply:
    LDA S_PEND
    BEQ ApplyDone
    LDA #$00
    STA S_PEND
    LDA HOLD_N              ; (a held list shown now: its colour scheme, and  #V2
    BEQ ApplyH              ; the top's colours from it)  #V2
    LDA HOLD_NEW  ; #V2
    STA G_L0F0C  ; #V2
    LDA #$00  ; #V2
    STA HOLD_N  ; #V2
    STA P3E_N               ; (the band's grey latched from the old scheme: none)  #V2
    JSR TopColoursF  ; #V2
ApplyH:  ; #V2
    LDA S_PDPPH
    STA DPPH
    LDA S_PDPPL
    STA DPPL
    LDA S_PCTRL
    STA CTRL
    LDA S_PVBI
    STA S_NMIVBI
    LDA S_PPD1
    STA S_NMIPD1
    LDA S_PPD2
    STA S_NMIPD2
    LDA S_PBLANK
    STA S_SHOWBLANK
    LDA S_PCHT
    STA S_NMICHT
    JSR TsFirst
ApplyDone:
    RTS
; the NMI's stub for the shown list (in the vertical blank: no DLI then):
; the title's or story's, its tables' entries for its first DLI (S_NMICHT:
; A's or B's), else straight to NmiGo
TsFirst:
    LDA S_NMICHT
    BEQ TsFirstOff
    CLC
    ADC #<TS_CHTV
    STA NMI_STUB+2
    LDA #>TS_CHTV
    STA NMI_STUB+3
    LDA S_NMICHT
    CLC
    ADC #<TS_CHTP
    STA NMI_STUB+13
    LDA #$AD                ; (LDA abs: last, its operand set)
    STA NMI_STUB+1
    RTS
TsFirstOff:
    LDA #<NmiGo
    STA NMI_STUB+2
    LDA #>NmiGo
    STA NMI_STUB+3
    LDA #$4C                ; (JMP)
    STA NMI_STUB+1
    RTS

; ------------------------------------------------------ list building
; The builder (BuildDll and its zones) is in the top bank (FINDINGS "RAM and
; fixed ROM: step 3"). BuildDllF copies the list's description and table
; entries from the scene page, then runs it there; it runs in the NMI or
; the main program, never both (S_BUSY), and its calls into the story's and
; title's scene-page code go through the wrappers below.
BuildDllF:
    LDX S_DLIDX
    LDA DLT_BUF,X
    STA S_DLBUF
    LDA DLT_LO,X
    STA S_DLLO
    LDA DLT_HI,X
    STA S_DLHI
    LDA DLT_DLO,X
    STA ZP_P1
    LDA DLT_DHI,X
    STA ZP_P1+1
    LDY #$00
BuildDllCopy:               ; its runs (3 bytes each) to the $FF
    LDA (ZP_P1),Y
    STA DESCBUF,Y
    CMP #$FF
    BEQ BuildDllGo
    INY
    LDA (ZP_P1),Y
    STA DESCBUF,Y
    INY
    LDA (ZP_P1),Y
    STA DESCBUF,Y
    INY
    BNE BuildDllCopy
BuildDllGo:
    JSR TsWant              ; the title's or the story's: BuildTs, in the
    BEQ BuildDllNorm        ; scene page (bank 0: FINDINGS "The title and the
    LDA S_BANK              ; opening scroll in bank 0's MARIA copy")
    PHA
    LDA S_SCENEBANK
    STA S_BANK
    STA BANKSEL
    JSR BuildTs
    JMP BuildDllBack
BuildDllNorm:
    LDA #$00                ; (the buffer's list: not characters)
    LDX S_DLBUF
    BNE BuildDllNB
    STA S_CHONA
    BEQ BuildDllN1
BuildDllNB:
    STA S_CHONB
BuildDllN1:
    LDA S_BANK
    PHA
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    JSR BuildDll  ; #V1
    JSR PgBuildDll          ; (V2: the scene page's copy) #V2
BuildDllBack:
    PLA
    STA S_BANK
    STA BANKSEL
    RTS
; Z clear: the list being built is the title's (its buffer's marks) or the
; story's (S_STORY 2: the ending's is 1, BuildDll's letters)
TsWant:
    LDA S_STORY
    CMP #$02
    BEQ TsWantY
    LDA S_DLBUF
    BNE TsWantB
    LDA S_TITLEA
    RTS
TsWantB:
    LDA S_TITLEB
    RTS
TsWantY:
    LDA #$01
    RTS

; the story's and title's code is in the top bank (FINDINGS "The title and
; story code in bank 5"): its ways in from the scene pages' code and the
; loader, and its reads of the scene page
StoryStepF:                 ; (the story loop: SysStoryStep; from the scene
    JMP StoryTs             ; page, which is in)
; the title (SysTitleLogo, SysTitleCopy): the buffer $07 names now holds
; the logo (1) or the copyright (2): its marks, its lists forgotten (built
; again as the title's: BuildTs); no top pieces while it is up
TitleLogoF:
    LDA #$01
    BNE TitleMarkF
TitleCopyF:
    LDA #$02
TitleMarkF:
    PHA
    LDA #$00
    STA S_TN
    LDA G_Z07
    CMP #$20
    BEQ TitleMarkFB
    PLA
    ORA S_TITLEA
    STA S_TITLEA
    LDA #$00
    STA S_DLIST_A
    STA S_DLIST_A+1
    RTS
TitleMarkFB:
    PLA
    ORA S_TITLEB
    STA S_TITLEB
    LDA #$00
    STA S_DLIST_B
    STA S_DLIST_B+1
    RTS
ObjEndF:                    ; (LoadScene; C out kept)
    LDA #<ObjEnd
    LDX #>ObjEnd
    JMP TopArtCall

; ------------------------------------------------ the framebuffers' rows  #V1
; Both framebuffers are laid out for MARIA's multi-line zones: a row is 40  #V1
; bytes in one page, the row below it one page lower. Pages FB_PBOT-FB_PTOP  #V1
; each hold six rows side by side at bytes 16-255 (FbSlotLo; bytes 0-15 are  #V1
; left, and $4000-$400F is the cartridge's POKEY). Buffer A is columns 0-2,  #V1
; B columns 3-5, each column FB_BAND rows from the top page down. So the  #V1
; game's "40 bytes on" is "one page down, or the next column's top".  #V1
; RowAddr: A = row (FB_TOP to FB_ROWS-1) of the buffer $07 names ($20 B,  #V1
; else A): its first byte into $14/$15. Uses A only (the game's row address  #V1
; kept X and Y).  #V1
RowAddr:  ; #V1
    SEC  ; #V1
    SBC #FB_TOP             ; the buffers begin at row FB_TOP  #V1
    STA S_RROW  ; #V1
    LDA G_Z07  ; #V1
    CMP #$20  ; #V1
    BEQ RowAddrB  ; #V1
    LDA #16  ; #V1
    BNE RowAddrCol  ; #V1
RowAddrB:  ; #V1
    LDA #136  ; #V1
RowAddrCol:  ; #V1
    STA G_Z14               ; column 0's first byte  #V1
    LDA S_RROW  ; #V1
    CMP #FB_BAND  ; #V1
    BCC RowAddrIn  ; #V1
    SBC #FB_BAND  ; #V1
    PHA  ; #V1
    LDA G_Z14  ; #V1
    ADC #39                 ; (carry set) the next column  #V1
    STA G_Z14  ; #V1
    PLA  ; #V1
    CMP #FB_BAND  ; #V1
    BCC RowAddrIn  ; #V1
    SBC #FB_BAND  ; #V1
    PHA  ; #V1
    LDA G_Z14  ; #V1
    ADC #39  ; #V1
    STA G_Z14  ; #V1
    PLA  ; #V1
RowAddrIn:  ; #V1
    EOR #$FF                ; the page: FB_PTOP - place  #V1
    SEC  ; #V1
    ADC #FB_PTOP  ; #V1
    STA G_Z15  ; #V1
    RTS  ; #V1
; RowNext: $14/$15 to the same byte of the next row down (the game's  #V1
; ADC #$28). A pointer that isn't in a buffer (the clip row) only moves on a  #V1
; page. Uses A only.  #V1
RowNext:  ; #V1
    DEC G_Z15  ; #V1
    LDA G_Z15  ; #V1
    CMP #FB_PBOT-1  ; #V1
    BNE RowNextDone  ; #V1
    LDA #FB_PTOP            ; below the column's foot: the next column's top  #V1
    STA G_Z15  ; #V1
    LDA G_Z14  ; #V1
    CLC  ; #V1
    ADC #40  ; #V1
    STA G_Z14  ; #V1
RowNextDone:  ; #V1
    RTS  ; #V1
; RowNextC: RowNext, and the carry added to the byte (the mirrored blitter  #V1
; moves 40 bytes plus its shift's odd bit, and a byte back at the loop's top)  #V1
RowNextC:  ; #V1
    BCC RowNext             ; (even: the plain step)  #V1
    JSR RowNext  ; #V1
    INC G_Z14  ; #V1
    BNE RowNextCDone  ; #V1
    INC G_Z15  ; #V1
RowNextCDone:  ; #V1
    RTS  ; #V1
; the step's rare half, for the steps written inline in the game's code  #V1
; (DEC high / LDA high / CMP #FB_PBOT-1 / BNE / JSR here): a column's foot  #V1
; left, the next column's top  #V1
RowWrap:  ; #V1
    LDA #FB_PTOP  ; #V1
    STA G_Z15  ; #V1
    LDA G_Z14  ; #V1
    CLC  ; #V1
    ADC #40  ; #V1
    STA G_Z14  ; #V1
    RTS  ; #V1
; the sound's frame-wait counters ($24A4 STA $0AFC, $24AA STA $0AFD; the vs
; fight's $0AF9, $0AFA), A and the flags kept: engine part 2's sound module
; is in ROM, so the vs fight's two operands can't be patched (FINDINGS "RAM
; and fixed ROM: step 4")
FwLo:
    PHP
    BIT S_VS
    BMI FwLoVs
    PLP
    STA G_L0AFC
    RTS
FwLoVs:
    PLP
    STA G_L0AF9
    RTS
FwHi:
    PHP
    BIT S_VS
    BMI FwHiVs
    PLP
    STA G_L0AFD
    RTS
FwHiVs:
    PLP
    STA G_L0AFA
    RTS
; the game's full clear and buffer copy, and the TIA sound, are in the top
; bank (FINDINGS "RAM and fixed ROM: step 3"): these select it, and give the
; caller its bank back with A and the flags as the routine left them (the
; caller's bank kept in S_STUBBK: the main program's only; the NMI's sound
; keeps its own on the stack)
ClearBufF:
    JSR StubIn
    JSR ClearBuf
    JMP StubOut
CopyBufF:
    JSR StubIn
    JSR CopyBuf
    JMP StubOut
StubIn:
    PHA
    LDA S_BANK
    STA S_STUBBK
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    PLA
    RTS
StubOut:
    PHP
    PHA
    LDA S_STUBBK
    STA S_BANK
    STA BANKSEL
    PLA
    PLP
    RTS
TiaSoundF:                  ; (the NMI)
    LDA S_BANK
    PHA
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    JSR TiaSound
    PLA
    STA S_BANK
    STA BANKSEL
    RTS
FbSlotLo:                   ; each column's first byte in its pages
    .byte 16,56,96,136,176,216

; ------------------------------------------------------------- loading
; the XEGS loader's two entries: $2F5A (common, then the scene) and $2F66
; (the scene's code and data banks)
LoadCommon:                 ; (the small-sprite block is not copied in: the
    LDA S_SCENEBANK         ; game's text routine has it brought in, TextInF)
    STA S_BANK
    STA BANKSEL
    LDX #$00
LoadCommonCarve:
    CPX #N_CCARVE*5
    BCS LoadCommonDone
    JSR CopyEntryC
    JMP LoadCommonCarve
LoadCommonDone:
    RTS

LoadScene:
    JSR ObjEndF
    JSR PageBlank           ; (V2: the blank list on screen first) #V2
    LDX G_ZD0
    LDA SCENEBANK_TAB,X
    STA S_SCENEBANK
    STA S_BANK              ; (the fast fill's code no longer copied in: every
    STA BANKSEL             ; scene that plays has a set, which captures its fills)
    LDX #CARVE_E2_N-1       ; engine part 2's variables (carved: their modules
    LDA #$00                ; are in ROM), zero as its image had them
LoadSceneEngine:
    STA CARVE_E2_AT,X
    DEX
    BPL LoadSceneEngine
    LDX #$00
LoadSceneCarve:
    TXA
    CMP SP_NCARVE
    BCS LoadSceneDone
    JSR CopyEntryS
    JMP LoadSceneCarve
LoadSceneDone:
    LDA #<LoadInit          ; its RAM's state (in the top bank)
    LDX #>LoadInit
    JSR TopArtCall          ; #V1
    JSR LoaderCall          ; (V2: the loader bank's) #V2
    LDA SCID_PAGE           ; the scene's identity byte ($7FE7: S_SCID)
    STA S_SCID
    JSR J_VSSETUP           ; level 1's page: the vs fight's mode (ScVsSetup)
    LDA #<L1Load            ; level 1's windows (FINDINGS "Level 1 without the
    LDX #>L1Load
    LDY #TOP_BANK           ; #V1
    LDY #LOADER_BANK        ; (V2: the loader bank's) #V2
    JSR L1Call
    JMP TopLoadF            ; blitter"); the top rows' pieces #V1
    JSR TopLoadF            ; (the top rows' pieces) #V2
    JMP PageShow            ; (V2: the new scene's lists from now) #V2


; level 1's generator (L1Gen, bank L1_HOME) reads its tables and the scene
; page's and the art bank's images through here: X bytes from ZP_P1 in bank
; A to L1G_BUF; back to the caller's bank
L1Fetch:
    TAY                     ; (the source's bank; the caller's back after)
    LDA S_BANK
    PHA
    STY S_BANK
    STY BANKSEL
    TXA
    TAY
L1Fetch1:
    DEY
    BMI L1Fetch2
    LDA (ZP_P1),Y
    STA L1G_BUF,Y
    JMP L1Fetch1
L1Fetch2:
    PLA
    STA S_BANK
    STA BANKSEL
    RTS

; level 1's code in its banks (FARL1: L1_HOME, the shapes' records and the
; lists' objects; FARL2: L1_CAP, the draws' capture) from anywhere: A/X its
; address, Y its bank, in meanwhile, the caller's after; Y as the routine
; leaves it. The NMI's list building (Frame) keeps out meanwhile (S_BUSY):
; it can call here too
L1Call:
L1CallU:                    ; (L1Load's: the set's load, whatever shows)
    INC S_BUSY
    STA L1_JV
    STX L1_JV+1
    LDA S_BANK
    PHA
    CPY #V2_LO_BANK         ; (V2: bank 6 is fixed at $4000: no switch) #V2
    BEQ L1CallNS            ; #V2
    CPY S_SCENEBANK         ; (nor for the scene page: in, in play) #V2
    BEQ L1CallNS            ; #V2
    STY S_BANK
    STY BANKSEL
L1CallNS:                   ; #V2
    JSR L1CallJ
    PLA
    STA S_BANK
    STA BANKSEL
    DEC S_BUSY
    RTS
L1CallJ:
    JMP (L1_JV)
; the game's $02/$03 kept around it (ZP_P2: the records' pointer)
L1CallK:
    PHA
    LDA ZP_P2
    STA L1_SV
    LDA ZP_P2+1
    STA L1_SV+1
    PLA
    JSR L1Call
    LDA L1_SV
    STA ZP_P2
    LDA L1_SV+1
    STA ZP_P2+1
    RTS
; the level-1 column routine's column (ColA, Col68 in level 1's page:
; SysL1Col; L1C_MIR set)
L1ColF:
    LDA #<L1Col
    LDX #>L1Col
    LDY #L1_CAP
    JMP L1CallK
; the fills' clip ($2CCD's and $2D03's JSR $2DA4: SysL1Fill, SysL1Pat): in
; level 1 the fill is clipped (the game's clip: $06 at least $23, the
; columns cut, $0D its rows), its part above FB_TOP told to the top's pieces
; as RowBase would (TopEraseF), then it is an instance's eraser (L1Fill);
; nothing drawn: back to the fill's caller, X, Y and $06 as they came (a
; fighter-box erase, S_NOFILL, is passed over); else the clip, as before
L1FillF:
    LDA S_L1
    BNE L1FillF1
    JMP G_L2DA4
L1FillF1:
    LDA #$00
    BIT L1_SF
    BPL L1FillGo
L1FillCvJ:
    JMP L1FillCv  ; #V1
L1FillGo:
    STA L1F_PAT
    STX L1_FX
    STY L1_FY
    LDA G_Z06
    STA L1_F06
    LDA S_NOFILL
    BEQ L1FillG
    JSR FgRecF              ; (a fighter-box erase: its box all the same, as
    JMP L1FillOut           ; RowBase takes it: FgRecFB)  #V1
    JMP L1FillC             ; RowBase takes it: FgRecFB; V2: and the rooms' #V2
                            ; figures under it, L1Fill) #V2
L1FillG:
    JSR G_L2DA4
    BMI L1FillOut           ; (nothing on screen)
    JSR FgRecF              ; (its box: FgRecFB)
    LDA L1F_PAT             ; (C set: the rectangle)
    EOR #$01
    LSR A
    LDA G_Z06
    SEC
    SBC #$23
    CMP #FB_TOP
    BCS L1FillC
    PHA
    LDA L1F_PAT
    EOR #$01
    LSR A
    PLA
    JSR TopEraseF
L1FillC:
    LDA #<L1Fill
    LDX #>L1Fill
    LDY #L1_CAP
    JSR L1CallK
L1FillOut:
    LDX L1_FX
    LDY L1_FY
    LDA L1_F06
    STA G_Z06
    PLA
    PLA
    RTS
L1PatF:
    LDA S_L1
    BNE L1PatF1
    JMP G_L2DA4
L1PatF1:
    LDA #$01
    BIT L1_SF
    BMI L1FillCvJ
    JMP L1FillGo
; the picture done (TopFlip): level 1's instances' end of picture (L1Flip)
L1FlipF:
    LDA S_STORY             ; (none while the title's or story's text shows:
    ORA S_TITLEA            ; its characters are bank 0's MARIA copy's, so the
    ORA S_TITLEB            ; window keeps bank 0; scene 0's set waits)
    BNE L1FlipF1
    LDA S_L1
    BEQ L1FlipF1
    LDA #<L1Flip
    LDX #>L1Flip
    LDY #L1_CAP
    JMP L1CallK
L1FlipF1:
    RTS
; and after its lists are written (FtEmit): nothing changed since
L1DoneF:
    LDA S_L1
    BEQ L1DoneF1
    LDX #$00
    LDA G_Z07
    CMP #$20
    BNE L1DoneF2
    INX
L1DoneF2:
    LDA #$00
    STA L1_DIRTY,X
L1DoneF1:
    RTS

; level 1 without the blitter, its instances (FINDINGS "Level 1 without the
; blitter"): run through L1Call (bank L1_HOME in, where the shapes' records
; are: L1Find, L1Zone). Each buffer's instances (L1_SHA/L1_XA, B's from 2 x L1_NMAX on: the
;;; shape, bit 7 drawn in this picture; its place, an object's horizontal
; position) in the order drawn; its view (L1_V), its world (L1_WLD: its
; tiles); L1_DIRTY when its lists want writing again
; copy entries: source, destination (both little-endian), length (1 byte)
CopyEntryC:
    LDA CCARVE,X
    STA ZP_P1
    LDA CCARVE+1,X
    STA ZP_P1+1
    LDA CCARVE+2,X
    STA ZP_P2
    LDA CCARVE+3,X
    STA ZP_P2+1
    LDA CCARVE+4,X
    JMP CopyEntryGo
CopyEntryS:
    LDA SP_CARVE,X
    STA ZP_P1
    LDA SP_CARVE+1,X
    STA ZP_P1+1
    LDA SP_CARVE+2,X
    STA ZP_P2
    LDA SP_CARVE+3,X
    STA ZP_P2+1
    LDA SP_CARVE+4,X
CopyEntryGo:
    STX S_TMP+3
    LDX #$00
    JSR Copy
    LDA S_TMP+3
    CLC
    ADC #$05
    TAX
    RTS

; Copy A (low) + X (high) bytes from (ZP_P1) to (ZP_P2)
Copy:
    STA S_TMP
    STX S_TMP+1
    LDY #$00
CopyLoop:
    LDA S_TMP
    ORA S_TMP+1
    BEQ CopyDone
    LDA (ZP_P1),Y
    STA (ZP_P2),Y
    INY
    BNE CopyCount
    INC ZP_P1+1
    INC ZP_P2+1
CopyCount:
    LDA S_TMP
    BNE CopyDec
    DEC S_TMP+1
CopyDec:
    DEC S_TMP
    JMP CopyLoop
CopyDone:
    RTS

; ----------------------------------------- the zero-page swap and clear
; The XEGS swaps $00-$7F with $0880-$08FF, and clears $01-$7F, byte by byte
; through $00,X; here each XEGS byte is wherever the layout put it. Table A
; lists those now in zero page (7800 address, XEGS index), table B those in
; the $18xx page (offset, XEGS index).
ZpSwap:
    LDX #N_ZA-1
ZpSwapA:
    LDY ZPT_A,X
    LDA.w $0000,Y
    PHA
    LDY ZPT_AX,X
    LDA SWAPBUF,Y
    LDY ZPT_A,X
    STA.w $0000,Y
    LDY ZPT_AX,X
    PLA
    STA SWAPBUF,Y
    DEX
    BPL ZpSwapA
    LDX #N_ZB-1
ZpSwapB:
    LDY ZPT_B,X
    LDA $1800,Y
    PHA
    LDY ZPT_BX,X
    LDA SWAPBUF,Y
    LDY ZPT_B,X
    STA $1800,Y
    LDY ZPT_BX,X
    PLA
    STA SWAPBUF,Y
    DEX
    BPL ZpSwapB
    LDX #$FF                ; as the XEGS loop leaves it
    RTS

ZpClear:
    LDX #N_ZA-1
ZpClearA:
    LDY ZPT_AX,X
    BEQ ZpClearA1           ; the XEGS loop stops before $00
    LDY ZPT_A,X
    LDA #$00
    STA.w $0000,Y
ZpClearA1:
    DEX
    BPL ZpClearA
    LDX #N_ZB-1
ZpClearB:
    LDY ZPT_BX,X
    BEQ ZpClearB1
    LDY ZPT_B,X
    LDA #$00
    STA $1800,Y
ZpClearB1:
    DEX
    BPL ZpClearB
    LDA #$00
    LDX #$00                ; as the XEGS loop leaves them
    RTS

; ------------------------------------------------ the small replacements
; $2F8A waited for scanline 200: wait for the next vertical-blank stand-in
WaitFrame:
    LDA S_FRAMES
WaitFrameLoop:
    CMP S_FRAMES
    BEQ WaitFrameLoop
    RTS

; $29DC: LDA $04 / STA $1C, then the art bank in if the source is art. A
; blit of a recorded fighter (FT_IN 1, from its record to its torso: its
; parts are objects, FINDINGS "The fighters as objects: step 4") is not
; drawn: the return to the header read and the header read's to the blitter
; dropped, the blitter returns to its caller as after a draw ($03, $04 as
; they were)
BlitBank:
    LDA S_GLYIN
    BNE BlitBank0
    LDA FT_IN
    CMP #$01
    BEQ BlitBankX
    CMP #$02
    BEQ BlitBankK
    CMP #$03
    BNE BlitBank0
BlitBankK:
    JSR AkCap               ; (Akuma's, the hawk's: captured, then not drawn)
    BCC BlitBank0
BlitBankX:
    PLA
    PLA
    PLA
    PLA
    RTS
BlitBank0:
    JSR TopCaptureF         ; a top piece (FINDINGS "The top rows as objects")
    LDA S_L1                ; level 1: an instance (L1Blit), not drawn
    BEQ BlitBank0A
    BIT L1_SF               ; (the rooms' canvas: a store drawn into it, no
    BPL BlitBank0L          ; read of it: BlLeftN, BlLnS; an OR or an AND
    LDA G_Z0F               ; blit an instance)
    BMI BlitBank0L
    BNE BlitBank0A
BlitBank0L:
    JMP BlitBankL1
BlitBank0A:
    LDA G_Z04
    STA G_Z1C
    CMP #$80
    BCC BlitBankKeep
    CMP #$A0
    BCC BlitBankArt         ; $80-$9F: the art
    CMP #$C0
    BCS BlitBankKeep
    STX S_BTX               ; $A0-$BF: the scene's data, unless its page map
    SEC                     ; says the page holds art-bank copies of its
    SBC #$A0                ; scene-code sprites (X and Y are the blitter's)
    TAX
    LDA SP_PAGEMAP,X
    LDX S_BTX
    CMP #$00
    BEQ BlitBankKeep
BlitBankArt:
    LDA #ART_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
BlitBankKeep:
    RTS
; (level 1) the kind of blit from its entry's return (module B's: TOP_RETA
; normal, BL_RETAR right-aligned, TOP_RETM mirrored, TOP_RETMR both; the
; first two by their pages, the mirrored ones, on one page, by their low
; bytes), X and Y kept
BlitBankL1:
    TXA
    PHA
    TYA
    PHA
    TSX
    LDA $0106,X
    LDY #$00
    CMP #>TOP_RETA
    BEQ BlitBankL2
    INY
    CMP #>BL_RETAR
    BEQ BlitBankL2
    LDY #$02
    LDA $0105,X
    CMP #<TOP_RETM
    BEQ BlitBankL2
    INY
BlitBankL2:
    STY L1B_KIND
    LDA #<L1Blit
    LDX #>L1Blit
    LDY #L1_CAP
    JSR L1CallK
    PLA
    TAY
    PLA
    TAX
    BCS BlitBankL3          ; (an instance: not drawn)
    BIT L1_SF               ; (the canvas: a blit not in the set's inventory
    BPL BlitBankL3          ; drawn as ever, as Akuma's masks his capture
    JMP BlitBank0A          ; leaves: FINDINGS "Levels 2-4 without the
BlitBankL3:                 ; blitter")
    JMP BlitBankX

; Akuma's drawing (scene 4's $7C50, in place of its JMP $7C56: a JSR here,
; so its return, $7C52's home, gives $7C56's: + 4), then his blits'
; capture ended (FT_IN 0: the draws after him are in front of him, as front
; boxes). X (his pose, bank 15's) kept
AkW:
    PLA
    CLC
    ADC #$04
    STA AK_VEC
    PLA
    ADC #$00
    STA AK_VEC+1
    JSR AkW1
    LDA #$00
    STA FT_IN
    RTS
AkW1:
    JMP (AK_VEC)

; level 3's hawk (its loop's JSR $6980, in its place: FINDINGS "The hawk as
; objects"): drawn with its blits captured as Akuma's (FT_IN 3: AkCap), then
; the capture ended; with no objects (the text up, the glyphs in) drawn as
; before
HawkW:
    JSR StarOff
    BEQ HawkW1
    JMP G3_L6980
HawkW1:
    LDA #$03
    STA FT_IN
    JSR G3_L6980
    LDA #$00
    STA FT_IN
    RTS

; bank 15's fighter-box erase (FINDINGS "The fighter-box fills dropped"):
; its entries ($A78C the player's, $A780 the enemy's) decide for both its
; fills (S_ERS): $C0, nothing painted, when its box holds nothing of the
; bitmap's (FT_DRW, taken here: the player's 1, drawn as objects; the
; enemy's 0 or 1, none or objects), else $80, painted as before (layout7800
; S_ERS). A, X and Y as the game's entries leave them
ErP:
    PHA
    TXA
    PHA
    LDX #$00
    BEQ ErDec
ErE:
    PHA
    TXA
    PHA
    LDX #$01
ErDec:
    LDA G_Z07
    CMP #$20
    BNE ErDec1
    INX
    INX
ErDec1:
    LDA #$80
    PHA
    LDA S_GLYIN
    BNE ErDec2
    TXA
    LSR A
    LDA FT_DRW,X
    BCS ErDecEn
    CMP #$01                ; (the player's: objects?)
    BNE ErDec2
    BEQ ErDecN
ErDecEn:
    CMP #$02                ; (the enemy's: the bitmap?)
    BEQ ErDec2
ErDecN:
    PLA
    LDA #$C0
    PHA
ErDec2:
    LDA #$00
    STA FT_DRW,X
    LDA FR_V,X              ; (its record, an earlier picture's, goes with
    AND #$FE                ; its box: drawn again, it comes back at once;
    CMP FR_V,X              ; not, as the player in the embrace, no ghost.
    BEQ ErDec3              ; The scenes' sets' fills never erase a
    STA FR_V,X              ; fighter's record: FINDINGS "The ghost player
    TXA                     ; in the embrace")
    PHA
    LSR A
    TAX
    LDA #$01                ; (the buffer's objects made again)
    STA FT_DIRTY,X
    PLA
    TAX
ErDec3:
    TYA                     ; (and the other fighter's record in this
    PHA                     ; buffer, an earlier picture's, its box over
    TXA                     ; this one's: the erase wipes it on the
    EOR #$01                ; original. The cutscene's guard waits drawn
    TAY                     ; as the player, then leaves as the enemy:
    LDA FR_V,Y              ; FINDINGS "The cutscene guard's ghost".
    CMP #$01                ; In a fight both are drawn again at once)
    BNE ErDec4
    TXA                     ; (against the erase's own columns, as the
    LSR A                   ; game's fill: the enemy's from $E5 - 6, the
    BCC ErDecP              ; player's from $E3 - 3, 11 bytes, the rows
    LDA G_ZE5               ; 114-153 every fighter's. Not this fighter's
    SEC                     ; record: the first time the guard is drawn as
    SBC #$06                ; the enemy there is none yet, and the standing
    JMP ErDecC              ; guard stayed two pictures: FINDINGS
ErDecP:                     ; "Recording 02")
    LDA G_ZE3
    SEC
    SBC #$03
ErDecC:
    BPL ErDecC1
    LDA #$00
ErDecC1:
    CMP FR_C1,Y             ; (its first before the record's past-last,
    BCS ErDec4              ; and its past-last past the record's first)
    CLC
    ADC #11
    CMP FR_C0,Y
    BEQ ErDec4
    BCC ErDec4
    LDA #$00
    STA FR_V,Y
    TXA
    LSR A
    TAY
    LDA #$01
    STA FT_DIRTY,Y
ErDec4:
    PLA
    TAY
    PLA
    STA S_ERS
    TXA
    AND #$01
    TAX
    PLA
    CPX #$00
    BNE ErDecE
    TAX
    PLA
    JMP G_LA78F
ErDecE:
    TAX
    PLA
    JMP G_LA797
; its rectangle fill ($2CCD) and pattern fill ($2D03): with S_ERS $C0
; (bit 6), run with S_NOFILL set, so RowBase sends them to the scratch row
; after their bookkeeping
NoFill:
    BIT S_ERS
    BVS NoFill1
    JMP G_L2CCD
NoFill1:
    INC S_NOFILL
    JSR G_L2CCD
    DEC S_NOFILL
    RTS
NoPat:
    BIT S_ERS
    BVS NoPat1
    JMP G_L2D03
NoPat1:
    INC S_NOFILL
    JSR G_L2D03
    DEC S_NOFILL
    RTS

; a blit of Akuma's (FT_IN 2: FINDINGS "Akuma as objects") captured for
; the buffer being drawn ($07), C set: its image from the scene's data
; (AK_PG0-AK_PG1), an OR (sprite, $0F 0) or an AND (mask, negative), by the
; normal, right-aligned, mirrored or mirrored right-aligned blitter (its
; JSR $29D8's return: TOP_RETA, BL_RETAR, TOP_RETM, TOP_RETMR), while the
; buffer has room (AK_MAX). Else C clear, and it is drawn. X, Y kept
AkCap:
    TXA
    PHA
    TYA
    PHA
    LDA G_Z04
    CMP AK_PG0
    BCC AkCapN0
    CMP AK_PG1
    BEQ AkCap1
    BCS AkCapN0
AkCap1:
    LDY #$00                ; (the flags: Y)
    LDA G_Z0F
    BEQ AkCap2
    BPL AkCapN0             ; (a store: drawn)
    LDY #$20
AkCap2:
    TSX                     ; the blitter: under our two bytes, the returns
    LDA $0108,X             ; into BlitBank and into $29DC
    CMP #>TOP_RETA
    BNE AkCapK2
    LDA $0107,X
    CMP #<TOP_RETA
    BEQ AkCapK
AkCapK2:
    LDA $0108,X
    CMP #>BL_RETAR
    BNE AkCapK3
    LDA $0107,X
    CMP #<BL_RETAR
    BNE AkCapK3
    TYA
    ORA #$40
    TAY
    BNE AkCapK
AkCapK3:
    LDA $0108,X
    CMP #>TOP_RETM
    BNE AkCapK4
    LDA $0107,X
    CMP #<TOP_RETM
    BNE AkCapK4
    TYA
    ORA #$80
    TAY
    BNE AkCapK
AkCapK4:
    LDA $0108,X
    CMP #>TOP_RETMR
    BNE AkCapN0
    LDA $0107,X
    CMP #<TOP_RETMR
    BNE AkCapN0
    TYA
    ORA #$C0
    TAY
    JMP AkCapK
AkCapN0:
    JMP AkCapNo
AkCapK:
    LDA FT_IN               ; (the hawk's, FT_IN 3: never merged, its grey
    CMP #$03                ; kept: flag bit 4)
    BNE AkCapK0
    TYA
    ORA #$10
    TAY
AkCapK0:
    STY S_BTX               ; (the flags)
    LDX #$00                ; the buffer, its next entry (Y)
    LDA G_Z07
    CMP #$20
    BNE AkCapB
    INX
AkCapB:
    LDA AK_FR,X             ; (the picture's first: the list afresh)
    BEQ AkCapB0
    LDA #$00
    STA AK_N,X
    STA AK_FR,X
AkCapB0:
    LDA #$02
    STA AK_V,X
    LDA #$01
    STA FT_SEEN,X
    LDA AK_N,X
    CMP #AK_MAX
    BCS AkCapNo
    CPX #$00
    BEQ AkCapB1
    CLC
    ADC #AK_MAX
AkCapB1:
    TAY
    INC AK_N,X
    LDA S_BTX
    STA AK_FL,Y
    LDA G_Z03
    STA AK_LO,Y
    LDA G_Z04
    STA AK_HI,Y
    CMP #$A0                ; its bank, as BlitBank's: $80-$9F the art; $A0-$BF
    BCC AkCapArt            ; the scene's, unless its page map says art-bank
    SEC                     ; copies
    SBC #$A0
    TAX
    LDA SP_PAGEMAP,X
    BNE AkCapArt
    LDA S_SCENEBANK
    BNE AkCapBk
AkCapArt:
    LDA #ART_BANK
AkCapBk:
    STA AK_BK,Y
    LDA G_Z05
    STA AK_COL,Y
    LDA G_Z06
    SEC
    SBC #35
    STA AK_ROW,Y
    LDA G_Z10
    STA AK_SH,Y
    PLA
    TAY
    PLA
    TAX
    SEC
    RTS
AkCapNo:
    PLA
    TAY
    PLA
    TAX
    CLC
    RTS

; $29FF: the scene page back, then LDA $1C / STA $04 / RTS  #V1
BlitDone:  ; #V1
    LDA S_SCENEBANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    LDA G_Z1C  ; #V1
    STA G_Z04  ; #V1
    RTS  ; #V1

; the OS's SETVBV: A = 6 immediate (X high, Y low); 7 deferred is unused
SetVBV:
    CMP #$06
    BNE SetVBVDone
    STY S_VVBLKI
    STX S_VVBLKI+1
SetVBVDone:
OsStub:
    RTS

; $0FFB: LDA $0F17 / BNE $101F, falling into $1000
CommonTail:
    LDA G_L0F17
    BNE CommonTail1
    JMP G_L1000
CommonTail1:
    JMP G_L101F

; $2422, the sound-effect starter, with $04 kept (FINDINGS, "The linker")
Sound:
    STA S_TMP
    LDA G_Z04
    STA S_SND04
    LDA S_TMP
    JSR SoundBody
    LDA S_SND04
    STA G_Z04
    RTS
SoundBody:
    PHA                     ; the four bytes the jump replaced
    JSR G_L258D
    JMP G_L2426

; the tables the builder generates follow


; A list to build in the vertical blank (Frame, from the game's handler): a  #V2
; whole list takes the builder about 3 frames (a cutscene's room), and the  #V2
; NMI's DLIs and vertical blanks are lost meanwhile: the old picture with the  #V2
; new scheme's colours, black zones (FINDINGS "Recording 07": the switch  #V2
; frames). In play the list is held instead: Frame chooses it again later  #V2
; (S_CHOSEN+1), the game waits on for its flip ($0AF6), and the picture on  #V2
; screen keeps its colour scheme ($0F0C, HOLD_SCH); the main program builds  #V2
; it in the game's flip wait (FlipWait), the NMI running, and the next  #V2
; vertical blank shows it as the game's handler releases the flip. Held  #V2
; HOLD_MAX frames with no flip wait to build it, the NMI builds it as  #V2
; before. C set: held (FrameDone next).  #V2
HOLD_MAX = 3  ; #V2
FrameDefer:  ; #V2
    LDA S_INVBI  ; #V2
    BEQ FrameDeferN         ; (the main program: build it)  #V2
    LDA S_L1                ; (play only: a tiles set on, not the title's or  #V2
    BEQ FrameDeferN         ; story's text over scene 0's)  #V2
    LDA S_STORY  ; #V2
    ORA S_TITLEA  ; #V2
    ORA S_TITLEB  ; #V2
    BNE FrameDeferN  ; #V2
    LDA HOLD_N  ; #V2
    BNE FrameDefer1  ; #V2
    LDA G_L0F0C             ; (the held list's scheme, as the game set it)  #V2
    STA HOLD_NEW  ; #V2
    LDA HOLD_N  ; #V2
FrameDefer1:  ; #V2
    CMP #HOLD_MAX  ; #V2
    BCS FrameDeferN  ; #V2
    INC HOLD_N  ; #V2
    LDA #$FF  ; #V2
    STA S_CHOSEN+1          ; (chosen again)  #V2
    STA G_L0AF6             ; (the game waits on)  #V2
    LDA HOLD_SCH  ; #V2
    STA G_L0F0C             ; (the scheme on screen, and its top colours)  #V2
    JSR TopColoursF  ; #V2
    SEC  ; #V2
    RTS  ; #V2
FrameDeferN:  ; #V2
    CLC  ; #V2
    RTS  ; #V2
; Frame's DMA bit ($20 on): the game's (DMACTL), but in play with the  #V2
; game's DLIs off (NMIEN bit 7: its pause between scenes, its screen  #V2
; cleared) none: the blank list. Level 1's tiles showed a row of junk there  #V2
; without the game's DLIs (FINDINGS "Run 10")  #V2
FrameKey:  ; #V2
    LDA S_L1  ; #V2
    BEQ FrameKeyD  ; #V2
    LDA S_STORY  ; #V2
    ORA S_TITLEA  ; #V2
    ORA S_TITLEB  ; #V2
    BNE FrameKeyD  ; #V2
    BIT S_NMIEN  ; #V2
    BMI FrameKeyD  ; #V2
    LDA #$00  ; #V2
    RTS  ; #V2
FrameKeyD:  ; #V2
    LDA S_DMACTL  ; #V2
    AND #$20  ; #V2
    RTS  ; #V2

;;; FARPG (Buttons) -- (V2: a copy in every scene page, through ScButtons, ScFlipWait) #V2
; The fire button, for the game's frame routine ($0FAC-$0FFA; FINDINGS  #V2
; "Two buttons: punch and kick"). The XEGS has one button: held under 20  #V2
; frames it punches on release ($47), held 20 frames it kicks ($46). A 7800  #V2
; two-button joystick (the boot sets the mode) punches on button 1's press  #V2
; (INPT1) and kicks on button 2's (INPT0), each once a press. With neither  #V2
; down, the old way on INPT4 (a one-button joystick). $DC: bit 7 a button  #V2
; down (the game's own test is non-zero), bits 0-1 which of the two; $DB the  #V2
; old way's frames held. A only.  #V2
Buttons:  ; #V2
    LDA G_ZC4  ; #V2
    BNE ButtonsX  ; #V2
    LDA #$00  ; #V2
    BIT INPT1               ; (two-button mode: bit 7 set while pressed)  #V2
    BPL Buttons1  ; #V2
    ORA #$01  ; #V2
Buttons1:  ; #V2
    BIT INPT0  ; #V2
    BPL Buttons2  ; #V2
    ORA #$02  ; #V2
Buttons2:  ; #V2
    CMP #$01  ; #V2
    BCC ButtonsOne  ; #V2
    STA G_ZDB               ; (the two buttons down now)  #V2
    LDA G_ZDC  ; #V2
    AND #$03  ; #V2
    EOR #$03  ; #V2
    AND G_ZDB               ; (the ones just pressed)  #V2
    LSR A  ; #V2
    BCC ButtonsK  ; #V2
    LDA #$FF                ; button 1: a punch, unless a kick is waiting  #V2
    CMP G_Z46  ; #V2
    BEQ ButtonsSet  ; #V2
    STA G_Z47  ; #V2
    BNE ButtonsSet  ; #V2
ButtonsK:  ; #V2
    LSR A  ; #V2
    BCC ButtonsSet  ; #V2
    LDA #$FF                ; button 2: a kick, unless a punch is waiting  #V2
    CMP G_Z47  ; #V2
    BEQ ButtonsSet  ; #V2
    STA G_Z46  ; #V2
ButtonsSet:  ; #V2
    LDA G_ZDB  ; #V2
    ORA #$80  ; #V2
    STA G_ZDC  ; #V2
    LDA #$00  ; #V2
    STA G_ZDB  ; #V2
ButtonsX:  ; #V2
    RTS  ; #V2
ButtonsOne:  ; #V2
    LDA G_ZDC  ; #V2
    AND #$03  ; #V2
    BEQ ButtonsOld  ; #V2
    LDA #$00                ; the two buttons let go  #V2
    STA G_ZDC  ; #V2
    STA G_ZDB  ; #V2
    RTS  ; #V2
ButtonsOld:                 ; (the XEGS's: $0FB0-$0FFA)  #V2
    LDA G_ZDC  ; #V2
    BPL ButtonsUp  ; #V2
    BIT INPT4               ; (bit 7 clear while pressed)  #V2
    BPL ButtonsHeld  ; #V2
    LDA #$00                ; let go: a punch if held under 20 frames  #V2
    STA G_ZDC  ; #V2
    LDA G_ZDB  ; #V2
    CMP #$14  ; #V2
    LDA #$00  ; #V2
    STA G_ZDB  ; #V2
    BCS ButtonsX  ; #V2
    LDA #$FF  ; #V2
    CMP G_Z46  ; #V2
    BEQ ButtonsX  ; #V2
    STA G_Z47  ; #V2
    RTS  ; #V2
ButtonsHeld:  ; #V2
    INC G_ZDB  ; #V2
    LDA G_ZDB  ; #V2
    CMP #$14  ; #V2
    BNE ButtonsX  ; #V2
    LDA #$E8                ; held 20 frames: a kick (and another 44 on)  #V2
    STA G_ZDB  ; #V2
    LDA #$FF  ; #V2
    CMP G_Z47  ; #V2
    BEQ ButtonsX  ; #V2
    STA G_Z46  ; #V2
    RTS  ; #V2
ButtonsUp:  ; #V2
    BIT INPT4  ; #V2
    BMI ButtonsX  ; #V2
    LDA #$80  ; #V2
    STA G_ZDC  ; #V2
    RTS  ; #V2
; the game's flip waits (LDA $0AF6 / BMI): a held list built here, then  #V2
; $0AF6 read as the game did (N its flag; A, X, Y as the game left them but A)  #V2
FlipWait:  ; #V2
    LDA HOLD_N  ; #V2
    BEQ FlipWaitG  ; #V2
    LDA S_BUSY  ; #V2
    BNE FlipWaitG  ; #V2
    LDA S_PEND              ; (built, shown at the next vertical blank)  #V2
    BNE FlipWaitG  ; #V2
    TXA  ; #V2
    PHA  ; #V2
    TYA  ; #V2
    PHA  ; #V2
    JSR Frame  ; #V2
    PLA  ; #V2
    TAY  ; #V2
    PLA  ; #V2
    TAX  ; #V2
FlipWaitG:  ; #V2
    LDA G_L0AF6  ; #V2
    RTS  ; #V2

;;; SCENEPAGE -- assembled at $9420 and placed in every scene page (free
;;; in all six); runs only with a scene page in (never during a blit); the
;;; jump table must stay first (link7800.py SCENEPAGE_ENTRIES)
ScStBuild:
    JMP StBuild
ScColA:
    JMP ColA
ScCol68:
    JMP Col68
ScVsSetup:
    JMP VsSetupSp
ScL1Gen:                    ; (unused: L1Gen is in bank L1_HOME, L1Load calls
    RTS                     ; it through L1Call; the entry keeps the table's
    NOP                     ; layout)
    NOP
ScButtons:                  ; (V2: the game's fire routine, $0FAC) #V2
    JMP Buttons             ; #V2
ScFlipWait:                 ; (V2: the game's flip waits) #V2
    JMP FlipWait            ; #V2


; the end of a scene's load: in level 1's page, the vs fight's mode
; (VsSetup, in the page's level-1 code)
VsSetupSp:
    LDA S_SCENEBANK
    CMP #L1_BANK
    BNE VsSetupSp1
    JMP VsSetup
VsSetupSp1:
    RTS

; The status bar as objects (FINDINGS "The status bar as objects"): the
; game's three status entries ($0B27 clear, $0B3E the player's arrows, $0B98
; the foe's; layout7800.py) set the arrows buffer X shows and come here.
; Buffer X's status list: each bar as blocks of 4 arrows (a 5-byte object
; each: the pitch lines up with the bytes every 20 pixels), then single
; arrows (a byte each) for the rest; the player's from x = 0 rightwards, the
; foe's from x = 160 leftwards. Both from the strips at the heads of pages
; ST_HI-ST_HI+6 (the player's at offset ST_PLO, the foe's at ST_FLO; a
; single arrow is a strip's first byte). The bars never hold more than 28
; arrows between them: 11 objects at most (the list's room is 11 and its end)
StBuild:
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDA #<STATUS_DLA
    CPX #$00
    BEQ StBuild1
    LDA #<STATUS_DLB
StBuild1:
    STA ZP_P1
    LDA #>STATUS_DLA
    STA ZP_P1+1
    LDY #$00
    LDA #32                 ; the player's: those left of the foe's (the
    SEC                     ; bar is 32 arrows' places; the game draws the
    SBC S_STF,X             ; foe's after, each opaque over its place)
    BCS StPMax
    LDA #$00
StPMax:
    CMP S_STP,X
    BCC StPSet
    LDA S_STP,X
StPSet:
    STA S_STR
    LDA #$00
    STA S_STX
    LDA #ST_PLO
    STA S_STL
StPBlk:
    JSR StBlk
    BCS StPOne
    LDA S_STX
    ADC #20                 ; (C clear)
    STA S_STX
    BCC StPBlk
StPOne:
    JSR StOne
    BCS StFoeBar
    LDA S_STX
    ADC #$05                ; (C clear)
    STA S_STX
    BCC StPOne
StFoeBar:
    LDA S_STF,X             ; the foe's
    STA S_STR
    LDA #160
    STA S_STX
    LDA #ST_FLO
    STA S_STL
StFBlk:
    LDA S_STX
    SEC
    SBC #20
    STA S_STX
    JSR StBlk
    BCC StFBlk
    LDA S_STX               ; (no block there)
    ADC #20-1               ; (C set)
    STA S_STX
StFOne:
    LDA S_STX
    SEC
    SBC #$05
    STA S_STX
    JSR StOne
    BCC StFOne
    LDA #$00                ; the list's end
    STA (ZP_P1),Y
    INY
    STA (ZP_P1),Y
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    RTS
; a block of 4 arrows at x S_STX, if 4 are left: C clear; else C set
StBlk:
    LDA S_STR
    CMP #$04
    BCC StNone
    SBC #$04                ; (C set)
    STA S_STR
    LDA #$05
    BNE StObj
; a single arrow at x S_STX, if one is left: C clear; else C set
StOne:
    LDA S_STR
    BEQ StNone
    DEC S_STR
    LDA #$01
; an object A bytes wide from the strip's S_STL at x S_STX, at (ZP_P1),Y
; (Y += 4; none past the list's room); C clear
StObj:
    CPY #STATUS_DLB-STATUS_DLA-5   ; (room for it and the end)
    BCS StObjFull
    EOR #$FF                ; the width's two's complement, 5 bits
    SEC
    ADC #$00
    AND #$1F
    ORA #DL_PAL
    PHA
    LDA S_STL
    STA (ZP_P1),Y
    INY
    PLA
    STA (ZP_P1),Y
    INY
    LDA #ST_HI
    STA (ZP_P1),Y
    INY
    LDA S_STX
    STA (ZP_P1),Y
    INY
StObjFull:
    CLC
    RTS
StNone:
    SEC
    RTS

; PORTA as the XEGS reads it (stick 1 low nibble, stick 2 high, active
; low, same bit order: SWCHA with its nibbles swapped). With the left
; difficulty switch at A, "quick stick": a push that ended since the last
; look is handed over once when the stick reads centred.
ReadStick:
    LDA S_RSWCHA            ; this frame's reading (Inputs)
    ASL A
    ADC #$80
    ROL A
    ASL A
    ADC #$80
    ROL A
    STA S_PORTA
    LDA S_RSWCHB
    AND #$40
    BEQ ReadStickLive
    LDA S_PORTA
    AND #$0F
    CMP #$0F
    BNE ReadStickLive
    LDA S_LATCH
    CMP #$FF
    BEQ ReadStickLive
    LDA S_PORTA
    AND #$F0
    ORA S_LATCH
    STA S_PORTA
ReadStickLive:
    LDA #$FF
    STA S_LATCH
    LDA S_PORTA
    RTS
PgBuildDll:                 ; (V2: this page's copy of the builder, FARPG) #V2
    JMP BuildDll            ; #V2
PgTopErase:                 ; #V2
    JMP TopErase            ; #V2
;;; END SCENEPAGE
;;; LEVEL1PAGE -- placed in level 1's scene pages only (scenes 1 and 6, the
;;; banks with the column loops), wherever both have room; the scene page's
;;; jump table (ScColA, ScCol68) leads here, and only level 1 calls it
; Level 1's posts and pillars: its scenery code draws each as a column of
; 1- or 2-row pieces, 2 rows apart, in a loop (INC $06 / INC $06 / JSR piece
; / LDA $06 / CMP #lim / BCC), one whole blit call a piece -- about 800
; cycles each for a few bytes, and a pillar off screen is clipped away 50
; times over. The loops call here instead, with A = the limit (layout7800
; COLUMN_LOOPS). The first piece and the last are drawn by the game's
; blitter; the ones between are copies of the first, 2 rows further down
; each time, keeping of the screen exactly the pixels the blitter keeps (in
; its store mode: the first byte's left of the shift, unless clipped at the
; left, and the edge byte's right of it). The last piece being the game's,
; everything a blit leaves behind is as the loop left it. Other cases (the
; OR and AND modes, 3 rows or more, wider than 8 bytes, a template piece
; not wholly on screen) go the game's way, piece by piece. FINDINGS "The
; tiny sprites are columns".
Col68:                      ; the loops through $6E68: blitter C while $52 is
    STA S_CLIM              ; negative or below $14 (keeping $05), else A
    LDA G_Z52
    BMI ColC
    CMP #$14
    BCC ColC
    LDA S_CLIM
    JMP ColA
ColC:                       ; (from Col68, S_CLIM set)
    LDA S_L1                ; level 1: an instance (ColL1)  #V1
    BEQ ColC0  ; #V1
    STX S_CX
    STY S_CY
    LDA #$80
    STA L1C_MIR
    LDA #$90
    JMP ColL1
ColC0:  ; #V1
    LDA #$90                ; above the cut: the column one piece (mirrored)  #V1
    JSR J_TOPCOLUMN  ; #V1
ColC1:  ; #V1
    INC G_Z06  ; #V1
    INC G_Z06  ; #V1
    LDA G_Z05  ; #V1
    PHA  ; #V1
    JSR G_L280C  ; #V1
    PLA  ; #V1
    STA G_Z05  ; #V1
    LDA G_Z06  ; #V1
    CMP S_CLIM  ; #V1
    BCC ColC1  ; #V1
    LDA #$00  ; #V1
    STA S_TCOL  ; #V1
    RTS  ; #V1

ColA:
    STA S_CLIM
    STX S_CX
    STY S_CY
    LDA S_L1                ; level 1: an instance (ColL1)  #V1
    BEQ ColA0  ; #V1
    LDA #$00
    STA L1C_MIR
    LDA #$10
    JMP ColL1
ColA0:  ; #V1
    LDA G_Z06               ; (the first piece's line: the column's front box)  #V1
    CLC  ; #V1
    ADC #$02  ; #V1
    STA S_CTOP  ; #V1
    LDA #$10                ; above the cut: the column one piece (FINDINGS  #V1
    JSR J_TOPCOLUMN         ; "Step 1: the rest of the inventory, and the layout")  #V1
    LDA G_Z06  ; #V1
    CLC  ; #V1
    ADC #$02  ; #V1
    STA G_Z06  ; #V1
    JSR G_L284E             ; the first piece  #V1
ColAbove:  ; #V1
    LDA G_Z06  ; #V1
    CMP S_CLIM  ; #V1
    BCS ColDone             ; the only one (or the last)  #V1
    SEC  ; #V1
    SBC #$23                ; a piece above the buffers' top rows (FB_TOP) is  #V1
    CMP #FB_TOP             ; not in the buffer to copy from: the next piece  #V1
    BCS ColTempl            ; through the blitter (which cuts it), until one  #V1
    LDA G_Z06               ; lies wholly in the buffer  #V1
    CLC  ; #V1
    ADC #$02  ; #V1
    STA G_Z06  ; #V1
    JSR G_L284E  ; #V1
    JMP ColAbove  ; #V1
ColTempl:  ; #V1
    JSR ColTemplate  ; #V1
    BCS ColPlain  ; #V1
ColNext:  ; #V1
    LDA G_Z06  ; #V1
    CLC  ; #V1
    ADC #$02  ; #V1
    STA G_Z06  ; #V1
    CMP S_CLIM  ; #V1
    BCS ColLast  ; #V1
    JSR ColPiece  ; #V1
    JSR J_ROWNEXT          ; the next piece: 2 rows down  #V1
    JSR J_ROWNEXT  ; #V1
    JMP ColNext  ; #V1
ColLast:  ; #V1
    JSR G_L284E             ; the last piece  #V1
    JMP ColDone  ; #V1
ColPlain:  ; #V1
    INC G_Z06  ; #V1
    INC G_Z06  ; #V1
    JSR G_L284E  ; #V1
    LDA G_Z06  ; #V1
    CMP S_CLIM  ; #V1
    BCC ColPlain  ; #V1
ColDone:  ; #V1
    LDA #$00  ; #V1
    STA S_TCOL  ; #V1
    JSR J_FGCOL             ; (in front of the picture's fighters, if after)  #V1
    LDX S_CX  ; #V1
    LDY S_CY  ; #V1
    RTS  ; #V1

; after the first piece: carry clear if the copy covers it, with S_CNONE  #V1
; (nothing drawn: wholly off screen), or the template (S_CH rows of S_CNB  #V1
; bytes, S_CK and S_CT) and $14/$15 at the next piece; carry set if not  #V1
ColTemplate:  ; #V1
    LDA G_Z0F  ; #V1
    BEQ ColBad  ; #V1
    BMI ColBad              ; the store mode only  #V1
    LDA #$00  ; #V1
    STA S_CNONE  ; #V1
    LDA G_Z05  ; #V1
    BMI ColTLeft  ; #V1
    CMP #40  ; #V1
    BCS ColTNone            ; right of the screen  #V1
    BCC ColTOn  ; #V1
ColTLeft:  ; #V1
    CLC  ; #V1
    ADC G_Z1F  ; #V1
    BCS ColTOn              ; partly on screen  #V1
ColTNone:  ; #V1
    LDA #$01                ; wholly off: the blitter drew nothing  #V1
    STA S_CNONE  ; #V1
    CLC  ; #V1
    RTS  ; #V1
ColBad:  ; #V1
    SEC  ; #V1
    RTS  ; #V1
ColTOn:  ; #V1
    LDA G_Z06  ; #V1
    SEC  ; #V1
    SBC #$23                ; the row  #V1
    CMP #FB_ROWS  ; #V1
    BCS ColBad  ; #V1
    STA S_CR  ; #V1
    LDA G_Z0D  ; #V1
    CMP #$03  ; #V1
    BCS ColBad              ; at most 2 rows  #V1
    STA S_CH  ; #V1
    CLC  ; #V1
    ADC S_CR  ; #V1
    CMP #FB_ROWS  ; #V1
    BCS ColBad              ; to the last row: RowBase may have cut it short  #V1
    LDA G_Z05  ; #V1
    CLC  ; #V1
    ADC G_Z1F  ; #V1
    LDX #$00                ; the edge byte: when the sprite ends left of 40  #V1
    CMP #40  ; #V1
    BCS ColTNoEdge  ; #V1
    INX  ; #V1
ColTNoEdge:  ; #V1
    STX S_CJ  ; #V1
    TXA  ; #V1
    CLC  ; #V1
    ADC G_Z0E               ; bytes a row: the visible width, and the edge  #V1
    BEQ ColBad  ; #V1
    CMP #$09  ; #V1
    BCS ColBad              ; at most 8  #V1
    STA S_CNB  ; #V1
    LDX #$0F  ; #V1
    LDA #$00  ; #V1
ColTK0:  ; #V1
    STA S_CK,X  ; #V1
    DEX  ; #V1
    BPL ColTK0  ; #V1
    LDA G_Z10  ; #V1
    LSR A  ; #V1
    TAY                     ; the shift  #V1
    LDA G_Z16  ; #V1
    BNE ColTNoFirst         ; clipped at the left: the first byte is all sprite  #V1
    LDA G_Z0E  ; #V1
    BEQ ColTNoFirst  ; #V1
    LDA ColMask1,Y  ; #V1
    STA S_CK  ; #V1
    STA S_CK+8  ; #V1
ColTNoFirst:  ; #V1
    LDA S_CJ  ; #V1
    BEQ ColTNoEdgeK  ; #V1
    LDX S_CNB  ; #V1
    LDA ColMask2,Y  ; #V1
    STA S_CK-1,X  ; #V1
    STA S_CK+7,X  ; #V1
ColTNoEdgeK:  ; #V1
    LDA S_CR  ; #V1
    JSR ColRow              ; the first piece's first row  #V1
    LDA G_Z14  ; #V1
    STA S_CPL  ; #V1
    LDA G_Z15  ; #V1
    STA S_CPH  ; #V1
    LDX #$00  ; #V1
    LDY #$00  ; #V1
    LDA S_CH  ; #V1
    STA S_CHH  ; #V1
ColTRow:  ; #V1
    LDA S_CNB  ; #V1
    STA S_CJ  ; #V1
ColTByte:  ; #V1
    LDA S_CK,X  ; #V1
    EOR #$FF  ; #V1
    AND (G_Z14),Y  ; #V1
    STA S_CT,X  ; #V1
    INX  ; #V1
    INY  ; #V1
    DEC S_CJ  ; #V1
    BNE ColTByte  ; #V1
    LDX #$08                ; row 2  #V1
    LDY #$00  ; #V1
    JSR J_ROWNEXT  ; #V1
    DEC S_CHH  ; #V1
    BNE ColTRow  ; #V1
    LDA S_CPL               ; the next piece: 2 rows down  #V1
    STA G_Z14  ; #V1
    LDA S_CPH  ; #V1
    STA G_Z15  ; #V1
    JSR J_ROWNEXT  ; #V1
    JSR J_ROWNEXT  ; #V1
ColTEnd:  ; #V1
    CLC  ; #V1
    RTS  ; #V1

;;; PART -- placed on its own (no branch crosses into it)  #V1
; one piece, at row $06 - $23 from $14/$15, cut at the bottom as RowBase  #V1
; cuts it (and skipped, as RowBase sends it to its scratch row, when it  #V1
; starts below the bottom or above the top)  #V1
ColPiece:  ; #V1
    LDA S_CNONE  ; #V1
    BNE ColPRet  ; #V1
    LDA G_Z06  ; #V1
    SEC  ; #V1
    SBC #$23  ; #V1
    CMP #FB_ROWS  ; #V1
    BCS ColPRet  ; #V1
    STA S_CR  ; #V1
    LDA #FB_ROWS  ; #V1
    SEC  ; #V1
    SBC S_CR                ; rows to the bottom  #V1
    CMP S_CH  ; #V1
    BCC ColPFit  ; #V1
    LDA S_CH  ; #V1
ColPFit:  ; #V1
    STA S_CHH  ; #V1
ColPNoSt:  ; #V1
    LDA G_Z14  ; #V1
    STA S_CPL  ; #V1
    LDA G_Z15  ; #V1
    STA S_CPH  ; #V1
    LDX #$00  ; #V1
    LDY #$00  ; #V1
ColPRow:  ; #V1
    LDA S_CNB  ; #V1
    STA S_CJ  ; #V1
ColPByte:  ; #V1
    LDA (G_Z14),Y  ; #V1
    AND S_CK,X  ; #V1
    ORA S_CT,X  ; #V1
    STA (G_Z14),Y  ; #V1
    INX  ; #V1
    INY  ; #V1
    DEC S_CJ  ; #V1
    BNE ColPByte  ; #V1
    LDX #$08  ; #V1
    LDY #$00  ; #V1
    JSR J_ROWNEXT          ; row 2  #V1
    DEC S_CHH  ; #V1
    BNE ColPRow  ; #V1
    LDA S_CPL  ; #V1
    STA G_Z14  ; #V1
    LDA S_CPH  ; #V1
    STA G_Z15  ; #V1
ColPRet:  ; #V1
    RTS  ; #V1

ColMask1:                   ; the blitter's $2981: kept left of the shift  #V1
    .byte $00,$C0,$F0,$FC  ; #V1
ColMask2:                   ; its $2985: kept right of it, in the edge byte  #V1
    .byte $FF,$3F,$0F,$03  ; #V1

;;; PART  #V1
; $14/$15 = row A of the buffer being drawn, at the blit's column $1E  #V1
ColRow:  ; #V1
    JSR J_ROWADDR  ; #V1
    LDA G_Z14  ; #V1
    CLC  ; #V1
    ADC G_Z1E  ; #V1
    STA G_Z14  ; #V1
    RTS  ; #V1
;;; PART
; the end of level 1's page's load (scenes 1 and 6): the vs fight runs in
; level 1's page
; (layout7800 VS_REPLACEMENTS), its sites choosing by S_VS ($80 in it).
; Also level 1's constant ($0B; the vs fight's $01, zero-page $FF), the
; scene's identity byte ($7FE7: 1, or 6), and the engine's frame-wait
; counters at $24A5 (the page holds level 1's). (The other pages don't use
; them.)
VsSetup:
    LDA G_ZD0
    CMP #VS_SCENE
    BEQ VsSetupVs
    LDA #$00
    STA S_VS
    LDA #$0B
    STA G_ZFF
    RTS
VsSetupVs:
    LDA #$80
    STA S_VS
    LDA #$01
    STA G_ZFF
    LDA #VS_SCENE
    STA S_SCID
    RTS
;;; PART -- level 1 without the blitter: the column routine's column
; level 1 without the blitter (FINDINGS "Level 1 without the blitter: steps
; 3 and 4"): the column an instance (L1Col, through SysL1Col; L1C_MIR set),
; nothing drawn; its part above the cut one top piece as before (A:
; TopColumn's argument); $06 left as the loop leaves it (the first row at or
; past the limit, 2 rows a piece), X and Y as they came
ColL1:
    PHA
    LDA G_Z06
    CLC
    ADC #$02
    STA S_CTOP
    PLA
    JSR J_TOPCOLUMN
    JSR J_L1COL
ColL1A:
    INC G_Z06
    INC G_Z06
    LDA G_Z06
    CMP S_CLIM
    BCC ColL1A
    LDA #$00
    STA S_TCOL
    LDX S_CX
    LDY S_CY
    RTS

;;; END LEVEL1PAGE
;;; LEVEL2PAGE -- (V2) placed in level 2's scene page only (bank 2): its #V2
;;; capture and list code for the window wall's joints #V2
; Level 2's window wall (FINDINGS "Level 2's windows: the joints as one #V2
; entry"): each picture the game paints the wall over the old joints and #V2
; draws the new ones, 32 pixels apart, plain left of pixel 84 and mirrored #V2
; from it. Each was an entry of the top list, and each draw a cover test #V2
; over it. Now a buffer's joints are one entry, of the plain joint's piece: #V2
; its left pixel the leftmost joint's, its bytes 0 to the last joint's #V2
; first + 1, as a box (TopEBox, the fills' trims as before); its zones' #V2
; slices $FE, which TopEmitLo hands to L2JEmit. The erases are no piece #V2
; L2Joint: from TopCapture, a joint (S_TI the piece, S_TL its left pixel, S_TBUF the #V2
; buffer; X, Y free) #V2
L2Joint:                    ; #V2
    LDX S_TI                ; #V2
    LDA TOP_FLAGS,X         ; (the mirrored joint: the plain one's piece, #V2
    BPL L2Jt1               ; the one before it) #V2
    DEX                     ; #V2
L2Jt1:                      ; #V2
    STX S_TI                ; #V2
    JSR TopBufY             ; #V2
    LDA TOPLN,Y             ; #V2
    BEQ L2JNew              ; #V2
    CLC                     ; #V2
    ADC S_TBUF              ; #V2
    TAX                     ; #V2
    DEX                     ; (the list's last: this picture's) #V2
    LDA TOPLI,X             ; #V2
    CMP S_TI                ; #V2
    BEQ L2JHave             ; #V2
    JSR TopOne              ; (an earlier picture's: out, this one at the end) #V2
L2JNew:                     ; #V2
    JSR TopBufY             ; #V2
    LDA TOPLN,Y             ; #V2
    CMP #TOPL_MAX           ; #V2
    BCS L2JRts              ; #V2
    ADC S_TBUF              ; #V2
    TAX                     ; #V2
    LDA TOPLN,Y             ; #V2
    ADC #$01                ; #V2
    STA TOPLN,Y             ; #V2
    LDA S_TI                ; #V2
    STA TOPLI,X             ; #V2
L2JReset:                   ; #V2
    LDA S_TL                ; #V2
    STA TOPLX,X             ; #V2
    LDA #$00                ; #V2
    STA TOPLK0,X            ; #V2
    LDA #$01                ; #V2
    STA TOPLK1,X            ; #V2
L2JSt:                      ; #V2
    JSR TbcStale            ; #V2
    JMP TopStale            ; #V2
L2JRts:                     ; #V2
    RTS                     ; #V2
L2JHave:                    ; (X the entry: this joint d pixels from its left) #V2
    LDY #$00                ; #V2
    LDA TOPLX,X             ; #V2
    CMP #160                ; #V2
    BCC L2JH1               ; #V2
    DEY                     ; #V2
L2JH1:                      ; #V2
    STY TP_T2               ; #V2
    LDA S_TL                ; #V2
    SEC                     ; #V2
    SBC TOPLX,X             ; #V2
    STA TP_T0               ; #V2
    LDA S_TL+1              ; #V2
    SBC TP_T2               ; #V2
    STA TP_T1               ; #V2
    LDA TP_T0               ; (off the 32-pixel grid: a new view's) #V2
    AND #$1F                ; #V2
    BNE L2JReset            ; #V2
    LDA TP_T1               ; #V2
    BMI L2JLeft             ; #V2
    LDA TP_T0               ; (right of it: its first byte kept, and the #V2
    LSR A                   ; span to its byte) #V2
    LSR A                   ; #V2
    STA TP_T2               ; #V2
    CMP TOPLK0,X            ; #V2
    BCS L2JH2               ; #V2
    STA TOPLK0,X            ; #V2
L2JH2:                      ; #V2
    LDA TP_T2               ; #V2
    CLC                     ; #V2
    ADC #$01                ; #V2
    CMP TOPLK1,X            ; #V2
    BCC L2JRts              ; #V2
    BEQ L2JRts              ; #V2
    STA TOPLK1,X            ; #V2
    JMP L2JSt               ; #V2
L2JLeft:                    ; (a new leftmost: its bytes from it) #V2
    LDA #$00                ; #V2
    SEC                     ; #V2
    SBC TP_T0               ; #V2
    LSR A                   ; #V2
    LSR A                   ; #V2
    CLC                     ; #V2
    ADC TOPLK1,X            ; #V2
    STA TOPLK1,X            ; #V2
    LDA #$00                ; #V2
    STA TOPLK0,X            ; #V2
    LDA S_TL                ; #V2
    STA TOPLX,X             ; #V2
    JMP L2JSt               ; #V2
;;; PART #V2
; L2JEmit: from TopEmitLo (by JMP: back to TopEmitSkip), the joints' entry #V2
; X (kept) in the zone TopEmit #V2
; writes (S_EJ its slice, S_ETMP+1 its page, TP_PASS 1 counting): an #V2
; object a joint, as TopEmitLo writes a piece's, its slice's column from #V2
; L2JZT (the plain or the mirrored joint's: J_* from the build) #V2
L2JEmit:                    ; #V2
    LDA #$00                ; #V2
    STA TP_T1               ; (the joint's byte in the entry) #V2
    LDA TOPLX,X             ; #V2
    STA TP_T2               ; (its left pixel) #V2
L2JE1:                      ; #V2
    LDA TP_T1               ; #V2
    CMP TOPLK1,X            ; #V2
    BCS L2JERts             ; #V2
    CMP TOPLK0,X            ; #V2
    BCC L2JENext            ; (trimmed off) #V2
    LDA S_EW                ; (room: as TopEmitMeets) #V2
    CMP #TOPDL_ARG-5        ; #V2
    BCS L2JERts             ; #V2
    LDA TP_PASS             ; #V2
    BEQ L2JEW               ; #V2
    LDA S_EW                ; (counting) #V2
    CLC                     ; #V2
    ADC #$04                ; #V2
    STA S_EW                ; #V2
    JMP L2JENext            ; #V2
L2JEW:                      ; #V2
    LDY #$00                ; (plain: left of pixel 84, or off the left) #V2
    LDA TP_T2               ; #V2
    CMP #160                ; #V2
    BCS L2JEP               ; #V2
    CMP #84                 ; #V2
    BCC L2JEP               ; #V2
    LDY #$06                ; #V2
L2JEP:                      ; #V2
    STY TP_T0               ; #V2
    TYA                     ; #V2
    CLC                     ; #V2
    ADC S_EJ                ; #V2
    TAY                     ; #V2
    LDA L2JZT,Y             ; #V2
    LDY S_EW                ; #V2
    STA (ZP_P1),Y           ; #V2
    INY                     ; #V2
    LDA #J_PPALW            ; #V2
    STA (ZP_P1),Y           ; #V2
    INY                     ; #V2
    LDA S_EJ                ; (the last zone: its slices TOP_Z4O pages lower) #V2
    CMP #$04                ; #V2
    LDA S_ETMP+1            ; #V2
    BCC L2JEH               ; #V2
    STY S_EI                ; #V2
    LDY TP_T0               ; #V2
    SEC                     ; #V2
    SBC L2JZT+5,Y           ; #V2
    LDY S_EI                ; #V2
L2JEH:                      ; #V2
    STA (ZP_P1),Y           ; #V2
    INY                     ; #V2
    LDA TP_T2               ; #V2
    STA (ZP_P1),Y           ; #V2
    INY                     ; #V2
    STY S_EW                ; #V2
L2JENext:                   ; #V2
    LDA TP_T1               ; #V2
    CLC                     ; #V2
    ADC #$08                ; #V2
    STA TP_T1               ; #V2
    LDA TP_T2               ; #V2
    CLC                     ; #V2
    ADC #$20                ; #V2
    STA TP_T2               ; #V2
    JMP L2JE1               ; #V2
L2JERts:                    ; #V2
    JMP TopEmitSkip         ; #V2
L2JZT:                      ; (plain: slices 0-4, Z4O; mirrored the same) #V2
    .byte J_PZ0, J_PZ1, J_PZ2, J_PZ3, J_PZ4, J_PZ4O  ; #V2
    .byte J_MZ0, J_MZ1, J_MZ2, J_MZ3, J_MZ4, J_MZ4O  ; #V2
;;; END LEVEL2PAGE #V2
;;; FARL0 (L1GenA) -- level 1's windows rendered into the bitmap's pages
;;; (the load's code, L1Gen and L1TLoad: bank L1_GEN, 0, run only while
;;; the load shows the blank list, so its MARIA copy's title data never
;;; shows; FINDINGS "Levels 3 and 4 as tiles")
;;; from the scene's own images at its load (L1Load, through L1Call;
;;; port/l1scene7800.py makes the tables, and checks this step for step:
;;; generate). In bank L1_HOME with its tables (it was in level 1's page)
; each shape's record (L1S_R: its address; bank L1_HOME, read through
; L1Fetch: its flags, width, first part, entries; its image's address, row
; and limit from the capture's arrays, L1K_*, bank L1_CAP; then its
; entries, T and C a part: the window's line g at page
; T - g, low byte C; T 0 none) taken, then each entry's window made
; of its zone part's lines (L1P_*): a line in the part's rows that the shape
; covers is the image's row, mirrored (bit 7) or its columns repeated (bit
; 4), converted for the part's background (L1Conv); every other line 0. A
; column (bit 6): its pieces every 2 rows from its row, the last the first
; at or past its limit. The image's rows are read through L1Fetch too, from
; the scene page or the art bank (bit 5)
L1Gen:
    LDA L1G_SF              ; (an AND mask's black: its 0s; with the set's
    AND #$10                ; flag bit 4, the rooms', its 0s and 1s: L1Conv)
    BEQ L1Gen0A
    LDA #$80
    BNE L1Gen0
L1Gen0A:
    LDA #$C0
L1Gen0:
    STA L1G_AM
L1GenS:                     ; (its set's shapes: L1G_S from the first, L1Load's,
    LDA L1G_S               ; to L1G_KE)
    CMP L1G_KE
    BCC L1GenS1
    BIT L1G_SF              ; then the tiles (characters, maps), with a set's
    BVC L1GenS0             ; tiles
    JSR L1TLoad
L1GenS0:
    LDA #$00                ; then its variables cleared (console RAM: just
    TAX                     ; theirs, two halves; the instances' tables need
L1GenC:                     ; none: read only below their counts, L1_E),
    STA L1VARS,X            ; each buffer's view unknown, no world
    STA L1VARB,X
    INX
    CPX #L1VARS_N
    BNE L1GenC
    LDA #$FF
    STA L1_V+1
    STA L1_V+3
    STA L1_WLD
    STA L1_WLD+1
    RTS
L1GenS1:
    LDX #$05                ; its flags, width, image's address, row and
L1GenK:                     ; limit: the capture's arrays' (bank L1_CAP; the
    TXA                     ; limits' L1_GEN: the load's only)
    PHA
    LDA L1GenKL,X
    CLC
    ADC L1G_S
    STA ZP_P1
    LDA L1GenKH,X
    ADC #$00
    STA ZP_P1+1
    LDA L1GenKB,X
    LDX #$01
    JSR L1Fetch
    PLA
    TAX
    LDA L1G_BUF
    STA L1G_FL,X
    DEX
    BPL L1GenK
    LDA L1G_W               ; (L1K_W less bit 7, in front)
    AND #$7F  ; #V1
    AND #$1F                ; (V2: and bit 6, in the tiles too) #V2
    STA L1G_W
    LDA L1G_S
    ASL A                   ; its record's address (2 x the shape: up to 255)
    STA ZP_P1
    LDA #>L1S_R
    ADC #$00
    STA ZP_P1+1
    LDA ZP_P1
    CLC
    ADC #<L1S_R
    STA ZP_P1
    BCC L1GenS2
    INC ZP_P1+1
L1GenS2:
    LDA #L1_HOME
    LDX #$02
    JSR L1Fetch
    LDA L1G_BUF
    STA ZP_P1
    LDA L1G_BUF+1
    STA ZP_P1+1
    LDA #L1_HOME            ; its fields (first part, entries)
    LDX #$02
    JSR L1Fetch
    LDA L1G_BUF
    STA L1G_P
    LDA L1G_BUF+1
    STA L1G_NE
    LDA ZP_P1               ; its entries (past its fields: +2)
    CLC
    ADC #$02
    STA ZP_P1
    BCC L1GenF1
    INC ZP_P1+1
L1GenF1:
    LDA L1G_NE
    ASL A
    TAX
    LDA L1G_FL              ; (an overlay's entries after its own: twice as many)
    AND #$04
    BEQ L1GenF2
    TXA
    ASL A
    TAX
L1GenF2:
    LDA #L1_HOME
    JSR L1Fetch
    LDX #$00                ; (its entries, out of the fetches' way)
L1GenEC:
    CPX #L1_NB
    BCS L1GenI
    LDA L1G_BUF,X
    STA L1G_E,X
    INX
    BNE L1GenEC
L1GenI:
    LDA L1G_FL              ; its image's bank
    AND #$20
    BEQ L1GenI1
    LDA #ART_BANK
    BNE L1GenI2
L1GenI1:
    LDA S_SCENEBANK
L1GenI2:
    STA L1G_IB
    LDA L1G_SRC             ; its rows and width
    STA ZP_P1
    LDA L1G_SRC+1
    STA ZP_P1+1
    LDA L1G_IB
    LDX #$02
    JSR L1Fetch
    LDA L1G_BUF
    STA L1G_ROWS
    LDA L1G_BUF+1
    STA L1G_IW
    LDA #$00
    STA L1G_J
L1GenJ:
    LDA L1G_J
    CMP L1G_NE
    BCC L1GenJ1
    LDA L1G_FL              ; then its overlay's: the same parts again, in
    AND #$04                ; mode 3 (flags bit 2 off: once)
    BEQ L1GenJX
    LDA L1G_FL
    EOR #$07
    STA L1G_FL
    LDA L1G_P
    SEC
    SBC L1G_NE
    STA L1G_P
    ASL L1G_NE
    JMP L1GenJ
L1GenJX:
    INC L1G_S
    JMP L1GenS
L1GenJ1:
    ASL A
    TAX
    LDA L1G_E,X
    STA L1G_T
    LDA L1G_E+1,X
    STA L1G_C
    LDA L1G_T
    BEQ L1GenJN             ; (none)
    ROL A                   ; its palette (bits 6-7): the colour it shows
    ROL A                   ; clear (L1GenTB); its page (the rest, + $40)
    ROL A
    AND #$03
    TAY
    LDA L1GenTB,Y
    STA L1G_BG
    LDA L1GenOC,Y           ; (an overlay: the colour it draws, its value)
    STA L1G_OC
    LDA L1GenOV,Y
    STA L1G_OV
    LDA L1G_T
    AND #$3F
    CLC
    ADC #$40
    STA L1G_T
    LDA L1G_P
    CLC
    ADC L1G_J
    TAX
    LDA L1P_Z0,X
    STA L1G_Z0
    LDA L1P_H,X
    STA L1G_H
    LDA L1P_A,X
    STA L1G_A
    LDA L1P_E,X
    STA L1G_EE
    LDA #$00
    STA L1G_G
L1GenG:
    LDA L1G_G
    CMP L1G_H
    BCS L1GenJN
    LDA L1G_T
    SEC
    SBC L1G_G
    STA ZP_P2+1
    LDA L1G_C
    STA ZP_P2
    LDA L1G_Z0
    CLC
    ADC L1G_G
    STA L1G_R
    JSR L1GenLine
    INC L1G_G
    JMP L1GenG
L1GenJN:
    INC L1G_J
    JMP L1GenJ
;;; FARL0 (L1TLoadP) -- (the tiles' loader)
; level 1's tiles into cart RAM (FINDINGS "Level 1: the cliffs broken; the
; background as a world of tiles"): the build's streams (l1world7800.stream;
; in pieces, any bank: L1TSP, bank L1_HOME, each piece's bank and address,
; $FF the end) read a byte at a time through L1Fetch: 0, an address to go on
; at (its high byte 0: the piece's end); n (1-127) and n bytes as they are;
; $80 + n and a byte, n times. The characters' line pages (CHBASE L1_CHB
; on), and each map row. The CPU only writes cart RAM
L1TLoad:
    LDA L1G_TS              ; (the set's pieces, to its $FF)
    STA L1G_J
L1TLP:
    LDA #<L1TSP             ; (the next piece)
    CLC
    ADC L1G_J
    STA ZP_P1
    LDA #>L1TSP
    ADC #$00
    STA ZP_P1+1
    LDA #L1_LDB             ; (the pieces' table: the load's data's bank)
    LDX #$03
    JSR L1Fetch
    LDA L1G_BUF
    CMP #$FF
    BEQ L1TLRts
    STA L1G_IB
    LDA L1G_BUF+1
    STA ZP_P1
    LDA L1G_BUF+2
    STA ZP_P1+1
    JSR L1TL0
    LDA L1G_J
    CLC
    ADC #$03
    STA L1G_J
    JMP L1TLP
L1TLRts:
    RTS
L1TL0:
    JSR L1TByte
    BNE L1TL1
    JSR L1TByte             ; (an address)
    STA ZP_P2
    JSR L1TByte
    STA ZP_P2+1
    BNE L1TL0
    RTS
L1TL1:
    BMI L1TLRun
    STA L1G_K               ; (n bytes as they are)
L1TL2:
    JSR L1TByte
    JSR L1TPut
    DEC L1G_K
    BNE L1TL2
    BEQ L1TL0
L1TLRun:
    AND #$7F                ; (a byte, n times)
    STA L1G_K
    JSR L1TByte
L1TL3:
    JSR L1TPut
    DEC L1G_K
    BNE L1TL3
    BEQ L1TL0
L1TByte:
    LDA L1G_IB
    LDX #$01
    JSR L1Fetch
    INC ZP_P1
    BNE L1TB1
    INC ZP_P1+1
L1TB1:
    LDA L1G_BUF
    RTS
L1TPut:
    LDY #$00
    STA (ZP_P2),Y
    INC ZP_P2
    BNE L1TP1
    INC ZP_P2+1
L1TP1:
    RTS
;;; FARL0 (L1GenTab) -- (L1Gen's tables)
L1GenKL:                    ; (into L1G_FL, L1G_W, L1G_SRC, +1, L1G_ROW, L1G_LIM)
    .byte <L1K_FL, <L1K_W, <L1K_SLO, <L1K_SHI, <L1K_ROW, <L1K_LIM
L1GenKH:
    .byte >L1K_FL, >L1K_W, >L1K_SLO, >L1K_SHI, >L1K_ROW, >L1K_LIM
L1GenKB:                    ; (the limits: the load's data's bank, L1_LDB)
    .byte L1_CAP, L1_CAP, L1_CAP, L1_CAP, L1_CAP, L1_LDB
L1GenTB:                    ; (palette 1: black clear; 2: the sky; 3: the floor's colour)
    .byte 0, 0, 2, 1
L1GenOC:                    ; (an overlay's: palette 1 the floor's colour as 1; 2
    .byte 0, 1, 0, 2        ; black as 2; 3 the sky as 2)
L1GenOV:
    .byte 0, 1, 2, 2
;;; FARL0 (L1GenLn) -- (L1Gen's lines, on)
; the window's line for row L1G_R at ZP_P2 (L1GenZero: all 0)
L1GenZero:
    LDY L1G_W
    LDA #$00
L1GenZ1:
    DEY
    BMI L1GenZ2
    STA (ZP_P2),Y
    JMP L1GenZ1
L1GenZ2:
    RTS
L1GenLine:
    LDA L1G_R
    CMP L1G_A
    BCC L1GenZero           ; above the part's rows
    CMP L1G_EE
    BCS L1GenZero           ; below them
    LDA L1G_FL
    AND #$08
    BEQ L1GenLI
    LDA L1G_FL
    AND #$10
    BEQ L1GenLS
    LDA L1G_R               ; the rails with the sky (bits 3 and 4): from its
    CMP L1G_ROW             ; row the rails' image, from its limit to its row
    BCS L1GenLI             ; the sky ($AA)
    CMP L1G_LIM
    BCC L1GenZero
    LDA #$AA
    BNE L1GenSolV
L1GenLS:
    LDA L1G_R               ; a solid strip (bit 3): its value (the image's
    CMP L1G_ROW             ; address's low byte) from its row to its limit
    BCC L1GenZero
    CMP L1G_LIM
    BCS L1GenZero
    LDA L1G_SRC
L1GenSolV:
    LDY L1G_W
L1GenSol:
    DEY
    BMI L1GenSol1
    STA (ZP_P2),Y
    JMP L1GenSol
L1GenSol1:
    RTS
L1GenZ:                     ; (L1GenZero, in reach)
    JMP L1GenZero
L1GenLI:
    LDA L1G_R
    SEC
    SBC L1G_ROW
    BCC L1GenZ           ; above the shape
    STA L1G_K
    BIT L1G_FL
    BVC L1GenLB
    LSR A                   ; a column: its piece, at most (LIM - ROW + 1) / 2
    STA L1G_IN
    LDA L1G_LIM
    SEC
    SBC L1G_ROW
    CLC
    ADC #$01
    LSR A
    CMP L1G_IN
    BCC L1GenZ
    LDA L1G_K
    AND #$01
    STA L1G_K
L1GenLB:
    LDA L1G_K
    CMP L1G_ROWS
    BCS L1GenZ
    LDA L1G_SRC             ; the image row: SRC + 2 + K * IW
    CLC
    ADC #$02
    STA ZP_P1
    LDA L1G_SRC+1
    ADC #$00
    STA ZP_P1+1
    LDX L1G_K
L1GenLM:
    DEX
    BMI L1GenLM1
    LDA ZP_P1
    CLC
    ADC L1G_IW
    STA ZP_P1
    BCC L1GenLM
    INC ZP_P1+1
    JMP L1GenLM
L1GenLM1:
    LDA L1G_IB
    LDX L1G_IW
    JSR L1Fetch
    LDA #$00
    STA L1G_K
L1GenLK:
    LDA L1G_K
    CMP L1G_W
    BCS L1GenLDone
    LDA L1G_FL
    AND #$10
    BEQ L1GenLK1
    LDA L1G_K               ; repeated: K mod IW
L1GenLKm:
    CMP L1G_IW
    BCC L1GenLK2
    SBC L1G_IW
    JMP L1GenLKm
L1GenLK1:
    LDA L1G_K
    BIT L1G_FL
    BPL L1GenLK2
    LDA L1G_W               ; mirrored: W - 1 - K
    SEC
    SBC #$01
    SEC
    SBC L1G_K
L1GenLK2:
    TAY
    LDA L1G_BUF,Y
    BIT L1G_FL
    BPL L1GenLK3
    TAX
    LDA TOP_MIRROR,X
L1GenLK3:
    JSR L1Conv
    LDY L1G_K
    STA (ZP_P2),Y
    INC L1G_K
    JMP L1GenLK
L1GenLDone:
    RTS

;;; FARL0 (L1ConvP) -- (L1Gen's conversion: a piece of its own, bank 0's runs
;;; are short)
; a byte's 4 pixels as the window holds them (A in and out): a stored
; image's background colour 0 and its black the background's index; an AND
; mask's 0 black (1), else 0; an OR image as drawn; an overlay (mode 3)
; its one colour
L1Conv:
    STA L1G_IN
    LDA #$00
    STA L1G_OUT
    LDA L1G_FL
    AND #$03
    BNE L1ConvM
    LDX #$04
L1ConvS:
    ASL L1G_OUT
    ASL L1G_OUT
    LDA #$00
    ASL L1G_IN
    ROL A
    ASL L1G_IN
    ROL A
    CMP L1G_BG
    BEQ L1ConvS0
    CMP #$00
    BNE L1ConvS1
    LDA L1G_BG
L1ConvS1:
    ORA L1G_OUT
    STA L1G_OUT
L1ConvS0:
    DEX
    BNE L1ConvS
    LDA L1G_OUT
    RTS
L1ConvM:
    CMP #$01
    BEQ L1ConvA
    CMP #$03
    BEQ L1ConvO
    LDA L1G_IN
    RTS
L1ConvO:                    ; an overlay: its colour (L1G_OC) as L1G_OV, else 0
    LDX #$04
L1ConvO1:
    ASL L1G_OUT
    ASL L1G_OUT
    LDA #$00
    ASL L1G_IN
    ROL A
    ASL L1G_IN
    ROL A
    CMP L1G_OC
    BNE L1ConvO2
    LDA L1G_OV
    ORA L1G_OUT
    STA L1G_OUT
L1ConvO2:
    DEX
    BNE L1ConvO1
    LDA L1G_OUT
    RTS
L1ConvA:
    LDX #$04
L1ConvA1:
    ASL L1G_OUT
    ASL L1G_OUT
    LDA L1G_IN
    AND L1G_AM              ; ($C0: 0 black; the canvas's $80: 0 and 1, which
    BNE L1ConvA2            ; AND the floor's stripes, colour 2, to black)
    INC L1G_OUT
L1ConvA2:
    ASL L1G_IN
    ASL L1G_IN
    DEX
    BNE L1ConvA1
    LDA L1G_OUT
    RTS
;;; RAMFILL -- assembled at $7203 (cart RAM free between the engine's two
;;; parts) and copied there at load (CopyFill); the jump table must stay
;;; first (link7800.py RAMFILL_ENTRIES)
; The fills: the game's rectangle ($2CCD) and pattern ($2D03) fills store
; row by row, STA ($14),Y / DEY / BPL, 11 cycles a byte. Here the rows go 4
; at a time into the engine's store block at $2D19 (STA row,X for each of 4
; rows, DEX, BPL), whose row addresses are written in first, so each byte
; costs 5 cycles; the columns loop. A fill never reads the buffer, so the
; order of the stores can't change what it leaves. It leaves $14/$15 at the
; last row and Y = $FF, as the game's loops do. Being in RAM, it jumps
; through its own JMPs (FpJmp, FpGo), written as it goes. FINDINGS "The
; fast fill".
RfPass:
    JMP FillPass
RfPattern:
    JMP FillPat

; (first, so the patch code is in one page: FpPatchLo holds low bytes)
; one block: its rows' addresses into the store block, then the block (its
; RTS returns from here); $14/$15 move on to the next block's first row
FpOne:
    LDA G_Z14
    LDY G_Z15
FpJmp:
    JMP FpPatch0
; rows one apart: each store's row, then one row down (a page, or at a
; column's foot the next column's top: sys7800 RowNext, inline)
FpPatch0:
    STA FILL_BLK+1
    STY FILL_BLK+2
    DEY
    CPY #FB_PBOT-1
    BNE FpPatch1
    JSR FpWrap
FpPatch1:
    STA FILL_BLK+4
    STY FILL_BLK+5
    DEY
    CPY #FB_PBOT-1
    BNE FpPatch2
    JSR FpWrap
FpPatch2:
    STA FILL_BLK+7
    STY FILL_BLK+8
    DEY
    CPY #FB_PBOT-1
    BNE FpPatch3
    JSR FpWrap
FpPatch3:
    STA FILL_BLK+10
    STY FILL_BLK+11
    DEY
    CPY #FB_PBOT-1
    BNE FpPatched
    JSR FpWrap
    JMP FpPatched
; rows two apart (the pattern fill): two steps each
FpQatch0:
    STA FILL_BLK+1
    STY FILL_BLK+2
    JSR FpStep2
FpQatch1:
    STA FILL_BLK+4
    STY FILL_BLK+5
    JSR FpStep2
FpQatch2:
    STA FILL_BLK+7
    STY FILL_BLK+8
    JSR FpStep2
FpQatch3:
    STA FILL_BLK+10
    STY FILL_BLK+11
    JSR FpStep2
FpPatched:
    STA G_Z14
    STY G_Z15
    LDX G_Z0E
    LDA S_FVAL
FpGo:
    JMP FILL_BLK

; the pattern: rows alternate $12 and $02, the last row $02 (the game's X
; counts the rows down: odd $02, even $12). The $12 rows first, then the $02
; rows, each 80 bytes apart, so the last pass ends at the last row
FillPat:
    LDA #$02                ; every other row
    STA S_FSTRIDE
    LDA G_Z12
    STA S_FVAL
    LDA G_Z14
    STA S_FP0
    LDA G_Z15
    STA S_FP0+1
    LDA G_Z0D
    LSR A
    STA S_FCOUNT            ; $12 rows: half, rounded down
    BCC FpEvenH             ; an even count: from the first row
    JSR FpNextZ             ; odd: from the second row
FpEvenH:
    JSR FillPass
    LDA G_Z0D
    LSR A
    ADC #$00
    STA S_FCOUNT            ; $02 rows: half, rounded up
    LDA G_Z02
    STA S_FVAL
    LDA S_FP0
    STA G_Z14
    LDA S_FP0+1
    STA G_Z15
    LDA G_Z0D
    LSR A
    BCS FpSecond            ; an odd count: from the first row
    JSR FpNextZ             ; even: from the second
FpSecond:
    JSR FillPass
    JMP G_L2D3E

; S_FCOUNT rows of S_FVAL from $14/$15, S_FSTRIDE rows apart, $0E+1 bytes each;
; leaves $14/$15 at the last row and Y = $FF. The rows over a multiple of 4
; first (entering the block part way), then whole blocks of 4
FillPass:
    LDA S_FSTRIDE           ; 1 or 2 rows apart: the patch sequence
    SEC
    SBC #$01
    ASL A
    ASL A
    STA FpSeq
    LDA S_FCOUNT
    AND #$03
    BEQ FpFull
    EOR #$FF
    SEC
    ADC #$04
    TAX                     ; the first of the block's 4 stores used
    CLC
    ADC FpSeq               ; the sequence for the stride
    TAY
    LDA FpPatchLo,Y
    STA FpJmp+1
    STX S_FT
    TXA
    ASL A
    ADC S_FT                ; 3 bytes a store
    ADC #<FILL_BLK
    STA FpGo+1
    SEC
    SBC #<FILL_NEXT
    STA FILL_BPLI+1         ; the loop starts at the first store used
    JSR FpOne
FpFull:
    LDA S_FCOUNT
    LSR A
    LSR A
    STA S_FK                ; whole blocks
    BEQ FpDone
    LDY FpSeq
    LDA FpPatchLo,Y
    STA FpJmp+1
    LDA #<FILL_BLK
    STA FpGo+1
    SEC
    SBC #<FILL_NEXT
    STA FILL_BPLI+1
FpFullLoop:
    JSR FpOne
    DEC S_FK
    BNE FpFullLoop
FpDone:
    LDA S_FCOUNT
    BEQ FpDoneHi
    LDA FILL_BLK+10         ; the last row: the last block's fourth store's
    STA G_Z14
    LDA FILL_BLK+11
    STA G_Z15
FpDoneHi:
    LDY #$FF
    RTS

FpPatchLo:
    .byte <FpPatch0,<FpPatch1,<FpPatch2,<FpPatch3
    .byte <FpQatch0,<FpQatch1,<FpQatch2,<FpQatch3
FpSeq:
    .byte $00               ; 0 rows one apart, 4 two apart
; A/Y (a row's address) past a column's foot: the next column's top (a
; pointer outside the buffers, the clip row, never gets here)
FpWrap:
    LDY #FB_PTOP
    CLC
    ADC #40
    RTS
; A/Y two rows down
FpStep2:
    DEY
    CPY #FB_PBOT-1
    BNE FpStep2b
    JSR FpWrap
FpStep2b:
    DEY
    CPY #FB_PBOT-1
    BNE FpStep2c
    JSR FpWrap
FpStep2c:
    RTS
; $14/$15 one row down
FpNextZ:
    LDA G_Z14
    LDY G_Z15
    DEY
    CPY #FB_PBOT-1
    BNE FpNextZ1
    JSR FpWrap
FpNextZ1:
    STA G_Z14
    STY G_Z15
    RTS
; the store block (FILL_BLK; it was the engine's at $2D19, now in ROM): 4
; rows a pass, each STA's address written in for the block, the BPL's
; offset set so the loop starts at the first store used; one page
FILL_BLK:
    STA $FFFF,X
    STA $FFFF,X
    STA $FFFF,X
    STA $FFFF,X
    DEX
FILL_BPLI:
    .byte $10,$F1        ; BPL FILL_BLK (its offset: FILL_BPLI+1)
FILL_NEXT:
    RTS
;;; END RAMFILL

;;; FAR (RowBase) -- each ;;; FAR piece below is assembled on its own and  #V1
;;; placed in a free gap of the fixed bank (the system block above has no room  #V1
;;; left); a piece may use equates but not labels from above or from another  #V1
;;; piece, and the block above reaches it through equates the build supplies  #V1
;  #V1
; RowBase: the game's $2D46 (row Y - 35, its first byte in the buffer $07  #V1
; names, into $14/$15; the rows are one page apart, so SysRowAddr, and the  #V1
; game's times-40 and buffer base after the call are skipped), with the  #V1
; bottom check it lacks. The blitters and fills that call it draw $0D rows 40 bytes  #V1
; apart from there; a draw that ran past row 153 wrote over whatever follows  #V1
; the buffer (on the 7800, the engine). So $0D is cut to the rows left, and a  #V1
; draw that starts at or past the bottom -- or above the top, where Y - 35  #V1
; wraps to a large row, as on the XEGS -- draws its one row into the scratch  #V1
; row instead, returning straight to $2D46's caller. Nothing that reaches the  #V1
; screen changes. Every blit and fill sets $0D afresh before calling here.  #V1
RowBase:  ; #V1
    LDA S_NOFILL            ; (a fighter-box erase: nothing painted)  #V1
    BNE RowOff  ; #V1
    LDA G_Z06  ; #V1
    SEC  ; #V1
    SBC #$23                ; the row  #V1
    CMP #ST_ROW  ; #V1
    BCS RowOff              ; (the status rows are objects: nothing draws there)  #V1
    CMP #FB_TOP  ; #V1
    BCS RowBelow  ; #V1
; it starts in the top rows (objects: FINDINGS "The top rows as objects"),  #V1
; which the buffers no longer hold: its rows there are cut, and a blit's  #V1
; source moves on past them ($1F bytes a row, both blitters)  #V1
    STA G_L2DA1  ; #V1
    TSX                     ; the caller of $2D46: a blitter (engine part 2's  #V1
    LDA $0104,X             ; $2800-$2BFF, in cart RAM) or else a fill (or the  #V1
    SEC                     ; common code's two calls, which the earlier page  #V1
    SBC #>G_L2800           ; test also counted as fills): by the return's  #V1
    CMP #E2_BPAGES          ; page (FINDINGS "RAM and fixed ROM: steps 4, 5")  #V1
    BCC RowCutCount  ; #V1
    LDA $0104,X             ; (the page again)  #V1
    CMP #>TOP_RETRECT       ; a fill: what it covers of the top's pieces  #V1
    BNE RowFillPat          ; goes (C set: the rectangle fill)  #V1
    LDA $0103,X  ; #V1
    CMP #<TOP_RETRECT  ; #V1
    BEQ RowFillRect  ; #V1
RowFillPat:  ; #V1
    CLC  ; #V1
    BCC RowFillGo  ; #V1
RowFillRect:  ; #V1
    SEC  ; #V1
RowFillGo:  ; #V1
    LDA G_L2DA1  ; #V1
    JSR TopEraseF  ; #V1
RowCutCount:  ; #V1
    LDA #FB_TOP  ; #V1
    SEC  ; #V1
    SBC G_L2DA1             ; the rows above the cut  #V1
    CMP G_Z0D  ; #V1
    BCS RowOff              ; all of them: nothing in the buffer  #V1
    STA S_CUTK  ; #V1
    LDA G_Z0D  ; #V1
    SEC  ; #V1
    SBC S_CUTK  ; #V1
    STA G_Z0D  ; #V1
    TSX  ; #V1
    LDA $0104,X  ; #V1
    SEC  ; #V1
    SBC #>G_L2800  ; #V1
    CMP #E2_BPAGES  ; #V1
    BCS RowCutDone  ; #V1
RowCutSrc:  ; #V1
    LDA G_Z03  ; #V1
    CLC  ; #V1
    ADC G_Z1F  ; #V1
    STA G_Z03  ; #V1
    BCC RowCutNext  ; #V1
    INC G_Z04  ; #V1
RowCutNext:  ; #V1
    DEC S_CUTK  ; #V1
    BNE RowCutSrc  ; #V1
RowCutDone:  ; #V1
    LDA #FB_TOP  ; #V1
RowBelow:  ; #V1
    STA G_L2DA1             ; the multiplier's input, as the original  #V1
    LDA #ST_ROW  ; #V1
    SEC  ; #V1
    SBC G_L2DA1             ; rows from here to the status rows  #V1
    CMP G_Z0D  ; #V1
    BCS RowFits  ; #V1
    STA G_Z0D               ; would run into them: stop there  #V1
RowFits:  ; #V1
    LDA G_L2DA1             ; the row  #V1
    JSR J_ROWADDR           ; its first byte in the buffer $07 names  #V1
    PLA                     ; not back into $2D46 (its buffer base is in  #V1
    PLA                     ; already): to its caller  #V1
    RTS  ; #V1
RowOff:  ; #V1
    PLA                     ; not back into $2D46: to its caller, with  #V1
    PLA                     ; the scratch row as the address  #V1
    LDA #$01  ; #V1
    STA G_Z0D  ; #V1
    LDA #<CLIPROW  ; #V1
    STA G_Z14  ; #V1
    LDA #>CLIPROW  ; #V1
    STA G_Z15  ; #V1
    RTS  ; #V1

;;; FAR (BlRom) -- the blitters' set-up and inner loops (layout7800's  #V1
;;; $289B-$2B19 replacements: their module is in ROM)  #V1
; the shift routine (by the shift $10: the module's tables $298D/$2991) and  #V1
; the mode ($0F: negative AND, 0 ORA, positive a store) for the loops; X the  #V1
; shift on the way out, as the set-up left it  #V1
BlSetup:  ; #V1
    LDX G_Z10  ; #V1
    LDA G_L298D,X  ; #V1
    STA BL_SHV  ; #V1
    LDA G_L2991,X  ; #V1
    STA BL_SHV+1  ; #V1
    LDA G_Z0F  ; #V1
    BMI BlSetup1            ; ($80: AND)  #V1
    BEQ BlSetup1            ; ($00: ORA)  #V1
    LDA #$40                ; (a store)  #V1
BlSetup1:  ; #V1
    STA BL_MODE  ; #V1
    RTS  ; #V1
BlSh:  ; #V1
    JMP (BL_SHV)  ; #V1
;;; FAR (BlRomN) -- (the normal blitter's loops: a piece of their own)  #V1
; the normal blitter's bytes across ($291A-$292D): the source byte shifted,  #V1
; the carry from the last, combined with the screen's by the mode  #V1
BlLoopN:  ; #V1
    BIT BL_MODE  ; #V1
    BMI BlLnA  ; #V1
    BVS BlLnS  ; #V1
BlLnO:  ; #V1
    LDA (G_Z03),Y  ; #V1
    JSR BlSh  ; #V1
    EOR G_Z19  ; #V1
    LDX G_Z08  ; #V1
    STX G_Z19  ; #V1
    ORA (G_Z14),Y  ; #V1
    STA (G_Z14),Y  ; #V1
    INY  ; #V1
    CPY G_Z0E  ; #V1
    BNE BlLnO  ; #V1
    JMP G_L292E  ; #V1
BlLnA:  ; #V1
    LDA (G_Z03),Y  ; #V1
    JSR BlSh  ; #V1
    EOR G_Z19  ; #V1
    LDX G_Z08  ; #V1
    STX G_Z19  ; #V1
    AND (G_Z14),Y  ; #V1
    STA (G_Z14),Y  ; #V1
    INY  ; #V1
    CPY G_Z0E  ; #V1
    BNE BlLnA  ; #V1
    JMP G_L292E  ; #V1
BlLnS:  ; #V1
    LDA (G_Z03),Y  ; #V1
    JSR BlSh  ; #V1
    EOR G_Z19  ; #V1
    LDX G_Z08  ; #V1
    STX G_Z19  ; #V1
    STA (G_Z14),Y  ; #V1
    INY  ; #V1
    CPY G_Z0E  ; #V1
    BNE BlLnS  ; #V1
    JMP G_L292E  ; #V1
;;; FAR (BlRomM) -- (the mirrored blitter's loop: a piece of its own)  #V1
; the mirrored blitter's ($2AFA-$2B18): the source from G_Z0A up, the screen  #V1
; from G_Z0B down, each byte mirrored (FT_MIR), combined by the mode (one  #V1
; loop testing it a byte: the fixed bank's room; the normal blitter, the  #V1
; common one, has a loop a mode)  #V1
BlLoopM:  ; #V1
    LDY G_Z0A  ; #V1
    LDA (G_Z03),Y  ; #V1
    JSR BlSh  ; #V1
    EOR G_Z19  ; #V1
    LDX G_Z08  ; #V1
    STX G_Z19  ; #V1
    TAX  ; #V1
    LDA FT_MIR,X  ; #V1
    INY  ; #V1
    STY G_Z0A  ; #V1
    LDY G_Z0B  ; #V1
    BIT BL_MODE  ; #V1
    BMI BlLmA  ; #V1
    BVS BlLmS  ; #V1
    ORA (G_Z14),Y  ; #V1
    BVC BlLmS               ; (V clear: always)  #V1
BlLmA:  ; #V1
    AND (G_Z14),Y  ; #V1
BlLmS:  ; #V1
    STA (G_Z14),Y  ; #V1
    DEY  ; #V1
    STY G_Z0B  ; #V1
    BNE BlLoopM  ; #V1
    JMP G_L2B19  ; #V1

;;; FARLOAD (L1Load) -- (the scenes' object sets at a load: in the top bank,
;;; through L1Call: the fixed bank's room)
; (level 2 too, FINDINGS "Level 2 as tiles": a tiles set; L1G_TS its tiles'
; first piece, L1_RW its rooms' world)
; level 1 without the blitter (FINDINGS "Level 1 without the blitter: the
; data and the plan"), and levels 3 and 4 ("Levels 2-4 without the
; blitter"): at a scene's load, on (S_L1) in a scene with an object set
; (L1L_SET: level 1's in scenes 1 and 6): its windows made (L1Gen, bank
; L1_HOME, the set's shapes), its RAM (the fast fill's) cleared, each
; buffer's view unknown; then the set (L1_SET), its first zone (L1_ZB), its
; bottom zones' first (L1_ZBT) and flags (L1_SF: bit 7 the canvas, 6 tiles)
L1Load:
    LDA #$00
    STA S_L1
    STA L1_SF               ; (no set: none of its flags either)
    LDX G_ZD0               ; (S_BLPC: the scene's lists' pieces, L1L_BLPC)
    LDA L1L_BLPC,X
    STA S_BLPC
    LDA L1L_SET,X
    BMI L1LoadNo
    PHA
    STA L1G_SET
    TAX
    LDA L1L_SF,X
    STA L1G_SF
    LDA L1L_TS,X            ; (its tiles' pieces, L1TLoad's) #V1
    STA L1G_TS              ; #V1
    LDA L1L_KB,X            ; (its shapes)
    STA L1G_S
    LDA L1L_KE,X
    STA L1G_KE
    INC S_L1
    LDA #<L1Gen             ; #V1
    LDX #>L1Gen             ; #V1
    LDY #L1_GEN             ; #V1
    JSR L1CallU             ; #V1
    JSR L1Init              ; (V2: the windows in MARIA's ROM: only L1Gen's end) #V2
    PLA                     ; (after L1Gen, which clears the variables)
    TAX
    STX L1_SET
    LDA L1L_KB,X            ; (its shapes: the first, the end, its block of
    STA L1_KB               ; the capture's index)
    LDA L1L_KE,X
    STA L1_KE
    TXA
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA L1_KF
    LDA L1L_ZB,X
    STA L1_ZB
    LDA L1L_ZBT,X
    STA L1_ZBT
    LDA L1L_RW,X            ; (its rooms' world: the rooms' floor marks it)
    STA L1_RW
    LDA L1L_SF,X
    STA L1_SF
    JSR AkPre               ; (Akuma's or the hawk's poses cut: akpose7800) #V1
L1LoadNo:
    LDA #FT_COLS            ; (the slice pages' columns for copied parts: all,
    LDX S_L1                ; or below AK_COLS with poses pre-cut above it)
    BEQ L1LoadC
    LDX L1_SET
    LDY AKP_PH,X
    BEQ L1LoadC
    LDA #AK_COLS
L1LoadC:
    STA AKP_COLS
    RTS
; (V2) L1Gen's end: the set's variables cleared (two halves), each buffer's #V2
; view unknown, no world: its windows, characters and poses are in its #V2
; scene's MARIA page (FINDINGS "The ROM by scene: step 3") #V2
L1Init:                     ; #V2
    LDA #$00                ; #V2
    TAX                     ; #V2
L1InitC:                    ; #V2
    STA L1VARS,X            ; #V2
    STA L1VARB,X            ; #V2
    INX                     ; #V2
    CPX #L1VARS_N           ; #V2
    BNE L1InitC             ; #V2
    LDA #$FF                ; #V2
    STA L1_V+1              ; #V2
    STA L1_V+3              ; #V2
    STA L1_WLD              ; #V2
    STA L1_WLD+1            ; #V2
    RTS                     ; #V2
L1L_BLPC:                   ; (scene 0's $20, level 1's $00, levels 2-4's $10)
    .byte $20, $00, $10, $10, $10, $FF, $00

;;; FAR (L1FillCv)  #V1
; (the canvas: the instances the fill covers out, then the fill as the  #V1
; game's; a fighter-box erase drawn as the game's, nothing out)  #V1
L1FillCv:  ; #V1
    STA L1F_PAT  ; #V1
    LDA S_NOFILL  ; #V1
    BNE L1FillCv1  ; #V1
    STX L1_FX  ; #V1
    STY L1_FY  ; #V1
    LDA #<L1Fill  ; #V1
    LDX #>L1Fill  ; #V1
    LDY #L1_CAP  ; #V1
    JSR L1CallK  ; #V1
    LDX L1_FX  ; #V1
    LDY L1_FY  ; #V1
L1FillCv1:  ; #V1
    JMP G_L2DA4  ; #V1

;;; FAR (CopyFill)
; the fast fill's code into cart RAM, with the images' bank in (the loader,
; after the engine's second part)

;;; FARL1 (L1Rec) -- level 1's shapes' records (bank L1_HOME)
; shape A's record at ZP_P2 (Y kept)
L1Rec:
    STY L1_T4
    ASL A
    TAY
    BCS L1RecH              ; (shapes 128 on: the index's second page)
    LDA L1S_R,Y
    STA ZP_P2
    LDA L1S_R+1,Y
    STA ZP_P2+1
    LDY L1_T4
    RTS
L1RecH:
    LDA L1S_R+256,Y
    STA ZP_P2
    LDA L1S_R+257,Y
    STA ZP_P2+1
    LDY L1_T4
    RTS

;;; FARL2 (L1Look) -- level 1's draws captured (bank L1_CAP, through L1Call):
;;; the shapes' lookup table (L1K_*: image, row, flags, width, past the last
;;; row), and the capture's code
; the shape of image L1_SRC at row L1_ROW, its flags' bits 7, 6 and 3
; L1_FLM (mirrored, a column, a strip): C set, L1_S and X it. The shapes
; are in their images' low bytes' order: from the first with L1_SRC's
; (L1K_F32: the set's block, L1_KF, by the low byte / 8, the first at or
; past 8 x it) past the lower ones, while theirs is it, to the set's end
L1Find:
    LDA L1_SRC
    LSR A
    LSR A
    LSR A
    ORA L1_KF
    TAY
    LDX L1K_F32,Y
L1Find1:
    CPX L1_KE
    BCS L1FindNo
    LDA L1K_SLO,X
    CMP L1_SRC
    BCC L1FindN
    BNE L1FindNo
    LDA L1K_SHI,X
    CMP L1_SRC+1
    BNE L1FindN
    LDA L1K_ROW,X
    CMP L1_ROW
    BNE L1FindN
    LDA L1K_FL,X
    AND #$C8
    CMP L1_FLM
    BNE L1FindN
    STX L1_S
    SEC
    RTS
L1FindN:
    INX
    BNE L1Find1
L1FindNo:
    CLC
    RTS
; the place of shape L1_S for column $05 (right-aligned if L1_T1: less its
; width less 1) and shift $10: 4 x column + shift / 2, its low byte (an
; object's horizontal position) in L1_X, C clear; C set, off the screen (a
; column 40 on, or before -14: level 3's right door frame at x 272 while the
; stairs show, its low byte 16)
L1Place:
    LDX L1_S
    LDA L1K_W,X             ; (bit 7: in front)
    AND #$1F
    STA L1_W
    LDA G_Z05
    LDY L1_T1
    BEQ L1Place1
    SEC
    SBC L1_W
    CLC
    ADC #$01
L1Place1:
    CMP #40
    BCC L1Place2
    CMP #$F2
    BCS L1Place2
    SEC                     ; (off the screen)
    RTS
L1Place2:
    ASL A
    ASL A
    STA L1_T0
    LDA G_Z10
    LSR A
    CLC
    ADC L1_T0
    STA L1_X
    CLC
    RTS
; the image and row of the draw: $03/$04, $06 - $23
L1Src:
    LDA G_Z03
    STA L1_SRC
    LDA G_Z04
    STA L1_SRC+1
    LDA G_Z06
    SEC
    SBC #$23
    STA L1_ROW
    RTS

; the buffer the game draws ($07: $20 B): L1_B 0 or 1
L1Buf:
    LDA #$00
    LDX G_Z07
    CPX #$20
    BNE L1Buf1
    LDA #$01
L1Buf1:
    STA L1_B
    RTS
; the buffer's instances: X its first's offset, L1_E past its last
L1Base:
    LDX #$00
    LDY L1_B
    BEQ L1Base1
    LDX #L1_NB
L1Base1:
    TXA
    CLC
    ADC L1_N,Y
    STA L1_E
    RTS
; instance L1_S at L1_X into the buffer's list, drawn in this picture: at
; its end (the list follows the game's latest drawing order: one already
; there moves to the end, unless it is there)
L1Add:
    LDA L1_S                ; (an instance keeps the shape less its set's
    SEC                     ; first: 127 a set)
    SBC L1_KB
    STA L1_T3
    JSR L1Base
L1Add1:
    CPX L1_E
    BCS L1AddNew
    LDA L1_SHA,X
    AND #$7F
    CMP L1_T3
    BNE L1AddN
    LDA L1_XA,X
    CMP L1_X
    BNE L1AddN
    INX                     ; (already the last: marked only)
    CPX L1_E
    BCC L1AddMv
    DEX
    LDA L1_SHA,X
    ORA #$80
    STA L1_SHA,X
    RTS
L1AddMv:
    DEX
    JSR L1Del               ; (out, then in again at the end)
    JSR L1Base
    JMP L1AddNew
L1AddN:
    INX
    BNE L1Add1
L1AddNew:
    LDX L1_E
L1AddNew0:
    LDY L1_B
    LDA L1_N,Y
    CMP #L1_NMAX
    BCS L1AddFull
    LDA L1_T3
    ORA #$80
    STA L1_SHA,X
    LDA L1_X
    STA L1_XA,X
    LDA L1_N,Y
    CLC
    ADC #$01
    STA L1_N,Y
    LDA #$01
    STA L1_DIRTY,Y
L1AddFull:
    RTS
; the instance at X out, the ones after it moved down (X kept: the next one)
L1Del:
    STX L1_T0
L1Del1:
    INX
    CPX L1_E
    BCS L1Del2
    LDA L1_SHA,X
    STA L1_SHA-1,X
    LDA L1_XA,X
    STA L1_XA-1,X
    JMP L1Del1
L1Del2:
    DEC L1_E
    LDY L1_B
    LDA L1_N,Y
    SEC
    SBC #$01
    STA L1_N,Y
    LDA #$01
    STA L1_DIRTY,Y
    LDX L1_T0
    RTS

;;; FARL2 (L1Draw)
; a blit (BlitBank: L1B_KIND 0 normal, 1 right-aligned, 2 mirrored, 3 both):
; its shape at its place (the rails: the buffer's background, under every
; instance); one not in the inventory is dropped
L1Blit:
    JSR L1Buf
    JSR L1Src
    JSR PcCap               ; (V2: level 2's portcullis, C set: taken, #V2
    BCC L1BlitP             ; not a shape's) #V2
    CLC                     ; #V2
    RTS                     ; #V2
L1BlitP:                    ; #V2
    LDA #$00                ; (L1_T3: $40, found as a column)
    STA L1_T3
    LDX #L1MK_N-1           ; the set's world markers (L1MK_*: image, row and
L1BlitK:                    ; kind, $FF any): level 1's rails ($AA11: every
    LDA L1MK_SET,X          ; view of the level draws them), its world
    CMP L1_SET              ; (L1Mark, W $80) and nothing else; level 2's
    BNE L1BlitKN            ; stakes, its cell's wall (bit 6: out of a room
    LDA L1MK_SLO,X          ; only), its bed: W's world, the draw captured
    CMP L1_SRC              ; as any
    BNE L1BlitKN
    LDA L1MK_SHI,X
    CMP L1_SRC+1
    BNE L1BlitKN
    LDA L1MK_ROW,X
    CMP #$FF
    BEQ L1BlitK1
    CMP L1_ROW
    BNE L1BlitKN
L1BlitK1:
    LDA L1MK_KD,X
    CMP #$FF
    BEQ L1BlitK2
    CMP L1B_KIND
    BNE L1BlitKN
L1BlitK2:
    LDA L1MK_W,X
    BPL L1BlitK3
    CMP #$C0                ; ($C0: its column shape's, level 2's portcullis
    BCC L1BlitKM            ; drop; else the rails)
    LDA #$40
    STA L1_T3
    BNE L1BlitF
L1BlitKM:
    JMP L1Mark
L1BlitK3:
    STA L1_T0
    LDY L1_B
    AND #$40
    BEQ L1BlitK4
    LDX L1_WLD,Y
    BMI L1BlitK4            ; (none: out of a room)
    LDA L1T_FL,X
    BMI L1BlitF             ; (in a room: it stays)
L1BlitK4:
    LDA L1_T0
    AND #$3F
    JSR L1MarkW
    JMP L1BlitF
L1BlitKN:
    DEX
    BPL L1BlitK
L1BlitF:
    LDA L1B_KIND
    AND #$02
    BEQ L1Blit1
    LDA #$80
L1Blit1:
    ORA L1_T3
    STA L1_FLM
    JSR L1Find
    BCC L1BlitRts
    LDA L1K_W,X             ; (a shape in front of the fighters (bit 7): only
    BPL L1BlitS             ; drawn after them, FT_SEEN, else its world's tile
    LDY L1_B                ; shows it: level 3's left post under the stairs)
    LDA FT_SEEN,Y
    BEQ L1BlitRts
L1BlitS:
    LDA L1B_KIND
    AND #$01
    STA L1_T1
    JSR L1Place
    BCS L1BlitRts           ; (off the screen)
L1BlitA:
    JSR L1Add               ; (C set: an instance; clear, none: L1BlitRts)
    SEC
    RTS
L1BlitRts:
    CLC
    RTS
; the buffer's world (L1_WLD) the level's: 0 structure 0 before the cutscene,
; 1 after it (the game's $30), 2 structure 1 ($4C); L1MarkW: A's (3: the cutscene's
; room)
L1Mark:
    LDA G_Z4C
    BEQ L1Mark0
    LDA #$02
    BNE L1Mark1
L1Mark0:
    LDA G_Z30               ; (the game's $30, console $00E9: 1 once past the cutscene)
    BEQ L1Mark1
    LDA #$01
L1Mark1:
    LDY L1_B
L1MarkW:
    CMP L1_WLD,Y
    BEQ L1MarkR
    STA L1_WLD,Y
    LDA #$01
    STA L1_DIRTY,Y
L1MarkR:
    RTS

; a column (ColA, Col68: L1C_MIR $80 if mirrored, its pieces then
; right-aligned): its shape (image, first row) at its place; the caller's
; first piece (the same image at that row and place) is the column's
L1Col:
    JSR L1Buf
    JSR L1Src
    LDA L1C_MIR
    ORA #$40
    STA L1_FLM
    JSR L1Find
    BCC L1ColRts
    LDA #$00
    BIT L1C_MIR
    BPL L1Col0
    LDA #$01
L1Col0:
    STA L1_T1
    JSR L1Place
    BCS L1ColRts            ; (off the screen)
    LDA L1_S
    STA L1_T2
    JSR L1Base
L1Col1:
    CPX L1_E
    BCS L1Col3
    LDA L1_XA,X
    CMP L1_X
    BNE L1Col2
    LDA L1_SHA,X
    AND #$7F
    CLC
    ADC L1_KB
    TAY
    LDA L1K_SLO,Y
    CMP L1_SRC
    BNE L1Col2
    LDA L1K_SHI,Y
    CMP L1_SRC+1
    BNE L1Col2
    LDA L1K_ROW,Y
    CMP L1_ROW
    BNE L1Col2
    LDA L1K_FL,Y
    AND #$40
    BNE L1Col2
    JSR L1Del
    JMP L1Col3
L1Col2:
    INX
    BNE L1Col1
L1Col3:
    LDA L1_T2
    STA L1_S
    JMP L1Add
L1ColRts:
    RTS

;;; FARL2 (L1FillC)
; a fill (in place of $2CCD's and $2D03's clip, L1F_PAT 1 the pattern's;
; not a fighter-box erase): the instances it covers any of (rows and
; columns) out, the game drawing again what it wants there; one across the
; whole width over the sky's rows (65-68) or the floor's (118-145) sets the
; buffer's background there: the sky with $AA, the floor with $55 (both a
; pattern's values)
L1Fill:
    LDA S_NOFILL
    BEQ L1Fill0
    RTS  ; #V1
                            ; (V2: a fighter-box erase too, its figures only) #V2
L1Fill0:
    JSR L1Buf
    LDA G_Z05               ; columns $05-$09 (a negative left: 0, unless the
    CMP #40                 ; right is past 40 too)
    BCC L1Fill1
    LDA G_Z09
    CMP #41
    BCC L1Fill0A
    RTS
L1Fill0A:
    LDA #$00
L1Fill1:
    STA L1_C0
    LDA G_Z09
    CMP #41
    BCC L1Fill2
    LDA #40
L1Fill2:
    STA L1_C1
    LDA G_Z06               ; rows $06-$08, less $23 (a top above 0: 0)
    SEC
    SBC #$23
    BCS L1Fill3
    LDA #$00
L1Fill3:
    STA L1_R0
    LDA G_Z08
    SEC
    SBC #$23
    BCS L1Fill4
    RTS
L1Fill4:
    STA L1_R1
    BIT L1_SF               ; (level 1's tiles only)
    BVC L1FillPx
    LDA L1F_PAT             ; a room's floor (a pattern over rows 118-145):
    BEQ L1FillPx            ; the buffer's world the set's room (L1_RW)
    LDA L1_R0
    CMP #118
    BNE L1FillPx
    LDA L1_R1
    CMP #145
    BNE L1FillPx
    LDY L1_B
    LDA L1_RW
    JSR L1MarkW
L1FillPx:
    ASL L1_C0               ; (in pixels)
    ASL L1_C0
    ASL L1_C1
    ASL L1_C1
    JSR L1Base
L1FillI:
    CPX L1_E
    BCC L1FillI1
    RTS
L1FillI1:
    LDA L1_SHA,X            ; (an object whose middle the fill covers: its
    AND #$7F                ; middle row and middle column in the fill's)
    CLC
    ADC L1_KB
    TAY
    LDA S_NOFILL            ; (V2: a fighter-box erase takes out only the #V2
    BEQ L1FillI2            ; rooms' figures, L1K_W bit 5: its black covers #V2
    LDA L1K_W,Y             ; them on the original; the princess's leg #V2
    AND #$20                ; stayed: FINDINGS "The hardware test") #V2
    BEQ L1FillN             ; #V2
L1FillI2:                   ; #V2
    LDA L1K_ROW,Y           ; its middle row: (row + past its last) / 2
    CLC
    ADC L1K_ROWE,Y
    ROR A
    CMP L1_R0
    BCC L1FillN
    CMP L1_R1
    BCS L1FillN
    LDA L1K_W,Y             ; its middle column: its place + 2 x its width
    AND #$1F                ; (200 on: less 256)
    ASL A
    CLC
    ADC L1_XA,X
    BCS L1FillM             ; (past 255: from left of 0, now on the screen)
    LDY L1_XA,X
    CPY #200
    BCC L1FillM
    LDA L1_C0               ; (still left of 0: covered by a fill from 0)
    BNE L1FillN
    BEQ L1FillY
L1FillM:
    CMP L1_C0
    BCC L1FillN
    CMP L1_C1
    BCS L1FillN  ; #V1
    BCC L1FillY             ; (V2: its middle past the right edge: covered #V2
    CMP #160                ; by a fill to the edge, as left of 0 by one #V2
    BCC L1FillN             ; from 0: the hawk flown out left its edge on #V2
    LDA L1_C1               ; screen; FINDINGS "The hardware test") #V2
    CMP #160                ; #V2
    BNE L1FillN             ; #V2
L1FillY:
    JSR L1Del
    JMP L1FillI
L1FillN:
    INX
    BNE L1FillI
    RTS

;;; FARL2 (L1BufC)
; the game's full clear of the buffer it draws: none of its instances
L1Clear:
    JSR L1Buf
    LDY L1_B
    LDA #$00
    STA L1_N,Y
    LDA #$FF                ; (no world till its marker: nothing shown)
    STA L1_WLD,Y
    LDA #$01
    STA L1_DIRTY,Y
    RTS
; the game's buffer copy ($07 $40: B into A, else A into B): the
; instances, view and backgrounds as the other's
L1Copy:
    LDX #$00                ; (into A)
    LDY #L1_NB
    LDA G_Z07
    CMP #$40
    BEQ L1Copy1
    LDX #L1_NB          ; (into B)
    LDY #$00
L1Copy1:
    STX L1_T0
    LDA #L1_NMAX
    STA L1_T2
L1Copy2:
    LDA L1_SHA,Y
    STA L1_SHA,X
    LDA L1_XA,Y
    STA L1_XA,X
    INX
    INY
    DEC L1_T2
    BNE L1Copy2
    LDX #$00                ; the counts and the rest, by buffer
    LDY #$01
    LDA L1_T0
    BEQ L1Copy3
    LDX #$01
    LDY #$00
L1Copy3:
    LDA L1_N,Y
    STA L1_N,X
    LDA L1_WLD,Y
    STA L1_WLD,X
    LDA #$01
    STA L1_DIRTY,X
    TXA
    ASL A
    TAX
    TYA
    ASL A
    TAY
    LDA L1_V,Y
    STA L1_V,X
    LDA L1_V+1,Y
    STA L1_V+1,X
    LDA L1_VP,Y             ; (V2: its half pixel too, or the copy's next #V2
    STA L1_VP,X             ; flip took it for a view change and dropped what #V2
                            ; it was given: the attract's posts every other #V2
                            ; picture, FINDINGS "The hardware test") #V2
    RTS

;;; FARL2 (L1FlipC)
; the picture done (TopFlip; $07 the buffer drawn): its view, V = 4 x $52
; + $50 / 2; when that changed, the instances not drawn in this picture out
; (the game draws again all it shows when the view moves); the marks
; cleared; if anything changed its lists are wanted again (FT_DIRTY, for
; FtEmit) and its bottom zones' lists written
L1Flip:
    JSR L1Buf
    LDY L1_B                ; level 1's worlds follow the game's structure and
    LDX L1_WLD,Y            ; stretch ($4C, $30: L1Mark) though no rails are
    BMI L1FlipW             ; drawn (L1T_FL bit 6); the others and none stay
    LDA L1T_FL,X
    AND #$40
    BEQ L1FlipW
    JSR L1Mark
L1FlipW:
    BIT L1_SF               ; (the tiles' characters: the buffer's world's
    BVC L1FlipW1            ; CHBASE, L1T_CB)
    LDY L1_B
    LDX L1_WLD,Y
    BMI L1FlipW1
    LDA L1T_CB,X
    STA M_CHBASE
L1FlipW1:
    LDA G_Z52
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    STA L1_T1
    LDA G_Z52
    ASL A
    ASL A
    STA L1_T0
    LDA G_Z50
    LSR A
    CLC
    ADC L1_T0
    STA L1_T0
    LDA L1_T1
    ADC #$00
    STA L1_T1
    LDA L1_SF               ; (level 2's view wraps: 0-63 for 1,024 on)
    AND #$20
    BEQ L1FlipV0
    LDA L1_T1
    BNE L1FlipV0
    LDA L1_T0
    CMP #64
    BCS L1FlipV0
    LDA #$04
    STA L1_T1
L1FlipV0:
    LDA L1_B
    ASL A
    TAY
    LDA L1_T0
    CMP L1_V,Y
    BNE L1FlipV
    LDA L1_T1
    CMP L1_V+1,Y
    BEQ L1FlipM  ; #V1
    BEQ L1FlipP             ; (V2) #V2
L1FlipV:
    LDA L1_T0
    STA L1_V,Y
    LDA L1_T1
    STA L1_V+1,Y
    LDA G_Z50               ; (V2: its half pixel too) #V2
    AND #$01                ; #V2
    STA L1_VP,Y             ; #V2
    JSR FtViewGone          ; (its fighters from an earlier picture too)
    LDY L1_B                ; (and its bottom zones written again: their #V2
    LDA #$01                ; tiles move with the view too, level 3's #V2
    STA L1_DIRTY,Y          ; stairs' post: FINDINGS "The stairs' post") #V2
    JSR L1Base
    JMP L1FlipV1  ; #V2
; (V2) the same view, but $50's half pixel moved: V halves $50, and the game's #V2
; draws moved a pixel (the posts at 105, then 104, at V $6C): a view change #V2
; too, its instances not drawn out, or a buffer kept the posts twice, a pixel #V2
; apart, every other picture: FINDINGS "Recording 02" #V2
L1FlipP:  ; #V2
    LDA G_Z50  ; #V2
    AND #$01  ; #V2
    CMP L1_VP,Y  ; #V2
    BNE L1FlipV  ; #V2
    JMP L1FlipM  ; #V2
L1FlipV1:
    CPX L1_E
    BCS L1FlipM
    LDA L1_SHA,X
    BMI L1FlipV2
    JSR L1Del
    JMP L1FlipV1
L1FlipV2:
    INX
    BNE L1FlipV1
L1FlipM:
    JSR L1Base
L1FlipM1:
    CPX L1_E
    BCS L1FlipD
    LDA L1_SHA,X
    AND #$7F
    STA L1_SHA,X
    INX
    BNE L1FlipM1
L1FlipD:
    LDY L1_B
    LDA L1_DIRTY,Y
    BEQ L1FlipRts
    TYA
    TAX
    LDA #$01
    STA FT_DIRTY,X
    JMP L1Bottom
L1FlipRts:
    RTS


;;; FARL1 (L1Emit) -- level 1's zone lists' objects: a zone's (L1_K: 0-12;
;;; its parts: L1Q_ZP0, L1Q_ZNP), in the pass L1_FP (0 all; 1 the tiles and the
;;; instances behind the fighters; 2 those in front of them, L1K_W bit 7), counted (L1_WR 0:
;;; L1_ZN4 bytes) or written at ZP_P1 (L1_WR 1; Y, L1_WY the bytes), at most
;;; L1_WMAX bytes: the backgrounds' strips (the sky's, the floor's, the
;;; rails': from 0 and 80) when the buffer has them, then its instances in
;;; their order; each
;;; part with a window an object [C, palette | width, T - lines + 1, place]
; ZP_P2 kept
L1Zone:
    LDA ZP_P2
    PHA
    LDA ZP_P2+1
    PHA
    LDA #$00
    STA L1_ZN4
    STA L1_WY
    STA L1_LW               ; (V2: L1PartW's last entry: none) #V2
    LDA L1_FP               ; (the front pass: no tiles)
    CMP #$02
    BEQ L1ZoneI
    BIT L1_SF               ; its world's tiles (a set with tiles)
    BVC L1ZoneI
    JSR L1Tiles
L1ZoneI:
    JSR L1BaseZ
    STX L1_I
L1ZoneI1:
    LDX L1_I
L1ZoneI2:                   ; (X the instance: one not in this zone passed
    CPX L1_E                ; over in X alone; FINDINGS "Speed: the first
    BCS L1ZoneDone          ; savings")
    LDA L1_SHA,X
    AND #$7F
    CLC
    ADC L1_KB
    TAY
    LDA L1_K                ; (in this zone: its zones L1S_ZA to L1S_ZE)
    CMP L1S_ZA,Y
    BCC L1ZoneN  ; #V1
    BCC L1ZoneX  ; #V2
    CMP L1S_ZE,Y
    BCS L1ZoneN  ; #V1
    BCS L1ZoneX  ; #V2
    STX L1_I  ; #V2
    LDA L1_FP               ; (and in this pass, or all: L1K_W bit 7, in
    BEQ L1ZoneO             ; front, pass 2; else 1)
    LDA L1K_W,Y
    ROL A
    LDA #$00
    ROL A
    CLC
    ADC #$01
    CMP L1_FP
    BEQ L1ZoneO
    STA L1_FS               ; (another pass's: pass 1 notes one in front, L1_FS) #V1
    CMP #$02                ; (V2: pass 1 counts the zone's ones in front, #V2
    BNE L1ZoneN             ; L1_FS; pass 2 stops at the last: FINDINGS #V2
    LDA L1K_W,Y             ; "The torii in front"; those in the tiles #V2
    AND #$40                ; too only over a fighter: none, no pass 2) #V2
    BEQ L1ZoneFC            ; #V2
    LDA L1_XA,X             ; #V2
    STA L1_X                ; #V2
    JSR L1FrHit             ; #V2
    BCC L1ZoneN             ; #V2
L1ZoneFC:                   ; #V2
    INC L1_FS               ; #V2
    JMP L1ZoneN
L1ZoneO:
    LDA L1_XA,X
    STA L1_X
    LDA L1K_W,Y             ; (in front and in the world's tiles too, #V2
    AND #$40                ; bit 6: drawn only over a fighter, L1FrHit) #V2
    BEQ L1ZoneO1            ; #V2
    JSR L1FrHit  ; #V2
    BCC L1ZoneOS  ; #V2
L1ZoneO1:  ; #V2
    TYA
    JSR L1Obj
L1ZoneOS:  ; #V2
    LDA L1_FP  ; #V2
    CMP #$02  ; #V2
    BNE L1ZoneN  ; #V2
    DEC L1_FS  ; #V2
    BNE L1ZoneN  ; #V2
    JMP L1ZoneDone  ; #V2
L1ZoneN:
    INC L1_I
    JMP L1ZoneI1
L1ZoneX:  ; #V2
    INX  ; #V2
    JMP L1ZoneI2  ; #V2
L1ZoneDone:
    PLA
    STA ZP_P2+1
    PLA
    STA ZP_P2
    LDY L1_WY
    RTS
; (V2) whether the front instance at L1_X (shape Y) meets a fighter of #V2
; buffer L1_B (records 2B, 2B + 1: FR_V shown, FR_C0-FR_C1 its columns): #V2
; C set if so. Columns + 64, so those left of the screen stay positive. #V2
; Y kept #V2
L1FrHit:  ; #V2
    LDA L1_X                ; its first column: x / 4, less 64 left of the #V2
    LSR A                   ; screen (x 160 on) #V2
    LSR A  ; #V2
    CMP #40  ; #V2
    BCS L1FrH1  ; #V2
    ADC #64  ; #V2
L1FrH1:  ; #V2
    STA L1FH_A  ; #V2
    LDA L1K_W,Y  ; #V2
    AND #$1F  ; #V2
    SEC                     ; (+ 1: its shift) #V2
    ADC L1FH_A  ; #V2
    STA L1FH_B  ; #V2
    LDA L1_B  ; #V2
    ASL A  ; #V2
    TAX  ; #V2
    JSR L1FrH2  ; #V2
    BCS L1FrH9  ; #V2
    INX  ; #V2
L1FrH2:  ; #V2
    LDA FR_V,X  ; #V2
    BEQ L1FrHN  ; #V2
    LDA FR_C0,X  ; #V2
    CMP FR_C1,X  ; #V2
    BCS L1FrHN              ; (no box) #V2
    LDA FR_C1,X             ; its past-last column past our first, #V2
    CLC  ; #V2
    ADC #64  ; #V2
    CMP L1FH_A  ; #V2
    BEQ L1FrHN  ; #V2
    BCC L1FrHN  ; #V2
    LDA FR_C0,X             ; and its first before our past-last #V2
    CLC  ; #V2
    ADC #64  ; #V2
    CMP L1FH_B  ; #V2
    BCS L1FrHN  ; #V2
    SEC  ; #V2
    RTS  ; #V2
L1FrHN:  ; #V2
    CLC  ; #V2
L1FrH9:  ; #V2
    RTS  ; #V2
;;; FARL1 (L1BaseZ)
; (L1Base's twin, in this bank) the buffer's instances: X its first's
; offset, L1_E past its last
L1BaseZ:
    LDX #$00
    LDY L1_B
    BEQ L1BaseZ1
    LDX #L1_NB
L1BaseZ1:
    TXA
    CLC
    ADC L1_N,Y
    STA L1_E
    RTS
;;; FARL1 (L1TileC)
; the zone's background: its world's map row (L1T_LO/HI by world x 13 +
; zone) as one indirect header: the view's 21 two-byte characters (168
; pixels) from its column, hpos its fine part (0 to -7), from K - V (the
; room's, world 3: K; L1T_KL/KH: each world's origin), trimmed to the row's
; columns that aren't blank (L1T_FB to L1T_LB: MARIA's time), none if the
; view's all are, or for a buffer with no world (L1_WLD $FF). 5 bytes
; (L1_ZN4), written if L1_WR, room permitting
L1Tiles:
    LDY L1_B
    LDA L1_WLD,Y
    BPL L1Tiles0
    JMP L1TilesZ
L1Tiles0:
    TAX                     ; its palette (L1_TP): 1 above the band's colour
    LDA L1_K                ; DLI's split, L1_PAL from the world's zone L1T_PZ
    CMP L1T_PZ,X            ; on (ColTail; level 2's none)
    LDA #$20
    BCC L1Tiles0P
    LDA #L1_PALB
L1Tiles0P:
    STA L1_TP
    STX L1_T0               ; the world's rows from L1T_WB (less its set's
    LDA L1T_WB,X            ; first zone) + the zone, through L1T_IX (the
    CLC                     ; distinct rows)
    ADC L1_K
    TAX
    LDA L1T_IX,X
    TAX
    STX L1_I                ; (the row)
    LDA L1T_LO,X
    STA L1_T2
    LDA L1T_HI,X
    STA L1_T3
    LDX L1_T0
    LDA L1T_KL,X
    STA L1_T1
    LDA L1T_KH,X
    STA L1_T4
    LDA L1T_FL,X            ; (a room: not scrolled)
    BMI L1Tiles1
    TYA
    ASL A
    TAY
    LDA L1_T1               ; K - V
    SEC
    SBC L1_V,Y
    STA L1_T1
    LDA L1_T4
    SBC L1_V+1,Y
    STA L1_T4
L1Tiles1:
    LDA L1_T1               ; its fine part
    AND #$07
    STA L1_T0
    LSR L1_T4               ; its column (c0): / 8
    ROR L1_T1
    LSR L1_T4
    ROR L1_T1
    LSR L1_T4
    ROR L1_T1
    LDX L1_I                ; (the row as stored: its long run of one
    LDA L1_T1               ; character cut to 21 at L1T_CL, L1T_CD shorter:
    CMP L1T_CL,X            ; c0 before it as it is, in its first L1T_CD
    BCC L1TilesS            ; the run's first, past them less L1T_CD)
    SBC L1T_CD,X
    BCC L1TilesS0
    CMP L1T_CL,X
    BCS L1TilesS1
L1TilesS0:
    LDA L1T_CL,X
L1TilesS1:
    STA L1_T1
L1TilesS:
    LDA L1T_FB,X            ; the first column shown: the row's first not
                            ; blank, if later than c0 (L1_T4)
    CMP L1_T1
    BCS L1TilesA
    LDA L1_T1
L1TilesA:
    STA L1_T4
    LDA L1_T1               ; the last: c0 + 20, or the row's last not
    CLC                     ; blank if before (L1_X)
    ADC #20
    CMP L1T_LB,X
    BCC L1TilesB
    LDA L1T_LB,X
L1TilesB:
    CMP L1_T4               ; (none shown: the 160A header alone)
    BCS L1TilesC  ; #V1
    BCC L1TilesNo           ; (V2: the routine in two parts, cut here: split_parts) #V2
    JMP L1TilesC            ; #V2
L1TilesNo:                  ; #V2
    JMP L1TilesZ
L1TilesC:
    SEC                     ; its characters: last - first + 1 (L1_X)
    SBC L1_T4
    STA L1_X
    INC L1_X
    LDA L1_T4               ; its hpos: (first - c0) x 8 - the fine part
    SEC
    SBC L1_T1
    ASL A
    ASL A
    ASL A
    SEC
    SBC L1_T0
    STA L1_T0
    LDA L1_T2               ; its map bytes from the first
    CLC
    ADC L1_T4
    STA L1_T2
    BCC L1Tiles2
    INC L1_T3
L1Tiles2:
    LDA L1_WR
    BEQ L1TilesN
    LDA L1_WY
    CLC
    ADC #$05
    CMP L1_WMAX
    BCC L1TilesW
    BNE L1TilesN
L1TilesW:
    LDY L1_WY
    LDA L1_T2
    STA (ZP_P1),Y
    INY
    LDA #$60                ; (indirect, 160A)
    STA (ZP_P1),Y
    INY
    LDA L1_T3
    STA (ZP_P1),Y
    INY
    LDA #$00                ; (its characters, its palette)
    SEC
    SBC L1_X
    AND #$1F
    ORA L1_TP
    STA (ZP_P1),Y
    INY
    LDA L1_T0
    STA (ZP_P1),Y
    INY
    STY L1_WY
L1TilesN:
    LDA L1_ZN4
    CLC
    ADC #$05
    STA L1_ZN4
L1TilesR:
    RTS
; no tiles: a 160A header all the same (a byte off the screen's right), so
; the list starts in 160A whatever the zone before it ended in
L1TilesZ:
    LDA L1_WR
    BEQ L1TilesN
    LDA L1_WY
    CLC
    ADC #$05
    CMP L1_WMAX
    BCC L1TilesZ1
    BNE L1TilesN
L1TilesZ1:
    LDY L1_WY
    LDA #$00
    STA (ZP_P1),Y
    INY
    LDA #$40
    STA (ZP_P1),Y
    INY
    LDA #FT_PTOP
    STA (ZP_P1),Y
    INY
    LDA #$1F
    STA (ZP_P1),Y
    INY
    LDA #160
    STA (ZP_P1),Y
    INY
    STY L1_WY
    JMP L1TilesN
;;; FARL1 (L1Obj)
; shape A at L1_X: its objects in the zone; then its overlay's (flags bit
; 2: its entries after the shape's own, as many), if it has one
L1Obj:
    TAX                     ; (its flags and width: the capture's arrays, in
    LDA L1K_FL,X            ; this bank; its record: its first part, its
    STA L1_FL               ; entries)
    LDA L1K_W,X             ; (less bit 7, in front)
    AND #$7F  ; #V1
    AND #$1F                ; (V2: and bit 6, in the tiles too) #V2
    STA L1_W
    TXA
    JSR L1Rec
    LDY #$00
    LDA (ZP_P2),Y
    STA L1_P0
    INY
    LDA (ZP_P2),Y
    STA L1_NE
L1ObjP:
    LDX L1_K                ; the zone's parts (L1Q_ZP0 on, L1Q_ZNP of them)
    LDA L1Q_ZNP,X
    STA L1_T1
    LDA L1Q_ZP0,X
L1Obj1:
    PHA
    JSR L1Part
    PLA
    CLC
    ADC #$01
    DEC L1_T1
    BNE L1Obj1
    LDA L1_FL
    AND #$04
    BEQ L1Obj2
    EOR L1_FL               ; (once)
    STA L1_FL
    LDA L1_NE
    ASL A
    CLC
    ADC ZP_P2
    STA ZP_P2
    BCC L1ObjP
    INC ZP_P2+1
    BNE L1ObjP
L1Obj2:
    RTS
;;; FARL1 (L1PartC)
; part A of the shape: its window's object, if it has one
L1Part:
    STA L1_T2
    SEC
    SBC L1_P0
    BCC L1PartRts           ; (before its first)
    CMP L1_NE
    BCS L1PartRts           ; (past its last)
    ASL A
    CLC
    ADC #$02
    TAY
    LDA (ZP_P2),Y           ; T (its page less $40; its palette in bits 6-7)
    BEQ L1PartRts
    STA L1_T3
    INY
    LDA (ZP_P2),Y           ; C
    STA L1_T4
    LDA L1_WR
    BEQ L1PartN
    LDA L1_WY               ; (room for it)
    CLC
    ADC #$04
    CMP L1_WMAX
    BCC L1PartW
    BEQ L1PartW
L1PartRts:
    RTS
L1PartW:
    LDY L1_WY
    LDA L1_T4
    STA (ZP_P1),Y
    INY
    LDX L1_T2
    LDA L1_T3               ; the palette (bits 6-7, << 5)
    AND #$C0
    LSR A
    STA L1_T0
    LDA L1_W
    EOR #$FF
    CLC
    ADC #$01
    AND #$1F
    ORA L1_T0
    STA (ZP_P1),Y
    INY
    LDA L1_T3               ; the page, less the lines less 1
    AND #$3F
    CLC
    ADC #L1_WBASE           ; (the windows' first page: $40, V2 $80)
    SEC
    SBC L1Q_HM1,X
    STA (ZP_P1),Y
    INY
    LDA L1_X
    STA (ZP_P1),Y
    INY
    STY L1_WY
    JSR L1PartDd            ; (V2: the same as the one before it: dropped) #V2
L1PartN:
    LDA L1_ZN4
    CLC
    ADC #$04
    STA L1_ZN4
    RTS

;;; FARL9 (L1PartDd) -- (V2: placed after the poses' tables, in the runs left) #V2
; (V2) the entry L1PartW just wrote (Y past it) dropped when the one before #V2
; it is L1PartW's too (it ended where this starts: L1_LW) and the same 4 #V2
; bytes: two shapes at one place with one window there, drawn twice for #V2
; nothing (Akuma's room's dead hawk: 23 cycles a line; FINDINGS "Akuma's #V2
; red"). In three parts for the fixed bank's short runs #V2
L1PartDd:                   ; #V2
    TYA                     ; #V2
    SEC                     ; #V2
    SBC #$04                ; #V2
    CMP L1_LW               ; #V2
    STY L1_LW               ; #V2
    BNE L1PartDR            ; #V2
    TAY                     ; (L1Zone's 0: none before it) #V2
    BEQ L1PartDR            ; #V2
    LDX #$04                ; #V2
    JMP L1PartD1            ; #V2
L1PartDR:                   ; #V2
    RTS                     ; #V2
L1PartD1:                   ; (byte k back from its start against its #V2
    DEY                     ; own, 4 on) #V2
    LDA (ZP_P1),Y           ; #V2
    INY                     ; #V2
    INY                     ; #V2
    INY                     ; #V2
    INY                     ; #V2
    CMP (ZP_P1),Y           ; #V2
    BNE L1PartD9            ; #V2
    DEY                     ; #V2
    DEY                     ; #V2
    DEY                     ; #V2
    DEY                     ; #V2
    DEX                     ; #V2
    BNE L1PartD1            ; #V2
    JMP L1PartDx            ; #V2
L1PartD9:                   ; #V2
    RTS                     ; #V2
L1PartDx:                   ; (the same: the list back to its start) #V2
    TYA                     ; #V2
    CLC                     ; #V2
    ADC #$04                ; #V2
    STA L1_WY               ; #V2
    STA L1_LW               ; #V2
    RTS                     ; #V2

;;; FARL2 (L1Bottom)
; the buffer L1_B's two bottom zones' lists (rows 135-144 and 145: not band
; zones; their DLL entries point here, RowsEmitPlain), 64 bytes each (in
; bank L1_CAP, from L1Flip: L1Zone through L1Call)
L1Bottom:
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDA L1_ZBT
    STA L1_K
    LDA #<L1BOT
    LDY #>L1BOT
    LDX L1_B
    BEQ L1Bot1
    LDA #<L1BOTB
    LDY #>L1BOTB
L1Bot1:
    STA ZP_P1
    STY ZP_P1+1
L1Bot2:
    LDA #$01
    STA L1_WR
    LDA #L1BOT_N-2
    STA L1_WMAX
    LDA #<L1Zone
    LDX #>L1Zone
    LDY #L1_HOME
    JSR L1Call
    LDA #$00
    STA (ZP_P1),Y
    INY
    STA (ZP_P1),Y
    LDA ZP_P1
    CLC
    ADC #L1BOT_N
    STA ZP_P1
    INC L1_K
    LDA L1_K
    SEC
    SBC L1_ZBT
    CMP #$02
    BCC L1Bot2
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    RTS

;;; FAR04 (BuildTs) -- the title's and story's lists (FINDINGS "The title and
;;; the opening scroll in bank 0's MARIA copy")
; BuildDllF's builder for the title (the buffer's marks) and the story
; (S_STORY 2), run with bank 0 in (no other bank may be in while MARIA reads
; their data: bank 0's MARIA copy holds it). The description's runs
; (DESCBUF) as BuildDll makes them: blank lines in zones of up to 16, a
; flagged last line a zone of its own; buffer rows as the title's canvases
; (direct objects reading their chunks) or the story's lines (two indirect
; objects a zone reading their maps, character mode). A zone of characters
; whose CHBASE (TS_CB + 14 less its last row in the slot) differs from the
; ones before carries a DLI, ours alone unless the game's is there; its
; number's TS_CHTV entry is that CHBASE (the NMI writes it as the zone
; starts), its TS_CHTP entry 1 if ours alone. The lists in TS_DLA/TS_DLB;
; the results as BuildDll's. S_BTMP the table's base, S_BTMP+1 a zone's
; CHBASE (0 any)
BuildTs:
    LDA #<DESCBUF
    STA S_TSD
    LDA #>DESCBUF
    STA S_TSD+1
    LDA S_DLBUF
    BNE BuildTsB
    LDA #<DLL_A
    STA ZP_P2
    LDA #>DLL_A
    STA ZP_P2+1
    LDA #<TS_DLA
    STA S_TSDL
    LDA #>TS_DLA
    STA S_TSDL+1
    LDA #$00
    BEQ BuildTs1
BuildTsB:
    LDA #<DLL_B
    STA ZP_P2
    LDA #>DLL_B
    STA ZP_P2+1
    LDA #<TS_DLB
    STA S_TSDL
    LDA #>TS_DLB
    STA S_TSDL+1
    LDA #TS_CHB
BuildTs1:
    STA S_BTMP
    TAX                     ; the buffer's tables cleared: past its last
    LDY #TS_CHB+1           ; entry every NMI goes on to NmiGo (its vertical
    LDA #$00                ; blank resets the stub), whatever an NMI missed
BuildTsClr:
    STA TS_CHTV+1,X
    STA TS_CHTP+1,X
    INX
    DEY
    BNE BuildTsClr
    STA S_LINES
    STA S_TSN
    STA S_TSCUR
    STA S_MRG               ; (no empty zone before)
    LDA #$FF
    STA S_TSLL              ; (no story line's list made yet)
BuildTsRun:
    LDA S_TSD
    STA ZP_P1
    LDA S_TSD+1
    STA ZP_P1+1
    LDY #$00
    LDA (ZP_P1),Y
    CMP #$FF
    BNE BuildTsGo
    JMP BuildTsEnd
BuildTsGo:
    STA S_KIND
    INY
    LDA (ZP_P1),Y
    STA S_COUNT
    INY
    LDA (ZP_P1),Y
    STA S_ARG
    LDA S_TSD
    CLC
    ADC #$03
    STA S_TSD
    BCC BuildTs2
    INC S_TSD+1
BuildTs2:
    LDA #$00
    STA S_HASDLI
    LDA S_KIND              ; (DLI_FIRST: as BuildDll's)
    AND #DLI_FIRST
    ASL A
    STA S_DLI1
    LDA S_KIND
    BPL BuildTs3
    INC S_HASDLI
    DEC S_COUNT
BuildTs3:
    AND #$3F
    BEQ BuildTsBlank
    CMP #$01
    BEQ BuildTsM8
BuildTsRows:                ; buffer rows
    LDA S_COUNT
    BEQ BuildTsRowsL
    JSR TsRows
    LDA S_DLI1              ; (the run's first zone: its DLI_FIRST)
    STA S_FLAG
    LDA #$00
    STA S_DLI1
    JSR TsZone
    LDA S_ARG
    CLC
    ADC S_H
    STA S_ARG
    LDA S_COUNT
    SEC
    SBC S_H
    STA S_COUNT
    JMP BuildTsRows
BuildTsRowsL:               ; (the flagged last row alone)
    LDA S_HASDLI
    BEQ BuildTsRunJ
    LDA #$01
    STA S_COUNT
    JSR TsRows
    LDA #$80
    STA S_FLAG
    JSR TsZone
    INC S_ARG
BuildTsRunJ:
    JMP BuildTsRun
BuildTsBlank:
    JSR TsBlanks
    LDA S_HASDLI
    BEQ BuildTsRunJ
    JSR TsFlagged
    JMP BuildTsRun
BuildTsM8:                  ; (mode-8 rows: their lines empty, as blanks)
    JSR TsBlanks
BuildTsM8L:
    LDA S_HASDLI
    BEQ BuildTsRunJ
    JSR TsFlagged
    JMP BuildTsRun
BuildTsEnd:                 ; blanks to VBI_LINE, its stand-in, blanks to the end
    LDA #VBI_LINE
    SEC
    SBC S_LINES
    STA S_COUNT
    JSR TsBlanks
    LDA #$01                ; (the stand-in: no number of ours)
    STA S_H
    LDA #$80
    STA S_FLAG
    LDA #$00
    STA S_BTMP+1
    JSR TsEmpty
    JSR TsPut
    LDA #$80                ; (the lines after it join it)
    STA S_MRG
    LDA #DLL_LINES
    SEC
    SBC S_LINES
    STA S_COUNT
    JSR TsBlanks
    LDA S_BTMP              ; the entry after the last (the vertical blank's
    CLC                     ; NMI): nothing (its flag cleared already)
    ADC S_TSN
    TAX
    LDA #$00
    STA TS_CHTV+1,X
    LDA S_DLBUF
    BNE BuildTsDoneB
    LDA S_TSN
    CLC
    ADC #$01
    STA S_VBI_A
    LDA #$00
    STA S_PDA1
    STA S_PDA2
    LDA S_DLLO
    STA S_DLIST_A
    LDA S_DLHI
    STA S_DLIST_A+1
    LDA #$01
    STA S_CHONA
    RTS
BuildTsDoneB:
    LDA S_TSN
    CLC
    ADC #$01
    STA S_VBI_B
    LDA #$00
    STA S_PDB1
    STA S_PDB2
    LDA S_DLLO
    STA S_DLIST_B
    LDA S_DLHI
    STA S_DLIST_B+1
    LDA #TS_CHB+1
    STA S_CHONB
    RTS
;;; FAR04 (TsZone)
; S_COUNT blank lines in zones of up to 16, the first lines joining the
; empty zone before (S_MRG bit 7: blank, flagged or not) while it has room
; (MARIA loses 8 cycles at every zone's end: the flagged blank line and the
; vertical blank's stand-in were zones of one line)
TsBlanks:
    LDA S_COUNT
    BEQ TsBlanks9
    BIT S_MRG
    BPL TsBlanks0
    LDA #$00
    STA S_MRG
    LDA ZP_P2               ; (the entry before: back 3)
    SEC
    SBC #$03
    STA ZP_P2
    BCS TsBlanksJ
    DEC ZP_P2+1
TsBlanksJ:
    LDY #$00
    LDA (ZP_P2),Y
    AND #$0F
    EOR #$0F                ; (its room: 15 - its OFFSET)
    CMP S_COUNT
    BCC TsBlanksJ1
    LDA S_COUNT
TsBlanksJ1:
    STA S_H                 ; (the lines it takes)
    CLC
    ADC (ZP_P2),Y
    STA (ZP_P2),Y
    JSR TsPutFwd
    LDA S_COUNT
    SEC
    SBC S_H
    STA S_COUNT
    JMP TsBlanks
TsBlanks0:
    LDA S_COUNT
    CMP #17
    BCC TsBlanks1
    LDA #16
TsBlanks1:
    STA S_H
    LDA #$00
    STA S_FLAG
    STA S_BTMP+1
    JSR TsEmpty
    JSR TsZone
    LDA #$80                ; (the lines after it may join it)
    STA S_MRG
    LDA S_COUNT
    SEC
    SBC S_H
    STA S_COUNT
    JMP TsBlanks
TsBlanks9:
    RTS
; one blank line, the game's DLI (the blank lines after it may join it)
TsFlagged:
    LDA #$01
    STA S_H
    LDA #$80
    STA S_FLAG
    LDA #$00
    STA S_BTMP+1
    JSR TsEmpty
    JSR TsZone
    LDA #$80
    STA S_MRG
    RTS
TsEmpty:
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
    RTS
; a zone: S_H lines of the list S_ROWP, S_FLAG $80 the game's DLI on it,
; S_BTMP+1 the CHBASE it wants (0 any)
TsZone:
    LDA S_FLAG
    BEQ TsZone1
    INC S_TSN               ; the game's DLI: its number, the CHBASE so far
    JSR TsIdx               ; (the NMI writes one at every DLI; its flag a
    LDA S_TSCUR             ; place on: the NMI's stub)
    STA TS_CHTV,X
    LDA #$00
    STA TS_CHTP+1,X
TsZone1:
    LDA S_BTMP+1
    BEQ TsPut
    CMP S_TSCUR
    BEQ TsPut
    STA S_TSCUR
    LDA S_FLAG
    BNE TsZone2             ; (the game's DLI carries it)
    LDA S_TSN
    CMP #TS_DLIS
    BCS TsPut               ; (no numbers left: as it was)
    INC S_TSN
    LDA #$80
    STA S_FLAG
    JSR TsIdx
    LDA #$01
    STA TS_CHTP+1,X
TsZone2:
    JSR TsIdx
    LDA S_TSCUR
    STA TS_CHTV,X
TsPut:                      ; the DLL's entry
    LDY #$00
    LDA S_H
    SEC
    SBC #$01
    ORA S_FLAG
    STA (ZP_P2),Y
    INY
    LDA S_ROWP+1
    STA (ZP_P2),Y
    INY
    LDA S_ROWP
    STA (ZP_P2),Y
TsPutFwd:                   ; (on past it; its lines counted)
    LDA ZP_P2
    CLC
    ADC #$03
    STA ZP_P2
    BCC TsPut1
    INC ZP_P2+1
TsPut1:
    LDA S_LINES
    CLC
    ADC S_H
    STA S_LINES
    LDA #$00                ; (a zone that is not empty: nothing joins it)
    STA S_MRG
    RTS
TsIdx:                      ; X: the table entry of DLI S_TSN
    LDA S_BTMP
    CLC
    ADC S_TSN
    TAX
    RTS
;;; FAR04 (TsRows)
; buffer rows from S_ARG (at most S_COUNT): S_H of them, their list S_ROWP,
; their CHBASE S_BTMP+1
TsRows:
    LDA S_STORY
    CMP #$02
    BEQ TsStory
    JMP TsTitle
TsStory:                    ; the story or the ending: rows S_STOP-S_SBOT its
    LDA S_ARG               ; text (S_SLN lines)
    CMP S_STOP
    BCS TsSt1
    LDA S_STOP
    SEC
    SBC S_ARG
    JMP TsBlankH
TsSt1:
    LDA S_SBOT
    CMP S_ARG
    LDA S_ARG
    BCS TsSt2
    LDA #$FF
    JMP TsBlankH
TsSt2:
    CLC                     ; its slot (row + step) / 14, the row in it
    ADC S_STORYT
    STA S_TSQ
    LDA S_STORYT+1
    ADC #$00
    STA S_TSL
    LDX #$00
TsDiv:
    LDA S_TSQ
    SEC
    SBC #STORY_PITCH
    TAY
    LDA S_TSL
    SBC #$00
    BCC TsDivD
    STA S_TSL
    STY S_TSQ
    INX
    BNE TsDiv
TsDivD:
    TXA                     ; its line: the slot less STORY_L0
    SEC
    SBC #STORY_L0
    STA S_TSL
    LDA #STORY_PITCH        ; rows: to the slot's end, the text's, S_COUNT
    SEC
    SBC S_TSQ
    STA S_H
    LDA S_SBOT
    SEC
    SBC S_ARG
    CLC
    ADC #$01
    CMP S_H
    BCS TsSt3
    STA S_H
TsSt3:
    LDA S_COUNT
    CMP S_H
    BCS TsSt4
    STA S_H
TsSt4:
    LDA S_TSL
    CMP S_SLN
    BCS TsStNone            ; (before the first or past the last: none)
    CMP S_TSLL
    BEQ TsStHave
    JSR TsLineDl
    BCS TsStNone            ; (no room: none)
TsStHave:
    LDA S_TSDL              ; its list: the last made
    SEC
    SBC #12
    STA S_ROWP
    LDA S_TSDL+1
    SBC #$00
    STA S_ROWP+1
    LDA #TS_CB+STORY_PITCH  ; CHBASE: TS_CB + 14 less the zone's end in the slot
    SEC
    SBC S_TSQ
    SEC
    SBC S_H
    STA S_BTMP+1
    RTS
TsStNone:
    LDA #$00
    STA S_BTMP+1
    JMP TsEmpty
; A rows (at most S_COUNT, 16) blank
TsBlankH:
    CMP S_COUNT
    BCC TsBH1
    LDA S_COUNT
TsBH1:
    CMP #17
    BCC TsBH2
    LDA #16
TsBH2:
    STA S_H
    LDA #$00
    STA S_BTMP+1
    JMP TsEmpty
; line S_TSL's list at S_TSDL (its two halves' maps, indirect, palette 1):
; C set when the area is full
TsLineDl:
    LDA S_TSDL
    CLC
    ADC #12
    LDX S_DLBUF
    BNE TsLD1
    CMP #<TS_DLAEND
    LDA S_TSDL+1
    SBC #>TS_DLAEND
    BCC TsLD2
    RTS
TsLD1:
    CMP #<TS_DLBEND
    LDA S_TSDL+1
    SBC #>TS_DLBEND
    BCC TsLD2
    RTS
TsLD2:
    LDA S_TSL
    STA S_TSLL
    TAX
    LDA S_TSDL
    STA ZP_P1
    LDA S_TSDL+1
    STA ZP_P1+1
    LDY #$00
    LDA TS_MAPLO,X
    STA (ZP_P1),Y
    INY
    LDA #$60                ; (indirect, a 5-byte header)
    STA (ZP_P1),Y
    INY
    LDA TS_MAPHI,X
    STA (ZP_P1),Y
    INY
    LDA #DL_W               ; (palette 1, 20 codes)
    STA (ZP_P1),Y
    INY
    LDA #$00
    STA (ZP_P1),Y
    INY
    LDA TS_MAPLO,X
    CLC
    ADC #20
    STA (ZP_P1),Y
    INY
    LDA #$60
    STA (ZP_P1),Y
    INY
    LDA TS_MAPHI,X
    STA (ZP_P1),Y
    INY
    LDA #DL_W
    STA (ZP_P1),Y
    INY
    LDA #80
    STA (ZP_P1),Y
    INY
    LDA #$00
    STA (ZP_P1),Y
    INY
    STA (ZP_P1),Y
    LDA S_TSDL
    CLC
    ADC #12
    STA S_TSDL
    BCC TsLD3
    INC S_TSDL+1
TsLD3:
    CLC
    RTS
;;; FAR04 (TsTitle)
; the title: rows in a chunk of a canvas the buffer holds (TS_TK*: its first
; row, rows, the page of its first, its columns, its canvas's mark) a zone
; reading it; else blank to the next such chunk
TsTitle:
    LDA S_DLBUF
    BEQ TsT0
    LDA S_TITLEB
    BNE TsT1
TsT0:
    LDA S_TITLEA
TsT1:
    STA S_TSQ               ; (the buffer's marks)
    LDA #$FF
    STA S_TSL               ; (rows to the next chunk)
    LDX #TS_NCH-1
TsTChunk:
    LDA TS_TKM,X
    AND S_TSQ
    BEQ TsTNext
    LDA S_ARG
    CMP TS_TK0,X
    BCC TsTBelow
    SEC
    SBC TS_TK0,X
    CMP TS_TKN,X
    BCC TsTIn
    BCS TsTNext
TsTBelow:                   ; (the chunk starts below: rows to it)
    LDA TS_TK0,X
    SEC
    SBC S_ARG
    CMP S_TSL
    BCS TsTNext
    STA S_TSL
TsTNext:
    DEX
    BPL TsTChunk
    LDA S_TSL
    JMP TsBlankH
TsTIn:                      ; A: the row's place in the chunk
    STA S_TSQ
    LDA TS_TKN,X            ; rows: to its end, S_COUNT
    SEC
    SBC S_TSQ
    CMP S_COUNT
    BCC TsTIn1
    LDA S_COUNT
TsTIn1:
    STA S_H
    LDA S_TSDL              ; its list (two 20-byte halves) at S_TSDL
    STA ZP_P1
    STA S_ROWP
    LDA S_TSDL+1
    STA ZP_P1+1
    STA S_ROWP+1
    LDA TS_TKP,X            ; the high byte: line L reads page high + h - 1
    SEC                     ; - L, its row's page TS_TKP - its place
    SBC S_TSQ
    SEC
    SBC S_H
    CLC
    ADC #$01
    STA S_TSQ
    LDY #$00
    LDA TS_TKC,X
    STA (ZP_P1),Y
    INY
    LDA #DL_W
    STA (ZP_P1),Y
    INY
    LDA S_TSQ
    STA (ZP_P1),Y
    INY
    LDA #$00
    STA (ZP_P1),Y
    INY
    LDA TS_TKC,X
    CLC
    ADC #20
    STA (ZP_P1),Y
    INY
    LDA #DL_W
    STA (ZP_P1),Y
    INY
    LDA S_TSQ
    STA (ZP_P1),Y
    INY
    LDA #80
    STA (ZP_P1),Y
    INY
    LDA #$00
    STA (ZP_P1),Y
    INY
    STA (ZP_P1),Y
    LDA S_TSDL
    CLC
    ADC #10
    STA S_TSDL
    BCC TsTIn2
    INC S_TSDL+1
TsTIn2:
    LDA #$00
    STA S_BTMP+1
    RTS

;;; FAR04 (StoryTs) -- the story's step (FINDINGS "The title and the opening
;;; scroll in bank 0's MARIA copy")
; the story loop's scroll, clear and string (scene 0 $785E: SysStoryStep):
; the first step story mode on (S_STORY 2: BuildTs's characters) at step 0;
; then each step waits out the pace and counts it (S_STORYT, 0-377); then
; the next picture's list (the other buffer's of the pair on screen) is
; built, which the flip shows. All in the scene page (bank 0) and the fixed
; bank: no other bank in while MARIA reads the story's data
StoryTs:
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDA ZP_P2
    PHA
    LDA ZP_P2+1
    PHA
    LDA S_STORY
    CMP #$02
    BEQ StoryTsWait
    LDA #STORY_N            ; (its lines and rows: StoryTs's, BuildTs's)
    STA S_SLN
    LDA #STORY_TOP
    STA S_STOP
    LDA #STORY_BOT
    STA S_SBOT
    LDA #$02
    STA S_STORY
    LDA #$00
    STA S_STORYT
    STA S_STORYT+1
    STA S_TN
    BEQ StoryTsBuild
StoryTsWait:
    LDA S_FRAMES
    SEC
    SBC S_STORYF
    CMP #STORY_PACE-1
    BCC StoryTsWait
    INC S_STORYT
    BNE StoryTsBuild
    INC S_STORYT+1
StoryTsBuild:
    LDA S_FRAMES
    STA S_STORYF
    INC S_BUSY
    LDX #$00                ; the list on screen
StoryTsCur:
    CPX SP_NDL
    BCS StoryTsNo
    LDA DLT_LO,X
    CMP S_DLIST
    BNE StoryTsCurN
    LDA DLT_HI,X
    CMP S_DLIST+1
    BEQ StoryTsCurY
StoryTsCurN:
    INX
    BNE StoryTsCur
StoryTsCurY:
    LDA DLT_BUF,X
    STA S_SCOL
    LDA DLT_CTRL,X
    STA S_SSH
    LDX #$00                ; its partner: the other buffer's, the same mode
StoryTsTgt:
    CPX SP_NDL
    BCS StoryTsNo
    LDA DLT_BUF,X
    CMP S_SCOL
    BEQ StoryTsTgtN
    LDA DLT_CTRL,X
    CMP S_SSH
    BEQ StoryTsTgtY
StoryTsTgtN:
    INX
    BNE StoryTsTgt
StoryTsTgtY:
    STX S_DLIDX
    JSR BuildDllF
StoryTsNo:
    DEC S_BUSY
    PLA
    STA ZP_P2+1
    PLA
    STA ZP_P2
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    RTS

;;; FAR04 (EndText)
; the ending's text (FINDINGS "The ending's text as characters"): scene 4's
; JSR $6200 (its ten strings, 14 rows apart from row 0, drawn once) comes
; here: the story's characters (BuildTs, S_STORY 2), from bank 4's MARIA copy
; (the ending's characters and maps where the story's are in bank 0's), at
; the step where the first line is at row 0, rows 0-END_BOT, END_N lines; no
; scrolling. Both buffers' lists forgotten: built again as the ending's
EndText:
    LDA #END_N
    STA S_SLN
    LDA #$00
    STA S_L1                ; (scene 4's object set off: the ending is text,
    STA L1_SF               ; the story's way; its lists' RAM theirs)
    STA S_STOP
    STA S_TN
    STA S_STORYT+1
    LDA #END_BOT
    STA S_SBOT
    LDA #STORY_ROW0
    STA S_STORYT
    LDA #$02
    STA S_STORY
    LDA #$00
    STA S_DLIST_A
    STA S_DLIST_A+1
    STA S_DLIST_B
    STA S_DLIST_B+1
    JSR PageBlank           ; (V2: the blank list on screen first) #V2
    LDA #ENDING_BANK        ; (V2: the ending's page, bank 5: scene 4's code, #V2
    STA S_SCENEBANK         ; byte for byte, and MARIA's half the ending's text; #V2
    STA S_BANK              ; the next load sets the scene's again) #V2
    STA BANKSEL             ; #V2
    JMP PageShow            ; #V2
    RTS                     ; #V1

;;; FARART (ObjBlank) #V1
;;; FARCOM (ObjBlank) -- (V2: in every scene page, after its system code) #V2
; the objects' data (the story's, the title's) goes in framebuffer pages,
; so a bitmap list on screen would show it: both buffers' bitmaps are marked
; as holding it (S_OBLANK, a bit a buffer), their rows shown as empty zones
; unless the story's or title's lists show that buffer, every list built
; again, and a three frames' wait, so the list on screen is rebuilt first.
; A buffer's bit comes off when the game clears it (a copy passes it on).
ObjBlank:
    LDA #$03
    STA S_OBLANK
    LDA #$00
    STA S_DLIST_A
    STA S_DLIST_A+1
    STA S_DLIST_B
    STA S_DLIST_B+1
    STA S_CHOSEN
    STA S_CHOSEN+1
    LDA S_FRAMES
    CLC
    ADC #$03
ObjBlankWait:
    CMP S_FRAMES
    BNE ObjBlankWait
    RTS
; the story's and title's modes end (a full clear, a scene load): the screen
; blank first (the clear or the load writes where their data is). C set
; when one ended
ObjEnd:
    LDA S_STORY
    ORA S_TITLEA
    ORA S_TITLEB
    BEQ ObjEndDone
    LDA #$00                ; (off first: the lists rebuilt meanwhile are blank)
    STA S_STORY
    STA S_TITLEA
    STA S_TITLEB
    JSR ObjBlank
    SEC
    RTS
ObjEndDone:
    CLC
    RTS

;;; FARART (TopHelp)
; ----------------------------------------- the top rows as objects
; FINDINGS "The top rows as objects". The buffers hold rows FB_TOP down; what
; the game draws above (level 1's torii, gate structure and posts, level 2's
; gate building and doors: the scene's pieces, the TOP_ tables) is kept as a
; list per buffer of the pieces it holds there, in draw order, and shown as
; objects. A blit of a piece adds it (TopCapture), a fill takes out what it
; covers (TopErase), the full clear empties the list and the buffer copy
; copies it (TopClear, TopCopy); the rows' zones show the list (TopEmit).
; The pieces' rows above the cut are loaded at the scene's load (TopLoad).
;
; S_TBUF from $07: the buffer being drawn's first list entry (A 0, B TOPL_MAX)
TopBuf:
    LDA G_Z07
    CMP #$20
    BNE TopBufA
    LDA #TOPL_MAX
    BNE TopBuf1
TopBufA:
    LDA #$00
TopBuf1:
    STA S_TBUF
    RTS
; Y = S_TBUF's buffer (0 A, 1 B), for its count and background
TopBufY:
    LDY #$00
    LDA S_TBUF
    BEQ TopBufY1
    INY
TopBufY1:
    RTS
; the buffer's pieces changed: its top zones' lists written again when it
; is next shown (TopRefresh; the whole display list built again took most
; of a frame, in the vertical blank, and the game's DLIs were lost: FINDINGS
; "The top rows' flicker")
TopStale:
    JSR TopBufY
    LDA #$01
    STA TOPLD,Y
    RTS
; A the buffer's top's background (Y its buffer, 0 A, 1 B): a change builds
; its display list again when it is next shown (the sky's DLIs: TopSky)
TopBgSet:
    CMP TOPLBG,Y
    BEQ TopBgRts
    STA TOPLBG,Y
    LDA #$00
    LDY S_TBUF
    BNE TopBgB
    STA S_DLIST_A
    STA S_DLIST_A+1
    RTS
TopBgB:
    STA S_DLIST_B
    STA S_DLIST_B+1
TopBgRts:
    RTS
; on to the buffer's next zone slot (its ordinal: TP_DLL, TOPZ_ARG/H)
TopNextSlot:
    INC TP_SO
    RTS

; S_TL (signed) a first pixel, S_TW bytes: S_TX0-S_TX1 its pixels on the
; screen (0-159), C clear; C set when none
TopVis:
    LDA S_TW
    ASL A
    ASL A
    SEC
    SBC #$01                ; 4 x bytes - 1
    CLC
    ADC S_TL
    STA S_TTMP
    LDA S_TL+1
    ADC #$00
    STA S_TTMP+1            ; the last pixel
    BMI TopVisNone          ; left of the screen
    LDA S_TL+1
    BMI TopVisL0
    BNE TopVisNone          ; right of it
    LDA S_TL
    CMP #160
    BCS TopVisNone
    STA S_TX0
    JMP TopVisR
TopVisL0:
    LDA #$00
    STA S_TX0
TopVisR:
    LDA S_TTMP+1
    BNE TopVisR159
    LDA S_TTMP
    CMP #160
    BCC TopVisR1
TopVisR159:
    LDA #159
TopVisR1:
    STA S_TX1
    CLC
    RTS
TopVisNone:
    SEC
    RTS
; list entry X: S_TL its first pixel kept, S_TW its bytes kept, S_TR0-S_TR1
; its rows, and TopVis; Y = the piece
TopEBox:
    LDY TOPLI,X
    LDA TOPLX,X             ; the left pixel: a piece is at most 64 pixels
    STA S_TL                ; wide, so a low byte of 160 or more is left of
    CMP #160                ; the screen
    LDA #$00
    BCC TopEBox1
    LDA #$FF
TopEBox1:
    STA S_TL+1
    LDA TOPLK0,X
    ASL A
    ASL A
    CLC
    ADC S_TL
    STA S_TL
    LDA S_TL+1
    ADC #$00
    STA S_TL+1
    LDA TOPLK1,X
    SEC
    SBC TOPLK0,X
    STA S_TW
    LDA TOP_ROW,Y
    STA S_TR0
    CLC
    ADC TOP_ROWS,Y
    SEC
    SBC #$01
    STA S_TR1
    JMP TopVis
; (V2) the top boxes' cache (FINDINGS "Speed: the top boxes"): for the #V2
; buffer TBC_TAG's list (S_TBUF's: its entries less S_TBUF), each entry's #V2
; shown pixels S_TX0-S_TX1 (TBC_X0, TBC_X1: $FE not known, $FF none shown), #V2
; in the stack page's bottom ($0140-$0178: play's stack stays above $01B8) #V2
TbcCheck:  ; #V2
    LDA S_TBUF  ; #V2
    CMP TBC_TAG  ; #V2
    BEQ TbcCheck2  ; #V2
    STA TBC_TAG  ; #V2
    LDA #$FE  ; #V2
    LDY #TOPL_MAX-1  ; #V2
TbcCheck1:  ; #V2
    STA TBC_X0,Y  ; #V2
    DEY  ; #V2
    BPL TbcCheck1  ; #V2
TbcCheck2:  ; #V2
    RTS  ; #V2
; entry X's box as TopEBox makes it (S_TX0/S_TX1, S_TR0/S_TR1, C set when #V2
; none shown), from the cache when known (no S_TL, S_TW: TopEBox for those); #V2
; Y the piece #V2
TopEBoxC:  ; #V2
    TXA  ; #V2
    SEC  ; #V2
    SBC S_TBUF  ; #V2
    TAY  ; #V2
    LDA TBC_X0,Y  ; #V2
    CMP #$FE  ; #V2
    BCC TopEBC2  ; #V2
    BNE TopEBC9  ; #V2
    TYA  ; #V2
    PHA  ; #V2
    JSR TopEBox  ; #V2
    PLA  ; #V2
    TAY  ; #V2
    BCS TopEBC8  ; #V2
    LDA S_TX0  ; #V2
    STA TBC_X0,Y  ; #V2
    LDA S_TX1  ; #V2
    STA TBC_X1,Y  ; #V2
    LDY TOPLI,X  ; #V2
    CLC  ; #V2
    RTS  ; #V2
TopEBC8:  ; #V2
    LDA #$FF  ; #V2
    STA TBC_X0,Y  ; #V2
TopEBC9:  ; #V2
    SEC  ; #V2
    RTS  ; #V2
TopEBC2:  ; #V2
    STA S_TX0  ; #V2
    LDA TBC_X1,Y  ; #V2
    STA S_TX1  ; #V2
    LDY TOPLI,X  ; #V2
    LDA TOP_ROW,Y  ; #V2
    STA S_TR0  ; #V2
    CLC  ; #V2
    ADC TOP_ROWS,Y  ; #V2
    SEC  ; #V2
    SBC #$01  ; #V2
    STA S_TR1  ; #V2
    CLC  ; #V2
    RTS  ; #V2
; entry X's cache slot not known (its list entry made or changed); A, Y lost #V2
TbcStale:  ; #V2
    TXA  ; #V2
    SEC  ; #V2
    SBC S_TBUF  ; #V2
    TAY  ; #V2
    LDA #$FE  ; #V2
    STA TBC_X0,Y  ; #V2
    RTS  ; #V2
; take entry X out of buffer S_TBUF's list (the later ones move down);
; S_TK the entries left to look at after it
TopDel:
    STX S_TJ
    JSR TopBufY             ; (only the entries in use move: past the list's
    LDA S_TBUF              ; last, S_TTMP; FINDINGS "Speed: the first
    CLC                     ; savings")
    ADC TOPLN,Y
    STA S_TTMP
TopDel1:
    INX
    CPX S_TTMP
    BCS TopDel2
    LDA TOPLI,X
    STA TOPLI-1,X
    LDA TOPLX,X
    STA TOPLX-1,X
    LDA TOPLK0,X
    STA TOPLK0-1,X
    LDA TOPLK1,X
    STA TOPLK1-1,X
    JMP TopDel1
TopDel2:
    LDA TOPLN,Y
    SEC
    SBC #$01
    STA TOPLN,Y
    LDY S_TBUF              ; (the cache's slots move too) #V2
    CPY TBC_TAG  ; #V2
    BNE TopDelX  ; #V2
    STA S_TTMP  ; #V2
    LDA S_TJ  ; #V2
    SEC  ; #V2
    SBC S_TBUF  ; #V2
    TAY  ; #V2
TopDelC:  ; #V2
    CPY S_TTMP  ; #V2
    BCS TopDelX  ; #V2
    LDA TBC_X0+1,Y  ; #V2
    STA TBC_X0,Y  ; #V2
    LDA TBC_X1+1,Y  ; #V2
    STA TBC_X1,Y  ; #V2
    INY  ; #V2
    BNE TopDelC  ; #V2
TopDelX:  ; #V2
    LDX S_TJ
    RTS

;;; FARART (TopCapture)
; at a blit's start (BlitBank, from $29D8; $03/$04 the image, $05 its
; column, $06 its top line, $10 the shift, $07 the buffer): a scene's piece
; drawn above FB_TOP goes into the buffer's list, unless wholly off the
; screen, taking out the pieces wholly under its rectangle (the blit writes
; all of it). X and Y kept.
; a column of the level-1 column routine (TopColumnF: S_TROW its first
; piece's row, A its kind, $10 or mirrored $90): the column's entry, its
; image repeated from that row to the cut, as one piece
TopCapCol:
    STA S_TMIR
    STA S_TRAL              ; (mirrored: its column the right byte's)
    TXA
    PHA
    TYA
    PHA
    LDY S_TMIR
    JMP TopCapKind
TopCapture:                 ; (the top bank in: TopCaptureF; S_TROW set)
    TXA
    PHA
    TYA
    PHA
    TSX                     ; the blit's kind: $29D8's caller, under our two
    LDY #$00                ; bytes, the return into TopCaptureF, its saved
    STY S_TRAL              ; bank, and the returns into BlitBank and $29DC:
    LDA $010A,X             ; TOP_RETA normal, TOP_RETM mirrored, TOP_RETMR
    CMP #<TOP_RETA          ; mirrored with its column the right byte's (the
    BNE TopCapK2            ; low bytes differ: the build checks)
    LDA $010B,X
    CMP #>TOP_RETA
    BEQ TopCapKind
TopCapOut:
    JMP TopCapDone
TopCapK2:
    LDY #$80
    CMP #<TOP_RETM
    BNE TopCapK3
    LDA $010B,X
    CMP #>TOP_RETM
    BEQ TopCapKind
    BNE TopCapOut
TopCapK3:
    CMP #<TOP_RETMR
    BNE TopCapOut
    LDA $010B,X
    CMP #>TOP_RETMR
    BNE TopCapOut
    STY S_TRAL
TopCapKind:
    STY S_TMIR
    LDX S_TT                ; which piece
    LDA S_TN
    STA S_TJ
TopCapFind:
    LDA TOP_SRCLO,X
    CMP G_Z03
    BNE TopCapNext
    LDA TOP_SRCHI,X
    CMP G_Z04
    BNE TopCapNext
    LDA TOP_ROW,X
    CMP S_TROW
    BNE TopCapNext
    LDA TOP_FLAGS,X         ; (mirrored $80, a column $10; a chained column,
    AND #$98                ; $18, matches its first piece's blit: FINDINGS
    CMP #$18                ; "Step 1: scene 0, and level 1's cutscene")
    BEQ TopCapChain
    LDA TOP_FLAGS,X
    AND #$90
    CMP S_TMIR
    BEQ TopCapFound
    BNE TopCapNext
TopCapChain:
    LDA TOP_FLAGS,X
    AND #$80
    CMP S_TMIR
    BEQ TopCapFound
TopCapNext:
    INX
    DEC S_TJ
    BNE TopCapFind
    BEQ TopCapOut           ; not one of the scene's pieces
TopCapFound:
    STX S_TI
    TXA                     ; in the set not loaded: that set loaded first
    SEC
    SBC S_TT
    LDY G_ZD0
    CMP TOPSCN_N,Y
    LDA #$00
    ROL A                   ; (1: the other set)
    CMP S_TSET
    BEQ TopCapSet
    JSR TopSwitch
    LDX S_TI
TopCapSet:
    LDA G_Z05               ; its left pixel: 4 x column + shift; mirrored
    BIT S_TRAL              ; through $2B8B (and the columns'), the column
    BPL TopCapL             ; is its right byte's
    SEC
    SBC TOP_W,X
    CLC
    ADC #$01
TopCapL:
    STA S_TL
    LDY #$00
    CMP #$80
    BCC TopCapL1
    DEY
TopCapL1:
    STY S_TL+1
    ASL S_TL
    ROL S_TL+1
    ASL S_TL
    ROL S_TL+1
    LDA G_Z10
    LSR A
    CLC
    ADC S_TL
    STA S_TL
    LDA S_TL+1
    ADC #$00
    STA S_TL+1
    LDA TOP_W,X
    STA S_TW
    JSR TopVis
    BCS TopCapDone          ; wholly off the screen: the blitter draws nothing
    LDA S_TX0               ; its rectangle
    STA S_TB0
    LDA S_TX1
    STA S_TB1
    LDA S_TROW
    STA S_TF0
    LDX S_TI
    CLC
    ADC TOP_ROWS,X
    SEC
    SBC #$01
    STA S_TF1
    LDA S_TL                ; (kept: TopEBox uses S_TL)
    PHA
    JSR TopBuf
    LDX S_TI                ; its kind (TOP_FLAGS, a piece not a column)
    LDA TOP_FLAGS,X
    AND #$1E
    CMP #$0C                ; (V2: level 2's joint: L2Joint, its page's; #V2
    BEQ TopCapJ             ; FINDINGS "Level 2's windows: the joints as #V2
                            ; one entry". Its erases are no piece) #V2
    CMP #$04                ; an erasing piece ($04): not kept; the pieces  #V1
    BNE TopCapOne           ; wholly under it go (it paints the wall over an  #V1
    PLA                     ; old joint, at a pixel shift: no trimming;  #V1
    JSR TopCover            ; FINDINGS "Step 1: level 2's wall")  #V1
    JSR TopStale  ; #V1
    JMP TopCapDone  ; #V1
TopCapOne:
    CMP #$08                ; one object ($08): its earlier places go
    BNE TopCapCover         ; (FINDINGS "Step 1: level 3's pillar and door
    JSR TopOne              ; frames, one object each")
TopCapCover:
    JSR TopCover
    JSR TopBufY             ; on the end of the list
    LDA TOPLN,Y
    CMP #TOPL_MAX
    BCS TopCapFull
    ADC S_TBUF
    TAX
    LDA TOPLN,Y
    ADC #$01
    STA TOPLN,Y
    LDA S_TI
    STA TOPLI,X
    PLA
    STA TOPLX,X
    LDA #$00
    STA TOPLK0,X
    LDY S_TI
    LDA TOP_W,Y
    STA TOPLK1,X
    JSR TbcStale  ; #V2
    JSR TopStale
    JMP TopCapDone
TopCapFull:
    PLA
TopCapDone:
    PLA
    TAY
    PLA
    TAX
TopCapRts:
    RTS
TopCapJ:                    ; #V2
    PLA                     ; #V2
    JSR L2Joint             ; #V2
    JMP TopCapDone          ; #V2
; the other set of pieces (A: 1 TOP_ALT's, 0 the scene's) loaded in place
; of the one in, both lists emptied (FINDINGS "Step 1: scene 0, and level
; 1's cutscene"); the blit's state and the game's $00-$03 kept
TopSwitch:
    STA S_TSET
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDA ZP_P2
    PHA
    LDA ZP_P2+1
    PHA
    LDA S_TROW
    PHA
    LDA S_TMIR
    PHA
    LDA S_TRAL
    PHA
    LDA S_TI
    PHA
    JSR TopLoadSet
    LDA #$01                ; (both buffers' lists written again)
    STA TOPLD
    STA TOPLD+1
    PLA
    STA S_TI
    PLA
    STA S_TRAL
    PLA
    STA S_TMIR
    PLA
    STA S_TROW
    PLA
    STA ZP_P2+1
    PLA
    STA ZP_P2
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    RTS
; take out of buffer S_TBUF's list each entry of piece S_TI
TopOne:
    JSR TopBufY
    LDA TOPLN,Y
    STA S_TK
    LDX S_TBUF
TopOne1:
    LDA S_TK
    BEQ TopOneDone
    DEC S_TK
    LDA TOPLI,X
    CMP S_TI
    BNE TopOneKeep
    JSR TopDel
    JMP TopOne1
TopOneKeep:
    INX
    JMP TopOne1
TopOneDone:
    RTS
; take out of buffer S_TBUF's list each entry wholly inside pixels
; S_TB0-S_TB1, rows S_TF0-S_TF1 (or wholly off the screen)
TopCover:
    JSR TbcCheck  ; #V2
    JSR TopBufY
    LDA TOPLN,Y
    STA S_TK
    LDX S_TBUF
TopCover1:
    LDA S_TK
    BEQ TopCoverDone
    DEC S_TK
    JSR TopEBox  ; #V1
    TXA                     ; (its cached pixels first: wholly left or right #V2
    SEC                     ; of the rectangle's, kept at once; FINDINGS #V2
    SBC S_TBUF              ; "Speed: the top boxes") #V2
    TAY  ; #V2
    LDA TBC_X0,Y  ; #V2
    CMP #$FE  ; #V2
    BCS TopCoverS  ; #V2
    CMP S_TB0  ; #V2
    BCC TopCoverKeep  ; #V2
    LDA S_TB1  ; #V2
    CMP TBC_X0,Y  ; #V2
    BCC TopCoverKeep  ; #V2
TopCoverS:  ; #V2
    JSR TopEBoxC  ; #V2
    BCS TopCoverDel
    LDA S_TX0
    CMP S_TB0
    BCC TopCoverKeep
    LDA S_TB1
    CMP S_TX1
    BCC TopCoverKeep
    LDA S_TR0
    CMP S_TF0
    BCC TopCoverKeep
    LDA S_TF1
    CMP S_TR1
    BCC TopCoverKeep
TopCoverDel:
    JSR TopDel
    JMP TopCover1
TopCoverKeep:
    INX
    JMP TopCover1
TopCoverDone:
    RTS

;;; FARART (TopErase) #V1
;;; FARPG (TopErase) -- (V2: a copy in every scene page, through PgBuildDll, PgTopErase) #V2
; a fill reaching above FB_TOP (RowBase, before its cut: $05-$09 its
; columns, A its first row, $0D its rows, C set for the rectangle fill, $02
; its value): the pieces it covers wholly go; a piece it covers in part,
; all its rows and from one side, keeps the other side's bytes when it lies
; on whole bytes (FINDINGS: the gate structure's roof, against the torii's
; erase); a rectangle fill over the whole top sets the top's background.
TopErase:                   ; (the top bank in: TopEraseF; S_TF0, S_TMIR set)
    TXA
    PHA
    TYA
    PHA
    LDA S_TF0
    CLC
    ADC G_Z0D
    SEC
    SBC #$01
    CMP #FB_TOP
    BCC TopErase1
    LDA #FB_TOP-1
TopErase1:
    STA S_TF1
    LDA G_Z05
    ASL A
    ASL A
    STA S_TB0
    LDA G_Z09
    ASL A
    ASL A
    SEC
    SBC #$01
    STA S_TB1
    JSR TopBuf
    BIT S_TMIR              ; over the whole top: its background
    BPL TopErase2
    LDA G_Z05
    BNE TopErase2
    LDA G_Z09
    CMP #40
    BCC TopErase2
    LDA S_TF0
    BNE TopErase2
    LDA S_TF1
    CMP #FB_TOP-1
    BNE TopErase2
    JSR TopBufY
    LDA G_Z02
    AND #$03
    JSR TopBgSet
TopErase2:
    JSR TopEraseList
    JSR TopFillAdd
    PLA
    TAY
    PLA
    TAX
    RTS
; the list pass: buffer S_TBUF's pieces under a fill's pixels S_TB0-S_TB1,
; rows S_TF0-S_TF1
TopEraseList:
    JSR TbcCheck  ; #V2
    JSR TopBufY
    LDA TOPLN,Y
    STA S_TK
    LDX S_TBUF
TopEraseNext:
    LDA S_TK
    BNE TopEraseOne
    JMP TopEraseDone
TopEraseOne:
    DEC S_TK
    JSR TopEBox  ; #V1
    TXA                     ; (its cached pixels first: no overlap, kept at #V2
    SEC                     ; once) #V2
    SBC S_TBUF  ; #V2
    TAY  ; #V2
    LDA TBC_X0,Y  ; #V2
    CMP #$FE  ; #V2
    BCS TopEraseS  ; #V2
    LDA S_TB1  ; #V2
    CMP TBC_X0,Y  ; #V2
    BCC TopEraseKeep  ; #V2
    LDA TBC_X1,Y  ; #V2
    CMP S_TB0  ; #V2
    BCC TopEraseKeep  ; #V2
TopEraseS:  ; #V2
    JSR TopEBoxC  ; #V2
    BCS TopEraseDel         ; (off the screen)
    LDA S_TX1               ; no overlap: kept
    CMP S_TB0
    BCC TopEraseKeep
    LDA S_TB1
    CMP S_TX0
    BCC TopEraseKeep
    LDA S_TR1
    CMP S_TF0
    BCC TopEraseKeep
    LDA S_TF1
    CMP S_TR0
    BCC TopEraseKeep
    JSR TbcStale            ; (it may be trimmed: its whole box, S_TL) #V2
    JSR TopEBox  ; #V2
    JSR TopStale
    JMP TopErasePart
TopEraseKeep:
    INX
    JMP TopEraseNext
TopEraseDel:
    JSR TopDel
    JSR TopStale
    JMP TopEraseNext
TopErasePart:
    LDA S_TR0               ; all its rows?
    CMP S_TF0
    BCC TopErasePRows       ; (some rows only)
    LDA S_TF1
    CMP S_TR1
    BCC TopErasePRows
    LDA S_TX0               ; from its left?
    CMP S_TB0
    BCC TopEraseRight
    LDA S_TB1
    CMP S_TX1
    BCS TopEraseDel         ; all of it
    LDA S_TL+1              ; the left part: bytes up to the fill's end go
    BNE TopEraseKeep        ; (from left of the screen: kept whole)
    LDA S_TL
    AND #$03
    BNE TopEraseKeep        ; (not on whole bytes: kept whole)
    LDA S_TB1
    SEC
    SBC S_TL
    CLC
    ADC #$01
    LSR A
    LSR A                   ; the bytes covered
    CLC
    ADC TOPLK0,X
    STA TOPLK0,X
    CMP TOPLK1,X
    BCS TopEraseDel
    JMP TopEraseKeep
TopEraseRight:
    LDA S_TB1               ; the right part
    CMP S_TX1
    BCC TopEraseKeep        ; (the middle: kept whole)
    LDA S_TL+1
    BNE TopEraseKeep
    LDA S_TL
    AND #$03
    BNE TopEraseKeep
    LDA S_TB0
    SEC
    SBC S_TL
    LSR A
    LSR A                   ; the bytes kept
    CLC
    ADC TOPLK0,X
    STA TOPLK1,X
    CMP TOPLK0,X
    BEQ TopEraseDel
    BCC TopEraseDel
    JMP TopEraseKeep
TopEraseDone:
    RTS
; some of its rows only: kept whole, unless the fill spans its kept width
; and those rows hold every pixel it shows there (each byte's first and last
; rows with a visible pixel: TOP_NTI, TOP_NTLO/HI; FINDINGS "Step 1: the
; vertical erase")
TopErasePRows:
    LDA S_TB0
    CMP S_TX0
    BEQ TopEPR1
    BCS TopEPRRight         ; (the fill starts right of its left edge)
TopEPR1:
    LDA S_TX1
    CMP S_TB1
    BEQ TopEPR2
    BCS TopEPRLeft          ; (it reaches right of the fill)
TopEPR2:
    LDY TOPLI,X
    LDA TOP_NTI,Y
    CLC
    ADC TOPLK0,X
    TAY                     ; the first kept byte's entry
    LDA TOPLK1,X
    SEC
    SBC TOPLK0,X
    STA S_TTMP              ; the kept bytes
TopEPR3:
    LDA TOP_NTLO,Y          ; (no visible pixel: $FF and $00)
    CMP S_TF0
    BCC TopEPRKeep          ; it shows above the fill
    LDA S_TF1
    CMP TOP_NTHI,Y
    BCC TopEPRKeep          ; it shows below it
    INY
    DEC S_TTMP
    BNE TopEPR3
    JMP TopEraseDel
TopEPRKeep:
    JMP TopEraseKeep
; the fill over its left edge, some rows only: its first bytes the fill
; spans go while each shows only in those rows (on screen, whole bytes)
TopEPRLeft:
    LDA S_TL+1
    BNE TopEPRKeep          ; (from left of the screen)
TopEPRL1:
    LDA S_TL                ; this byte's last pixel within the fill?
    CLC
    ADC #$03
    BCS TopEPRKeep
    CMP S_TB1
    BEQ TopEPRL2
    BCS TopEPRDone
TopEPRL2:
    JSR TopEPRByte          ; (Y: its entry, from TOPLK0)
    LDY TOPLK0,X
    BCC TopEPRDone          ; it shows outside the fill's rows
    INC TOPLK0,X
    LDA TOPLK0,X
    CMP TOPLK1,X
    BCS TopEPRDel
    LDA S_TL
    CLC
    ADC #$04
    STA S_TL
    BCC TopEPRL1
TopEPRDone:
    JMP TopEraseKeep
TopEPRDel:
    JMP TopEraseDel
; the fill over its right edge, some rows only: the same from its last byte
TopEPRRight:
    LDA S_TX1
    CMP S_TB1
    BEQ TopEPRR0
    BCS TopEPRKeep          ; (it reaches right of the fill: the middle only)
TopEPRR0:
    LDA S_TL+1
    BNE TopEPRKeep
    LDA TOPLK1,X            ; its last byte's first pixel
    SEC
    SBC TOPLK0,X
    SEC
    SBC #$01
    ASL A
    ASL A
    CLC
    ADC S_TL
    BCS TopEPRKeep
    STA S_TL
TopEPRR1:
    LDA S_TL
    CMP S_TB0
    BCC TopEPRDone          ; (not within the fill)
    LDY TOPLK1,X
    DEY
    TYA
    JSR TopEPRByteA
    BCC TopEPRDone
    DEC TOPLK1,X
    LDA TOPLK1,X
    CMP TOPLK0,X
    BEQ TopEPRDel
    BCC TopEPRDel
    LDA S_TL
    SEC
    SBC #$04
    STA S_TL
    BCS TopEPRR1
    JMP TopEraseKeep
; C set if byte TOPLK0 (TopEPRByte) or A (TopEPRByteA) of entry X shows only
; within rows S_TF0-S_TF1 (or not at all)
TopEPRByte:
    LDA TOPLK0,X
TopEPRByteA:
    LDY TOPLI,X
    CLC
    ADC TOP_NTI,Y
    TAY
    LDA TOP_NTLO,Y
    CMP S_TF0
    BCC TopEPRByteNo
    LDA S_TF1
    CMP TOP_NTHI,Y
    BCC TopEPRByteNo
    SEC
    RTS
TopEPRByteNo:
    CLC
    RTS

; a fill one of the scene's fill pieces stands for (TOPSCN_FF, TOPSCN_FN;
; a fill piece's source: the fill's first row and colour byte, then its own
; rows' bytes): the piece over the fill's columns, an entry each TOP_W
; bytes, on the end of the list (FINDINGS "Step 1: level 2's wall")
TopFillAdd:
    LDX G_ZD0
    LDA TOPSCN_FN,X
    BEQ TopFARts
    STA S_TJ
    LDA TOPSCN_FF,X
    TAX
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
TopFA1:
    LDA TOP_SRCLO,X
    STA ZP_P1
    LDA TOP_SRCHI,X
    STA ZP_P1+1
    LDY #$00
    LDA (ZP_P1),Y
    CMP S_TF0
    BNE TopFANext
    INY
    LDA (ZP_P1),Y
    CMP G_Z02
    BEQ TopFAFound
TopFANext:
    INX
    DEC S_TJ
    BNE TopFA1
TopFAOut:
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
TopFARts:
    RTS
TopFAFound:
    STX S_TI
    LDA TOP_ROW,X           ; its rectangle: the fill's columns (S_TB0-S_TB1),
    STA S_TF0               ; the piece's rows
    CLC
    ADC TOP_ROWS,X
    SEC
    SBC #$01
    STA S_TF1
    JSR TopCover
    LDA G_Z05
    STA S_TK
TopFA2:
    JSR TopBufY
    LDA TOPLN,Y
    CMP #TOPL_MAX
    BCS TopFADone
    ADC S_TBUF
    TAX
    LDA TOPLN,Y
    ADC #$01
    STA TOPLN,Y
    LDA S_TI
    STA TOPLI,X
    LDA S_TK
    ASL A
    ASL A
    STA TOPLX,X
    LDA #$00
    STA TOPLK0,X
    JSR TbcStale  ; #V2
    LDY S_TI
    LDA G_Z09               ; TOP_W bytes, or to the fill's end
    SEC
    SBC S_TK
    CMP TOP_W,Y
    BCC TopFA3
    LDA TOP_W,Y
TopFA3:
    STA TOPLK1,X
    LDA S_TK
    CLC
    ADC TOP_W,Y
    STA S_TK
    CMP G_Z09
    BCC TopFA2
TopFADone:
    JSR TopStale
    JMP TopFAOut
;;; FARART (TopClearCopy) #V1
;;; FARCOM (TopClearCopy) -- (V2: in every scene page, after its system code) #V2
; the full clear: the buffer's list empty, its top black (as the clear
; leaves its rows)
TopClear:
    LDA #$FF                ; (the boxes' cache dropped) #V2
    STA TBC_TAG  ; #V2
    JSR TopBuf
    JSR TopBufY
    LDA #$00
    STA TOPLN,Y
    JSR TopBgSet
    JMP TopStale
; the buffer copy ($07 = $40: B into A, else A into B): the list too
TopCopy:
    LDA #$FF                ; (the boxes' cache dropped) #V2
    STA TBC_TAG  ; #V2
    LDX #$00                ; X the source's first entry, Y the copy's
    LDY #TOPL_MAX
    LDA G_Z07
    CMP #$40
    BNE TopCopy1
    LDX #TOPL_MAX
    LDY #$00
TopCopy1:
    STY S_TBUF
    LDA #TOPL_MAX
    STA S_TK
TopCopy2:
    LDA TOPLI,X
    STA TOPLI,Y
    LDA TOPLX,X
    STA TOPLX,Y
    LDA TOPLK0,X
    STA TOPLK0,Y
    LDA TOPLK1,X
    STA TOPLK1,Y
    INX
    INY
    DEC S_TK
    BNE TopCopy2
    LDX #$00                ; the count and background
    LDY #$01
    LDA S_TBUF
    BNE TopCopy3
    LDX #$01
    LDY #$00
TopCopy3:
    LDA TOPLN,X
    STA TOPLN,Y
    LDA TOPLBG,X
    JSR TopBgSet
    JMP TopStale

;;; FARART (TopEmit)
; the zone of S_H rows from row S_ARG (above FB_TOP) of buffer S_SLOT (0 A,
; 3 B): its list's pieces with rows in it, as objects reading the top data
; (row r at page TOP_PBASE - r mod 15, the piece's slice of the zone at its
; TOP_Zn byte), written straight into the first of the buffer's top pieces
; in console RAM with room (TpPlace): a pass counts the list's bytes, a
; second writes them there (none, or no room: the empty list); then its DLL
; entry. Its slot (TP_SO, by ordinal) keeps the zone for TopRefresh
; (TOPZ_ARG, TOPZ_H)
TopEmit:                    ; (the top bank in: TopEmitF)
    LDA TP_SO               ; the buffer's slots (TOPDL_N, A's ordinals from
    LDX S_SLOT              ; 0, B's from TOPDL_N): one left?
    BEQ TopEmitSlA
    SEC
    SBC #TOPDL_N
TopEmitSlA:
    CMP #TOPDL_N
    BCC TopEmitSl
    JMP TopEmitEmpty
TopEmitSl:
    LDA S_ARG               ; the grid zone (0-2) and the zone's last row
    LDX #$00
TopEmitZ:
    CMP #TOP_ZONE
    BCC TopEmitZ1
    SBC #TOP_ZONE
    INX
    BNE TopEmitZ
TopEmitZ1:
    STX S_EJ
    CLC
    ADC S_H
    SEC
    SBC #$01                ; (within the grid zone)
    STA S_ETMP
    LDA S_TPB               ; (the set's data in MARIA's ROM: TopLoad)
    SEC
    SBC S_ETMP
    STA S_ETMP+1            ; the high byte: the zone's last row's page
    LDA S_ARG
    CLC
    ADC S_H
    STA S_ETMP              ; the row after the zone
    LDA #$00
    LDY #$00
    LDX S_SLOT
    BEQ TopEmitBuf
    LDA #TOPL_MAX
    INY
TopEmitBuf:
    STA S_EBUF
    LDA TOPLN,Y
    STA TP_EK               ; (the pieces' count, again for the second pass)
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDX TP_SO               ; the slot's zone, for TopRefresh
    LDA S_ARG
    STA TOPZ_ARG,X
    LDA S_H
    STA TOPZ_H,X
    LDA TP_BLD              ; (the DLL being built: its entry's address, for
    BEQ TopEmitNB           ; TopRefresh to point at the list: TP_DLL by the
    LDA ZP_P2               ; slot's ordinal, the low byte: the page the
    STA TP_DLL,X            ; buffer's DLL's)
TopEmitNB:
    LDA #$01                ; the counting pass
    STA TP_PASS
TopEmitPass:
    LDA TP_EK
    STA S_EK
    LDA #$00
    STA S_EW                ; the list's bytes so far
    LDA S_TSKY              ; with a sky, the top's last row: opaque sky
    BEQ TopEmitPieces       ; under the pieces (the switch may land anywhere
    LDA S_ARG               ; in it)
    CMP #FB_TOP-1
    BNE TopEmitPieces
    LDY #$08
    LDA TP_PASS
    BNE TopEmitSkyN
    LDY #$00
TopEmitSky:
    LDA TopEmitSkyObj,Y
    STA (ZP_P1),Y
    INY
    CPY #$08
    BNE TopEmitSky
TopEmitSkyN:
    STY S_EW
TopEmitPieces:
    LDX S_EBUF
TopEmitNext:
    LDA S_EK
    BNE TopEmitMore
    JMP TopEmitEnd
TopEmitMore:
    DEC S_EK
    LDY TOPLI,X             ; the piece
    LDA TOP_ROW,Y           ; its rows meet the zone's?
    CMP S_ETMP
    BCS TopEmitSkipJ
    CLC
    ADC TOP_ROWS,Y
    SEC
    SBC #$01
    CMP S_ARG
    BCS TopEmitMeets
TopEmitSkipJ:
    JMP TopEmitSkip
TopEmitMeets:
    LDA S_EW                ; (a list holds 14 objects and the end; the rest
    CMP #TOPDL_ARG-5        ; are left out)
    BCS TopEmitSkipJ
    LDA S_EJ                ; its slice of the grid zone (0-4)
    BEQ TopEmitZ0
    CMP #$02
    BCC TopEmitZ1b
    BEQ TopEmitZ2b
    CMP #$04
    BCC TopEmitZ3b
    LDA TOP_Z4,Y
    JMP TopEmitLo
TopEmitZ3b:
    LDA TOP_Z3,Y
    JMP TopEmitLo
TopEmitZ2b:
    LDA TOP_Z2,Y
    JMP TopEmitLo
TopEmitZ1b:
    LDA TOP_Z1,Y
    JMP TopEmitLo
TopEmitZ0:
    LDA TOP_Z0,Y
TopEmitLo:
    CMP #$FF
    BEQ TopEmitSkip
    CMP #$FE                ; (V2: level 2's joints' entry: L2JEmit, which #V2
    BNE TopEmitLoN          ; goes on at TopEmitSkip) #V2
    JMP L2JEmit             ; #V2
TopEmitLoN:                 ; #V2
    LDY TP_PASS             ; (counting: its 4 bytes only)
    BNE TopEmitCnt
    CLC
    ADC TOPLK0,X            ; from the first byte kept
    LDY S_EW
    STA (ZP_P1),Y
    LDY TOPLI,X             ; the piece again
    LDA TOPLK0,X            ; the width kept: palette and -width
    SEC
    SBC TOPLK1,X
    AND #$1F
    STA S_EI
    LDA TOP_PALW,Y
    AND #$E0
    ORA S_EI
    LDY S_EW
    INY
    STA (ZP_P1),Y
    INY
    LDA S_EJ                ; its data's page: the zone's last row's; in the
    CMP #$04                ; last zone, TOP_Z4O pages lower (three of that
    LDA S_ETMP+1            ; zone's slices share a column)
    BCC TopEmitHi
    STY S_EI
    LDY TOPLI,X
    SEC
    SBC TOP_Z4O,Y
    LDY S_EI
TopEmitHi:
    STA (ZP_P1),Y
    INY
    LDA TOPLK0,X            ; the first pixel kept
    ASL A
    ASL A
    CLC
    ADC TOPLX,X
    STA (ZP_P1),Y
    INY
    STY S_EW
    BNE TopEmitSkip
TopEmitCnt:
    LDA S_EW
    CLC
    ADC #$04
    STA S_EW
TopEmitSkip:
    INX
    JMP TopEmitNext
TopEmitEnd:
    LDA TP_PASS
    BEQ TopEmitEnd0
    LDA S_EW                ; counted: none, the empty list; else a piece
    BEQ TopEmitNone         ; with room for it and its end (ZP_P1 there)
    JSR TpPlace
    BCS TopEmitNone
    LDA #$00                ; and written
    STA TP_PASS
    JMP TopEmitPass
TopEmitNone:
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
    JMP TopEmitDll
TopEmitEnd0:
    LDY S_EW                ; the list's end
    LDA #$00
    STA (ZP_P1),Y
    INY
    STA (ZP_P1),Y
    LDA ZP_P1
    STA S_ROWP
    LDA ZP_P1+1
    STA S_ROWP+1
TopEmitDll:
    JSR TpDll
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    JSR TopNextSlot         ; the next slot
    JMP TopEmitEntry
TopEmitEmpty:
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
TopEmitEntry:
    RTS
TopEmitSkyObj:
    .byte <TOPSKYROW, DL_W, >TOPSKYROW, 0, <TOPSKYROW, DL_W, >TOPSKYROW, 80

; room for S_EW + 2 bytes in the first of the buffer's top pieces with it
; (TPSG_* from TP_SG; TP_SGP its next byte): ZP_P1 there, its next byte past
; them, C clear; C set: none (or no pieces, S_BLPC $FF)
TpPlace:
    LDA S_BLPC
    BMI TpPlNo
    LDA S_EW
    CLC
    ADC #$02
    STA TP_T0
    LDY TP_SG
    LDX #$00
TpPlT:
    LDA TPSG_SH,Y           ; (a high byte 0 ends the buffer's pieces)
    BEQ TpPlNo
    LDA TP_SGP,X
    CLC
    ADC TP_T0
    STA TP_T1
    LDA TP_SGP+1,X
    ADC #$00
    STA TP_T2
    LDA TPSG_EH,Y
    CMP TP_T2
    BCC TpPlN
    BNE TpPlF
    LDA TPSG_EL,Y
    CMP TP_T1
    BCS TpPlF
TpPlN:
    INY
    INX
    INX
    BNE TpPlT
TpPlF:
    LDA TP_SGP,X            ; (here)
    STA ZP_P1
    LDA TP_SGP+1,X
    STA ZP_P1+1
    LDA TP_T1
    STA TP_SGP,X
    LDA TP_T2
    STA TP_SGP+1,X
    CLC
    RTS
TpPlNo:
    SEC
    RTS
; out of the DLL's build (TopRefresh), the slot's DLL entry (the address
; the build kept in TP_DLL) pointed at S_ROWP. ZP_P2 kept
TpDll:
    LDA TP_BLD              ; (the build writes the entry itself)
    BNE TpDllOut
    LDA ZP_P2
    PHA
    LDA ZP_P2+1
    PHA
    LDY TP_SO
    LDA TP_DLL,Y
    STA ZP_P2
    LDA #>DLL_A             ; (A's slots 0-9, B's from TOPDL_N)
    CPY #TOPDL_N
    BCC TpDll1
    LDA #>DLL_B
TpDll1:
    STA ZP_P2+1
    LDY #$01
    LDA S_ROWP+1
    STA (ZP_P2),Y
    INY
    LDA S_ROWP
    STA (ZP_P2),Y
    PLA
    STA ZP_P2+1
    PLA
    STA ZP_P2
TpDllOut:
    RTS

; the DLL's build: all the buffer's top slots (from TP_SO) unused, their
; zone's height 0, till the build lists them (TopEmit), so TopRefresh writes
; only this DLL's zones (with S_BLPC's pieces only; a slot from an earlier
; build had its DLL entry's place taken by another zone)
TopSlotsOff:
    LDA S_BLPC
    BMI TopSlotsOff9
    LDX TP_SO
    LDY #TOPDL_N
    LDA #$00
TopSlotsOff1:
    STA TOPZ_H,X
    INX
    DEY
    BNE TopSlotsOff1
TopSlotsOff9:
    RTS

; a buffer's top pieces afresh (A: 0 A, 8 B; with S_BLPC's pieces only), X
; and Y kept
TopSegStart:
    PHA
    LDA S_BLPC
    BPL TopSegS1
    PLA
    RTS
TopSegS1:
    PLA
    ORA S_BLPC
    STA TP_SG
    TXA
    PHA
    TYA
    PHA
    LDY TP_SG
    LDX #$00
TopSegS2:
    LDA TPSG_SL,Y
    STA TP_SGP,X
    LDA TPSG_SH,Y
    STA TP_SGP+1,X
    INY
    INX
    INX
    CPX #$0E
    BCC TopSegS2
    PLA
    TAY
    PLA
    TAX
    RTS
TPSG_SL:                    ; (rows as L1SG_*'s: level 1's A 0, B 8; levels
    .byte <TPSA0, <TPSA1, <TPSA2, <TPSA3, <TPSA4, <TPSA5, <TPSA6, 0     ; 2-4's A
    .byte <TPSB0, <TPSB1, <TPSB2, <TPSB3, <TPSB4, <TPSB5, <TPSB6, 0     ; 16, B 24;
    .byte <TPSC0, <TPSC1, <TPSC2, <TPSC3, <TPSC4, <TPSC5, <TPSC6, 0     ; a high
    .byte <TPSD0, <TPSD1, <TPSD2, <TPSD3, <TPSD4, <TPSD5, <TPSD6, 0
    .byte <TPSE0, <TPSE1, <TPSE2, <TPSE3, <TPSE4, <TPSE5, <TPSE6, 0
    .byte <TPSF0, <TPSF1, <TPSF2, <TPSF3, <TPSF4, <TPSF5, <TPSF6, 0     ; byte 0
TPSG_SH:                    ; ends a buffer's)
    .byte >TPSA0, >TPSA1, >TPSA2, >TPSA3, >TPSA4, >TPSA5, >TPSA6, 0
    .byte >TPSB0, >TPSB1, >TPSB2, >TPSB3, >TPSB4, >TPSB5, >TPSB6, 0
    .byte >TPSC0, >TPSC1, >TPSC2, >TPSC3, >TPSC4, >TPSC5, >TPSC6, 0
    .byte >TPSD0, >TPSD1, >TPSD2, >TPSD3, >TPSD4, >TPSD5, >TPSD6, 0
    .byte >TPSE0, >TPSE1, >TPSE2, >TPSE3, >TPSE4, >TPSE5, >TPSE6, 0
    .byte >TPSF0, >TPSF1, >TPSF2, >TPSF3, >TPSF4, >TPSF5, >TPSF6, 0
TPSG_EL:
    .byte <TPSA0E, <TPSA1E, <TPSA2E, <TPSA3E, <TPSA4E, <TPSA5E, <TPSA6E, 0
    .byte <TPSB0E, <TPSB1E, <TPSB2E, <TPSB3E, <TPSB4E, <TPSB5E, <TPSB6E, 0
    .byte <TPSC0E, <TPSC1E, <TPSC2E, <TPSC3E, <TPSC4E, <TPSC5E, <TPSC6E, 0
    .byte <TPSD0E, <TPSD1E, <TPSD2E, <TPSD3E, <TPSD4E, <TPSD5E, <TPSD6E, 0
    .byte <TPSE0E, <TPSE1E, <TPSE2E, <TPSE3E, <TPSE4E, <TPSE5E, <TPSE6E, 0
    .byte <TPSF0E, <TPSF1E, <TPSF2E, <TPSF3E, <TPSF4E, <TPSF5E, <TPSF6E, 0
TPSG_EH:
    .byte >TPSA0E, >TPSA1E, >TPSA2E, >TPSA3E, >TPSA4E, >TPSA5E, >TPSA6E, 0
    .byte >TPSB0E, >TPSB1E, >TPSB2E, >TPSB3E, >TPSB4E, >TPSB5E, >TPSB6E, 0
    .byte >TPSC0E, >TPSC1E, >TPSC2E, >TPSC3E, >TPSC4E, >TPSC5E, >TPSC6E, 0
    .byte >TPSD0E, >TPSD1E, >TPSD2E, >TPSD3E, >TPSD4E, >TPSD5E, >TPSD6E, 0
    .byte >TPSE0E, >TPSE1E, >TPSE2E, >TPSE3E, >TPSE4E, >TPSE5E, >TPSE6E, 0
    .byte >TPSF0E, >TPSF1E, >TPSF2E, >TPSF3E, >TPSF4E, >TPSF5E, >TPSF6E, 0

;;; FARLOAD (TopLoad) #V1
;;; FARART (TopLoad) -- (V2: not the loader bank's: TopCapture's TopSwitch loads a set in play, TopLoadSet) #V2
; at a scene's load: the scene's pieces (S_TT the first, S_TN how many),
; both lists empty and the tops black, and the pieces' rows above the cut
; into the top data, from their images in the scene's data (mirrored with
; the mirrored blitter's own byte table; level 1's converted for its sky:
; colour 2 transparent, colour 0 an opaque black in the pieces' palette)
TopLoad:
    LDA #$00
    STA TOPLN
    STA TOPLN+1
    STA TOPLBG
    STA TOPLBG+1
    STA TOPLD
    STA TOPLD+1
    STA S_TSET              ; (its first set)
    LDX G_ZD0
    LDA TOPSCN_FIRST,X
    STA S_TT
    LDA TOPSCN_N,X          ; S_TN: both sets' pieces (TopCapture matches
    CLC                     ; either)
    ADC TOPSCN_A,X
    STA S_TN
    BNE TopLoadSet
    RTS
; set S_TSET's pieces (0 the scene's TOPSCN_N, 1 the TOPSCN_A after them):
; their data's top page (S_TPB); both lists emptied
TopLoadSet:
    LDA #$FF                ; (the boxes' cache dropped) #V2
    STA TBC_TAG  ; #V2
    LDA #$00
    STA TOPLN
    STA TOPLN+1
    LDX #9                  ; the black line's list (the sky row: MARIA's ROM)
TopLoadBl:
    LDA TopLoadBlack,X
    STA TOPBLACKDL,X
    DEX
    BPL TopLoadBl
    LDX G_ZD0               ; its data (converted by the build, in MARIA's
    LDA TOPSCN_PB,X         ; ROM: FINDINGS "BankSet step 1: the top
    LDY S_TSET              ; pieces"): its top page
    BEQ TopLoadPB
    LDA TOPSCN_PBA,X
TopLoadPB:
    STA S_TPB
    RTS
TopLoadBlack:
    .byte <TOPSKYROW, TOP_BLACKW, >TOPSKYROW, 0, <TOPSKYROW, TOP_BLACKW, >TOPSKYROW, 80, 0, 0

;;; FAR (TopStubs)
; the top bank's parts' entries (TOP_BANK, the spare bank: the art bank
; had no room left): that bank in meanwhile (S_BANK kept true, for the NMI)
TopCaptureF:                ; BlitBank, at a blit's start
    LDA S_TN
    BEQ TopStubRts
    LDA S_TCOL              ; (inside a captured column: its pieces aren't)
    BNE TopStubRts
    LDA G_Z06
    SEC
    SBC #$23
    CMP #FB_TOP
    BCS TopStubRts
    STA S_TROW
    LDA S_BANK
    PHA
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    JSR TopCapture
TopStubOut:
    PLA
    STA S_BANK
    STA BANKSEL
TopStubRts:
    RTS
TopEraseF:                  ; RowBase, a fill: A its first row, C set for the
    STA S_TF0               ; rectangle fill
    ROR S_TMIR
    LDA S_TN
    BEQ TopStubRts
    LDA S_BANK
    PHA
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    JSR TopErase  ; #V1
    JSR PgTopErase          ; (V2: the scene page's copy) #V2
    JMP TopStubOut
TopRefreshF:                ; FrameGo: A the buffer shown (0 A, 3 B)
    STA S_SLOT
    LDA S_TN
    BEQ TopStubRts
    LDA S_BANK
    PHA
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    JSR TopRefresh
    JMP TopStubOut
TopColumnF:                 ; the level-1 column routine (ColA, ColC), on
    STA S_TCOLK             ; entry: A the kind ($10, mirrored $90); $06 the
    LDA S_TN                ; top line of the column's first piece (the game
    BEQ TopColRts           ; drew it before the loop the routine replaces)
    LDA G_Z06
    SEC
    SBC #$23
    CMP #FB_TOP
    BCS TopColRts           ; wholly in the buffer
    STA S_TROW
    INC S_TCOL              ; (its pieces' own captures skip; ColDone clears)
    LDA S_BANK
    PHA
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    LDA S_TCOLK
    JSR TopCapCol
    JMP TopStubOut
TopColRts:
    RTS
TopClearF:                  ; ClearBuf
    LDA #<TopClear
    LDX #>TopClear
    BNE TopArtCall
TopCopyF:                   ; CopyBuf
    LDA #<TopCopy
    LDX #>TopCopy
    BNE TopArtCall
TextInF:                    ; the game's text routine ($0780), as it starts:
    LDA S_GLYIN             ; its glyphs (the small-sprite block) brought into
    BNE TextInGo            ; RAM if not there since the scene loaded
    LDA #<TextIn
    LDX #>TextIn
    JSR TopArtCall
TextInGo:
    LDY #$00                ; (the routine's first two instructions)
    STY G_Z0F
    RTS
TopLoadF:                   ; LoadScene
    LDA #<TopLoad
    LDX #>TopLoad
    BNE TopArtCall
TopColoursF:                ; Frame (in the NMI: its own way in)
    LDA S_BANK
    PHA
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    JSR TopColours
    JMP TopStubOut
; the top bank's routine at X:A, that bank in meanwhile (X, Y not kept;
; the main program's only: S_TTMP)
TopArtCall:
    STA S_TTMP
    STX S_TTMP+1
    LDA S_BANK
    PHA
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    JSR TopArtJmp
    JMP TopStubOut
TopArtJmp:
    JMP (S_TTMP)
; (V2) a load's piece (FARLOAD) in the loader bank: A/X its address; the #V2
; caller's bank after. Only at a load (the blank list) or the game's end #V2
LoaderCall:                 ; #V2
    STA S_TTMP              ; #V2
    STX S_TTMP+1            ; #V2
    LDA S_BANK              ; #V2
    PHA                     ; #V2
    LDA #LOADER_BANK        ; #V2
    STA S_BANK              ; #V2
    STA BANKSEL             ; #V2
    JSR TopArtJmp           ; #V2
    JMP TopStubOut          ; #V2
; (V2) a page switch under the blank list (FINDINGS "V2: page switches #V2
; under the blank list"): MARIA draws a frame through the list it began #V2
; with, so a page switched under a scene's lists shows the new page's #V2
; graphics through them for the rest of the frame, and Frame building #V2
; the old scene's lists from the new page's tables garbles the next. #V2
; PageBlank: the blank list chosen (FrameBlank's values), Frame kept out #V2
; (S_BUSY) till PageShow; back once the NMI has shown it and a frame has #V2
; begun with it. Main program only (the NMI's Apply shows it) #V2
PageBlank:                  ; #V2
    INC S_BUSY              ; #V2
    LDA #$00                ; #V2
    STA S_PCHT              ; #V2
    STA S_PPD1              ; #V2
    STA S_PPD2              ; #V2
    LDA #<BLANK_DLL         ; #V2
    STA S_PDPPL             ; #V2
    LDA #>BLANK_DLL         ; #V2
    STA S_PDPPH             ; #V2
    LDA #$40                ; #V2
    STA S_PCTRL             ; #V2
    LDA #VBI_NMI            ; #V2
    STA S_PVBI              ; #V2
    LDA #$01                ; #V2
    STA S_PBLANK            ; #V2
    STA S_PEND              ; (last: Apply takes them all) #V2
PageBlankW1:                ; #V2
    LDA S_PEND              ; (Apply, at a vertical blank) #V2
    BNE PageBlankW1         ; #V2
    LDA S_FRAMES            ; #V2
PageBlankW2:                ; #V2
    CMP S_FRAMES            ; (the next: a whole frame of it since) #V2
    BEQ PageBlankW2         ; #V2
    RTS                     ; #V2
; PageShow: Frame back, the lists chosen afresh (A, X, Y, flags kept) #V2
PageShow:                   ; #V2
    PHP                     ; #V2
    PHA                     ; #V2
    LDA #$FF                ; #V2
    STA S_CHOSEN+1          ; #V2
    DEC S_BUSY              ; #V2
    PLA                     ; #V2
    PLP                     ; #V2
    RTS                     ; #V2


;;; FARLOAD (LoadInit) -- (LoadScene's RAM set-up, at a scene's load: in the
;;; top bank, through TopArtCall, for the fixed bank's room)
LoadInit:
    LDA #$00                ; the small-sprite block's RAM is the scene's again
    STA S_GLYIN             ; (TextInF): no fighters recorded or shown yet
    STA S_FON
    STA S_FON+1
    STA S_ZTN
    STA S_ZTN+1
    STA FR_V
    STA FR_V+1
    STA FR_V+2
    STA FR_V+3
    STA FT_SEEN
    STA FT_SEEN+1
    LDA #$01                ; (each buffer's lists made at its first flip)
    STA FT_DIRTY
    STA FT_DIRTY+1
    LDA #$00
    STA FT_USE              ; (no parts in place)
    STA FT_USE+1
    LDX #$07
LoadSceneRU:
    STA RU_OK,X
    DEX
    BPL LoadSceneRU
    STA LS_22               ; (no last emit: FtSame)
    STA LS_22+1
    STA LS_22+2
    STA LS_22+3
    STA SR_V                ; (no hit stars)
    STA SR_V+1
    STA LS_STAR
    STA LS_STAR+1
    STA AK_V                ; (no Akuma; his blits from the scene's data)
    STA AK_V+1
    STA PC_V                ; (V2: no portcullis) #V2
    STA PC_V+1              ; #V2
    LDA #$01
    STA AK_FR
    STA AK_FR+1
    LDA #$00
    STA LS_AK
    STA LS_AK+1
    LDA #$A0
    STA AK_PG0
    LDA #$BF
    STA AK_PG1
    LDA #$00
    STA FT_IN
    JSR FtBlack
    LDA #$FF
    STA S_DLIST_A+1
    STA S_DLIST_B+1
    STA S_CHOSEN+1          ; the new scene's lists: choose afresh
    LDA #$00                ; and no arrows shown in either buffer
    STA S_STP
    STA S_STP+1
    STA S_STF
    STA S_STF+1
    STA STATUS_DLA+1
    STA STATUS_DLB+1
    RTS

;;; FARART (FRec) -- the fighters' records (SysFRec: FRecF, through TopArtCall)
FRec:
    LDA S_GLYIN             ; (the tables' RAM holds the glyphs: into the
    BEQ FRecObj             ; bitmap, as before; its erase paints)
    LDX #$00
    LDA G_Z07
    CMP #$20
    BNE FRecG0
    INX
    INX
FRecG0:
    LDA G_Z2C
    BPL FRecG1
    INX
FRecG1:
    LDA #$02
    STA FT_DRW,X
    BNE FRecDone
FRecObj:
    LDX #$00
    LDA G_Z07
    CMP #$20
    BNE FRec0
    INX
FRec0:
    LDA #$01
    STA FT_SEEN,X
    STA FT_IN
    TXA
    ASL A
    TAX
    LDA G_Z2C
    BPL FRecP
    INX
    LDA G_Z4D
    BEQ FRecP
    CMP #$05
    BEQ FRecP
    LDA #$02                ; (the scene's own: Akuma, his blits captured
    STA FT_IN               ; as he draws: AkCap; his erase paints, as some
    STA FT_DRW,X            ; may not be)
    LDA #$00
    BEQ FRecV
FRecP:
    LDA G_Z20
    STA FR_20,X
    LDA G_Z21
    STA FR_21,X
    LDA G_Z22
    STA FR_22,X
    LDA G_Z50
    STA FR_50,X
    LDA G_Z3E
    STA FR_3E,X
    LDA G_Z36
    STA FR_36,X
    LDA #$01                ; (drawn as objects: its next erase paints nothing)
    STA FT_DRW,X
    LDA #$02                ; (this picture's: FtEmit makes it 1, an earlier one's)
FRecV:
    STA FR_V,X
FRecDone:
    LDX G_Z20
    LDA G_Z50
    RTS

;;; FARLOAD (FtBlack) -- (LoadScene, through TopArtCall)
; the black block (the front boxes' underlay): columns FT_BLKCOL-+FT_BLKW of the
; slice pages, all $AA (colour 2 of FT_PAL: black); the cells' object counts
; cleared. LoadScene
FtBlack:
    ; (V2: no cart RAM: only the cells' counts) #V2
    LDA #FT_BLKCOL  ; #V1
    STA ZP_P2  ; #V1
    LDA #FT_P0  ; #V1
    STA ZP_P2+1  ; #V1
FtBlk1:  ; #V1
    LDY #FT_BLKW-1  ; #V1
    LDA #$AA  ; #V1
FtBlk2:  ; #V1
    STA (ZP_P2),Y  ; #V1
    DEY  ; #V1
    BPL FtBlk2  ; #V1
    INC ZP_P2+1  ; #V1
    LDA ZP_P2+1  ; #V1
    CMP #FT_PTOP+1  ; #V1
    BNE FtBlk1  ; #V1
    LDX #FT_NCELL-1         ; and no fighter objects in either buffer's cells
    LDA #$00
FtBlk3:
    STA FC_N,X
    STA FC_N+FS_BOFF,X
    DEX
    BPL FtBlk3
    RTS

;;; FARLOAD (ResetB) -- the boot's body (Reset enters it by JMP with this bank
;;; in: the clear wipes the stack page; ResetTail, fixed, loads the scene
;;; and turns MARIA's DMA on)
ResetB:
    LDA #$00
    STA AUDV0
    STA AUDV1
    STA CTLSWA              ; the sticks are inputs
; clear console RAM $1800-$27FF with absolute stores: zero page and the
; stack are mirrors inside it, so a pointer kept in zero page would be wiped
; by its own loop
    LDA #$00
    TAX
ClrRam:
    STA $1800,X
    STA $1900,X
    STA $1A00,X
    STA $1B00,X
    STA $1C00,X
    STA $1D00,X
    STA $1E00,X
    STA $1F00,X
    STA $2000,X
    STA $2100,X
    STA $2200,X
    STA $2300,X
    STA $2400,X
    STA $2500,X
    STA $2600,X
    STA $2700,X
    INX
    BNE ClrRam
; clear cartridge RAM $4000-$7FFF  #V1
    LDA #$40  ; #V1
    STA ZP_P1+1  ; #V1
    LDA #$00  ; #V1
    STA ZP_P1  ; #V1
    TAY  ; #V1
ClrCart:  ; #V1
    STA (ZP_P1),Y  ; #V1
    INY  ; #V1
    BNE ClrCart  ; #V1
    INC ZP_P1+1  ; #V1
    LDX ZP_P1+1  ; #V1
    CPX #$80  ; #V1
    BNE ClrCart  ; #V1
ClrCart:                    ; (V2: no cart RAM to clear; the label the probes' boot gate reads) #V2
; the empty display list and the blank DLL: static, copied from ROM (the
; spare bank's) into console RAM (display lists must be in RAM)
    LDA #SPARE_BANK
    STA BANKSEL
    LDA #<IMG_SMALLDL
    STA ZP_P1
    LDA #>IMG_SMALLDL
    STA ZP_P1+1
    LDA #<SMALLDL_AT
    STA ZP_P2
    LDA #>SMALLDL_AT
    STA ZP_P2+1
    LDA #<LEN_SMALLDL
    LDX #>LEN_SMALLDL
    JSR Copy
; system state
    LDA #$0F
    STA S_CONSOL            ; XEGS console keys: none pressed
    LDA #$FF
    STA S_PORTA
    STA S_LATCH             ; no push kept
    STA S_POKEY+9           ; KBCODE: no key
    STA S_POKEY+15          ; SKSTAT: idle
    STA S_DLIST_A+1         ; neither list built yet
    STA S_DLIST_B+1
    STA S_CHOSEN+1          ; nor chosen
    LDA #<VbiDefault
    STA S_VVBLKI
    LDA #>VbiDefault
    STA S_VVBLKI+1
    LDA #<DliDefault
    STA S_VDSLST
    LDA #>DliDefault
    STA S_VDSLST+1
    LDA #$22
    STA S_SDMCTL
    STA S_DMACTL
    LDA #$40                ; the OS leaves the vertical blank enabled, and the
    STA S_NMIEN             ; game enables DLIs with LDA NMIEN / ORA #$80
; the display: a blank list until the game picks one
    LDA #>BLANK_DLL
    STA DPPH
    LDA #<BLANK_DLL
    STA DPPL
    LDA #VBI_NMI
    STA S_NMIVBI
    LDA #$01
    STA S_SHOWBLANK
    JMP ResetTail

;;; FARART (TopEmitF) -- the builder's top zone (RowsZoneEmit; the builder #V1
;;; FARPG (TopEmitF) -- (V2: a copy in every scene page, through PgBuildDll, PgTopErase) #V2
;;; runs in this bank)
TopEmitF:
    LDA S_TN
    BEQ TopEmitFEmpty
    INC TP_BLD
    JSR TopEmit
    DEC TP_BLD
    JMP RowsEmitEntry
TopEmitFEmpty:
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
    JMP RowsEmitEntry

;;; FARART (TopSky) -- (the builder's, in the same bank) #V1
;;; FARPG (TopSky) -- (V2: a copy in every scene page, through PgBuildDll, PgTopErase) #V2
; the top's sky (FINDINGS "The top rows as objects"): when the buffer being
; listed has a sky top (its background colour 2: level 1's), its list gets
; two DLIs of the port's own, counted in with the game's: on the blank line
; before the top region (its mode-8 rows or its buffer rows above FB_TOP) the
; background becomes the sky, on its last row (FB_TOP-1) black again
TopSkyGo:
    LDA #$00
    STA S_PPD1
    STA S_PPD2
    STA S_TSKY
    LDA S_TN
    BEQ TopSkyRts
    LDY #$00
    LDA S_SLOT
    BEQ TopSkyGo1
    INY
TopSkyGo1:
    LDA TOPLBG,Y
    CMP #$02
    BNE TopSkyRts
    STA S_TSKY
TopSkyRts:
    RTS
; a blank run (unflagged): flagged if the next run begins the top region
TopSkyOnRun:
    LDA S_TSKY
    BEQ TopSkyRts
    LDA S_KIND
    AND #$3F
    BNE TopSkyRts           ; (a blank run only)
    LDY #$00
    LDA (ZP_P1),Y           ; the next run
    AND #$3F
    CMP #$01
    BEQ TopSkyOnYes         ; mode-8 rows
    CMP #$02
    BNE TopSkyRts
    LDY #$02
    LDA (ZP_P1),Y
    CMP #FB_TOP
    BCS TopSkyRts
TopSkyOnYes:
    LDA S_COUNT
    BEQ TopSkyRts
    INC S_HASDLI
    DEC S_COUNT
    LDA #$80
    STA S_TSKY              ; (bit 7: the next flagged line is ours)
    RTS
TopSkyOnMark:
    CLC
    LDA S_TSKY
    BPL TopSkyRts
    LDA S_NDLI
    STA S_PPD1
    LDA #$02
    STA S_TSKY
    LDA #<TOPBLACKDL        ; its line opaque black, so the switch may land
    STA S_ROWP              ; anywhere in it
    LDA #>TOPBLACKDL
    STA S_ROWP+1
    SEC
    RTS
; a zone of buffer rows: with a sky, the top's last row a zone of its own,
; flagged (S_H, S_FLAG for it)
TopSkyOffZone:
    LDA S_TSKY
    BEQ TopSkyRts
    LDA S_ARG
    CMP #FB_TOP-1
    BEQ TopSkyOffRow
    BCS TopSkyRts           ; below the top
    CLC
    ADC S_H
    CMP #FB_TOP
    BCC TopSkyRts           ; ends above the last row
    LDA #FB_TOP-1
    SEC
    SBC S_ARG
    STA S_H                 ; to just above it
    RTS
TopSkyOffRow:
    LDA #$01
    STA S_H
    LDA #$80
    STA S_FLAG
    INC S_NDLI
    LDA S_NDLI
    STA S_PPD2
    RTS

;;; FARART (TopColours) #V1
;;; FARCOM (TopColours) -- (V2: in every scene page, after its system code) #V2
; every frame (Frame, from the game's vertical blank): the top band's
; colours as the game's colour set 0 makes them ($1125: the scheme $0F0C's
; set, less the fade $0F12): the sky (colour 2) for the DLI, and the
; converted pieces' palette (TOP_PAL1): colours 1 and 3 the band's, colour 2
; black
TopColours:
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDX G_L0F0C
    LDA G_L1197,X
    STA ZP_P1
    LDA G_L119D,X
    STA ZP_P1+1
    LDY #$00                ; set 0's colours
    LDA (ZP_P1),Y
    PHA
    INY
    LDA (ZP_P1),Y
    STA ZP_P1+1
    PLA
    STA ZP_P1
    LDY #$00
    JSR TopColour
    STA TOP_PALR
    INY
    JSR TopColour
    STA S_SKY
    INY
    JSR TopColour
    STA TOP_PALR+2
    STA TOP_PAL2R+2         ; (palette 3: black, then the game's 2 and 3)
    LDA S_SKY
    STA TOP_PAL2R+1
    LDA #$00
    STA TOP_PALR+1
    STA TOP_PAL2R
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    RTS
TopColour:
    LDA (ZP_P1),Y
    SEC
    SBC G_L0F12
    BCS TopColour1
    LDA #$00
TopColour1:
    RTS

;;; FARART (TopRefresh)
; as buffer S_SLOT (0 A, 3 B) is about to be shown (TopFlip, in the main
; program; FrameGo as it is shown, for any flip TopFlip did not see): if its
; pieces changed, its top zones' lists written again in their slots (each slot's zone as its
; list was built; the background as built: a change rebuilt the list)
TopRefresh:                 ; (the top bank in: TopRefreshF)
    LDY #$00
    LDA S_SLOT
    BEQ TopRef1
    INY
TopRef1:
    LDA TOPLD,Y
    BEQ TopRefRts
    LDA #$00
    STA TOPLD,Y
    LDA TOPLBG,Y
    CMP #$02
    BEQ TopRef2
    LDA #$00
TopRef2:
    STA S_TSKY
    LDA #$00                ; (their lists' pieces afresh, the slots'
    LDX #$00                ; ordinal)
    CPY #$00
    BEQ TopRef4
    LDA #$08
    LDX #TOPDL_N
TopRef4:
    STX TP_SO
    JSR TopSegStart
    LDA #TOPDL_N
    STA S_ER
TopRefSlot:
    LDX TP_SO
    LDA TOPZ_H,X
    BEQ TopRefNone          ; (not used)
    STA S_H
    LDA TOPZ_ARG,X
    STA S_ARG
    JSR TopEmit             ; (on to the next slot)
    JMP TopRefNext
TopRefNone:
    JSR TopNextSlot
TopRefNext:
    DEC S_ER
    BNE TopRefSlot
TopRefRts:
    RTS

;;; FAR (TopFlip)
; $B60F's first instruction (the flip and frame wait in play): the picture is
; done, and the buffer drawn ($07) is shown from the flip on, so its top
; zones' lists are written again now if its pieces changed: in the main
; program, where it costs no DLI (in the vertical blank it ran past the
; game's first DLI: FINDINGS "The top rows' flicker"). The frame routine
; keeps out meanwhile (it would build a list with the same scratch); X, Y
; and the game's $00/$01 kept; then $B60F's LDA $0AFE, its flags for the
; BNE after
TopFlip:
    TXA
    PHA
    TYA
    PHA
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    INC S_BUSY
    LDA #$00
    LDX G_Z07
    CPX #$20
    BNE TopFlip1
    LDA #$03
TopFlip1:
    STA S_SLOT
    LDA S_TN
    BEQ TopFlipFt
    LDA #<TopRefresh
    LDX #>TopRefresh
    JSR TopArtCall
TopFlipFt:
    JSR L1FlipF             ; (level 1's instances: L1Flip)
    LDA #<FtEmit            ; the fighters' objects (FINDINGS "The fighters
    LDX #>FtEmit            ; as objects: step 3")
    JSR TopArtCall
    JSR L1DoneF
    DEC S_BUSY
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    PLA
    TAY
    PLA
    TAX
TopFlipOut:
    LDA G_L0AFE
    RTS

;;; FAR (FtFixed) -- the fighters as objects: the fixed bank's part (FINDINGS
;;; "The fighters as objects: step 3")
; bank 15's fighter drawing ($A815) records the fighter for the buffer being
; drawn ($07: $20 B): its poses, column, shift, enemy type and $36 (FR_*: A's
; player, A's enemy, B's player, B's enemy); the scene code's own enemies
; ($2C negative, $4D not 0 or 5: $A827) are not. The buffer's picture has
; fighters (FT_SEEN), and one is being drawn (FT_IN, to its torso: FtEnd).
; Then the two instructions it replaced (LDX $20, LDA $50)
FRecF:                      ; (SysFRec: FRec in the top bank, X and A as it
    LDA #<FRec              ; leaves them)
    LDX #>FRec
    JSR TopArtCall
    LDX G_Z20
    LDA G_Z50
    RTS

;;; FAR (FtStars) -- (FtFixed's hit stars: a piece of their own)
; a hit star (bank 15's $B503, $B54D): its mask's blit ($B533, $B580)
; records it for the buffer being drawn ($07), as the fighters are: the big
; one ($93AB) or the small ($9490), its top row ($06, the mask's; the merged
; image's sprite is 3 below), column ($05) and shift ($10). Both its blits
; (the sprite's: the tail call, StarS) run with nothing drawn (FT_IN 1, as a
; fighter's: BlitBank), so the blitter leaves the game's zero page as it
; would. With the text up or the glyphs in, both drawn as before
StarM:
    JSR StarOff
    BNE StarMg
    JMP StarM1              ; (a piece of its own: the fixed bank's runs)
StarMg:
    JMP G_L284E
;;; FAR (StarM1) -- (the big star's record)
StarM1:
    TXA
    PHA
    LDX #$00
    LDA G_Z07
    CMP #$20
    BNE StarM2
    INX
StarM2:
    LDA #$02
    STA SR_V,X
    LDA #$01                ; (the picture has actors: the draws after are
    STA FT_SEEN,X           ; in front)
    LDA #$00
    LDY G_Z04
    CPY #$93                ; (the big one's mask: $93AB)
    BEQ StarM3
    LDA #$01
StarM3:
    STA SR_IMG,X
    LDA G_Z06
    SEC
    SBC #35
    STA SR_ROW,X
    LDA G_Z05
    STA SR_COL,X
    LDA G_Z10
    STA SR_SUB,X
    PLA
    TAX
    JMP StarBlit
;;; FAR (StarS) -- (the small star, the stars' blit)
StarS:
    JSR StarOff
    BEQ StarBlit
    JMP G_L284E
; the blit with nothing drawn (FT_IN 1: BlitBank drops it), FT_IN as it was
StarBlit:
    LDA FT_IN
    PHA
    LDA #$01
    STA FT_IN
    JSR G_L284E
    PLA
    STA FT_IN
    RTS
; (Z clear: no objects now, the text up or the glyphs in)
StarOff:
    LDA S_GLYIN
    ORA S_STORY
    ORA S_TITLEA
    ORA S_TITLEB
    RTS

;;; FAR (FtEnds) -- (FtFixed's ends and front-box records: a piece of their own)
; a fighter's last part (its torso: bank 15's tail calls at $A8B4, the
; enemy's $A940) drawn: its drawing is done (FT_IN off), so the band's draws
; after it are in front of it. The blit's A and flags kept
FtEnd:
    JSR G_L284E
    JMP FtEndDone
FtEnd2:
    JSR G_L2B8B
FtEndDone:
    PHP
    PHA
    LDA S_GLYIN
    BNE FtEnd1
    LDA #$00
    STA FT_IN
FtEnd1:
    PLA
    PLP
    RTS

;;; FAR (FtViewGone) -- the buffer L1_B's view moved (L1Flip): its fighters,
;;; hit star and Akuma from an earlier picture are gone. The XEGS scrolls
;;; nothing: a new view is a new picture, the background drawn again over
;;; the old fighters, and the game draws again only those still in view
;;; (FR_V 2). Without this, an off-screen fighter stayed where it last was:
;;; the user's ghost at the first guard's gate, and bodies moving with the
;;; camera. (The records: 0 none, 1 an earlier picture's, 2 this one's; AND
;;; #$FE clears only the 1s.) X, Y kept
FtViewGone:
    TXA
    PHA
    TYA
    PHA
    LDA L1_B
    TAX                     ; the buffer: its star, its Akuma
    ASL A
    TAY                     ; its two fighters' records
    LDA FR_V,Y
    AND #$FE
    STA FR_V,Y
    LDA FR_V+1,Y
    AND #$FE
    STA FR_V+1,Y
    LDA SR_V,X
    AND #$FE
    STA SR_V,X
    LDA AK_V,X
    AND #$FE
    STA AK_V,X
    LDA PC_V,X              ; #V2
    AND #$FE                ; #V2
    STA PC_V,X              ; #V2
    LDA #$01                ; (its objects made again)
    STA FT_DIRTY,X
    PLA
    TAY
    PLA
    TAX
    RTS
; (V2) level 2's portcullis (FINDINGS "The portcullis as one image"): #V2
; the game draws $A0FC's bar line row by row from the lintel's (row 80) #V2
; down, then one of six bottom pieces under its last; the original's #V2
; portcullis rises and drops with it. PcCap: a blit of the set's (L1Src's #V2
; L1_SRC, L1_ROW; L1_B) in scene 2: a bar line under the lintel or a #V2
; bottom piece taken as the buffer's portcullis (PC_*), C set; the #V2
; lintel's line starts it afresh and stays a shape (C clear) #V2
PcCap:                      ; #V2
    LDA G_ZD0               ; #V2
    CMP #$02                ; #V2
    BNE PcCapN              ; #V2
    LDA L1_SRC+1            ; #V2
    CMP #$A0                ; #V2
    BNE PcCapN              ; #V2
    LDY L1_B                ; #V2
    LDA L1_SRC              ; #V2
    CMP #$FC                ; #V2
    BNE PcCapT              ; #V2
    LDA L1_ROW              ; (a bar line: the last so far) #V2
    STA PC_ROW,Y            ; #V2
    LDA G_Z05               ; (and where: it scrolls in with its gate) #V2
    STA PC_COL,Y            ; #V2
    LDA G_Z10               ; #V2
    STA PC_SH,Y             ; #V2
    LDA L1_ROW              ; #V2
    CMP #81                 ; #V2
    BCS PcCapY              ; #V2
    LDA #$FF                ; (the lintel's: no bottom piece yet) #V2
    STA PC_TIP,Y            ; #V2
PcCapN:                     ; #V2
    CLC                     ; #V2
    RTS                     ; #V2
PcCapT:                     ; #V2
    LDX #PC_NTIP-1          ; #V2
PcCapT1:                    ; #V2
    CMP PcTipLo,X           ; #V2
    BEQ PcCapT2             ; #V2
    DEX                     ; #V2
    BPL PcCapT1             ; #V2
    CLC                     ; #V2
    RTS                     ; #V2
PcCapT2:                    ; #V2
    TXA                     ; #V2
    STA PC_TIP,Y            ; #V2
PcCapY:                     ; #V2
    LDA #$02                ; #V2
    STA PC_V,Y              ; #V2
    LDA #$01                ; (the picture has actors: its objects #V2
    STA FT_SEEN,Y           ; made) #V2
    SEC                     ; #V2
    RTS                     ; #V2
PcTipLo:                    ; #V2
    .byte $00, $16, $2C, $4C, $7B, $B4 ; #V2
PcRecLo:                    ; #V2
    .byte <FT_PC_0, <FT_PC_1, <FT_PC_2, <FT_PC_3, <FT_PC_4, <FT_PC_5 ; #V2
PcRecHi:                    ; #V2
    .byte >FT_PC_0, >FT_PC_1, >FT_PC_2, >FT_PC_3, >FT_PC_4, >FT_PC_5 ; #V2
; FtEmitPc: buffer S_FBUF's portcullis (drawn now or then, with its #V2
; bottom piece) as two tall images, its bars (44 rows) ending at PC_ROW #V2
; and its bottom piece under them, at column 32, their rows from 81 on #V2
; (the lintel's line is the set's); then an earlier picture's #V2
FtEmitPc:                   ; #V2
    LDX S_FBUF              ; #V2
    LDA PC_V,X              ; #V2
    BEQ FtEmitPcD           ; #V2
    LDA PC_TIP,X            ; #V2
    BMI FtEmitPcO           ; #V2
    LDA #<FT_PC_BAR         ; #V2
    STA ZP_P1               ; #V2
    LDA #>FT_PC_BAR         ; #V2
    STA ZP_P1+1             ; #V2
    TXA                     ; (its box Akuma's, 6 + buffer; its key #V2
    CLC                     ; his, 10 + buffer) #V2
    ADC #$06                ; #V2
    TAY                     ; #V2
    STY FP_REC              ; #V2
    LDA #$FF                ; #V2
    STA FR_C0,Y             ; #V2
    STA FR_R0,Y             ; #V2
    LDA #$00                ; #V2
    STA FR_C1,Y             ; #V2
    STA FR_R1,Y             ; #V2
    STA FP_NOCP             ; #V2
    STA S_FMIR              ; #V2
    TXA                     ; #V2
    CLC                     ; #V2
    ADC #$0A                ; #V2
    STA FP_CLS              ; #V2
    LDA PC_ROW,X            ; #V2
    SEC                     ; #V2
    SBC #43                 ; #V2
    STA FP_ROW              ; #V2
    JSR FtPcCol             ; #V2
    LDA #81                 ; #V2
    STA PT_T                ; #V2
    JSR FtTallC             ; #V2
    LDX S_FBUF              ; (its bottom piece, under its bars) #V2
    LDY PC_TIP,X            ; #V2
    LDA PcRecLo,Y           ; #V2
    STA ZP_P1               ; #V2
    LDA PcRecHi,Y           ; #V2
    STA ZP_P1+1             ; #V2
    LDA PC_ROW,X            ; #V2
    CLC                     ; #V2
    ADC #$01                ; #V2
    STA FP_ROW              ; #V2
    JSR FtPcCol             ; #V2
    LDA #81                 ; #V2
    STA PT_T                ; #V2
    JSR FtTallC             ; #V2
FtEmitPcO:                  ; #V2
    LDX S_FBUF              ; #V2
    LDA #$01                ; #V2
    STA PC_V,X              ; #V2
FtEmitPcD:                  ; #V2
    LDX S_FBUF              ; (the masks used: the next picture's #V2
    LDA #$00                ; fills set them again) #V2
    STA FT_ML,X             ; #V2
    STA FT_MRI,X            ; #V2
    RTS                     ; #V2
FtPcCol:                    ; (buffer X's portcullis's column and shift, as #V2
    LDA PC_COL,X            ; the game drew it; X kept) #V2
    STA FP_COL              ; #V2
    LDA PC_SH,X             ; #V2
    LSR A                   ; #V2
    STA S_FSUB              ; #V2
    RTS                     ; #V2
; (V2) an object's palette and width (A): C clear when it is 160B, #V2
; palette 0 (the heads) or 5 (the coloured parts); A kept #V2
PwIsB:                      ; #V2
    CMP #$20                ; #V2
    BCC PwIsBR              ; #V2
    PHA                     ; #V2
    AND #$E0                ; #V2
    CMP #$A0                ; #V2
    BEQ PwIsB5              ; #V2
    PLA                     ; #V2
    SEC                     ; #V2
PwIsBR:                     ; #V2
    RTS                     ; #V2
PwIsB5:                     ; #V2
    PLA                     ; #V2
    CLC                     ; #V2
    RTS                     ; #V2
;;; FAR (FgStubs) -- (a piece of their own: the fixed bank's runs)
; (a tiles set's captured fill, after the game's clip: it never reaches
; RowBase; an earlier picture's hit star it covers goes, FgRecFB)
FgRecF:
    LDA S_GLYIN
    ORA FT_IN
    BEQ FgRecFS
    RTS
FgRecFS:
    LDA S_BANK
    PHA
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    JSR FgRecFB
FgStubOut:
    PLA
    STA S_BANK
    STA BANKSEL
    RTS
FgCol:                      ; (the level-1 column routine's front box: its
    RTS                     ; call is on the path before level 1's objects,
                            ; which no scene takes: S_L1 is on in level 1)

;;; FARART (FgRecB)
; (the front boxes' recorder was here: no scene draws the bitmap any more,
; so no draw is in front of the fighters but a tiles set's front shapes)
FgRecOut:
    PLA
    TAY
    PLA
    TAX
    RTS
; FgRecF's: a fill's box (rows from $06 and $08, past its last, as L1Fill
; reads them; columns $05-$09) over the buffer's earlier hit star (FgStale's
; box 4 + buffer) or Akuma (box 6 + buffer) erases it. Not the fighters' records: level 1's fills never
; went through FgStale (its pictures as before)
FgRecFB:
    TXA
    PHA
    TYA
    PHA
    LDA G_Z06
    SEC
    SBC #$23
    BCS FgRecF1
    LDA #$00
FgRecF1:
    STA S_FMIR
    LDA G_Z08
    SEC
    SBC #$24
    BCS FgRecF2
    JMP FgRecOut            ; (wholly above the top)
FgRecF2:
    STA S_FSW
    LDA G_Z05
    CMP #40
    BCS FgRecF3             ; (its left off the screen's)
    STA S_FCOL
    LDA G_Z09
    CLC
    ADC #$01
    STA S_FTK
    LDX #$00
    LDA G_Z07
    CMP #$20
    BNE FgRecF4
    INX
FgRecF4:
    LDA SR_V,X
    CMP #$01
    BNE FgRecFA
    TXA
    CLC
    ADC #$04
    TAY
    JSR FgStaleHit
    BCC FgRecFA
    LDA #$00
    STA SR_V,X
    LDA #$01
    STA FT_DIRTY,X
FgRecFA:                    ; (and the buffer's Akuma, an earlier picture's:
    LDA AK_V,X              ; his box 6 + buffer. The room's repaint at a
    CMP #$01                ; cut erases him: FINDINGS "Akuma's body in the
    BNE FgRecF3             ; next rooms")
    TXA
    CLC
    ADC #$06
    TAY
    JSR FgStaleHit
    BCC FgRecF3
    LDA #$00
    STA AK_V,X
    LDA #$01
    STA FT_DIRTY,X
FgRecF3:
    LDA PC_V,X              ; (V2: and level 2's portcullis, an earlier #V2
    CMP #$01                ; picture's: its box Akuma's, 6 + buffer) #V2
    BNE FgRecF3P            ; #V2
    TXA                     ; #V2
    CLC                     ; #V2
    ADC #$06                ; #V2
    TAY                     ; #V2
    JSR FgStaleHit          ; #V2
    BCC FgRecF3P            ; #V2
    LDA #$00                ; #V2
    STA PC_V,X              ; #V2
    LDA #$01                ; #V2
    STA FT_DIRTY,X          ; #V2
FgRecF3P:                   ; #V2
    LDA FT_SEEN,X           ; (V2: a black fill after the fighters, #V2
    BEQ FgRecFM9            ; from a screen edge, over their rows: #V2
    LDA G_Z06               ; the buffer's mask there, FT_ML or #V2
    CMP #114+1              ; FT_MRI. The rooms' doorways hide them: #V2
    BCS FgRecFM9            ; FINDINGS "Fighters behind the #V2
    LDA G_Z08               ; doorways") #V2
    CMP #163                ; #V2
    BCC FgRecFM9            ; #V2
    LDA G_Z05               ; #V2
    BNE FgRecFM1            ; #V2
    LDA G_Z09               ; (from column 0: to its last) #V2
    CLC                     ; #V2
    ADC #$01                ; #V2
    CMP #20                 ; #V2
    BCS FgRecFM9            ; (not an edge's) #V2
    STA FT_ML,X             ; #V2
    JMP FgRecFM9            ; #V2
FgRecFM1:                   ; #V2
    CMP #20                 ; #V2
    BCC FgRecFM9            ; #V2
    LDA G_Z09               ; (to the screen's right: 40 less its #V2
    CMP #39                 ; first) #V2
    BCC FgRecFM9            ; #V2
    LDA #40                 ; #V2
    SEC                     ; #V2
    SBC G_Z05               ; #V2
    STA FT_MRI,X            ; #V2
FgRecFM9:                   ; #V2
    JMP FgRecOut

; an opaque draw (columns S_FCOL to S_FTK, rows S_FMIR-S_FSW) in buffer X  #V1
; over an earlier picture's fighter there (FR_V 1) erases it: its record  #V1
; goes, the buffer's objects are made again (FT_DIRTY). X kept  #V1
FgStale:  ; #V1
    LDA S_FLIM  ; #V1
    BMI FgStaleD            ; (see-through: nothing erased)  #V1
    TXA  ; #V1
    ASL A  ; #V1
    TAY  ; #V1
    JSR FgStale1  ; #V1
    INY  ; #V1
    JSR FgStale1  ; #V1
    LDA SR_V,X              ; and the buffer's earlier hit star  #V1
    CMP #$01  ; #V1
    BNE FgStaleA  ; #V1
    TXA  ; #V1
    CLC  ; #V1
    ADC #$04  ; #V1
    TAY  ; #V1
    JSR FgStaleHit  ; #V1
    BCC FgStaleA  ; #V1
    LDA #$00  ; #V1
    STA SR_V,X  ; #V1
    LDA #$01  ; #V1
    STA FT_DIRTY,X  ; #V1
FgStaleA:  ; #V1
    LDA AK_V,X              ; and its earlier Akuma (box 6 + buffer)  #V1
    CMP #$01  ; #V1
    BNE FgStaleD  ; #V1
    TXA  ; #V1
    CLC  ; #V1
    ADC #$06  ; #V1
    TAY  ; #V1
    JSR FgStaleHit  ; #V1
    BCC FgStaleD  ; #V1
    LDA #$00  ; #V1
    STA AK_V,X  ; #V1
    LDA #$01  ; #V1
    STA FT_DIRTY,X  ; #V1
FgStaleD:  ; #V1
    RTS  ; #V1
FgStale1:  ; #V1
    LDA FR_V,Y  ; #V1
    CMP #$01  ; #V1
    BNE FgStaleD  ; #V1
    JSR FgStaleHit  ; #V1
    BCC FgStaleD  ; #V1
    LDA #$00  ; #V1
    STA FR_V,Y  ; #V1
    LDA #$01  ; #V1
    STA FT_DIRTY,X  ; #V1
    RTS  ; #V1
; the draw over box Y (FR_C0/C1/R0/R1)? C set
FgStaleHit:
    LDA S_FCOL
    CMP FR_C1,Y
    BCS FgStaleN
    LDA FR_C0,Y
    CMP S_FTK
    BCS FgStaleN
    LDA FR_R1,Y
    CMP S_FMIR
    BCC FgStaleN
    LDA S_FSW
    CMP FR_R0,Y
    BCC FgStaleN
    SEC
    RTS
FgStaleN:
    CLC
    RTS

;;; FAR (FtFixed2)
; the common flip ($0862: its JSR $0878, the swap of $07; the title's, the
; story's, and the levels' through $0803): in play, the top rows' refresh and
; the fighters' objects for the buffer drawn (TopFlip, as at $B60F); then the
; swap
Flip0:
    LDA S_STORY             ; (in play only: the title's and story's own
    ORA S_TITLEA            ; flips, and while the bitmaps are blanked, as
    ORA S_TITLEB            ; before)
    ORA S_OBLANK
    BNE Flip0Go
    JSR TopFlip
Flip0Go:
    JMP G_L0878

; the lower-body masks the level's code draws before the fighters ($AA58's
; tail JMP $A975, the player's; $AA32's JMP $A980, the enemy's): part of
; the recorded fighter's merged lower body (an object), so not drawn; the
; scene code's own enemies ($4D not 0 or 5) and anything with the glyphs in
; as before
MaskP:
    LDA S_GLYIN
    BNE MaskP1
    RTS
MaskP1:
    JMP G_LA975
MaskE:
    LDA S_GLYIN
    BNE MaskE1
    LDA G_Z4D
    BEQ MaskE0
    CMP #$05
    BNE MaskE1
MaskE0:
    RTS
MaskE1:
    JMP G_LA980


; the colour routine's end ($1155): its loop's DEY, BPL; then the fighters'
; black palette (FT_PAL) from the same set: colour 1 as palette 1's (A, the
; last written), black, and colour 3 as palette 1's (the set's third, less
; the fade $0F12). In level 1, at the band's set (the third DLI: the count
; $0F14 3), its colours to L1_PAL too, the tiles' below the split. Y $FF on
; the way out, as the routine left it
ColTail:
    DEY
    BMI ColTailEnd
    JMP G_L1148
ColTailEnd:
    STA FT_PALR
    LDY S_L1
    BEQ ColTail4
    LDY G_L0F14
    CPY #$03
    BNE ColTail4
    LDY #$02
ColTail5:
    LDA (G_Z03),Y
    SEC
    SBC G_L0F12
    BCS ColTail6
    LDA #$00
ColTail6:
    STA L1_PALR,Y
    STA L1PE,Y              ; (V2: for the next frame's early write) #V2
    DEY
    BPL ColTail5
ColTail4:
    LDA #$00
    STA FT_PALR+1
    LDY #$02
    LDA (G_Z03),Y
    SEC
    SBC G_L0F12
    BCS ColTail3
    LDA #$00
ColTail3:
    STA FT_PALR+2
    LDY G_L0F14             ; (level 2, the sets below the top's: palette 3
    BEQ ColTailP            ; black, grey, white for the hawk, FtRowPH's;
    LDY G_ZD0               ; at the top it is the windows' black, blue,
    CPY #$02                ; white, TopColours': FINDINGS "The hawk's
    BNE ColTailN            ; blue") #V2
    BNE ColTailP  ; #V1
    STA TOP_PAL2R+2
    LDY #$01
    LDA (G_Z03),Y
    SEC
    SBC G_L0F12
    BCS ColTailQ
    LDA #$00
ColTailQ:
    STA TOP_PAL2R+1
    LDY G_L0F14             ; (the band's set: its NMI and grey for the #V2
    CPY #$03                ; next frame's early write, NmiDli) #V2
    BNE ColTailR  ; #V2
    STA P3E_G  ; #V2
    LDY S_NMICOUNT          ; (level 2: the count at the handler's end, the #V2
    STY P3E_N               ; NMI after the windows' last rows) #V2
ColTailR:  ; #V2
    LDA #$00
    STA TOP_PAL2R
    BEQ ColTailP  ; #V2
ColTailN:  ; #V2
    LDY G_L0F14             ; (another scene: the band's grey early too, in #V2
    CPY #$03                ; palettes 1, 6 and 7 only: the posts and the #V2
    BNE ColTailP            ; fighters below the top took the top's sky for #V2
    LDY #$01                ; the lines the game's handler is late; FINDINGS #V2
    LDA (G_Z03),Y           ; "Run 10") #V2
    SEC  ; #V2
    SBC G_L0F12  ; #V2
    BCS ColTailN1  ; #V2
    LDA #$00  ; #V2
ColTailN1:  ; #V2
    STA P3E_G  ; #V2
    LDY DLI_NUM  ; #V2
    STY P3E_N  ; #V2
ColTailP:
    LDY #$01                ; (V2: palette 1's grey, the fighters' in #V2
    LDA (G_Z03),Y           ; P6 and P7: FINDINGS "The fighters #V2
    SEC                     ; coloured") #V2
    SBC G_L0F12             ; #V2
    BCS ColTailG            ; #V2
    LDA #$00                ; #V2
ColTailG:                   ; #V2
    STA MP6C1               ; #V2
    STA MP7C1               ; #V2
    LDY G_L0F14             ; (the status bar's set, the sixth: palette 1's #V2
    CPY #$06                ; colours and its NMI for the next frame's #V2
    BNE ColTailS            ; early write, NmiDli; after the writes here, #V2
    LDY #$02                ; which keep their lines) #V2
ColTailS1:  ; #V2
    LDA (G_Z03),Y  ; #V2
    SEC  ; #V2
    SBC G_L0F12  ; #V2
    BCS ColTailS2  ; #V2
    LDA #$00  ; #V2
ColTailS2:  ; #V2
    STA P6E,Y  ; #V2
    DEY  ; #V2
    BPL ColTailS1  ; #V2
    LDA DLI_NUM  ; #V2
    STA P6E_N  ; #V2
ColTailS:  ; #V2
    LDY #$FF
    RTS
; (V2) the fighters' own colours, every frame (Frame), less the game's #V2
; fade: the player's P6 a black belt and a blue trim; the guard's P7 #V2
; his belt by his strength ($B0: 14 the weakest) and his trim by his #V2
; type ($3E: 7 Akuma), the strength latched when the type changes (it #V2
; drops as he falls). Their grey: ColTail #V2
FtColours:                  ; #V2
    LDA G_Z3E               ; (the guard's trim by his type, and his belt's #V2
    AND #$07                ; tips the same: the gi's highlights; the user, #V2
    TAX                     ; run 10: by strength they didn't match them) #V2
    LDA FtTrimTab,X         ; #V2
    JSR FtColF              ; #V2
    STA MP7C2               ; #V2
    STA MP7C3               ; #V2
    TAY                     ; (and for the cutscene's palette 6, below) #V2
    CPX #$07                ; (Akuma: his robe's edge darker, the user's #V2
    BNE FtColour1           ; option E: FINDINGS "Akuma's red") #V2
    LDA #$32                ; #V2
    JSR FtColF              ; #V2
    STA MP7C2               ; #V2
FtColour1:                  ; #V2
    LDA L1_WLD              ; (level 1's cutscene room in both buffers, #V2
    AND L1_WLD+1            ; world 3: no player; its guard comes in facing #V2
    CMP #$03                ; right, in the player's parts, and takes the #V2
    BNE FtColour2           ; guard's trim in palette 6 too: FINDINGS "The #V2
    STY MP6C2               ; messenger's trim") #V2
    TYA  ; #V2
    BCS FtColour3           ; (always: CMP's equal) #V2
FtColour2:                  ; #V2
    LDA #$00                ; (the player's belt: black) #V2
    STA MP6C2               ; #V2
    LDA #$86                ; (his trim: blue, the user's) #V2
    JSR FtColF              ; #V2
FtColour3:                  ; #V2
    STA MP6C3               ; #V2
    LDA #FUJI_C1            ; (Mt Fuji's palette 5 for the top: the band's #V2
    JSR FtColF              ; colour DLI makes it level 1's tiles' again; #V2
    STA MP5C1               ; FINDINGS "Mt Fuji") #V2
    LDA #FUJI_C2            ; #V2
    JSR FtColF              ; #V2
    STA MP5C2               ; #V2
    LDA #FUJI_C3            ; #V2
    JSR FtColF              ; #V2
    STA MP5C3               ; #V2
    RTS                     ; #V2
FtColF:                     ; (less the fade, not below 0) #V2
    SEC                     ; #V2
    SBC G_L0F12             ; #V2
    BCS FtColF1             ; #V2
    LDA #$00                ; #V2
FtColF1:                    ; #V2
    RTS                     ; #V2
FtTrimTab:                  ; (by type, none a belt's or the player's blue: cyan, #V2
                            ; red, lime, lilac, teal, gold, coral; 7 Akuma's blood red) #V2
    .byte $A8, $46, $D8, $6A, $B8, $1C, $36, $34 ; #V2

; A = (ZP_P1),Y in the source's bank (FT_SRCB), from the top bank's code
; (X, Y kept)
FtRead:
    LDA FT_SRCB  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    LDA (ZP_P1),Y
    PHA
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    PLA
    RTS

; (ZP_P1),0-4 in the source's bank (FT_SRCB) into FP_RB, from the top
; bank's code (X kept)
FtRead5:
    LDA FT_SRCB  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    LDY #$04
FtRead5a:
    LDA (ZP_P1),Y
    STA FP_RB,Y
    DEY
    BPL FtRead5a
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    RTS

;;; FAR (FtFixed2b) -- (FtFixed2's slice copy: a piece of its own, the fixed
;;; bank having no run for both)
; a slice's rows into the slice pages (FtPlain, from the top bank): S_FN rows
; of S_FW bytes from (ZP_P1) in bank FT_SRCB (ZP_P1 left past them), its grid
; lines from S_FL0 (line g at page FT_PTOP - g), at column A, the cell's
; other lines (S_FB0 its height) cleared; mirrored (S_FMIR bit 7): a row's bytes
; reversed, each through the mirror table. The top bank back after
FtCopy:  ; #V1
    STA ZP_P2  ; #V1
    LDA FT_SRCB  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    LDA FP_T                ; the cell's lines (S_FB0 of them) the slice #V1
    STA ZP_P2+1             ; leaves: zeros; those before it #V1
    LDX S_FL0  ; #V1
    BEQ FtClrB  ; #V1
FtClr:  ; #V1
    LDY S_FW  ; #V1
    LDA #$00  ; #V1
FtClr1:  ; #V1
    DEY  ; #V1
    STA (ZP_P2),Y  ; #V1
    BNE FtClr1  ; #V1
    DEC ZP_P2+1  ; #V1
    DEX  ; #V1
    BNE FtClr  ; #V1
FtClrB:  ; #V1
    LDA S_FL0               ; and those after it #V1
    CLC  ; #V1
    ADC S_FN  ; #V1
    STA S_FJ  ; #V1
    LDA S_FB0  ; #V1
    SEC  ; #V1
    SBC S_FJ  ; #V1
    BEQ FtClrDone  ; #V1
    BCC FtClrDone  ; #V1
    TAX  ; #V1
    LDA FP_T  ; #V1
    SEC  ; #V1
    SBC S_FJ  ; #V1
    STA ZP_P2+1  ; #V1
FtClrB1:  ; #V1
    LDY S_FW  ; #V1
    LDA #$00  ; #V1
FtClrB2:  ; #V1
    DEY  ; #V1
    STA (ZP_P2),Y  ; #V1
    BNE FtClrB2  ; #V1
    DEC ZP_P2+1  ; #V1
    DEX  ; #V1
    BNE FtClrB1  ; #V1
FtClrDone:  ; #V1
    LDA FP_T  ; #V1
    SEC  ; #V1
    SBC S_FL0  ; #V1
    STA ZP_P2+1  ; #V1
    LDA S_FN  ; #V1
    STA S_FTK  ; #V1
FtRow:  ; #V1
    LDA FP_PAIR             ; (a pair of Akuma's: FtRowP2) #V1
    BEQ FtRow0  ; #V1
    JMP FtRowP2  ; #V1
FtRow0:  ; #V1
    LDA S_FMIR              ; (a mask: FtRowK) #V1
    AND #$20  ; #V1
    BNE FtRowK  ; #V1
    BIT S_FMIR  ; #V1
    BMI FtRowM  ; #V1
    LDY S_FW  ; #V1
    DEY  ; #V1
FtRowP:  ; #V1
    LDA (ZP_P1),Y  ; #V1
    STA (ZP_P2),Y  ; #V1
    DEY  ; #V1
    BPL FtRowP  ; #V1
    BMI FtRowNext  ; #V1
FtRowM:  ; #V1
    LDA ZP_P2               ; mirrored: byte j at width - 1 - j, through #V1
    PHA                     ; ZP_P2 + width - 256 at 255 - j (Y and its #V1
    CLC                     ; complement taking turns) #V1
    ADC S_FW  ; #V1
    STA ZP_P2  ; #V1
    LDA ZP_P2+1  ; #V1
    PHA  ; #V1
    SBC #$00  ; #V1
    STA ZP_P2+1  ; #V1
    LDY #$00  ; #V1
FtRowM1:  ; #V1
    LDA (ZP_P1),Y  ; #V1
    TAX  ; #V1
    TYA  ; #V1
    EOR #$FF  ; #V1
    TAY  ; #V1
    LDA FT_MIR,X  ; #V1
    STA (ZP_P2),Y  ; #V1
    TYA  ; #V1
    EOR #$FF  ; #V1
    TAY  ; #V1
    INY  ; #V1
    CPY S_FW  ; #V1
    BNE FtRowM1  ; #V1
    PLA  ; #V1
    STA ZP_P2+1  ; #V1
    PLA  ; #V1
    STA ZP_P2  ; #V1
    JMP FtRowNext  ; #V1
; a mask's row (S_FMIR bit 5: Akuma's): a pixel 3 (the background kept) #V1
; transparent, any other black (colour 2: the AND's 1 keeps the low bit of #V1
; black or the floor's grey, both black); mirrored as FtRowM (bit 7) #V1
FtRowK:  ; #V1
    LDY S_FW  ; #V1
    DEY  ; #V1
FtRowK1:  ; #V1
    LDA (ZP_P1),Y  ; #V1
    BIT S_FMIR  ; #V1
    BPL FtRowK2  ; #V1
    TAX  ; #V1
    LDA FT_MIR,X  ; #V1
FtRowK2:  ; #V1
    STA S_FJ              ; (pixels 3: low bits where both bits are set) #V1
    LSR A  ; #V1
    AND S_FJ  ; #V1
    AND #$55  ; #V1
    ASL A  ; #V1
    EOR #$FF  ; #V1
    AND #$AA  ; #V1
    PHA  ; #V1
    BIT S_FMIR              ; (mirrored: at width - 1 - j) #V1
    BPL FtRowK3  ; #V1
    STY S_FJ  ; #V1
    LDA S_FW  ; #V1
    CLC  ; #V1
    SBC S_FJ  ; #V1
    TAY  ; #V1
    PLA  ; #V1
    STA (ZP_P2),Y  ; #V1
    LDY S_FJ  ; #V1
    JMP FtRowK4  ; #V1
FtRowK3:  ; #V1
    PLA  ; #V1
    STA (ZP_P2),Y  ; #V1
FtRowK4:  ; #V1
    DEY  ; #V1
    BPL FtRowK1  ; #V1
FtRowNext:  ; #V1
    LDA FP_PAIR  ; #V1
    BEQ FtRowNx0  ; #V1
    JSR FtPairNext  ; #V1
    JMP FtRowNext1  ; #V1
FtRowNx0:  ; #V1
    LDA ZP_P1  ; #V1
    CLC  ; #V1
    ADC S_FW  ; #V1
    STA ZP_P1  ; #V1
    BCC FtRowNext1  ; #V1
    INC ZP_P1+1  ; #V1
FtRowNext1:  ; #V1
    DEC ZP_P2+1             ; the next line: a page lower #V1
    DEC S_FTK  ; #V1
    BEQ FtRowEnd  ; #V1
    JMP FtRow  ; #V1
FtRowEnd:  ; #V1
    LDA #TOP_BANK  ; #V1
    STA S_BANK  ; #V1
    STA BANKSEL  ; #V1
    RTS  ; #V1
; a pair's row (FP_PAIR: Akuma's mask, at (G_Z14), and his sprite over it, #V1
; at (ZP_P1), row FP_RI of them; past either's rows: none): the sprite's #V1
; pixels (grey made white), else black where the mask clears (not 3), else #V1
; transparent, in the black palette; mirrored (S_FMIR bit 7) as FtRowM. #V1
; FP_PAIR 2 (the hawk's, in TOP_PAL2: black, grey, white): its pixels kept #V1
; (skin made grey), black colour 1 #V1
FtRowP2:  ; #V1
    LDY S_FW  ; #V1
    DEY  ; #V1
FtRowP3:  ; #V1
    LDA #$00                ; the sprite's byte #V1
    LDX FP_RI  ; #V1
    CPX FP_SROWS  ; #V1
    BCS FtRowP4  ; #V1
    LDA (ZP_P1),Y  ; #V1
FtRowP4:  ; #V1
    STA PT_S  ; #V1
    LDA #$FF                ; the mask's #V1
    CPX FP_MROWS  ; #V1
    BCS FtRowP5  ; #V1
    LDA (G_Z14),Y  ; #V1
FtRowP5:  ; #V1
    BIT S_FMIR  ; #V1
    BPL FtRowP6  ; #V1
    TAX  ; #V1
    LDA FT_MIR,X  ; #V1
    STA PT_M  ; #V1
    LDX PT_S  ; #V1
    LDA FT_MIR,X  ; #V1
    STA PT_S  ; #V1
    LDA PT_M  ; #V1
FtRowP6:  ; #V1
    STA PT_M                ; kept (mask 3): PT_T, both bits #V1
    LSR A  ; #V1
    AND PT_M  ; #V1
    AND #$55  ; #V1
    STA PT_T  ; #V1
    ASL A  ; #V1
    ORA PT_T  ; #V1
    STA PT_T  ; #V1
    LDA PT_S                ; the sprite's (any not 0): with them #V1
    LSR A  ; #V1
    ORA PT_S  ; #V1
    AND #$55  ; #V1
    STA PT_M  ; #V1
    ASL A  ; #V1
    ORA PT_M  ; #V1
    ORA PT_T  ; #V1
    EOR #$FF  ; #V1
    LDX FP_PAIR  ; #V1
    CPX #$02  ; #V1
    BEQ FtRowPH  ; #V1
    AND #$AA                ; black: neither #V1
    STA PT_T  ; #V1
    LDA PT_S                ; and the sprite, grey (2) made white #V1
    LSR A  ; #V1
    AND #$55  ; #V1
    ORA PT_S  ; #V1
    ORA PT_T  ; #V1
FtRowPW:  ; #V1
    PHA  ; #V1
    BIT S_FMIR              ; (mirrored: at width - 1 - j) #V1
    BPL FtRowP7  ; #V1
    STY PT_T  ; #V1
    LDA S_FW  ; #V1
    CLC  ; #V1
    SBC PT_T  ; #V1
    TAY  ; #V1
    PLA  ; #V1
    STA (ZP_P2),Y  ; #V1
    LDY PT_T  ; #V1
    JMP FtRowP8  ; #V1
FtRowP7:  ; #V1
    PLA  ; #V1
    STA (ZP_P2),Y  ; #V1
FtRowP8:  ; #V1
    DEY  ; #V1
    BMI FtRowP9  ; #V1
    JMP FtRowP3  ; #V1
; the hawk's (A: neither, both bits): black colour 1; its 3s' low bits, and #V1
; any pixel's high bit (1 and 2 grey, 3 white) #V1
FtRowPH:  ; #V1
    AND #$55  ; #V1
    STA PT_T  ; #V1
    LDA PT_S  ; #V1
    LSR A  ; #V1
    AND PT_S  ; #V1
    AND #$55  ; #V1
    ORA PT_T  ; #V1
    STA PT_T  ; #V1
    LDA PT_S  ; #V1
    ASL A  ; #V1
    ORA PT_S  ; #V1
    AND #$AA  ; #V1
    ORA PT_T  ; #V1
    JMP FtRowPW  ; #V1
FtRowP9:  ; #V1
    JMP FtRowNext  ; #V1
; a pair's next row: each image's pointer on while it has rows (FP_RI)
FtPairNext:
    LDA FP_RI
    CMP FP_SROWS
    BCS FtPairN1
    LDA ZP_P1
    CLC
    ADC S_FW
    STA ZP_P1
    BCC FtPairN1
    INC ZP_P1+1
FtPairN1:
    LDA FP_RI
    CMP FP_MROWS
    BCS FtPairN2
    LDA G_Z14
    CLC
    ADC S_FW
    STA G_Z14
    BCC FtPairN2
    INC G_Z15
FtPairN2:
    INC FP_RI
    RTS

;;; FARART (FtEmit) -- the fighters as objects: the top bank's part
; at a flip (TopFlip; S_SLOT the buffer drawn, 0 A, 3 B), each fighter
; recorded for it (FR_*) as objects: its parts' slices copied into the
; buffer's columns of the slice pages (FT_COLS each, A's then B's: FtCopy),
; an object each (FO_*: FT_FON a buffer); the front boxes recorded for it
; become the ones shown (FG_*); then its band lists are written again
; (BandRefresh). A record stays (FR_V 1: an earlier picture's) till the
; game redraws that fighter, or erases it (an opaque draw over its box:
; FgStale), or the buffer is cleared or copied (FtForget, FtCopyRec): the
; game leaves a fighter it doesn't redraw in its buffer (Akuma's cutscene
; redraws Akuma alone). A buffer with no fighter drawn and none erased is
; left as it is shown; one with only earlier fighters keeps its front boxes.
; Nothing with the text up or the glyphs in (the tables share their RAM).
; Each fighter's lower body (FtLower) and upper body (FtUpper); its box as
; its objects are made (FtObj)
FtEmit:
    LDA S_GLYIN
    ORA S_STORY
    ORA S_TITLEA
    ORA S_TITLEB
    BEQ FtEmitGo
    RTS
FtEmitGo:
    LDA ZP_P2
    PHA
    LDA ZP_P2+1
    PHA
    LDX #$00
    LDY S_SLOT
    BEQ FtEmitBuf
    INX
FtEmitBuf:
    STX S_FBUF
    LDA FT_SEEN,X           ; anything drawn or erased?
    ORA FT_DIRTY,X
    BNE FtEmitDo
    JMP FtEmitOut
FtEmitDo:
    JSR FtSame              ; as the buffer's last emit: its objects and
    BCC FtEmitDo1           ; lists stand
    LDA #$00
    STA FT_DIRTY,X
    STA FT_SEEN,X
    STA FT_IN
    TXA
    ASL A
    TAX
    LDA FR_V,X
    BEQ FtEmitDoS
    LDA #$01
    STA FR_V,X
FtEmitDoS:
    LDA FR_V+1,X
    BEQ FtEmitDoT
    LDA #$01
    STA FR_V+1,X
FtEmitDoT:
    JMP FtEmitOut
FtEmitDo1:
    LDA #$00
    STA FT_DIRTY,X
    STA S_FON,X
    LDA FT_SEEN,X
    BNE FtEmitNew
    STA FT_IN               ; (earlier fighters only: their boxes kept)
    JMP FtEmitP
FtEmitNew:
    LDA #$00
    STA FT_SEEN,X
    STA FT_IN
FtEmitP:
    LDX S_FBUF              ; the parts' columns: A's from 0 up to where B's
    BNE FtEmitPB            ; shown ones begin, B's from FT_COLS down to the
    LDA #$00                ; end of A's (AKP_COLS: FT_COLS, or AK_COLS with
    STA S_FCOL              ; the level's poses pre-cut above it, AkPre)
    LDA AKP_COLS
    SEC
    SBC FT_USE+1
    STA S_FLIM
    JMP FtEmitPC
FtEmitPB:
    LDA AKP_COLS
    STA S_FCOL
    LDA FT_USE
    STA S_FLIM
FtEmitPC:
    LDA #$00
    STA FP_PAIR
    TXA                     ; the buffer's two boxes empty (FtObj grows them)
    ASL A
    TAX
    LDA #$FF
    STA FR_C0,X
    STA FR_C0+1,X
    STA FR_R0,X
    STA FR_R0+1,X
    LDA #$00
    STA FR_C1,X
    STA FR_C1+1,X
    STA FR_R1,X
    STA FR_R1+1,X
    STA FP_PART
FtEmitPL:
    LDX S_FBUF              ; the part's first object (an upper body's: and
    LDA S_FON,X             ; after its pose mask, till FtUpper has one)
    LDY FP_PART
    STA PO_ST,Y
    CPY #$02
    BCS FtEmitPL0
    STA PO_ST+7,Y
FtEmitPL0:
    CPY #$04
    BCC FtEmitPK
    JMP FtEmitPD
FtEmitPK:
    TXA                     ; its index (FP_CLS) and record (X)
    ASL A
    ASL A
    ORA FP_PART
    STA FP_CLS
    LDA FP_PART
    AND #$01
    STA FP_K1
    TXA
    ASL A
    ORA FP_K1
    TAX
    STX FP_REC
    LDA FR_V,X
    BEQ FtEmitPNJ
    LDA FR_20,X
    CMP #42
    BCS FtEmitPNJ
    LDA FP_PART             ; its key
    CMP #$02
    BCS FtEmitPKL
    LDA FR_21,X
    CMP #38
    BCC FtEmitPKU
FtEmitPNJ:
    JMP FtEmitPNo
FtEmitPKU:
    STA FP_K1
    LDA FR_36,X
    BEQ FtEmitPK0
    LDA #$80
FtEmitPK0:
    ORA FR_3E,X
    STA FP_K2
    JMP FtEmitPK1
FtEmitPKL:
    LDA FR_20,X
    STA FP_K1
    LDA #$00
    STA FP_K2
FtEmitPK1:
    LDY FP_CLS              ; its key, for the next emit (FtSame)
    LDA FP_K1
    STA RU_K1,Y
    LDA FP_K2
    STA RU_K2,Y
    LDA #$01
    STA RU_OK,Y
    LDA FP_PART
    CMP #$02
    BCS FtEmitPL1
    JSR FtUpper
    JMP FtEmitPN
FtEmitPL1:
    JSR FtLower
    JMP FtEmitPN
FtEmitPNo:
    LDY FP_CLS              ; (none: what was there may be overwritten)
    LDA #$00
    STA RU_OK,Y
FtEmitPN:
    INC FP_PART
    JMP FtEmitPL
FtEmitPD:
    LDX S_FBUF              ; Akuma's blits, after the fighters (FtEmitAk)
    LDA AK_V,X
    STA LS_AK,X
    BEQ FtEmitPA
    JSR FtEmitAk
FtEmitPA:
    LDX S_FBUF
    LDA S_FON,X
    STA PO_ST+5
    LDA SR_V,X              ; the hit star, last (drawn over the fighters):
                            ; its merged image (FtTall, the black palette),
    STA LS_STAR,X           ; in MARIA's ROM; its box FR_C0/C1/R0/R1
    BEQ FtEmitSt9           ; 4 + buffer
    TXA
    CLC
    ADC #$04
    TAY
    STY FP_REC
    LDA #$FF
    STA FR_C0,Y
    STA FR_R0,Y
    LDA #$00
    STA FR_C1,Y
    STA FR_R1,Y
    STA FP_NOCP
    STA S_FMIR
    TXA
    CLC
    ADC #$08
    STA FP_CLS
    LDA SR_IMG,X
    BNE FtEmitSt1
    LDA #<FT_STAR_942A
    STA ZP_P1
    LDA #>FT_STAR_942A
    STA ZP_P1+1
    JMP FtEmitSt2
FtEmitSt1:
    LDA #<FT_STAR_94E6
    STA ZP_P1
    LDA #>FT_STAR_94E6
    STA ZP_P1+1
FtEmitSt2:
    LDA #ART_BANK
    STA FT_SRCB
    LDA SR_ROW,X
    STA FP_ROW
    LDA SR_COL,X
    STA FP_COL
    LDA SR_SUB,X
    LSR A
    STA S_FSUB
    JSR FtTall
FtEmitSt9:
    JSR FtEmitPc            ; (V2: level 2's portcullis, over the fighters) #V2
    LDX S_FBUF
    LDA S_FON,X
    STA PO_ST+6
    LDA S_FBUF              ; each record's place for the next (FtSame:
    ASL A                   ; LS_22 $FF none)
    TAX
    JSR FtEmitLS
    INX
    JSR FtEmitLS
    LDX S_FBUF              ; the columns the buffer's parts take
    BNE FtEmitPDB
    LDA S_FCOL
    STA FT_USE
    JMP FtEmitBx
FtEmitPDB:
    LDA AKP_COLS
    SEC
    SBC S_FCOL
    STA FT_USE+1
FtEmitBx:
FtEmitR:
    LDA S_FBUF              ; the records: an earlier picture's now
    ASL A
    TAX
    LDA FR_V,X
    BEQ FtEmitR1
    LDA #$01
    STA FR_V,X
FtEmitR1:
    LDA FR_V+1,X
    BEQ FtEmitR2
    LDA #$01
    STA FR_V+1,X
FtEmitR2:
    LDX S_FBUF
    LDA SR_V,X
    BEQ FtEmitR3
    LDA #$01
    STA SR_V,X
FtEmitR3:
    LDA #$01                ; (its next capture starts the list afresh)
    STA AK_FR,X
    LDA AK_V,X
    BEQ FtEmitR4
    LDA #$01
    STA AK_V,X
FtEmitR4:
    JSR FtSort
    JSR BandRefresh
FtEmitOut:
    PLA
    STA ZP_P2+1
    PLA
    STA ZP_P2
    RTS

; buffer S_FBUF's Akuma: each captured blit (AK_*), in order, as FtPlain
; draws a part (its image from its bank, at its row and column, mirrored or
; right-aligned as the blitter was, a mask in the black palette, a sprite
; in the scene's), copied each time; his box FR_C0/C1/R0/R1 6 + buffer
FtEmitAk:
    LDA S_FBUF
    CLC
    ADC #$06
    TAY
    STY FP_REC
    LDA #$FF
    STA FR_C0,Y
    STA FR_R0,Y
    LDA #$00
    STA FR_C1,Y
    STA FR_R1,Y
    STA FP_NOCP
    LDA S_FBUF
    CLC
    ADC #$0A
    STA FP_CLS
    LDA G_Z14               ; ($14/$15: a pair's mask pointer)
    STA FP_Z14
    LDA G_Z15
    STA FP_Z14+1
    LDA #$00                ; (the blit: on the stack)
    PHA
FtEmitAk1:
    PLA
    LDX S_FBUF
    CMP AK_N,X
    BCS FtEmitAk9
    PHA
    CPX #$00                ; (its entry)
    BEQ FtEmitAk2
    CLC
    ADC #AK_MAX
FtEmitAk2:
    TAY
    LDA AK_LO,Y
    STA ZP_P1
    LDA AK_HI,Y
    STA ZP_P1+1
    LDA AK_BK,Y
    STA FT_SRCB
    LDA AK_ROW,Y
    STA FP_ROW
    LDA AK_COL,Y
    STA FP_COL
    LDA AK_SH,Y
    LSR A
    STA S_FSUB
    LDA AK_FL,Y
    STA S_FMIR
    AND #$20                ; (a mask: black)
    BEQ FtEmitAk3  ; #V1
    BEQ FtEmitAkS           ; #V2
    JSR FtAkPair            ; (a mask and its sprite: one image, C set)
    BCC FtEmitAk4
    PLA                     ; (two blits)
    CLC
    ADC #$01
    PHA
FtEmitAk4:
    LDA #FT_PALB
    LDX FP_PAIR             ; (the hawk's pair: palette 3)
    CPX #$02  ; #V1
    BNE FtEmitAk5  ; #V1
    LDA #TOP_PAL2B  ; #V1
    BEQ FtEmitAk5           ; (V2: a mask alone: black) #V2
    LDA #$A0                ; (V2: a pair, the hawk's or Akuma's: 160B, its #V2
                            ; cells cut so: FINDINGS "The hawk in 160B", #V2
                            ; "Akuma's red") #V2
FtEmitAk5:
    LDX S_FBUF
FtEmitAk3:
    STA S_FPAL
    JSR AkLook              ; (pre-cut at the load: its objects point there)
    JSR FtPlain
    LDA #$00
    STA FP_PAIR
    STA AKP_ON
    STA FP_NOCP
    PLA
    CLC
    ADC #$01
    PHA
    JMP FtEmitAk1
FtEmitAk9:
    LDA FP_Z14
    STA G_Z14
    LDA FP_Z14+1
    STA G_Z15
    RTS
FtEmitAkS:                  ; (V2: a sprite alone: Akuma's 160B, its cells #V2
    LDA S_FMIR              ; cut so, FINDINGS "Akuma's red"; the hawk's, #V2
    AND #$10                ; flags bit 4, palette 0 as ever) #V2
    EOR #$10                ; #V2
    BEQ FtEmitAk3           ; #V2
    LDA #$A0                ; #V2
    BNE FtEmitAk3           ; #V2

;;; FARART (AkLookP) -- (Akuma's and the hawk's poses: a piece of its own, the
;;; top bank's runs are short)
; a pose of Akuma's or the hawk's pre-cut at the load (FINDINGS "Akuma and
; the hawk pre-cut at load"; akpose7800): the draw's image (ZP_P1), mask (a
; pair's $14/$15, else 0), flags (S_FMIR) and row (FP_ROW) found in the
; set's table (AKP_PL/PH: its chunks, its bank AKP_PB; its search AkFind
; there, AKP_FL/FH): its cells'
; places AKP_T/C, AKP_ON and FP_NOCP set (FtObj points its objects there, no
; copy); else AKP_ON 0 (copied as ever)
AkLook:
    LDA #$00
    STA AKP_ON
    STA AKP_K
    LDA S_L1
    BNE AkLookG
    RTS
AkLookG:
    LDA ZP_P1               ; the key
    STA AKP_KEY
    STA AKP_S
    LDA ZP_P1+1
    STA AKP_KEY+1
    STA AKP_S+1
    LDA #$00
    STA AKP_KEY+2
    STA AKP_KEY+3
    LDA FP_PAIR
    BEQ AkLook0
    LDA G_Z14
    STA AKP_KEY+2
    LDA G_Z15
    STA AKP_KEY+3
AkLook0:
    LDA S_FMIR
    STA AKP_KEY+4
    LDA FP_ROW
    STA AKP_KEY+5
    LDX L1_SET              ; the set's table: searched in its bank (AkFind,
    LDA AKP_PH,X            ; bank AK_TABB: the table read there directly)
    BEQ AkLookE
    STA AKP_P+1
    LDA AKP_PL,X
    STA AKP_P
    LDA AKP_PB,X            ; (its bank, its search's address)
    TAY
    LDA AKP_FL,X
    PHA
    LDA AKP_FH,X
    TAX
    PLA
    JSR L1Call
    LDA AKP_ON
    STA FP_NOCP
AkLookE:
    RTS
; (the table's walkers below: AkPre's, v1's only; V2 cuts the poses at the build: FINDINGS "The hardware test") #V2
; the set's (L1_SET's) table's first chunk at ZP_P1, its bank (AKP_PB) in  ; #V1
; FT_SRCB, C clear (C set: none); AkChunk: a chunk's header at ZP_P1, its  ; #V1
; poses in AKP_N, the next chunk in AKP_P (0: none), ZP_P1 past it  ; #V1
AkTab:  ; #V1
    LDX L1_SET  ; #V1
    LDA AKP_PH,X  ; #V1
    BEQ AkTabNo  ; #V1
    STA ZP_P1+1  ; #V1
    LDA AKP_PL,X  ; #V1
    STA ZP_P1  ; #V1
    LDA AKP_PB,X  ; #V1
    STA FT_SRCB  ; #V1
AkChunk:  ; #V1
    LDY #$00  ; #V1
    JSR FtRead  ; #V1
    STA AKP_N  ; #V1
    INY  ; #V1
    JSR FtRead  ; #V1
    STA AKP_P  ; #V1
    INY  ; #V1
    JSR FtRead  ; #V1
    STA AKP_P+1  ; #V1
    LDA ZP_P1  ; #V1
    CLC  ; #V1
    ADC #$03  ; #V1
    STA ZP_P1  ; #V1
    BCC AkTab1  ; #V1
    INC ZP_P1+1  ; #V1
AkTab1:  ; #V1
    CLC  ; #V1
    RTS  ; #V1
AkTabNo:  ; #V1
    SEC  ; #V1
    RTS  ; #V1
; a pose next at ZP_P1, C clear (the next chunk's when this one's are done);  ; #V1
; C set: none left  ; #V1
AkMore:  ; #V1
    LDA AKP_N  ; #V1
    BNE AkMore1  ; #V1
    LDA AKP_P+1  ; #V1
    BEQ AkTabNo  ; #V1
    STA ZP_P1+1  ; #V1
    LDA AKP_P  ; #V1
    STA ZP_P1  ; #V1
    JSR AkChunk  ; #V1
    JMP AkMore  ; #V1
AkMore1:  ; #V1
    DEC AKP_N  ; #V1
    CLC  ; #V1
    RTS  ; #V1
; the pose at ZP_P1's cells (its byte 7 the count, then T, C each) into  ; #V1
; AKP_T/C  ; #V1
AkCells:  ; #V1
    LDY #$07  ; #V1
    JSR FtRead  ; #V1
    STA AKP_SB+1            ; (the count)  ; #V1
    LDX #$00  ; #V1
AkCells1:  ; #V1
    CPX AKP_SB+1  ; #V1
    BCS AkCells2  ; #V1
    INY  ; #V1
    JSR FtRead  ; #V1
    STA AKP_T,X  ; #V1
    INY  ; #V1
    JSR FtRead  ; #V1
    STA AKP_C,X  ; #V1
    INX  ; #V1
    BNE AkCells1  ; #V1
AkCells2:  ; #V1
    RTS  ; #V1
; ZP_P1 past the pose there (8 + 2 x its cells)  ; #V1
AkNext:  ; #V1
    LDY #$07  ; #V1
    JSR FtRead  ; #V1
    ASL A  ; #V1
    CLC  ; #V1
    ADC #$08  ; #V1
    CLC  ; #V1
    ADC ZP_P1  ; #V1
    STA ZP_P1  ; #V1
    BCC AkNext1  ; #V1
    INC ZP_P1+1  ; #V1
AkNext1:  ; #V1
    RTS  ; #V1
; at a set's load (L1Load): each pose of its table cut into its cells  ; #V1
; (FtPlain in render mode, AKP_REND: FtObj copies each cell to its place  ; #V1
; and makes no object), as FtEmitAk would draw it  ; #V1
AkPre:  ; #V1
    JSR AkTab  ; #V1
    BCC AkPre1  ; #V1
    RTS  ; #V1
AkPre1:  ; #V1
    LDX L1_SET              ; (FtPlain leaves the image's bank) #V1
    LDA AKP_PB,X  ; #V1
    STA FT_SRCB  ; #V1
    JSR AkMore  ; #V1
    BCC AkPre2  ; #V1
    RTS  ; #V1
AkPre2:  ; #V1
    LDY #$00                ; the pose #V1
    JSR FtRead  ; #V1
    STA AKP_S  ; #V1
    INY  ; #V1
    JSR FtRead  ; #V1
    STA AKP_S+1  ; #V1
    INY  ; #V1
    JSR FtRead  ; #V1
    STA G_Z14  ; #V1
    INY  ; #V1
    JSR FtRead  ; #V1
    STA G_Z15  ; #V1
    INY  ; #V1
    JSR FtRead  ; #V1
    STA S_FMIR  ; #V1
    INY  ; #V1
    JSR FtRead  ; #V1
    STA FP_ROW  ; #V1
    INY  ; #V1
    JSR FtRead  ; #V1
    STA AKP_SB  ; #V1
    JSR AkCells  ; #V1
    JSR AkNext  ; #V1
    LDA ZP_P1               ; (the next pose's place) #V1
    PHA  ; #V1
    LDA ZP_P1+1  ; #V1
    PHA  ; #V1
    LDA AKP_SB              ; the draw, as FtEmitAk's: a pair's mask at #V1
    STA FT_SRCB             ; $14/$15 (FP_PAIR 1; the hawk's 2) #V1
    LDA AKP_S  ; #V1
    STA ZP_P1  ; #V1
    LDA AKP_S+1  ; #V1
    STA ZP_P1+1  ; #V1
    LDA #$00  ; #V1
    STA FP_PAIR  ; #V1
    LDA G_Z14  ; #V1
    ORA G_Z15  ; #V1
    BEQ AkPre3  ; #V1
    LDA S_FMIR  ; #V1
    AND #$10  ; #V1
    LSR A  ; #V1
    LSR A  ; #V1
    LSR A  ; #V1
    LSR A  ; #V1
    CLC  ; #V1
    ADC #$01  ; #V1
    STA FP_PAIR  ; #V1
AkPre3:  ; #V1
    LDA #$00  ; #V1
    STA FP_COL  ; #V1
    STA S_FSUB  ; #V1
    STA FP_NOCP  ; #V1
    STA AKP_K  ; #V1
    LDA #$01  ; #V1
    STA AKP_ON  ; #V1
    STA AKP_REND  ; #V1
    JSR FtPlain  ; #V1
    LDA #$00  ; #V1
    STA AKP_ON  ; #V1
    STA AKP_REND  ; #V1
    STA FP_PAIR  ; #V1
    PLA  ; #V1
    STA ZP_P1+1  ; #V1
    PLA  ; #V1
    STA ZP_P1  ; #V1
    JMP AkPre1  ; #V1

;;; FARART (FtAkPairP) -- (the fighters as objects, on)
; entry Y (a mask, set up for FtPlain: ZP_P1, FT_SRCB, FP_ROW, FP_COL) and
; the next blit, the buffer's (X), a sprite drawn the same way at the same
; place (column, row, shift, bank, kind) and as wide: a pair (C set): the
; mask's pointer to $14/$15, the sprite's to ZP_P1, its flags in S_FMIR,
; FP_PAIR 1. Else C clear, nothing changed
FtAkPair:
    LDA AK_N,X              ; (a next one?)
    STA PT_T
    TYA
    CPX #$00
    BEQ FtAkP0
    SEC
    SBC #AK_MAX
FtAkP0:
    CLC
    ADC #$01
    CMP PT_T
    BCC FtAkP1
    CLC                     ; (none)
    RTS
FtAkP1:
    LDA AK_FL+1,Y           ; a sprite, the same kind
    AND #$20
    BNE FtAkPNo
    LDA AK_FL+1,Y
    EOR AK_FL,Y
    AND #$C0
    BNE FtAkPNo
    LDA AK_COL+1,Y
    CMP AK_COL,Y
    BNE FtAkPNo
    LDA AK_ROW+1,Y
    CMP AK_ROW,Y
    BNE FtAkPNo
    LDA AK_SH+1,Y
    CMP AK_SH,Y
    BNE FtAkPNo
    LDA AK_BK+1,Y
    CMP AK_BK,Y
    BNE FtAkPNo
    TYA                     ; as wide (the headers' second bytes)
    PHA
    LDY #$01
    JSR FtRead
    STA PT_T
    PLA
    TAY
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDA AK_LO+1,Y
    STA ZP_P1
    LDA AK_HI+1,Y
    STA ZP_P1+1
    TYA
    PHA
    LDY #$01
    JSR FtRead
    STA PT_S
    PLA
    TAY
    LDA PT_S
    CMP PT_T
    BNE FtAkPNo2
    PLA                     ; the pair: the mask's at $14/$15
    STA G_Z15
    PLA
    STA G_Z14
    LDA AK_FL+1,Y
    STA S_FMIR
    AND #$10                ; (1; the hawk's 2: FtRowPH, TOP_PAL2)
    LSR A
    LSR A
    LSR A
    LSR A
    ADC #$01
    STA FP_PAIR
    SEC
    RTS
FtAkPNo2:
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
FtAkPNo:
    CLC
    RTS

; record X's place as emitted (LS_22, LS_50; LS_22 $FF: none). X kept
FtEmitLS:
    LDA FR_V,X
    BNE FtEmitLS1
    LDA #$FF
    STA LS_22,X
    RTS
FtEmitLS1:
    LDA FR_22,X
    STA LS_22,X
    LDA FR_50,X
    STA LS_50,X
    RTS

; buffer X's picture as its last emit (C set): its front boxes the shown ones
; (or none recorded), each record there as then (none, or at the same place
; with its parts in place from then: RU_*, whole). X kept
FtSame:
    LDA S_L1                ; (level 1's scenery changed: made again)
    BEQ FtSame0
    LDA L1_DIRTY,X
    BNE FtSmNoA
FtSame0:
    LDA SR_V,X              ; (a hit star or Akuma, now or then: made again)
    ORA LS_STAR,X
    ORA AK_V,X
    ORA LS_AK,X
    ORA PC_V,X              ; (V2: level 2's portcullis) #V2
    BNE FtSmNoA
    BEQ FtSmRec             ; (no front boxes to compare any more)
FtSmNoA:
    CLC
    RTS
FtSmRec:
    LDA #$00                ; each record (S_FJ its slot)
    STA S_FJ
FtSmR1:
    TXA
    ASL A
    ORA S_FJ
    TAY
    LDA FR_V,Y
    BNE FtSmR2
    LDA LS_22,Y             ; none: none then
    CMP #$FF
    BNE FtSmNo
    BEQ FtSmR9
FtSmR2:
    LDA LS_22,Y
    CMP FR_22,Y
    BNE FtSmNo
    LDA LS_50,Y
    CMP FR_50,Y
    BNE FtSmNo
    LDA FR_36,Y             ; its upper body's key (FtEmit's)
    BEQ FtSmR3
    LDA #$80
FtSmR3:
    ORA FR_3E,Y
    STA FP_K2
    LDA FR_21,Y
    STA FP_K1
    LDA FR_20,Y
    PHA
    TXA                     ; (its index: buffer * 4 + slot)
    ASL A
    ASL A
    ORA S_FJ
    TAY
    PLA
    STA S_FTK               ; (its lower body's key)
    LDA RU_OK,Y
    BEQ FtSmNo
    LDA RU_K1,Y
    CMP FP_K1
    BNE FtSmNo
    LDA RU_K2,Y
    CMP FP_K2
    BNE FtSmNo
    LDA RU_OK+2,Y           ; its lower body's
    BEQ FtSmNo
    LDA RU_K1+2,Y
    CMP S_FTK
    BNE FtSmNo
    LDA RU_K2+2,Y
    BNE FtSmNo
FtSmR9:
    INC S_FJ
    LDA S_FJ
    CMP #$02
    BCC FtSmR1
    SEC
    RTS
FtSmNo:
    CLC
    RTS

; a fighter's lower body (record X; odd: the enemy): its pose's part (FT_LOW*,
; mirrored FT_LOWM*: pre-cut in MARIA's ROM, fighters7800.py) as objects
; (FtPart). The sprite's column is $22 + $A054,pose (the enemy's $22 less
; it); it is drawn mirrored for the enemy or for a pose with $A2BE set, not
; both; the player's box starts at the column, the enemy's ends there. x is
; a slice's first shown byte's column x 4 plus the pixel (the shift's
; eighths / 2)
FtLower:
    STX S_FX
    LDY FR_20,X
    CPY #42
    BCC FtLow0
    RTS
FtLow0:
    LDA #$00                ; (S_FMIR bit 7 mirrored, bit 6 the box ends at
    STA S_FMIR              ; the column)
    LDA G_LA2BE,Y
    BEQ FtLow1
    LDA #$80
    STA S_FMIR
FtLow1:
    LDA G_LA054,Y
    STA S_FBOX
    TXA
    LSR A
    BCS FtLowE
    LDA FR_22,X
    CLC
    ADC S_FBOX
    JMP FtLow2
FtLowE:
    LDA S_FMIR
    EOR #$C0
    STA S_FMIR
    LDA FR_22,X
    SEC
    SBC S_FBOX
FtLow2:
    STA S_FBOX              ; the sprite's column
    LDA FR_50,X
    LSR A
    STA S_FSUB              ; and pixel
    BIT S_FMIR
    BMI FtLowM
    LDA FT_LOWLO,Y
    STA ZP_P1
    LDA FT_LOWHI,Y
    STA ZP_P1+1
    JMP FtPart
FtLowM:
    LDA FT_LOWMLO,Y
    STA ZP_P1
    LDA FT_LOWMHI,Y
    STA ZP_P1+1
    JMP FtPart

; a pre-cut part (its record at (ZP_P1) in the art bank: fighters7800.py;
; its slices' data in MARIA's ROM, FINDINGS "BankSet step 1: the fighters'
; parts") as objects: its box's column S_FBOX (S_FMIR bit 6: where the box
; ends) and pixel S_FSUB; each slice at the box's column plus its offset,
; in its cell, palette and width, its data's address and page from the
; record (FtObjV)
FtPart:
    LDA #ART_BANK
    STA FT_SRCB
    LDY #$00
    JSR FtRead
    STA S_FSW               ; the box's width
    INY
    JSR FtRead
    STA S_FCNT              ; its slices
    BIT S_FMIR
    BVC FtPart1
    LDA S_FBOX
    SEC
    SBC S_FSW
    CLC
    ADC #$01
    STA S_FBOX
FtPart1:
    LDA ZP_P1
    CLC
    ADC #$02
    STA ZP_P1
    BCC FtPartSl
    INC ZP_P1+1
FtPartSl:
    LDA S_FCNT
    BNE FtPartS1
    RTS
FtPartS1:
    DEC S_FCNT
    JSR FtRead5             ; cell | palette, offset, width, address, page
    LDA FP_RB
    AND #$0F
    STA S_FZ
    LDA FP_RB
    AND #$E0
    STA S_FPAL
    LDA FP_RB+1
    CLC
    ADC S_FBOX
    STA S_FZR
    LDA FP_RB+2
    STA S_FW
    LDA FP_RB+3
    STA FP_SCOL
    LDA FP_RB+4
    STA FP_T
    LDA ZP_P1
    CLC
    ADC #$05
    STA ZP_P1
    BCC FtPartS2
    INC ZP_P1+1
FtPartS2:
    JSR FtObjV
    JMP FtPartSl

; a tall image (its record at (ZP_P1) in the art bank: its box's width,
; rows, palette, address, page; its rows in MARIA's ROM, row r at the page
; less r, zero rows around it) as a fighter's part: its top row FP_ROW, its
; box's column FP_COL (S_FMIR bit 6: where the box ends) and pixel S_FSUB.
; An object, its whole width, for each of the band's cells its rows cross,
; its page for the cell's line 0 the image's less the cell's first row's
; distance below the image's top (FtObjV)
FtTall:
    LDA #FB_TOP             ; (V2: its rows from PT_T's on, FtTallC's; #V2
    STA PT_T                ; the band's top) #V2
FtTallC:                    ; #V2
    LDA #ART_BANK
    STA FT_SRCB
    JSR FtRead5
    LDA FP_RB
    STA S_FW
    LDA FP_RB+2
    STA S_FPAL
    LDA FP_ROW
    CLC
    ADC FP_RB+1
    STA FP_END              ; past its last row
    LDA FP_COL
    BIT S_FMIR
    BVC FtTall1
    SEC
    SBC S_FW
    CLC
    ADC #$01
FtTall1:
    STA FP_COL
    LDA FP_ROW
    CMP #FB_TOP  ; #V1
    CMP PT_T                ; #V2
    BCS FtTallR
    LDA #FB_TOP             ; (its rows above the band passed over) #V1
    LDA PT_T                ; (its rows above the clip passed over) #V2
FtTallR:
    CMP FP_END
    BCS FtTallD
    CMP #BAND_ZEND+1
    BCS FtTallD             ; below the band's cells
    SEC
    SBC #FB_TOP
    TAY
    LDA FT_ROWCELL,Y
    TAY
    STY S_FZ
    LDA FP_RB+4
    CLC
    ADC FP_ROW
    SEC
    SBC FT_CELLROW,Y
    STA FP_T
    LDA FT_CELLROW,Y        ; (the next row: the cell's end)
    CLC
    ADC FT_CELLH,Y
    PHA
    LDA FP_RB+3
    STA FP_SCOL
    LDA FP_COL
    STA S_FZR
    JSR FtObjV
    PLA
    JMP FtTallR
FtTallD:
    RTS

; the buffer's objects sorted by grid cell, a cell's black ones (FT_PAL)
; first: their indexes into FS_I (page $7B; B's +$80), with each cell's
; first (FC_START) and count (FC_N): a zone's list copies its cell's
; straight (BandWrite)
FtSort:
    LDA #$00
    LDY S_FBUF
    BEQ FtSort0
    LDA #FS_BOFF
FtSort0:
    STA S_FTK               ; the page's half
    TAX
    LDY #FT_NCELL
    LDA #$00
FtSort1:
    STA FC_N,X
    STA FC_CUR,X            ; (first the cell's black ones: their count)
    INX
    DEY
    BNE FtSort1
    LDA #$00                ; the buffer's objects: S_FJ to S_FN
    LDY S_FBUF
    BEQ FtSort2
    LDA #FO_BOFF            ; (B's objects: over A's, one copy)
FtSort2:
    STA S_FJ
    STA FP_OBASE
    CLC
    ADC S_FON,Y
    STA S_FN
    LDA PO_ST+4             ; (Akuma's first, then the star's: their objects
    CLC                     ; all go after the cell's others, black or not)
    ADC FP_OBASE
    STA S_FL0
    LDY S_FJ                ; a cell's count, and its black ones'
FtSort3:
    CPY S_FN
    BCS FtSort4
    LDA FO_CELL,Y
    CLC
    ADC S_FTK
    TAX
    INC FC_N,X
    CPY S_FL0
    BCS FtSort3A
    LDA FO_PW,Y
    AND #$E0
    CMP #FT_PALB
    BNE FtSort3A
    INC FC_CUR,X
FtSort3A:
    INY
    BNE FtSort3
FtSort4:
    LDX S_FTK               ; its first: the counts before it; the next
    LDA #$00                ; places, the black ones' from there (FC_CUR)
    STA S_FL0               ; and the others' after them (in page $7B's
    LDY #FT_NCELL           ; tail, the band lists' later: BANDX_A,X)
FtSort5:
    LDA S_FL0
    STA FC_START,X
    CLC
    ADC FC_CUR,X
    STA BANDX_A,X
    LDA S_FL0
    STA FC_CUR,X
    CLC
    ADC FC_N,X
    STA S_FL0
    INX
    DEY
    BNE FtSort5
; placed, a range at a time: the player's pose mask, its lower body, the
; rest of its upper body, the enemy's the same, Akuma's blits, the hit star
; (later ones drawn over earlier ones, as the game drew them: bank 15 draws
; the pose mask before the legs, FINDINGS "The belt's black rectangle"); a
; cell's black ones (FT_PAL) first, but Akuma's and the star's after all
; the others, in their own order
    LDA #$00
    STA FP_PI
FtPlaceQ:
    LDY FP_PI
    CPY #$08
    BCS FtPlace3
    LDX FT_PORDS,Y
    LDA PO_ST,X
    CLC
    ADC FP_OBASE
    STA S_FJ
    LDX FT_PORDE,Y
    LDA PO_ST,X
    CLC
    ADC FP_OBASE
    STA S_FN
    LDY S_FJ
FtPlace1:
    CPY S_FN
    BCS FtPlace2
    LDA FO_CELL,Y
    CLC
    ADC S_FTK
    TAX
    LDA FP_PI               ; (Akuma's, the hit star: after the others)
    CMP #$06
    BCS FtPlaceC
    LDA FO_PW,Y
    AND #$E0
    CMP #FT_PALB
    BNE FtPlaceC
    LDA FC_CUR,X
    INC FC_CUR,X
    JMP FtPlaceS
FtPlaceC:
    LDA BANDX_A,X
    INC BANDX_A,X
FtPlaceS:
    CLC                     ; (its place: its index)
    ADC S_FTK
    TAX
    TYA
    STA FS_I,X
    INY
    BNE FtPlace1
FtPlace2:
    INC FP_PI
    JMP FtPlaceQ
FtPlace3:
    RTS
; the ranges, from PO_ST index FT_PORDS to FT_PORDE: the player's pose
; mask, its lower body, the rest of its upper; the enemy's the same; Akuma's
; blits; the hit star
FT_PORDS:
    .byte 0, 2, 7, 1, 3, 8, 4, 5
FT_PORDE:
    .byte 7, 3, 1, 8, 4, 2, 5, 6

; a fighter's upper body (record X; odd: the enemy), as bank 15 draws it
; ($A815-$AACD): from a base (column $22 + $A150,lower pose, eighths $50 +
; $A17A,pose carried; the enemy's $22 and $50 less them, borrowed), by the
; upper pose ($21, Y): its pose mask ($9A2A for 6 and $14-$1D, 15 rows down
; at the base + $2C; $9A18 for 7, $0A-$0D and $27, 22 rows down at the base:
; FT_PM_*), its head (by $A1A4,Y: 8 and 9 its images 1 and 2; else image 0
; nudged that many eighths, the enemy's less, with the head mask's black: at
; the base + $A1DA,Y, row $A200,Y; the enemy's, or the player's with $36
; set, the type's ($3E) image 2 rows up and $2C less), and its torso
; ($A226/$A24C,Y at the base + $A272,Y, row $A298,Y). The enemy's parts are
; drawn mirrored, each box ending at its column (and less, not plus); a row
; is the table's + $72 - 35. All from MARIA's ROM (FtPart, FtTall)
FtUpper:
    STX S_FX
    LDY FR_20,X
    CPY #42
    BCC FtUp0
    RTS
FtUp0:
    TXA
    LSR A
    BCS FtUpE
    LDA FR_22,X
    CLC
    ADC G_LA150,Y
    STA FP_BCOL
    LDA FR_50,X
    CLC
    ADC G_LA17A,Y
    CMP #$08
    BCC FtUp1
    SBC #$08
    INC FP_BCOL
    JMP FtUp1
FtUpE:
    LDA FR_22,X
    SEC
    SBC G_LA150,Y
    STA FP_BCOL
    LDA FR_50,X
    SEC
    SBC G_LA17A,Y
    BPL FtUp1
    CLC
    ADC #$08
    DEC FP_BCOL
FtUp1:
    STA FP_BSUB
    LDA FR_21,X
    CMP #38
    BCC FtUp2
    RTS
FtUp2:
    STA FP_UY
    LDA #$00                ; the enemy's: mirrored
    STA S_FMIR
    TXA
    LSR A
    BCC FtUp3
    LDA #$C0                ; (and its boxes end at their columns)
    STA S_FMIR
FtUp3:
    LDA #ART_BANK
    STA FT_SRCB
    LDA FP_BSUB
    LSR A
    STA S_FSUB
; the pose mask
    LDA FP_UY
    CMP #$06
    BEQ FtUpPA
    CMP #$14
    BCC FtUpP1
    CMP #$1E
    BCC FtUpPA
FtUpP1:
    CMP #$07
    BEQ FtUpPB
    CMP #$27
    BEQ FtUpPB
    CMP #$0A
    BCC FtUpHead
    CMP #$0E
    BCS FtUpHead
FtUpPB:
    LDA #<FT_PM_9A18        ; $9A18: 22 rows down, at the base
    STA ZP_P1
    LDA #>FT_PM_9A18
    STA ZP_P1+1
    BIT S_FMIR
    BPL FtUpPB1
    LDA #<FT_PM_9A18M
    STA ZP_P1
    LDA #>FT_PM_9A18M
    STA ZP_P1+1
FtUpPB1:
    LDA FP_BCOL
    JMP FtUpP2
FtUpPA:
    LDA #<FT_PM_9A2A        ; $9A2A: 15 rows down, at the base + $2C (the
    STA ZP_P1               ; player's 1, the enemy's -1)
    LDA #>FT_PM_9A2A
    STA ZP_P1+1
    LDA FP_BCOL
    CLC
    ADC #$01
    BIT S_FMIR
    BPL FtUpP2
    LDA #<FT_PM_9A2AM
    STA ZP_P1
    LDA #>FT_PM_9A2AM
    STA ZP_P1+1
    LDA FP_BCOL
    SEC
    SBC #$01
FtUpP2:
    STA S_FBOX              ; (pre-cut at its rows: the black one)
    JSR FtPart
; the head: its image, nudge, column and pixel
FtUpHead:
    LDA S_FX                ; (its first object after the pose mask: PO_ST
    AND #$01                ; 7 + slot, FtPlace)
    TAY
    LDX S_FBUF
    LDA S_FON,X
    STA PO_ST+7,Y
    LDX S_FX
    LDY FP_UY
    LDA G_LA1A4,Y
    CMP #$08
    BCC FtUpH0
    SBC #$07                ; (C set) images 1, 2: no mask, no nudge
    STA FP_HI
    LDA #$00
    STA FP_HV
    BEQ FtUpH1
FtUpH0:
    STA FP_HV
    LDA #$00
    STA FP_HI
FtUpH1:
    LDA FP_BCOL
    STA FP_HCOL
    LDA FP_BSUB
    BIT S_FMIR
    BMI FtUpH2
    CLC
    ADC FP_HV
    CMP #$08
    BCC FtUpH3
    SBC #$08
    INC FP_HCOL
    JMP FtUpH3
FtUpH2:
    SEC
    SBC FP_HV
    BPL FtUpH3
    CLC
    ADC #$08
    DEC FP_HCOL
FtUpH3:
    STA FP_HSUB
    LDA FP_HCOL             ; + $A1DA (the enemy's: less)
    BIT S_FMIR
    BMI FtUpH4
    CLC
    ADC G_LA1DA,Y
    JMP FtUpH5
FtUpH4:
    SEC
    SBC G_LA1DA,Y
FtUpH5:
    STA FP_HCOL
    LDA FP_HSUB
    LSR A
    STA S_FSUB
; the head (image 0 with its mask's black, in 160B: fighters7800): the
; player's own image, or the type's 2 rows up and $2C less (the player's 1,
; the enemy's -1)
FtUpHC:
    LDX S_FX
    LDY FP_UY
    LDA G_LA200,Y
    CLC
    ADC #79
    STA FP_ROW
    LDA FP_HCOL
    STA FP_COL
    LDA FP_HI               ; its image's index: the player's 0-2, a type's
    STA FP_HV               ; 3 + 3 type + 0-2
    TXA
    LSR A
    BCS FtUpHT
    LDA FR_36,X
    BEQ FtUpHI
    DEC FP_COL              ; (the player's $2C: 1)
    JMP FtUpHT1
FtUpHT:
    INC FP_COL              ; (the enemy's: -1)
FtUpHT1:
    DEC FP_ROW
    DEC FP_ROW
    LDA FR_3E,X
    CMP #$07
    BCS FtUpTorso
    STA FP_HV
    ASL A
    CLC
    ADC FP_HV
    CLC
    ADC #$03
    CLC
    ADC FP_HI
    STA FP_HV
FtUpHI:
    LDX G_ZD0               ; its image by scene (FT_HVAR: 24 a scene, $FF
    LDA FT_HV24,X           ; none; FT_HT*: its record, the mirrored one's
    CLC                     ; the next)
    ADC FP_HV
    TAY
    LDA FT_HVAR,Y
    CMP #$FF
    BEQ FtUpTorso
    TAY
    LDA FT_HTLO,Y
    STA ZP_P1
    LDA FT_HTHI,Y
    STA ZP_P1+1
    BIT S_FMIR
    BPL FtUpHI1
    LDA ZP_P1
    CLC
    ADC #$05
    STA ZP_P1
    BCC FtUpHI1
    INC ZP_P1+1
FtUpHI1:
    JSR FtTall
; the torso, at the base (unnudged): pre-cut at its rows (FT_TOR*,
; mirrored FT_TORM*)
FtUpTorso:
    LDY FP_UY
    LDA FP_BCOL
    BIT S_FMIR
    BMI FtUpT1
    CLC
    ADC G_LA272,Y
    STA S_FBOX
    LDA FT_TORLO,Y
    STA ZP_P1
    LDA FT_TORHI,Y
    STA ZP_P1+1
    JMP FtUpT2
FtUpT1:
    SEC
    SBC G_LA272,Y
    STA S_FBOX
    LDA FT_TORMLO,Y
    STA ZP_P1
    LDA FT_TORMHI,Y
    STA ZP_P1+1
FtUpT2:
    LDA FP_BSUB
    LSR A
    STA S_FSUB
    JMP FtPart

; a plain image (rows, width, the rows) at (ZP_P1) in bank FT_SRCB as a
; fighter's part: its top row FP_ROW, its box's column FP_COL (mirrored,
; S_FMIR: where the box ends) and pixel S_FSUB, palette S_FPAL: its rows in
; the band cut at the grid's cells, each piece an object (FtObj)
FtPlain:
    LDY #$00
    JSR FtRead
    STA FP_END              ; (its rows)
    STA FP_SROWS
    INY
    JSR FtRead
    STA S_FW
    LDA ZP_P1
    CLC
    ADC #$02
    STA ZP_P1
    BCC FtPlA
    INC ZP_P1+1
FtPlA:
    LDA FP_PAIR             ; a pair: the mask's rows too (FP_END the more),
    BEQ FtPl0               ; past its header; FP_RI its first
    LDA #$00
    STA FP_RI
    LDA G_Z14
    PHA
    LDA G_Z15
    PHA
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDA G_Z14
    STA ZP_P1
    LDA G_Z15
    STA ZP_P1+1
    LDY #$00
    JSR FtRead
    STA FP_MROWS
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    PLA
    STA G_Z15
    PLA
    CLC
    ADC #$02
    STA G_Z14
    BCC FtPlB
    INC G_Z15
FtPlB:
    LDA FP_MROWS
    CMP FP_END
    BCC FtPl0
    STA FP_END
FtPl0:
    BIT S_FMIR              ; (bit 6: its column the right byte's)
    BVC FtPl1
    LDA FP_COL
    SEC
    SBC S_FW
    CLC
    ADC #$01
    STA FP_COL
FtPl1:
    LDA FP_ROW
    CLC
    ADC FP_END
    STA FP_END              ; past its last row
FtPlRow:
    LDA FP_ROW
    CMP FP_END
    BCS FtPlDone
    CMP #BAND_ZEND+1
    BCS FtPlDone            ; below the band's cells
    CMP #FB_TOP
    BCS FtPlCell
    INC FP_ROW              ; above the band: passed over
    LDA FP_PAIR
    BEQ FtPlR1
    JSR FtPairNext
    JMP FtPlRow
FtPlR1:
    LDA ZP_P1
    CLC
    ADC S_FW
    STA ZP_P1
    BCC FtPlRow
    INC ZP_P1+1
    JMP FtPlRow
FtPlCell:
    LDA FP_ROW              ; its cell (FT_ROWCELL: the band's rows')
    SEC
    SBC #FB_TOP
    TAY
    LDA FT_ROWCELL,Y
    TAY
FtPlC2:
    STY S_FZ
    LDA FP_ROW
    SEC
    SBC FT_CELLROW,Y
    STA S_FL0
    LDA FT_CELLROW,Y        ; its rows: to the cell's end or the image's
    CLC
    ADC FT_CELLH,Y
    CMP FP_END
    BCC FtPlC3
    LDA FP_END
FtPlC3:
    SEC
    SBC FP_ROW
    STA S_FN
    CLC
    ADC FP_ROW
    PHA                     ; (the next row)
    LDA FP_COL
    STA S_FZR
    JSR FtObj
    PLA
    STA FP_ROW
    JMP FtPlRow
FtPlDone:
    RTS

; a part's slice as an object (FtLower, FtPlain): S_FN rows of S_FW bytes from
; (ZP_P1) (left past them), grid cell S_FZ from its line S_FL0, at column
; S_FZR (signed) and pixel S_FSUB, palette S_FPAL (bit 7: the black one;
; bit 6: TOP_PAL2), mirrored S_FMIR. Its columns in the slice pages: A's next up from S_FCOL,
; B's next down, within S_FLIM (no room: the part not whole, RU_OK). Copied
; there (FtCopy) unless already in place (FP_NOCP), whether shown or not, so
; a part's columns are the same wherever it stands. Its object is cut to
; columns 0-39 as the blitter cuts its draws (the bytes left of 0 and from
; 40 on are not drawn), and made (FO_*) if any byte shows
FtObj:
    LDA AKP_ON              ; (a pose pre-cut at the load, AkLook, AkPre: its
    BEQ FtObj0              ; cell's place, AKP_T/C, line g at T - g)  #V1
    BEQ FtObjNR             ; (V2: every pose pre-cut; none: not shown) #V2
    LDX AKP_K
    INC AKP_K
    LDA AKP_T,X
    STA FP_T
    LDA AKP_C,X
    STA FP_SCOL
    JMP FtObjCp
FtObj0:  ; #V1
    LDA #FT_PTOP            ; (the slice pages: line g at FT_PTOP - g)  #V1
    STA FP_T  ; #V1
    LDA S_FBUF  ; #V1
    BNE FtObjB  ; #V1
    LDA S_FCOL              ; A's: up  #V1
    STA FP_SCOL  ; #V1
    CLC  ; #V1
    ADC S_FW  ; #V1
    BCS FtObjNR  ; #V1
    CMP S_FLIM  ; #V1
    BEQ FtObjA1  ; #V1
    BCS FtObjNR  ; #V1
FtObjA1:  ; #V1
    STA S_FCOL  ; #V1
    JMP FtObjCp  ; #V1
FtObjB:  ; #V1
    LDA S_FCOL              ; B's: down  #V1
    SEC  ; #V1
    SBC S_FW  ; #V1
    BCC FtObjNR  ; #V1
    CMP S_FLIM  ; #V1
    BCC FtObjNR  ; #V1
    STA S_FCOL  ; #V1
    STA FP_SCOL  ; #V1
FtObjCp:
    LDA FP_NOCP
    BNE FtObjNC
    LDY S_FZ                ; the cell's height (the copy clears its lines)
    LDA FT_CELLH,Y
    STA S_FB0
    LDA FP_SCOL
    JSR FtCopy              ; its rows, at its column #V1
    LDA AKP_REND            ; (the load's cutting: no object)
    BEQ FtObjCp1
    RTS
FtObjCp1:
    JMP FtObjV
FtObjNR:
    LDY FP_CLS              ; (no room: the part isn't whole, nor this shown)
    LDA #$00
    STA RU_OK,Y
    JMP FtObjSkip
FtObjNC:
    JSR FtObjSkip
FtObjV:
    LDX S_FBUF              ; (V2: the buffer's masks: from FT_ML to #V2
    LDA S_FSUB              ; before 40 - FT_MRI; shifted right, a byte #V2
    BEQ FtObjV0             ; less: its last byte's pixels carried past the #V2
    LDA FT_MRI,X            ; mask's edge, past the doorway's outer post, #V2
    BEQ FtObjV1             ; Akuma's: FINDINGS "Run 10") #V2
    CLC                     ; #V2
    ADC #$01                ; #V2
    BNE FtObjV1             ; #V2
FtObjV0:                    ; #V2
    LDA FT_MRI,X            ; #V2
FtObjV1:                    ; #V2
    STA MRI_E               ; #V2
    LDA S_FZR               ; #V2
    BMI FtObjCL             ; #V2
    CLC                     ; #V2
    ADC MRI_E               ; #V2
    CMP #40                 ; #V2
    BCC FtObjK2             ; #V2
    RTS                     ; #V2
FtObjK2:                    ; #V2
    LDA S_FZR               ; (left of FT_ML: those bytes cut) #V2
    SEC                     ; #V2
    SBC FT_ML,X             ; #V2
    BCS FtObjK1             ; #V2
    EOR #$FF                ; #V2
    CLC                     ; #V2
    ADC #$01                ; #V2
    JMP FtObjCW             ; #V2
    LDA S_FZR               ; shown? #V1
    BMI FtObjCL  ; #V1
    CMP #40  ; #V1
    BCC FtObjK1             ; from column 40 on: none shown #V1
    RTS  ; #V1
FtObjK1:
    LDA #$00
    BEQ FtObjCK
FtObjCL:
    EOR #$FF                ; left of column 0: those bytes cut
    CLC
    ADC #$01
    CLC                     ; (V2: and FT_ML's) #V2
    ADC FT_ML,X             ; #V2
FtObjCW:                    ; #V2
    CMP S_FW
    BCC FtObjCK
    RTS
FtObjCK:
    STA S_FOV
    LDX S_FBUF              ; room in the buffer's objects
    LDA S_FON,X
    CMP #FT_FON
    BCC FtObjK4
    RTS
FtObjK4:
    INC S_FON,X
    CPX #$00
    BEQ FtObjO
    CLC
    ADC #FO_BOFF            ; (B's: over A's)
FtObjO:
    TAY                     ; (the object)
    LDA FP_T
    STA FO_HB,Y
    LDA S_FOV
    JSR FtObjDb
    CLC
    ADC FP_SCOL
    STA FO_LO,Y             ; its first shown byte
    LDA S_FZ
    STA FO_CELL,Y
    LDA S_FW                ; the shown width: less the bytes cut left, and
    SEC                     ; none from column 40 on
    SBC S_FOV
    STA S_FN
    LDA S_FZR
    BMI FtObjW
    CLC
    ADC S_FW
    LDX S_FBUF              ; (V2: to before 40 - FT_MRI) #V2
    CLC                     ; #V2
    ADC MRI_E               ; #V2
    CMP #41
    BCC FtObjW
    LDA #40
    SEC                     ; #V2
    SBC MRI_E               ; #V2
    SEC
    SBC S_FZR
    STA S_FN
FtObjW:
    LDA S_FN                ; its palette and width (two's complement, 5 bits)
    JSR FtObjDb
    EOR #$FF
    CLC
    ADC #$01
    AND #$1F
    PHA                     ; (V2: a coloured part, $A0: palette 5, #V2
    LDA S_FPAL              ; the band writer's 160B mark; MARIA takes #V2
    CMP #$A0                ; the upper group from it) #V2
    BNE FtObjPN             ; #V2
    PLA                     ; #V2
    ORA #$A0                ; #V2
    BNE FtObjP              ; #V2
FtObjPN:                    ; #V2
    PLA                     ; #V2
    BIT S_FPAL
    BMI FtObjPB
    BVS FtObjP3             ; (bit 6: palette 3, the hawk's pairs)
    PHA
    LDA S_FPAL
    CMP #$20
    BEQ FtObjPZ
    PLA
    ORA #DL_PAL
    BNE FtObjP
FtObjPZ:
    PLA                     ; (160B: palette 0, BandWrite's mark; its pixels
    JMP FtObjP              ; pick palettes 0-3)
FtObjP3:
    ORA #TOP_PAL2B
    BNE FtObjP
FtObjPB:
    ORA #FT_PALB
FtObjP:
    STA FO_PW,Y
    LDA S_FZR               ; its x
    CLC
    ADC S_FOV
    PHA
    ASL A
    ASL A
    CLC
    ADC S_FSUB
    STA FO_X,Y
    LDX FP_REC              ; the record's box takes it in (FR_C0/C1/R0/R1:
    PLA                     ; its first column to past its last, its cell's
    CMP FR_C0,X             ; rows)
    BCS FtObjB1
    STA FR_C0,X
FtObjB1:
    CLC
    ADC S_FN
    CMP FR_C1,X
    BCC FtObjB2
    STA FR_C1,X
FtObjB2:
    LDY S_FZ
    LDA FT_CELLROW,Y
    CMP FR_R0,X
    BCS FtObjB3
    STA FR_R0,X
FtObjB3:
    CLC
    ADC FT_CELLH,Y
    SEC
    SBC #$01
    CMP FR_R1,X
    BCC FtObjB4
    STA FR_R1,X
FtObjB4:
    RTS
; A doubled for a 160B object (S_FPAL $20: two bytes a column)
FtObjDb:
    PHA
    LDA S_FPAL
    CMP #$20  ; #V1
    BEQ FtObjDb1  ; #V1
    AND #$20                ; (V2: $20 and $A0, the coloured parts) #V2
    BNE FtObjDb1            ; #V2
    PLA
    RTS
FtObjDb1:
    PLA
    ASL A
    RTS
FtObjSkip:                  ; (its rows passed over)
    LDX S_FN
FtObjSk1:
    LDA FP_PAIR
    BEQ FtObjSk3
    TXA
    PHA
    JSR FtPairNext
    PLA
    TAX
    JMP FtObjSk2
FtObjSk3:
    LDA ZP_P1
    CLC
    ADC S_FW
    STA ZP_P1
    BCC FtObjSk2
    INC ZP_P1+1
FtObjSk2:
    DEX
    BNE FtObjSk1
    RTS

; the buffer S_FBUF's band zones' lists written again from its zone table
; (FtEmit), each entry's DLL address set to its new list
BandRefresh:
    LDY S_FBUF
    LDA S_ZTN,Y
    STA S_FCNT
    LDA #<BAND_A
    STA S_BDLP
    LDA #>BAND_A
    STA S_BDLP+1
    LDA #>DLL_A
    STA ZP_P2+1
    CPY #$00
    BEQ BandRef0
    LDA #<BAND_B
    STA S_BDLP
    LDA #>BAND_B
    STA S_BDLP+1
    LDA #>DLL_B
    STA ZP_P2+1
BandRef0:
    LDA S_BLPC               ; (console RAM's pieces, L1SG_*: from S_BLPC, B's
    BMI BandRef0L           ; 8 on)
    CPY #$00
    BEQ BandRef0A
    ORA #$08
BandRef0A:
    STA L1_SG
    TYA
    PHA
    JSR BandL1Start
    PLA
    TAY
BandRef0L:
    LDA #<BANDX_A           ; (page $7B's tail)
    CPY #$00
    BEQ BandRef0X
    LDA #<BANDX_B
BandRef0X:
    STA S_BX
    LDA #$FF                ; (no cell's columns kept yet: BandWrite)
    STA FB_CELL
    LDA #$00
    STA S_FTK
BandRef1:
    LDA S_FTK
    CMP S_FCNT
    BCS BandRefDone
    LDA S_FBUF
    ASL A
    ASL A
    ASL A
    ASL A
    ORA S_FTK
    TAX
    STX S_FB0
    JSR BandWrite
    LDX S_FB0
    LDA ZT_DLL,X
    STA ZP_P2
    LDY #$01
    LDA S_ROWP+1
    STA (ZP_P2),Y
    INY
    LDA S_ROWP
    STA (ZP_P2),Y
    INC S_FTK
    JMP BandRef1
BandRefDone:
    RTS

; a band zone's list (ZT entry X; S_FBUF its buffer, S_FTK the zones before
; it) at S_BDLP: the bitmap row's two objects; with fighter objects in the
; zone's grid cell (none with the glyphs in), those holding black (FT_PAL)
; first, then the others, then for each front box crossing the zone's rows
; the black block and the bitmap's own bytes over the box (the scenery in
; front of the fighters: FINDINGS "The fighters as objects: step 3"); the
; end. S_ROWP its address. A list of at most 16 goes in the zone's own
; bytes (BH_LO/HI: a page head), a longer one at S_BDLP (S_BDLP then past
; it), never across a page's end (on at the next page's 16), or else at S_BX
; in page $7B's tail. Short of room there, the front boxes are left out, then the objects one at a time from
; the last, till it fits in either (FINDINGS "The fighters as objects: step
; 4"). An object's high byte: line L of the zone is the cell's line S + L,
; at page FO_HB - S - L. A 160B object (palette 0) has a 5-byte header, and
; so has the next; the list ends in 160A (MARIA keeps the write mode till
; the next 5-byte header)
BandWrite:
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDA #$00                ; the cell's objects: FC_N of them from FS_I
    STA S_FW                ; (S_FN: the first's place; page $7B's half),
    STA S_FPAL              ; none with the glyphs in; and boxes
    LDA S_L1                ; (level 1: its zone's objects' bytes, L1_ZN4)
    BEQ BandWNoL1
    JSR BandL1Arg
    LDA #$00
    STA L1_WR
    STA L1_FP               ; (all passes: the behind pass's 1 stays after a
    LDA #<L1Zone            ; zone with nothing in front, and the next zone's
    LDX #>L1Zone            ; front instances went uncounted: its list past
    LDY #L1_HOME            ; its estimate, FINDINGS "the lists replayed")
    JSR L1CallK
    LDX L1_SX
BandWNoL1:
    LDA S_GLYIN
    BNE BandWE0
    LDA S_FBUF
    BEQ BandW0
    LDA #FS_BOFF
BandW0:
    STA S_FJ
    CLC
    ADC ZT_CELL,X
    TAY
    LDA FC_N,Y
    STA S_FW
    BEQ BandWE0
    LDA FC_START,Y
    CLC
    ADC S_FJ
    STA S_FN
    JMP BandWObj
BandWE0:
    LDA S_BLPC               ; (in console RAM's pieces: sized as any)  #V1
    BMI BandWE0B  ; #V1
    LDA ZT_H,X
    AND #$7F
    STA ZT_H,X
    LDA #$00
    STA FB_NB
    JMP BandW2
BandWE0B:  ; #V1
    LDA BH_LO,X             ; none: the bitmap's list alone, in the zone's  #V1
    STA ZP_P1               ; own bytes, unless it is there already (ZT_H  #V1
    STA S_ROWP              ; bit 7: from this zone's last list)  #V1
    LDA BH_HI,X  ; #V1
    STA ZP_P1+1  ; #V1
    STA S_ROWP+1  ; #V1
    LDA ZT_H,X  ; #V1
    BPL BandWE1  ; #V1
    JMP BandWOut  ; #V1
BandWE1:  ; #V1
    ORA #$80  ; #V1
    STA ZT_H,X  ; #V1
    JMP BandWGo  ; #V1
BandWObj:
    LDA ZT_H,X              ; (its own bytes no longer known)
    AND #$7F
    STA ZT_H,X
    LSR A                   ; the zone's rows: S_FZR to S_FOV (its first
    LSR A                   ; line in the cell: ZT_H bits 4-6; its height:
    LSR A                   ; bits 0-3)
    LSR A
    STA S_FOV
    LDY ZT_CELL,X
    LDA FT_CELLROW,Y
    CLC
    ADC S_FOV
    STA S_FZR
    LDA ZT_H,X
    AND #$0F
    CLC
    ADC S_FZR
    SEC
    SBC #$01
    STA S_FOV
    TYA                     ; the objects' columns: FB_XMIN to FB_XMAX (the
    CMP FB_CELL             ; cell's: kept for its next zones, FB_CELL)
    BEQ BandWXC
    STA FB_CELL
    TXA
    PHA
    LDA #$FF
    STA FB_XMIN
    LDA #$00
    STA FB_XMAX
    STA FB_NB
    LDY S_FN
    LDA S_FW
    STA S_FL0
BandWX1:
    LDA FS_I,Y
    TAX
    LDA FO_X,X
    LSR A
    LSR A
    STA S_FPAL              ; (its first column)
    CMP FB_XMIN
    BCS BandWX2
    STA FB_XMIN
BandWX2:
    LDA FO_PW,X             ; past its last (160B: two bytes a column)
    CMP #$20  ; #V1
    JSR PwIsB               ; (V2: palettes 0 and 5) #V2
    PHP
    EOR #$FF
    CLC
    ADC #$01
    AND #$1F
    PLP
    BCS BandWX2B
    LSR A
    INC FB_NB
BandWX2B:
    CLC
    ADC S_FPAL
    CMP FB_XMAX
    BCC BandWX3
    STA FB_XMAX
BandWX3:
    INY
    DEC S_FL0
    BNE BandWX1
    PLA
    TAX
    LDA #$00
    STA S_FPAL
BandWXC:
BandW2:
    LDA S_FPAL              ; the bytes: 10, 4 an object, 8 an opaque box, 4
    CLC                     ; a see-through one; 6 more a 160B object (its
    ADC S_FW                ; header's fifth byte and the next's, or a
    ASL A                   ; header to end its mode)
    ASL A
    CLC
    ADC #10
    STA S_FL0
    LDA S_L1                ; (level 1: its objects for the bitmap's two; the
    BEQ BandW2L             ; canvas: its objects too)
    LDA S_FL0
    BIT L1_SF
    BMI BandW2K
    SEC
    SBC #$08
BandW2K:
    CLC
    ADC L1_ZN4
    STA S_FL0
BandW2L:
    LDA FB_NB
    BEQ BandW2B
    ASL A
    CLC
    ADC FB_NB
    ASL A
    CLC
    ADC S_FL0
    STA S_FL0
BandW2B:
    LDA S_BLPC               ; (console RAM's pieces: BandWL1)  #V1
    BMI BandW2C  ; #V1
    JMP BandWL1
BandW2C:  ; #V1
    LDA S_FL0  ; #V1
BandWTry:  ; #V1
    CMP #17                 ; at most 16: the zone's own bytes  #V1
    BCS BandWArea  ; #V1
    LDA BH_LO,X  ; #V1
    STA ZP_P1  ; #V1
    LDA BH_HI,X  ; #V1
    STA ZP_P1+1  ; #V1
    JMP BandWGo  ; #V1
BandWArea:  ; #V1
    LDA S_BDLP              ; in the area (ZP_P1): here (never in a page's  #V1
    STA ZP_P1               ; first 16 bytes: the page heads), or the next  #V1
    LDA S_BDLP+1            ; page's 16 when it would cross this one's end  #V1
    STA ZP_P1+1  ; #V1
    LDA ZP_P1  ; #V1
    CMP #$10  ; #V1
    BCS BandWTry1  ; #V1
    LDA #$10  ; #V1
    STA ZP_P1  ; #V1
BandWTry1:  ; #V1
    LDA ZP_P1  ; #V1
    CLC  ; #V1
    ADC S_FL0  ; #V1
    BCC BandW3  ; #V1
    BEQ BandW3  ; #V1
    INC ZP_P1+1  ; #V1
    LDA #$10  ; #V1
    STA ZP_P1  ; #V1
BandW3:  ; #V1
    LDA ZP_P1               ; its end (S_BTMP)  #V1
    CLC  ; #V1
    ADC S_FL0  ; #V1
    STA S_BTMP  ; #V1
    LDA ZP_P1+1  ; #V1
    ADC #$00  ; #V1
    STA S_BTMP+1  ; #V1
    JSR BandEnd             ; the buffer's area's end  #V1
    CMP S_BTMP+1  ; #V1
    BCC BandWNone  ; #V1
    BNE BandWFit  ; #V1
    CPY S_BTMP  ; #V1
    BCS BandWFit  ; #V1
BandWNone:  ; #V1
    LDA S_BX                ; no room: in page $7B's tail  #V1
    CLC  ; #V1
    ADC S_FL0  ; #V1
    BCS BandWDrop  ; #V1
    LDY S_FBUF  ; #V1
    BNE BandWXB  ; #V1
    CMP #<BANDX_AEND+1  ; #V1
    BCS BandWDrop  ; #V1
    BCC BandWX  ; #V1
BandWXB:  ; #V1
    CMP #<BANDX_BEND+1  ; #V1
    BCS BandWDrop  ; #V1
BandWX:  ; #V1
    LDY S_BX  ; #V1
    STY ZP_P1  ; #V1
    STA S_BX  ; #V1
    LDA #>BANDX_A  ; #V1
    STA ZP_P1+1  ; #V1
    JMP BandWGo  ; #V1
BandWDrop:
    LDA S_FPAL              ; else without the front boxes (none pass the
    BEQ BandWN1             ; columns test), else an object fewer (at most
    LDA #$00                ; one and no boxes fits the zone's own bytes)
    STA S_FPAL
    STA FB_XMAX
    LDA #$FF
    STA FB_XMIN
    STA FB_CELL
    JMP BandW2
BandWN1:
    DEC S_FW
    JMP BandW2
BandWFit:  ; #V1
    LDA S_BTMP  ; #V1
    STA S_BDLP  ; #V1
    LDA S_BTMP+1  ; #V1
    STA S_BDLP+1  ; #V1
BandWGo:
    LDA ZP_P1               ; (ZP_P1: its place)
    STA S_ROWP
    LDA ZP_P1+1
    STA S_ROWP+1
    LDA S_L1                ; level 1: the zone's objects (Y: their bytes)
    BEQ BandWBm
    BIT L1_SF
    BMI BandWBm
    JSR BandL1Arg
    LDA #$00
    STA L1_FS
    LDA #$01
    STA L1_WR
    STA L1_FP               ; (the tiles and the instances behind the fighters)
    LDA #$FF
    STA L1_WMAX
    LDA #<L1Zone
    LDX #>L1Zone
    LDY #L1_HOME
    JSR L1CallK
    LDX L1_SX
    JMP BandWAfter
BandWBm:                    ; (no set on, the ending's text: no bitmap any more,
    LDY #$00                ; so no bitmap row's objects; its own only)
BandWAfter:
    LDA S_FW
    BNE BandWOS
    JMP BandWFrP
BandWOS:
    STA S_FL0               ; the cell's objects (sorted: black first), their
    LDA ZT_H,X              ; high byte for the zone's lines (each one's
    LSR A                   ; page for its cell's line 0, FO_HB, + S_FPAL:
    LSR A                   ; 1 less the zone's first line and height)
    LSR A
    LSR A
    STA S_FPAL
    LDA ZT_H,X
    AND #$0F
    CLC
    ADC S_FPAL
    STA S_FPAL
    LDA #$01
    SEC
    SBC S_FPAL
    STA S_FPAL
    LDA #$00                ; (the list's write mode: 160A, as every list
    STA FB_MB               ; ends)
    LDX S_FN
BandWO1:
    LDA FS_I,X              ; (the object)
    STX S_FN
    TAX
    LDA FO_LO,X
    STA (ZP_P1),Y
    INY
    LDA FO_PW,X
    CMP #$20  ; #V1
    JSR PwIsB               ; (V2: palettes 0 and 5) #V2
    BCC BandWOB             ; (palette 0: 160B)
    LDA FB_MB
    BNE BandWOA
    LDA FO_PW,X
    STA (ZP_P1),Y
    INY
    LDA FO_HB,X
    CLC
    ADC S_FPAL
    STA (ZP_P1),Y
    INY
    JMP BandWOX
BandWOB:
    LDA #$C0                ; a 5-byte header: write mode 160B
    STA FB_MB
    BNE BandWO5
BandWOA:
    LDA #$00                ; (after a 160B one: a 5-byte header, 160A)
    STA FB_MB
    LDA #$40
BandWO5:
    STA (ZP_P1),Y
    INY
    LDA FO_HB,X
    CLC
    ADC S_FPAL
    STA (ZP_P1),Y
    INY
    LDA FO_PW,X
    STA (ZP_P1),Y
    INY
BandWOX:
    LDA FO_X,X
    STA (ZP_P1),Y
    INY
    LDX S_FN
    INX
    DEC S_FL0
    BNE BandWO1
BandWO8:                    ; (a tiles set's too: its instances in front of the
                            ; fighters follow, 4-byte headers, 160A)
    LDA FB_MB               ; still 160B: a 160A header (a byte off the
    BEQ BandWO9             ; screen's right) to end the mode
    LDA #$00
    STA (ZP_P1),Y
    INY
    LDA #$40
    STA (ZP_P1),Y
    INY
    LDA #FT_PTOP
    STA (ZP_P1),Y
    INY
    LDA #$1F
    STA (ZP_P1),Y
    INY
    LDA #160
    STA (ZP_P1),Y
    INY
BandWO9:
BandWFrP:
    LDA S_L1                ; (a tiles set: its instances in front of the
    BEQ BandWEnd            ; fighters, after them: L1Zone's pass 2, at Y)
    BIT L1_SF
    BVC BandWEnd
    LDA L1_FS               ; (none in front in this zone: no pass 2)
    BEQ BandWEnd
    JSR BandWFr
BandWEnd:
    LDA #$00
    STA (ZP_P1),Y
    INY
    STA (ZP_P1),Y
    LDA S_BLPC               ; (in a piece: its next free byte the list's real
    BMI BandWOut            ; end, past Y)
    STX L1_SGX
    LDX L1_SGK
    TYA
    SEC
    ADC ZP_P1
    STA L1_SGP,X
    LDA ZP_P1+1
    ADC #$00
    STA L1_SGP+1,X
    LDX L1_SGX
BandWOut:
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    RTS
; (a tiles set) the zone's instances in front of the fighters (L1_FP 2), at
; Y: L1Zone writes them at ZP_P1 + Y; Y past them, X the zone
BandWFr:
    LDX L1_SX               ; (the zone: BandL1Arg's)
    LDA #$02
    STA L1_FP
    TYA
    PHA
    CLC
    ADC ZP_P1
    STA ZP_P1
    BCC BandWFr1
    INC ZP_P1+1
BandWFr1:
    JSR BandL1Arg
    LDA #$01
    STA L1_WR
    LDA #$FF
    STA L1_WMAX
    LDA #<L1Zone
    LDX #>L1Zone
    LDY #L1_HOME
    JSR L1CallK
    STY L1_T0               ; (its bytes)
    PLA                     ; (ZP_P1 back; Y past them)
    PHA
    EOR #$FF
    SEC
    ADC ZP_P1
    STA ZP_P1
    BCS BandWFr2
    DEC ZP_P1+1
BandWFr2:
    PLA
    CLC
    ADC L1_T0
    TAY
    LDA #$00
    STA L1_FP
    LDX L1_SX
    RTS
; (level 1) L1Zone's arguments: the zone (ZT entry X: its low 4 bits), the
; buffer; X kept in L1_SX
BandL1Arg:
    STX L1_SX
    TXA
    AND #$0F
    CLC                     ; (on from the set's first zone)
    ADC L1_ZB
    STA L1_K
    LDA S_FBUF
    STA L1_B
    RTS
; level 1: the zone's list (S_FL0 bytes) in the first of its buffer's
; pieces with room (L1SG_* from L1_SG: their ends; L1_SGP: each one's next
; free byte), X kept; none with room: an object fewer (BandWDrop), and with
; none, the empty list (DL_EMPTY)
BandWL1:
    STX L1_SGX
    LDY L1_SG
    LDX #$00
BandWL1T:
    LDA L1SG_SH,Y           ; (a high byte 0 ends the buffer's pieces)
    BEQ BandWL1X
    LDA L1_SGP,X
    CLC
    ADC S_FL0
    STA S_BTMP
    LDA L1_SGP+1,X
    ADC #$00
    STA S_BTMP+1
    LDA L1SG_EH,Y
    CMP S_BTMP+1
    BCC BandWL1N
    BNE BandWL1F
    LDA L1SG_EL,Y
    CMP S_BTMP
    BCC BandWL1N
BandWL1F:
    STX L1_SGK              ; (the piece: its pointer to the list's real end
    LDA L1_SGP,X            ; once written, BandWEnd)
    STA ZP_P1
    LDA L1_SGP+1,X
    STA ZP_P1+1
    LDA S_BTMP
    STA L1_SGP,X
    LDA S_BTMP+1
    STA L1_SGP+1,X
    LDX L1_SGX
    JMP BandWGo
BandWL1N:
    INY
    INX
    INX
    BNE BandWL1T
BandWL1X:
    LDX L1_SGX
    LDA S_FW
    BEQ BandWL1E
    JMP BandWDrop
BandWL1E:
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
    JMP BandWOut
; BuildDll's: level 1's pieces from A's first (A 0) or B's (A 8), X and Y
; kept. In level 1 only: L1RAM is the fast fill's code in the other scenes
; (L1_SG was written first, into its STY FILL_BLK+2: the fill then wrote
; over its own code)
BuildL1Seg:
    PHA
    LDA S_BLPC               ; (levels 2-4 too: their pieces from 16, S_BLPC)
    BPL BuildL1S1
    PLA
    RTS
BuildL1S1:
    PLA
    ORA S_BLPC
    STA L1_SG
    TXA
    PHA
    TYA
    PHA
    JSR BandL1Start
    PLA
    TAY
    PLA
    TAX
BuildL1S9:
    RTS
; the buffer's pieces' next free bytes (L1_SGP) their starts
BandL1Start:
    LDY L1_SG
    LDX #$00
BandL1S1:
    LDA L1SG_SL,Y
    STA L1_SGP,X
    LDA L1SG_SH,Y
    STA L1_SGP+1,X
    INY
    INX
    INX
    CPX #$0E
    BCC BandL1S1
    RTS
L1SG_SL:                    ; (level 1's A's pieces from 0, B's from 8: console
    .byte <L1SA0, <L1SA1, <L1SA2, <L1SA3, <L1SA4, <L1SA5, <L1SA6, 0     ; RAM's six,
    .byte <L1SB0, <L1SB1, <L1SB2, <L1SB3, <L1SB4, <L1SB5, <L1SB6, 0     ; then cart
    .byte <L1SC0, <L1SC1, <L1SC2, <L1SC3, <L1SC4, <L1SC5, <L1SC6, 0     ; RAM's while
    .byte <L1SD0, <L1SD1, <L1SD2, <L1SD3, <L1SD4, <L1SD5, <L1SD6, 0
    .byte <L1SE0, <L1SE1, <L1SE2, <L1SE3, <L1SE4, <L1SE5, <L1SE6, 0
    .byte <L1SF0, <L1SF1, <L1SF2, <L1SF3, <L1SF4, <L1SF5, <L1SF6, 0     ; it is short;
L1SG_SH:                    ; levels 2-4's A's from 16, B's from 24, console
    .byte >L1SA0, >L1SA1, >L1SA2, >L1SA3, >L1SA4, >L1SA5, >L1SA6, 0     ; RAM's only:
    .byte >L1SB0, >L1SB1, >L1SB2, >L1SB3, >L1SB4, >L1SB5, >L1SB6, 0     ; a high byte
    .byte >L1SC0, >L1SC1, >L1SC2, >L1SC3, >L1SC4, >L1SC5, >L1SC6, 0     ; 0 ends them)
    .byte >L1SD0, >L1SD1, >L1SD2, >L1SD3, >L1SD4, >L1SD5, >L1SD6, 0
    .byte >L1SE0, >L1SE1, >L1SE2, >L1SE3, >L1SE4, >L1SE5, >L1SE6, 0
    .byte >L1SF0, >L1SF1, >L1SF2, >L1SF3, >L1SF4, >L1SF5, >L1SF6, 0
L1SG_EL:
    .byte <L1SA0E, <L1SA1E, <L1SA2E, <L1SA3E, <L1SA4E, <L1SA5E, <L1SA6E, 0
    .byte <L1SB0E, <L1SB1E, <L1SB2E, <L1SB3E, <L1SB4E, <L1SB5E, <L1SB6E, 0
    .byte <L1SC0E, <L1SC1E, <L1SC2E, <L1SC3E, <L1SC4E, <L1SC5E, <L1SC6E, 0
    .byte <L1SD0E, <L1SD1E, <L1SD2E, <L1SD3E, <L1SD4E, <L1SD5E, <L1SD6E, 0
    .byte <L1SE0E, <L1SE1E, <L1SE2E, <L1SE3E, <L1SE4E, <L1SE5E, <L1SE6E, 0
    .byte <L1SF0E, <L1SF1E, <L1SF2E, <L1SF3E, <L1SF4E, <L1SF5E, <L1SF6E, 0
L1SG_EH:
    .byte >L1SA0E, >L1SA1E, >L1SA2E, >L1SA3E, >L1SA4E, >L1SA5E, >L1SA6E, 0
    .byte >L1SB0E, >L1SB1E, >L1SB2E, >L1SB3E, >L1SB4E, >L1SB5E, >L1SB6E, 0
    .byte >L1SC0E, >L1SC1E, >L1SC2E, >L1SC3E, >L1SC4E, >L1SC5E, >L1SC6E, 0
    .byte >L1SD0E, >L1SD1E, >L1SD2E, >L1SD3E, >L1SD4E, >L1SD5E, >L1SD6E, 0
    .byte >L1SE0E, >L1SE1E, >L1SE2E, >L1SE3E, >L1SE4E, >L1SE5E, >L1SE6E, 0
    .byte >L1SF0E, >L1SF1E, >L1SF2E, >L1SF3E, >L1SF4E, >L1SF5E, >L1SF6E, 0
; the buffer's band area's end: A high, Y low
BandEnd:
    LDA S_FBUF
    BNE BandEndB
    LDA #>BAND_AEND
    RTS
BandEndB:
    LDY #<BAND_BEND
    LDA #>BAND_BEND
    RTS
;;; FARART (TextIn) #V1
;;; FARCOM (TextIn) -- (V2: in every scene page, after its system code) #V2
; the small-sprite block (the game's glyphs) into RAM from its image, for the
; game's own text routine, which writes its glyphs' headers as it draws: no
; longer copied at boot, so its RAM is free in play until a text draw ("the
; end" at a game over; FINDINGS "The small-sprite block moved to paged ROM").
; The scene's top pieces are loaded again with it in (level 1-3's "the end"
; pieces are read from it), unless the title's or story's data is in their
; pages. $00-$03 kept
TextIn:
    LDA #$01                ; (first: the fighters' tables share its RAM)
    STA S_GLYIN
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDA ZP_P2
    PHA
    LDA ZP_P2+1
    PHA
    LDA #<IMG_SPRITES
    STA ZP_P1
    LDA #>IMG_SPRITES
    STA ZP_P1+1
    LDA #<RAM_SPRITES
    STA ZP_P2
    LDA #>RAM_SPRITES
    STA ZP_P2+1
    LDA #<LEN_SPRITES
    LDX #>LEN_SPRITES
    JSR Copy
    LDA S_STORY
    ORA S_TITLEA
    ORA S_TITLEB
    BNE TextInDone
    JSR TopLoadF
TextInDone:
    PLA
    STA ZP_P2+1
    PLA
    STA ZP_P2
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    RTS

;;; FARART (ClearCopy) -- the game's full clear and buffer copy (ClearBufF,
;;; CopyBufF select the top bank)
; TopLoad from the game's clear: its registers and $00-$03 kept
ClearTopLoad:
    TXA
    PHA
    TYA
    PHA
    LDA ZP_P1
    PHA
    LDA ZP_P1+1
    PHA
    LDA ZP_P2
    PHA
    LDA ZP_P2+1
    PHA
    JSR TopLoadF
    PLA
    STA ZP_P2+1
    PLA
    STA ZP_P2
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    PLA
    TAY
    PLA
    TAX
    RTS
; the buffer $07 names cleared: its fighter records gone (FtEmit)
FtForget:
    LDA S_GLYIN             ; (the tables' RAM holds the glyphs)
    BNE FtForgetD
    LDX #$00
    LDA G_Z07
    CMP #$20
    BNE FtForget1
    INX
FtForget1:
    LDA #$01
    STA FT_DIRTY,X
    LDA #$00
    STA SR_V,X
    STA AK_V,X
    STA PC_V,X              ; #V2
    TXA
    ASL A
    TAX
    LDA #$00
    STA FR_V,X
    STA FR_V+1,X
FtForgetD:
    RTS
; the buffer copy's (CopyBuf: $07 $40, B into A, else A into B): the
; source's fighter records and shown front boxes are the target's, as an
; earlier picture's (FtEmit)
FtCopyRec:
    LDA S_GLYIN
    BNE FtForgetD
    LDX #$00                ; X the target's first record, Y the source's
    LDY #$02
    LDA G_Z07
    CMP #$40
    BEQ FtCopyR1
    LDX #$02
    LDY #$00
FtCopyR1:
    LDA #$02
    STA S_FTK
FtCopyR2:
    LDA FR_V,Y
    BEQ FtCopyR3
    LDA #$01
FtCopyR3:
    STA FR_V,X
    LDA FR_20,Y
    STA FR_20,X
    LDA FR_21,Y
    STA FR_21,X
    LDA FR_22,Y
    STA FR_22,X
    LDA FR_50,Y
    STA FR_50,X
    LDA FR_3E,Y
    STA FR_3E,X
    LDA FR_36,Y
    STA FR_36,X
    LDA FR_C0,Y
    STA FR_C0,X
    LDA FR_C1,Y
    STA FR_C1,X
    LDA FR_R0,Y
    STA FR_R0,X
    LDA FR_R1,Y
    STA FR_R1,X
    INX
    INY
    DEC S_FTK
    BNE FtCopyR2
    TXA                     ; (X 2 past the target's: buffer = X / 2 - 1)
    LSR A
    TAX
    DEX
    TYA
    LSR A
    TAY
    DEY
    LDA #$01
    STA FT_DIRTY,X
    LDA SR_V,Y              ; the hit star, an earlier picture's
    BEQ FtCopyR5
    LDA #$01
FtCopyR5:
    STA SR_V,X
    LDA PC_V,Y              ; (V2: level 2's portcullis, an earlier #V2
    BEQ FtCopyRP            ; picture's) #V2
    LDA #$01                ; #V2
FtCopyRP:                   ; #V2
    STA PC_V,X              ; #V2
    LDA PC_ROW,Y            ; #V2
    STA PC_ROW,X            ; #V2
    LDA PC_TIP,Y            ; #V2
    STA PC_TIP,X            ; #V2
    LDA PC_COL,Y            ; #V2
    STA PC_COL,X            ; #V2
    LDA PC_SH,Y             ; #V2
    STA PC_SH,X             ; #V2
    LDA SR_IMG,Y
    STA SR_IMG,X
    LDA SR_ROW,Y
    STA SR_ROW,X
    LDA SR_COL,Y
    STA SR_COL,X
    LDA SR_SUB,Y
    STA SR_SUB,X
    LDA FR_C0+4,Y
    STA FR_C0+4,X
    LDA FR_C1+4,Y
    STA FR_C1+4,X
    LDA FR_R0+4,Y
    STA FR_R0+4,X
    LDA FR_R1+4,Y
    STA FR_R1+4,X
    LDA FR_C0+6,Y           ; Akuma's: his box, his blits
    STA FR_C0+6,X
    LDA FR_C1+6,Y
    STA FR_C1+6,X
    LDA FR_R0+6,Y
    STA FR_R0+6,X
    LDA FR_R1+6,Y
    STA FR_R1+6,X
    LDA AK_V,Y
    BEQ FtCopyR6
    LDA #$01
FtCopyR6:
    STA AK_V,X
    LDA AK_N,Y
    STA AK_N,X
    LDA #$01
    STA AK_FR,X
    JSR FtCopyAk
    RTS
; buffer Y's captured blits into buffer X's (FtCopyRec). X, Y kept
FtCopyAk:
    TXA
    PHA
    TYA
    PHA
    LDA #$00                ; X, Y: their first entries
    CPX #$00
    BEQ FtCopyAk1
    LDA #AK_MAX
FtCopyAk1:
    PHA
    LDA #$00
    CPY #$00
    BEQ FtCopyAk2
    LDA #AK_MAX
FtCopyAk2:
    TAY
    PLA
    TAX
    LDA #AK_MAX
    STA S_FTK
FtCopyAk3:
    LDA AK_LO,Y
    STA AK_LO,X
    LDA AK_HI,Y
    STA AK_HI,X
    LDA AK_BK,Y
    STA AK_BK,X
    LDA AK_COL,Y
    STA AK_COL,X
    LDA AK_ROW,Y
    STA AK_ROW,X
    LDA AK_SH,Y
    STA AK_SH,X
    LDA AK_FL,Y
    STA AK_FL,X
    INX
    INY
    DEC S_FTK
    BNE FtCopyAk3
    PLA
    TAY
    PLA
    TAX
    RTS
; the game's full clear ($280F): the buffer $07 names, all its rows
ClearBuf:
    JSR ObjEnd
    BCC ClearBuf1           ; the story or title ended: the scene's top pieces
    JSR ClearTopLoad        ; loaded again (their pages were the text's)
ClearBuf1:
    JSR TopClearF
    JSR FtForget
    LDA S_L1                ; level 1: its instances (its windows are in the
    BEQ ClearBufBm          ; bitmap's pages)  #V1
    BEQ ClearBufAfter  ; (V2: no cart RAM, no bitmap) #V2
    LDA #<L1Clear
    LDX #>L1Clear
    LDY #L1_CAP
    JSR L1CallK
    BIT L1_SF               ; (the canvas: the bitmap cleared too)  #V1
    BMI ClearBufBm  ; #V1
    JMP ClearBufAfter  ; #V1
ClearBufBm:  ; #V1
    LDA G_Z07  ; #V1
    CMP #$20  ; #V1
    BEQ ClearBufB  ; #V1
    LDA #16  ; #V1
    BNE ClearBufGo  ; #V1
ClearBufB:  ; #V1
    LDA #136  ; #V1
ClearBufGo:  ; #V1
    STA G_Z14  ; #V1
    LDA #FB_PBOT  ; #V1
    STA G_Z15  ; #V1
ClearBufPage:  ; #V1
    LDY #119                ; the buffer's three rows on this page  #V1
    LDA #$00  ; #V1
ClearBufByte:  ; #V1
    STA (G_Z14),Y  ; #V1
    DEY  ; #V1
    BPL ClearBufByte  ; #V1
    INC G_Z15  ; #V1
    LDA G_Z15  ; #V1
    CMP #FB_PTOP+1  ; #V1
    BNE ClearBufPage  ; #V1
ClearBufAfter:
    LDX #$00                ; no arrows shown in it
    LDA G_Z07
    CMP #$20
    BNE ClearBufStA
    INX
ClearBufStA:
    LDA #$00
    STA S_STP,X
    STA S_STF,X
    LDA #<STATUS_DLA+1
    CPX #$00
    BEQ ClearBufStL
    LDA #<STATUS_DLB+1
ClearBufStL:
    TAX
    LDA #$00
    STA STATUS_PG,X         ; (both lists in one page)
    LDA G_Z07               ; this buffer's bitmap is clean again (if it
    CMP #$20                ; held the objects' data: then its lists are
    BEQ ClearBufCleanB      ; built again)
    LDA S_OBLANK
    AND #$01
    BEQ ClearBufDone
    LDA #$FE
    AND S_OBLANK
    STA S_OBLANK
    LDA #$00
    STA S_DLIST_A
    STA S_DLIST_A+1
    BEQ ClearBufClean
ClearBufCleanB:
    LDA S_OBLANK
    AND #$02
    BEQ ClearBufDone
    LDA #$FD
    AND S_OBLANK
    STA S_OBLANK
    LDA #$00
    STA S_DLIST_B
    STA S_DLIST_B+1
ClearBufClean:
    STA S_CHOSEN
    STA S_CHOSEN+1
ClearBufDone:
    RTS
; the game's buffer copy ($ADC7 and $AE05): with $07 = $40 (A drawn) B into
; A, else A into B, all rows; through $03/$04 and $14/$15 as the game's
CopyBuf:
    JSR TopCopyF
    JSR FtCopyRec
    LDA S_L1                ; level 1: its instances
    BEQ CopyBufBm  ; #V1
    BEQ CopyBufAfter  ; (V2: no cart RAM, no bitmap) #V2
    LDA #<L1Copy
    LDX #>L1Copy
    LDY #L1_CAP
    JSR L1CallK
    BIT L1_SF  ; #V1
    BMI CopyBufBm  ; #V1
    JMP CopyBufAfter  ; #V1
CopyBufBm:  ; #V1
    LDA G_Z07  ; #V1
    CMP #$40  ; #V1
    BNE CopyBufAB  ; #V1
    LDA #136  ; #V1
    STA G_Z03  ; #V1
    LDA #16  ; #V1
    STA G_Z14  ; #V1
    BNE CopyBufGo  ; #V1
CopyBufAB:  ; #V1
    LDA #16  ; #V1
    STA G_Z03  ; #V1
    LDA #136  ; #V1
    STA G_Z14  ; #V1
CopyBufGo:  ; #V1
    LDA #FB_PBOT  ; #V1
    STA G_Z04  ; #V1
    STA G_Z15  ; #V1
CopyBufPage:  ; #V1
    LDY #119  ; #V1
CopyBufByte:  ; #V1
    LDA (G_Z03),Y  ; #V1
    STA (G_Z14),Y  ; #V1
    DEY  ; #V1
    BPL CopyBufByte  ; #V1
    INC G_Z04  ; #V1
    INC G_Z15  ; #V1
    LDA G_Z15  ; #V1
    CMP #FB_PTOP+1  ; #V1
    BNE CopyBufPage  ; #V1
CopyBufAfter:
    LDY #STATUS_DLB-STATUS_DLA-1   ; the copy's arrows: the source's
    LDA G_Z07
    CMP #$40
    BNE CopyStAB
    LDA S_STP+1             ; B into A
    STA S_STP
    LDA S_STF+1
    STA S_STF
CopyStBA:
    LDA STATUS_DLB,Y
    STA STATUS_DLA,Y
    DEY
    BPL CopyStBA
    BMI CopyStDone
CopyStAB:
    LDA S_STP               ; A into B
    STA S_STP+1
    LDA S_STF
    STA S_STF+1
CopyStAB1:
    LDA STATUS_DLA,Y
    STA STATUS_DLB,Y
    DEY
    BPL CopyStAB1
CopyStDone:
    LDA S_OBLANK            ; the copy holds what its source held
    BEQ CopyBufDone
    LDA G_Z07
    CMP #$40
    BNE CopyBufToB
    LDA S_OBLANK            ; B into A
    AND #$02
    LSR A
    STA S_BTMP
    LDA S_OBLANK
    AND #$02
    ORA S_BTMP
    STA S_OBLANK
    JMP CopyBufRebuild
CopyBufToB:
    LDA S_OBLANK            ; A into B
    AND #$01
    ASL A
    STA S_BTMP
    LDA S_OBLANK
    AND #$01
    ORA S_BTMP
    STA S_OBLANK
CopyBufRebuild:
    LDA #$00
    STA S_DLIST_A
    STA S_DLIST_A+1
    STA S_DLIST_B
    STA S_DLIST_B+1
    STA S_CHOSEN
    STA S_CHOSEN+1
CopyBufDone:
    RTS

;;; FARART (TiaSound) -- run from the NMI (TiaSoundF)
; ------------------------------------------------------------ sound
; The game plays two voices on POKEY, each a pair of channels joined into a
; 16-bit divider on the 1.79 MHz clock (AUDCTL $78): voice 0 is AUDF1/AUDF2
; with AUDC2, voice 1 AUDF3/AUDF4 with AUDC4, all written to the shadow. Once a
; frame each becomes one TIA channel: a pure tone (distortion $A0) the TIA tone
; nearest its pitch (a binary search over the dividers where the nearest tone
; changes), anything else (the noise, $00) TIA's 9-bit noise at the nearest
; rate, and the 4-bit volume as it is. Tables from port/sndconv.py; runs in the
; NMI, with scratch of its own (S_SN.., not S_TMP).
TiaSound:
    LDX #$00
    JSR TiaVoice
    LDX #$01
    JMP TiaVoice
TiaOff:
    LDA #$00
    STA AUDV0,X
    RTS
TiaVoice:                   ; X = TIA channel, 0 or 1
    TXA
    ASL A
    ASL A
    TAY                     ; the voice's POKEY registers
    LDA S_POKEY+3,Y
    AND #$0F
    BEQ TiaOff
    STA S_SVOL
    LDA S_POKEY+0,Y
    STA S_SN
    LDA S_POKEY+2,Y
    STA S_SN+1
    LDA S_POKEY+3,Y
    AND #$F0
    CMP #$A0
    BNE TiaNoise
    LDA S_SN+1
    BNE TiaTone
    LDA S_SN
    CMP #SND_ULTRA
    BCC TiaOff              ; above 16 kHz: nothing to hear
TiaTone:
    STX S_SCH
    LDX #$00                ; how many boundaries are at or below N
    LDA #$40
    STA S_SSTEP
TiaSearch:
    TXA
    CLC
    ADC S_SSTEP
    TAY
    DEY
    CPY #SND_NB
    BCS TiaLess
    LDA S_SN+1
    CMP SND_NBHI,Y
    BCC TiaLess
    BNE TiaGE
    LDA S_SN
    CMP SND_NBLO,Y
    BCC TiaLess
TiaGE:
    TXA
    CLC
    ADC S_SSTEP
    TAX
TiaLess:
    LSR S_SSTEP
    BNE TiaSearch
    LDA SND_TONE,X          ; mode index << 5 | AUDF
    TAY
    AND #$1F
    STA S_SF
    TYA
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    TAY
    LDA SND_MODE,Y
    LDX S_SCH
    JMP TiaSet
TiaNoise:
    LDA S_SN+1
    CMP #$07
    BCS TiaNoiseLow         ; N >> 6 >= 28: the slowest
    ASL S_SN
    ROL A
    ASL S_SN
    ROL A                   ; N >> 6
    TAY
    LDA SND_NOISE,Y
    JMP TiaNoiseSet
TiaNoiseLow:
    LDA #$1F
TiaNoiseSet:
    STA S_SF
    LDA #$08                ; 9-bit polynomial noise
TiaSet:
    STA AUDC0,X
    LDA S_SF
    STA AUDF0,X
    LDA S_SVOL
    STA AUDV0,X
    RTS

;;; FARART (Builder) -- the display-list builder (BuildDllF selects the #V1
;;; FARPG (Builder) -- (V2: a copy in every scene page, through PgBuildDll, PgTopErase) #V2
;;; top bank; FINDINGS "RAM and fixed ROM: step 3")
; ------------------------------------------------------ list building
; BuildDll: the DLL for the list at table index S_DLIDX, into its buffer's
; DLL, and the display lists of its buffer-row zones into the buffer's DL
; area (DLS_A, DLS_B; the band zones' into BAND_A, BAND_B: RowsBand). A descriptor is a run list: kind|$80 (DLI on the
; run's last line), line count, argument; kind 0 blank, 1 mode-8 row
; (argument 0-2), 2 buffer rows from the argument row on; $FF ends it. After
; the runs come blanks, with the DLI that stands in for the vertical blank
; on line VBI_LINE. Zones: MARIA raises a zone's DLI as the zone starts, so a
; flagged line is a zone of its own (as in the game lists, where the DLI is
; on a run's last line); blank lines go in zones of up to 16; buffer rows in
; zones of up to 16 within one column of the buffer (FB_BAND rows, one page
; apart, the top row on the highest page: FINDINGS "display lists by the
; 7800's rules"); the mode-8 rows' lines one a zone (each line repeats the
; row's data). It runs in the NMI, so its scratch is its own (S_BTMP, not
; the loaders' S_TMP).
BuildDll:                   ; (the top bank in: BuildDllF; the description in
    LDA #<DESCBUF           ; DESCBUF, the list's DLT entries in S_DLBUF,
    STA ZP_P1               ; S_DLLO, S_DLHI)
    LDA #>DESCBUF
    STA ZP_P1+1
    LDA S_DLBUF
    BNE BuildForB
    LDA #<DLL_A
    STA ZP_P2
    LDA #>DLL_A
    STA ZP_P2+1
    LDA #<DLS_A
    STA S_DLSP
    LDA #>DLS_A
    STA S_DLSP+1
    LDA #<BAND_A            ; the band zones' lists (with the title off)
    STA S_BDLP
    LDA #>BAND_A
    STA S_BDLP+1
    LDA #$00                ; (level 1's: its pieces from A's first)
    JSR BuildL1Seg
    LDA #$00                ; the top zones' slots (their lists' pieces; the
                            ; slots' ordinal; the
    STA TP_SO               ; slots all unused till listed)
    JSR TopSegStart
    JSR TopSlotsOff
    LDA #STORY_PATA         ; the objects' patched lists (story, title)
    STA S_SPAT+1
    LDA #16
    STA S_SPAT
    LDA #$00                ; buffer A's first column
    STA S_SLOT
    STA S_ZTN               ; (its band zones: none yet)
    JMP BuildGo
BuildForB:
    LDA #<DLL_B
    STA ZP_P2
    LDA #>DLL_B
    STA ZP_P2+1
    LDA #<DLS_B
    STA S_DLSP
    LDA #>DLS_B
    STA S_DLSP+1
    LDA #<BAND_B
    STA S_BDLP
    LDA #>BAND_B
    STA S_BDLP+1
    LDA #$08                ; (level 1's: its pieces from B's first)
    JSR BuildL1Seg
    LDA #TOPDL_N            ; the top zones' slots
    STA TP_SO
    LDA #$08
    JSR TopSegStart
    JSR TopSlotsOff
    LDA #STORY_PATB
    STA S_SPAT+1
    LDA #16
    STA S_SPAT
    LDA #$03                ; buffer B's first column
    STA S_SLOT
    LDA #$00
    STA S_ZTN+1
BuildGo:
    LDA #$00
    STA S_LINES
    STA S_NDLI
    STA S_MRG
    JSR TopSkyGo
BuildRun:
    LDY #$00
    LDA (ZP_P1),Y
    CMP #$FF
    BNE BuildRunGo
    JMP BuildEnd
BuildRunGo:
    STA S_KIND
    INY
    LDA (ZP_P1),Y
    STA S_COUNT
    INY
    LDA (ZP_P1),Y
    STA S_ARG
    LDA ZP_P1
    CLC
    ADC #$03
    STA ZP_P1
    BCC BuildKind
    INC ZP_P1+1
BuildKind:
    LDA #$00                ; the lines before a flagged last one
    STA S_HASDLI
    LDA S_KIND              ; (DLI_FIRST: the DLI on its first zone, S_DLI1
    AND #DLI_FIRST          ; $80; buffer rows only)
    ASL A
    STA S_DLI1
    LDA S_KIND
    BPL BuildKind1
    INC S_HASDLI
    DEC S_COUNT
    JMP BuildKind0
BuildKind1:
    JSR TopSkyOnRun         ; (a blank run before the top's sky: flagged)
BuildKind0:
    LDA S_KIND
    AND #$3F
    BNE BuildKind2
    JMP BuildBlankRun
BuildKind2:
    CMP #$01
    BNE BuildRowsZone
    JMP BuildM8Run
; buffer rows: zones (the first flagged with DLI_FIRST), then the flagged
; last row alone
BuildRowsZone:
    LDA S_COUNT
    BEQ BuildRowsLast
    JSR ZoneH
    STA S_H
    LDA S_DLI1              ; (the run's first zone: its DLI_FIRST)
    STA S_FLAG
    BPL BuildRowsZ1
    INC S_NDLI
    LDA #$00
    STA S_DLI1
BuildRowsZ1:
    JSR TopSkyOffZone       ; (the top's last row: a flagged zone of its own)
    JSR ZoneEmit
    LDA S_ARG
    CLC
    ADC S_H
    STA S_ARG
    LDA S_COUNT
    SEC
    SBC S_H
    STA S_COUNT
    JMP BuildRowsZone
BuildRowsLast:
    LDA S_HASDLI
    BNE BuildRowsLast1
    JMP BuildRun
BuildRowsLast1:
    LDA #$01
    STA S_H
    LDA #$80
    STA S_FLAG
    INC S_NDLI
    JSR ZoneEmit
    JMP BuildRun
; mode-8 row: its lines one a zone, the flagged last one included
; the three mode-8 rows showed the first 30 bytes of buffer row 0, which
; holds only the top's background (sky or black: FINDINGS "The top rows as
; objects"); the buffers no longer hold row 0, so they are empty lines over
; the background colour
BuildM8Run:
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
    LDA #$01
    STA S_H
BuildM8Line:
    LDA #$00
    STA S_FLAG
    LDA S_COUNT
    BEQ BuildM8Last
    INC S_MRG               ; (empty lines: one zone, PutEntry)
    JSR PutEntry
    DEC S_COUNT
    JMP BuildM8Line
BuildM8Last:
    LDA S_HASDLI
    BEQ BuildM8Done
    LDA #$80
    STA S_FLAG
    INC S_NDLI
    INC S_MRG
    JSR PutEntry
BuildM8Done:
    JMP BuildRun
; blank lines
BuildBlankRun:
    JSR BlankZones
    LDA S_HASDLI
    BEQ BuildBlankDone
    INC S_NDLI
    JSR TopSkyOnMark        ; (ours: its number, and C set)
    BCC BuildBlankGame
    JSR BlankFlaggedP       ; (the black line's list: TopSkyOnMark)
    JMP BuildBlankDone
BuildBlankGame:
    JSR BlankFlagged
BuildBlankDone:
    JMP BuildRun
BuildEnd:
; blanks to the end of the list; line VBI_LINE stands in for the vertical
; blank (where ANTIC's comes), leaving the game's handler the bottom lines and
; the top border to finish in before the next frame's first DLI, as on the
; XEGS (its DLI and VBI handlers share save bytes, so they must not overlap)
    LDA #VBI_LINE
    SEC
    SBC S_LINES
    STA S_COUNT
    JSR BlankZones
    JSR BlankFlagged
    LDA #DLL_LINES
    SEC
    SBC S_LINES
    STA S_COUNT
    JSR BlankZones
BuildDone:
    LDA S_PPD2              ; no sky off: no sky on either (the sky would
    BNE BuildDone1          ; reach the bottom)
    STA S_PPD1
BuildDone1:
    LDA S_DLBUF
    BNE BuildDoneB
    LDA S_NDLI
    CLC
    ADC #$01
    STA S_VBI_A
    LDA S_PPD1
    STA S_PDA1
    LDA S_PPD2
    STA S_PDA2
    LDA S_DLLO
    STA S_DLIST_A
    LDA S_DLHI
    STA S_DLIST_A+1
    RTS
BuildDoneB:
    LDA S_NDLI
    CLC
    ADC #$01
    STA S_VBI_B
    LDA S_PPD1
    STA S_PDB1
    LDA S_PPD2
    STA S_PDB2
    LDA S_DLLO
    STA S_DLIST_B
    LDA S_DLHI
    STA S_DLIST_B+1
    RTS

; S_COUNT blank lines in zones of up to 16
BlankZones:
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
BlankZone:
    LDA S_COUNT
    BEQ BlankDone
    CMP #17
    BCC BlankZoneH
    LDA #16
BlankZoneH:
    STA S_H
    SEC
    SBC #$01
    STA S_FLAG
    INC S_MRG               ; (may join an empty zone before it)
    JSR PutEntry
    LDA S_COUNT
    SEC
    SBC S_H
    STA S_COUNT
    JMP BlankZone
BlankDone:
    RTS
; one blank line with a DLI
BlankFlagged:
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
    INC S_MRG               ; (empty: the lines after it may join it)
BlankFlaggedP:
    LDA #$01
    STA S_H
    LDA #$80
    STA S_FLAG
    JMP PutEntry

; buffer rows as the bitmap's zones, or blank (the title's, story's and
; ending's lists are BuildTs's)

ZoneH:
    JSR OBlankBit
    BEQ ZoneHBmp
    LDA S_COUNT             ; blanked: the rows as empty zones
    CMP #17
    BCC ZoneHBl
    LDA #16
ZoneHBl:
    RTS
ZoneHBmp:
    JMP RowsZoneH
ZoneEmit:
    JSR OBlankBit
    BEQ ZoneEmitBmp
    JMP ZoneEmitBlank
ZoneEmitBmp:
    JMP RowsZoneEmit
; the buffer being built's bitmap holds objects' data (S_OBLANK bit 0 A,
; bit 1 B): A nonzero
OBlankBit:
    LDA S_SLOT
    BNE OBlankBitB
    LDA S_OBLANK
    AND #$01
    RTS
OBlankBitB:
    LDA S_OBLANK
    AND #$02
    RTS

; the next zone's height for buffer rows from S_ARG, S_COUNT of them: at
; most 16, and within the row's column
RowsZoneH:
    LDA S_ARG               ; the status rows and below are not the
    CMP #ST_ROW             ; buffer's (it ends above them): at most 16
    BCC RowsZoneTop
    LDA S_COUNT
    CMP #17
    BCC RowsZoneStH
    LDA #16
RowsZoneStH:
    RTS
RowsZoneTop:
    CMP #FB_TOP
    BCS RowsZoneBuf
RowsZoneTMod:               ; the top rows: zones on the TOP_ZONE grid
    CMP #TOP_ZONE
    BCC RowsZoneTIn
    SBC #TOP_ZONE
    JMP RowsZoneTMod
RowsZoneTIn:
    STA S_BTMP
    LDA #TOP_ZONE
    SEC
    SBC S_BTMP              ; rows left in the grid's zone
    CMP S_COUNT
    BCC RowsZoneT1
    LDA S_COUNT
RowsZoneT1:
    STA S_BTMP              ; and not past the cut (FB_TOP need not be on
    LDA #FB_TOP             ; the grid: the last top zone is cut short)
    SEC
    SBC S_ARG
    CMP S_BTMP
    BCC RowsZoneTC
    LDA S_BTMP
RowsZoneTC:
    CMP #17
    BCC RowsZoneT2
    LDA #16
RowsZoneT2:
    RTS
RowsZoneBuf:
    SEC
    SBC #FB_TOP             ; the buffer's rows begin at FB_TOP
RowsZoneMod:
    CMP #FB_BAND
    BCC RowsZoneIn
    SBC #FB_BAND
    JMP RowsZoneMod
RowsZoneIn:
    STA S_BTMP
    LDA #FB_BAND
    SEC
    SBC S_BTMP              ; rows left in the column
    CMP S_COUNT
    BCC RowsZoneH1
    LDA S_COUNT
RowsZoneH1:
    PHA                     ; and, in the actors' rows (to BAND_ZEND, the
    JSR RowsBand            ; title off), in its BAND_ZH-row zone of the column
    BCC RowsZoneH16         ; (their slices are cut on that grid: FINDINGS "The
                            ; fighters as objects: decided, and the plan");
                            ; else at most 16
    LDA S_BTMP
    AND #BAND_ZH-1
    EOR #$FF
    SEC
    ADC #BAND_ZH
    STA S_BTMP
    PLA
    CMP S_BTMP
    BCC RowsZoneH2
    LDA S_BTMP
    JMP RowsZoneH2
RowsZoneH16:
    PLA
    CMP #17
    BCC RowsZoneH2
    LDA #16
RowsZoneH2:
    STA S_H                 ; and not across the status rows' top
    LDA S_ARG
    CMP #ST_ROW
    BCS RowsZoneH3
    LDA #ST_ROW
    SEC
    SBC S_ARG
    CMP S_H
    BCC RowsZoneH4
RowsZoneH3:
    LDA S_H
RowsZoneH4:
    RTS

; the buffer row S_ARG (FB_TOP on) is in the actors' rows with their own
; zones and lists (to BAND_ZEND, and the title off: its canvases are in the
; band lists' pages): C set
RowsBand:
    LDA S_TITLEA
    ORA S_TITLEB
    BNE RowsBandNo
    LDA #BAND_ZEND
    CMP S_ARG
    RTS
RowsBandNo:
    CLC
    RTS

; a band zone (RowsEmitIn: X the buffer column 0-5, S_BTMP the zone's first
; row in it): its entry in the buffer's zone table (ZT_*: the DLL entry
; PutEntry writes next, the grid cell, the zone's first line in it, its
; height, the bitmap row's address), and its list (BandWrite)
BandZone:
    LDY #$00
    LDA S_SLOT
    BEQ BandZone1
    INY
BandZone1:
    STY S_FBUF
    LDA S_ZTN,Y
    CMP #16                 ; (at most 16 a buffer: the build checks)
    BCC BandZone2
    LDA #15
BandZone2:
    STA S_FTK                ; the zones before this one
    TXA                     ; the grid cell: 4 a column, BAND_ZH rows each
    SEC
    SBC S_SLOT
    ASL A
    ASL A
    STA S_FZ
    LDA S_BTMP
    LSR A
    LSR A
    LSR A
    CLC
    ADC S_FZ
    STA S_FZ
    LDA S_BTMP
    AND #BAND_ZH-1
    STA S_FL0               ; the zone's first line in it
    LDA #FB_PTOP+1          ; the bitmap row: the bottom row's page
    SEC
    SBC S_BTMP
    SEC
    SBC S_H
    STA S_BTMP+1
    LDA FbSlotLo,X
    STA S_BTMP
    LDA S_FBUF              ; the entry: 16 a buffer
    ASL A
    ASL A
    ASL A
    ASL A
    ORA S_FTK
    TAX
    LDA ZP_P2
    STA ZT_DLL,X
    LDA S_FZ
    STA ZT_CELL,X
    LDA S_FL0               ; (its first line in the cell, bits 4-6; its
    ASL A                   ; height, 0-3; bit 7 BandWrite's)
    ASL A
    ASL A
    ASL A
    ORA S_H
    STA ZT_H,X
    LDY S_FBUF
    LDA S_FTK
    CLC
    ADC #$01
    STA S_ZTN,Y
    LDA #$FF                ; (no cell's columns kept: BandWrite)
    STA FB_CELL
    JSR BandWrite
    JMP RowsEmitEntry

; the zone of S_H buffer rows from row S_ARG: its display list at S_DLSP
; (S_BDLP for a band zone: RowsBand)
; (the row's two 20-byte halves; MARIA reads line k of the zone at page
; high + OFFSET, OFFSET counting down from S_H - 1, so high is the bottom
; row's page), and its DLL entry with S_FLAG's DLI
RowsZoneEmit:
    LDA S_ARG               ; the status rows: the buffer's status list (the
    CMP #ST_ROW             ; whole bar a zone), else nothing
    BCC RowsEmitBmp
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
    LDA S_ARG
    CMP #ST_ROW
    BNE RowsEmitSt
    LDA S_H
    CMP #ST_ROWS
    BNE RowsEmitSt
    LDA #<STATUS_DLA
    LDX S_SLOT
    BEQ RowsEmitStA
    LDA #<STATUS_DLB
RowsEmitStA:
    STA S_ROWP
    LDA #>STATUS_DLA
    STA S_ROWP+1
RowsEmitSt:
    JMP RowsEmitEntry
RowsEmitBmp:
    LDA S_ARG
    CMP #FB_TOP
    BCS RowsEmitBuf
    JMP TopEmitF            ; the top rows: objects
RowsEmitBuf:
    SEC
    SBC #FB_TOP
    LDX S_SLOT
RowsEmitMod:
    CMP #FB_BAND
    BCC RowsEmitIn
    SBC #FB_BAND
    INX
    JMP RowsEmitMod
RowsEmitIn:
    STA S_BTMP              ; the top row's place in its column
    JSR RowsBand            ; a band zone: its own list (BandZone)
    BCC RowsEmitPlain
    JMP BandZone
RowsEmitPlain:
    LDA S_L1                ; level 1: its bottom lists (L1BOT: A's, L1BOTB:  #V1
    BEQ RowsEmitPl1         ; B's; rows 145 on: L1BOT_N bytes on), written  #V1
    BIT L1_SF               ; (the canvas: the bitmap's)  #V1
    BMI RowsEmitPl1  ; #V1
    LDA ZP_P1               ; now (L1Zone: zones L1_ZBT, +1) as L1Flip writes
    PHA                     ; them too
    LDA ZP_P1+1
    PHA
    LDA L1_ZBT
    STA L1_K
    LDX #$00                ; (the buffer: S_SLOT 0 A's, else B's)
    STX L1_B
    LDA #<L1BOT
    LDY #>L1BOT
    LDX S_SLOT
    BEQ RowsEmitL1
    INC L1_B
    LDA #<L1BOTB
    LDY #>L1BOTB
RowsEmitL1:
    LDX S_ARG
    CPX #145
    BCC RowsEmitL2
    CLC
    ADC #L1BOT_N
    INC L1_K
RowsEmitL2:
    STA S_ROWP
    STA ZP_P1
    STY S_ROWP+1
    STY ZP_P1+1
    LDA #$01
    STA L1_WR
    LDA #L1BOT_N-2
    STA L1_WMAX
    LDA #<L1Zone
    LDX #>L1Zone
    LDY #L1_HOME
    JSR L1CallK
    LDA #$00
    STA (ZP_P1),Y
    INY
    STA (ZP_P1),Y
    PLA
    STA ZP_P1+1
    PLA
    STA ZP_P1
    JMP RowsEmitEntry
RowsEmitPl1:  ; #V1
    LDA #FB_PTOP+1  ; #V1
    SEC  ; #V1
    SBC S_BTMP  ; #V1
    SEC  ; #V1
    SBC S_H  ; #V1
    STA S_BTMP+1            ; the bottom row's page  #V1
    LDA FbSlotLo,X  ; #V1
    STA S_BTMP  ; #V1
    LDA ZP_P1  ; #V1
    PHA  ; #V1
    LDA ZP_P1+1  ; #V1
    PHA  ; #V1
    LDA S_DLSP              ; the list: in DLS_A/B  #V1
    STA ZP_P1  ; #V1
    LDA S_DLSP+1  ; #V1
    STA ZP_P1+1  ; #V1
    LDY #$00  ; #V1
    LDA S_BTMP  ; #V1
    STA (ZP_P1),Y  ; #V1
    INY  ; #V1
    LDA #DL_W  ; #V1
    STA (ZP_P1),Y  ; #V1
    INY  ; #V1
    LDA S_BTMP+1  ; #V1
    STA (ZP_P1),Y  ; #V1
    INY  ; #V1
    LDA #$00  ; #V1
    STA (ZP_P1),Y  ; #V1
    INY  ; #V1
    LDA S_BTMP  ; #V1
    CLC  ; #V1
    ADC #20  ; #V1
    STA (ZP_P1),Y  ; #V1
    INY  ; #V1
    LDA #DL_W  ; #V1
    STA (ZP_P1),Y  ; #V1
    INY  ; #V1
    LDA S_BTMP+1  ; #V1
    STA (ZP_P1),Y  ; #V1
    INY  ; #V1
    LDA #80  ; #V1
    STA (ZP_P1),Y  ; #V1
    INY  ; #V1
    LDA #$00  ; #V1
    STA (ZP_P1),Y  ; #V1
    INY  ; #V1
    STA (ZP_P1),Y  ; #V1
    PLA  ; #V1
    STA ZP_P1+1  ; #V1
    PLA  ; #V1
    STA ZP_P1  ; #V1
    LDA S_DLSP  ; #V1
    STA S_ROWP  ; #V1
    LDA S_DLSP+1  ; #V1
    STA S_ROWP+1  ; #V1
    LDA S_DLSP  ; #V1
    CLC  ; #V1
    ADC #10  ; #V1
    STA S_DLSP  ; #V1
    BCC RowsEmitEntry  ; #V1
    INC S_DLSP+1  ; #V1
RowsEmitEntry:
    LDA S_H
    SEC
    SBC #$01
    ORA S_FLAG
    STA S_FLAG
    JMP PutEntry

; one DLL entry (S_FLAG: DLI flag and OFFSET; S_ROWP: its DL) covering S_H
; lines (never past the list's end). An empty line or run with S_MRG bit 0
; (the blank and mode-8 paths') and no DLI joins the entry before it when
; that one was such too (S_MRG bit 7) and they make 16 lines at most: the
; empty top lines in zones, not a DLL entry a line (MARIA's time)
PutEntry:
    LDA S_LINES
    CMP #DLL_LINES
    BCC PutEntryGo
    RTS
PutEntryGo:
    LDA S_MRG
    CMP #$81
    BNE PutEntryNew
    LDA S_FLAG
    BMI PutEntryNew
    LDA ZP_P2               ; (the entry before: back 3)
    SEC
    SBC #$03
    STA ZP_P2
    BCS PutEntryM1
    DEC ZP_P2+1
PutEntryM1:
    LDY #$00
    LDA (ZP_P2),Y
    AND #$0F
    SEC                     ; (its lines - 1, + S_H: 15 at most)
    ADC S_H
    CMP #17
    BCS PutEntryM2
    SBC #$00                ; (C clear: - 1)
    STA S_BTMP
    LDA (ZP_P2),Y
    AND #$F0
    ORA S_BTMP
    STA (ZP_P2),Y
    JSR PutEntryFwd
    LDA #$80
    STA S_MRG
    JMP PutEntryDone
PutEntryM2:
    LDA (ZP_P2),Y           ; (more than 16: the entry before filled to 16
    AND #$0F                ; lines, the rest an entry of its own)
    EOR #$0F                ; (its room: 15 - its OFFSET)
    BEQ PutEntryM3
    STA S_BTMP
    LDA (ZP_P2),Y
    ORA #$0F
    STA (ZP_P2),Y
    LDA S_H                 ; (the new entry's OFFSET: S_H - room - 1; S_H and
    CLC                     ; S_LINES as they are: the two hold S_H lines, and
    SBC S_BTMP              ; the callers count S_H)
    STA S_BTMP
    LDA S_FLAG
    AND #$F0
    ORA S_BTMP
    STA S_FLAG
PutEntryM3:
    JSR PutEntryFwd
PutEntryNew:
    LDA S_MRG               ; (this one may take the next if it is empty)
    ROR A
    LDA #$00
    ROR A
    STA S_MRG
    LDY #$00
    LDA S_FLAG
    STA (ZP_P2),Y
    INY
    LDA S_ROWP+1
    STA (ZP_P2),Y
    INY
    LDA S_ROWP
    STA (ZP_P2),Y
    JSR PutEntryFwd
PutEntryDone:
    LDA S_LINES
    CLC
    ADC S_H
    STA S_LINES
    RTS
PutEntryFwd:
    LDA ZP_P2
    CLC
    ADC #$03
    STA ZP_P2
    BCC PutEntryFwd1
    INC ZP_P2+1
PutEntryFwd1:
    RTS

; an empty zone of S_H rows (S_FLAG's DLI)
ZoneEmitBlank:
    LDA #<DL_EMPTY
    STA S_ROWP
    LDA #>DL_EMPTY
    STA S_ROWP+1
    LDA S_H
    SEC
    SBC #$01
    ORA S_FLAG
    STA S_FLAG
    JMP PutEntry

