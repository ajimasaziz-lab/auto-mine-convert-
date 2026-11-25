--[[ AUTO MINE v3 (rekonstruksi dari AUTO CHOP v17: nambang Ore, tombol & alur sama dengan nebang)
     v2: penomoran ore tetap per lokasi (tahan respawn), tidak ngulang dari 1 saat scan ulang
     v3: - scan ulang otomatis tiap 20 detik (bisa diubah di menu), ore yang dilewati dicoba lagi setelah 20 detik
         - titik koordinat bisa lebih dari 1 (TAMBAH TITIK), hapus 1 titik / hapus semua
         - wilayah scan ditampilkan sebagai dinding kuning transparan di pinggir lingkaran;
           lingkaran yang saling bertemu digabung (dinding di bagian yang tumpang tindih dihilangkan)
         - perbaikan: spam print dihapus, loop ganda saat START/STOP cepat dicegah, memori ore lama dibersihkan,
           error di loop utama tidak lagi membuat script macet diam-diam ]]--

local CONFIG = {
    ORE_KEYWORDS      = {"ore"},  -- nama model/part ore mengandung salah satu kata ini (mis. "Iron Ore", "CopperOre")
    ORE_IGNORE_WORDS  = {"more", "core", "store", "explore", "restore", "score", "spore", "ignore", "before", "bore", "shore", "wore", "sore", "snore"}, -- nama berisi kata ini BUKAN ore
    MINE_KEY          = Enum.KeyCode.F,
    MINE_DISTANCE     = 7,
    REACH_TIMEOUT     = 30,     -- detik: batas waktu menggapai tombol Mine (mendekat + memutari ore), lewat = ore dilewati (bisa diubah di menu)
    AFTER_MINE_DELAY  = 1,      -- detik: jeda setelah menambang selesai sebelum ambil hasil (bisa diubah di menu)
    ACTION_WORDS      = {"mine", "mining"}, -- teks tombol aksi (muncul saat dekat ore). Tombol yang mengandung "stop" TIDAK dihitung
    STOP_TEXT         = "stop mining", -- teks tombol yang muncul selama menambang (tidak peka huruf besar/kecil)
    START_GRACE       = 3,      -- detik: tunggu tombol "Stop Mining" muncul setelah F ditekan
    START_RETRIES     = 2,      -- berapa kali F ditekan ulang kalau tombol "Stop Mining" tidak muncul
    SAFETY_MAX_MINE   = 120,    -- detik: batas pengaman kalau tombol "Stop Mining" tidak pernah hilang
    PICKUP_ENABLED    = true,   -- tekan F 1 kali setelah menambang untuk mengambil hasil yang jatuh
    PICKUP_TEXT       = "picked up", -- teks notifikasi ambil item (tidak peka huruf besar/kecil)

    -- penghitung item
    COUNT_ITEM_NAME       = "Gold Veined Quartz", -- hanya item ini yang dihitung (tidak peka huruf besar/kecil)
    COUNT_REQUIRE_PICKUP  = true,   -- true = teks harus mengandung PICKUP_TEXT juga; false = cukup ada nama item
    COUNT_PARSE_QTY       = true,   -- baca jumlah dari teks (mis. "x3" atau "3x"); kalau tidak ada dihitung 1
    DEFAULT_RADIUS    = 300,    -- radius (stud) tiap titik koordinat
    RESCAN_INTERVAL   = 20,     -- detik: scan ulang otomatis selama berjalan (bisa diubah di menu)
    DONE_EXPIRE       = 20,     -- detik: ore yang dilewati (tidak terjangkau/gagal) tidak dipilih lagi selama ini
    MINED_EXPIRE      = 15,     -- detik: ore yang berhasil ditambang boleh dipilih lagi (kalau respawn)
    USE_PATHFINDING   = true,

    -- penomoran tetap per lokasi
    SLOT_TOLERANCE    = 3,      -- stud: ore baru sedekat ini dari lokasi ore lama = memakai nomor lama (naikkan, mis. 6, kalau ore bergeser saat respawn)

    -- titik koordinat & tampilan zona
    POINT_MIN_GAP      = 2,     -- stud: titik baru sedekat ini dengan titik lama ditolak (duplikat)
    ZONE_COLOR         = Color3.fromRGB(255, 215, 0), -- kuning
    ZONE_TRANSPARENCY  = 0.65,  -- 0 = padat, 1 = tak terlihat
    ZONE_WALL_HEIGHT   = 10,    -- stud: tinggi dinding zona
    ZONE_WALL_THICK    = 0.4,   -- stud: tebal dinding zona
    ZONE_SEGMENT_LEN   = 6,     -- stud: panjang tiap potongan dinding (makin kecil makin halus)
    ZONE_MAX_SEGMENTS  = 240,   -- batas potongan per lingkaran

    -- kalkulasi rute: hitung rute ke ore DULU, baru bergerak (mengurangi nyangkut)
    ROUTE_ENABLED     = true,   -- false = langsung jalan tanpa hitung rute dulu
    ROUTE_DRAW        = true,   -- tampilkan garis rute
    ROUTE_COLOR       = Color3.fromRGB(0, 255, 90), -- warna garis rute (hijau)
    ROUTE_MAX_TRIES   = 3,      -- berapa kali rute dihitung ulang kalau gagal/nyangkut di tengah jalan
    ROUTE_RING_RADIUS = 4,      -- stud: kalau titik ore tidak bisa dijangkau, coba titik di sekeliling ore pada jarak ini
    ROUTE_RING_POINTS = 8,      -- jumlah titik alternatif di sekeliling ore
    ROUTE_MAX_TIME    = 25,     -- detik: batas waktu mengikuti satu rute

    -- filter batas tak terlihat
    WALL_CHECK        = true,
    WALL_MIN_SIZE     = 15,
    WALL_TRANSPARENCY = 0.9,
    WALL_NAMES        = {"wall", "barrier", "boundary", "border", "invisible", "limit"},

    -- deteksi ore yang sedang/sudah ditambang player lain
    OTHER_CHECK        = true,
    OTHER_EXPIRE       = 15,
    OTHER_ATTR_CHECK   = true,
    OTHER_ATTR_WORDS   = {"mining", "beingmined", "minedby", "busy", "occupied", "inuse", "in_use", "lockedby", "taken", "user"},
    OTHER_NEAR_DIST    = 7,     -- stud: player lain dianggap sedang di ore ini kalau berdiri sedekat ini
    OTHER_MAX_SPEED    = 3,     -- player lain harus hampir diam (stud/detik)
    OTHER_REQUIRE_ANIM = false, -- true = harus ada animasi bernama OTHER_ANIM_WORDS
    OTHER_ANIM_WORDS   = {"mine", "mining", "pickaxe", "swing", "dig", "hit"},
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local lp = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
if env.__AutoMineStop then pcall(env.__AutoMineStop) end

local running = false
local runToken = 0
local loopActive = false
local scanning = false
local pendingScan = false
local needRescan = false
local lastScanAt = 0
local mode = "map"                   -- "map" = seluruh map | "coord" = di titik-titik koordinat
local radius = CONFIG.DEFAULT_RADIUS
local reachTimeout = CONFIG.REACH_TIMEOUT
local afterMineDelay = CONFIG.AFTER_MINE_DELAY
local rescanInterval = CONFIG.RESCAN_INTERVAL
local coordPoints = {}               -- { {pos = Vector3}, ... }
local zoneFolder = nil
local patrolIdx = 0
local minedCount = 0

local oreId, nextId = {}, 1
local oreSlots = {}                  -- {pos, id}: nomor tetap per lokasi ore (tahan respawn)
local oreH0, doneOres = {}, {}
local excluded = {}
local areaOres, ores = {}, {}
local oreMarks = {}
local camByUs = false
local connections = {}

-- deteksi player lain
local knownOres, orePos = {}, {}
local trunkCache = {}
local takenMap, takenAt = {}, 0
local attrIgnore = false
local currentOre = nil
local otherPosOn = true

for _, o in ipairs(Workspace:GetChildren()) do
    if o.Name == "AutoMine_CoordMarker" or o.Name == "AutoMine_RouteMarker" then o:Destroy() end
end

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------
local parent = (gethui and gethui()) or game:GetService("CoreGui")
local old = parent:FindFirstChild("AutoMineGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoMineGui"
gui.ResetOnSpawn = false
gui.Parent = parent

local COLORS = {
    bg     = Color3.fromRGB(24, 26, 33),
    bar    = Color3.fromRGB(35, 38, 48),
    field  = Color3.fromRGB(55, 58, 72),
    text   = Color3.fromRGB(235, 235, 240),
    muted  = Color3.fromRGB(170, 175, 190),
    green  = Color3.fromRGB(46, 160, 80),
    red    = Color3.fromRGB(190, 55, 55),
    orange = Color3.fromRGB(200, 120, 40),
    blue   = Color3.fromRGB(55, 105, 190),
    purple = Color3.fromRGB(110, 80, 190),
    accent = Color3.fromRGB(70, 200, 120),
}

local WIDTH, BAR_H, BODY_H = 260, 34, 510
-- tinggi area menu yang terlihat (bisa di-scroll kalau layar pendek, mis. HP)
local BODY_VIEW = BODY_H
do
    local cam = Workspace.CurrentCamera
    if cam then
        BODY_VIEW = math.clamp(math.floor(cam.ViewportSize.Y - BAR_H - 80), 200, BODY_H)
    end
end

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.new(0, WIDTH, 0, BAR_H + BODY_VIEW)
frame.Position = UDim2.new(0, 20, 0, 60)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
do
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
    local s = Instance.new("UIStroke", frame)
    s.Color = Color3.fromRGB(70, 75, 95)
    s.Thickness = 1
end

local titleBar = Instance.new("Frame", frame)
titleBar.Size = UDim2.new(1, 0, 0, BAR_H)
titleBar.BackgroundColor3 = COLORS.bar
titleBar.BorderSizePixel = 0
titleBar.Active = true

local title = Instance.new("TextLabel", titleBar)
title.Size = UDim2.new(1, -140, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = CONFIG.COUNT_ITEM_NAME .. ": 0"
title.TextScaled = true
do
    local c = Instance.new("UITextSizeConstraint", title)
    c.MaxTextSize = 12
    c.MinTextSize = 7
end
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left

local function barBtn(text, xOff, color)
    local b = Instance.new("TextButton", titleBar)
    b.Size = UDim2.new(0, 26, 0, 22)
    b.Position = UDim2.new(1, xOff, 0.5, -11)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.Text = text
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end
local minBtn   = barBtn("–", -64, Color3.fromRGB(80, 85, 100))
local closeBtn = barBtn("×", -34, COLORS.red)

local miniBtn = Instance.new("TextButton", titleBar)
miniBtn.Size = UDim2.new(0, 54, 0, 22)
miniBtn.Position = UDim2.new(1, -124, 0.5, -11)
miniBtn.BackgroundColor3 = COLORS.green
miniBtn.TextColor3 = Color3.new(1, 1, 1)
miniBtn.Font = Enum.Font.GothamBold
miniBtn.TextSize = 11
miniBtn.Text = "START"
Instance.new("UICorner", miniBtn).CornerRadius = UDim.new(0, 6)

local body = Instance.new("ScrollingFrame", frame)
body.Size = UDim2.new(1, 0, 0, BODY_VIEW)
body.Position = UDim2.new(0, 0, 0, BAR_H)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.CanvasSize = UDim2.new(0, 0, 0, BODY_H)
body.ScrollBarThickness = 4
body.ScrollingDirection = Enum.ScrollingDirection.Y

local function mkBtnAt(text, x, y, w, color)
    local b = Instance.new("TextButton", body)
    b.Size = w and UDim2.new(0, w, 0, 30) or UDim2.new(1, -20, 0, 30)
    b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.TextWrapped = true
    b.Text = text
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end
local function mkBtn(text, y, color) return mkBtnAt(text, 10, y, nil, color) end

local function mkLabel(text, y)
    local l = Instance.new("TextLabel", body)
    l.Size = UDim2.new(0, 170, 0, 20)
    l.Position = UDim2.new(0, 12, 0, y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = COLORS.muted
    l.Font = Enum.Font.Gotham
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    return l
end

local function mkBox(y, text)
    local b = Instance.new("TextBox", body)
    b.Size = UDim2.new(0, 64, 0, 26)
    b.Position = UDim2.new(1, -76, 0, y)
    b.Text = tostring(text)
    b.BackgroundColor3 = COLORS.field
    b.TextColor3 = COLORS.text
    b.Font = Enum.Font.Gotham
    b.TextSize = 13
    b.ClearTextOnFocus = false
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local startBtn  = mkBtn("START", 8, COLORS.green)
local coordBtn  = mkBtn("TAMBAH TITIK (posisi saya) [0]", 44, COLORS.purple)

-- baris hapus titik: [no.] [HAPUS 1 TITIK] [HAPUS SEMUA]
local delBox = Instance.new("TextBox", body)
delBox.Size = UDim2.new(0, 46, 0, 30)
delBox.Position = UDim2.new(0, 10, 0, 80)
delBox.Text = ""
delBox.PlaceholderText = "no."
delBox.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
delBox.BackgroundColor3 = COLORS.field
delBox.TextColor3 = COLORS.text
delBox.Font = Enum.Font.Gotham
delBox.TextSize = 13
delBox.ClearTextOnFocus = false
Instance.new("UICorner", delBox).CornerRadius = UDim.new(0, 6)
local delOneBtn = mkBtnAt("HAPUS 1 TITIK", 62, 80, 91, COLORS.orange)
local delAllBtn = mkBtnAt("HAPUS SEMUA", 159, 80, 91, COLORS.red)
delOneBtn.TextSize = 11
delAllBtn.TextSize = 11

local mapBtn    = mkBtn("TANDAI SELURUH MAP", 116, COLORS.field)
local nearBtn   = mkBtn("TANDAI DI TITIK KOORDINAT", 152, COLORS.field)

local function setRunUI(on)
    local txt = on and "STOP" or "START"
    local col = on and COLORS.red or COLORS.green
    startBtn.Text = txt
    startBtn.BackgroundColor3 = col
    miniBtn.Text = txt
    miniBtn.BackgroundColor3 = col
end

mkLabel("Radius tiap titik (stud):", 192)
local radiusBox = mkBox(189, radius)
mkLabel("Batas raih Mine (detik):", 224)
local reachBox = mkBox(221, reachTimeout)
mkLabel("Jeda setelah tambang (detik):", 256)
local mineBox = mkBox(253, afterMineDelay)
mkLabel("Scan ulang tiap (detik):", 288)
local rescanBox = mkBox(285, rescanInterval)

mkLabel("Kecualikan no. ore:", 320)
local exBox = Instance.new("TextBox", body)
exBox.Size = UDim2.new(1, -20, 0, 28)
exBox.Position = UDim2.new(0, 10, 0, 342)
exBox.Text = ""
exBox.PlaceholderText = "contoh: 3, 7, 10-15"
exBox.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
exBox.BackgroundColor3 = COLORS.field
exBox.TextColor3 = COLORS.text
exBox.Font = Enum.Font.Gotham
exBox.TextSize = 13
exBox.ClearTextOnFocus = false
Instance.new("UICorner", exBox).CornerRadius = UDim.new(0, 6)

local posBtn = mkBtn("DETEKSI POSISI PLAYER: ON", 378, COLORS.accent)
posBtn.TextColor3 = Color3.fromRGB(10, 30, 15)

local statusBox = Instance.new("Frame", body)
statusBox.Size = UDim2.new(1, -20, 0, 84)
statusBox.Position = UDim2.new(0, 10, 0, 416)
statusBox.BackgroundColor3 = COLORS.bar
statusBox.BorderSizePixel = 0
Instance.new("UICorner", statusBox).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel", statusBox)
status.Size = UDim2.new(1, -16, 1, -8)
status.Position = UDim2.new(0, 8, 0, 4)
status.BackgroundTransparency = 1
status.Text = "Status: pilih mode penandaan ore (seluruh map / titik koordinat)."
status.TextColor3 = COLORS.muted
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top

local function setStatus(t) status.Text = "Status: " .. t end

local function updateCounter()
    title.Text = ("%s: %d"):format(CONFIG.COUNT_ITEM_NAME, minedCount)
end
updateCounter()

-- hitung otomatis tiap muncul teks "picked up ..." di PlayerGui
do
    local itemLower = CONFIG.COUNT_ITEM_NAME:lower()
    local function textMatches(o)
        if o.Text == "" then return false end
        local t = o.Text:lower()
        if not t:find(itemLower, 1, true) then return false end
        if CONFIG.COUNT_REQUIRE_PICKUP and not t:find(CONFIG.PICKUP_TEXT, 1, true) then return false end
        return true
    end

    -- jumlah item dari teks: "x3" / "3x" / "x 3"; default 1
    local function qtyOf(o)
        if not CONFIG.COUNT_PARSE_QTY then return 1 end
        local t = o.Text:lower()
        local n = t:match("x%s*(%d+)") or t:match("(%d+)%s*x")
        n = n and tonumber(n)
        if n and n >= 1 and n <= 9999 then return n end
        return 1
    end

    local lastCount = setmetatable({}, {__mode = "k"})
    local function countPickup(o)
        local now = os.clock()
        if lastCount[o] and now - lastCount[o] < 0.3 then return end
        lastCount[o] = now
        minedCount = minedCount + qtyOf(o)
        updateCounter()
    end

    local hooked = setmetatable({}, {__mode = "k"})
    local function hook(o, initial)
        if hooked[o] then return end
        if not (o:IsA("TextLabel") or o:IsA("TextButton")) then return end
        hooked[o] = true
        if not initial and textMatches(o) then countPickup(o) end
        o:GetPropertyChangedSignal("Text"):Connect(function()
            if gui.Parent and textMatches(o) then countPickup(o) end
        end)
        o:GetPropertyChangedSignal("Visible"):Connect(function()
            if gui.Parent and o.Visible and textMatches(o) then countPickup(o) end
        end)
    end

    task.spawn(function()
        local pg = lp:WaitForChild("PlayerGui")
        for _, d in ipairs(pg:GetDescendants()) do hook(d, true) end
        table.insert(connections, pg.DescendantAdded:Connect(function(d) hook(d, false) end))
    end)
end

local function refreshModeButtons()
    local on, off = COLORS.accent, COLORS.field
    mapBtn.BackgroundColor3  = (mode == "map") and on or off
    mapBtn.TextColor3        = (mode == "map") and Color3.fromRGB(10, 30, 15) or Color3.new(1, 1, 1)
    nearBtn.BackgroundColor3 = (mode == "coord") and on or off
    nearBtn.TextColor3       = (mode == "coord") and Color3.fromRGB(10, 30, 15) or Color3.new(1, 1, 1)
end
refreshModeButtons()

-- drag lewat title bar (mouse & touch)
do
    local dragging, dragStart, startPos
    table.insert(connections, titleBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, frame.Position
        end
    end))
    table.insert(connections, UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    table.insert(connections, UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    minBtn.Text = minimized and "+" or "–"
    local h = minimized and BAR_H or (BAR_H + BODY_VIEW)
    TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {Size = UDim2.new(0, WIDTH, 0, h)}):Play()
end)

----------------------------------------------------------------
-- Util umum
----------------------------------------------------------------
local function flatDist(a, b)
    return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function root()
    local c = lp.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function camera() return Workspace.CurrentCamera end

local function key(k, down) VIM:SendKeyEvent(down, k, false, game) end
local function tap(k, t) key(k, true) task.wait(t or 0.05) key(k, false) end

local function releaseAll()
    for _, k in ipairs({Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D}) do key(k, false) end
end

local function posOf(inst)
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then return inst:GetPivot().Position end
end

local function boundsOf(inst)
    if inst:IsA("Model") then return inst:GetBoundingBox() end
    return inst.CFrame, inst.Size
end

local function guiShown(g, stop)
    local o = g
    while o and o ~= stop do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("LayerCollector") and not o.Enabled then return false end
        o = o.Parent
    end
    return true
end

local function nameHas(n, words)
    n = n:lower()
    for _, w in ipairs(words) do
        if n:find(w, 1, true) then return true end
    end
    return false
end

----------------------------------------------------------------
-- Titik koordinat & zona (dinding kuning, lingkaran yang bertemu digabung)
----------------------------------------------------------------
-- kelompokkan titik yang lingkarannya saling bertemu (jarak antar pusat <= 2 x radius)
local function pointGroups()
    local n = #coordPoints
    local par = {}
    for i = 1, n do par[i] = i end
    local function find(i)
        while par[i] ~= i do
            par[i] = par[par[i]]
            i = par[i]
        end
        return i
    end
    for i = 1, n do
        for j = i + 1, n do
            if flatDist(coordPoints[i].pos, coordPoints[j].pos) <= radius * 2 then
                local a, b = find(i), find(j)
                if a ~= b then par[b] = a end
            end
        end
    end
    local groupOf, groups, idx = {}, {}, {}
    for i = 1, n do
        local r = find(i)
        if not idx[r] then
            table.insert(groups, {})
            idx[r] = #groups
        end
        groupOf[i] = idx[r]
        table.insert(groups[idx[r]], i)
    end
    return groupOf, groups
end

local function clearCoordMarker()
    if zoneFolder then
        pcall(function() zoneFolder:Destroy() end)
        zoneFolder = nil
    end
end

local function drawCoordMarker()
    clearCoordMarker()
    if #coordPoints == 0 then return end

    zoneFolder = Instance.new("Folder")
    zoneFolder.Name = "AutoMine_CoordMarker"
    zoneFolder.Parent = Workspace

    local col = CONFIG.ZONE_COLOR
    local H = CONFIG.ZONE_WALL_HEIGHT
    local function mkPart(size, shape)
        local p = Instance.new("Part")
        p.Name = "AutoMine_CoordMarker"
        p.Shape = shape or Enum.PartType.Block
        p.Size = size
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.CastShadow = false
        p.Material = Enum.Material.SmoothPlastic
        p.Color = col
        p.Transparency = CONFIG.ZONE_TRANSPARENCY
        p.Parent = zoneFolder
        return p
    end

    local groupOf, groups = pointGroups()
    local segs = math.clamp(math.floor(2 * math.pi * radius / CONFIG.ZONE_SEGMENT_LEN), 24, CONFIG.ZONE_MAX_SEGMENTS)

    for i, pt in ipairs(coordPoints) do
        local c = pt.pos

        -- bola penanda titik + label
        local ball = mkPart(Vector3.new(2, 2, 2), Enum.PartType.Ball)
        ball.Material = Enum.Material.Neon
        ball.Transparency = 0.2
        ball.Position = c

        local g = groups[groupOf[i]]
        local txt = ("TITIK %d"):format(i)
        if #g > 1 then
            local names = {}
            for _, k in ipairs(g) do table.insert(names, tostring(k)) end
            txt = txt .. " (gabung " .. table.concat(names, "+") .. ")"
        end
        local bb = Instance.new("BillboardGui", ball)
        bb.Size = UDim2.new(0, 160, 0, 22)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        local tl = Instance.new("TextLabel", bb)
        tl.Size = UDim2.new(1, 0, 1, 0)
        tl.BackgroundTransparency = 1
        tl.Text = txt
        tl.TextColor3 = col
        tl.TextStrokeTransparency = 0.3
        tl.Font = Enum.Font.GothamBold
        tl.TextSize = 14

        -- dinding di pinggir lingkaran; potongan yang berada di dalam lingkaran titik lain dilewati (= digabung)
        local midY = (c.Y - 3) + H / 2
        for k = 0, segs - 1 do
            local a0 = k * 2 * math.pi / segs
            local a1 = (k + 1) * 2 * math.pi / segs
            local p0 = Vector3.new(c.X + math.cos(a0) * radius, midY, c.Z + math.sin(a0) * radius)
            local p1 = Vector3.new(c.X + math.cos(a1) * radius, midY, c.Z + math.sin(a1) * radius)
            local mid = (p0 + p1) / 2
            local inside = false
            for j, o in ipairs(coordPoints) do
                if j ~= i and flatDist(mid, o.pos) < radius - 0.05 then
                    inside = true
                    break
                end
            end
            if not inside then
                local len = (p1 - p0).Magnitude + 0.15
                local w = mkPart(Vector3.new(CONFIG.ZONE_WALL_THICK, H, len))
                w.CFrame = CFrame.lookAt(mid, mid + (p1 - p0))
            end
        end
    end
end

-- titik terdekat yang lingkarannya memuat posisi p (nil kalau di luar semua lingkaran)
local function pointCovering(p)
    local best, bd
    for _, pt in ipairs(coordPoints) do
        local d = flatDist(p, pt.pos)
        if d <= radius and (not bd or d < bd) then best, bd = pt.pos, d end
    end
    return best
end

local function areaCount()
    if #coordPoints == 0 then return 0 end
    local _, groups = pointGroups()
    return #groups
end

----------------------------------------------------------------
-- Ore: deteksi, penomoran, marker, pengecualian
----------------------------------------------------------------
local function isOreName(i)
    if not (i:IsA("Model") or i:IsA("BasePart")) then return false end
    local n = i.Name:lower()
    -- buang kata yang kebetulan mengandung "ore" (more, core, store, ...)
    local cleaned = n
    for _, w in ipairs(CONFIG.ORE_IGNORE_WORDS) do
        cleaned = cleaned:gsub(w, "")
    end
    for _, k in ipairs(CONFIG.ORE_KEYWORDS) do
        if cleaned:find(k, 1, true) then return true end
    end
    return false
end

local function isGroup(m)
    return m:IsA("Model") and not m:FindFirstChildWhichIsA("BasePart")
end

local function hasOreAncestor(d)
    local p = d.Parent
    while p and p ~= Workspace do
        if isOreName(p) and not isGroup(p) then return true end
        p = p.Parent
    end
    return false
end

local function oreHeight(t)
    if t:IsA("Model") then return t:GetExtentsSize().Y end
    return t.Size.Y
end

local function oreVisible(t)
    if t:IsA("BasePart") and t.Transparency < 0.9 then return true end
    for _, p in ipairs(t:GetDescendants()) do
        if p:IsA("BasePart") and p.Transparency < 0.9 then return true end
    end
    return false
end

-- ore dianggap habis kalau: hilang dari workspace, tak terlihat, atau jauh lebih kecil
local function isMined(ore)
    if not ore.Parent or not ore:IsDescendantOf(Workspace) then return true end
    if not oreVisible(ore) then return true end
    local h0 = oreH0[ore]
    if h0 and h0 > 0 and oreHeight(ore) < h0 * 0.5 then return true end
    return false
end

local function isExcluded(t)
    local id = oreId[t]
    return id ~= nil and excluded[id] == true
end

----------------------------------------------------------------
-- Deteksi ore yang sedang/sudah ditambang player lain
----------------------------------------------------------------
local function foreignValue(v)
    local tv = typeof(v)
    if tv == "boolean" then return v end
    if tv == "string" then
        return v ~= "" and v ~= lp.Name and v ~= lp.DisplayName and v ~= tostring(lp.UserId)
    end
    if tv == "number" then return v ~= 0 and v ~= lp.UserId end
    if tv == "Instance" then return v ~= lp and v ~= lp.Character end
    return false
end

local function attrTaken(ore)
    if not CONFIG.OTHER_ATTR_CHECK or attrIgnore then return false end
    for k, v in pairs(ore:GetAttributes()) do
        if nameHas(k, CONFIG.OTHER_ATTR_WORDS) and foreignValue(v) then return true end
    end
    for _, c in ipairs(ore:GetChildren()) do
        if c:IsA("ValueBase") and nameHas(c.Name, CONFIG.OTHER_ATTR_WORDS) then
            local ok, v = pcall(function() return c.Value end)
            if ok and foreignValue(v) then return true end
        end
    end
    return false
end

local function otherLooksMining(char, hrp)
    if hrp.AssemblyLinearVelocity.Magnitude > CONFIG.OTHER_MAX_SPEED then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return false end
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
        if ok then
            for _, tr in ipairs(tracks) do
                if nameHas(tr.Name, CONFIG.OTHER_ANIM_WORDS) then return true end
            end
        end
    end
    return not CONFIG.OTHER_REQUIRE_ANIM
end

local function trunkRadius(t)
    local r = trunkCache[t]
    if r then return r end
    local ok, _, size = pcall(boundsOf, t)
    r = 2
    if ok and size then r = math.min(math.max(size.X, size.Z) / 2, 4) end
    trunkCache[t] = r
    return r
end

local function refreshTaken(force)
    local now = os.clock()
    if not force and now - takenAt < 0.5 then return end
    takenAt = now
    local map = {}
    if CONFIG.OTHER_CHECK and otherPosOn then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lp then
                local ch = plr.Character
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                if hrp and otherLooksMining(ch, hrp) then
                    local hp = hrp.Position
                    local best, bd
                    for _, t in ipairs(knownOres) do
                        local p = orePos[t]
                        if p and t.Parent then
                            local d = flatDist(p, hp)
                            if not bd or d < bd then best, bd = t, d end
                        end
                    end
                    if best and bd <= CONFIG.OTHER_NEAR_DIST + trunkRadius(best) then
                        map[best] = true
                    end
                end
            end
        end
    end
    takenMap = map
end

local function isTaken(ore)
    if not CONFIG.OTHER_CHECK then return false end
    if ore == currentOre then return false end
    refreshTaken(false)
    return takenMap[ore] == true or attrTaken(ore)
end

----------------------------------------------------------------
-- Marker
----------------------------------------------------------------
-- kotak merah + label nomor (oranye "X" bila dikecualikan, biru "P" bila dipakai player lain)
local function ensureMark(t)
    local m = oreMarks[t]
    if not m then
        local box = Instance.new("SelectionBox")
        box.Adornee = t
        box.Color3 = Color3.fromRGB(255, 0, 0)
        box.SurfaceColor3 = Color3.fromRGB(255, 0, 0)
        box.SurfaceTransparency = 0.7
        box.LineThickness = 0.06
        box.Parent = gui

        local bb, label
        local part = t:IsA("BasePart") and t or t.PrimaryPart or t:FindFirstChildWhichIsA("BasePart", true)
        if part then
            local cf, size = boundsOf(t)
            bb = Instance.new("BillboardGui")
            bb.Adornee = part
            bb.Size = UDim2.new(0, 60, 0, 22)
            bb.AlwaysOnTop = true
            bb.StudsOffsetWorldSpace = Vector3.new(0, (cf.Position.Y + size.Y / 2) - part.Position.Y + 2, 0)
            bb.Parent = gui

            label = Instance.new("TextLabel", bb)
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
            label.BackgroundTransparency = 0.25
            label.Font = Enum.Font.GothamBold
            label.TextSize = 14
            Instance.new("UICorner", label).CornerRadius = UDim.new(0, 6)
        end
        m = {box = box, bb = bb, label = label}
        oreMarks[t] = m
    end

    local ex = isExcluded(t)
    local tk = (not ex) and isTaken(t)
    m.box.Visible = not ex
    m.box.Color3 = tk and Color3.fromRGB(80, 160, 255) or Color3.fromRGB(255, 0, 0)
    m.box.SurfaceColor3 = m.box.Color3
    if m.label then
        local id = oreId[t] or 0
        if ex then
            m.label.Text = ("#%d X"):format(id)
            m.label.TextColor3 = Color3.fromRGB(255, 170, 60)
        elseif tk then
            m.label.Text = ("#%d P"):format(id)
            m.label.TextColor3 = Color3.fromRGB(120, 180, 255)
        else
            m.label.Text = ("#%d"):format(id)
            m.label.TextColor3 = Color3.new(1, 1, 1)
        end
    end
end

local function removeMark(t)
    local m = oreMarks[t]
    if m then
        m.box:Destroy()
        if m.bb then m.bb:Destroy() end
        oreMarks[t] = nil
    end
end

local function clearOreMarks()
    for t in pairs(oreMarks) do removeMark(t) end
end

local function pruneMarks()
    for t in pairs(oreMarks) do
        if not t.Parent or not t:IsDescendantOf(Workspace) then removeMark(t) end
    end
end

local function updateMarks()
    local want = {}
    for _, t in ipairs(areaOres) do
        if t.Parent and not doneOres[t] then
            want[t] = true
            ensureMark(t)
        end
    end
    for t in pairs(oreMarks) do
        if not want[t] then removeMark(t) end
    end
end

local lastMarkRefresh = 0
local function refreshMarkStates()
    local now = os.clock()
    if now - lastMarkRefresh < 1 then return end
    lastMarkRefresh = now
    for t in pairs(oreMarks) do
        if t.Parent then ensureMark(t) end
    end
end

local function rebuildCandidates()
    local keep = {}
    for _, t in ipairs(areaOres) do
        if t.Parent and not doneOres[t] and not isExcluded(t) then table.insert(keep, t) end
    end
    local r = root()
    if r then
        local rp = r.Position
        table.sort(keep, function(a, b)
            return flatDist(posOf(a), rp) < flatDist(posOf(b), rp)
        end)
    end
    ores = keep
end

local function countExcludedInArea()
    local n = 0
    for _, t in ipairs(areaOres) do
        if t.Parent and not doneOres[t] and isExcluded(t) then n = n + 1 end
    end
    return n
end

local function countTakenInArea()
    local n = 0
    for _, t in ipairs(areaOres) do
        if t.Parent and not doneOres[t] and not isExcluded(t) and isTaken(t) then n = n + 1 end
    end
    return n
end

-- "3, 7, 10-15" -> {[3]=true,[7]=true,[10]=true,...}
local function parseExclusions(text)
    local set = {}
    for tok in text:gmatch("[^,;%s]+") do
        local a, b = tok:match("^(%d+)%-(%d+)$")
        if a and b then
            a, b = tonumber(a), tonumber(b)
            if a > b then a, b = b, a end
            if b - a <= 5000 then
                for n = a, b do set[n] = true end
            end
        elseif tok:match("^%d+$") then
            set[tonumber(tok)] = true
        end
    end
    return set
end

local function resetNumbering()
    clearOreMarks()
    oreId, nextId, oreH0, doneOres = {}, 1, {}, {}
    oreSlots = {}
    areaOres, ores = {}, {}
    excluded = {}
    exBox.Text = ""
end

----------------------------------------------------------------
-- Filter batas tak terlihat
----------------------------------------------------------------
local function isWallPart(d)
    if not d:IsA("BasePart") or not d.CanCollide then return false end
    if lp.Character and d:IsDescendantOf(lp.Character) then return false end
    if isOreName(d) or hasOreAncestor(d) then return false end
    local m = d:FindFirstAncestorOfClass("Model")
    if m and m:FindFirstChildOfClass("Humanoid") then return false end
    local s = d.Size
    if math.max(s.X, s.Y, s.Z) < CONFIG.WALL_MIN_SIZE then return false end
    if d.Transparency >= CONFIG.WALL_TRANSPARENCY then return true end
    local nm = d.Name:lower()
    for _, w in ipairs(CONFIG.WALL_NAMES) do
        if nm:find(w, 1, true) then return true end
    end
    return false
end

-- return fungsi(p, ref): true kalau ada dinding batas di antara ref dan p
local function makeBlockedCheck(walls)
    if not CONFIG.WALL_CHECK or #walls == 0 then
        return function() return false end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = walls
    params.IgnoreWater = true
    return function(p, ref)
        if not ref then return false end
        local origin = ref + Vector3.new(0, 3, 0)
        local target = Vector3.new(p.X, origin.Y, p.Z)
        return Workspace:Raycast(origin, target - origin, params) ~= nil
    end
end

local function doScan()
    -- 1. kumpulkan semua ore & dinding batas di map
    local all, walls, n = {}, {}, 0
    for _, d in ipairs(Workspace:GetDescendants()) do
        n = n + 1
        if n % 3000 == 0 then task.wait() end
        if d.Parent and isOreName(d) and not isGroup(d)
            and not hasOreAncestor(d)
            and not (lp.Character and d:IsDescendantOf(lp.Character))
            and not (d:IsA("Model") and d:FindFirstChildOfClass("Humanoid")) then
            local p = posOf(d)
            if p then
                table.insert(all, d)
                orePos[d] = p
            end
        elseif CONFIG.WALL_CHECK and d.Parent and isWallPart(d) then
            table.insert(walls, d)
        end
    end

    knownOres = all
    for t in pairs(orePos) do
        if not t.Parent then orePos[t] = nil trunkCache[t] = nil end
    end
    -- bersihkan data ore yang sudah dihapus game (mencegah memori terus membengkak)
    for t in pairs(oreId) do
        if not t.Parent then oreId[t] = nil oreH0[t] = nil end
    end
    for t in pairs(doneOres) do
        if not t.Parent then doneOres[t] = nil end
    end

    attrIgnore = false
    if CONFIG.OTHER_CHECK and CONFIG.OTHER_ATTR_CHECK then
        local sample, flagged = 0, 0
        for i = 1, math.min(#all, 200) do
            sample = sample + 1
            if attrTaken(all[i]) then flagged = flagged + 1 end
        end
        if sample >= 5 and flagged / sample > 0.5 then attrIgnore = true end
    end
    refreshTaken(true)

    -- 2. pilih sesuai mode
    local r = root()
    local playerPos = r and r.Position
    local isBlocked = makeBlockedCheck(walls)
    local outside = 0
    local selected = {}
    for _, t in ipairs(all) do
        local p = posOf(t)
        local ok, ref
        if mode == "map" then
            ok, ref = true, playerPos
        else
            ref = pointCovering(p)
            ok = ref ~= nil
        end
        if ok and isBlocked(p, ref) then
            ok = false
            outside = outside + 1
        end
        if ok then table.insert(selected, t) end
    end

    -- 3. beri nomor: ore hasil respawn di lokasi lama memakai nomor lama
    local usedIds = {}
    for _, t in ipairs(all) do
        local id = oreId[t]
        if id then usedIds[id] = true end
    end

    local ref = playerPos or (coordPoints[1] and coordPoints[1].pos) or Vector3.zero
    local fresh = {}
    for _, t in ipairs(selected) do
        if not oreId[t] then table.insert(fresh, t) end
    end
    table.sort(fresh, function(a, b)
        return flatDist(posOf(a), ref) < flatDist(posOf(b), ref)
    end)
    for _, t in ipairs(fresh) do
        local p = posOf(t)
        local id, bestD
        for _, s in ipairs(oreSlots) do
            if not usedIds[s.id] then
                local d = (s.pos - p).Magnitude
                if d <= CONFIG.SLOT_TOLERANCE and (not bestD or d < bestD) then
                    id, bestD = s.id, d
                end
            end
        end
        if not id then
            id = nextId
            nextId = nextId + 1
            table.insert(oreSlots, {pos = p, id = id})
        end
        usedIds[id] = true
        oreId[t] = id
        oreH0[t] = oreHeight(t)
    end

    -- 4. ore aktif (belum selesai, terlihat, belum habis)
    local now = os.clock()
    local active = {}
    for _, t in ipairs(selected) do
        local doneAt = doneOres[t]
        if doneAt and now >= doneAt then doneOres[t] = nil doneAt = nil end
        if not doneAt and oreVisible(t) and not isMined(t) then table.insert(active, t) end
    end
    areaOres = active

    rebuildCandidates()
    updateMarks()
    local where
    if mode == "map" then
        where = "Seluruh map"
    else
        where = ("%d titik / %d area"):format(#coordPoints, areaCount())
    end
    setStatus(("%s: %d ore | dikecualikan: %d | dipakai player lain: %d | di luar batas: %d | akan ditambang: %d | scan ulang tiap %ds")
        :format(where, #areaOres, countExcludedInArea(), countTakenInArea(), outside, #ores, rescanInterval))
end

local function scanOres()
    if scanning then
        pendingScan = true
        return
    end
    if mode == "coord" and #coordPoints == 0 then
        setStatus("Tambahkan titik koordinat dulu (tombol TAMBAH TITIK).")
        return
    end
    scanning = true
    local ok, err = pcall(doScan)
    scanning = false
    lastScanAt = os.clock()
    if not ok then
        warn("scanOres error:", err)
        setStatus("Scan gagal, coba lagi.")
    end
    if pendingScan then
        pendingScan = false
        if not running then task.spawn(scanOres) else needRescan = true end
    end
end

local function nextOre()
    local r = root()
    if not r then return end
    local best, bd
    for _, t in ipairs(ores) do
        if t.Parent and not doneOres[t] and not isExcluded(t) then
            local d = flatDist(posOf(t), r.Position)
            if (not bd or d < bd) and not isTaken(t) then best, bd = t, d end
        end
    end
    return best
end

local function finishOre(ore, ttl)
    doneOres[ore] = os.clock() + (ttl or CONFIG.DONE_EXPIRE)
    removeMark(ore)
    for i = #ores, 1, -1 do
        if ores[i] == ore then table.remove(ores, i) end
    end
end

----------------------------------------------------------------
-- Pergerakan WASD
----------------------------------------------------------------
local function setCam(on)
    local cam = camera()
    if not cam then return end
    if on then
        if cam.CameraType == Enum.CameraType.Custom then
            cam.CameraType = Enum.CameraType.Scriptable
            camByUs = true
        end
    else
        if camByUs then
            cam.CameraType = Enum.CameraType.Custom
            camByUs = false
        end
    end
end

local function walkDirect(target, stopDist, timeout, abortFn)
    local t0 = os.clock()
    local r0 = root()
    local lastPos, lastCheck = r0 and r0.Position, os.clock()
    local stuck = 0
    while running and os.clock() - t0 < timeout do
        local r = root()
        if not r then break end
        local flat = Vector3.new(target.X - r.Position.X, 0, target.Z - r.Position.Z)
        if flat.Magnitude <= stopDist or flat.Magnitude < 0.05 then break end
        if abortFn and abortFn() then break end

        local dir = flat.Unit
        camera().CFrame = CFrame.lookAt(r.Position - dir * 10 + Vector3.new(0, 6, 0), r.Position + dir * 10)
        key(Enum.KeyCode.W, true)

        if os.clock() - lastCheck > 0.7 then
            if lastPos and (r.Position - lastPos).Magnitude < 1 then
                stuck = stuck + 1
                tap(Enum.KeyCode.Space, 0.1)
                local side = (stuck % 2 == 0) and Enum.KeyCode.A or Enum.KeyCode.D
                key(side, true) task.wait(0.35) key(side, false)
            end
            lastPos, lastCheck = r.Position, os.clock()
        end
        RunService.RenderStepped:Wait()
    end
    key(Enum.KeyCode.W, false)
end

local function walkTo(target, stopDist, timeout, abortFn)
    stopDist = stopDist or 4
    timeout = timeout or 25
    setCam(true)
    local ok, err = pcall(function()
        local r = root()
        if CONFIG.USE_PATHFINDING and r and flatDist(r.Position, target) > 15 then
            local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true})
            local okp = pcall(function() path:ComputeAsync(r.Position, target) end)
            if okp and path.Status == Enum.PathStatus.Success then
                local t0 = os.clock()
                for i, wp in ipairs(path:GetWaypoints()) do
                    if not running or os.clock() - t0 > timeout then break end
                    if abortFn and abortFn() then return end
                    if i > 1 then
                        if wp.Action == Enum.PathWaypointAction.Jump then tap(Enum.KeyCode.Space, 0.1) end
                        walkDirect(wp.Position, 3, 6, abortFn)
                    end
                end
            end
        end
        walkDirect(target, stopDist, timeout, abortFn)
    end)
    if not ok then warn("walkTo error:", err) end
    releaseAll()
    setCam(false)
end

----------------------------------------------------------------
-- Kalkulasi rute (hitung dulu, gambar garis hijau, baru bergerak)
----------------------------------------------------------------
local routeFolder = nil

local function clearRoute()
    if routeFolder then
        pcall(function() routeFolder:Destroy() end)
        routeFolder = nil
    end
end

local function drawRoute(route)
    clearRoute()
    if not CONFIG.ROUTE_DRAW or not route or #route < 2 then return end
    routeFolder = Instance.new("Folder")
    routeFolder.Name = "AutoMine_RouteMarker"
    routeFolder.Parent = Workspace
    local lift = Vector3.new(0, 0.6, 0)
    local function mk(size, shape)
        local part = Instance.new("Part")
        part.Name = "AutoMine_RouteMarker"
        part.Shape = shape or Enum.PartType.Block
        part.Size = size
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Color = CONFIG.ROUTE_COLOR
        part.Parent = routeFolder
        return part
    end
    for i = 1, #route - 1 do
        local a, b = route[i].pos + lift, route[i + 1].pos + lift
        local len = (b - a).Magnitude
        if len > 0.05 then
            local seg = mk(Vector3.new(0.3, 0.3, len))
            seg.CFrame = CFrame.lookAt((a + b) / 2, b)
        end
    end
    for i = 1, #route do
        local dot = mk(Vector3.new(0.7, 0.7, 0.7), Enum.PartType.Ball)
        dot.Position = route[i].pos + lift
    end
end

local function tryPath(from, dest)
    local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true})
    local ok = pcall(function() path:ComputeAsync(from, dest) end)
    if ok and path.Status == Enum.PathStatus.Success then
        local route = {}
        for _, wp in ipairs(path:GetWaypoints()) do
            table.insert(route, {pos = wp.Position, jump = (wp.Action == Enum.PathWaypointAction.Jump)})
        end
        if #route >= 2 then return route end
    end
    return nil
end

-- hitung rute dari posisi sekarang ke ore. Coba titik ore dulu, kalau gagal coba titik di sekeliling ore
local function computeRoute(target)
    local r = root()
    if not r then return nil end
    local from = r.Position
    local route = tryPath(from, target)
    if route then return route end

    local cands = {}
    for k = 1, CONFIG.ROUTE_RING_POINTS do
        local ang = (k - 1) * (2 * math.pi / CONFIG.ROUTE_RING_POINTS)
        table.insert(cands, Vector3.new(target.X + math.cos(ang) * CONFIG.ROUTE_RING_RADIUS, target.Y, target.Z + math.sin(ang) * CONFIG.ROUTE_RING_RADIUS))
    end
    table.sort(cands, function(a, b) return flatDist(a, from) < flatDist(b, from) end)
    for i = 1, math.min(#cands, 4) do
        if not running then return nil end
        route = tryPath(from, cands[i])
        if route then return route end
    end
    return nil
end

-- ikuti rute titik demi titik. return true kalau sampai ujung rute (atau dihentikan abortFn), false kalau nyangkut
local function followRoute(route, abortFn, maxTime)
    setCam(true)
    local t0 = os.clock()
    local ok = true
    for i = 2, #route do
        if not running then ok = false break end
        if abortFn and abortFn() then break end
        if os.clock() - t0 > maxTime then ok = false break end
        local wp = route[i]
        if wp.jump then tap(Enum.KeyCode.Space, 0.1) end
        walkDirect(wp.pos, 3, 6, abortFn)
        if abortFn and abortFn() then break end
        local r = root()
        if not r or flatDist(r.Position, wp.pos) > 6 then ok = false break end
    end
    releaseAll()
    setCam(false)
    return ok
end

----------------------------------------------------------------
-- Deteksi tombol "Mine" & "Stop Mining"
----------------------------------------------------------------
local function scanGuiText(match)
    local pg = lp:FindFirstChildOfClass("PlayerGui")
    if not pg then return false end
    for _, d in ipairs(pg:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("TextLabel")) and d.Text ~= "" then
            if match(d.Text:lower()) and guiShown(d, pg) then
                return true
            end
        end
    end
    return false
end

local function isStopText(s) return s:find(CONFIG.STOP_TEXT, 1, true) ~= nil end
local function isMineText(s)
    if s:find("stop", 1, true) then return false end
    s = s:gsub("[^%a]", "")          -- buang spasi, simbol, "[F]"
    return s == "mine" or s == "fmine"
end

local mineCache, mineCacheAt = false, 0
local function mineButtonVisible()                 -- tombol "Mine" (bukan "Stop Mining")
    local now = os.clock()
    if now - mineCacheAt < 0.15 then return mineCache end
    mineCacheAt = now
    mineCache = scanGuiText(isMineText)
    return mineCache
end

local stopCache, stopCacheAt = false, 0
local function stopButtonVisible()                 -- tombol "Stop Mining" (muncul selama menambang)
    local now = os.clock()
    if now - stopCacheAt < 0.1 then return stopCache end
    stopCacheAt = now
    stopCache = scanGuiText(isStopText)
    return stopCache
end

local function waitButton(t)
    local t0 = os.clock()
    repeat
        mineCacheAt = 0
        if mineButtonVisible() then return true end
        task.wait(0.1)
    until os.clock() - t0 >= t or not running
    return false
end

----------------------------------------------------------------
-- Mine (F ditekan 1 kali, selesai otomatis saat "Stop Mining" hilang)
----------------------------------------------------------------
local function approachOre(ore, id)
    local deadline = os.clock() + reachTimeout
    local function left() return deadline - os.clock() end

    local invCache, invAt = false, 0
    local function invalid()
        local now = os.clock()
        if now - invAt < 0.25 then return invCache end
        invAt = now
        invCache = isMined(ore) or isExcluded(ore) or isTaken(ore)
        return invCache
    end
    local function abort()
        return invalid() or mineButtonVisible()
    end

    local p = posOf(ore)
    if not p then return false end
    invAt = 0
    if invalid() then return false end
    if waitButton(0.3) then return true end

    -- 0. hitung rute dulu (garis hijau), baru bergerak; kalau nyangkut, hitung ulang dari posisi sekarang
    if CONFIG.ROUTE_ENABLED then
        for attempt = 1, CONFIG.ROUTE_MAX_TRIES do
            if not running or left() <= 0 then break end
            setStatus(("Ore #%d: menghitung rute (%d/%d)..."):format(id, attempt, CONFIG.ROUTE_MAX_TRIES))
            local route = computeRoute(p)
            if not route then break end             -- tidak ada rute: pakai cara bertahap di bawah
            drawRoute(route)
            setStatus(("Ore #%d: mengikuti rute (%d titik, sisa %ds)"):format(id, #route, math.max(0, math.floor(left()))))
            local okr = followRoute(route, abort, math.min(left(), CONFIG.ROUTE_MAX_TIME))
            invAt = 0
            if invalid() then clearRoute() return false end
            if waitButton(0.5) then clearRoute() return true end
            if okr then break end                   -- rute selesai tapi tombol belum muncul: lanjut mendekat bertahap
        end
        clearRoute()
    end

    -- 1. mendekat bertahap
    for _, d in ipairs({CONFIG.MINE_DISTANCE, 5, 3.5, 2.5, 1.5}) do
        if not running or left() <= 0 then break end
        setStatus(("Mendekati ore #%d (sisa %ds)..."):format(id, math.max(0, math.floor(left()))))
        walkTo(p, d, math.min(left(), 12), abort)
        invAt = 0
        if invalid() then return false end
        if waitButton(0.5) then return true end
    end

    -- 2. putari ore
    local r = root()
    local startAng = r and math.atan2(r.Position.Z - p.Z, r.Position.X - p.X) or 0
    local steps = 8
    for k = 1, steps do
        if not running or left() <= 0 then break end
        local ang = startAng + k * (2 * math.pi / steps)
        local pt = Vector3.new(p.X + math.cos(ang) * 4, p.Y, p.Z + math.sin(ang) * 4)
        setStatus(("Ore #%d: memutar mencari posisi mine (%d/%d, sisa %ds)"):format(id, k, steps, math.max(0, math.floor(left()))))
        walkTo(pt, 2, math.min(left(), 6), abort)
        invAt = 0
        if invalid() then return false end
        if waitButton(0.4) then return true end
        walkTo(p, 2, math.min(left(), 4), abort)
        invAt = 0
        if invalid() then return false end
        if waitButton(0.4) then return true end
    end
    return waitButton(0.2)
end

local function mineOreInner(ore)
    local id = oreId[ore] or 0
    setStatus(("Menuju ore #%d..."):format(id))

    local reached = approachOre(ore, id)
    if not running then return end
    if isExcluded(ore) then return end
    if not reached then
        if isMined(ore) then
            finishOre(ore, CONFIG.MINED_EXPIRE)
        elseif isTaken(ore) then
            setStatus(("Ore #%d sedang ditambang player lain, dilewati"):format(id))
            task.wait(0.5)
            finishOre(ore, CONFIG.OTHER_EXPIRE)
        else
            setStatus(("Ore #%d tidak terjangkau (batas %d dtk), dilewati %d dtk"):format(id, reachTimeout, CONFIG.DONE_EXPIRE))
            task.wait(0.8)
            finishOre(ore, CONFIG.DONE_EXPIRE)
        end
        return
    end

    currentOre = ore
    tap(CONFIG.MINE_KEY, 0.05)                      -- F cukup 1 kali
    setStatus(("Mine #%d (F x1), menunggu tombol Stop Mining..."):format(id))

    local start = os.clock()
    local lastTap = start
    local retries = 0
    local sawStop = false
    local goneSince = nil
    local finished = false

    while running do
        if isExcluded(ore) then return end
        if isMined(ore) then
            finished = true
            break
        end

        local now = os.clock()
        if now - start > CONFIG.SAFETY_MAX_MINE then
            setStatus(("Ore #%d: melewati batas pengaman %d dtk"):format(id, CONFIG.SAFETY_MAX_MINE))
            break
        end

        if stopButtonVisible() then
            sawStop = true
            goneSince = nil
            setStatus(("Menambang #%d... (menunggu Stop Mining hilang)"):format(id))
        elseif sawStop then
            goneSince = goneSince or now
            if now - goneSince >= 0.3 then
                finished = true
                break
            end
        elseif now - lastTap > CONFIG.START_GRACE then
            if retries < CONFIG.START_RETRIES and mineButtonVisible() then
                retries = retries + 1
                tap(CONFIG.MINE_KEY, 0.05)
                lastTap = os.clock()
            else
                setStatus(("Ore #%d: Stop Mining tidak muncul, dilewati"):format(id))
                break
            end
        end
        task.wait(0.1)
    end

    if finished and running and not isExcluded(ore) then
        setStatus(("Ore #%d selesai, jeda %.1f dtk..."):format(id, afterMineDelay))
        task.wait(afterMineDelay)
        if CONFIG.PICKUP_ENABLED and running and not isExcluded(ore) then
            setStatus(("Ore #%d: ambil hasil (F x1)..."):format(id))
            tap(CONFIG.MINE_KEY, 0.05)
            task.wait(0.6)
        end
    end

    finishOre(ore, finished and CONFIG.MINED_EXPIRE or CONFIG.DONE_EXPIRE)
end

local function mineOre(ore)
    local ok, err = pcall(mineOreInner, ore)
    if not ok then
        warn("mineOre error:", err)
        finishOre(ore, CONFIG.DONE_EXPIRE)
    end
    clearRoute()
    currentOre = nil
end

----------------------------------------------------------------
-- Loop utama
----------------------------------------------------------------
local function alive(token) return running and token == runToken end

local function mainLoopInner(token)
    if mode == "coord" and #coordPoints == 0 then
        setStatus("Tambahkan titik koordinat dulu (tombol TAMBAH TITIK).")
        running = false
        setRunUI(false)
        return
    end
    scanOres()

    while alive(token) do
        if not root() then
            task.wait(1)
        else
            pruneMarks()
            refreshMarkStates()
            -- scan ulang otomatis tiap rescanInterval detik (default 20)
            if needRescan or os.clock() - lastScanAt >= rescanInterval then
                needRescan = false
                scanOres()
            end

            local target = nextOre()
            if target then
                if isMined(target) then
                    finishOre(target, CONFIG.MINED_EXPIRE)
                else
                    mineOre(target)
                end
            elseif alive(token) then
                local waiting = 0
                for _, t in ipairs(ores) do
                    if t.Parent and not doneOres[t] and not isExcluded(t) then waiting = waiting + 1 end
                end
                if waiting > 0 then
                    setStatus(("%d ore sedang ditambang player lain, menunggu..."):format(waiting))
                    task.wait(1)
                else
                    setStatus("Ore yang ditandai habis, scan ulang di area yang ditandai...")
                    task.wait(0.5)
                    scanOres()
                    if #ores == 0 and alive(token) then
                        -- keliling ke titik koordinat berikutnya (bergiliran) supaya ore di sana termuat
                        local r = root()
                        if mode == "coord" and #coordPoints > 0 and r then
                            patrolIdx = (patrolIdx % #coordPoints) + 1
                            local dest = coordPoints[patrolIdx].pos
                            if flatDist(r.Position, dest) > 8 then
                                setStatus(("Area kosong, pindah ke titik %d dari %d..."):format(patrolIdx, #coordPoints))
                                walkTo(dest, 4, 40)
                                if alive(token) then
                                    task.wait(1)
                                    scanOres()
                                end
                            end
                        end
                    end
                    if #ores == 0 and alive(token) then
                        setStatus(("Tidak ada ore tersedia di area yang ditandai, scan ulang tiap %d dtk..."):format(rescanInterval))
                        task.wait(3)
                    end
                end
            end
        end
        task.wait()
    end
end

local function mainLoop(token)
    loopActive = true
    local ok, err = pcall(mainLoopInner, token)
    loopActive = false
    currentOre = nil
    releaseAll()
    setCam(false)
    clearRoute()
    if not ok then
        warn("mainLoop error:", err)
        if token == runToken then
            running = false
            setRunUI(false)
            setStatus("Error, dihentikan: " .. tostring(err))
        end
    end
end

----------------------------------------------------------------
-- Tombol & input
----------------------------------------------------------------
local function toggleRun()
    if not running then
        running = true
        runToken = runToken + 1
        local my = runToken
        setRunUI(true)
        task.spawn(function()
            -- tunggu loop lama benar-benar berhenti (mencegah 2 loop jalan bersamaan)
            while loopActive do task.wait(0.1) end
            if running and my == runToken then mainLoop(my) end
        end)
    else
        running = false
        releaseAll()
        setCam(false)
        clearRoute()
        setRunUI(false)
        setStatus("Dihentikan")
    end
end
startBtn.MouseButton1Click:Connect(toggleRun)
miniBtn.MouseButton1Click:Connect(toggleRun)

local function refreshPointUI()
    coordBtn.Text = ("TAMBAH TITIK (posisi saya) [%d]"):format(#coordPoints)
    nearBtn.Text = ("TANDAI DI TITIK KOORDINAT (%d titik / %d area)"):format(#coordPoints, areaCount())
end
refreshPointUI()

-- dipanggil setiap titik ditambah / dihapus
local function onPointsChanged(msg)
    drawCoordMarker()
    refreshPointUI()
    if mode == "coord" then
        if #coordPoints == 0 then
            if running then toggleRun() end
            clearOreMarks()
            areaOres, ores = {}, {}
            setStatus(msg .. " Tidak ada titik tersisa, tambahkan titik baru atau pilih TANDAI SELURUH MAP.")
            return
        end
        setStatus(msg .. " Scanning...")
        if running then needRescan = true else task.spawn(scanOres) end
    else
        setStatus(msg .. " Klik TANDAI DI TITIK KOORDINAT untuk memakai titik.")
    end
end

coordBtn.MouseButton1Click:Connect(function()
    local r = root()
    if not r then setStatus("Karakter belum ada.") return end
    local p = r.Position
    for i, pt in ipairs(coordPoints) do
        if flatDist(pt.pos, p) < CONFIG.POINT_MIN_GAP then
            setStatus(("Posisi ini sudah jadi titik %d."):format(i))
            return
        end
    end
    table.insert(coordPoints, {pos = p})
    onPointsChanged(("Titik %d ditambahkan (X %.0f, Z %.0f)."):format(#coordPoints, p.X, p.Z))
end)

delOneBtn.MouseButton1Click:Connect(function()
    if #coordPoints == 0 then setStatus("Belum ada titik.") return end
    local txt = delBox.Text:gsub("%s", "")
    local n = (txt == "") and #coordPoints or tonumber(txt)   -- kosong = hapus titik terakhir
    if not n or n ~= math.floor(n) or n < 1 or n > #coordPoints then
        setStatus(("Nomor titik tidak valid. Isi 1 - %d (kosong = titik terakhir)."):format(#coordPoints))
        return
    end
    table.remove(coordPoints, n)
    delBox.Text = ""
    patrolIdx = 0
    onPointsChanged(("Titik %d dihapus (nomor titik lain disesuaikan)."):format(n))
end)

delAllBtn.MouseButton1Click:Connect(function()
    if #coordPoints == 0 then setStatus("Belum ada titik.") return end
    local n = #coordPoints
    coordPoints = {}
    delBox.Text = ""
    patrolIdx = 0
    onPointsChanged(("Semua titik (%d) dihapus."):format(n))
end)

mapBtn.MouseButton1Click:Connect(function()
    if running then setStatus("Hentikan (STOP) dulu sebelum ganti mode") return end
    if scanning then return end
    mode = "map"
    refreshModeButtons()
    resetNumbering()
    setStatus("Menandai seluruh ore di map...")
    task.spawn(scanOres)
end)

nearBtn.MouseButton1Click:Connect(function()
    if running then setStatus("Hentikan (STOP) dulu sebelum ganti mode") return end
    if scanning then return end
    if #coordPoints == 0 then setStatus("Tambahkan titik koordinat dulu (tombol TAMBAH TITIK).") return end
    mode = "coord"
    refreshModeButtons()
    resetNumbering()
    setStatus("Menandai ore di semua titik koordinat...")
    task.spawn(scanOres)
end)

local function refreshPosBtn()
    posBtn.Text = "DETEKSI POSISI PLAYER: " .. (otherPosOn and "ON" or "OFF")
    posBtn.BackgroundColor3 = otherPosOn and COLORS.accent or COLORS.field
    posBtn.TextColor3 = otherPosOn and Color3.fromRGB(10, 30, 15) or Color3.new(1, 1, 1)
end
refreshPosBtn()

posBtn.MouseButton1Click:Connect(function()
    otherPosOn = not otherPosOn
    refreshPosBtn()
    refreshTaken(true)
    lastMarkRefresh = 0
    refreshMarkStates()
    setStatus(otherPosOn
        and "Deteksi player lain berdasarkan posisi: ON"
        or  "Deteksi player lain berdasarkan posisi: OFF (ore tetap ditambang walau ada player lain di dekatnya)")
end)

exBox.FocusLost:Connect(function()
    excluded = parseExclusions(exBox.Text)
    rebuildCandidates()
    updateMarks()
    local cnt = 0
    for _ in pairs(excluded) do cnt = cnt + 1 end
    setStatus(("Pengecualian diperbarui: %d nomor | akan ditambang: %d"):format(cnt, #ores))
end)

radiusBox.FocusLost:Connect(function()
    local n = tonumber(radiusBox.Text)
    if n and n >= 5 and n <= 5000 then
        radius = n
        drawCoordMarker()        -- gambar ulang zona (penggabungan dihitung ulang)
        refreshPointUI()
        if mode == "coord" and #coordPoints > 0 then
            if running then needRescan = true else task.spawn(scanOres) end
        end
    else
        radiusBox.Text = tostring(radius)
    end
end)

mineBox.FocusLost:Connect(function()
    local n = tonumber(mineBox.Text)
    if n and n >= 0 and n <= 60 then
        afterMineDelay = n
    else
        mineBox.Text = tostring(afterMineDelay)
    end
end)

reachBox.FocusLost:Connect(function()
    local n = tonumber(reachBox.Text)
    if n and n >= 5 and n <= 180 then
        reachTimeout = n
    else
        reachBox.Text = tostring(reachTimeout)
    end
end)

rescanBox.FocusLost:Connect(function()
    local n = tonumber(rescanBox.Text)
    if n and n >= 5 and n <= 600 then
        rescanInterval = n
        setStatus(("Scan ulang otomatis tiap %d detik."):format(n))
    else
        rescanBox.Text = tostring(rescanInterval)
    end
end)

local function stopAll()
    running = false
    runToken = runToken + 1
    currentOre = nil
    releaseAll()
    setCam(false)
    clearOreMarks()
    clearCoordMarker()
    clearRoute()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
    pcall(function() gui:Destroy() end)
end

closeBtn.MouseButton1Click:Connect(stopAll)
env.__AutoMineStop = stopAll
