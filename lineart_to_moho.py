# -*- coding: utf-8 -*-
"""
Line Art -> Moho  (add-on para Blender 3.6)

Exporta los trazos de Grease Pencil ya horneados (Bake de Line Art) a UN SOLO
archivo (.lineart) con un indice al final: Moho lee el indice, salta directo a
los fotogramas que pides y lee solo esos.

Formato (todo en bytes, UTF-8):
  linea 1 : cabecera fija de 81 bytes: "LINEARTMOHO 2 index_offset=NNNNNNNNNN index_length=NNNNNNNNNN"
  lineas  : un JSON por fotograma {"frame":N,"strokes":[...]}
  ultima  : el indice (JSON) con fps, camara y, por fotograma, offset y length en bytes

Solo usa la API de Blender 3.6 (GPencil antiguo):
  GPencilLayer.frames / .hide / .info
  GPencilFrame.frame_number / .strokes
  GPencilStroke.points / .use_cyclic / .material_index / .line_width
  GPencilStrokePoint.co / .pressure
  bpy_extras.object_utils.world_to_camera_view
"""

bl_info = {
    "name": "Line Art to Moho",
    "author": "Claude",
    "version": (0, 2, 0),
    "blender": (3, 6, 0),
    "location": "Vista 3D > Barra lateral (N) > pestana Moho",
    "description": "Exporta los trazos horneados de Line Art a JSON por fotograma para Moho",
    "category": "Import-Export",
}

import json
import os

import bpy
from bpy.props import BoolProperty, IntProperty, PointerProperty, StringProperty
from bpy_extras.object_utils import world_to_camera_view

FORMAT_VERSION = 2


# ----------------------------------------------------------------------
# Nucleo (sin interfaz): se puede probar por separado
# ----------------------------------------------------------------------

def find_key(layer, frame_number, exact_only):
    """Devuelve el GPencilFrame de la capa para ese fotograma, o None.

    exact_only=True : solo si existe una clave EXACTAMENTE en ese fotograma
                      (asi no se repiten datos fuera del rango horneado).
    exact_only=False: usa la clave anterior mas cercana (mantiene el dibujo).
    """
    best = None
    for fr in layer.frames:
        n = fr.frame_number
        if exact_only:
            if n == frame_number:
                return fr
        elif n <= frame_number and (best is None or n > best.frame_number):
            best = fr
    return best


def collect_frame(scene, camera, gp_obj, frame_number, exact_only=True, include_hidden=False):
    """Lee los trazos de todas las capas en un fotograma.

    Devuelve (hay_clave, lista_de_trazos). Cada punto sale como
    [x, y, presion] con x, y normalizados al encuadre de la camara
    (0,0 = abajo-izquierda, 1,1 = arriba-derecha).
    """
    mw = gp_obj.matrix_world          # co esta en espacio local del objeto
    has_key = False
    strokes_out = []
    for layer in gp_obj.data.layers:
        if layer.hide and not include_hidden:
            continue
        fr = find_key(layer, frame_number, exact_only)
        if fr is None:
            continue
        has_key = True
        for st in fr.strokes:
            if len(st.points) < 2:
                continue
            pts = []
            for p in st.points:
                ndc = world_to_camera_view(scene, camera, mw @ p.co)
                pts.append([round(ndc.x, 5), round(ndc.y, 5), round(p.pressure, 4)])
            strokes_out.append({
                "capa": layer.info,
                "cerrado": bool(st.use_cyclic),
                "material": int(st.material_index),
                "grosor": int(st.line_width),
                "puntos": pts,
            })
    return has_key, strokes_out


HEADER_LEN = 80


def _header(index_offset, index_length):
    text = "LINEARTMOHO 2 index_offset=%010d index_length=%010d" % (index_offset, index_length)
    return text.ljust(HEADER_LEN).encode("ascii") + b"\n"          # 81 bytes en total


