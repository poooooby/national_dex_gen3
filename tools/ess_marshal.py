"""A small reader for Ruby Marshal 4.8, enough for Pokémon Essentials' PkmnAnimations.rxdata.

load(bytes) -> Python values: nil/true/false -> None/True/False, fixnum/bignum -> int, float ->
float, string -> str (decoded as UTF-8, else Latin-1), symbol -> Sym, array -> list, hash ->
dict, an object -> Obj(cls, ivars), a user subclass of Array/Hash/String ("C") -> the inner value
with `.cls` set when it is a list (UserList), and a _dump'd object ("u", e.g. RGSS's Color) ->
Dumped(cls, bytes).
"""
import struct


class Sym(str):
    pass


class Obj:
    __slots__ = ("cls", "ivars")

    def __init__(self, cls, ivars=None):
        self.cls, self.ivars = cls, ivars or {}

    def get(self, name, default=None):
        return self.ivars.get("@" + name, default)

    def __repr__(self):
        return "Obj(%s, %s)" % (self.cls, list(self.ivars))


class Dumped:
    __slots__ = ("cls", "data")

    def __init__(self, cls, data):
        self.cls, self.data = cls, data


class UList(list):
    cls = None
    ivars = None

    def get(self, name, default=None):
        return (self.ivars or {}).get("@" + name, default)


class _Reader:
    def __init__(self, data):
        self.b, self.p = data, 0
        self.syms, self.objs = [], []

    def byte(self):
        v = self.b[self.p]
        self.p += 1
        return v

    def long(self):
        c = self.byte()
        if c >= 128:
            c -= 256
        if c == 0:
            return 0
        if 5 <= c <= 127:
            return c - 5
        if -128 <= c <= -5:
            return c + 5
        if c > 0:
            v = 0
            for i in range(c):
                v |= self.byte() << (8 * i)
            return v
        n = -c
        v = 0
        for i in range(n):
            v |= self.byte() << (8 * i)
        return v - (1 << (8 * n))

    def raw(self):
        n = self.long()
        s = self.b[self.p:self.p + n]
        self.p += n
        return s

    def reg(self, v):
        self.objs.append(v)
        return v

    def symbol(self):
        t = chr(self.byte())
        if t == ":":
            s = Sym(self.raw().decode("utf-8", "replace"))
            self.syms.append(s)
            return s
        if t == ";":
            return self.syms[self.long()]
        if t == "I":
            s = self.symbol()
            for _ in range(self.long()):
                self.symbol()
                self.value()
            return s
        raise ValueError("symbol expected, got %r at %d" % (t, self.p))

    @staticmethod
    def text(raw):
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            return raw.decode("latin-1")

    def value(self):
        t = chr(self.byte())
        if t == "0":
            return None
        if t == "T":
            return True
        if t == "F":
            return False
        if t == "i":
            return self.long()
        if t == ":" or t == ";":
            self.p -= 1
            return self.symbol()
        if t == "@":
            return self.objs[self.long()]
        if t == '"':
            return self.reg(self.text(self.raw()))
        if t == "f":
            s = self.raw().decode()
            v = {"inf": float("inf"), "-inf": float("-inf"), "nan": float("nan")}.get(s)
            return self.reg(v if v is not None else float(s))
        if t == "l":
            sign = chr(self.byte())
            n = self.long()
            raw = self.b[self.p:self.p + n * 2]
            self.p += n * 2
            v = int.from_bytes(raw, "little")
            return self.reg(-v if sign == "-" else v)
        if t == "I":
            v = self.value()
            n = self.long()
            ivars = {}
            for _ in range(n):
                k = self.symbol()
                ivars[k] = self.value()
            if isinstance(v, UList):
                v.ivars = {k: x for k, x in ivars.items() if k.startswith("@")}
            elif isinstance(v, Obj):
                v.ivars.update({k: x for k, x in ivars.items() if k.startswith("@")})
            return v
        if t == "[":
            a = self.reg(UList())
            for _ in range(self.long()):
                a.append(self.value())
            return a
        if t == "{" or t == "}":
            h = self.reg({})
            for _ in range(self.long()):
                k = self.value()
                h[k if not isinstance(k, list) else id(k)] = self.value()
            if t == "}":
                self.value()
            return h
        if t == "o":
            cls = self.symbol()
            o = self.reg(Obj(cls))
            for _ in range(self.long()):
                k = self.symbol()
                o.ivars[k] = self.value()
            return o
        if t == "C":
            cls = self.symbol()
            v = self.value()   # the inner value registers itself
            if isinstance(v, UList):
                v.cls = cls
            return v
        if t == "u":
            cls = self.symbol()
            return self.reg(Dumped(cls, self.raw()))
        if t == "U":
            cls = self.symbol()
            o = self.reg(Obj(cls))
            o.ivars["@_load"] = self.value()
            return o
        if t == "e":
            self.symbol()
            return self.value()
        if t == "S":
            cls = self.symbol()
            o = self.reg(Obj(cls))
            for _ in range(self.long()):
                k = self.symbol()
                o.ivars["@" + k] = self.value()
            return o
        if t == "/":
            src = self.raw()
            self.byte()
            return self.reg(self.text(src))
        if t == "c" or t == "m" or t == "M":
            return self.reg(Sym(self.raw().decode()))
        raise ValueError("unknown Marshal type %r at %d" % (t, self.p - 1))


def load(data):
    if data[:2] != b"\x04\x08":
        raise ValueError("not Marshal 4.8")
    r = _Reader(data)
    r.p = 2
    return r.value()


def color(d):
    """RGSS Color/Tone _dump: four little-endian doubles."""
    if isinstance(d, Dumped) and len(d.data) >= 32:
        return struct.unpack("<4d", d.data[:32])
    return None
