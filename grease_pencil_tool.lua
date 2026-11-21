-- **************************************************************
-- Grease Pencil Tool  v1.0 (GreasePencilTool)
-- Un solo script con tres herramientas de Line Art para Moho:
--   1) Auto Lineart        : contorno vectorial de una capa (un fotograma o rango)
--   2) Importar de Blender : importa un .lineart exportado desde Blender
--   3) Propagar estilo     : copia los cambios de un fotograma a todo el Switch
-- Al ejecutarlo aparece un panel con tres botones: eliges una herramienta,
-- pulsas OK y se abre el panel propio de esa herramienta (el mismo de antes).
-- Cada herramienta conserva exactamente su lógica original.
-- Pensado para Moho Pro 14.4.
-- **************************************************************

ScriptName = "GreasePencilTool"
GreasePencilTool = {}

function GreasePencilTool:Name() return "Grease Pencil Tool" end
function GreasePencilTool:Version() return "1.0" end
function GreasePencilTool:UILabel() return "Grease Pencil Tool" end
function GreasePencilTool:Creator() return "Claude" end
function GreasePencilTool:Description()
	return "Auto Lineart, importar Line Art de Blender y propagar estilo a todos los fotogramas, en un solo script."
end
function GreasePencilTool:ColorizeIcon() return false end
function GreasePencilTool:IsRelevant(moho) return true end
function GreasePencilTool:IsEnabled(moho) return true end

-- ##############################################################
-- HERRAMIENTA: AL_AutoLineart
-- ##############################################################
local function make_auto()
-- **************************************************************
-- AL_AutoLineart  v0.3  (PROTOTIPO - Funciones 1 y 2: un fotograma o rango en capa Switch)
-- Genera un contorno vectorial editable alrededor de la capa
-- seleccionada (imagen, vector, grupo, switch...): la renderiza con
-- MohoLayer:RenderLayerImage (Moho 14.4+) y traza la silueta.
-- El pincel, color y grosor se copian de la ventana Style de Moho.
-- Lua puro, sin programas externos. Pensado para Moho Pro 14.4.
--
-- Instalación: copiar a la carpeta Scripts/Menu de tu contenido
-- personalizado de Moho y recargar scripts (o reiniciar Moho).
-- **************************************************************

local AL_AutoLineart = {}

local AL = {}                 -- núcleo puro (no usa la API de Moho)
AL_AutoLineart._core = AL     -- expuesto para pruebas fuera de Moho

local sbyte, sub = string.byte, string.sub
local floor, abs, sqrt, max, min = math.floor, math.abs, math.sqrt, math.max, math.min

function AL_AutoLineart:Name() return "Auto Lineart (prototipo)" end
function AL_AutoLineart:Version() return "0.1" end
function AL_AutoLineart:UILabel() return "Auto Lineart (prototipo)" end
function AL_AutoLineart:Creator() return "Claude" end
function AL_AutoLineart:Description()
	return "Crea un contorno vectorial editable alrededor de la silueta de una capa de imagen PNG."
end

-- ==============================================================
-- 1. DECODIFICADOR PNG -> MÁSCARA (Lua puro, con inflate propio)
-- ==============================================================

