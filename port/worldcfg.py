"""The tiles scenes' worlds' settings (FINDINGS "Level 2 as tiles", "Levels
3 and 4 as tiles"): for probes/worldlist.py (the world lists) and
probes/tilemodel.py (the runtime's model).

A scene's worlds: scrolled ones (world x = screen x - V) and rooms (fixed on
the screen: world x = screen x). A buffer's world follows the markers, as
the runtime's L1MK_* (image, kind or None, row or None, world, only out of a
room) and its rooms' floor fill (rows 118-145, a pattern). Per world its
base (the rows' bytes before any draw); images never in a world (objects:
OBJECTS; the rooms' figures, FIGURES); a scrolled world's own images
(WORLD_IMAGES: the others are objects); the images the game draws after
the fighters (FRONT: probes/p7800-l1cap.lua's B lines' last field, FT_SEEN),
objects in front of them, never in a world; but FRONT_OR's (stores with
colours besides black: the door frames' posts, level 2's gate post) stay in
their world and their front copy is an OR, palette 1 (the band's: palettes 2
and 3 hold the top rows' colours, which in the rooms aren't the band's), its
black clear."""

FRONT_OR = {0x96CE, 0xA1EC}

FLOOR_STRIPES_55 = [(r, r + 1, 0x55 if r % 2 else 0x00) for r in range(118, 146)]
FLOOR_STRIPES_AA = [(r, r + 1, 0x00 if r % 2 else 0xAA) for r in range(118, 145)]   # (the rooms' floor fill's)

# the rooms' images: the door frames (both sides, their feet) and the
# princess's room's (its frame, her bed and furniture)
FRAMES = {0x964A, 0x96CE, 0x971D, 0x9743}
PRINCESS_ROOM = {0x964A, 0x96CE, 0xB700, 0xB7C8, 0xB9BE, 0xBABF, 0xBAD0}

