import bpy

SRC = r"C:/Users/93343/Desktop/demo/fp_viewmodel/ak47_viewmodel.gltf"
DST = r"C:/Users/93343/Desktop/demo/fp_viewmodel/ak47_viewmodel_r.glb"

def snapshot(gltf_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=gltf_path)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    # rest AABB over mesh children
    lo = [float('inf')] * 3
    hi = [-float('inf')] * 3
    mw = arm.matrix_world
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        M = mw @ o.matrix_basis
        for v in o.data.vertices:
            p = M @ v.co
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    # idle at frame 30 -> bone world heads
    idle = None
    for a in bpy.data.actions:
        if a.name == 'idle':
            idle = a
            break
    if idle is not None:
        arm.animation_data.action = idle
        bpy.context.scene.frame_set(30)
        bpy.context.view_layer.update()
    heads = {}
    for pb in arm.pose.bones:
        wm = arm.matrix_world @ pb.matrix
        heads[pb.name] = wm.translation
    verts = {o.name: len(o.data.vertices) for o in bpy.data.objects if o.type == 'MESH'}
    return {
        'scale': tuple(round(x, 5) for x in arm.scale),
        'actions': sorted(a.name for a in bpy.data.actions if a.users),
        'aabb_lo': tuple(round(x, 4) for x in lo),
        'aabb_hi': tuple(round(x, 4) for x in hi),
        'heads': heads,
        'verts': verts,
    }

s = snapshot(SRC)
m = snapshot(DST)

print("SRC scale =", s['scale'])
print("MIR scale =", m['scale'])
print("SRC actions =", len(s['actions']), s['actions'])
print("MIR actions =", len(m['actions']), m['actions'])
print("SRC verts =", sorted(s['verts'].items(), key=lambda kv: kv[0]))
print("MIR verts =", sorted(m['verts'].items(), key=lambda kv: kv[0]))
print("SRC AABB lo=%s hi=%s" % (s['aabb_lo'], s['aabb_hi']))
print("MIR AABB lo=%s hi=%s" % (m['aabb_lo'], m['aabb_hi']))
exp_lo = (-s['aabb_hi'][0], s['aabb_lo'][1], s['aabb_lo'][2])
exp_hi = (-s['aabb_lo'][0], s['aabb_hi'][1], s['aabb_hi'][2])
ok_aabb = (abs(m['aabb_lo'][0] - exp_lo[0]) < 0.02 and abs(m['aabb_hi'][0] - exp_hi[0]) < 0.02
           and abs(m['aabb_lo'][1] - exp_lo[1]) < 0.02 and abs(m['aabb_hi'][1] - exp_hi[1]) < 0.02
           and abs(m['aabb_lo'][2] - exp_lo[2]) < 0.02 and abs(m['aabb_hi'][2] - exp_hi[2]) < 0.02)
print("AABB_X_MIRROR_OK =", ok_aabb)

det_ok = m['scale'][0] > 0 and m['scale'][1] > 0 and m['scale'][2] > 0
print("MIR_DET_POSITIVE =", det_ok)

mism = 0
checked = 0
for name in s['heads']:
    if name in m['heads']:
        checked += 1
        a = s['heads'][name]
        b = m['heads'][name]
        if not (abs(a.x + b.x) < 0.05 and abs(a.y - b.y) < 0.05 and abs(a.z - b.z) < 0.05):
            mism += 1
print("BONE_IDLE30_CHECKED =", checked, " MISMATCH =", mism)

verts_ok = sorted((k.split('.')[0], v) for k, v in s['verts'].items()) == sorted((k.split('.')[0], v) for k, v in m['verts'].items())
print("VERTS_EQUAL =", verts_ok)
print("=== VERIFY DONE ===")
