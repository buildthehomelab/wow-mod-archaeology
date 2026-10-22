"""Minimal 3.3.5 icon model writer, adapted from wow-mod-visible-bags m2conv.py."""
import math
import struct
HEADER_SIZE = 0x130
SEQ_FLAG_IN_M2 = 0x20
SEQUENCE_HASH_SIZE = 8
TRACK = "<HhIIII"  # interpolation, global sequence, timestamps and values M2Arrays

class Blob:
    def __init__(self):
        self.data = bytearray(HEADER_SIZE)

    def add(self, payload, count):
        """Append payload (16-byte aligned) and return the M2Array (count, offset)."""
        if not count:
            return (0, 0)
        while len(self.data) % 16:
            self.data.append(0)
        off = len(self.data)
        self.data += payload
        return (count, off)

def sequence_hash(anim_ids):
    """3.3.5's sequenceIdxHashById: an open-addressed hash (slot = id % size, quadratic probing)
    of sequence indexes, 0xFFFF = empty. The client probes until it finds the id or an empty
    slot, so the table must keep empty slots: a full one hangs it on any missing animation
    (spell kits ask attached models for more than Stand)."""
    table = [0xFFFF] * SEQUENCE_HASH_SIZE
    assert len(set(anim_ids)) < SEQUENCE_HASH_SIZE
    seen = set()
    for seq_index, anim_id in enumerate(anim_ids):
        if anim_id in seen:
            continue  # a variation; the client reaches it through variationNext
        seen.add(anim_id)
        slot, step = anim_id % SEQUENCE_HASH_SIZE, 1
        while table[slot] != 0xFFFF:
            slot = (slot + step * step) % SEQUENCE_HASH_SIZE
            step += 1
        table[slot] = seq_index
    return struct.pack("<%dH" % SEQUENCE_HASH_SIZE, *table)

def empty_track():
    return struct.pack(TRACK, 0, -1, 0, 0, 0, 0)

def bounds(points):
    xs, ys, zs = zip(*points)
    lo = (min(xs), min(ys), min(zs))
    hi = (max(xs), max(ys), max(zs))
    radius = max(math.sqrt(x * x + y * y + z * z) for x, y, z in points)
    return lo + hi, radius

def vertex(pos, normal, uv):
    return struct.pack("<3f4B4B3f2f2f", *pos, 255, 0, 0, 0, 0, 0, 0, 0, *normal, *uv, 0.0, 0.0)

def quad(name, texture, size=0.3):
    """A flat square facing -x (behind the attachment): the smallest model the client can draw."""
    s = size
    corners = [(0.0, -s, -s), (0.0, s, -s), (0.0, s, s), (0.0, -s, s)]
    uvs = [(0, 1), (1, 1), (1, 0), (0, 0)]
    verts = [vertex(c, (-1.0, 0.0, 0.0), uv) for c, uv in zip(corners, uvs)]
    indices = [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]  # both sides
    subs = [(0, 0, 0, 4, 0, len(indices), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), s * 1.5)]
    m2 = write_model(name, verts, corners, [texture], [(0x1 | 0x4 | 0x10, 1)])
    return m2, build_skin(4, indices, subs, [(0, 0, 0, 0)])

