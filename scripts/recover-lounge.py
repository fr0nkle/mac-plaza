#!/usr/bin/env python3
"""Read-only, offline inspection and differential fixtures for US Menu v277.

Requires an existing local men.rpx. Never downloads or boots firmware. The tiny
instruction runner is deliberately limited to the audited routines listed below;
unknown instructions/calls and out-of-range memory accesses stop the run.
Generated binary-derived files belong under ignored Local Resources or .qa.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import zlib

SHA256 = 'b67deb8fb36889fd5451b89a5b1ce06b31abe341960c3bf1df84e9df4bbe1474'
MASK = 0xffffffff


def signed(value, bits=32):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def f32(value):
    return struct.unpack('>f', struct.pack('>f', value))[0]


def sections(path):
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SHA256:
        raise ValueError('Unsupported executable: this recovery profile requires US Menu v277')
    if raw[:6] != b'\x7fELF\x01\x02' or struct.unpack_from('>H', raw, 18)[0] != 20:
        raise ValueError('Expected big-endian ELF32 PowerPC')
    offset = struct.unpack_from('>I', raw, 32)[0]
    size, count, names = struct.unpack_from('>HHH', raw, 46)
    if size != 40 or count > 128 or offset + size * count > len(raw):
        raise ValueError('Invalid section table')
    result = []
    for index in range(count):
        name, kind, flags, address, start, length, link, info, alignment, entry = struct.unpack_from('>10I', raw, offset + index * size)
        if length > 32 * 1024 * 1024 or (kind != 8 and start + length > len(raw)):
            raise ValueError('Section outside file or size budget')
        data = b'' if kind == 8 else raw[start:start + length]
        if flags & 0x08000000:
            expected = int.from_bytes(data[:4], 'big')
            if expected > 32 * 1024 * 1024:
                raise ValueError('Inflated section exceeds size budget')
            inflater = zlib.decompressobj()
            data = inflater.decompress(data[4:], expected + 1)
            if len(data) != expected or not inflater.eof:
                raise ValueError('Invalid compressed section')
        result.append(dict(index=index, nameOffset=name, kind=kind, address=address, length=length,
                           data=data, link=link, entrySize=entry))
    strings = result[names]['data']
    for section in result:
        start = section.pop('nameOffset')
        section['name'] = strings[start:strings.index(0, start)].decode('ascii')
    # Resolve original ADDR32 relocations in data; never run relocation code.
    symbols = result[49]['data']
    for relocation_index, target_index in [(8, 3), (9, 4)]:
        section = result[target_index]
        data = bytearray(section['data'])
        relocs = result[relocation_index]['data']
        for start in range(0, len(relocs), 12):
            destination, info, addend = struct.unpack_from('>IIi', relocs, start)
            if info & 255 == 1:
                value = struct.unpack_from('>I', symbols, (info >> 8) * 16 + 4)[0]
                struct.pack_into('>I', data, destination - section['address'], (value + addend) & MASK)
        section['data'] = bytes(data)
    return result


def descriptors(parts):
    data = parts[4]['data']
    strings = parts[3]['data']
    rows = []
    for index in range(128):
        offset = 0x100f43f8 - parts[4]['address'] + index * 24
        pointer, blend, limit, flags, unused_a, unused_b = struct.unpack_from('>Iff3I', data, offset)
        start = pointer - parts[3]['address']
        name = strings[start:strings.index(0, start)].decode('ascii')
        if unused_a or unused_b:
            raise ValueError('Descriptor profile differs from expected layout')
        rows.append(dict(id=index, name=name, blendFrames=blend, blendLimit=limit, flags=flags))
    return rows


class RoutineRunner:
    """Non-JIT reference runner for the audited integer/FPU decision blocks.

    This is a development test oracle, not an application dependency or Wii U
    emulator. Original instructions supply every branch and arithmetic operation.
    No system calls, networking, rendering or arbitrary entry points are exposed.
    """
    def __init__(self, parts):
        self.memory = [(s['address'], bytearray(s['data'])) for s in parts if s['index'] in (2, 3, 4)]
        self.memory += [(0x1011c600, bytearray(0x100000)), (0x20000000, bytearray(0x20000))]
        self.r = [0] * 32
        self.f = [0.0] * 32
        self.secondary = [0.0] * 32
        self.heading_call = None
        self.fi = {}
        self.cr = [False] * 32
        self.lr = self.ctr = 0
        self.carry = False

    def region(self, address, size):
        for base, data in self.memory:
            if base <= address and address + size <= base + len(data):
                return data, address - base
        raise ValueError(f'Out-of-range reference memory: {address:08x}, {size}')

    def read(self, address, size=4):
        data, offset = self.region(address, size)
        return int.from_bytes(data[offset:offset + size], 'big')

    def write(self, address, value, size=4):
        data, offset = self.region(address, size)
        if address < 0x10000000:
            raise ValueError('Reference code is read-only')
        data[offset:offset + size] = (value & ((1 << (size * 8)) - 1)).to_bytes(size, 'big')

    def read_float(self, address, double=False):
        return struct.unpack('>d' if double else '>f', self.read(address, 8 if double else 4).to_bytes(8 if double else 4, 'big'))[0]

    def write_float(self, address, value, double=False):
        data = struct.pack('>d' if double else '>f', value)
        self.write(address, int.from_bytes(data, 'big'), len(data))

    def compare(self, field, a, b):
        self.cr[field * 4:field * 4 + 4] = [a < b, a > b, a == b, False]

    def branch(self, bo, bi):
        if not bo & 4:
            self.ctr = (self.ctr - 1) & MASK
        ctr_ok = bool(bo & 4) or ((self.ctr != 0) != bool(bo & 2))
        condition_ok = bool(bo & 16) or self.cr[bi] == bool(bo & 8)
        return ctr_ok and condition_ok

    def run(self, entry, stop=None, limit=1000):
        if entry not in (0x2454a98, 0x2454b34, 0x21902d4, 0x2183104, 0x2194214, 0x219a320, 0x2188b08, 0x2186808,
                         0x218e378, 0x218e60c, 0x21ad1e4, 0x21882b0, 0x218e99c, 0x218e7f4, 0x2185250, 0x2186c64, 0x21876a4, 0x219220c, 0x217f42c, 0x217ec30, 0x218e4ac, 0x21922b0, 0x2184dbc, 0x2184b24, 0x218ff0c, 0x2191bc8, 0x219237c, 0x2192450, 0x2192514, 0x2192580, 0x2186dbc, 0x2191d30) and not (0x218914c <= entry <= 0x21891ac and entry % 4 == 0):
            raise ValueError('Entry point is outside the audited routine list')
        self.r[1] = 0x2001f000
        self.lr = 0x2001fff0
        pc = entry
        for _ in range(limit):
            if pc in (stop if isinstance(stop, tuple) else (stop if stop is not None else 0x2001fff0,)):
                return self.r[3]
            if entry == 0x2191d30 and pc == 0x2191cd4:
                # Owner callback updates actor destinations outside this search.
                # Its node-occupant exchange is the only result read afterward.
                a,b=self.r[3:5]
                first,second=self.read(a+0x1c),self.read(b+0x1c)
                self.write(a+0x1c,second);self.write(b+0x1c,first)
                pc=self.lr
                continue
            if entry == 0x2186dbc and pc == 0x20009000:
                # Audited animation-controller boundary: capture type/rate, no
                # callback execution. The original branch still computes both.
                self.reaction_call = [self.read(self.r[4]),self.f[1]]
                pc = self.lr
                continue
            if entry == 0x2184b24 and pc == 0x2183104:
                # State output is already stored. Restrictions are separately
                # verified; their owner callbacks are outside this decision block.
                pc = self.lr
                continue
            if entry == 0x219a320 and pc == 0x218e12c:
                # Clip selection is already finished. This external adapter only
                # writes the group database cooldown and owner flag; its output
                # is not read again by the selector. Do not run the database.
                self.write(self.r[3] + 0x488, 1, 1)
                pc = self.lr
                continue
            if entry == 0x21ad1e4 and pc == 0x243fd18:
                # Explicit host geometry boundary: SDK point-to-segment distance.
                p = [self.read_float(self.r[3]+i*4) for i in range(2)]
                a = [self.read_float(self.r[4]+i*4) for i in range(2)]
                b = [self.read_float(self.r[4]+8+i*4) for i in range(2)]
                delta = [f32(b[i]-a[i]) for i in range(2)]
                squared = f32(delta[0]*delta[0]+f32(delta[1]*delta[1]))
                t = f32(f32(f32((p[0]-a[0])*delta[0])+f32((p[1]-a[1])*delta[1]))/squared) if squared else 0
                t = min(1,max(0,t))
                dx, dz = [f32(p[i]-f32(a[i]+t*delta[i])) for i in range(2)]
                self.f[1] = f32(dx*dx+f32(dz*dz))
                pc = self.lr
                continue
            if entry in (0x21882b0,0x218e7f4,0x2185250,0x2186c64,0x21876a4,0x2184b24,0x2191bc8,0x2186dbc) and pc == 0x200533c:
                # Original SDK normalization boundary, with host sqrt.
                values = [self.read_float(self.r[3]+i*4) for i in range(3)]
                length = f32(math.sqrt(sum(x*x for x in values)))
                if length:
                    for i,x in enumerate(values): self.write_float(self.r[3]+i*4,f32(x/length))
                self.f[1] = length
                pc = self.lr
                continue
            if entry == 0x2186c64 and pc == 0x260db38:
                self.f[1] = f32(math.sqrt(sum(self.read_float(self.r[3]+i*4)**2 for i in range(3))))
                pc = self.lr
                continue
            if entry == 0x21882b0 and pc == 0x21867c8:
                # Capture the recovered root's heading inputs. Scalar turning
                # is separately checked against its original instruction block.
                self.heading_call = [self.read_float(self.r[4]+i*4) for i in (0,2)]+[self.f[1],self.f[2]]
                pc = self.lr
                continue
            if entry in (0x21882b0,0x21922b0) and pc == 0x265afd8:
                self.f[1] = math.atan2(self.f[1],self.f[2])
                pc = self.lr
                continue
            word = self.read(pc)
            op = word >> 26
            d, a, b = (word >> 21) & 31, (word >> 16) & 31, (word >> 11) & 31
            imm = signed(word & 65535, 16)
            following = pc + 4
            result = None
            record = False
            if op in (14, 15):
                self.r[d] = ((self.r[a] if a else 0) + (imm << (16 if op == 15 else 0))) & MASK
            elif op == 7:
                self.r[d] = (self.r[a] * imm) & MASK
            elif op in (12, 13):
                total = self.r[a] + (imm & MASK)
                self.carry = total > MASK
                self.r[d] = total & MASK
                if op == 13: self.compare(0, signed(self.r[d]), 0)
            elif op in (10, 11):
                self.compare((word >> 23) & 7, self.r[a] if op == 10 else signed(self.r[a]), word & 65535 if op == 10 else imm)
            elif op in (24, 25):
                self.r[a] = self.r[d] | ((word & 65535) << (16 if op == 25 else 0))
            elif op in (26, 27):
                self.r[a] = self.r[d] ^ ((word & 65535) << (16 if op == 27 else 0))
            elif op in (28, 29):
                self.r[a] = self.r[d] & ((word & 65535) << (16 if op == 29 else 0))
                self.compare(0, signed(self.r[a]), 0)
            elif op == 21:
                sh, mb, me = b, (word >> 6) & 31, (word >> 1) & 31
                value = ((self.r[d] << sh) | (self.r[d] >> ((32 - sh) & 31))) & MASK
                mask = sum(1 << (31 - i) for i in range(32) if (mb <= i <= me if mb <= me else i >= mb or i <= me))
                self.r[a] = value & mask
                if word & 1: self.compare(0, signed(self.r[a]), 0)
            elif op in (32, 34, 40, 42):
                size = 4 if op == 32 else 1 if op == 34 else 2
                
                try: value = self.read(((self.r[a] if a else 0) + imm) & MASK, size)
                except ValueError as error: raise ValueError(f'{error} at {pc:08x}, entry {entry:08x}') from error
                self.r[d] = (signed(value, 16) & MASK) if op == 42 else value
            elif op in (36, 37, 38):
                address = ((self.r[a] if a else 0) + imm) & MASK
                self.write(address, self.r[d], 1 if op == 38 else 4)
                if op == 37: self.r[a] = address
            elif op == 46:
                for register in range(d, 32): self.r[register] = self.read(self.r[a] + imm + (register - d) * 4)
            elif op == 47:
                for register in range(d, 32): self.write(self.r[a] + imm + (register - d) * 4, self.r[register])
            elif op in (48, 49, 50):
                self.f[d] = self.read_float(self.r[a] + imm, op == 50)
                if op == 49: self.r[a] = (self.r[a] + imm) & MASK
            elif op in (52, 54):
                self.write_float(self.r[a] + imm, self.f[d], op == 54)
            elif op == 18:
                delta = signed(word & 0x03fffffc, 26)
                if word & 1: self.lr = following
                following = delta & MASK if word & 2 else (pc + delta) & MASK
            elif op == 16:
                if self.branch(d, a):
                    delta = signed(word & 0xfffc, 16)
                    if word & 1: self.lr = following
                    following = delta & MASK if word & 2 else (pc + delta) & MASK
            elif op == 19 and (word >> 1) & 1023 == 16:
                if self.branch(d, a): following = self.lr & ~3
            elif op == 19 and (word >> 1) & 1023 == 528:
                target = self.ctr & ~3
                allowed = entry == 0x219a320 and 0x219a320 <= target <= 0x219acac
                allowed |= entry == 0x2184b24 and target in (*range(0x2184c40,0x2184c5c,4),*range(0x2185220,0x218523c,4))
                if entry == 0x2186dbc and target == 0x20009000 and word & 1:
                    self.lr = following
                    allowed = True
                elif word & 1:
                    raise ValueError('Indirect call outside audited reaction boundary')
                if not allowed:
                    raise ValueError('Indirect branch outside audited idle switch')
                following = target
            elif op == 31:
                xo = (word >> 1) & 1023
                if xo == 19:
                    self.r[d] = sum(int(value) << (31-index) for index,value in enumerate(self.cr))
                elif xo == 26:
                    self.r[a] = 32-self.r[d].bit_length()
                elif xo in (0, 32):
                    self.compare((word >> 23) & 7, signed(self.r[a]) if xo == 0 else self.r[a], signed(self.r[b]) if xo == 0 else self.r[b])
                elif xo == 23:
                    self.r[d] = self.read(((self.r[a] if a else 0) + self.r[b]) & MASK)
                elif xo == 87:
                    self.r[d] = self.read(((self.r[a] if a else 0) + self.r[b]) & MASK, 1)
                elif xo == 983:
                    self.write(((self.r[a] if a else 0) + self.r[b]) & MASK, self.fi[d])
                elif xo == 339:
                    spr = ((word >> 16) & 31) | (((word >> 11) & 31) << 5)
                    if spr != 8: raise ValueError('Unexpected special register read')
                    self.r[d] = self.lr
                elif xo == 467:
                    spr = ((word >> 16) & 31) | (((word >> 11) & 31) << 5)
                    if spr == 9: self.ctr = self.r[d]
                    elif spr == 8: self.lr = self.r[d]
                    else: raise ValueError('Unexpected special register write')
                else:
                    if xo == 316: result = self.r[d] ^ self.r[b]
                    elif xo == 444: result = self.r[d] | self.r[b]
                    elif xo == 28: result = self.r[d] & self.r[b]
                    elif xo == 24: result = self.r[d] << (self.r[b] & 63)
                    elif xo == 536: result = self.r[d] >> (self.r[b] & 63)
                    elif xo == 136:
                        total = ((~self.r[a]) & MASK) + self.r[b] + int(self.carry)
                        self.carry = total > MASK
                        result = total
                    elif xo == 40: result = self.r[b] - self.r[a]
                    elif xo == 104: result = -self.r[a]
                    elif xo == 75: result = (signed(self.r[a])*signed(self.r[b])) >> 32
                    elif xo == 824:
                        value = signed(self.r[d]); result = value >> b
                        self.carry = value < 0 and bool(value & ((1<<b)-1))
                    elif xo == 202:
                        result = self.r[a]+int(self.carry); self.carry = result > MASK
                    elif xo == 11: result = (self.r[a] * self.r[b]) >> 32
                    elif xo == 235: result = self.r[a] * self.r[b]
                    elif xo == 266: result = self.r[a] + self.r[b]
                    elif xo == 491: result = int(signed(self.r[a])/signed(self.r[b]))
                    else: raise ValueError(f'Unsupported integer instruction {word:08x} at {pc:08x}')
                    target = d if xo in (202, 75, 11, 40, 104, 136, 235, 266, 491) else a
                    self.r[target] = result & MASK
                    if word & 1: self.compare(0, signed(self.r[target]), 0)
            elif op == 63:
                xo = (word >> 1) & 1023
                if xo == 0: self.compare((word >> 23) & 7, self.f[a], self.f[b])
                elif xo == 15: self.fi[d] = int(self.f[b]) & MASK
                elif xo == 12: self.f[d] = f32(self.f[b])
                elif xo == 20: self.f[d] = self.f[a] - self.f[b]
                elif xo == 21: self.f[d] = self.f[a] + self.f[b]
                elif (word >> 1) & 31 == 25: self.f[d] = self.f[a] * self.f[(word >> 6) & 31]
                elif xo == 40: self.f[d] = -self.f[b]
                elif xo == 72: self.f[d] = self.f[b]
                elif xo == 264: self.f[d] = abs(self.f[b])
                elif xo == 26 and entry in (0x21882b0,0x2185250,0x217f42c,0x2184b24):
                    # Host reciprocal sqrt, not a hardware-estimate emulator.
                    self.f[d] = 1/math.sqrt(self.f[b])
                elif (word >> 1) & 31 == 23:
                    c = (word >> 6) & 31
                    self.f[d] = self.f[c] if self.f[a] >= 0 else self.f[b]
                else: raise ValueError(f'Unsupported FPU instruction {word:08x}')
            elif op == 59 and (word >> 1) & 31 == 18:
                self.f[d] = f32(self.f[a] / self.f[b])
            elif op == 59 and (word >> 1) & 31 in (28, 29, 30):
                value = self.f[a] * self.f[(word >> 6) & 31]
                xo = (word >> 1) & 31
                self.f[d] = f32(value + self.f[b] if xo == 29 else self.f[b] - value if xo == 30 else value - self.f[b])
            elif op == 59 and (word >> 1) & 31 in (20, 21, 25):
                xo = (word >> 1) & 31
                self.f[d] = f32(self.f[a] - self.f[b] if xo == 20 else self.f[a] + self.f[b] if xo == 21 else self.f[a] * self.f[(word >> 6) & 31])
            elif op == 19 and (word >> 1) & 1023 == 150:
                pass # isync: no asynchronous execution in this test runner.
            elif entry in (0x21882b0,0x218e7f4,0x2185250,0x2186c64,0x21876a4,0x2184b24,0x2191bc8,0x2186dbc) and op in (56,60):
                quantizer, one = (word>>12)&7, (word>>15)&1
                if quantizer: raise ValueError('Only audited GQR0 float access is supported')
                address = ((self.r[a] if a else 0)+signed(word&4095,12))&MASK
                if op == 56:
                    self.f[d] = self.read_float(address)
                    self.secondary[d] = 1 if one else self.read_float(address+4)
                else:
                    self.write_float(address,self.f[d])
                    if not one: self.write_float(address+4,self.secondary[d])
            elif entry in (0x21882b0,0x218e7f4,0x2185250,0x2186c64,0x21876a4,0x2184b24,0x2191bc8,0x2186dbc) and op == 4:
                xo, small, c = (word>>1)&1023, (word>>1)&31, (word>>6)&31
                aa, bb, cc = (self.f[a],self.secondary[a]), (self.f[b],self.secondary[b]), (self.f[c],self.secondary[c])
                if xo == 528: values = (aa[0],bb[0])
                elif xo == 560: values = (aa[0],bb[1])
                elif xo == 592: values = (aa[1],bb[0])
                elif xo == 624: values = (aa[1],bb[1])
                elif small == 21: values = tuple(f32(aa[i]+bb[i]) for i in range(2))
                elif small == 20: values = tuple(f32(aa[i]-bb[i]) for i in range(2))
                elif small == 12: values = tuple(f32(aa[i]*cc[0]) for i in range(2))
                elif small == 25: values = tuple(f32(aa[i]*cc[i]) for i in range(2))
                elif small == 10: values = (f32(aa[0]+bb[1]),cc[1])
                elif small == 11: values = (cc[0],f32(aa[0]+bb[1]))
                elif small == 14: values = tuple(f32(aa[i]*cc[0]+bb[i]) for i in range(2))
                elif small == 29: values = tuple(f32(aa[i]*cc[i]+bb[i]) for i in range(2))
                else: raise ValueError(f'Unsupported paired-single instruction {word:08x} at {pc:08x}')
                self.f[d],self.secondary[d] = values
            elif pc in (0x219a338, 0x219a340, 0x219a344, 0x218f924, 0x218f92c):
                # Audited ps_merge10 save shuttles: lane 1 is moved into lane 0
                # only to spill it. The following body overwrites these FPRs,
                # and its return restores primary lanes with the original lfd.
                # Unused secondary lanes never affect these decision routines.
                pass
            elif pc in (0x2194224, 0x2194230):
                # Paired-single stack spills save only the unused second lanes.
                # Primary f30/f31 are saved by the adjacent original stfd. The
                # audited prefix stops before any restore or call uses the lanes.
                pass
            else:
                raise ValueError(f'Unsupported instruction {word:08x} at {pc:08x}')
            pc = following
        raise ValueError('Instruction budget exhausted')


def state_group_oracle(parts,vectors):
    r=RoutineRunner(parts)
    actor,other,output,play,loop,item,rng=0x20000000,0x20002000,0x20006000,0x20004000,0x20005000,0x20007000,0x20001000
    def seed(value):
        r.r[3:5]=[rng,value];r.run(0x2454a98)
    def words():return [r.read(rng+i*4) for i in range(4)]
    # Find rare outcomes using the original RNG, then execute their decisions.
    seeds=[0,1,42,0x57415241]
    for value in range(200000):
        seed(value);r.r[3]=rng;draw=r.run(0x2454b34)
        if draw<430000:
            seeds.append(value)
            if len(seeds)>=12:break
    vectors['locomotion']=[]
    for state in range(7):
     for assigned in [0,1]:
      for distance in [0,2,5,6,39,40,49,50,79,80,199,200,201,400]:
       for speed,ticks,style,cooldown,complete,special in [(0,0,0,0,0,0),(.4,10,0,300,1,0),(.8,11,1,0,0,0),(.9,0,0,0,0,0),(1.4,60,3,-1,0,0),(1.4,61,0,0,1,0),(.6,90,2,0,0,1)]:
        for value in (seeds if state==2 and speed>=.9 else [42]):
         seed(value)
         animation={4:1,5:60,6:2}.get(state,4 if state==2 else 3)
         for off,val in [(0x1f4,rng),(0x478,play),(0x2b0,item),(0x2e8,state),(0x2ec,ticks),(0x324,cooldown),(0x278,style)]:r.write(actor+off,val)
         r.write(item,assigned)
         r.write(actor+0x2cc,special,1);r.write(actor+0x288,0,1);r.write(actor+0x289,0,1)
         r.write(play+4,loop);r.write(play+8,animation);r.write(play+12,2);r.write(play+28,0,1);r.write_float(play+24,40)
         r.write_float(loop+4,40 if complete else 15);r.write_float(loop+12,40);r.write_float(loop+20,1);r.write(loop+28,0 if complete else 1,1)
         for off,val in [(0x7c,0),(0x80,0),(0x84,0),(0x318,1),(0x34c,0),(0x350,0),(0x354,1),(0xa0,0),(0xa4,0),(0xa8,1),(0x3f0,.5),(0x33c,1),(0x348,1),(0x32c,speed),(0x328,0)]:r.write_float(actor+off,val)
         r.write_float(output,0);r.write_float(output+4,0);r.write_float(output+8,distance)
         r.r[3:6]=[actor,output,0];r.run(0x2184b24,stop=0x2185bec,limit=10000)
         vectors['locomotion'].append([state,assigned,distance,f32(speed),ticks,style,cooldown,complete,special,value,animation,
            r.read(actor+0x2e8),signed(r.read(actor+0x2ec)),signed(r.read(actor+0x324)),r.read_float(actor+0x32c),r.read_float(actor+0x34c),r.read_float(actor+0x354)]+words())
    vectors['groupCoordinates']=[]
    for ring in range(12):
     for position in range(max(1,6*ring)):
        r.r[3:8]=[0,ring,position,output,output+4];r.run(0x218ff0c)
        vectors['groupCoordinates'].append([ring,position,signed(r.read(output)),signed(r.read(output+4))])
    vectors['groupSwaps']=[]
    nodeA,nodeB=0x20008000,0x20008100
    for a in [(0,0),(16,0),(0,16),(-20,40),(1e-6,-1e-6)]:
     for b in [(0,0),(16,0),(0,16),(-20,40)]:
      for flags in [0,0x20]:
        r.write(nodeA+0x1c,actor);r.write(nodeB+0x1c,other);r.write(actor+0x27c,flags);r.write(other+0x27c,0)
        for address,x,z in [(nodeA+8,0,0),(nodeB+8,16,16),(actor+0x7c,*a),(other+0x7c,*b)]:r.write_float(address,x);r.write_float(address+8,z)
        r.r[3:5]=[nodeA,nodeB];result=r.run(0x2191bc8)
        vectors['groupSwaps'].append([*map(f32,[*a,*b]),flags,result])
    vectors['collisionReactions']=[]
    # Capture the original vtable's type and f1 rate after arithmetic/branches.
    for dx,dz in [(0,10),(0,-10),(10,0),(-10,0),(6,8),(-6,-8),(0,0)]:
     for vx,vz in [(0,-1.3),(0,-.8),(0,1.3),(.01,0),(.1,0),(.2,0),(.8,0),(-.1,0),(-.8,0),(.6,.8)]:
      for flags in [0,4]:
        seed(42);r.reaction_call=None
        r.write(actor+0x478,play);r.write(actor+0x1f4,rng);r.write(actor+0x27c,flags);r.write(actor+0x304,0,1)
        r.write(play+8,10);r.write(play+0x40,0x2000a000);r.write(0x2000a00c,0x2000b000);r.write(0x2000b01c,0x20009000)
        r.write(other+0x478,0x2000c000);r.write(0x2000c008,4)
        for off,val in [(0xa0,0),(0xa4,0),(0xa8,1),(0x430,0)]:r.write_float(actor+off,val)
        for off,val in [(0x34c,vx),(0x350,0),(0x354,vz),(0x32c,1),(0x36c,0)]:r.write_float(other+off,val)
        for off,val in [(12,dx),(16,0),(20,dz)]:r.write_float(0x2001f000+off,val)
        r.r[25]=actor;r.r[29]=other;r.r[26]=0;r.f[29]=0;r.f[28]=.5
        r.run(0x2186dbc,stop=0x2187314,limit=10000)
        vectors['collisionReactions'].append(list(map(f32,[dx,dz,vx,vz]))+[flags]+(r.reaction_call or [-1,0])+[r.read(actor+0x314)]+words())
    vectors['groupOptimizations']=[]
    axial=[(0,0),(-1,1),(0,1),(1,0),(1,-1),(0,-1),(-1,0)]
    offsets=[(-1,0),(0,-1),(1,-1),(1,0),(0,1),(-1,1)]
    lookup={a:i for i,a in enumerate(axial)}
    addresses=[0x20008000+i*0x40 for i in range(7)]
    actors=[0x20000000+i*0x800 for i in range(7)]
    for value in range(32):
     for shift in [1,3,6]:
      seed(value)
      for i,(q,z) in enumerate(axial):
        n,a=addresses[i],actors[i]
        r.write_float(n+8,(q-z)*8);r.write_float(n+16,(q+z)*f32(8*f32(1.7320510149002075)))
        r.write(n+0x1c,a);r.write(a+0x27c,0);r.write(a+0x2cc,0,1)
        pos=axial[(i+shift)%7]
        r.write_float(a+0x7c,(pos[0]-pos[1])*8);r.write_float(a+0x84,(pos[0]+pos[1])*f32(8*f32(1.7320510149002075)))
        for slot,(dq,dz) in enumerate(offsets):
            j=lookup.get((q+dq,z+dz));r.write(n+0x28+slot*4,addresses[j] if j is not None else 0)
      r.r[3:6]=[addresses[0],0x3f,rng];result=r.run(0x2191d30,limit=100000)
      vectors['groupOptimizations'].append([value,shift,addresses.index(result)]+[actors.index(r.read(n+0x1c)) for n in addresses]+words())
    print('Executed new state/group routines: '+', '.join(f'{len(vectors[k])} {k}' for k in ['locomotion','groupCoordinates','groupSwaps','collisionReactions','groupOptimizations']),flush=True)


def motion_oracle(parts, vectors):
    r = RoutineRunner(parts)
    actor, other, output, rng = 0x20000000,0x20005000,0x20006000,0x20001000
    def seed(value):
        r.r[3:5]=[rng,value];r.run(0x2454a98)
    def words(): return [r.read(rng+i*4) for i in range(4)]
    vectors['walks']=[]
    for dx,dz in [(0,0),(0,0.01),(0,2),(0,20),(0,50),(0,200),(20,30),(-20,-30),(100,0)]:
      for direction in [(0,1),(1,0),(-0.6,-0.8)]:
       for height,urgency,special,turn,ramp,speed in [(0.5,0,0,1,0,0),(0,0,0,1,0.5,0.1),(1,0,0,0,1,0.4),(0.2,0.5,0,0.4,0.99,0.2),(0.8,1,0,1,0.998,0.6),(0.5,0,1,0.5,0,0.8),(0.5,0.5,1,1,1,0.1)]:
        for forward in [(0,1),(0.6,0.8),(0,-1)]:
         inputs=list(map(f32,[dx,dz,*direction,*forward,height,urgency,special,turn,ramp,speed]))
         for offset,value in zip((0x34c,0x354,0xa0,0xa8,0x3f0,0x328,0x33c,0x348,0x32c),[*inputs[2:8],inputs[9],inputs[10],inputs[11]]):r.write_float(actor+offset,value)
         r.write_float(actor+0x350,0);r.write_float(actor+0xa4,0);r.write(actor+0x2cc,special,1)
         r.r[31]=actor;r.f[26]=0;r.f[27]=f32(inputs[0]**2+f32(inputs[1]**2));r.f[28]=1;r.f[29]=0.5;r.f[30]=inputs[0];r.f[31]=inputs[1];r.f[11]=f32(0.93)
         r.run(0x2185250,stop=0x2185bec,limit=10000)
         vectors['walks'].append(inputs+[r.read_float(actor+off) for off in (0x32c,0x34c,0x354,0x348)])
    vectors['contacts']=[]
    for cx,cz in [(0,0),(-6,0),(3,4),(0,5),(-0.01,-0.02)]:
     for px,pz in [(0,0),(2,3),(-2,-3),(6,5)]:
      for dx,dz,mx,mz in [(10,0,0,0),(10,2,-0.2,0),(0,10,0.1,0.1),(0,0,1,0),(6,8,0.6,0.8)]:
       inputs=list(map(f32,[cx,cz,px,pz,dx,dz,mx,mz,0.6,0.8,0.1,-0.2]))
       for offset,value in [(0x7c,0),(0x80,0),(0x84,0),(0x34c,0.6),(0x350,0),(0x354,0.8),(0x37c,px),(0x384,pz),(0x364,0),(0x368,0),(0x36c,0),(0x370,0.1),(0x374,0),(0x378,-0.2)]:r.write_float(actor+offset,value)
       for offset,value in [(0x7c,dx),(0x80,0),(0x84,dz),(0x364,mx),(0x368,0),(0x36c,mz)]:r.write_float(other+offset,value)
       for offset,value in [(0,cx),(4,0),(8,cz)]:r.write_float(output+offset,value)
       r.r[25]=actor;r.r[29]=other;r.r[30]=output;r.r[28]=0
       r.run(0x2186c64,stop=0x2186dbc,limit=10000)
       vectors['contacts'].append(inputs+[r.read_float(output),r.read_float(output+8),r.read_float(actor+0x370),r.read_float(actor+0x378),r.r[28],r.read_float(0x2001f00c),r.read_float(0x2001f014)])
    vectors['collisionIntegration']=[]
    for cx,cz in [(0,0),(-6,0),(3,4),(0,5)]:
     for ix,iz in [(0,0),(0.1,-0.2)]:
      for previous in [0,2]:
       for opposed in [0,1]:
        for special,urgency in [(0,0),(0,0.5),(0,1),(1,0.5)]:
         inputs=list(map(f32,[cx,cz,ix,iz,previous,opposed,special,urgency,0.7,0.4,0.6,0.8,1.1]))
         for off,val in [(0x7c,5),(0x80,0),(0x84,7),(0x428,0),(0x42c,0),(0x430,0),(0xa0,0.6),(0xa4,0),(0xa8,0.8),(0x338,1.1),(0x334,0.4),(0x318,0.7),(0x328,urgency),(0x37c,previous),(0x384,-previous),(0x370,ix),(0x374,0),(0x378,iz)]:r.write_float(actor+off,val)
         r.write(actor+0x2cc,special,1);r.r[30]=actor;r.r[31]=opposed
         for offset,value in [(8,f32(cx+ix)),(12,0),(16,f32(cz+iz))]:r.write_float(0x2001f000+offset,value)
         r.f[10]=f32(ix);r.secondary[10]=0
         r.run(0x21876a4,stop=0x218791c,limit=10000)
         vectors['collisionIntegration'].append(inputs+[r.read_float(actor+off) for off in (0x7c,0x84,0x370,0x378,0x334,0x318,0x37c,0x384)])
    vectors['groupSlots']=[]
    for value in range(40):
     for mask in [0,1,0x1c,0xe,7,0x23,0x31,0x38,0x3f]:
      for occupied in [0,1,0x15,0x2a,0x3f]:
       seed(value)
       for i in range(6):
        node=0x20002000+i*0x100
        r.write(actor+0x28+i*4,node if occupied&(1<<i) else 0);r.write(node+0x1c,i+1)
       r.r[3:6]=[actor,rng,mask];result=r.run(0x219220c)
       vectors['groupSlots'].append([value,mask,occupied,result]+words())
    vectors['groupGates']=[]
    for value in range(200):
     for count in [0,1,2,6,30,60,120,10000]:
      seed(value);r.r[28]=rng;r.f[31]=0;r.f[28]=count;r.f[30]=2**-32;r.f[29]=0.5;r.f[27]=3
      r.run(0x217f42c,stop=(0x217f4e4,0x217f534),limit=10000)
      # The comparison's CR0 less-than bit identifies the taken dance branch.
      vectors['groupGates'].append([value,count,int(r.cr[0])]+words())
    vectors['groupTurns']=[]
    for value in range(200):
     for fx,fz in [(0,1),(1,0),(-1,0),(0,-1),(0.6,0.8),(-0.6,-0.8)]:
      seed(value);r.r[31]=actor;r.r[30]=rng;r.f[1]=f32(0.7)
      r.write_float(actor+0xa0,fx);r.write_float(actor+0xa8,fz)
      r.run(0x217ec30,stop=0x217edd8,limit=10000)
      vectors['groupTurns'].append([value,fx,fz,r.f[1]]+words())
    vectors['groupDirections']=[]
    for degree in range(-3600,3601,10):
      radians=degree*math.pi/180
      x,z=f32(math.sin(radians)),f32(math.cos(radians))
      r.write_float(output,x);r.write_float(output+8,z)
      r.r[3:6]=[actor,rng,output]
      r.run(0x21922b0,stop=0x219220c,limit=10000)
      vectors['groupDirections'].append([x,z,r.r[5]])
    vectors['walkStops']=[]
    for length in [1,12,40,41.25]:
     for fraction in [0,0.1,0.15,0.25,0.4,0.5,0.65,0.75,0.9,0.999,1]:
      for stage in [0,1,2]:
       r.r[12]=output;r.f[26]=0;r.f[29]=0.5
       r.write(output+0xc,stage);r.write(output+4,other)
       r.write_float(output+0x18,length);r.write_float(other+4,f32(length*fraction))
       r.run(0x2184dbc,stop=0x2184e44,limit=10000)
       vectors['walkStops'].append([length,f32(length*fraction),stage,r.f[12]])
    vectors['groupFacing']=[]
    for animation in [0,1,3,7,8,9,10,25,26,34]:
     for watch,partner,flags,ticks in [(0,0,0,0),(1,0,0,0),(0,1,0,0),(0,0,128,0),(0,0,64,0),(0,0,0,-1)]:
      for dx,dz in [(0,0),(0,1),(0,29.999),(0,30),(0,30.001),(0,-1),(29,1)]:
       r.write(actor+0x478,0x20004000);r.write(0x20004008,animation)
       for offset,value in [(0x3a0,watch),(0x3b4,partner),(0x27c,flags),(0x3b8,ticks)]:r.write(actor+offset,value)
       for offset,value in [(0x7c,5),(0x84,7),(0xa0,0),(0xa8,1)]:r.write_float(actor+offset,value)
       r.write_float(output,f32(5+dx));r.write_float(output+8,f32(7+dz))
       r.r[3:5]=[actor,output];result=r.run(0x218e4ac)
       vectors['groupFacing'].append([animation,watch,partner,flags,ticks,r.read_float(output),r.read_float(output+8),result])
    print('Executed motion/group routines: '+', '.join(f'{len(vectors[k])} {k}' for k in ['walks','contacts','collisionIntegration','groupSlots','groupGates','groupTurns']),flush=True)


def spatial_oracle(parts, vectors):
    runner = RoutineRunner(parts)
    vectors['partnerEligibility'] = []
    for animation in [3,9,10,17,25,26,34,110]:
        for watch,partner,flags,ticks in [(0,0,0,0),(1,0,0,0),(0,1,0,0),(0,0,128,0),(0,0,64,0),(0,0,0,-1)]:
            for dx,dz in [(0,0),(0,1),(0,17.999),(0,18),(0,18.001),(0,-1),(17,1),(10,10),(-10,10),(0.35,0.9367497),(0.349,0.937)]:
                for fx,fz in [(0,1),(1,0),(0.6,0.8)]:
                    inputs = list(map(f32,[animation,watch,partner,flags,ticks,5,7,fx,fz,5+dx,7+dz]))
                    actor, target = 0x20000000,0x20005000
                    for offset,value in [(0x478,0x20004000),(0x3a0,watch),(0x3b4,partner),(0x27c,flags),(0x3b8,ticks)]: runner.write(actor+offset,value)
                    runner.write(0x20004008,animation)
                    for offset,value in zip((0x7c,0x84,0xa0,0xa8),inputs[5:9]): runner.write_float(actor+offset,value)
                    runner.write_float(target,inputs[9]);runner.write_float(target+8,inputs[10])
                    runner.r[3:5] = [actor,target]
                    result = runner.run(0x218e378)
                    vectors['partnerEligibility'].append(inputs+[result])
    vectors['socialStarts'] = []
    vectors['danceStarts'] = []
    for seed in range(1000):
        runner.r[3:5] = [0x20001000,seed];runner.run(0x2454a98)
        for actor in (0x20000000,0x20005000):
            runner.write(actor+0x280,MASK);runner.write(actor+0x478,0x20004000)
        runner.write(0x200001f0,0);runner.write(0x200001f4,0x20001000)
        runner.write_float(0x1013e244,12)
        runner.r[29:31] = [0x20000000,0x20005000]
        runner.run(0x218e60c,stop=0x218e76c,limit=10000)
        row = [seed,runner.read(0x200003c0),runner.read(0x200053c0),runner.read(0x200003bc),runner.read(0x200003c4,1)]
        vectors['socialStarts'].append(row+[runner.read(0x20001000+i*4) for i in range(4)])
        runner.r[3:5] = [0x20001000,seed];runner.run(0x2454a98)
        runner.r[30:32] = [0x20000000,0x20005000]
        runner.run(0x218e99c,stop=0x218ebb0,limit=10000)
        row = [seed,runner.read(0x200003c0),runner.read(0x200053c0),runner.read(0x200003bc),runner.read(0x200003c4,1)]
        vectors['danceStarts'].append(row+[runner.read(0x20001000+i*4) for i in range(4)])
    vectors['danceEligibility'] = []
    for fx,fz in [(0,1),(0.6,0.8),(-0.6,0.8),(1,0),(0,-1)]:
        for gx,gz in [(0,1),(0.6,0.8),(-0.6,0.8),(1,0),(0,-1)]:
            for dx,dz in [(16,0),(7,0),(17,0),(8,6),(-16,0),(3,15),(0,0)]:
                for animation,watch,flags,ticks in [(10,0,0,0),(25,0,0,0),(9,0,0,0),(10,1,0,0),(10,0,128,0),(10,0,0,-1)]:
                    for actor,controller,x,z,forward_x,forward_z in [(0x20000000,0x20004000,5,7,fx,fz),(0x20005000,0x20006000,5+dx,7+dz,gx,gz)]:
                        runner.write(actor+0x478,controller);runner.write(controller+8,animation)
                        for offset,value in [(0x3a0,watch),(0x3b4,0),(0x27c,flags),(0x3b8,ticks)]: runner.write(actor+offset,value)
                        for offset,value in [(0x7c,x),(0x80,0),(0x84,z),(0x88,forward_z),(0x8c,0),(0x90,-forward_x),(0xa0,forward_x),(0xa4,0),(0xa8,forward_z)]: runner.write_float(actor+offset,value)
                    runner.r[3:5] = [0x20000000,0x20005000]
                    result = runner.run(0x218e7f4,limit=10000)
                    vectors['danceEligibility'].append(list(map(f32,[fx,fz,gx,gz,dx,dz,animation,watch,flags,ticks]))+[result])
    vectors['destinations'] = []
    for seed in range(200):
        for config in (0,1):
            runner.r[3:5] = [0x20001000,seed];runner.run(0x2454a98)
            runner.r[27] = 0x20000000;runner.r[24] = 0x20001000
            runner.r[25] = config*2;runner.r[26] = 0x20006000;runner.r[28] = 0x20000390
            runner.write(0x20000268,0)
            runner.f[23] = 432;runner.f[1] = 288
            runner.write_float(0x2001f018,5);runner.write_float(0x2001f01c,7)
            for j,(x,z,radius) in enumerate([(30,40,35),(-50,-60,50)]):
                runner.write_float(0x20006000+j*8,x);runner.write_float(0x20006004+j*8,z)
                clearance = min(f32(f32((7-z)**2)+(5-x)**2),f32(f32(radius*0.8)**2))
                runner.write_float(0x2001f064+j*4,clearance)
            runner.run(0x21ad1e4,stop=0x21ad5d8,limit=100000)
            vectors['destinations'].append([seed,config,runner.read_float(0x20000390),runner.read_float(0x20000398)]+[runner.read(0x20001000+i*4) for i in range(4)])
    vectors['dancePositions'] = []
    for action in range(25):
        for frame,other_frame,length in [(0,0,40),(6,0,40),(7,0,40),(19,0,40),(20,0,40),(30,0,40),(39,25,40),(29.25,22.5,41.25)]:
            for stage,other_stage in [(2,2),(1,2),(2,1),(0,0)]:
                for dx,dz in [(8,6),(0,5),(0,20),(0,0),(-12,9)]:
                    for actor,controller,clip,x,z in [(0x20000000,0x20004000,0x20007000,5,7),(0x20005000,0x20006000,0x20008000,5+dx,7+dz)]:
                        runner.write(actor+0x478,controller);runner.write(controller+4,clip)
                        runner.write_float(actor+0x7c,x);runner.write_float(actor+0x80,0);runner.write_float(actor+0x84,z)
                        for offset,value in [(0x88,1),(0x8c,0),(0x90,0),(0xa0,0),(0xa4,0),(0xa8,1),(0x428,0),(0x42c,0),(0x430,0)]: runner.write_float(actor+offset,value)
                    runner.write(0x200003c0,action);runner.write(0x200003b8,0);runner.write(0x200003bc,1000)
                    runner.write(0x2000400c,stage);runner.write(0x2000600c,other_stage)
                    runner.write_float(0x20007004,frame);runner.write_float(0x20008004,other_frame)
                    runner.write_float(0x20004018,length);runner.heading_call=None
                    runner.r[30] = 0x20000000;runner.r[28] = 0x20005000
                    runner.f[30] = 0;runner.f[31] = 1
                    runner.run(0x21882b0,stop=(0x21894c8,0x21894d8),limit=10000)
                    heading = runner.heading_call or [0,0,0,0]
                    vectors['dancePositions'].append([action,frame,other_frame,length,stage,other_stage,5,7,5+dx,7+dz,
                        runner.read_float(0x2000007c),runner.read_float(0x20000084),runner.read_float(0x20004014)]+heading)
    print('Executed spatial routines: '+', '.join(f'{len(vectors[key])} {key}' for key in ['partnerEligibility','socialStarts','danceStarts','danceEligibility','destinations','dancePositions']),flush=True)


def oracle(parts, output):
    runner = RoutineRunner(parts)
    vectors = dict(version=1, sha256=SHA256, random=[], masks=[], restrictions=[], transitions=[])
    state_group_oracle(parts, vectors)
    motion_oracle(parts, vectors)
    spatial_oracle(parts, vectors)
    for seed in [0, 1, 1234, MASK, 0x57415241]:
        runner.r[3:5] = [0x20000000, seed]
        runner.run(0x2454a98)
        words = [runner.read(0x20000000 + i * 4) for i in range(4)]
        values = []
        for _ in range(100):
            runner.r[3] = 0x20000000
            values.append(runner.run(0x2454b34))
        vectors['random'].append(dict(seed=seed, words=words, values=values))
    for bits in range(4096):
        text = bytes((49 + i if i < 9 else 56 + i) if bits & (1 << i) else 32 for i in range(12))
        for i, value in enumerate(text + b'\0'): runner.write(0x20000100 + i, value, 1)
        runner.r[3] = 0x20000100
        vectors['masks'].append(runner.run(0x21902d4))
    for animation in range(128):
        for forced in [-1, 0, 34, 37, 38, 46, 49, 50]:
            for bits in [0, 1, 2, 4, 8, 16, 31]:
                state, flags, category = bits % 7, (bits >> 1) & 24, bits % 5
                runner.write(0x20000280, forced)
                runner.write(0x20000288, bits & 1, 1); runner.write(0x20000289, (bits >> 1) & 1, 1)
                runner.write(0x200002e8, state)
                runner.write(0x200003b4, bits & 4); runner.write(0x200003a0, bits & 8)
                runner.write(0x20000478, 0x20001000); runner.write(0x2000048c, category)
                runner.write(0x20001008, animation); runner.write(0x20001020, flags)
                runner.r[3] = 0x20000000
                runner.run(0x2183104)
                vectors['restrictions'].append([forced, bits & 1, (bits >> 1) & 1, state, bits & 4, bits & 8, flags, animation, category, runner.read(0x2000027c)])
    print('Original random, masks, restriction instructions executed', flush=True)
    for previous in range(128):
        for following in range(128):
            for presence in range(4):
                # Exit/entrance lookup pairs are host-provided clip availability.
                runner.write(0x1013d8cc + previous * 12, 0 if presence & 1 else MASK)
                runner.write(0x1013d8d0 + following * 12, 0 if presence & 2 else MASK)
                override = [0.0, 3.0, 17.0, 60.0][(previous + following + presence) % 4]
                runner.write(0x20001008, previous); runner.write_float(0x2000102c, override)
                runner.write(0x20002000, following)
                runner.r[3:5] = [0x20001000, 0x20002000]
                runner.run(0x2194214, stop=0x219445c)
                vectors['transitions'].append([previous, following, presence & 1, presence & 2, override,
                                               runner.read(0x2000100c), runner.read_float(0x20001010)])
    vectors['idleSelections'] = []
    for seed in range(200):
        for current, idle_ticks, density, prevent, activity, disabled in [
            (10, 0, 0, 0, 128, 0), (15, 301, 0, 0, 128, 0), (19, 600, 0, 0, 128, 0),
            (10, 601, 0, 0, 128, 0), (10, 601, 4, 0, 128, 0), (10, 1000, 0, 1, 128, 0),
            (34, 1000, 0, 0, 128, 0), (31, 0, 0, 0, 128, 0), (100, 0, 0, 0, 128, 0),
            (10, 0, 0, 0, 75, 0), (10, 0, 0, 0, 71, 0), (10, 0, 0, 0, 75, 1)]:
            runner.r[3:5] = [0x20001000, seed]; runner.run(0x2454a98)
            runner.write(0x200001f0, 0); runner.write(0x200001f4, 0x20001000)
            runner.write(0x20000268, 0); runner.write(0x200002d0, density)
            runner.write(0x200002d4, 0x20000800); runner.write(0x20000824, prevent)
            runner.write(0x20000484, activity); runner.write(0x20000488, disabled, 1)
            runner.write(0x20000478, 0x20004000); runner.write(0x20004008, current)
            runner.write(0x20002000, 0x20000000); runner.write(0x20002004, 0x20004000)
            runner.write(0x2000202c, idle_ticks); runner.write(0x20003000, current)
            runner.r[3:6] = [0x20002000, 0x20003000, 0x20003010]
            runner.run(0x219a320, limit=100000)
            result = [runner.read(0x20003010 + i * 4) for i in range(4)]
            words = [runner.read(0x20001000 + i * 4) for i in range(4)]
            vectors['idleSelections'].append([seed, current, idle_ticks, density, prevent, activity, disabled] + result + words)
    print(f'Executed {len(vectors["idleSelections"])} original idle selections', flush=True)
    vectors['socialSelections'] = []
    for seed in range(1000):
        for current in [0, 1, 2, 3, 11, 19, 20, 21, 22, 23, 24, 25]:
            runner.r[3:5] = [0x20001000, seed]; runner.run(0x2454a98)
            runner.write(0x200001f0, 0); runner.write(0x200001f4, 0x20001000)
            runner.write(0x200003c0, current); runner.r[30] = 0x20000000
            runner.f[29] = 0.5; runner.f[31] = 1.0 # Original prefix's live constants.
            runner.run(0x2188b08, stop=(0x2189138, 0x21893a0, 0x21894d0), limit=10000)
            selected = runner.r[31]
            words = [runner.read(0x20001000 + i * 4) for i in range(4)]
            vectors['socialSelections'].append([seed, current, selected] + words)
    print(f'Executed {len(vectors["socialSelections"])} original social selections', flush=True)
    vectors['socialTimings'] = []
    for animation, row in enumerate(descriptors(parts)):
        runner.write_float(0x1013decc + animation * 8, 40 if row['name'].endswith('_l') else 12)
    for seed in range(40):
        for action in range(25):
            runner.r[3:5] = [0x20001000, seed]; runner.run(0x2454a98)
            for actor in (0x20000000, 0x20005000):
                runner.write(actor + 0x280, MASK); runner.write(actor + 0x478, 0x20004000)
            runner.r[24] = 0; runner.r[25] = 0x1013decc; runner.r[26] = 0x20001000
            runner.r[27] = 0; runner.r[28] = 0x20005000; runner.r[29] = 0
            runner.r[30] = 0x20000000; runner.r[31] = action; runner.f[31] = 1.0
            runner.write(0x2001f014, action)
            try:
                runner.run(0x218914c + action * 4, stop=(0x21894c8, 0x21894d8), limit=10000)
            except ValueError as error:
                raise ValueError(f'Social timer fixture seed={seed} action={action}, lr={runner.lr:08x}: {error}') from error
            words = [runner.read(0x20001000 + i * 4) for i in range(4)]
            vectors['socialTimings'].append([seed, action, runner.read(0x200053c0), runner.read(0x200003bc), runner.read_float(0x200003c8)] + words)
    print(f'Executed {len(vectors["socialTimings"])} original paired timers and rates', flush=True)
    vectors['headings'] = []
    angles = [-100, -6.2831855, -3.1415927, -0.001, 0, 0.001, 3.1415927, 6.2831855, 100]
    for angle in angles:
        for bearing in angles:
            for gain, cap in [(0.01, 1.5), (0.03, 1), (0.1, 0.4), (0.2, 0.4), (0.3, 1), (0.5, 1), (1, 3.1415927)]:
                for lean in [-9, 0, 9]:
                    inputs = list(map(f32, [angle, bearing, gain, cap, lean, 12.345]))
                    runner.write_float(0x20000340, inputs[0])
                    runner.write_float(0x20000424, inputs[4]); runner.write_float(0x20000434, inputs[5])
                    runner.r[31] = 0x20000000
                    runner.f[1] = inputs[1]; runner.f[31] = inputs[2]; runner.f[30] = inputs[3]
                    runner.run(0x2186808, stop=0x2186a0c)
                    vectors['headings'].append(inputs + [runner.read_float(0x20000000 + offset) for offset in (0x340, 0x344, 0x424, 0x434)])
    print(f'Executed {len(vectors["headings"])} original scalar heading updates', flush=True)
    output.write_text(json.dumps(vectors, separators=(',', ':')) + '\n')
    print(f'Wrote {len(vectors["transitions"])} original transition traces to {output}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rpx', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--swift-table', type=Path)
    parser.add_argument('--oracle', action='store_true')
    args = parser.parse_args()
    parts = sections(args.rpx)
    args.output.mkdir(parents=True, exist_ok=True)
    rows = descriptors(parts)
    (args.output / 'animation-descriptors.json').write_text(json.dumps(dict(sha256=SHA256, tableAddress='0x100f43f8', rows=rows), indent=2) + '\n')
    if args.swift_table:
        lines = ['// Descriptor data from verified US Menu v277, 0x100f43f8.', 'extension OriginalLounge {', '    static let animationTable: [Animation] = [']
        for row in rows:
            lines.append('        Animation(name: "%s", blendFrames: %s, blendLimit: %s, flags: %s), // %d' % (row['name'], row['blendFrames'], row['blendLimit'], row['flags'], row['id']))
        args.swift_table.write_text('\n'.join(lines + ['    ]', '}', '']))
    if args.oracle: oracle(parts, args.output / 'original-routine-vectors.json')
    print('Verified local executable; recovered 128 descriptors. No menu or OS code booted.')


if __name__ == '__main__':
    main()
