"""Disassemble the original (XEGS) game's code from a scene's memory view
(port/dis.py memory: the scene's code at $1000, data at $6000, banks 14 and
15 at $8000/$A000), with probes/mdis.py's opcode table.

    python probes/xedis.py SCENE START [COUNT]     (hex START, COUNT bytes)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
sys.path.insert(0, HERE)
import dis as D      # noqa: E402
import mdis          # noqa: E402

scene, start = int(sys.argv[1]), int(sys.argv[2], 16)
count = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x40
m = D.memory(scene)
lo = start & 0xF000
buf = bytes(m.get(lo + i, 0) for i in range(0x10000 - lo if lo else 0x10000))
print(mdis.disasm(buf, lo, start, count))