local LBASE = {[0]=3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local LEXT  = {[0]=0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local DBASE = {[0]=1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local DEXT  = {[0]=0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local CLORDER = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}

local function be32(s, p)
	local a, b, c, d = sbyte(s, p, p + 3)
	return (a << 24) | (b << 16) | (c << 8) | d
end

-- Tabla de Huffman canónica (método de puff.c)
local function huffBuild(lengths, n)
	local count = {}
	for i = 0, 15 do count[i] = 0 end
	for i = 0, n - 1 do count[lengths[i]] = count[lengths[i]] + 1 end
	local offs = {[1] = 0}
	for i = 1, 14 do offs[i + 1] = offs[i] + count[i] end
	local symbol = {}
	for i = 0, n - 1 do
		local l = lengths[i]
		if l ~= 0 then
			symbol[offs[l]] = i
			offs[l] = offs[l] + 1
		end
	end
	return {count = count, symbol = symbol}
end

local function makePixelGetter(ctype, depth, palR, palG, palB, palA)
	if ctype == 6 then
		if depth == 8 then
			return function(c, x) local i = (x - 1) * 4; return c[i+1], c[i+2], c[i+3], c[i+4] end
		end
		return function(c, x) local i = (x - 1) * 8; return c[i+1], c[i+3], c[i+5], c[i+7] end
	elseif ctype == 2 then
		if depth == 8 then
			return function(c, x) local i = (x - 1) * 3; return c[i+1], c[i+2], c[i+3], 255 end
		end
		return function(c, x) local i = (x - 1) * 6; return c[i+1], c[i+3], c[i+5], 255 end
	elseif ctype == 4 then
		if depth == 8 then
			return function(c, x) local i = (x - 1) * 2; local g = c[i+1]; return g, g, g, c[i+2] end
		end
		return function(c, x) local i = (x - 1) * 4; local g = c[i+1]; return g, g, g, c[i+3] end
	elseif ctype == 0 then
		if depth == 8 then
			return function(c, x) local g = c[x]; return g, g, g, 255 end
		elseif depth == 16 then
			return function(c, x) local g = c[(x - 1) * 2 + 1]; return g, g, g, 255 end
		end
		local mx = (1 << depth) - 1
		return function(c, x)
			local bp = (x - 1) * depth
			local v = (c[(bp >> 3) + 1] >> (8 - depth - (bp & 7))) & mx
			local g = v * 255 // mx
			return g, g, g, 255
		end
	else -- ctype == 3 (paleta)
		if depth == 8 then
			return function(c, x) local k = c[x]; return palR[k] or 0, palG[k] or 0, palB[k] or 0, palA[k] or 255 end
		end
		local mx = (1 << depth) - 1
		return function(c, x)
			local bp = (x - 1) * depth
			local k = (c[(bp >> 3) + 1] >> (8 - depth - (bp & 7))) & mx
			return palR[k] or 0, palG[k] or 0, palB[k] or 0, palA[k] or 255
		end
	end
end

-- data: contenido binario del PNG.
-- mode: 1 = canal alfa, 2 = luminosidad (blanco = objeto)
-- thr: umbral 0..255; step: submuestreo (1 = todos los píxeles)
-- Devuelve: mask (filas de 0/1), mw, mh, anchoOriginal, altoOriginal, tieneAlfa
function AL.decodePNGMask(data, mode, thr, step)
	if sub(data, 1, 8) ~= "\137PNG\r\n\26\n" then
		error("El archivo no es un PNG válido.")
	end
	local p = 9
	local w, h, depth, ctype, interlace
	local plte, trns
	local idat = {}
	while p <= #data do
		local len = be32(data, p)
		local typ = sub(data, p + 4, p + 7)
		local body = sub(data, p + 8, p + 7 + len)
		if typ == "IHDR" then
			w = be32(body, 1); h = be32(body, 5)
			depth = sbyte(body, 9); ctype = sbyte(body, 10); interlace = sbyte(body, 13)
		elseif typ == "PLTE" then plte = body
		elseif typ == "tRNS" then trns = body
		elseif typ == "IDAT" then idat[#idat + 1] = body
		elseif typ == "IEND" then break end
		p = p + 12 + len
	end
	if not w then error("PNG sin cabecera IHDR.") end
	if interlace ~= 0 then
		error("PNG entrelazado (Adam7) no soportado. Reexporta el PNG sin entrelazado.")
	end
	local chMap = {[0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4}
	local ch = chMap[ctype]
	if not ch then error("Tipo de color PNG no soportado: " .. tostring(ctype)) end
	if not (depth == 8 or depth == 16 or (depth < 8 and (ctype == 3 or ctype == 0))) then
		error("Profundidad de bits PNG no soportada: " .. tostring(depth))
	end

	local palR, palG, palB, palA = {}, {}, {}, {}
	if ctype == 3 then
		if not plte then error("PNG con paleta pero sin tabla PLTE.") end
		for i = 0, #plte // 3 - 1 do
			palR[i], palG[i], palB[i] = sbyte(plte, i * 3 + 1, i * 3 + 3)
			palA[i] = (trns and sbyte(trns, i + 1)) or 255
		end
	end
	local get = makePixelGetter(ctype, depth, palR, palG, palB, palA)

	step = max(1, floor(step or 1))
	thr = thr or 128
	local bitsPP = ch * depth
	local bpp = max(1, bitsPP // 8)
	local rowBytes = (w * bitsPP + 7) // 8
	local rowLen = rowBytes + 1

	local mask, mh, minA = {}, 0, 255
	local mw = (w - 1) // step + 1
	local win, wpos = {}, 0
	local row, rowN = {}, 0
	local prev, cur = {}, {}
	for i = 1, rowBytes do prev[i] = 0; cur[i] = 0 end
	local y = 1

	local function flushRow()
		local ft = row[1]
		if ft == 0 then
			for i = 1, rowBytes do cur[i] = row[i + 1] end
		elseif ft == 1 then
			for i = 1, rowBytes do
				local l = (i > bpp) and cur[i - bpp] or 0
				cur[i] = (row[i + 1] + l) & 255
			end
		elseif ft == 2 then
			for i = 1, rowBytes do cur[i] = (row[i + 1] + prev[i]) & 255 end
		elseif ft == 3 then
			for i = 1, rowBytes do
				local l = (i > bpp) and cur[i - bpp] or 0
				cur[i] = (row[i + 1] + ((l + prev[i]) >> 1)) & 255
			end
		elseif ft == 4 then
			for i = 1, rowBytes do
				local a = (i > bpp) and cur[i - bpp] or 0
				local b = prev[i]
				local c = (i > bpp) and prev[i - bpp] or 0
				local pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
				local pr
				if pa <= pb and pa <= pc then pr = a elseif pb <= pc then pr = b else pr = c end
				cur[i] = (row[i + 1] + pr) & 255
			end
		else
			error("Filtro PNG desconocido: " .. tostring(ft))
		end
		-- extraer fila de máscara si esta fila está muestreada
		if (y - 1) % step == 0 then
			local mr, k = {}, 0
			for x = 1, w, step do
				local r, g, b, a = get(cur, x)
				k = k + 1
				if a < minA then minA = a end
				local v
				if mode == 2 then v = (0.299 * r + 0.587 * g + 0.114 * b) * a / 255 else v = a end
				mr[k] = (v >= thr) and 1 or 0
			end
			mh = mh + 1
			mask[mh] = mr
		end
		prev, cur = cur, prev
		rowN = 0
		y = y + 1
	end

	local function put(b)
		win[wpos & 32767] = b
		wpos = wpos + 1
		if y > h then return end
		rowN = rowN + 1
		row[rowN] = b
		if rowN == rowLen then flushRow() end
	end

	-- ---- inflate (zlib) ----
	local zs = table.concat(idat)
	if #zs < 3 then error("PNG sin datos de imagen.") end
	if (sbyte(zs, 1) & 15) ~= 8 then error("Compresión PNG desconocida.") end
	local sp = 3 -- saltar cabecera zlib de 2 bytes
	local bb, bc = 0, 0

	local function bits(n)
		while bc < n do
			local b = sbyte(zs, sp)
			if not b then error("PNG: datos comprimidos truncados.") end
			sp = sp + 1
			bb = bb | (b << bc)
			bc = bc + 8
		end
		local v = bb & ((1 << n) - 1)
		bb = bb >> n
		bc = bc - n
		return v
	end

	local function decode(hf)
		local code, first, index = 0, 0, 0
		local count, symbol = hf.count, hf.symbol
		for len = 1, 15 do
			code = code | bits(1)
			local c = count[len]
			if code - c < first then return symbol[index + (code - first)] end
			index = index + c
			first = (first + c) << 1
			code = code << 1
		end
		error("PNG: código Huffman inválido.")
	end

	local fixedL, fixedD
	repeat
		local last = bits(1)
		local btype = bits(2)
		if btype == 0 then
			bb, bc = 0, 0
			local len = sbyte(zs, sp) | (sbyte(zs, sp + 1) << 8)
			sp = sp + 4
			for i = 0, len - 1 do
				local b = sbyte(zs, sp + i)
				if not b then error("PNG: bloque sin comprimir truncado.") end
				put(b)
			end
			sp = sp + len
		elseif btype == 3 then
			error("PNG: bloque de compresión inválido.")
		else
			local lc, dc
			if btype == 1 then
				if not fixedL then
					local ll, dl = {}, {}
					for i = 0, 143 do ll[i] = 8 end
					for i = 144, 255 do ll[i] = 9 end
					for i = 256, 279 do ll[i] = 7 end
					for i = 280, 287 do ll[i] = 8 end
					for i = 0, 29 do dl[i] = 5 end
					fixedL, fixedD = huffBuild(ll, 288), huffBuild(dl, 30)
				end
				lc, dc = fixedL, fixedD
			else
				local hlit = bits(5) + 257
				local hdist = bits(5) + 1
				local hclen = bits(4) + 4
				local cl = {}
				for i = 0, 18 do cl[i] = 0 end
				for i = 1, hclen do cl[CLORDER[i]] = bits(3) end
				local clh = huffBuild(cl, 19)
				local lens, i = {}, 0
				while i < hlit + hdist do
					local sym = decode(clh)
					if sym < 16 then
						lens[i] = sym; i = i + 1
					else
						local rep, val
						if sym == 16 then val = lens[i - 1]; rep = 3 + bits(2)
						elseif sym == 17 then val = 0; rep = 3 + bits(3)
						else val = 0; rep = 11 + bits(7) end
						for _ = 1, rep do lens[i] = val; i = i + 1 end
					end
				end
				local ll, dl = {}, {}
				for j = 0, hlit - 1 do ll[j] = lens[j] end
				for j = 0, hdist - 1 do dl[j] = lens[hlit + j] end
				lc, dc = huffBuild(ll, hlit), huffBuild(dl, hdist)
			end
			while true do
				local sym = decode(lc)
				if sym < 256 then
					put(sym)
				elseif sym == 256 then
					break
				else
					sym = sym - 257
					local len = LBASE[sym] + bits(LEXT[sym])
					local ds = decode(dc)
					local dist = DBASE[ds] + bits(DEXT[ds])
					for _ = 1, len do
						local b = win[(wpos - dist) & 32767]
						if not b then error("PNG: datos corruptos (referencia inválida).") end
						put(b)
					end
				end
			end
		end
	until last == 1

	if y <= h then error("PNG: faltan filas de imagen (archivo truncado).") end
	return mask, mw, mh, w, h, (minA < 255)
end

-- ==============================================================
-- 2. CONTORNO: máscara -> bucles cerrados en coordenadas de esquina
-- ==============================================================

-- Devuelve lista de bucles {X={...}, Y={...}} con coordenadas de
-- esquina de píxel (0..mw, 0..mh), eje Y hacia abajo.
function AL.traceLoops(mask, mw, mh)
	local W1 = mw + 1
	local es, ee, outs, n = {}, {}, {}, 0
	local function addEdge(sx, sy, ex, ey)
		n = n + 1
		local sk = sy * W1 + sx
		es[n] = sk
		ee[n] = ey * W1 + ex
		local o = outs[sk]
		if o then o[#o + 1] = n else outs[sk] = {n} end
	end
	local function inside(x, y)
		if x < 1 or y < 1 or x > mw or y > mh then return false end
		return mask[y][x] == 1
	end
	for y = 1, mh do
		local r = mask[y]
		for x = 1, mw do
			if r[x] == 1 then
				if not inside(x, y - 1) then addEdge(x - 1, y - 1, x, y - 1) end
				if not inside(x + 1, y) then addEdge(x, y - 1, x, y) end
				if not inside(x, y + 1) then addEdge(x, y, x - 1, y) end
				if not inside(x - 1, y) then addEdge(x - 1, y, x - 1, y - 1) end
			end
		end
	end

	local used, loops = {}, {}
	for id = 1, n do
		if not used[id] then
			local X, Y, k = {}, {}, 0
			local curE = id
			while curE do
				used[curE] = true
				local sk = es[curE]
				k = k + 1
				X[k] = sk % W1
				Y[k] = sk // W1
				local nxt = nil
				local o = outs[ee[curE]]
				if o then
					for i = 1, #o do
						if not used[o[i]] then nxt = o[i]; break end
					end
				end
				curE = nxt
			end
			if k >= 4 then loops[#loops + 1] = {X = X, Y = Y} end
		end
	end
	return loops
end

-- ==============================================================
-- 3. GEOMETRÍA: colineales, remuestreo, suavizado, Douglas-Peucker
-- ==============================================================

local function removeCollinear(X, Y)
	local n = #X
	local nx, ny, k = {}, {}, 0
	for i = 1, n do
		local ip = (i - 2) % n + 1
		local inx = i % n + 1
		local cr = (X[i] - X[ip]) * (Y[inx] - Y[i]) - (Y[i] - Y[ip]) * (X[inx] - X[i])
		if cr ~= 0 then
			k = k + 1
			nx[k] = X[i]; ny[k] = Y[i]
		end
	end
	return nx, ny
end

local function resampleClosed(X, Y, sp)
	local n = #X
	local cum = {[0] = 0}
	for i = 1, n do
		local j = i % n + 1
		local dx, dy = X[j] - X[i], Y[j] - Y[i]
		cum[i] = cum[i - 1] + sqrt(dx * dx + dy * dy)
	end
	local L = cum[n]
	if L <= 0 then return X, Y, 0 end
	local m = max(4, floor(L / sp + 0.5))
	local rx, ry = {}, {}
	local seg = 1
	for k = 0, m - 1 do
		local s = k * L / m
		while seg < n and cum[seg] < s do seg = seg + 1 end
		local j = seg % n + 1
		local segLen = cum[seg] - cum[seg - 1]
		local t = (segLen > 0) and (s - cum[seg - 1]) / segLen or 0
		rx[k + 1] = X[seg] + (X[j] - X[seg]) * t
		ry[k + 1] = Y[seg] + (Y[j] - Y[seg]) * t
	end
	return rx, ry, L
end

local function smoothClosed(X, Y, passes)
	local n = #X
	for _ = 1, passes do
		local nx, ny = {}, {}
		for i = 1, n do
			local ip = (i - 2) % n + 1
			local inx = i % n + 1
			nx[i] = (X[ip] + 2 * X[i] + X[inx]) / 4
			ny[i] = (Y[ip] + 2 * Y[i] + Y[inx]) / 4
		end
		X, Y = nx, ny
	end
	return X, Y
end

local function simplifyClosed(X, Y, tol)
	local n = #X
	if n <= 4 or tol <= 0 then return X, Y end
	local far, fd = 2, -1
	for i = 2, n do
		local d = (X[i] - X[1]) ^ 2 + (Y[i] - Y[1]) ^ 2
		if d > fd then fd = d; far = i end
	end
	local function idx(i) return (i - 1) % n + 1 end
	local keep = {}
	keep[1] = true; keep[far] = true
	local stack = {{1, far}, {far, n + 1}}
	local t2 = tol * tol
	while #stack > 0 do
		local seg = table.remove(stack)
		local a, b = seg[1], seg[2]
		local ia, ib = idx(a), idx(b)
		local ax, ay, bx, by = X[ia], Y[ia], X[ib], Y[ib]
		local dx, dy = bx - ax, by - ay
		local len2 = dx * dx + dy * dy
		local md, mi = -1, nil
		for i = a + 1, b - 1 do
			local k = idx(i)
			local d
			if len2 == 0 then
				d = (X[k] - ax) ^ 2 + (Y[k] - ay) ^ 2
			else
				local cr = (X[k] - ax) * dy - (Y[k] - ay) * dx
				d = cr * cr / len2
			end
			if d > md then md = d; mi = i end
		end
		if mi and md > t2 then
			keep[idx(mi)] = true
			stack[#stack + 1] = {a, mi}
			stack[#stack + 1] = {mi, b}
		end
	end
	local nx, ny, k = {}, {}, 0
	for i = 1, n do
		if keep[i] then k = k + 1; nx[k] = X[i]; ny[k] = Y[i] end
	end
	if k < 3 then return X, Y end
	return nx, ny
end

local function loopLength(X, Y)
	local n, L = #X, 0
	for i = 1, n do
		local j = i % n + 1
		L = L + sqrt((X[j] - X[i]) ^ 2 + (Y[j] - Y[i]) ^ 2)
	end
	return L
end

-- Pipeline de geometría para un bucle (todo en píxeles de la imagen)
-- Devuelve X, Y  (o nil si el bucle se descarta)
function AL.processLoop(loop, o)
	local X, Y = {}, {}
	for i = 1, #loop.X do X[i] = loop.X[i]; Y[i] = loop.Y[i] end
	X, Y = removeCollinear(X, Y)
	if #X < 3 then return nil end
	if loopLength(X, Y) < o.minLen then return nil end
	X, Y = resampleClosed(X, Y, 1.5)
	if o.smooth > 0 then X, Y = smoothClosed(X, Y, o.smooth * 2) end
	X, Y = simplifyClosed(X, Y, o.simplify)
	if #X < 3 then return nil end
	return X, Y
end

-- ==============================================================
-- 5. CÓDIGO DE MOHO (solo métodos que aparecen en la documentación)
-- ==============================================================

local function alert(title, msg)
	print("[AutoLineart] " .. tostring(title) .. ": " .. tostring(msg))
	pcall(function()
		LM.GUI.Alert(LM.GUI.ALERT_INFO, title, msg, nil, "OK", nil, nil)
	end)
end

local function readWholeFile(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local d = f:read("*a")
	f:close()
	return d
end

local function asString(v)
	if type(v) == "string" then return v end
	local s
	pcall(function() s = v:Buffer() end)
	return s
end

-- Resolución del render = tamaño del proyecto (lado mayor)
local function docMaxDim(moho)
	local w, h
	pcall(function() w = moho.document:Width(); h = moho.document:Height() end)
	if w and h and w > 0 and h > 0 then return max(64, floor(max(w, h))) end
	return 2048
end

-- Renderiza la capa seleccionada a PNG en un fotograma (MohoLayer:RenderLayerImage, 14.4+)
-- Devuelve ruta, minX, minY, maxX, maxY (límites en espacio del documento)
local function renderSelectedLayer(moho, layer, maxDim, frame)
	local opts
	local ctors = {
		function() return MOHO.MohoLayerRenderOptions:new_local() end,
		function() return LM.MohoLayerRenderOptions:new_local() end,
		function() return MohoLayerRenderOptions:new_local() end,
	}
	for _, c in ipairs(ctors) do
		local ok, r = pcall(c)
		if ok and r then opts = r; break end
	end
	if not opts then error("No pude crear MohoLayerRenderOptions (clase no encontrada en esta versión).", 0) end
	opts.frame = frame
	opts.maxDimension = maxDim
	opts.trimResult = true
	local ok, res = pcall(function() return layer:RenderLayerImage(opts) end)
	if not ok then error("RenderLayerImage falló: " .. tostring(res), 0) end
	if res == false then error("RenderLayerImage devolvió false (no pudo renderizar la capa).", 0) end
	local path = asString(opts.imagePath)
	if not path or path == "" then error("RenderLayerImage no devolvió la ruta de la imagen.", 0) end
	local b = opts.layerBounds
	return path, b.fMin.x, b.fMin.y, b.fMax.x, b.fMax.y
end

-- Ruta del PNG de una capa de imagen (ImageLayer:SourceImage)
local function imageLayerPath(moho, il)
	local ok, p = pcall(function() return il:SourceImage() end)
	if not ok or not p or p == "" then
		error("No pude obtener la ruta del PNG desde la capa de imagen.", 0)
	end
	p = tostring(p)
	local cands = {p}
	local okd, dpath = pcall(function() return tostring(moho.document:Path()) end)
	if okd and dpath then
		local dir = dpath:match("^(.*)[/\\]")
		if dir then
			cands[#cands + 1] = dir .. "\\" .. p
			cands[#cands + 1] = dir .. "/" .. p
		end
	end
	for _, c in ipairs(cands) do
		if readWholeFile(c) then return c end
	end
	error("No pude abrir el PNG de la capa. Probé:\n" .. table.concat(cands, "\n"), 0)
end

-- Estilo de pincel de la ventana Style de Moho -> estilo de forma
local STYLE_VALUES = {
	"fBrushAlign", "fBrushIsColor", "fBrushMergedAlpha", "fBrushRandomize",
	"fBrushRandomOrder", "fBrushTint", "fBrushAngleDrift", "fBrushHueDrift",
	"fBrushJitter", "fBrushRandomInterval", "fBrushSatDrift", "fBrushSizeVariationAmp",
	"fBrushSizeVariationScale", "fBrushSpacing", "fBrushValDrift", "fLineCaps", "fLineWidth",
}

local function copyStyle(dst, src, frame, failed)
	for _, f in ipairs(STYLE_VALUES) do
		local ok = pcall(function() dst[f] = src[f] end)
		if not ok then failed[f] = true end
	end
	local ok = pcall(function() dst.fBrushName:Set(src.fBrushName:Buffer()) end)
	if not ok then failed["fBrushName"] = true end
	ok = pcall(function() dst.fLineCol:SetValue(0, src.fLineCol:GetValue(frame)) end)
	if not ok then failed["fLineCol"] = true end
	dst.fDefineLineWidth = true
	dst.fDefineLineCol = true
end

-- Analiza un fotograma: render -> máscara -> contornos (en píxeles)
-- Devuelve tabla {loops, toDoc, copyTransform, pw, ph, usedRender, bounds, note}
local function captureFrame(moho, layer, frame, o, allowFallback)
	local pngPath, bMinX, bMinY, bMaxX, bMaxY
	local usedRender, note = false, nil
	local ok, a, b, c, d, e = pcall(renderSelectedLayer, moho, layer, o.maxDim, frame)
	if ok then
		pngPath, bMinX, bMinY, bMaxX, bMaxY = a, b, c, d, e
		usedRender = true
	elseif allowFallback and layer:LayerType() == MOHO.LT_IMAGE then
		note = "Render falló (" .. tostring(a):sub(1, 80) .. "); usé el PNG de la capa."
	else
		error(a, 0)
	end
	local il
	if not usedRender then
		il = moho:LayerAsImage(layer)
		pngPath = imageLayerPath(moho, il)
	end

	local data = readWholeFile(pngPath)
	if not data then error("No pude abrir la imagen renderizada: " .. tostring(pngPath), 0) end
	local mask, mw, mh, pw, ph, hasAlpha = AL.decodePNGMask(data, 1, o.thr, 1)
	if not hasAlpha then
		error("La imagen no tiene transparencia, así que no puedo separar el objeto del fondo.", 0)
	end

	local toDoc
	local copyTransform = false
	if usedRender then
		local sx, sy = (bMaxX - bMinX) / pw, (bMaxY - bMinY) / ph
		toDoc = function(px, py) return bMinX + px * sx, bMaxY - py * sy end
	else
		local uw, uh
		pcall(function() uw = il:Width(); uh = il:Height() end)
		if not uw or not uh or uw <= 0 or uh <= 0 then
			local p1 = moho:PixelToDoc(1)
			uw, uh = pw * p1, ph * p1
		end
		toDoc = function(px, py) return (px / pw - 0.5) * uw, (0.5 - py / ph) * uh end
		copyTransform = true
	end

	local loops = {}
	for _, loop in ipairs(AL.traceLoops(mask, mw, mh)) do
		local X, Y = AL.processLoop(loop, o)
		if X then loops[#loops + 1] = {X = X, Y = Y} end
	end
	return {loops = loops, toDoc = toDoc, copyTransform = copyTransform, pw = pw, ph = ph,
		usedRender = usedRender, note = note,
		bounds = usedRender and {bMinX, bMinY, bMaxX, bMaxY} or nil}
end

-- Crea las formas de contorno en la capa vectorial que esté seleccionada.
-- vlMesh: malla de esa capa. Devuelve nº de contornos y de puntos.
local function buildShapes(moho, mesh, cap, curStyle, lineW, failed, frame)
	local nLoops, nPoints = 0, 0
	local v = LM.Vector2:new_local()
	local toDoc = cap.toDoc
	for _, loop in ipairs(cap.loops) do
		local X, Y = loop.X, loop.Y
		mesh:SelectNone()
		local first = mesh:CountPoints()
		v.x, v.y = toDoc(X[1], Y[1])
		mesh:AddLonePoint(v, 0)
		for i = 2, #X do
			v.x, v.y = toDoc(X[i], Y[i])
			mesh:AppendPoint(v, 0)
		end
		v.x, v.y = toDoc(X[1], Y[1])
		mesh:AppendPoint(v, 0)                    -- punto duplicado para cerrar
		mesh:WeldPoints(mesh:CountPoints() - 1, first, 0)
		local lastKept = mesh:CountPoints() - 1
		for id = first, lastKept do mesh:Point(id).fSelected = true end
		moho:CreateShape(false)
		local shape = mesh:Shape(mesh:CountShapes() - 1)
		shape.fHasFill = false
		shape.fHasOutline = true
		copyStyle(shape.fMyStyle, curStyle, frame, failed)
		if lineW then shape.fMyStyle.fLineWidth = lineW end
		mesh:SelectNone()
		nLoops = nLoops + 1
		nPoints = nPoints + (lastKept - first + 1)
	end
	return nLoops, nPoints
end

local function newLayerOfType(moho, ltype)
	local okc, res = pcall(function() return moho:CreateNewLayer(ltype, false) end)
	if okc and res then return res end
	return moho:CreateNewLayer(ltype)
end

local function selectLayer(moho, layer)
	pcall(function() moho:SetSelLayer(layer) end)
end

function AL_AutoLineart.Generate(moho, o)
	local t0 = os.clock()
	local layer = moho.layer
	local f0, f1 = o.startFrame, o.endFrame
	if f1 < f0 then error("El fotograma final no puede ser menor que el inicial.", 0) end
	o.thr = 128
	o.maxDim = docMaxDim(moho)
	local curStyle = moho:CurrentEditStyle()
	local failed = {}
	local lineW = (o.width > 0) and moho:PixelToDoc(o.width) or nil
	local notes = {}
	local nLoops, nPoints = 0, 0
	local msg

	if f0 == f1 then
		-- ---------- UN SOLO FOTOGRAMA: capa vectorial simple ----------
		local cap = captureFrame(moho, layer, f0, o, true)
		if cap.note then notes[#notes + 1] = cap.note end
		local newLayer = newLayerOfType(moho, MOHO.LT_VECTOR)
		pcall(function() newLayer:SetName("Lineart - " .. layer:Name()) end)
		if cap.copyTransform then
			pcall(function()
				newLayer.fTranslation:SetValue(0, layer.fTranslation:GetValue(f0))
				newLayer.fScale:SetValue(0, layer.fScale:GetValue(f0))
				newLayer.fRotationZ:SetValue(0, layer.fRotationZ:GetValue(f0))
			end)
		end
		local mesh = moho:LayerAsVector(newLayer):Mesh()
		nLoops, nPoints = buildShapes(moho, mesh, cap, curStyle, lineW, failed, f0)
		msg = string.format("Fotograma %d  |  contornos: %d  |  puntos: %d  |  %.1f s",
			f0, nLoops, nPoints, os.clock() - t0)
		msg = msg .. string.format("\nFuente: %s (%dx%d px)",
			cap.usedRender and "render de la capa" or "PNG de la capa de imagen", cap.pw, cap.ph)
		if cap.bounds then
			msg = msg .. string.format("\nLímites del render: (%.3f, %.3f) a (%.3f, %.3f)",
				cap.bounds[1], cap.bounds[2], cap.bounds[3], cap.bounds[4])
		end
	else
		-- ---------- SECUENCIA: capa Switch con un dibujo por fotograma ----------
		local total = f1 - f0 + 1
		-- Fase A: analizar todos los fotogramas (la capa original sigue seleccionada)
		local caps, nErr, firstErr = {}, 0, nil
		for f = f0, f1 do
			local ok, cap = pcall(captureFrame, moho, layer, f, o, false)
			if ok then
				caps[f] = cap
			else
				if f == f0 then error("No pude procesar el primer fotograma: " .. tostring(cap), 0) end
				nErr = nErr + 1
				firstErr = firstErr or (f .. ": " .. tostring(cap))
				caps[f] = {loops = {}, toDoc = function(x, y) return 0, 0 end}
			end
			if (f - f0) % 25 == 0 then
				print(string.format("[AutoLineart] analizando fotograma %d/%d", f - f0 + 1, total))
			end
		end

		-- Fase B: crear la capa Switch y un dibujo vectorial por fotograma
		local swLayer = newLayerOfType(moho, MOHO.LT_SWITCH)
		pcall(function() swLayer:SetName("Lineart - " .. layer:Name()) end)
		local sw = moho:LayerAsSwitch(swLayer)
		for f = f0, f1 do
			local vlayer = newLayerOfType(moho, MOHO.LT_VECTOR)
			pcall(function() vlayer:SetName(tostring(f)) end)
			local okp = pcall(function() moho:PlaceLayerInGroup(vlayer, swLayer, true, false) end)
			if not okp then error("No pude mover el dibujo del fotograma " .. f .. " dentro de la capa Switch.", 0) end
			selectLayer(moho, vlayer)
			local mesh = moho:LayerAsVector(vlayer):Mesh()
			local nl, np = buildShapes(moho, mesh, caps[f], curStyle, lineW, failed, f)
			nLoops, nPoints = nLoops + nl, nPoints + np
			sw:SetValue(f, tostring(f))
			caps[f] = nil
			if (f - f0) % 25 == 0 then
				print(string.format("[AutoLineart] creando dibujo %d/%d", f - f0 + 1, total))
			end
		end

		-- Que no se vea nada fuera del rango pedido
		local okv = pcall(function()
			local docStart = moho.document:StartFrame()
			if f0 > docStart then swLayer.fVisibility:SetValue(docStart, false) end
			swLayer.fVisibility:SetValue(f0, true)
			swLayer.fVisibility:SetValue(f1 + 1, false)
		end)
		if not okv then notes[#notes + 1] = "No pude limitar la visibilidad al rango; la capa Switch se verá fuera de él." end
		selectLayer(moho, swLayer)

		msg = string.format("Fotogramas %d a %d (%d dibujos)  |  contornos: %d  |  puntos: %d  |  %.1f s",
			f0, f1, total, nLoops, nPoints, os.clock() - t0)
		msg = msg .. "\nCreada una capa Switch con un dibujo vectorial por fotograma."
		if nErr > 0 then
			msg = msg .. string.format("\n%d fotogramas fallaron y quedaron vacíos. Primer error: %s", nErr, tostring(firstErr))
		end
	end
	pcall(function() moho.document:SetDirty() end)

	local fl = {}
	for k in pairs(failed) do fl[#fl + 1] = k end
	table.sort(fl)
	if #fl > 0 then msg = msg .. "\nNo se pudo copiar del estilo: " .. table.concat(fl, ", ") end
	for _, n in ipairs(notes) do msg = msg .. "\n" .. n end
	if nLoops == 0 then msg = msg .. "\nNo se encontró ninguna silueta." end
	alert("Auto Lineart", msg)
end

-- ==============================================================
-- 6. DIÁLOGO
-- ==============================================================

local AL_Dialog = {}

function AL_Dialog:new(moho)
	local d = LM.GUI.SimpleDialog("Auto Lineart (prototipo v0.3)", AL_Dialog)
	local l = d:GetLayout()
	d.moho = moho
	local function field(label, kind)
		l:PushH()
			l:AddChild(LM.GUI.StaticText(label), LM.GUI.ALIGN_LEFT, 0)
			local c = LM.GUI.TextControl(0, "0000.00", 0, kind or LM.GUI.FIELD_FLOAT)
			l:AddChild(c, LM.GUI.ALIGN_LEFT, 0)
		l:Pop()
		return c
	end
	l:AddChild(LM.GUI.StaticText("El pincel, color y grosor se toman de la ventana Style de Moho."), LM.GUI.ALIGN_LEFT, 0)
	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL, 0)
	d.fStart  = field("Fotograma inicial:", LM.GUI.FIELD_INT)
	d.fEnd    = field("Fotograma final (igual al inicial = un solo fotograma):", LM.GUI.FIELD_INT)
	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL, 0)
	d.fSmooth = field("Suavizado (0-10):")
	d.fSimp   = field("Simplificación de puntos (tolerancia en px):")
	d.fMinLen = field("Ignorar contornos más cortos que (px):")
	d.fWidth  = field("Grosor en px (0 = usar el de Style):")
	return d
end

function AL_Dialog:UpdateWidgets()
	local f = (self.moho and self.moho.frame) or 0
	self.fStart:SetValue(f)
	self.fEnd:SetValue(f)
	self.fSmooth:SetValue(2)
	self.fSimp:SetValue(1.5)
	self.fMinLen:SetValue(12)
	self.fWidth:SetValue(0)
end

function AL_Dialog:OnOK() end

local function clampInt(v, lo, hi) return max(lo, min(hi, floor(v + 0.5))) end

function AL_AutoLineart:Run(moho)
	local dlg = AL_Dialog:new(moho)
	if dlg:DoModal() == LM.GUI.MSG_CANCEL then return end
	local o = {
		startFrame = dlg.fStart:IntValue(),
		endFrame   = dlg.fEnd:IntValue(),
		smooth     = clampInt(dlg.fSmooth:FloatValue(), 0, 10),
		simplify   = max(0, dlg.fSimp:FloatValue()),
		minLen     = max(0, dlg.fMinLen:FloatValue()),
		width      = max(0, dlg.fWidth:FloatValue()),
	}
	local ok, err = pcall(AL_AutoLineart.Generate, moho, o)
	if not ok then alert("Auto Lineart - error", err) end
end

return AL_AutoLineart
end
local TOOL_auto = make_auto()

-- ##############################################################
-- HERRAMIENTA: AL_ImportBlender
-- ##############################################################
local function make_imp()
-- **************************************************************
-- AL_ImportBlender  v0.6  (PROTOTIPO)
-- Importa a Moho los trazos de Line Art exportados desde Blender
-- con el add-on "Line Art to Moho" (lineart_to_moho.py).
--
-- Lee UN archivo .lineart con índice: lee el índice (pequeño),
-- salta directo a los fotogramas del rango pedido y solo lee esos.
-- Crea una capa Switch con un dibujo vectorial por fotograma
-- (o una capa vectorial simple si pides un solo fotograma).
-- El pincel, color y grosor se copian de la ventana Style.
-- Lua puro. Pensado para Moho Pro 14.4.
--
-- Instalación: copiar a la carpeta Scripts/Menu de tu contenido
-- personalizado de Moho y recargar scripts (o reiniciar Moho).
-- **************************************************************

local AL_ImportBlender = {}

local AL = {}
AL_ImportBlender._core = AL      -- expuesto para pruebas fuera de Moho

local floor, abs, sqrt, max, min = math.floor, math.abs, math.sqrt, math.max, math.min

function AL_ImportBlender:Name() return "Importar Line Art de Blender (prototipo)" end
function AL_ImportBlender:Version() return "0.6" end
function AL_ImportBlender:UILabel() return "Importar Line Art de Blender (prototipo)" end
function AL_ImportBlender:Creator() return "Claude" end
function AL_ImportBlender:Description()
	return "Crea trazos vectoriales a partir de los datos de Line Art exportados desde Blender."
end

-- ==============================================================
-- 1. LECTOR DE JSON (Lua puro)
-- ==============================================================

function AL.jsonDecode(s)
	local pos = 1
	local parseValue
	local ESC = {n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ["/"] = "/", ["\\"] = "\\", ['"'] = '"'}

	local function skip()
		pos = s:find("[^ \t\r\n]", pos) or (#s + 1)
	end

	local function parseString()
		local i, buf = pos + 1, {}
		while true do
			local j = s:find('["\\]', i)
			if not j then error("JSON: cadena sin cerrar") end
			buf[#buf + 1] = s:sub(i, j - 1)
			if s:sub(j, j) == '"' then
				pos = j + 1
				return table.concat(buf)
			end
			local e = s:sub(j + 1, j + 1)
			if e == "u" then
				buf[#buf + 1] = utf8.char(tonumber(s:sub(j + 2, j + 5), 16) or 63)
				i = j + 6
			else
				buf[#buf + 1] = ESC[e] or e
				i = j + 2
			end
		end
	end

	function parseValue()
		skip()
		local c = s:sub(pos, pos)
		if c == "{" then
			local obj = {}
			pos = pos + 1
			skip()
			if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
			while true do
				skip()
				if s:sub(pos, pos) ~= '"' then error("JSON: se esperaba una clave en la posición " .. pos) end
				local key = parseString()
				skip()
				if s:sub(pos, pos) ~= ":" then error("JSON: falta ':' en la posición " .. pos) end
				pos = pos + 1
				obj[key] = parseValue()
				skip()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "}" then return obj end
				if d ~= "," then error("JSON: se esperaba ',' o '}' en la posición " .. (pos - 1)) end
			end
		elseif c == "[" then
			local arr, n = {}, 0
			pos = pos + 1
			skip()
			if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
			while true do
				n = n + 1
				arr[n] = parseValue()
				skip()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "]" then return arr end
				if d ~= "," then error("JSON: se esperaba ',' o ']' en la posición " .. (pos - 1)) end
			end
		elseif c == '"' then
			return parseString()
		elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
		elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
		elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
		else
			local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
			if not num or num == "" then error("JSON: valor inesperado en la posición " .. pos) end
			pos = pos + #num
			return tonumber(num)
		end
	end

	local v = parseValue()
	return v
end

-- ==============================================================
-- 2. GEOMETRÍA de polilíneas (abiertas o cerradas), con presión por punto
-- ==============================================================

local function removeDuplicates(X, Y, P, closed)
	local nx, ny, np, k = {}, {}, {}, 0
	for i = 1, #X do
		if k == 0 or abs(X[i] - nx[k]) > 1e-6 or abs(Y[i] - ny[k]) > 1e-6 then
			k = k + 1
			nx[k], ny[k], np[k] = X[i], Y[i], P[i]
		end
	end
	if closed and k > 1 and abs(nx[1] - nx[k]) <= 1e-6 and abs(ny[1] - ny[k]) <= 1e-6 then
		nx[k], ny[k], np[k] = nil, nil, nil
	end
	return nx, ny, np
end

local function smooth(X, Y, passes, closed)
	local n = #X
	if passes <= 0 or n < 3 then return X, Y end
	for _ = 1, passes do
		local nx, ny = {}, {}
		for i = 1, n do
			if not closed and (i == 1 or i == n) then
				nx[i], ny[i] = X[i], Y[i]
			else
				local ip, inx = (i - 2) % n + 1, i % n + 1
				nx[i] = (X[ip] + 2 * X[i] + X[inx]) / 4
				ny[i] = (Y[ip] + 2 * Y[i] + Y[inx]) / 4
			end
		end
		X, Y = nx, ny
	end
	return X, Y
end

-- Douglas-Peucker. Devuelve la lista de índices a conservar (ordenada)
local function simplifyIndices(X, Y, tol, closed)
	local n = #X
	local all = {}
	for i = 1, n do all[i] = i end
	if tol <= 0 or n <= 3 then return all end
	local t2 = tol * tol
	local keep = {}
	local stack = {}
	local function idx(i) return (i - 1) % n + 1 end
	if closed then
		local far, fd = 2, -1
		for i = 2, n do
			local d = (X[i] - X[1]) ^ 2 + (Y[i] - Y[1]) ^ 2
			if d > fd then fd = d; far = i end
		end
		keep[1] = true; keep[far] = true
		stack = {{1, far}, {far, n + 1}}
	else
		keep[1] = true; keep[n] = true
		stack = {{1, n}}
	end
	while #stack > 0 do
		local seg = table.remove(stack)
		local a, b = seg[1], seg[2]
		local ia, ib = idx(a), idx(b)
		local ax, ay, bx, by = X[ia], Y[ia], X[ib], Y[ib]
		local dx, dy = bx - ax, by - ay
		local len2 = dx * dx + dy * dy
		local md, mi = -1, nil
		for i = a + 1, b - 1 do
			local k = idx(i)
			local d
			if len2 == 0 then
				d = (X[k] - ax) ^ 2 + (Y[k] - ay) ^ 2
			else
				local cr = (X[k] - ax) * dy - (Y[k] - ay) * dx
				d = cr * cr / len2
			end
			if d > md then md = d; mi = i end
		end
		if mi and md > t2 then
			keep[idx(mi)] = true
			stack[#stack + 1] = {a, mi}
			stack[#stack + 1] = {mi, b}
		end
	end
	local out = {}
	for i = 1, n do if keep[i] then out[#out + 1] = i end end
	if #out < 2 then return all end
	return out
end

-- Procesa un trazo ya en píxeles. Devuelve X, Y, P, closed  (o nil si se descarta)
function AL.processStroke(X, Y, P, closed, o)
	X, Y, P = removeDuplicates(X, Y, P, closed)
	if closed and #X < 3 then closed = false end
	if #X < 2 then return nil end
	X, Y = smooth(X, Y, o.smooth, closed)
	local idxs = simplifyIndices(X, Y, o.simplify, closed)
	local nx, ny, np = {}, {}, {}
	for k, i in ipairs(idxs) do nx[k], ny[k], np[k] = X[i], Y[i], P[i] end
	if closed and #nx < 3 then closed = false end
	if #nx < 2 then return nil end
	return nx, ny, np, closed
end

-- ==============================================================
-- 3. CÓDIGO DE MOHO (solo métodos que aparecen en la documentación)
-- ==============================================================

local function alert(title, msg)
	print("[ImportBlender] " .. tostring(title) .. ": " .. tostring(msg))
	pcall(function()
		LM.GUI.Alert(LM.GUI.ALERT_INFO, title, msg, nil, "OK", nil, nil)
	end)
end

-- Registro de diagnóstico: cada línea se guarda en disco de inmediato, así que si Moho
-- se cierra de golpe, la última línea del .log.txt dice qué llamada estaba ejecutando.
local LOG = nil
local LOGPATH = nil
local function openLog(fallbackPath)
	local cands = {}
	local tmp = os.getenv("TEMP") or os.getenv("TMP")
	if tmp then cands[#cands + 1] = tmp .. "\\al_import_blender_log.txt" end
	if fallbackPath then cands[#cands + 1] = fallbackPath .. ".log.txt" end
	for _, c in ipairs(cands) do
		local f = io.open(c, "w")
		if f then LOG = f; LOGPATH = c; return end
	end
end
local function log(...)
	if not LOG then return end
	local ok, line = pcall(string.format, ...)
	LOG:write(ok and line or tostring((...)), "\n")
	LOG:flush()
end

local function readWholeFile(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local d = f:read("*a")
	f:close()
	return d
end

local STYLE_VALUES = {
	"fBrushAlign", "fBrushIsColor", "fBrushMergedAlpha", "fBrushRandomize",
	"fBrushRandomOrder", "fBrushTint", "fBrushAngleDrift", "fBrushHueDrift",
	"fBrushJitter", "fBrushRandomInterval", "fBrushSatDrift", "fBrushSizeVariationAmp",
	"fBrushSizeVariationScale", "fBrushSpacing", "fBrushValDrift", "fLineCaps", "fLineWidth",
}

local function copyStyle(dst, src, frame, failed)
	for _, f in ipairs(STYLE_VALUES) do
		local ok = pcall(function() dst[f] = src[f] end)
		if not ok then failed[f] = true end
	end
	local ok = pcall(function() dst.fBrushName:Set(src.fBrushName:Buffer()) end)
	if not ok then failed["fBrushName"] = true end
	ok = pcall(function() dst.fLineCol:SetValue(0, src.fLineCol:GetValue(frame)) end)
	if not ok then failed["fLineCol"] = true end
	dst.fDefineLineWidth = true
	dst.fDefineLineCol = true
end

local function newLayerOfType(moho, ltype)
	local okc, res = pcall(function() return moho:CreateNewLayer(ltype, false) end)
	if okc and res then return res end
	return moho:CreateNewLayer(ltype)
end

local function selectLayer(moho, layer)
	pcall(function() moho:SetSelLayer(layer) end)
end

-- Convierte un trazo abierto en un lazo cerrado de "ida y vuelta": recorre el trazo
-- y regresa por casi el mismo camino (desplazado una fracción de píxel) para poder
-- usar solo curvas cerradas. Devuelve X, Y, P nuevos.
local function loopify(X, Y, P, eps)
	local n = #X
	local nx, ny, np = {}, {}, {}
	for i = 1, n do nx[i], ny[i], np[i] = X[i], Y[i], P[i] end
	local function normalAt(i)
		local a, b = max(1, i - 1), min(n, i + 1)
		local tx, ty = X[b] - X[a], Y[b] - Y[a]
		local tl = sqrt(tx * tx + ty * ty)
		if tl == 0 then return 0, 0 end
		return -ty / tl, tx / tl
	end
	if n == 2 then
		local mx, my = (X[1] + X[2]) / 2, (Y[1] + Y[2]) / 2
		local ax, ay = normalAt(1)
		nx[#nx + 1], ny[#ny + 1], np[#np + 1] = mx + ax * eps, my + ay * eps, (P[1] + P[2]) / 2
	else
		for i = n - 1, 2, -1 do
			local ax, ay = normalAt(i)
			nx[#nx + 1], ny[#ny + 1], np[#np + 1] = X[i] + ax * eps, Y[i] + ay * eps, P[i]
		end
	end
	return nx, ny, np
end

-- Crea las curvas/formas de una lista de trazos (en coordenadas ya de Moho)
-- strokes[i] = {X=, Y=, P=, closed=}. La capa vectorial destino debe estar seleccionada.
local function buildStrokes(moho, mesh, strokes, curStyle, lineW, failed, frame, o, stats)
	local v = LM.Vector2:new_local()
	local limit = o.strokeLimit or 0
	for si, s in ipairs(strokes) do
		if limit > 0 and si > limit then break end
		local X, Y, P, isClosed = s.X, s.Y, s.P, s.closed
		if not isClosed and o.closeOpen then
			X, Y, P = loopify(X, Y, P, o.eps or 0.0003)
			isClosed = true
		end
		log("  trazo %d/%d: %d puntos, %s%s", si, #strokes, #X, isClosed and "cerrado" or "abierto",
			(s.closed ~= isClosed) and " (ida y vuelta)" or "")
		mesh:SelectNone()
		local first = mesh:CountPoints()
		v:Set(X[1], Y[1])
		log("    AddLonePoint")
		mesh:AddLonePoint(v, 0)
		for i = 2, #X do
			v:Set(X[i], Y[i])
			mesh:AppendPoint(v, 0)
		end
		log("    AppendPoint x%d ok", #X - 1)
		if isClosed then
			v:Set(X[1], Y[1])
			mesh:AppendPoint(v, 0)                       -- punto duplicado para cerrar
			log("    WeldPoints")
			mesh:WeldPoints(mesh:CountPoints() - 1, first, 0)
		end
		local lastKept = mesh:CountPoints() - 1
		for id = first, lastKept do
			local pt = mesh:Point(id)
			pt.fSelected = true
			if o.usePressure then
				local w = (P[id - first + 1] or 1) * o.pressureScale
				local ok = pcall(function() pt.fWidth:SetValue(0, w) end)
				if not ok then stats.widthFail = true end
			end
		end
		local before = mesh:CountShapes()
		log("    CreateShape (formas antes: %d, puntos %d..%d)", before, first, lastKept)
		local okCS, ret = pcall(function() return moho:CreateShape(false) end)
		local after = mesh:CountShapes()
		log("    CreateShape terminó: ok=%s ret=%s formas después: %d", tostring(okCS), tostring(ret), after)
		if okCS and after > before then
			local shape = mesh:Shape(after - 1)       -- solo si de verdad se creó una forma nueva
			shape.fHasFill = false
			shape.fHasOutline = true
			log("    copyStyle")
			copyStyle(shape.fMyStyle, curStyle, frame, failed)
			if lineW then shape.fMyStyle.fLineWidth = lineW end
			stats.strokes = stats.strokes + 1
			stats.points = stats.points + (lastKept - first + 1)
		else
			stats.shapeFail = stats.shapeFail + 1
			if stats.shapeFail >= 3 and stats.strokes == 0 then
				error("CreateShape no creó ninguna forma con estos trazos (curvas " ..
					(isClosed and "cerradas" or "abiertas") .. "). Me detuve para no dejar basura en el proyecto.")
			end
		end
		mesh:SelectNone()
	end
end

-- Abre el archivo .lineart y lee su índice. Devuelve el manejador abierto y el índice.
local HEADER_LEN = 81
local function openIndexed(path)
	local f = io.open(path, "rb")
	if not f then error("No pude abrir el archivo:\n" .. path) end
	local head = f:read(HEADER_LEN) or ""
	local off, len = head:match("^LINEARTMOHO 2 index_offset=(%d+) index_length=(%d+)")
	off, len = tonumber(off), tonumber(len)
	if not off then
		f:close()
		error("Ese archivo no es un export de Line Art to Moho (.lineart, versión 2).")
	end
	if off == 0 or len == 0 then
		f:close()
		error("El archivo está incompleto: Blender no terminó de escribirlo. Vuelve a exportar.")
	end
	f:seek("set", off)
	local idxStr = f:read(len)
	if not idxStr or #idxStr < len then
		f:close()
		error("El índice del archivo está truncado. Vuelve a exportar.")
	end
	local ok, index = pcall(AL.jsonDecode, idxStr)
	if not ok or type(index) ~= "table" or not index.frames then
		f:close()
		error("No pude leer el índice del archivo.")
	end
	return f, index
end

-- Salta al fotograma indicado, lo lee y lo deja procesado, en píxeles del proyecto.
-- Devuelve lista de trazos {X, Y, P, closed}
local function loadFrame(handle, entry, W, H, o)
	handle:seek("set", entry.offset)
	local data = handle:read(entry.length)
	if not data or #data < entry.length then error("Datos truncados en el fotograma " .. tostring(entry.frame)) end
	local doc = AL.jsonDecode(data)
	local out = {}
	for _, st in ipairs(doc.strokes or {}) do
		local X, Y, P = {}, {}, {}
		for i, p in ipairs(st.puntos or {}) do
			X[i] = p[1] * W
			Y[i] = p[2] * H
			P[i] = p[3] or 1
		end
		local nx, ny, np, closed = AL.processStroke(X, Y, P, st.cerrado == true, o)
		if nx then out[#out + 1] = {X = nx, Y = ny, P = np, closed = closed} end
	end
	return out
end

-- Pasa trazos de píxeles a coordenadas de Moho
local function toMoho(strokes, W, H, Wu, Hu)
	for _, s in ipairs(strokes) do
		for i = 1, #s.X do
			s.X[i] = (s.X[i] / W - 0.5) * Wu
			s.Y[i] = (s.Y[i] / H - 0.5) * Hu
		end
	end
	return strokes
end

local function GenerateInner(moho, o)
	local t0 = os.clock()
	local srcLayer = moho.layer

	-- índice del archivo (solo se lee el índice, no todos los fotogramas)
	log("Abriendo índice...")
	local handle, manifest = openIndexed(o.path)
	log("Índice leído: %d fotogramas disponibles", #manifest.frames)

	-- fotogramas disponibles dentro del rango pedido
	local entries, availMin, availMax = {}, nil, nil
	for _, e in ipairs(manifest.frames) do
		local f = floor(e.frame)
		availMin = availMin and min(availMin, f) or f
		availMax = availMax and max(availMax, f) or f
		if f >= o.startFrame and f <= o.endFrame then
			entries[#entries + 1] = {frame = f, offset = e.offset, length = e.length}
		end
	end
	table.sort(entries, function(a, b) return a.frame < b.frame end)
	if (o.frameLimit or 0) > 0 then
		while #entries > o.frameLimit do entries[#entries] = nil end
	end
	if #entries == 0 then
		handle:close()
		error("El archivo no contiene ningún fotograma.")
	end

	-- tamaño del proyecto (los datos vienen normalizados 0-1 respecto a la cámara)
	local W, H = 1920, 1080
	pcall(function() W = moho.document:Width(); H = moho.document:Height() end)
	-- Tamaño FIJO en unidades de Moho, sin depender de la cámara ni del zoom de la vista:
	-- el encuadre del proyecto mide 2 unidades de alto (-1 a 1) y 2*ancho/alto de ancho.
	-- Así el liner cae exactamente sobre una secuencia de imágenes del mismo tamaño.
	local Hu = 2
	local Wu = 2 * W / H
	local upp = Hu / H                             -- unidades de Moho por píxel del proyecto
	local pxdoc = nil
	pcall(function() pxdoc = moho:PixelToDoc(1) end)
	log("Proyecto: %dx%d px, unidades fijas %.4f x %.4f (PixelToDoc(1)=%s, solo informativo)", W, H, Wu, Hu, tostring(pxdoc))
	local curStyle = moho:CurrentEditStyle()
	log("CurrentEditStyle ok")
	local failed = {}
	local lineW = (o.width > 0) and (o.width * upp) or nil
	local stats = {strokes = 0, points = 0, shapeFail = 0, widthFail = false}
	o.eps = 0.25 * upp                       -- 0,25 px en unidades de Moho

	-- fase A: leer y procesar todos los fotogramas del rango
	local frames = {}
	local okRead, errRead = pcall(function()
		for i, e in ipairs(entries) do
			frames[i] = toMoho(loadFrame(handle, e, W, H, o), W, H, Wu, Hu)
			if (i - 1) % 25 == 0 then
				print(string.format("[ImportBlender] leyendo fotograma %d/%d", i, #entries))
			end
		end
	end)
	handle:close()
	if not okRead then error(errRead) end

	log("Fase A (lectura) terminada. Fase B: crear capas")
	local lastMoho
	if #entries == 1 then
		log("Un solo fotograma: crear capa vectorial")
		local vlayer = newLayerOfType(moho, MOHO.LT_VECTOR)
		pcall(function() vlayer:SetName("Lineart Blender - " .. tostring(entries[1].frame)) end)
		selectLayer(moho, vlayer)
		local mesh = moho:LayerAsVector(vlayer):Mesh()
		buildStrokes(moho, mesh, frames[1], curStyle, lineW, failed, entries[1].frame + o.offset, o, stats)
		lastMoho = entries[1].frame + o.offset
	else
		log("Crear capa Switch")
		local swLayer = newLayerOfType(moho, MOHO.LT_SWITCH)
		pcall(function() swLayer:SetName("Lineart Blender") end)
		local sw = moho:LayerAsSwitch(swLayer)
		for i, e in ipairs(entries) do
			local mf = e.frame + o.offset
			log("Fotograma Blender %d -> Moho %d: crear capa vectorial", e.frame, mf)
			local vlayer = newLayerOfType(moho, MOHO.LT_VECTOR)
			pcall(function() vlayer:SetName(tostring(mf)) end)
			log("  PlaceLayerInGroup")
			local okp = pcall(function() moho:PlaceLayerInGroup(vlayer, swLayer, true, false) end)
			if not okp then error("No pude mover el dibujo del fotograma " .. mf .. " dentro de la capa Switch.") end
			log("  SetSelLayer / LayerAsVector")
			selectLayer(moho, vlayer)
			local mesh = moho:LayerAsVector(vlayer):Mesh()
			buildStrokes(moho, mesh, frames[i], curStyle, lineW, failed, mf, o, stats)
			sw:SetValue(mf, tostring(mf))
			frames[i] = nil
			lastMoho = mf
			if (i - 1) % 25 == 0 then
				print(string.format("[ImportBlender] creando dibujo %d/%d", i, #entries))
			end
		end
		local firstMoho = entries[1].frame + o.offset
		local okv = pcall(function()
			local docStart = moho.document:StartFrame()
			if firstMoho > docStart then swLayer.fVisibility:SetValue(docStart, false) end
			swLayer.fVisibility:SetValue(firstMoho, true)
			swLayer.fVisibility:SetValue(lastMoho + 1, false)
		end)
		if not okv then stats.visFail = true end
		selectLayer(moho, swLayer)
	end

	-- marco de alineación opcional (rectángulo del encuadre + diagonal desde abajo-izquierda)
	if o.drawFrame then
		local fl = newLayerOfType(moho, MOHO.LT_VECTOR)
		pcall(function() fl:SetName("Marco de alineación") end)
		selectLayer(moho, fl)
		local mesh = moho:LayerAsVector(fl):Mesh()
		local function pt(nx, ny) return (nx - 0.5) * Wu, (ny - 0.5) * Hu end
		local function stroke(closed, ...)
			local X, Y, P = {}, {}, {}
			for _, c in ipairs({...}) do
				local x, y = pt(c[1], c[2])
				X[#X + 1], Y[#Y + 1], P[#P + 1] = x, y, 1
			end
			return {X = X, Y = Y, P = P, closed = closed}
		end
		local fs = {
			stroke(true, {0, 0}, {1, 0}, {1, 1}, {0, 1}),
			stroke(false, {0, 0}, {0.5, 0.5}),
		}
		local ostats = {strokes = 0, points = 0, shapeFail = 0}
		buildStrokes(moho, mesh, fs, curStyle, lineW, failed, moho.frame, {usePressure = false, closeOpen = o.closeOpen, eps = o.eps}, ostats)
		selectLayer(moho, fl)
	end

	pcall(function() moho.document:SetDirty() end)

	local msg = string.format("Fotogramas importados: %d (Blender %d a %d)  |  trazos: %d  |  puntos: %d  |  %.1f s",
		#entries, entries[1].frame, entries[#entries].frame, stats.strokes, stats.points, os.clock() - t0)
	if o.offset ~= 0 then msg = msg .. string.format("\nDesfase aplicado: Moho = Blender %+d", o.offset) end
	if #entries > 1 then msg = msg .. "\nCreada una capa Switch con un dibujo por fotograma." end
	local missing = {}
	for _, f in ipairs(manifest.omitidos or {}) do
		if f >= o.startFrame and f <= o.endFrame then missing[#missing + 1] = tostring(f) end
	end
	if #missing > 0 then
		msg = msg .. "\nSin datos (no horneados en Blender): " .. table.concat(missing, ", ", 1, min(#missing, 8)) ..
			((#missing > 8) and ", ..." or "")
	end
	if stats.shapeFail > 0 then
		msg = msg .. string.format("\n%d trazos no se pudieron convertir en forma (CreateShape falló).", stats.shapeFail)
	end
	if stats.widthFail then msg = msg .. "\nNo se pudo aplicar el grosor por punto (fWidth)." end
	if stats.visFail then msg = msg .. "\nNo pude limitar la visibilidad de la capa Switch al rango." end
	local fl = {}
	for k in pairs(failed) do fl[#fl + 1] = k end
	table.sort(fl)
	if #fl > 0 then msg = msg .. "\nNo se pudo copiar del estilo: " .. table.concat(fl, ", ") end
	if stats.strokes == 0 then msg = msg .. "\nNo se creó ningún trazo." end
	alert("Importar Line Art", msg)
end

function AL_ImportBlender.Generate(moho, o)
	local ownLog = false
	if not LOG then openLog(o.path); ownLog = true end
	if LOG then
		log("Importar Line Art v0.6 - inicio. Archivo: %s", o.path)
		log("Límite de fotogramas %d, desfase %d, suavizado %d, simplificación %.2f, límite de trazos %d, presión=%s",
			o.frameLimit or 0, o.offset, o.smooth, o.simplify, o.strokeLimit or 0, tostring(o.usePressure))
	end
	local ok, err = pcall(GenerateInner, moho, o)
	if LOG then
		log(ok and "FIN correcto" or ("ERROR: " .. tostring(err)))
		if ownLog then LOG:close(); LOG = nil end
	end
	if not ok then error(err, 0) end
end

-- ==============================================================
-- 4. DIÁLOGO
-- ==============================================================

local AL_Dialog = {}

function AL_Dialog:new(moho)
	local d = LM.GUI.SimpleDialog("Importar Line Art de Blender (v0.6)", AL_Dialog)
	local l = d:GetLayout()
	d.moho = moho
	local function field(label, kind, width)
		l:PushH()
			l:AddChild(LM.GUI.StaticText(label), LM.GUI.ALIGN_LEFT, 0)
			local c = LM.GUI.TextControl(width or 0, "0000.00", 0, kind or LM.GUI.FIELD_FLOAT)
			l:AddChild(c, LM.GUI.ALIGN_LEFT, 0)
		l:Pop()
		return c
	end
	l:AddChild(LM.GUI.StaticText("El pincel, color y grosor se toman de la ventana Style de Moho."), LM.GUI.ALIGN_LEFT, 0)
	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL, 0)
	d.fFrames = field("Importar solo los primeros N fotogramas (0 = todo el archivo):")
	d.fOffset = field("Desfase (fotograma de Moho = Blender + desfase):")
	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL, 0)
	d.fSmooth = field("Suavizado (0-10):")
	d.fSimp   = field("Simplificación de puntos (tolerancia en px):")
	d.fWidth  = field("Grosor en px (0 = usar el de Style):")
	d.cPress  = LM.GUI.CheckBox("Experimental: usar la presión de Blender como grosor por punto", 0)
	l:AddChild(d.cPress, LM.GUI.ALIGN_LEFT, 0)
	d.cFrame  = LM.GUI.CheckBox("Dibujar un marco de alineación (para comprobar la escala)", 0)
	l:AddChild(d.cFrame, LM.GUI.ALIGN_LEFT, 0)
	d.fLimit  = field("Límite de trazos por fotograma (0 = todos; útil para probar):")
	d.cClose  = LM.GUI.CheckBox("Cerrar los trazos abiertos como lazos de ida y vuelta (normalmente NO)", 0)
	l:AddChild(d.cClose, LM.GUI.ALIGN_LEFT, 0)
	return d
end

function AL_Dialog:UpdateWidgets()
	self.fFrames:SetValue(0)
	self.fOffset:SetValue(0)
	self.fSmooth:SetValue(1)
	self.fSimp:SetValue(0.75)
	self.fWidth:SetValue(0)
	self.cPress:SetValue(false)
	self.cFrame:SetValue(false)
	self.fLimit:SetValue(0)
	self.cClose:SetValue(false)
end

function AL_Dialog:OnOK() end

local function clampInt(v, lo, hi) return max(lo, min(hi, floor(v + 0.5))) end

function AL_ImportBlender:Run(moho, presetPath)
	openLog(nil)
	log("Run: inicio (v0.6)")
	-- El selector de archivos va PRIMERO, antes de cualquier diálogo (igual que SS_BVH_Bones):
	-- abrirlo después de un diálogo propio cerraba Moho.
	local path = presetPath or LM.GUI.OpenFile("Elige el archivo .lineart exportado desde Blender")
	path = tostring(path or "")
	path = path:gsub('^%s*"?', ""):gsub('"?%s*$', "")
	log("Run: archivo elegido = %s", path)
	if path == "" then
		if LOG then LOG:close(); LOG = nil end
		return
	end
	local dlg = AL_Dialog:new(moho)
	log("Run: diálogo creado")
	if dlg:DoModal() == LM.GUI.MSG_CANCEL then
		log("Run: cancelado por el usuario")
		if LOG then LOG:close(); LOG = nil end
		return
	end
	log("Run: diálogo aceptado, leyendo valores")
	local o = {
		path          = path,
		startFrame    = -2147483647,                 -- se importa todo el archivo
		endFrame      = 2147483647,
		frameLimit    = max(0, floor(dlg.fFrames:FloatValue() + 0.5)),
		offset        = floor(dlg.fOffset:FloatValue() + 0.5),
		smooth        = clampInt(dlg.fSmooth:FloatValue(), 0, 10),
		simplify      = max(0, dlg.fSimp:FloatValue()),
		width         = max(0, dlg.fWidth:FloatValue()),
		usePressure   = dlg.cPress:Value(),
		pressureScale = 1,
		drawFrame     = dlg.cFrame:Value(),
		strokeLimit   = max(0, floor(dlg.fLimit:FloatValue() + 0.5)),
		closeOpen     = dlg.cClose:Value(),
	}
	log("Run: valores leídos; archivo = %s", o.path)
	local ok, err = pcall(AL_ImportBlender.Generate, moho, o)
	if LOG then LOG:close(); LOG = nil end
	if not ok then
		err = tostring(err):gsub("^.-:%d+: ", "")   -- quitar "archivo.lua:123:" del mensaje
		alert("Importar Line Art - error", err)
	end
end

return AL_ImportBlender
end
local TOOL_imp = make_imp()

-- ##############################################################
-- HERRAMIENTA: AL_PropagarEstilo
-- ##############################################################
local function make_prop()
-- **************************************************************
-- AL_PropagarEstilo  v0.3  (Función 3A: propagación global)
-- Modificas los vectores de UN fotograma (la referencia) y el script detecta
-- qué propiedades cambiaste (pincel, parámetros, grosor, color, extremos) y las
-- copia a TODOS los trazos de los demás dibujos del Switch, dentro del rango.
-- No importa que cada fotograma tenga distinta cantidad de trazos o vértices.
-- No cambia la forma de los trazos, solo sus propiedades.
-- Pensado para Moho Pro 14.4. Se prueba por separado de los otros scripts.
-- **************************************************************

local AL_PropagarEstilo = {}

function AL_PropagarEstilo:Name() return "Propagar estilo a todos los fotogramas del Switch" end
function AL_PropagarEstilo:Version() return "0.3" end
function AL_PropagarEstilo:UILabel() return "Propagar estilo a todos los fotogramas del Switch" end
function AL_PropagarEstilo:Creator() return "Claude" end
function AL_PropagarEstilo:Description()
	return "Copia pincel, grosor, color y otros cambios de estilo del fotograma de referencia a todos los demas fotogramas de la capa Switch seleccionada"
end

local floor, max = math.floor, math.max

local function alert(title, msg)
	pcall(function()
		LM.GUI.Alert(LM.GUI.ALERT_INFO, title, msg, nil, "OK", nil, nil)
	end)
end

-- Campos de M_Style (todos existen en la documentación de Moho)
local BRUSH_PARAMS = {
	"fBrushAlign", "fBrushIsColor", "fBrushMergedAlpha", "fBrushRandomize",
	"fBrushRandomOrder", "fBrushTint", "fBrushAngleDrift", "fBrushHueDrift",
	"fBrushJitter", "fBrushRandomInterval", "fBrushSatDrift", "fBrushSizeVariationAmp",
	"fBrushSizeVariationScale", "fBrushSpacing", "fBrushValDrift",
}

-- Cada propiedad: nombre, grupo (casilla del diálogo), cómo leerla como texto comparable
-- y cómo copiarla de un estilo a otro.
local function buildProps(refFrame)
	local props = {}
	props[#props + 1] = {
		name = "Pincel", group = "brush",
		get = function(st) return tostring(st.fBrushName:Buffer()) end,
		set = function(dst, st) dst.fBrushName:Set(st.fBrushName:Buffer()) end,
	}
	for _, f in ipairs(BRUSH_PARAMS) do
		props[#props + 1] = {
			name = f, group = "params",
			get = function(st)
				local v = st[f]
				if type(v) == "number" then return string.format("%.4f", v) end
				return tostring(v)
			end,
			set = function(dst, st) dst[f] = st[f] end,
		}
	end
	props[#props + 1] = {
		name = "Grosor de línea", group = "width",
		get = function(st) return string.format("%.5f", st.fLineWidth) end,
		set = function(dst, st) dst.fLineWidth = st.fLineWidth; dst.fDefineLineWidth = true end,
	}
	props[#props + 1] = {
		name = "Color de línea", group = "color",
		get = function(st)
			local c = st.fLineCol:GetValue(refFrame)
			return string.format("%d,%d,%d,%d", floor(c.r + 0.5), floor(c.g + 0.5), floor(c.b + 0.5), floor(c.a + 0.5))
		end,
		set = function(dst, st)
			dst.fLineCol:SetValue(0, st.fLineCol:GetValue(refFrame))
			dst.fDefineLineCol = true
		end,
	}
	props[#props + 1] = {
		name = "Extremos de línea", group = "caps",
		get = function(st) return tostring(st.fLineCaps) end,
		set = function(dst, st) dst.fLineCaps = st.fLineCaps end,
	}
	return props
end

-- Devuelve la capa vectorial (VectorLayer) de una capa, o nil si no es vectorial
local function asVector(moho, layer)
	local ok, vl = pcall(function()
		if layer:LayerType() ~= MOHO.LT_VECTOR then return nil end
		return moho:LayerAsVector(layer)
	end)
	if ok then return vl end
	return nil
end

-- Lista de estilos (M_Style) de todos los trazos de una capa vectorial
local function shapeStyles(vl, out, shapesOut)
	local mesh = vl:Mesh()
	if not mesh then return end
	for i = 0, mesh:CountShapes() - 1 do
		local sh = mesh:Shape(i)
		if sh then
			out[#out + 1] = sh.fMyStyle
			if shapesOut then shapesOut[#shapesOut + 1] = sh end
		end
	end
end

-- Valor más repetido de una propiedad entre una lista de estilos.
-- Devuelve el valor (texto) y un estilo representativo que lo tiene.
local function modeOf(prop, styles)
	local counts, rep = {}, {}
	local bestV, bestN
	for _, st in ipairs(styles) do
		local ok, v = pcall(prop.get, st)
		if ok then
			counts[v] = (counts[v] or 0) + 1
			if not rep[v] then rep[v] = st end
			if not bestN or counts[v] > bestN then bestV, bestN = v, counts[v] end
		end
	end
	return bestV, rep[bestV]
end

-- ==============================================================
-- Trabajo principal
-- ==============================================================

local function Propagate(moho, o)
	local layer = moho.layer
	local sw
	local okSw = pcall(function()
		if layer:LayerType() == MOHO.LT_SWITCH then sw = moho:LayerAsSwitch(layer) end
	end)
	if not okSw or not sw then
		error("Selecciona primero la capa Switch (la que contiene un dibujo por fotograma).")
	end
	local n = sw:CountLayers()
	if n < 2 then error("El Switch tiene menos de 2 dibujos: no hay nada que propagar.") end

	-- dibujo de referencia: el que el Switch muestra en el fotograma de referencia
	local refName = sw:GetValue(o.refFrame)
	local refLayer
	for i = 0, n - 1 do
		local c = sw:Layer(i)
		if c:Name() == refName then refLayer = c; break end
	end
	if not refLayer then
		error("En el fotograma " .. tostring(o.refFrame) .. " el Switch no muestra ningún dibujo.\n" ..
			"Ve a un fotograma que tenga dibujo, o cambia el fotograma de referencia.")
	end
	local refVec = asVector(moho, refLayer)
	if not refVec then error("El dibujo de referencia ('" .. tostring(refName) .. "') no es una capa vectorial.") end
	local refStyles = {}
	shapeStyles(refVec, refStyles)
	if #refStyles == 0 then error("El dibujo de referencia ('" .. tostring(refName) .. "') no tiene trazos.") end
	if o.useStyleWindow then refStyles = {moho:CurrentEditStyle()} end

	-- trazos de destino: todos los demás dibujos dentro del rango
	local targets, nLayers, skipped = {}, 0, 0
	local targetShapes = {}
	local touched = {}                              -- capas modificadas, para refrescarlas
	for i = 0, n - 1 do
		local c = sw:Layer(i)
		local cname = c:Name()
		local frameNo = tonumber(cname)
		local inRange = (frameNo == nil) or (frameNo >= o.startFrame and frameNo <= o.endFrame)
		if inRange and cname ~= refName then
			local vec = asVector(moho, c)
			if vec then
				shapeStyles(vec, targets, targetShapes)
				touched[#touched + 1] = c
				nLayers = nLayers + 1
			else
				skipped = skipped + 1
			end
		end
	end
	if #targets == 0 then error("No hay trazos en los demás dibujos del rango elegido.") end

	-- decidir qué propiedades propagar
	local props = buildProps(o.refFrame)
	local changed, report = {}, {}
	for _, p in ipairs(props) do
		if o[p.group] then
			local rv, rst = modeOf(p, refStyles)
			local tv = modeOf(p, targets)
			if rv ~= nil and rst and (o.force or rv ~= tv) then
				changed[#changed + 1] = {prop = p, src = rst}
				report[#report + 1] = string.format("  %s: %s  (antes: %s)", p.name, tostring(rv), tostring(tv))
			end
		end
	end

	local failed, nShapes = {}, 0
	local brushChanged = false
	for _, ch in ipairs(changed) do if ch.prop.group == "brush" or ch.prop.group == "params" then brushChanged = true end end
	if #changed > 0 then
		for _, dst in ipairs(targets) do
			for _, ch in ipairs(changed) do
				local ok = pcall(ch.prop.set, dst, ch.src)
				if not ok then failed[ch.prop.name] = true end
			end
			nShapes = nShapes + 1
		end
		-- Moho no recarga la imagen del pincel en pantalla al cambiar su nombre por script
		-- (no hay llamada documentada para eso). Intento: apagar y encender el contorno de
		-- cada trazo para obligarlo a reevaluar su estilo.
		if brushChanged then
			for _, sh in ipairs(targetShapes) do
				pcall(function() sh.fHasOutline = false; sh.fHasOutline = true end)
			end
		end
		-- Moho guarda imágenes ya dibujadas de cada capa: hay que avisarle que cambiaron
		-- (FreeCachedImage, v12+) y que recalcule (UpdateCurFrame), o no se ve hasta reabrir.
		touched[#touched + 1] = refLayer
		touched[#touched + 1] = layer
		for _, c in ipairs(touched) do
			pcall(function() c:FreeCachedImage() end)
			pcall(function() c:UpdateCurFrame() end)
		end
		pcall(function() moho.document:SetDirty() end)
		pcall(function() moho:SetCurFrame(moho.frame) end)
		pcall(function() moho.document:Refresh() end)
		pcall(function() moho:UpdateUI() end)
	end
	return nLayers, nShapes, skipped, failed, report, refName
end

-- ==============================================================
-- Diálogo
-- ==============================================================

local AL_Dialog = {}

function AL_Dialog:new(moho)
	local d = LM.GUI.SimpleDialog("Propagar estilo a todos los fotogramas del Switch", AL_Dialog)
	local l = d:GetLayout()
	d.moho = moho
	local function field(label)
		l:PushH()
			l:AddChild(LM.GUI.StaticText(label), LM.GUI.ALIGN_LEFT, 0)
			local c = LM.GUI.TextControl(0, "0000.00", 0, LM.GUI.FIELD_FLOAT)
			l:AddChild(c, LM.GUI.ALIGN_LEFT, 0)
		l:Pop()
		return c
	end
	l:AddChild(LM.GUI.StaticText("Selecciona la capa Switch. Cambia los vectores de UN fotograma (la referencia)"), LM.GUI.ALIGN_LEFT, 0)
	l:AddChild(LM.GUI.StaticText("y el script detecta qué cambiaste y lo copia a los demás fotogramas."), LM.GUI.ALIGN_LEFT, 0)
	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL, 0)
	d.cWin   = LM.GUI.CheckBox("Tomar el estilo de la ventana Style en vez del dibujo de referencia", 0)
	l:AddChild(d.cWin, LM.GUI.ALIGN_LEFT, 0)
	d.cForce = LM.GUI.CheckBox("Copiar todo lo marcado aunque no detecte diferencias", 0)
	l:AddChild(d.cForce, LM.GUI.ALIGN_LEFT, 0)
	d.fRef   = field("Fotograma de referencia:")
	d.fStart = field("Aplicar desde el fotograma:")
	d.fEnd   = field("Aplicar hasta el fotograma:")
	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL, 0)
	l:AddChild(LM.GUI.StaticText("Qué cambios propagar:"), LM.GUI.ALIGN_LEFT, 0)
	d.cBrush  = LM.GUI.CheckBox("Pincel (nombre del pincel)", 0)
	l:AddChild(d.cBrush, LM.GUI.ALIGN_LEFT, 0)
	d.cParams = LM.GUI.CheckBox("Parámetros del pincel (espaciado, variación, deriva de color...)", 0)
	l:AddChild(d.cParams, LM.GUI.ALIGN_LEFT, 0)
	d.cWidth  = LM.GUI.CheckBox("Grosor de línea", 0)
	l:AddChild(d.cWidth, LM.GUI.ALIGN_LEFT, 0)
	d.cColor  = LM.GUI.CheckBox("Color de línea", 0)
	l:AddChild(d.cColor, LM.GUI.ALIGN_LEFT, 0)
	d.cCaps   = LM.GUI.CheckBox("Extremos de línea (redondeados / sin)", 0)
	l:AddChild(d.cCaps, LM.GUI.ALIGN_LEFT, 0)
	return d
end

function AL_Dialog:UpdateWidgets()
	local f = 1
	pcall(function() f = self.moho.frame end)
	self.cWin:SetValue(false)
	self.cForce:SetValue(false)
	self.fRef:SetValue(f)
	self.fStart:SetValue(0)
	self.fEnd:SetValue(100000)
	self.cBrush:SetValue(true)
	self.cParams:SetValue(true)
	self.cWidth:SetValue(true)
	self.cColor:SetValue(true)
	self.cCaps:SetValue(true)
end

function AL_Dialog:OnOK() end

-- ==============================================================
-- Ejecución
-- ==============================================================

function AL_PropagarEstilo:Run(moho)
	local dlg = AL_Dialog:new(moho)
	if dlg:DoModal() == LM.GUI.MSG_CANCEL then return end
	local o = {
		useStyleWindow = dlg.cWin:Value(),
		force       = dlg.cForce:Value(),
		refFrame    = floor(dlg.fRef:FloatValue() + 0.5),
		startFrame  = floor(dlg.fStart:FloatValue() + 0.5),
		endFrame    = floor(dlg.fEnd:FloatValue() + 0.5),
	}
	o.brush, o.params = dlg.cBrush:Value(), dlg.cParams:Value()
	o.width, o.color, o.caps = dlg.cWidth:Value(), dlg.cColor:Value(), dlg.cCaps:Value()
	if not (o.brush or o.params or o.width or o.color or o.caps) then
		alert("Propagar estilo", "No marcaste ningún cambio para propagar.")
		return
	end
	local ok, nLayers, nShapes, skipped, failed, report, refName = pcall(Propagate, moho, o)
	if not ok then
		local err = tostring(nLayers):gsub("^.-:%d+: ", "")
		alert("Propagar estilo - error", err)
		return
	end
	if #report == 0 then
		alert("Propagar estilo",
			"No detecté diferencias entre el dibujo de referencia ('" .. tostring(refName) .. "') y los demás.\n\n" ..
			"Si cambiaste solo ALGUNOS trazos, los demás siguen igual y cuentan como 'sin cambio':\n" ..
			"selecciona todos los trazos del fotograma al hacer el cambio.\n" ..
			"O marca 'Copiar todo lo marcado aunque no detecte diferencias'.")
		return
	end
	local msg = string.format("Listo. Referencia: dibujo '%s'.\nDibujos actualizados: %d  |  Trazos: %d\n\nCambios propagados:\n%s",
		tostring(refName), nLayers, nShapes, table.concat(report, "\n"))
	if skipped > 0 then msg = msg .. "\nDibujos omitidos (no vectoriales): " .. skipped end
	local bad = {}
	for k in pairs(failed) do bad[#bad + 1] = k end
	if #bad > 0 then
		table.sort(bad)
		msg = msg .. "\nNo se pudo copiar: " .. table.concat(bad, ", ")
	end
	alert("Propagar estilo", msg)
end

return AL_PropagarEstilo
end
local TOOL_prop = make_prop()

-- ##############################################################
-- PANEL PRINCIPAL: tres botones para elegir herramienta
-- ##############################################################

local Launcher = {}
Launcher.PICK_AUTO   = MOHO.MSG_BASE + 1
Launcher.PICK_IMPORT = MOHO.MSG_BASE + 2
Launcher.PICK_PROP   = MOHO.MSG_BASE + 3

local LABELS = {
	auto   = "Auto Lineart (contorno de una capa)",
	import = "Importar Line Art de Blender",
	prop   = "Propagar estilo a todos los fotogramas del Switch",
}

function Launcher:new(moho)
	local d = LM.GUI.SimpleDialog("Grease Pencil Tool", Launcher)
	local l = d:GetLayout()
	d.moho = moho
	d.choice = nil
	d.importPath = nil
	l:AddChild(LM.GUI.StaticText("Elige la herramienta que quieres usar y pulsa OK:"), LM.GUI.ALIGN_LEFT, 0)
	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL, 0)
	d.bAuto   = LM.GUI.Button(LABELS.auto, self.PICK_AUTO)
	d.bImport = LM.GUI.Button(LABELS.import, self.PICK_IMPORT)
	d.bProp   = LM.GUI.Button(LABELS.prop, self.PICK_PROP)
	l:AddChild(d.bAuto, LM.GUI.ALIGN_FILL, 0)
	l:AddChild(d.bImport, LM.GUI.ALIGN_FILL, 0)
	l:AddChild(d.bProp, LM.GUI.ALIGN_FILL, 0)
	return d
end

function Launcher:UpdateWidgets() end

-- Marca con ">>" el botón elegido
local function markChoice(d)
	pcall(function() d.bAuto:SetLabel((d.choice == "auto" and ">> " or "") .. LABELS.auto) end)
	pcall(function() d.bImport:SetLabel((d.choice == "import" and ">> " or "") .. LABELS.import) end)
	pcall(function() d.bProp:SetLabel((d.choice == "prop" and ">> " or "") .. LABELS.prop) end)
end

function Launcher:HandleMessage(what)
	if what == self.PICK_AUTO then
		self.choice = "auto"
	elseif what == self.PICK_PROP then
		self.choice = "prop"
	elseif what == self.PICK_IMPORT then
		-- El selector de archivos se abre aquí, DENTRO del panel (como el botón "Browse" de BVH
		-- Bones): abrirlo después de cerrar un panel propio cerraba Moho.
		local f = LM.GUI.OpenFile("Elige el archivo .lineart exportado desde Blender")
		f = tostring(f or "")
		f = f:gsub('^%s*"?', ""):gsub('"?%s*$', "")
		if f ~= "" then
			self.choice = "import"
			self.importPath = f
		end
	end
	markChoice(self)
end

function Launcher:OnOK() end

function GreasePencilTool:Run(moho)
	local dlg = Launcher:new(moho)
	if dlg:DoModal() == LM.GUI.MSG_CANCEL then return end
	local c = dlg.choice
	if c == "auto" then
		TOOL_auto:Run(moho)
	elseif c == "import" then
		TOOL_imp:Run(moho, dlg.importPath)
	elseif c == "prop" then
		TOOL_prop:Run(moho)
	else
		pcall(function()
			LM.GUI.Alert(LM.GUI.ALERT_INFO, "Grease Pencil Tool",
				"No elegiste ninguna herramienta. Pulsa uno de los tres botones antes de OK.", nil, "OK", nil, nil)
		end)
	end
end
