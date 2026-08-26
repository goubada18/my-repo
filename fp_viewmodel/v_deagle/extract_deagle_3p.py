#!/usr/bin/env python3
# ============================================================================
# extract_deagle_3p.py — 从 v_deagle_viewmodel.gltf 提取"纯手枪"静态 3P 模型
# - 烘焙 bind-pose 顶点（GIBM × 顶点加权），排除 hands（手）网格
# - 每材质一个 primitive（保留枪体多材质）
# - 输出 fp_viewmodel/v_deagle/deagle_world_static.gltf + .bin + textures/
# ============================================================================
import json, struct, os, shutil

SRC = "v_deagle_viewmodel.gltf"
OUT_DIR = "."
OUT_GLTF = "deagle_world_static.gltf"
OUT_BIN = "deagle_world_static.bin"
TEX_DIR = os.path.join(OUT_DIR, "textures")
EXCLUDE = {"studio__hands"}

d = json.load(open(SRC))
nodes, meshes, mats = d["nodes"], d["meshes"], d["materials"]

# ---- 骨骼全局变换 ----
parent = {}
for i, n in enumerate(nodes):
    for c in n.get("children", []):
        parent[c] = i

def mul(a, b):
    r = [0.0] * 16
    for cc in range(4):
        for rr in range(4):
            s = 0.0
            for k in range(4):
                s += a[k*4+rr] * b[cc*4+k]
            r[cc*4+rr] = s
    return r

def trs(T, R, S):
    tx, ty, tz = T; qx, qy, qz, qw = R; sx, sy, sz = S
    r00=1-2*(qy*qy+qz*qz); r01=2*(qx*qy-qz*qw); r02=2*(qx*qz+qy*qw)
    r10=2*(qx*qy+qz*qw); r11=1-2*(qx*qx+qz*qz); r12=2*(qy*qz-qx*qw)
    r20=2*(qx*qz-qy*qw); r21=2*(qy*qz+qx*qw); r22=1-2*(qx*qx+qy*qy)
    return [sx*r00,sy*r10,sz*r20,0, sx*r01,sy*r11,sz*r21,0, sx*r02,sy*r12,sz*r22,0, tx,ty,tz,1]

def local(n):
    if "matrix" in n:
        return [float(x) for x in n["matrix"]]
    return trs(n.get("translation",[0,0,0]), n.get("rotation",[0,0,0,1]), n.get("scale",[1,1,1]))

glob_m = [None]*len(nodes)
def cg(i):
    if glob_m[i] is not None:
        return glob_m[i]
    n = nodes[i]; lm = local(n); p = parent.get(i)
    glob_m[i] = lm if p is None else mul(cg(p), lm)
    return glob_m[i]
for i in range(len(nodes)):
    cg(i)

# ---- IBM ----
sk = d.get("skins", [{}])[0]
jn = sk.get("joints", [])
ibm = []
if jn:
    acc = d["accessors"][sk["inverseBindMatrices"]]
    bv = d["bufferViews"][acc["bufferView"]]
    buf = open(d["buffers"][bv["buffer"]]["uri"], "rb").read()
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    ibm = [list(struct.unpack_from("<16f", buf, off + j*64)) for j in range(acc["count"])]
GIBM = [mul(glob_m[jn[k]], ibm[k]) for k in range(len(jn))] if jn else []

