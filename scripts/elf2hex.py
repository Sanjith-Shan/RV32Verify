#!/usr/bin/env python3
"""Convert a RV32 ELF into a $readmemh word image plus a small metadata file.

    elf2hex.py prog.elf prog.hex [--base 0x80000000]

prog.hex  : "@<word index>" lines followed by one 32-bit word per line, word
            index i holding byte address base + 4*i (loaded by both the SV
            memory model and the C++ reference model).
prog.meta : key=value lines: entry, tohost, begin_signature, end_signature.
Standard library only.
"""
import argparse
import struct
import sys


def parse_elf(data):
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        sys.exit("not a little-endian ELF32 file")
    (e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags, e_ehsize,
     e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx) = struct.unpack_from("<HHIIIIIHHHHHH", data, 16)
    segs = []
    for i in range(e_phnum):
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = \
            struct.unpack_from("<IIIIIIII", data, e_phoff + i * e_phentsize)
        if p_type == 1 and p_memsz:  # PT_LOAD
            body = data[p_offset:p_offset + p_filesz] + b"\0" * (p_memsz - p_filesz)
            segs.append((p_paddr, body))
    syms = {}
    shdrs = [struct.unpack_from("<IIIIIIIIII", data, e_shoff + i * e_shentsize) for i in range(e_shnum)]
    for sh in shdrs:
        if sh[1] == 2:  # SHT_SYMTAB
            strtab = shdrs[sh[6]]
            for off in range(sh[4], sh[4] + sh[5], 16):
                st_name, st_value, st_size, st_info, st_other, st_shndx = struct.unpack_from("<IIIBBH", data, off)
                s = data[strtab[4] + st_name:data.index(b"\0", strtab[4] + st_name)].decode()
                if s:
                    syms[s] = st_value
    return e_entry, segs, syms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("elf")
    ap.add_argument("hex")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0x80000000)
    a = ap.parse_args()
    entry, segs, syms = parse_elf(open(a.elf, "rb").read())
    words = {}
    for addr, body in segs:
        body += b"\0" * (-len(body) % 4)
        for i in range(0, len(body), 4):
            words[(addr + i - a.base) // 4] = struct.unpack_from("<I", body, i)[0]
    out, expect = [], None
    for idx in sorted(words):
        if idx != expect:
            out.append("@%08x" % idx)
        out.append("%08x" % words[idx])
        expect = idx + 1
    open(a.hex, "w").write("\n".join(out) + "\n")
    meta = {"entry": entry}
    for k in ("tohost", "begin_signature", "end_signature"):
        if k in syms:
            meta[k] = syms[k]
    open(a.hex.rsplit(".", 1)[0] + ".meta", "w").write("".join("%s=0x%08x\n" % kv for kv in meta.items()))


if __name__ == "__main__":
    main()