def export_range(scene, camera, gp_obj, filepath, start, end, exact_only=True, include_hidden=False):
    """Exporta start..end (incluidos) a UN archivo con indice. Devuelve un resumen (dict)."""
    if end < start:
        raise ValueError("El fotograma final no puede ser menor que el inicial.")
    folder = os.path.dirname(filepath)
    if folder:
        os.makedirs(folder, exist_ok=True)
    original_frame = scene.frame_current
    frames_info, skipped = [], []
    total_strokes = 0
    try:
        with open(filepath, "wb") as fh:
            fh.write(_header(0, 0))                    # se reescribe al final con el indice real
            for f in range(start, end + 1):
                scene.frame_set(f)                     # la camara y el objeto pueden estar animados
                has_key, strokes = collect_frame(scene, camera, gp_obj, f, exact_only, include_hidden)
                if not has_key:
                    skipped.append(f)
                    continue
                data = json.dumps({"frame": f, "strokes": strokes},
                                  ensure_ascii=False, separators=(",", ":")).encode("utf-8")
                offset = fh.tell()
                fh.write(data)
                fh.write(b"\n")
                frames_info.append({"frame": f, "offset": offset, "length": len(data),
                                    "trazos": len(strokes)})
                total_strokes += len(strokes)
            index = {
                "version": FORMAT_VERSION,
                "origen": "Blender Line Art (Grease Pencil horneado)",
                "fps": scene.render.fps,
                "resolucion": [scene.render.resolution_x, scene.render.resolution_y],
                "camara": camera.name,
                "objeto": gp_obj.name,
                "rango_pedido": [start, end],
                "frames": frames_info,
                "omitidos": skipped,
            }
            idx_data = json.dumps(index, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            idx_offset = fh.tell()
            fh.write(idx_data)
            fh.write(b"\n")
            fh.seek(0)
            fh.write(_header(idx_offset, len(idx_data)))
    finally:
        scene.frame_set(original_frame)
    return {"exported": len(frames_info), "skipped": skipped, "strokes": total_strokes}


# ----------------------------------------------------------------------
# Interfaz de Blender
# ----------------------------------------------------------------------

class LineartMohoSettings(bpy.types.PropertyGroup):
    use_scene_range: BoolProperty(
        name="Usar el rango de la escena",
        description="Exporta del fotograma inicial al final de la escena",
        default=False,
    )
    frame_start: IntProperty(name="Inicio", default=1, min=0)
    frame_end: IntProperty(name="Fin", default=1, min=0)
    exact_only: BoolProperty(
        name="Solo fotogramas horneados",
        description="Omite los fotogramas que no tienen clave horneada, en vez de repetir el ultimo dibujo",
        default=True,
    )
    include_hidden: BoolProperty(
        name="Incluir capas ocultas",
        default=False,
    )


class LINEARTMOHO_OT_bake(bpy.types.Operator):
    bl_idname = "lineart_moho.bake"
    bl_label = "Hornear Line Art"
    bl_description = "Ejecuta el Bake de Line Art del objeto Grease Pencil activo (el mismo boton del modificador)"

    @classmethod
    def poll(cls, context):
        ob = context.active_object
        return ob is not None and ob.type == 'GPENCIL'

    def execute(self, context):
        try:
            bpy.ops.object.lineart_bake_strokes()
        except Exception as exc:  # el operador puede fallar si no hay modificador Line Art
            self.report({'ERROR'}, "No se pudo hornear: %s" % exc)
            return {'CANCELLED'}
        self.report({'INFO'}, "Line Art horneado.")
        return {'FINISHED'}


class LINEARTMOHO_OT_export(bpy.types.Operator):
    bl_idname = "lineart_moho.export"
    bl_label = "Exportar a Moho"
    bl_description = "Elige donde guardar el archivo .lineart y exporta los trazos horneados"

    filepath: StringProperty(subtype='FILE_PATH')
    filter_glob: StringProperty(default="*.lineart", options={'HIDDEN'})

    @classmethod
    def poll(cls, context):
        ob = context.active_object
        return ob is not None and ob.type == 'GPENCIL'

    def invoke(self, context, event):
        if not self.filepath:
            self.filepath = "lineart_moho.lineart"
        context.window_manager.fileselect_add(self)
        return {'RUNNING_MODAL'}

    def execute(self, context):
        scene = context.scene
        s = scene.lineart_moho
        gp_obj = context.active_object
        camera = scene.camera
        if camera is None:
            self.report({'ERROR'}, "La escena no tiene camara activa.")
            return {'CANCELLED'}
        if not self.filepath:
            self.report({'ERROR'}, "No elegiste donde guardar el archivo.")
            return {'CANCELLED'}
        path = bpy.path.abspath(self.filepath)
        if not path.lower().endswith(".lineart"):
            path += ".lineart"
        start = scene.frame_start if s.use_scene_range else s.frame_start
        end = scene.frame_end if s.use_scene_range else s.frame_end
        try:
            res = export_range(scene, camera, gp_obj, path,
                               start, end, s.exact_only, s.include_hidden)
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}
        msg = "Exportados %d fotogramas (%d trazos) a %s" % (
            res["exported"], res["strokes"], path)
        if res["skipped"]:
            msg += " | sin clave horneada: %d fotogramas (ej. %d)" % (len(res["skipped"]), res["skipped"][0])
        self.report({'INFO'}, msg)
        return {'FINISHED'}


class LINEARTMOHO_PT_panel(bpy.types.Panel):
    bl_label = "Line Art a Moho"
    bl_idname = "LINEARTMOHO_PT_panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Moho"

    def draw(self, context):
        layout = self.layout
        s = context.scene.lineart_moho
        layout.operator("lineart_moho.bake", icon='MOD_LINEART')
        layout.separator()
        layout.prop(s, "use_scene_range")
        col = layout.column(align=True)
        col.enabled = not s.use_scene_range
        col.prop(s, "frame_start")
        col.prop(s, "frame_end")
        layout.prop(s, "exact_only")
        layout.prop(s, "include_hidden")
        layout.operator("lineart_moho.export", icon='EXPORT')


CLASSES = (
    LineartMohoSettings,
    LINEARTMOHO_OT_bake,
    LINEARTMOHO_OT_export,
    LINEARTMOHO_PT_panel,
)


def register():
    for c in CLASSES:
        bpy.utils.register_class(c)
    bpy.types.Scene.lineart_moho = PointerProperty(type=LineartMohoSettings)


def unregister():
    del bpy.types.Scene.lineart_moho
    for c in reversed(CLASSES):
        bpy.utils.unregister_class(c)


if __name__ == "__main__":
    register()
