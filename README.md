# Grease Pencil Tool

**Lleva el Line Art de Blender a Moho como vectores reales que puedes editar.**

¿Animas en 2D usando modelos 3D? Entonces conoces el problema: el liner que sale de Blender es una imagen, y en Moho ya no puedes cambiarle el pincel, el grosor ni el color. Con este proyecto, el liner llega a Moho como **trazos vectoriales de verdad**, y desde ahí lo controlas todo a tu gusto.

Está hecho de dos piezas pequeñas que se instalan por separado:

| Pieza | Archivo | Dónde se usa |
|---|---|---|
| Add-on de Blender | `lineart_to_moho.py` | Blender 3.6 |
| Script de Moho | `grease_pencil_tool.lua` (con sus iconos) | Moho Pro 14.4 |

## ¿Qué puedes hacer con esto?

Al ejecutar **Grease Pencil Tool** en Moho eliges entre tres herramientas:

- **Importar Line Art de Blender:** trae a Moho el liner que exportaste desde Blender, un dibujo vectorial por fotograma, dentro de una capa Switch. Incluye los detalles internos (manos, pliegues...), no solo el contorno.
- **Auto Lineart:** crea un contorno vectorial alrededor de cualquier capa de Moho (imagen, vector, grupo...). Funciona incluso con objetos que se mueven o se deforman.
- **Propagar estilo:** cambias el pincel, el grosor o el color de **un** fotograma y ese cambio se copia a todos los demás. Se acabó retocar fotograma por fotograma.

## Cómo funciona, en tres pasos

1. **En Blender**, renderiza tu personaje **sin liner**, como secuencia de imágenes.
2. **En Blender**, con el add-on, hornea el Line Art y expórtalo a un archivo `.lineart`.
3. **En Moho**, importa tu secuencia de imágenes y abre **Grease Pencil Tool** para traer el liner vectorial.

> Importante: la secuencia de imágenes y el liner deben salir de la **misma cámara, con la misma resolución y el mismo rango de fotogramas**. Así cuadran perfecto sin tener que moverlos.

## Qué necesitas

- Blender **3.6**.
- Moho Pro **14.4** o más nuevo.

No tienes que instalar nada más.

## Instalación

### El add-on de Blender

1. En Blender ve a `Edit > Preferences > Add-ons > Install...` y elige `lineart_to_moho.py`.
2. Activa el add-on **Line Art to Moho**.
3. En la vista 3D abre la barra lateral (tecla `N`) y busca la pestaña **Moho**.

### El script de Moho

1. Copia `grease_pencil_tool.lua` y sus iconos (`grease_pencil_tool.png` y `grease_pencil_tool@2x.png`) a la carpeta de scripts de Moho. Deben ir juntos y con el mismo nombre base.
2. Recarga los scripts o reinicia Moho.

## Paso a paso

### 1. Exportar desde Blender

En la pestaña **Moho** de la barra lateral, con tu objeto Grease Pencil seleccionado:

1. Pulsa **Hornear Line Art**.
2. Elige los fotogramas que quieres: **Usar el rango de la escena**, o escribe **Inicio** y **Fin** (puede ser un solo fotograma).
3. Si quieres, activa **Solo fotogramas horneados** (omite los que no tengan dibujo en vez de repetir el último) o **Incluir capas ocultas**.
4. Pulsa **Exportar a Moho** y elige dónde guardar el archivo `.lineart`.

### 2. Usar las herramientas en Moho

Ejecuta **Grease Pencil Tool**. Verás un panel con tres botones: pulsa el de la herramienta que quieras (se marca su casilla) y luego **OK**. Se abre el panel de esa herramienta.

#### Importar Line Art de Blender

Al pulsar su botón se abre el selector de archivos para que elijas tu `.lineart`. Después puedes ajustar:

- Cuántos fotogramas importar (por si quieres probar con pocos primero) y un desfase de fotogramas.
- **Suavizado** y **simplificación de puntos**, para tener menos vértices y líneas más limpias.
- **Grosor** en píxeles (si lo dejas en 0 usa el de la ventana Style).
- Un límite de trazos por fotograma, útil para pruebas.
- Opciones extra: usar la presión de Blender como grosor (experimental) y dibujar un marco de alineación para comprobar la escala.

El **pincel, el color y el grosor** se toman de la ventana **Style** de Moho: elígelos antes de importar y el liner ya sale con tu estilo.

#### Auto Lineart

Selecciona la capa que quieres contornear y ejecuta la herramienta.

- Con un fotograma crea una capa vectorial.
- Con un rango crea una capa **Switch** con un dibujo vectorial por fotograma.
- Puedes ajustar suavizado, simplificación, tamaño mínimo de los contornos y grosor.
- También usa el pincel, el color y el grosor de la ventana **Style**.

#### Propagar estilo

1. Cambia el pincel, el grosor o el color de los trazos de **un** fotograma (el de referencia). Selecciona **todos** sus trazos al hacerlo.
2. Selecciona la capa Switch y ejecuta la herramienta.
3. Elige el fotograma de referencia y el rango al que aplicar los cambios.

La herramienta detecta qué cambiaste y lo copia a todos los trazos de los demás fotogramas del rango. No importa que cada fotograma tenga distinta cantidad de trazos. Al terminar te muestra un resumen de lo que propagó.

Propaga: pincel, parámetros del pincel, grosor, color y extremos de línea. La forma de los trazos no se toca.

## Cosas que conviene saber

- **La primera reproducción puede ir lenta.** Un fotograma importado puede tener cientos de trazos con pincel, y Moho los dibuja uno por uno la primera vez. Si te pasa, prueba con un pincel más simple o limita los trazos por fotograma.
- **Si cambias el pincel y no lo ves enseguida,** es cosa de Moho: el cambio sí se guarda, pero a veces no redibuja al momento. Elige el pincel en la ventana Style **antes** de importar, o guarda y vuelve a abrir el proyecto.
- **Todo es 2D.** Los trazos se proyectan con la cámara de Blender y se pierde la profundidad. Si la cámara está animada, cada fotograma usa la posición de cámara de ese momento.

## Qué viene después

- Propagación por proximidad: que cada trazo tome el estilo del trazo más cercano del fotograma anterior.

## Para curiosos: el archivo `.lineart`

Es un único archivo con un índice al final, así Moho salta directo a los fotogramas que necesita sin leerlo todo:

- Una cabecera fija de 81 bytes: `LINEARTMOHO 2 index_offset=NNNNNNNNNN index_length=NNNNNNNNNN`.
- Una línea de texto JSON por fotograma, con sus trazos. Cada punto es `[x, y, presión]`, normalizado al encuadre de la cámara.
- Al final, el índice, con los fps, la resolución, la cámara y la posición de cada fotograma dentro del archivo.

## Autor y licencia

Creado por **AngelicMotión**. El proyecto es gratuito y libre: cualquiera puede usarlo.
