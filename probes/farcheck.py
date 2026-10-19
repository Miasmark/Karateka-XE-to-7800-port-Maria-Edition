"""Assemble each ;;; FAR piece of port/sys7800.asm on its own (every outside
symbol at a placeholder), to find a piece's own errors, such as a branch
out of range, before the build does. NAME: only pieces whose name has it.
    python probes/farcheck.py [NAME]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import xesource  # noqa: E402,F401  (puts the toolkit on the path)
import asm       # noqa: E402

MN = {'LDA', 'STA', 'LDX', 'STX', 'LDY', 'STY', 'JSR', 'JMP', 'RTS', 'CMP', 'CPX', 'CPY', 'BNE', 'BEQ', 'BCC',
      'BCS', 'BPL', 'BMI', 'BVC', 'BVS', 'INX', 'INY', 'DEX', 'DEY', 'INC', 'DEC', 'CLC', 'SEC', 'CLI', 'SEI',
      'CLD', 'CLV', 'ADC', 'SBC', 'AND', 'ORA', 'EOR', 'ASL', 'LSR', 'ROL', 'ROR', 'TAX', 'TAY', 'TXA', 'TYA',
      'TSX', 'TXS', 'PHA', 'PLA', 'PHP', 'PLP', 'BIT', 'NOP', 'RTI', 'BRK', 'A'}
src = open(os.path.join(HERE, "..", "port", "sys7800.asm"), encoding="utf-8").read()
want = sys.argv[1] if len(sys.argv) > 1 else ""
for p in src.split("\n;;; FAR")[1:]:
    name = p.split("\n", 1)[0]
    if want not in name:
        continue
    lines = p.split("\n", 1)[1].splitlines()
    labels = {m.group(1) for ln in lines for m in [re.match(r'^([A-Za-z_]\w*):', ln)] if m}
    syms = set(re.findall(r'\b([A-Z_][A-Za-z0-9_]*)\b', "\n".join(ln.split(';')[0] for ln in lines)))
    eqs = ["%s = $%04X" % (s, 0x2000 if s.startswith(('S_', 'G_', 'ZP', 'TOPL')) else 0xF600)
           for s in syms - labels - MN]
    text = eqs + ["    .org $F500"] + lines
    try:
        print("%-40s %4d bytes" % (name.strip(), len(asm.Assembler().assemble(text))))
    except Exception as e:
        m = re.search(r'line (\d+)', str(e))
        print("%-40s ERROR %s: %s" % (name.strip(), e, text[int(m.group(1)) - 1].strip() if m else ""))
