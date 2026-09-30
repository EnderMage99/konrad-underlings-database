# Exports one mesh from a .blend as the star chart's mesh JSON.
# Run headless: blender.exe -b "file.blend" --python tools/export_mesh.py -- out.json
# Set the object name below; the decimate ratio keeps the triangle count sane.
# Exports one mesh object as the chart's mesh JSON: unit-scaled vertices,
# triangles carrying a material index, and one flat colour per material.
name = "spacestation_02"
o = bpy.data.objects[name]
mod = o.modifiers.new("dec", "DECIMATE"); mod.ratio = 0.5
dg = bpy.context.evaluated_depsgraph_get()
eo = o.evaluated_get(dg)
me = eo.to_mesh()
me.calc_loop_triangles()
# world-space vertices, centred, scaled so the longest extent is 1
mw = eo.matrix_world
vs = [mw @ v.co for v in me.vertices]
mins = [min(v[i] for v in vs) for i in range(3)]
maxs = [max(v[i] for v in vs) for i in range(3)]
ctr = [(mins[i] + maxs[i]) / 2 for i in range(3)]
span = max(maxs[i] - mins[i] for i in range(3)) or 1.0
V = [[round((v[0] - ctr[0]) / span, 3), round((v[1] - ctr[1]) / span, 3), round((v[2] - ctr[2]) / span, 3)] for v in vs]
ext = [round((maxs[i] - mins[i]) / span, 3) for i in range(3)]
# one colour per material slot, from the principled base colour where there is one
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
mats = [mat_colour(s.material) for s in o.material_slots] or [[0.62, 0.66, 0.70]]
F = []
for t in me.loop_triangles:
    mi = t.material_index if t.material_index < len(mats) else 0
    F.append([t.vertices[0], t.vertices[1], t.vertices[2], mi])
out = {"v": V, "f": F, "c": mats, "ext": ext}
path = sys.argv[sys.argv.index("--") + 1]
with open(path, "w") as fh:
    json.dump(out, fh, separators=(",", ":"))
print("EXPORTED", name, "verts", len(V), "tris", len(F), "mats", len(mats), "ext", ext)
