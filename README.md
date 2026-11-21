Grease Pencil Tool

Herramientas para llevar el Line Art de Blender a Moho como vectores reales y editables, y para trabajar con ellos dentro de Moho.

El proyecto tiene dos piezas que se prueban por separado:

Pieza	Archivo	Dónde corre
Add-on de Blender	lineart_to_moho.py	Blender 3.6
Script de Moho	grease_pencil_tool.lua (+ iconos .png)	Moho Pro 14.4
¿Para qué sirve?

Si animas en 2D con modelos 3D, el Line Art de Blender detecta contornos y detalles internos (manos, pliegues, etc.) a partir de la cámara. Este proyecto pasa esos trazos a Moho para que el liner sea vectorial y lo controles allí: pincel, grosor, color, máscara y postproducción.

Flujo de trabajo:

En Blender, renderiza tu personaje sin liner como secuencia de imágenes.
En Blender, hornea el Line Art a trazos de Grease Pencil y expórtalos a un archivo .lineart con el add-on.
En Moho, importa tu secuencia de imágenes y usa Grease Pencil Tool para crear el liner vectorial desde ese archivo.
Requisitos
Blender 3.6 (usa la API de Grease Pencil de esa versión; no es compatible con la API nueva de Blender 4.3+).
Moho Pro 14.4 o superior (usa RenderLayerImage, disponible desde 14.4).
No hace falta instalar nada más: el script de Moho es Lua puro.
Instalación
Add-on de Blender
En Blender: Edit > Preferences > Add-ons > Install... y elige lineart_to_moho.py.
Activa el add-on Line Art to Moho.
En la vista 3D, abre la barra lateral (tecla N) y busca la pestaña Moho.
Script de Moho
Copia grease_pencil_tool.lua y los iconos (grease_pencil_tool.png, grease_pencil_tool@2x.png) a la carpeta de scripts de Moho, juntos y con el mismo nombre base.
Recarga los scripts o reinicia Moho.
Uso
1. Exportar desde Blender

En la pestaña Moho de la barra lateral, con el objeto Grease Pencil activo:

Hornear Line Art: ejecuta el bake del modificador Line Art (el mismo botón del modificador).
Elige el rango de fotogramas:
Usar el rango de la escena, o
Inicio y Fin a mano (puede ser un solo fotograma).
Opciones:
Solo fotogramas horneados: omite los fotogramas sin clave horneada en vez de repetir el último dibujo.
Incluir capas ocultas.
Exportar a Moho: elige dónde guardar el archivo .lineart.

Cada punto se convierte a coordenadas de la cámara de la escena (normalizadas de 0 a 1), así que la secuencia de imágenes y el liner deben salir de la misma cámara, la misma resolución y el mismo rango de fotogramas.

2. Trabajar en Moho

Ejecuta Grease Pencil Tool. Aparece un panel con tres botones. Pulsa el de la herramienta que quieras (se marca su casilla) y luego OK; se abre el panel propio de esa herramienta.

Auto Lineart

Genera un contorno vectorial editable alrededor de la silueta de la capa seleccionada (imagen, vector, grupo, Switch...). Renderiza la capa y traza su borde, así que solo saca el contorno exterior, no los detalles internos.

Un fotograma: crea una capa vectorial.
Un rango: crea una capa Switch con un dibujo vectorial por fotograma.
Opciones: fotograma inicial y final, suavizado, simplificación de puntos, longitud mínima de contorno y grosor.
El pincel, el color y el grosor se toman de la ventana Style de Moho.
Importar Line Art de Blender

Lee el archivo .lineart y crea una capa Switch con un dibujo vectorial por fotograma (o una capa vectorial simple si el archivo tiene un solo fotograma). Al pulsar su botón se abre el selector de archivos.

Opciones: importar solo los primeros N fotogramas, desfase de fotogramas, suavizado, simplificación de puntos, grosor, límite de trazos por fotograma (útil para probar).
Opcionales: usar la presión de Blender como grosor por punto (experimental), dibujar un marco de alineación para comprobar la escala, cerrar los trazos abiertos como lazos de ida y vuelta (normalmente no).
El pincel, el color y el grosor se copian de la ventana Style.
La escala es fija: el encuadre del proyecto se toma como 2 unidades de alto, sin depender de la cámara ni del zoom de la vista de Moho, así que el liner debe caer sobre una secuencia de imágenes del mismo tamaño.
Propagar estilo

Modificas los vectores de un fotograma (la referencia) y el script detecta qué propiedades cambiaste y las copia a todos los trazos de los demás dibujos de la capa Switch seleccionada, dentro del rango que elijas. No importa que cada fotograma tenga distinta cantidad de trazos o vértices.

Propiedades que propaga: pincel, parámetros del pincel, grosor, color y extremos de línea.
Para que detecte bien el cambio, selecciona todos los trazos del fotograma de referencia al modificarlos. Si cambias solo algunos, los demás cuentan como "sin cambio".
Casillas: tomar el estilo de la ventana Style en vez del dibujo de referencia, y copiar todo lo marcado aunque no detecte diferencias.
No propaga la forma ni el ancho variable de cada punto, porque dependen de los vértices, que cambian entre fotogramas.
Formato .lineart

Un solo archivo con índice, para que Moho salte directo a los fotogramas que necesita sin leer todo:

Línea 1: cabecera fija de 81 bytes: LINEARTMOHO 2 index_offset=NNNNNNNNNN index_length=NNNNNNNNNN.
Una línea JSON por fotograma: {"frame": N, "strokes": [...]}. Cada trazo trae capa, cerrado, material, grosor y puntos ([x, y, presión] normalizados al encuadre de la cámara).
Última línea: el índice (JSON) con fps, resolución, cámara, objeto y, por fotograma, su posición (offset) y tamaño (length) en bytes.

La profundidad (eje Z de la cámara) se descarta: los trazos de Moho son 2D.

Estado del proyecto
Auto Lineart (un fotograma y rangos, incluso con objetos en movimiento o deformados): probado, funciona.
Exportar desde Blender e importar en Moho, tanto un fotograma como varios fotogramas: probado, funciona.
Propagar estilo (global): probado, funciona.
Pendiente de desarrollar: propagación por proximidad (cada trazo toma el estilo del trazo más cercano del fotograma anterior).
Limitaciones conocidas
Rendimiento: un fotograma importado puede tener cientos de trazos, cada uno con su pincel. La primera pasada de reproducción en Moho puede ser lenta, porque Moho dibuja los pinceles uno por uno y no guarda ese cache en el proyecto. Si pasa, prueba con un pincel simple o limitando los trazos por fotograma.
Cambio de pincel por script: Moho guarda el pincel correctamente, pero no siempre redibuja su imagen en pantalla al instante. Si no lo ves, elige el pincel en la ventana Style antes de importar, o guarda y reabre el proyecto.
Selector de archivos: abrirlo después de cerrar un panel propio cerraba Moho. Por eso el botón de importar lo abre dentro del panel principal.
Trazos en 2D: al proyectar con la cámara, se pierde la profundidad; si la cámara está animada, cada fotograma usa la posición de cámara de ese fotograma.
Autor y licencia

Creado por AngelicMotión. El proyecto es gratuito y libre: cualquiera puede usarlo.

Estructura
lineart_to_moho.py          Add-on de Blender 3.6 (exporta .lineart)
grease_pencil_tool.lua      Script de Moho con las tres herramientas
grease_pencil_tool.png      Icono 24x24
grease_pencil_tool@2x.png   Icono 48x48