CFG = {
    # scene 0, the attract loop after its story (FINDINGS "The attract loop as
    # tiles"): Akuma's cell ("0c": the right door frame marks it), the
    # princess's room ("0p": her bed), both fixed; level 1's cliff and first
    # gate ("0g": its world 0's images, scrolled, V 108-192, no wrap). The
    # fight's left post ($A684) is drawn piece by piece after the fighters:
    # one column shape in front (FRONT_COLS). Level 1's objects, the door,
    # the cliff's pictures drawn once and the figures are objects
    0: dict(
        scene=0, out="s0world.txt", scrolled=["0g"], rooms=["0c", "0p"], v_wrap=0,
        markers=[(0x964A, "A", 60, "0c", False), (0xB7C8, None, None, "0p", False),
                 (0xA68A, None, None, "0g", False), (0xAA11, None, None, "0g", False),
                 (0xAA7D, None, None, "0g", False)],
        room_floor=(("pat", 118, 145, 0xAA, 0x00), "0c"),
        # (the gate's rows: the sky, the rails ($AA11, drawn every 8 pixels at
        # row 69 as the view scrolls: each place seen once, so their rows are
        # the base, as level 1's rails are its buffer's background), black,
        # the floor's stripes)
        base={"0g": [(65, 69, 0xAA), (69, 70, 0xFF), (70, 73, 0x00), (73, 76, 0xAA), (76, 77, 0xFF),
                     (77, 118, 0x00), (118, 146, 0x55)], "0c": [], "0p": []},
        objects={0xAA23, 0xAA31, 0xA9B8, 0xA9E2, 0xAB4A, 0xAB94, 0x9980,
                 0xA3C5, 0xA3E9, 0xA40B, 0xA425, 0xA45A, 0xA4A4, 0xA4D2, 0xA4F2, 0xA548, 0xA572,
                 0xA5CC, 0xA5DC},
        front={0x96CE, 0xA684},
        world_images={"0g": {0xA68A, 0xA6A6, 0xA6C0, 0xA6D4, 0xA6EF, 0xA703, 0xA85F, 0xA865, 0xA877,
                             0xA87B, 0xAA11, 0xAA7D, 0xAB7C, 0xAB8E, 0xAC1A},
                      "0c": FRAMES, "0p": PRINCESS_ROOM},
        figures={0x974B, 0x984F, 0x9858, 0x985C, 0x988B, 0x989D, 0x98AF, 0x98C1, 0x98D3, 0x9908,
                 0x9956, 0x9A62, 0x9EB8, 0x9F8C, 0x9FC4, 0x9FD8,
                 0xB4C4, 0xB4D4, 0xB500, 0xB536, 0xB55A, 0xB57E, 0xB5A2, 0xB5D7,
                 0xAD30, 0xAD88, 0xAE11, 0xAE9A, 0xAECC, 0xAF5E, 0xAFD3, 0xB029, 0xB067},
        front_cols=["L A684 0 0 65 135 0"],
        # (the gate's first pictures' clear, rows 76-118 black, the base:
        # drawn before the sea, which the world list would put it over; and
        # the fighters' box erases, rows 77-118 black, the base, at the same
        # place in two pictures as the hero stands: over the fence)
        drop_fills=[("rect", 76, 118, 0x00, 0x55), ("rect", 77, 118, 0x00, 0x55)],
    ),
    2: dict(
        scene=2, out="l2world.txt", scrolled=["2"], rooms=["2c", "2p"], v_wrap=64,
        markers=[(0xA4F0, None, None, "2", False), (0xA4D8, None, None, "2", False),
                 (0x964A, "MR", 60, "2c", True), (0xB7C8, None, None, "2p", False)],
        room_floor=(("pat", 118, 145, 0xAA, 0x00), "2c"),
        # the fortress's rows: the palisade's beam (rows 65-66: $AA, the
        # stakes over it), black, the floor's stripes ($55 on odd rows)
        base={"2": [(65, 67, 0xAA)] + FLOOR_STRIPES_55, "2c": [], "2p": []},
        # the stakes and spikes: their places follow the view but for the
        # game's rounding of its half pixels (1-3 pixels off at times)
        objects={0xA4F0, 0xA4D8, 0xA5B8},
        front={0xA0FC, 0xA0B4, 0xA02C, 0xA000, 0xA1EC, 0x96CE, 0x9980},
        # the fortress's own images: the gate's pieces and the end walls
        world_images={"2": {0xA103, 0xA12D, 0xA1EC, 0xA000, 0xA274, 0xA602, 0xA546}},
        # Akuma's pieces in the cell (his arm's poses change), the princess's
        figures={0x974B, 0x984F, 0x9F8C, 0x9EB8, 0x9A62, 0x98D3, 0x9FC4, 0x9FD8, 0x9858, 0x985C,
                 0x9908, 0x9956, 0xB300, 0xB33E, 0xB36D},
    ),
    # level 3: the first room (the stairs, $A000 at world -1,024; the
    # corridor; the right door frame at -764) scrolled in, V 1,024 down to
    # 896; then rooms with both frames, all alike, at V 896 (a room: "3r");
    # the princess's room's cutscene ("3p"). The door ($9980, OR: it opens)
    # and the figures are objects
    3: dict(
        scene=3, out="l3world.txt", scrolled=["3s"], rooms=["3r", "3p"], v_wrap=64,
        markers=[(0xA000, None, 51, "3s", False),
                 (0x964A, "MR", 60, "3r", True), (0xB7C8, None, None, "3p", False)],
        room_floor=(("pat", 118, 145, 0xAA, 0x00), "3r"),
        # (the first room's floor: its stripes, drawn once and the same at
        # any view: the game doesn't draw them again as it scrolls)
        base={"3s": FLOOR_STRIPES_AA, "3r": [], "3p": []},
        objects={0x9980},
        front={0x96CE, 0x9980, 0xA0FC, 0xA0B4, 0xA1EC},
        mask01=True,
        world_images={"3s": {0xA000, 0x964A, 0x96CE, 0x971D, 0x9743}, "3r": FRAMES, "3p": PRINCESS_ROOM},
        figures={0xB300, 0xB33E, 0xB36D, 0xB391, 0xB3AE, 0xB0FE, 0xB430},
    ),
    # level 4: Akuma's room (both door frames: "4r"; the right one marks
    # it) and the princess's room ("4p": her bed), both at V 896, fixed;
    # Akuma's and the princess's pieces objects
    4: dict(
        scene=4, out="l4world.txt", scrolled=[], rooms=["4r", "4p"], v_wrap=64,
        markers=[(0x964A, "A", 60, "4r", True), (0xB7C8, None, None, "4p", False)],
        room_floor=(("pat", 118, 145, 0xAA, 0x00), "4r"),
        base={"4r": [], "4p": []},
        objects={0x9980},
        front={0x96CE, 0x9980, 0xBAD0},
        mask01=True,
        world_images={"4r": FRAMES, "4p": PRINCESS_ROOM},
        figures={0xB300, 0xB33E, 0xB36D, 0xB391, 0xB3AE, 0xB0FE, 0xB430,
                 0xA280, 0xA200, 0xBD72, 0xBE1E, 0xBE7A, 0xB2D7},
        # (V2) the pieces a fighter-box erase takes out (its black covers them
        # on the original): the figures and the princess's kick, $A2EE her
        # leg, $BB29 (FINDINGS "The hardware test": her leg stayed)
        fbox={0xA2EE, 0xBB29},
    ),
}
