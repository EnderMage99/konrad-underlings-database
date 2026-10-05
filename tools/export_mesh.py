# Exports meshes from a .blend as the star chart's mesh JSON: unit-scaled
# vertices, triangles carrying a material index, one flat colour per material.
# Run headless:
#   blender.exe -b "file.blend" --python tools/export_mesh.py -- out.json [ratio] [object names...]
# ratio (default 1) decimates to keep the triangle count sane; with no names
# every mesh in the file is merged into one.
import bpy, json, sys
args = sys.argv[sys.argv.index("--") + 1:]
path = args[0]
ratio = float(args[1]) if len(args) > 1 else 1.0
names = args[2:]
objs = [o for o in bpy.data.objects if o.type == 'MESH' and (not names or o.name in names)]
for o in objs:
    print("OBJ", o.name, len(o.data.polygons), [round(d, 2) for d in o.dimensions])
def mat_colour(m):
    if m is None: return [0.62, 0.66, 0.70]
    try:
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == 'BSDF_PRINCIPLED':
                    c = n.inputs['Base Color'].default_value
                    return [round(c[0], 3), round(c[1], 3), round(c[2], 3)]
    except Exception: pass
    c = m.diffuse_color
    return [round(c[0], 3), round(c[1], 3), round(c[2], 3)]
verts, F, mats, mat_ix = [], [], [], {}
dg = bpy.context.evaluated_depsgraph_get()
for o in objs:
    if ratio < 1:
        mod = o.modifiers.new("dec", "DECIMATE"); mod.ratio = ratio
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
for o in objs:
    eo = o.evaluated_get(dg); me = eo.to_mesh(); me.calc_loop_triangles()
    mw = eo.matrix_world; base = len(verts)
    verts.extend(mw @ v.co for v in me.vertices)
    slots = []
    for s in o.material_slots:
        key = s.material.name if s.material else None
        if key not in mat_ix: mat_ix[key] = len(mats); mats.append(mat_colour(s.material))
        slots.append(mat_ix[key])
    if not slots:
        if None not in mat_ix: mat_ix[None] = len(mats); mats.append(mat_colour(None))
        slots = [mat_ix[None]]
    for t in me.loop_triangles:
        mi = slots[t.material_index] if t.material_index < len(slots) else slots[0]
        F.append([base + t.vertices[0], base + t.vertices[1], base + t.vertices[2], mi])
mins = [min(v[i] for v in verts) for i in range(3)]
maxs = [max(v[i] for v in verts) for i in range(3)]
ctr = [(mins[i] + maxs[i]) / 2 for i in range(3)]
span = max(maxs[i] - mins[i] for i in range(3)) or 1.0
V = [[round((v[i] - ctr[i]) / span, 3) for i in range(3)] for v in verts]
ext = [round((maxs[i] - mins[i]) / span, 3) for i in range(3)]
with open(path, "w") as fh:
    json.dump({"v": V, "f": F, "c": mats, "ext": ext}, fh, separators=(",", ":"))
print("EXPORTED verts", len(V), "tris", len(F), "mats", mats, "ext", ext)