def write_model(name, out_verts, points, textures, materials, tex_flags=None, rig=None):
    box, radius = bounds(points)
    blob = Blob()
    h = {}
    nm = (name + "\0").encode()
    h["name"] = blob.add(nm, len(nm))

    if rig is None:
        rig = dict(sequences=[dict(id=0, variation=0, duration=3333, movespeed=0.0, frequency=0x7FFF,
                                   replay=(0, 0), box=box, radius=radius, var_next=-1, alias=0)],
                   bones=[dict(flags=0x8, parent=-1, submesh=0, tracks=[(0, [])] * 3, pivot=(0.0, 0.0, 0.0))],
                   bone_lookup=[0])
    seq_rows = b"".join(
        struct.pack("<HHIfIhHIII6ffhH", x["id"], x["variation"], x["duration"], x["movespeed"],
                    SEQ_FLAG_IN_M2, x["frequency"], 0, x["replay"][0], x["replay"][1], 150,
                    *x["box"], x["radius"], x["var_next"], x["alias"])
        for x in rig["sequences"])
    h["sequences"] = blob.add(seq_rows, len(rig["sequences"]))
    h["sequence_lookup"] = blob.add(sequence_hash([x["id"] for x in rig["sequences"]]), SEQUENCE_HASH_SIZE)

    def write_track(interp, per_seq, global_loop=-1):
        if not per_seq:
            return empty_track()
        times = [blob.add(t, n) for n, t, _ in per_seq]
        values = [blob.add(v, n) for n, _, v in per_seq]
        ts = blob.add(b"".join(struct.pack("<II", *x) for x in times), len(per_seq))
        vs = blob.add(b"".join(struct.pack("<II", *x) for x in values), len(per_seq))
        return struct.pack(TRACK, interp, global_loop, *ts, *vs)

    bone_rows = b""
    for bone in rig["bones"]:
        tracks = b"".join(write_track(*t) for t in bone["tracks"])
        bone_rows += struct.pack("<iIhHI", -1, bone["flags"], bone["parent"], bone["submesh"], 0) \
            + tracks + struct.pack("<3f", *bone["pivot"])
    h["bones"] = blob.add(bone_rows, len(rig["bones"]))
    loops = rig.get("global_loops", [])
    h["global_loops"] = blob.add(struct.pack("<%dI" % len(loops), *loops), len(loops))
    h["key_bone_lookup"] = (0, 0)
    h["vertices"] = blob.add(b"".join(out_verts), len(out_verts))

    # Textures: type 0 (hardcoded file name).
    tex_names = []
    for path in textures:
        s = (path + "\0").encode()
        tex_names.append(blob.add(s, len(s)))
    tex_flags = tex_flags or [3] * len(textures)
    tex_rows = b"".join(struct.pack("<IIII", 0, f, *n) for f, n in zip(tex_flags, tex_names))
    h["textures"] = blob.add(tex_rows, len(textures))

    # One static texture weight (fully opaque).
    ts = blob.add(struct.pack("<I", 0), 1)
    vs = blob.add(struct.pack("<h", 0x7FFF), 1)
    ts_outer = blob.add(struct.pack("<II", *ts), 1)
    vs_outer = blob.add(struct.pack("<II", *vs), 1)
    weight = struct.pack("<HhIIII", 0, -1, *ts_outer, *vs_outer)
    h["texture_weights"] = blob.add(weight, 1)

    h["replaceable_lookup"] = blob.add(struct.pack("<h", -1), 1)
    h["materials"] = blob.add(b"".join(struct.pack("<HH", *x) for x in materials), len(materials))
    h["bone_lookup"] = blob.add(struct.pack("<%dH" % len(rig["bone_lookup"]), *rig["bone_lookup"]),
                                len(rig["bone_lookup"]))
    h["texture_lookup"] = blob.add(struct.pack("<%dh" % len(textures), *range(len(textures))), len(textures))
    h["texunit_lookup"] = blob.add(struct.pack("<h", 0), 1)
    h["weight_lookup"] = blob.add(struct.pack("<h", 0), 1)
    h["transform_lookup"] = blob.add(struct.pack("<h", -1), 1)

    hdr = bytearray(b"MD20" + struct.pack("<I", 264))
    def arr(key):
        hdr.extend(struct.pack("<II", *h.get(key, (0, 0))))
    arr("name")
    hdr.extend(struct.pack("<I", 0))  # global flags
    for key in ("global_loops", "sequences", "sequence_lookup", "bones", "key_bone_lookup", "vertices"):
        arr(key)
    hdr.extend(struct.pack("<I", 1))  # one skin profile
    for key in ("colors", "textures", "texture_weights", "texture_transforms", "replaceable_lookup",
                "materials", "bone_lookup", "texture_lookup", "texunit_lookup", "weight_lookup",
                "transform_lookup"):
        arr(key)
    hdr.extend(struct.pack("<6ff6ff", *box, radius, *box, radius))
    hdr.extend(b"\0" * 8 * 11)  # collision (3), attachments, attachment lookup, events, lights,
                                # cameras, camera lookup, ribbons, particles
    assert len(hdr) == HEADER_SIZE, hex(len(hdr))
    blob.data[:HEADER_SIZE] = hdr

    return bytes(blob.data)

def build_skin(n, indices, subs, batches, vertex_bones=None, sub_bones=None):
    out = bytearray(48)
    parts = []

    def add(payload, count):
        while (len(out)) % 16:
            out.append(0)
        off = len(out)
        out.extend(payload)
        return (count, off) if count else (0, 0)

    parts.append(add(struct.pack("<%dH" % n, *range(n)), n))
    parts.append(add(struct.pack("<%dH" % len(indices), *indices), len(indices)))
    parts.append(add(vertex_bones or b"\0\0\0\0" * n, n))
    sub_rows = b""
    for i, (sid, level, vstart, vcount, istart, icount, center, sort_center, r) in enumerate(subs):
        bone_count, bone_combo, influences, center_bone = sub_bones[i] if sub_bones else (1, 0, 1, 0)
        sub_rows += struct.pack("<HHHHHHHHHH3f3ff", sid, level, vstart, vcount, istart, icount,
                                bone_count, bone_combo, influences, center_bone, *center, *sort_center, r)
    parts.append(add(sub_rows, len(subs)))
    batch_rows = b""
    for sub, tex, mat, prio in batches:
        # flags 16 (static), shader 0 (single diffuse texture), color -1, uv set 0, weight 0, no transform
        batch_rows += struct.pack("<BbHHHhHHHHHHH", 16, prio, 0, sub, sub, -1, mat, 0, 1, tex, 0, 0, 0)
    parts.append(add(batch_rows, len(batches)))
    out[:48] = b"SKIN" + b"".join(struct.pack("<II", *p) for p in parts) + struct.pack("<I", 21)
    return bytes(out)
