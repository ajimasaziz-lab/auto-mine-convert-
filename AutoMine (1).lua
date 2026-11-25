--[[ AUTO MINE v2 (rekonstruksi dari AUTO CHOP v17: nambang Ore, tombol & alur sama dengan nebang)
     v2: penomoran ore tetap per lokasi (tahan respawn), tidak ngulang dari 1 saat scan ulang ]]--

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
    DEFAULT_RADIUS    = 300,     -- radius (stud) untuk mode "terdekat koordinat"
    DONE_EXPIRE       = 180,    -- detik: ore yang dilewati (tidak terjangkau/gagal) tidak dipilih lagi
    MINED_EXPIRE      = 15,     -- detik: ore yang berhasil ditambang boleh dipilih lagi (kalau respawn)
    USE_PATHFINDING   = true,

    -- penomoran tetap per lokasi
    SLOT_TOLERANCE    = 3,      -- stud: ore baru sedekat ini dari lokasi ore lama = memakai nomor lama (naikkan, mis. 6, kalau ore bergeser saat respawn)

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
local scanning = false
local needRescan = false
local mode = "map"                   -- "map" = seluruh map | "coord" = terdekat koordinat
local radius = CONFIG.DEFAULT_RADIUS
local reachTimeout = CONFIG.REACH_TIMEOUT
local afterMineDelay = CONFIG.AFTER_MINE_DELAY
local coordPos = nil
local coordParts = {}
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
    blue   = Color3.fromRGB(55, 105, 190),
    purple = Color3.fromRGB(110, 80, 190),
    accent = Color3.fromRGB(70, 200, 120),
}

local WIDTH, BAR_H, BODY_H = 260, 34, 428

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.new(0, WIDTH, 0, BAR_H + BODY_H)
frame.Position = UDim2.new(0, 20, 0.3, 0)
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
miniBtn.BackgroundColor3 = Color3.fromRGB(46, 160, 80)
miniBtn.TextColor3 = Color3.new(1, 1, 1)
miniBtn.Font = Enum.Font.GothamBold
miniBtn.TextSize = 11
miniBtn.Text = "START"
Instance.new("UICorner", miniBtn).CornerRadius = UDim.new(0, 6)

local body = Instance.new("Frame", frame)
body.Size = UDim2.new(1, 0, 0, BODY_H)
body.Position = UDim2.new(0, 0, 0, BAR_H)
body.BackgroundTransparency = 1

local function mkBtn(text, y, color)
    local b = Instance.new("TextButton", body)
    b.Size = UDim2.new(1, -20, 0, 30)
    b.Position = UDim2.new(0, 10, 0, y)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Text = text
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

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

local startBtn = mkBtn("START", 8, COLORS.green)
local coordBtn = mkBtn("PILIH KOORDINAT (posisi saya)", 44, COLORS.purple)
local mapBtn   = mkBtn("TANDAI SELURUH MAP", 80, COLORS.field)
local nearBtn  = mkBtn("TANDAI TERDEKAT KOORDINAT", 116, COLORS.field)

local function setRunUI(on)
    local txt = on and "STOP" or "START"
    local col = on and COLORS.red or COLORS.green
    startBtn.Text = txt
    startBtn.BackgroundColor3 = col
    miniBtn.Text = txt
    miniBtn.BackgroundColor3 = col
end

mkLabel("Radius koordinat (stud):", 156)
local radiusBox = mkBox(153, radius)
mkLabel("Batas raih Mine (detik):", 188)
local reachBox = mkBox(185, reachTimeout)
mkLabel("Jeda setelah tambang (detik):", 220)
local mineBox = mkBox(217, afterMineDelay)

mkLabel("Kecualikan no. ore:", 252)
local exBox = Instance.new("TextBox", body)
exBox.Size = UDim2.new(1, -20, 0, 28)
exBox.Position = UDim2.new(0, 10, 0, 274)
exBox.Text = ""
exBox.PlaceholderText = "contoh: 3, 7, 10-15"
exBox.PlaceholderColor3 = Color3.fromRGB(120, 125, 140)
exBox.BackgroundColor3 = COLORS.field
exBox.TextColor3 = COLORS.text
exBox.Font = Enum.Font.Gotham
exBox.TextSize = 13
exBox.ClearTextOnFocus = false
Instance.new("UICorner", exBox).CornerRadius = UDim.new(0, 6)