def read_acc(idx):
    a = d["accessors"][idx]
    bv2 = d["bufferViews"][a["bufferView"]]
    data = open(d["buffers"][bv2["buffer"]]["uri"], "rb").read()
    o = bv2.get("byteOffset", 0) + a.get("byteOffset", 0)
    ncomp = {"SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4}[a["type"]]
    fc = {5126:"f",5123:"H",5125:"I",5121:"B",5122:"h"}[a["componentType"]]
    fmt = "<" + fc*ncomp
    stride = bv2.get("byteStride") or ncomp*{"f":4,"H":2,"I":4,"B":1,"h":2}[fc]
    return [list(struct.unpack_from(fmt, data, o + i*stride)) for i in range(a["count"])]

def apply_m4(m, v):
    x, y, z = v
    return (m[0]*x+m[4]*y+m[8]*z+m[12], m[1]*x+m[5]*y+m[9]*z+m[13], m[2]*x+m[6]*y+m[10]*z+m[14])

# ---- 收集要保留的网格 ----
keep_nodes = []
for n in nodes:
    if "mesh" in n and n.get("mesh") is not None:
        mn = meshes[n["mesh"]]["name"]
        if mn not in EXCLUDE:
            keep_nodes.append(n)

print("保留网格:", [meshes[n["mesh"]]["name"] for n in keep_nodes])

# ---- 逐 primitive 烘焙顶点 ----
out_prims = []   # (positions, normals, uvs, indices, material_idx)
used_mats = {}   # 源材质名 -> 输出材质索引
out_mats = []

for n in keep_nodes:
    m = meshes[n["mesh"]]
    for prim in m.get("primitives", []):
        attrs = prim["attributes"]
        pos = read_acc(attrs["POSITION"])
        nor = read_acc(attrs["NORMAL"]) if "NORMAL" in attrs else None
        uv = read_acc(attrs["TEXCOORD_0"]) if "TEXCOORD_0" in attrs else None
        idx = [x[0] for x in read_acc(prim["indices"])] if "indices" in prim else list(range(len(pos)))
        J = read_acc(attrs["JOINTS_0"]) if "JOINTS_0" in attrs else None
        W = read_acc(attrs["WEIGHTS_0"]) if "WEIGHTS_0" in attrs else None
        # 烘焙
        wpos = []
        wnor = []
        for vi, v in enumerate(pos):
            if J is None or not GIBM:
                wpos.append(v)
                wnor.append(nor[vi] if nor else [0,0,0])
            else:
                x=y=z=0.0
                nx=ny=nz=0.0
                for c in range(4):
                    w = W[vi][c]
                    if w == 0: continue
                    p = apply_m4(GIBM[J[vi][c]], v)
                    x+=w*p[0]; y+=w*p[1]; z+=w*p[2]
                    if nor:
                        nn = apply_m4(GIBM[J[vi][c]], nor[vi])
                        nx+=w*nn[0]; ny+=w*nn[1]; nz+=w*nn[2]
                wpos.append((x,y,z))
                wnor.append((nx,ny,nz))
        # 材质
        mi = prim.get("material")
        mname = mats[mi]["name"] if mi is not None else "default"
        if mname not in used_mats:
            used_mats[mname] = len(out_mats)
            src_m = mats[mi].copy() if mi is not None else {"name": mname}
            out_mats.append(src_m)
        out_prims.append((wpos, wnor, uv, idx, used_mats[mname]))

# ---- 序列化：合并 accessors/bufferViews ----
out_buf = bytearray()
out_accessors = []
out_buffer_views = []
out_buf_views = []  # (bufferView_idx, data_bytes)

def add_view(data_bytes, target):
    aligned = (len(out_buf) + 3) & ~3
    pad = aligned - len(out_buf)
    if pad:
        out_buf.extend(b"\x00" * pad)
    bv_idx = len(out_buffer_views)
    out_buffer_views.append({"buffer":0, "byteOffset":len(out_buf), "byteLength":len(data_bytes), "target":target})
    out_buf.extend(data_bytes)
    return bv_idx

def add_accessor(bv_idx, count, ctype, atype, mn=None, mx=None):
    ai = len(out_accessors)
    acc = {"bufferView":bv_idx, "componentType":ctype, "count":count, "type":atype}
    if mn is not None: acc["min"] = mn
    if mx is not None: acc["max"] = mx
    out_accessors.append(acc)
    return ai

import struct as S
prims_out = []
for wpos, wnor, uv, idx, mat_idx in out_prims:
    nv = len(wpos)
    # positions
    pb = b"".join(S.pack("<3f", *p) for p in wpos)
    pv = add_view(pb, 34962)
    mn = [min(p[i] for p in wpos) for i in range(3)]
    mx = [max(p[i] for p in wpos) for i in range(3)]
    pa = add_accessor(pv, nv, 5126, "VEC3", mn, mx)
    # normals
    nb = b"".join(S.pack("<3f", *q) for q in wnor)
    nv_idx = add_view(nb, 34962)
    na = add_accessor(nv_idx, nv, 5126, "VEC3")
    # uvs（无则填 0）
    if uv:
        ub = b"".join(S.pack("<2f", u[0], u[1]) for u in uv)
    else:
        ub = b"".join(S.pack("<2f", 0.0, 0.0) for _ in range(nv))
    uv_idx = add_view(ub, 34962)
    ua = add_accessor(uv_idx, nv, 5126, "VEC2")
    # indices
    ib = b"".join(S.pack("<I", i) for i in idx)
    iv = add_view(ib, 34963)
    ia = add_accessor(iv, len(idx), 5125, "SCALAR")
    prims_out.append({"attributes":{"POSITION":pa,"NORMAL":na,"TEXCOORD_0":ua}, "indices":ia, "material":mat_idx, "mode":4})

# ---- 材质/贴图 ----
imgs = d.get("images", [])
out_images = []
out_textures = []
tex_map = {}  # 源 image idx -> 输出 idx

for m in out_mats:
    # 收集 baseColorTexture 引用
    pbr = m.get("pbrMetallicRoughness", {})
    bct = pbr.get("baseColorTexture")
    if bct and bct.get("index") is not None:
        src_tex = bct["index"]
        src_img = d["textures"][src_tex]["source"]
        if src_img not in tex_map:
            uri = imgs[src_img]["uri"]
            # 拷贝贴图
            os.makedirs(TEX_DIR, exist_ok=True)
            src_path = os.path.join(os.path.dirname(SRC), uri)
            dst_path = os.path.join(TEX_DIR, os.path.basename(uri))
            if os.path.exists(src_path):
                if os.path.abspath(src_path) != os.path.abspath(dst_path):
                    shutil.copy2(src_path, dst_path)
            else:
                print("!! 贴图缺失:", src_path)
            new_img = len(out_images)
            out_images.append({"uri": "textures/" + os.path.basename(uri)})
            new_tex = len(out_textures)
            out_textures.append({"sampler":0, "source":new_img})
            tex_map[src_img] = new_tex
        bct["index"] = tex_map[src_img]

out_samplers = [{"magFilter":9729, "minFilter":9987, "wrapS":10497, "wrapT":10497}]

# ---- 写文件 ----
open(OUT_BIN, "wb").write(bytes(out_buf))
out_gltf = {
    "asset":{"version":"2.0","generator":"deagle_3p_static"},
    "scene":0,
    "scenes":[{"nodes":[0]}],
    "nodes":[{"name":"deagle_world_static","mesh":0}],
    "meshes":[{"name":"deagle_pistol","primitives":prims_out}],
    "materials":out_mats,
    "textures":out_textures,
    "images":out_images,
    "samplers":out_samplers,
    "accessors":out_accessors,
    "bufferViews":out_buffer_views,
    "buffers":[{"uri":OUT_BIN, "byteLength":len(out_buf)}],
}
json.dump(out_gltf, open(OUT_GLTF, "w"), separators=(",", ":"))
print("写出:", OUT_GLTF, "bin=", len(out_buf), "bytes, prims=", len(prims_out), "mats=", len(out_mats))
# 校验
print("材质:", [m.get("name") for m in out_mats])