local posBtn = mkBtn("DETEKSI POSISI PLAYER: ON", 310, COLORS.accent)
posBtn.TextColor3 = Color3.fromRGB(10, 30, 15)

local statusBox = Instance.new("Frame", body)
statusBox.Size = UDim2.new(1, -20, 0, 70)
statusBox.Position = UDim2.new(0, 10, 0, 348)
statusBox.BackgroundColor3 = COLORS.bar
statusBox.BorderSizePixel = 0
Instance.new("UICorner", statusBox).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel", statusBox)
status.Size = UDim2.new(1, -16, 1, -8)
status.Position = UDim2.new(0, 8, 0, 4)
status.BackgroundTransparency = 1
status.Text = "Status: pilih mode penandaan ore (seluruh map / terdekat koordinat)."
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
    local h = minimized and BAR_H or (BAR_H + BODY_H)
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
-- Penanda koordinat (bola + lingkaran radius)
----------------------------------------------------------------
local function clearCoordMarker()
    for _, p in ipairs(coordParts) do p:Destroy() end
    coordParts = {}
end

local function drawCoordMarker()
    clearCoordMarker()
    if not coordPos then return end
    local green = Color3.fromRGB(0, 255, 120)

    local ball = Instance.new("Part")
    ball.Name = "AutoMine_CoordMarker"
    ball.Shape = Enum.PartType.Ball
    ball.Size = Vector3.new(2, 2, 2)
    ball.Anchored = true
    ball.CanCollide = false
    ball.CanQuery = false
    ball.CanTouch = false
    ball.Material = Enum.Material.Neon
    ball.Color = green
    ball.Transparency = 0.3
    ball.Position = coordPos
    ball.Parent = Workspace

    local bb = Instance.new("BillboardGui", ball)
    bb.Size = UDim2.new(0, 90, 0, 22)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    local tl = Instance.new("TextLabel", bb)
    tl.Size = UDim2.new(1, 0, 1, 0)
    tl.BackgroundTransparency = 1
    tl.Text = "KOORDINAT"
    tl.TextColor3 = green
    tl.TextStrokeTransparency = 0.3
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 14

    local ring = Instance.new("Part")
    ring.Name = "AutoMine_CoordMarker"
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.3, radius * 2, radius * 2)
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.CanTouch = false
    ring.Material = Enum.Material.Neon
    ring.Color = green
    ring.Transparency = 0.88
    ring.CFrame = CFrame.new(coordPos - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
    ring.Parent = Workspace

    coordParts = {ball, ring}
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
        if ex then
            m.label.Text = ("#%d X"):format(oreId[t])
            m.label.TextColor3 = Color3.fromRGB(255, 170, 60)
        elseif tk then
            m.label.Text = ("#%d P"):format(oreId[t])
            m.label.TextColor3 = Color3.fromRGB(120, 180, 255)
        else
            m.label.Text = ("#%d"):format(oreId[t])
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
        table.sort(keep, function(a, b)
            return flatDist(posOf(a), r.Position) < flatDist(posOf(b), r.Position)
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

local function makeBlockedCheck(walls, ref)
    if not CONFIG.WALL_CHECK or #walls == 0 or not ref then
        return function() return false end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = walls
    params.IgnoreWater = true
    local origin = ref + Vector3.new(0, 3, 0)
    return function(p)
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
        if isOreName(d) and not isGroup(d)
            and not hasOreAncestor(d)
            and not (lp.Character and d:IsDescendantOf(lp.Character))
            and not (d:IsA("Model") and d:FindFirstChildOfClass("Humanoid")) then
            local p = posOf(d)
            if p then
                table.insert(all, d)
                orePos[d] = p
            end
        elseif CONFIG.WALL_CHECK and isWallPart(d) then
            table.insert(walls, d)
        end
    end

    knownOres = all
    for t in pairs(orePos) do
        if not t.Parent then orePos[t] = nil trunkCache[t] = nil end
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
    local rayRef = (mode == "coord" and coordPos) or playerPos
    local ref = rayRef or Vector3.zero
    local isBlocked = makeBlockedCheck(walls, rayRef)
    local outside = 0
    local selected = {}
    for _, t in ipairs(all) do
        local ok = (mode == "map") or (coordPos ~= nil and flatDist(posOf(t), coordPos) <= radius)
        if ok and isBlocked(posOf(t)) then
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
    setStatus(("%s: %d ore | dikecualikan: %d | dipakai player lain: %d | di luar batas: %d | akan ditambang: %d")
        :format(mode == "map" and "Seluruh map" or "Dekat koordinat",
            #areaOres, countExcludedInArea(), countTakenInArea(), outside, #ores))
end

local function scanOres()
    if scanning then return end
    if mode == "coord" and not coordPos then
        setStatus("Pilih koordinat dulu (tombol PILIH KOORDINAT).")
        return
    end
    scanning = true
    local ok, err = pcall(doScan)
    scanning = false
    if not ok then
        warn("scanOres error:", err)
        setStatus("Scan gagal, coba lagi.")
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
        if flat.Magnitude <= stopDist then break end
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
                print("MATCH:", d:GetFullName(), "|", d.Text)
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
            setStatus(("Ore #%d tidak terjangkau (batas %d dtk), dilewati"):format(id, reachTimeout))
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
    mineOreInner(ore)
    clearRoute()
    currentOre = nil
end

----------------------------------------------------------------
-- Loop utama
----------------------------------------------------------------
local function mainLoop()
    if mode == "coord" and not coordPos then
        setStatus("Pilih koordinat dulu (tombol PILIH KOORDINAT).")
        running = false
        setRunUI(false)
        return
    end
    scanOres()

    while running do
        if not root() then
            task.wait(1)
        else
            pruneMarks()
            refreshMarkStates()
            if needRescan then needRescan = false scanOres() end

            local target = nextOre()
            if target then
                if isMined(target) then
                    finishOre(target, CONFIG.MINED_EXPIRE)
                else
                    mineOre(target)
                end
            elseif running then
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
                    if #ores == 0 and running then
                        local r = root()
                        if mode == "coord" and coordPos and r and flatDist(r.Position, coordPos) > 8 then
                            setStatus("Area kosong, kembali ke titik koordinat yang ditandai...")
                            walkTo(coordPos, 4, 40)
                            if running then
                                task.wait(1)
                                scanOres()
                            end
                        end
                    end
                    if #ores == 0 and running then
                        setStatus("Tidak ada ore tersedia di area yang ditandai, menunggu ore muncul lagi...")
                        task.wait(3)
                    end
                end
            end
        end
        task.wait()
    end
    currentOre = nil
    releaseAll()
    setCam(false)
end

----------------------------------------------------------------
-- Tombol & input
----------------------------------------------------------------
local function toggleRun()
    if not running then
        running = true
        setRunUI(true)
        task.spawn(mainLoop)
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

coordBtn.MouseButton1Click:Connect(function()
    if running then setStatus("Hentikan (STOP) dulu sebelum ganti koordinat") return end
    local r = root()
    if not r then return end
    coordPos = r.Position
    drawCoordMarker()
    coordBtn.Text = "KOORDINAT [OK] (klik utk ganti)"
    if mode == "coord" then
        resetNumbering()
        setStatus("Koordinat baru disimpan, scanning...")
        task.spawn(scanOres)
    else
        setStatus(("Koordinat disimpan (X %.0f, Z %.0f). Klik TANDAI TERDEKAT KOORDINAT."):format(coordPos.X, coordPos.Z))
    end
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
    if not coordPos then setStatus("Pilih koordinat dulu (tombol PILIH KOORDINAT).") return end
    mode = "coord"
    refreshModeButtons()
    resetNumbering()
    setStatus("Menandai ore terdekat koordinat...")
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
        if coordPos then drawCoordMarker() end
        if mode == "coord" then
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

local function stopAll()
    running = false
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
