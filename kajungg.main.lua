local FOLDER_NAME = "infiniteyield"
local KEY_FILE    = FOLDER_NAME .. "/config_dev.txt"

if not isfolder(FOLDER_NAME) then
    makefolder(FOLDER_NAME)
end

local SUBFOLDERS = {
    FOLDER_NAME .. "/data",
    FOLDER_NAME .. "/data/cache",
    FOLDER_NAME .. "/data/cache/temp",
    FOLDER_NAME .. "/assets",
    FOLDER_NAME .. "/assets/images",
    FOLDER_NAME .. "/backup",
    FOLDER_NAME .. "/backup/old",
    FOLDER_NAME .. "/logs",
    FOLDER_NAME .. "/scripts"
}

for _, folder in pairs(SUBFOLDERS) do
    if not isfolder(folder) then
        makefolder(folder)
    end
end

KEY_FILE = FOLDER_NAME .. "/data/cache/temp/config.txt"

local DUMMY_FILES = {
    FOLDER_NAME .. "/assets/readme.txt",
    FOLDER_NAME .. "/backup/settings.bak",
    FOLDER_NAME .. "/logs/error.log"
}

for _, file in pairs(DUMMY_FILES) do
    if not isfile(file) then
        writefile(file, "-- Placeholder file")
    end
end

-- =========================
-- SERVICES
-- =========================

local RunService      = game:GetService("RunService")
local HttpService     = game:GetService("HttpService")
local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local CoreGui         = game:GetService("CoreGui")
local LocalPlayer     = Players.LocalPlayer
local IsLoggedIn      = false

-- =========================
-- API CONFIG
-- =========================

local API_CONFIG = {
    base_url = "https://rullzsyhub.web.id",
    validate_endpoint = "/validate_dev/validate.php",
    get_user_endpoint = "/validate_dev/get_user.php"
}

-- =========================
-- DATE FORMAT (INDONESIA)
-- =========================

local MONTH_ID = {
    "Januari","Februari","Maret","April","Mei","Juni",
    "Juli","Agustus","September","Oktober","November","Desember"
}

local function formatDateTime(timestamp)
    if not timestamp then
        return "-"
    end

    if type(timestamp) == "string" then
        local y, m, d, h, mi, s =
            timestamp:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
        if y then
            timestamp = os.time({
                year = tonumber(y),
                month = tonumber(m),
                day = tonumber(d),
                hour = tonumber(h),
                min = tonumber(mi),
                sec = tonumber(s),
            })
        else
            return timestamp
        end
    end

    local t = os.date("*t", timestamp)

    local hour = t.hour
    local ampm = "AM"
    if hour >= 12 then ampm = "PM" end
    hour = hour % 12
    if hour == 0 then hour = 12 end

    return string.format(
        "%02d %s %d | %d:%02d %s",
        t.day,
        MONTH_ID[t.month],
        t.year,
        hour,
        t.min,
        ampm
    )
end

local function addMonths(timestamp, months)
    local t = os.date("*t", timestamp)
    t.month = t.month + months
    return os.time(t)
end

-- =========================
-- UTILS
-- =========================

math.randomseed(os.clock() * 1e6)

local function randomString(len)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local t = {}
    for i = 1, len do
        t[i] = chars:sub(math.random(#chars), math.random(#chars))
    end
    return table.concat(t)
end

local function generateKeySecure()
    return randomString(12) .. "_" .. os.time()
end

local function safeHttpGet(url)
    local ok, res = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(res) == "string" and res ~= "" then
        return true, res
    end
    return false, nil
end

-- Function untuk check maintenance/server status
local function checkServerStatus(response)
    if not response then return false end
    
    -- Check jika response HTML (maintenance page)
    if response:lower():find("<!doctype") or response:lower():find("<html") then
        return true
    end
    
    -- Check jika ada kata-kata maintenance
    if response:lower():find("maintenance") or response:lower():find("under construction") then
        return true
    end
    
    return false
end

-- =========================
-- VALIDATE KEY
-- =========================

local function ValidateKey_Custom(key)
    if not key or key:gsub("%s+", "") == "" then
        return false, "Key kosong", "empty"
    end

    local url = string.format(
        "%s%s?key_secure=%s&key=%s&roblox_username=%s&roblox_user_id=%d&hwid=%s&device_id=%s&role=%s&nonce=%d",
        API_CONFIG.base_url,
        API_CONFIG.validate_endpoint,
        generateKeySecure(),
        HttpService:UrlEncode(key),
        HttpService:UrlEncode(LocalPlayer.Name),
        LocalPlayer.UserId,
        randomString(16),
        "WIN64-" .. randomString(6),
        "USER",
        os.time()
    )

    local ok, res = safeHttpGet(url)
    if not ok then
        return false, "Tidak dapat terhubung ke server", "connection_error"
    end
    
    -- Check apakah server sedang maintenance
    if checkServerStatus(res) then
        return false, "Server sedang dalam pemeliharaan, silakan coba beberapa saat lagi", "maintenance"
    end

    local data
    if not pcall(function()
        data = HttpService:JSONDecode(res)
    end) then
        return false, "Respon server tidak valid", "invalid_response"
    end

    -- Check status dari response
    if tostring(data.status):lower() == "success" then
        getgenv().AUTH_KEY = key
        return true, data, "success"
    end

    -- Kategorisasi error berdasarkan pesan dari server
    local message = data.message or "Key tidak valid"
    local errorType = "invalid_key"
    
    -- Deteksi jenis error
    if message:lower():find("salah") then
        errorType = "invalid_key"
    elseif message:lower():find("sharing") or message:lower():find("ciee") then
        errorType = "sharing_key"
    elseif message:lower():find("blacklist") then
        errorType = "blacklisted"
    elseif message:lower():find("expire") then
        errorType = "expired"
    elseif message:lower():find("database") or message:lower():find("server") then
        errorType = "database_error"
    end

    return false, message, errorType
end

-- =========================
-- GLOBAL AUTH STORAGE
-- =========================
getgenv().AUTH_KEY = getgenv().AUTH_KEY or ""

-- =========================
-- LOAD LIBLARY UI
-- =========================

if isfile(KEY_FILE) then
    local savedKey = readfile(KEY_FILE):gsub("%s+", "")
    if savedKey ~= "" then
        local success, data, errorType = ValidateKey_Custom(savedKey)
        
        if success then
            IsLoggedIn = true
        else
            if errorType == "invalid_key" or errorType == "expired" or errorType == "blacklisted" then
                delfile(KEY_FILE) 
            end
        end
    end
end

-- =========================
-- LOAD WINDUI
-- =========================
local WindUI = loadstring(game:HttpGet("https://rullzsyhub.web.id/lua/WindUI_Remake.lua"))()

-- ==========================================
-- WINDOW
-- ==========================================

local WindowConfig = {
    Title = "RullzsyHUB | Cracked By Pokay",
    Author = "Discord: dsc.gg/rullzsyhub",
    Folder = "RullzsyHUB",
    Icon = "rbxassetid://75111711057365",
    Background = "rbxassetid://133699862172739",
    BackgroundImageTransparency = 0.8,
    Theme = "Dark",
	Size = UDim2.fromOffset(600, 448),
    NewElements = true,
    HideSearchBar = false,
    OpenButton = {
        Title = "Open Menu",
        CornerRadius = UDim.new(0, 10),
        StrokeThickness = 3,
        Enabled = true,
        Draggable = true,
        OnlyMobile = true,
        Color = ColorSequence.new(Color3.fromHex("#ABABAB"))
    },
	User = {
        Enabled = true,
        Anonymous = true,
    },
    Topbar = {
        Height = 44,
        ButtonsType = "Mac",
    },
}

if not IsLoggedIn then
    WindowConfig.KeySystem = {
        Enabled = true,
        SaveKey = true,
        Note = "MASUKKAN KEY: JEPINGANTENG",
        KeyValidator = function(key)
            if key == "JEPINGANTENG" then
                if writefile then
                    writefile(KEY_FILE, key)
                end
                IsLoggedIn = true
                
                task.delay(0.5, function()
                    WindUI:Notify({
                        Title = "POKAYCORE AUTH",
                        Content = "Key Benar! Selamat datang, Jeping Ganteng.",
                        Duration = 5,
                        Icon = "check-circle",
                    })
                end)
                
                return true
            else
                WindUI:Notify({
                    Title = "POKAYCORE AUTH",
                    Content = "Key Salah! Lu nggak seganteng Jeping ya?",
                    Duration = 6,
                    Icon = "x-circle",
                })
                return false
            end
        end
    }
end

local Window = WindUI:CreateWindow(WindowConfig)

if IsLoggedIn then
    Window:Open(true) 
else
    repeat task.wait() until IsLoggedIn
    task.wait(0.5)
end

-- =========================
-- COLORS (macOS Style)
-- =========================

local MacBlue      = Color3.fromRGB(0, 122, 255)      -- Account / Identity
local MacPurple    = Color3.fromRGB(175, 82, 222)     -- Bypass / Advanced
local MacGreen     = Color3.fromRGB(52, 199, 89)      -- Automation / Success
local MacOrange    = Color3.fromRGB(255, 149, 0)      -- Settings
local MacRed       = Color3.fromRGB(255, 59, 48)      -- Danger / Logout
local MacTeal      = Color3.fromRGB(90, 200, 250)     -- Social / Network
local MacPink      = Color3.fromRGB(255, 45, 85)      -- Creative
local MacYellow    = Color3.fromRGB(255, 204, 0)      -- Animation / Fun
local MacIndigo    = Color3.fromRGB(88, 86, 214)      -- System / Hardware
local MacMint      = Color3.fromRGB(0, 199, 190)      -- Custom / Identity
local MacCyan      = Color3.fromRGB(50, 173, 230)     -- Sky / Visual
local MacGray      = Color3.fromRGB(142, 142, 147)    -- Neutral / Credits
local MacSystemGray = Color3.fromRGB(72, 72, 74)

-- =========================
-- TABS (macOS Style)
-- =========================

local AccountTab = Window:Tab({
    Title = "Account",
    Icon = "user",
    IconColor = MacGray,
    IconShape = "Square",
    Border = true
})

local MusicTab = Window:Tab({
    Title = "Music",
    Icon = "music",
    IconColor = MacGray,
    IconShape = "Square",
    Border = true
})

local RecordTab = Window:Tab({
    Title = "AW | Recorder",
    Icon = "wand-sparkles",
    IconColor = MacGray,
    IconShape = "Square",
    Border = true
})

local AutowalkTab = Window:Tab({
    Title = "AW | Loader",
    Icon = "bot",
    IconColor = MacGray,
    IconShape = "Square",
    Border = true
})

local SocialTab = Window:Tab({
    Title = "Social Media",
    Icon = "globe",
    IconColor = MacGray,
    IconShape = "Square",
    Border = true
})

local CreditsTab = Window:Tab({
    Title = "Credits",
    Icon = "copyright",
    IconColor = MacGray,
    IconShape = "Square",
    Border = true
})

local SettingsTab = Window:Tab({
    Title = "Settings",
    Icon = "settings",
    IconColor = MacGray,
    IconShape = "Square",
    Border = true
})

local LogoutTab = Window:Tab({
    Title = "Logout",
    Icon = "log-out",
    IconColor = MacGray,
    IconShape = "Square",
    Border = true
})

AccountTab:Select()

-- =========================
-- ACCOUNT TAB
-- =========================
AccountTab:Section({
    Title = "RullzsyHUB | Account",
    TextSize = 18,
})

AccountTab:Divider()

local WelcomeParagraph = AccountTab:Paragraph({
    Title = "Hello, My Friend ð",
    Desc = "Loading..."
})

local InfoParagraph = AccountTab:Paragraph({
    Title = "User Information",
    Desc = "Loading..."
})

AccountTab:Divider()

-- =========================
-- FETCH USER DATA
-- =========================
local function FetchAccountData()
    if getgenv().AUTH_KEY == "" then
        InfoParagraph:SetDesc("â Key belum tersedia.")
        return
    end

    local url = API_CONFIG.base_url ..
        API_CONFIG.get_user_endpoint ..
        "?key=" .. HttpService:UrlEncode(getgenv().AUTH_KEY)

    local ok, res = safeHttpGet(url)
    if not ok then
        InfoParagraph:SetDesc("â Gagal mengambil data.")
        return
    end

    local data
    if not pcall(function()
        data = HttpService:JSONDecode(res)
    end) then
        InfoParagraph:SetDesc("â Response tidak valid.")
        return
    end

    if data.status ~= "success" then
        InfoParagraph:SetDesc("â " .. (data.message or "Unknown error"))
        return
    end

    local createdAt = formatDateTime(data.created_at)

    WelcomeParagraph:SetDesc("Welcome back again, " .. data.username)

    InfoParagraph:SetDesc(string.format(
        "â¢ User ID: %s\n" ..
        "â¢ Username: %s\n" ..
        "â¢ Role: [%s]\n" ..
        "â¢ Discord ID: %s\n" ..
        "â¢ Expire Key: %d Days\n" ..
        "â¢ Execute Count: %d\n" ..
        "â¢ Status Account: %s\n" ..
        "â¢ Created At: %s",
        data.user_id,
        data.username,
        string.upper(data.role),
        data.discord_id,
        data.expire_days,
        data.execute_count,
        data.whitelist_status,
        createdAt
    ))
end

task.spawn(FetchAccountData)

-- =========================
-- REFRESH BUTTON
-- =========================
AccountTab:Button({
    Title = "[â] Refresh Account",
	Icon = "refresh-ccw",
    Callback = function()
        FetchAccountData()
        WindUI:Notify({
            Title = "Account",
            Content = "Data akun berhasil diperbarui!",
            Duration = 3,
            Icon = "refresh-ccw",
        })
    end
})

-- ==========================================================
-- RullzsyHUB | Music Tab
-- ==========================================================
local JSON_URL     = "https://raw.githubusercontent.com/0x-rullzsy/collection_music/refs/heads/main/list_music.json"
local MUSIC_FOLDER = "Workspace/RullzsyHUB/Music_Collection"
local SCAN_INTERVAL = 2

local HttpService  = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")

if not isfolder("Workspace") then makefolder("Workspace") end
if not isfolder("Workspace/RullzsyHUB") then makefolder("Workspace/RullzsyHUB") end
if not isfolder(MUSIC_FOLDER) then makefolder(MUSIC_FOLDER) end

local existingFolder = SoundService:FindFirstChild("RullzsyHUB_Music")
if existingFolder then existingFolder:Destroy() end

local SoundFolder  = Instance.new("Folder")
SoundFolder.Name   = "RullzsyHUB_Music"
SoundFolder.Parent = SoundService

local MusicList = {}

local function loadMusicList()
    local fetchOk, rawJson = pcall(function() return game:HttpGet(JSON_URL) end)
    if fetchOk and rawJson and rawJson ~= "" then
        local decodeOk, result = pcall(function() return HttpService:JSONDecode(rawJson) end)
        if decodeOk and result and type(result) == "table" and #result > 0 then
            MusicList = result
            return
        end
    end
end

loadMusicList()
if #MusicList == 0 then return end

local function getLocalPath(track)
    local filename = (track.filename and track.filename ~= "") 
        and track.filename 
        or  track.name:gsub('[<>:"/\\|?*%%]', "_") .. ".mp3"
    return MUSIC_FOLDER .. "/" .. filename
end

local function isDownloaded(track)
    return isfile(getLocalPath(track))
end

local function downloadTrack(track, onSuccess, onFail)
    local path = getLocalPath(track)
    if isfile(path) then
        if onSuccess then onSuccess(path) end
        return
    end
    task.spawn(function()
        local ok, data = pcall(function() return game:HttpGet(track.url) end)
        if not ok or not data or data == "" then
            if onFail then onFail() end
            return
        end
        local wok = pcall(writefile, path, data)
        if wok then
            if onSuccess then onSuccess(path) end
        else
            if onFail then onFail() end
        end
    end)
end

local ScannedFiles = {}

local function scanMusicFolder()
    if not isfolder(MUSIC_FOLDER) then return end
    local ok, files = pcall(listfiles, MUSIC_FOLDER)
    if not ok or not files then return end
    for _, filePath in ipairs(files) do
        local fileName = filePath:match("([^/\\]+)$")
        if fileName and fileName:lower():match("%.mp3$") and not ScannedFiles[fileName] then
            local sok, assetUrl = pcall(getcustomasset, filePath, true)
            if sok and assetUrl then
                ScannedFiles[fileName] = assetUrl
            end
        end
    end
end

scanMusicFolder()
task.spawn(function()
    while true do
        task.wait(SCAN_INTERVAL)
        scanMusicFolder()
    end
end)

-- Music State
local MusicState = {
    SelectedIndex   = 1,
    PlayingIndex    = nil,
    IsPlaying       = false,
    IsPaused        = false,
    Volume          = 100,
    ShuffleEnabled  = false,
    RandomEnabled   = false,
    CurrentSound    = nil,
    IsDownloading   = false,
    PausedPosition  = 0,
    CustomAudioId   = "",
    IsCustomMode    = false,
    -- Random mode tracking: set of indices already played this cycle
    RandomPlayed    = {},
    RandomCycleSize = 0,
}

local soundEndedConn = nil

local function stopCurrentSound()
    if soundEndedConn then
        soundEndedConn:Disconnect()
        soundEndedConn = nil
    end
    if MusicState.CurrentSound then
        MusicState.CurrentSound:Stop()
        MusicState.CurrentSound:Destroy()
        MusicState.CurrentSound = nil
    end
    MusicState.IsPlaying    = false
    MusicState.IsPaused     = false
    MusicState.PlayingIndex = nil
end

local StatusParagraph = nil

local function getStatusText()
    local trackName
    if MusicState.IsCustomMode and MusicState.CurrentSound then
        trackName = MusicState.CurrentSound.Name
    elseif MusicState.PlayingIndex then
        trackName = MusicList[MusicState.PlayingIndex].name
    else
        trackName = "Tidak ada"
    end

    local playState
    if MusicState.IsDownloading then
        playState = "â¬ Downloading..."
    elseif MusicState.IsPlaying then
        playState = "â¶ Playing"
    elseif MusicState.IsPaused then
        playState = "â¸ Paused"
    else
        playState = "â¹ Stopped"
    end

    local modeStr
    if MusicState.ShuffleEnabled and MusicState.RandomEnabled then
        modeStr = "Shuffle + Random"
    elseif MusicState.ShuffleEnabled then
        modeStr = "Shuffle"
    elseif MusicState.RandomEnabled then
        modeStr = "Random"
    else
        modeStr = "Off"
    end

    return string.format(
        "Fitur ini anda dapat memutar lagu, jika ingin request lagu silahkan ke discord > ãâï¸ãrequest-music.\n\n" ..
        "|STATUS MUSIC|\n" ..
        " - Status: %s\n" ..
        " - Now Playing: %s\n" ..
        " - Volume: %s\n" ..
        " - Mode: %s",
        playState, trackName,
        tostring(MusicState.Volume),
        modeStr
    )
end

local function updateStatus()
    if StatusParagraph then
        StatusParagraph:SetDesc(getStatusText())
    end
end

-- ============================================================
-- Random queue logic
-- ============================================================
-- Reset random cycle (call when Random is toggled on, or cycle finishes)
local function resetRandomCycle()
    MusicState.RandomPlayed    = {}
    MusicState.RandomCycleSize = 0
end

-- Mark index as played in random cycle
local function markRandomPlayed(index)
    MusicState.RandomPlayed[index] = true
    MusicState.RandomCycleSize     = MusicState.RandomCycleSize + 1
end

-- Pick next random index excluding already-played ones
-- Returns nil if all tracks have been played (cycle complete)
local function getNextRandomIndex()
    if MusicState.RandomCycleSize >= #MusicList then
        -- All tracks played; reset and signal end
        return nil
    end

    local available = {}
    for i = 1, #MusicList do
        if not MusicState.RandomPlayed[i] then
            table.insert(available, i)
        end
    end

    if #available == 0 then return nil end

    local pick = available[math.random(1, #available)]
    return pick
end

-- ============================================================
-- Determine what to play after current track ends
-- ============================================================
local function getNextIndex(currentIndex)
    -- Shuffle only (loop current track)
    if MusicState.ShuffleEnabled and not MusicState.RandomEnabled then
        return currentIndex  -- repeat same track
    end

    -- Random only (no shuffle): play random without repeat; stop when all played
    if MusicState.RandomEnabled and not MusicState.ShuffleEnabled then
        local next = getNextRandomIndex()
        if next then
            markRandomPlayed(next)
            return next
        else
            -- Cycle done â stop playback
            return nil
        end
    end

    -- Shuffle + Random: play random without repeat; when all done restart cycle (loop)
    if MusicState.ShuffleEnabled and MusicState.RandomEnabled then
        local next = getNextRandomIndex()
        if next then
            markRandomPlayed(next)
            return next
        else
            -- Cycle done â restart cycle from beginning (loop all)
            resetRandomCycle()
            local restart = getNextRandomIndex()
            if restart then
                markRandomPlayed(restart)
                return restart
            end
            return nil
        end
    end

    -- Neither enabled: just stop (no auto-next by default when both off)
    return nil
end

-- Forward declaration
local playMusic

-- Custom ID Play
local function playCustomAudio(audioId)
    local cleanId = tostring(audioId):gsub("%D", "")
    if cleanId == "" then
        WindUI:Notify({ Title = "Error", Content = "ID tidak valid!", Duration = 3, Icon = "alert-circle" })
        return
    end

    stopCurrentSound()

    local s = Instance.new("Sound")
    s.Name    = "Custom ID: " .. cleanId
    s.SoundId = "rbxassetid://" .. cleanId
    s.Volume  = MusicState.Volume / 100
    s.Looped  = false
    s.Parent  = SoundFolder
    s:Play()

    MusicState.CurrentSound  = s
    MusicState.IsPlaying     = true
    MusicState.IsPaused      = false
    MusicState.IsCustomMode  = true
    MusicState.PlayingIndex  = nil
    updateStatus()

    WindUI:Notify({ Title = "Custom ID", Content = "â¶ Playing ID: " .. cleanId, Duration = 3, Icon = "play" })

    if soundEndedConn then soundEndedConn:Disconnect() end
    soundEndedConn = s.Ended:Connect(function()
        if not MusicState.IsPlaying then return end

        -- Logika mode untuk Custom ID:
        -- Shuffle saja (tanpa Random)       â loop custom id terus
        -- Random saja (tanpa Shuffle)       â tidak berfungsi, stop saja
        -- Shuffle + Random                  â hanya shuffle berlaku, loop custom id
        -- Keduanya off                      â stop
        if MusicState.ShuffleEnabled then
            -- Shuffle aktif (dengan atau tanpa Random): ulangi custom id terus
            task.wait(0.5)
            if not MusicState.IsPlaying then return end  -- sudah di-stop manual, jangan lanjut
            s.TimePosition = 0
            s:Play()
            updateStatus()
        else
            -- Random saja atau keduanya off: stop, tidak lanjut
            MusicState.IsPlaying    = false
            MusicState.IsCustomMode = false
            updateStatus()
        end
    end)
end

local function waitForScanThenPlay(track, index, timeout)
    timeout = timeout or 15
    local filename = (track.filename and track.filename ~= "")
        and track.filename
        or  track.name:gsub('[<>:"/\\|?*%%]', "_") .. ".mp3"

    task.spawn(function()
        local elapsed = 0
        while elapsed < timeout do
            if ScannedFiles[filename] then
                local s = Instance.new("Sound")
                s.Name    = track.name
                s.SoundId = ScannedFiles[filename]
                s.Volume  = MusicState.Volume / 100
                s.Looped  = false
                s.Parent  = SoundFolder
                s:Play()

                MusicState.CurrentSound  = s
                MusicState.PlayingIndex  = index
                MusicState.SelectedIndex = index
                MusicState.IsPlaying     = true
                MusicState.IsPaused      = false
                MusicState.IsDownloading = false
                MusicState.IsCustomMode  = false
                updateStatus()

                WindUI:Notify({ Title = "Music Player", Content = "â¶ Now Playing: " .. track.name, Duration = 3, Icon = "play" })

                if soundEndedConn then soundEndedConn:Disconnect() end
                soundEndedConn = s.Ended:Connect(function()
                    if not MusicState.IsPlaying then return end

                    MusicState.IsPlaying    = false
                    MusicState.PlayingIndex = nil
                    MusicState.CurrentSound = nil

                    local nextIndex = getNextIndex(index)
                    if nextIndex then
                        task.wait(0.5)
                        playMusic(nextIndex)
                    else
                        updateStatus()
                    end
                end)
                return
            end
            task.wait(0.5)
            elapsed = elapsed + 0.5
        end

        MusicState.IsDownloading = false
        updateStatus()
        WindUI:Notify({ Title = "Music Player", Content = "â Gagal load: " .. track.name, Duration = 4, Icon = "alert-circle" })
    end)
end

playMusic = function(index)
    if MusicState.IsDownloading then
        WindUI:Notify({ Title = "Music Player", Content = "â¬ Sedang proses download...", Duration = 3, Icon = "loader" })
        return
    end

    local track = MusicList[index]
    if not track then return end

    stopCurrentSound()

    MusicState.IsDownloading = true
    MusicState.PlayingIndex  = index
    MusicState.SelectedIndex = index
    MusicState.IsCustomMode  = false
    updateStatus()

    local filename = (track.filename and track.filename ~= "")
        and track.filename
        or  track.name:gsub('[<>:"/\\|?*%%]', "_") .. ".mp3"

    if ScannedFiles[filename] then
        MusicState.IsDownloading = false

        local s = Instance.new("Sound")
        s.Name    = track.name
        s.SoundId = ScannedFiles[filename]
        s.Volume  = MusicState.Volume / 100
        s.Looped  = false
        s.Parent  = SoundFolder
        s:Play()

        MusicState.CurrentSound = s
        MusicState.IsPlaying    = true
        MusicState.IsPaused     = false
        updateStatus()

        WindUI:Notify({ Title = "Music Player", Content = "â¶ Now Playing: " .. track.name, Duration = 3, Icon = "play" })

        if soundEndedConn then soundEndedConn:Disconnect() end
        soundEndedConn = s.Ended:Connect(function()
            if not MusicState.IsPlaying then return end

            MusicState.IsPlaying    = false
            MusicState.PlayingIndex = nil
            MusicState.CurrentSound = nil

            local nextIndex = getNextIndex(index)
            if nextIndex then
                task.wait(0.5)
                playMusic(nextIndex)
            else
                updateStatus()
            end
        end)
        return
    end

    WindUI:Notify({
        Title    = "Music Player",
        Content  = isDownloaded(track)
            and ("â³ Loading: " .. track.name)
            or  ("â¬ Downloading: " .. track.name),
        Duration = 5,
        Icon     = "loader",
    })

    downloadTrack(track,
        function() waitForScanThenPlay(track, index, 15) end,
        function()
            MusicState.IsDownloading = false
            MusicState.PlayingIndex  = nil
            updateStatus()
            WindUI:Notify({ Title = "Music Player", Content = "â Gagal download: " .. track.name, Duration = 4, Icon = "alert-circle" })
        end
    )
end

-- Build dropdown
-- Urutan: [1] None, [2] [ Custom ID], [3+] preset dari JSON
local dropdownValues = { "â None â", "[ Custom ID]" }
for _, track in ipairs(MusicList) do
    local suffix = isDownloaded(track) and " [â downloaded]" or ""
    table.insert(dropdownValues, track.name .. suffix)
end

-- SOURCE OF TRUTH: satu-satunya penentu mode, tidak bisa korupsi
local currentDropdownValue = "â None â"  -- default: None, user wajib pilih dulu

-- UI Setup
MusicTab:Section({ Title = "RullzsyHUB | Music", TextSize = 18, TextXAlignment = "Left" })
MusicTab:Divider()

StatusParagraph = MusicTab:Paragraph({ Title = "Music Player", Desc = getStatusText() })

MusicTab:Section({ Title = "List Music", TextSize = 17, TextXAlignment = "Left" })
MusicTab:Divider()

MusicTab:Dropdown({
    Title    = "[â] Select Music",
    SearchBarEnabled = true,
    Values   = dropdownValues,
    Value    = "â None â",
    Callback = function(state)
        if not state then return end

        -- Simpan selalu, ini sumber kebenaran
        currentDropdownValue = state

        if state == "â None â" then
            MusicState.IsCustomMode  = false
            MusicState.SelectedIndex = nil
            updateStatus()
            return
        end

        if state == "[ Custom ID]" then
            MusicState.IsCustomMode  = true
            MusicState.SelectedIndex = nil
            updateStatus()
            return
        end

        MusicState.IsCustomMode = false

        local cleanName = state:gsub(" %[â downloaded%]$", "")
        local selectedIdx = nil
        for i, track in ipairs(MusicList) do
            if track.name == cleanName then
                selectedIdx = i
                break
            end
        end

        if not selectedIdx then return end

        if (MusicState.IsPlaying or MusicState.IsPaused)
            and MusicState.PlayingIndex ~= nil
            and MusicState.PlayingIndex ~= selectedIdx
        then
            WindUI:Notify({ Title = "Music Player", Content = 'â  Stop dulu sebelum ganti!', Duration = 4, Icon = "alert-circle" })
            return
        end

        if MusicState.IsDownloading then
            WindUI:Notify({ Title = "Music Player", Content = "â¬ Sedang proses download...", Duration = 3, Icon = "loader" })
            return
        end

        MusicState.SelectedIndex = selectedIdx
        updateStatus()
    end
})

-- Custom Audio ID Input
-- FIX: Setiap kali input berubah, flag dirty agar Play tahu harus buat Sound baru
local customIdDirty = false

MusicTab:Input({
    Title       = "[â] Custom ID",
    Value       = "",
    Placeholder = "Enter ID Music",
    Desc = "Masukkan ID audio Roblox",
    Callback    = function(value)
        -- Jika id berubah dari yang sedang playing, tandai dirty
        if value ~= MusicState.CustomAudioId then
            MusicState.CustomAudioId = value
            customIdDirty = true
        end
    end
})

MusicTab:Toggle({
    Title    = "[â] Shuffle",
    Value    = false,
    Callback = function(state)
        MusicState.ShuffleEnabled = state
        updateStatus()
        WindUI:Notify({ Title = "Shuffle", Content = state and "Shuffle On" or "Shuffle Off", Duration = 3, Icon = "shuffle" })
    end
})

MusicTab:Toggle({
    Title    = "[â] Random",
    Value    = false,
    Callback = function(state)
        MusicState.RandomEnabled = state
        if state then
            -- Reset cycle so it starts fresh
            resetRandomCycle()
            -- Pre-mark currently playing track if any, so it doesn't repeat immediately
            if MusicState.PlayingIndex then
                markRandomPlayed(MusicState.PlayingIndex)
            end
        end
        updateStatus()
        WindUI:Notify({ Title = "Random", Content = state and "Random On" or "Random Off", Duration = 3, Icon = "shuffle" })
    end
})

MusicTab:Slider({
    Title = "[â] Volume",
    Step  = 1,
    Value = { Min = 0, Max = 100, Default = 100 },
    Callback = function(value)
        MusicState.Volume = value
        if MusicState.CurrentSound then
            MusicState.CurrentSound.Volume = value / 100
        end
        updateStatus()
    end
})

MusicTab:Divider()

MusicTab:Button({
    Title    = "[â] Play Music",
    Icon     = "play",
    Callback = function()
        -- Gunakan currentDropdownValue sebagai satu-satunya penentu mode (tidak bisa korupsi)
        local isCustomMode = (currentDropdownValue == "[ Custom ID]")
        local isNone       = (currentDropdownValue == "â None â")

        -- Validasi: user belum pilih apapun
        if isNone then
            WindUI:Notify({ Title = "Music Player", Icon = "triangle-alert",  Content = "Pilih lagu atau Custom ID dulu!", Duration = 3, Icon = "alert-circle" })
            return
        end

        if isCustomMode then
            if MusicState.CustomAudioId == "" then
                WindUI:Notify({ Title = "Music Player", Icon = "triangle-alert", Content = "Masukkan ID audio dulu!", Duration = 3, Icon = "alert-circle" })
                return
            end

            -- Resume jika sedang di-pause DAN id tidak berubah
            if MusicState.IsPaused and MusicState.CurrentSound and not customIdDirty then
                MusicState.CurrentSound.TimePosition = MusicState.PausedPosition
                MusicState.CurrentSound:Play()
                MusicState.IsPlaying      = true
                MusicState.IsPaused       = false
                MusicState.PausedPosition = 0
                updateStatus()
                WindUI:Notify({ Title = "Custom ID", Content = "â¶ Dilanjutkan", Duration = 2, Icon = "play" })
                return
            end

            -- Selalu play ulang: id dirty, tidak ada sound, atau belum playing
            customIdDirty = false
            playCustomAudio(MusicState.CustomAudioId)
            return
        end

        local idx = MusicState.SelectedIndex
        if not idx then
            WindUI:Notify({ Title = "Music Player", Content = "â  Pilih lagu dulu!", Duration = 3, Icon = "alert-circle" })
            return
        end

        if MusicState.IsDownloading then
            WindUI:Notify({ Title = "Music Player", Content = "â¬ Sedang proses...", Duration = 3, Icon = "loader" })
            return
        end

        if MusicState.IsPaused and MusicState.CurrentSound and MusicState.PlayingIndex == idx then
            MusicState.CurrentSound.TimePosition = MusicState.PausedPosition
            MusicState.CurrentSound:Play()
            MusicState.IsPlaying      = true
            MusicState.IsPaused       = false
            MusicState.PausedPosition = 0
            updateStatus()
            WindUI:Notify({ Title = "Music Player", Content = "â¶ Dilanjutkan: " .. MusicList[idx].name, Duration = 3, Icon = "play" })
            return
        end

        if MusicState.IsPlaying and MusicState.PlayingIndex == idx then
            WindUI:Notify({ Title = "Music Player", Content = "Musik sudah diputar", Duration = 3, Icon = "info" })
            return
        end

        if (MusicState.IsPlaying or MusicState.IsPaused)
            and MusicState.PlayingIndex ~= nil
            and MusicState.PlayingIndex ~= idx
        then
            WindUI:Notify({ Title = "Music Player", Content = 'â  Stop dulu sebelum ganti!', Duration = 4, Icon = "alert-circle" })
            return
        end

        -- Setup random cycle when user manually picks a track
        if MusicState.RandomEnabled or (MusicState.ShuffleEnabled and MusicState.RandomEnabled) then
            resetRandomCycle()
            markRandomPlayed(idx)
        end

        playMusic(idx)
    end
})

MusicTab:Button({
    Title    = "[â] Pause Music",
    Icon     = "pause",
    Callback = function()
        if not MusicState.IsPlaying or not MusicState.CurrentSound then
            WindUI:Notify({ Title = "Music Player", Content = "Tidak ada musik yang diputar.", Duration = 3, Icon = "pause" })
            return
        end

        local savedPos = MusicState.CurrentSound.TimePosition or 0
        local pausedIdx = MusicState.PlayingIndex

        MusicState.CurrentSound:Stop()
        MusicState.IsPlaying      = false
        MusicState.IsPaused       = true
        MusicState.PausedPosition = savedPos
        updateStatus()

        local name = MusicState.IsCustomMode
            and MusicState.CurrentSound.Name
            or  (pausedIdx and MusicList[pausedIdx].name or "Unknown")

        WindUI:Notify({ Title = "Music Player", Content = "â¸ Dipaused: " .. name, Duration = 3, Icon = "pause" })
    end
})

MusicTab:Button({
    Title    = "[â] Stop Music",
    Icon     = "square",
    Callback = function()
        if not MusicState.CurrentSound and not MusicState.IsPaused and not MusicState.IsDownloading then
            WindUI:Notify({ Title = "Music Player", Content = "Tidak ada musik.", Duration = 3, Icon = "square" })
            return
        end

        local stoppedName = MusicState.IsCustomMode and (MusicState.CurrentSound and MusicState.CurrentSound.Name or "Custom ID")
            or (MusicState.PlayingIndex and MusicList[MusicState.PlayingIndex].name or "Unknown")

        MusicState.IsDownloading = false
        MusicState.IsCustomMode  = false
        -- Reset random cycle on manual stop
        resetRandomCycle()
        customIdDirty = false
        stopCurrentSound()
        updateStatus()

        WindUI:Notify({ Title = "Music Player", Content = "â¹ Dihentikan: " .. stoppedName, Duration = 3, Icon = "square" })
    end
})

MusicTab:Divider()

-- Auto update status
task.spawn(function()
    while true do
        task.wait(1)
        updateStatus()
    end
end)

-- ==========================================================
-- SETUP MUSIC TAB - END
-- ==========================================================

-- =========================
-- AUTO WALK | RECORDER TAB
-- =========================
local function setupRecordTab()

	local Section = RecordTab:Section({ 
		Title = "RullzsyHUB | Recorder",
		TextSize = 18,
	})

	RecordTab:Divider()

	local Paragraph = RecordTab:Paragraph({
		Title = "Recorder Menu",
		Desc = "Fitur ini anda dapat merakam jalur auto walk, tinggal anda click aja Load Recorder nanti secara otomatis muncul menu nya.",
	})

	RecordTab:Divider()

	local Toggle = RecordTab:Toggle({
		Title = "[â] Load Recorder",
		Value = false,
		Callback = function(state) 
			if state then
				if recorderLoaded then
					WindUI:Notify({
						Title = "AW | Recorder",
						Content = "Recorder sudah di-load sebelumnya!",
						Duration = 3,
						Icon = "circle-dot",
					})
					return
				end
				recorderLoaded = true
				WindUI:Notify({
					Title = "AW | Recorder",
					Content = "Berhasil di load!",
					Duration = 3,
					Icon = "circle-dot",
				})
 
				-- ============================================================
				-- AKA RECORDER â INLINE (Migrated from AKA.lua)
				-- ============================================================
				task.spawn(function()
 
				-- Services
				local REC_RunService = game:GetService("RunService")
				local REC_UserInputService = game:GetService("UserInputService")
				local REC_TweenService = game:GetService("TweenService")
				local REC_CoreGui = game:GetService("CoreGui")
 
				-- Player & Character
				local REC_LocalPlayer = Players.LocalPlayer
				local REC_Character = REC_LocalPlayer.Character or REC_LocalPlayer.CharacterAdded:Wait()
				local REC_Humanoid = REC_Character:WaitForChild("Humanoid")
				local REC_HumanoidRootPart = REC_Character:WaitForChild("HumanoidRootPart")
 
				-- Folder untuk menyimpan data
				local CHECKPOINT_FOLDER = "RHUB_AUTOWALK_RECORDER"
				if not isfolder(CHECKPOINT_FOLDER) then
					makefolder(CHECKPOINT_FOLDER)
				end
 
				-- Visualizer State
				local VISUALIZER_FOLDER_NAME = "RullzsyVisualizer"
				local activeVisuals = {}
 
				local VisualizerFolder = workspace:FindFirstChild(VISUALIZER_FOLDER_NAME)
				if not VisualizerFolder then
					VisualizerFolder = Instance.new("Folder")
					VisualizerFolder.Name = VISUALIZER_FOLDER_NAME
					VisualizerFolder.Parent = workspace
				end
 
				-- Recording State
				local isRecording = false
				local isWaitingForMovement = false
				local isPlaying = false
				local recordedData = {}
				local recordStartTime = 0
				local playStartTime = 0
				local playConnection = nil
 
				-- Playback Settings
				local playbackSpeed = 1
				local isLooping = false
				local playbackOffset = 0
				local lastSampleTime = 0
				local lastRecordedPosition = nil
 
				-- Saved Position
				local savedPosition = nil
				local SAVED_POS_FILE = CHECKPOINT_FOLDER .. "/_lastpos.json"
 
				-- Anti-Fall Settings
				local antiFallEnabled = false
				local FALL_THRESHOLD = 20
				local lastSafePosition = nil
				local realSafePosition = nil
				local realSafeCFrame = nil
				local lastSafeIndex = 0
				local isRecovering = false
				local BUFFER_FRAMES = 3
 
				-- Editor State
				local currentEditingCheckpoint = nil
				local currentEditingData = nil
				local selectedNodePart = nil
				local selectedNodeIndex = 0
				local editStepSize = 0.5
 
				-- Tool Tracking State
				local lastRecordedTool = nil
				local toolLockEnabled = false
				local toolLockConnection = nil
 
				-- State Change Management
				local lastPlaybackState = nil
				local lastStateChangeTime = 0
				local STATE_CHANGE_COOLDOWN = 0.08
				local JUMP_VELOCITY_THRESHOLD = 10
 
				-- Custom Record Keybind
				local recordKeybind = Enum.KeyCode.F
				local isBindingKey = false
 
				-- God Mode
				local godModeEnabled = false
				local originalMaxHealth = 100
				local healthConnection = nil
				local stateConnection = nil
 
				-- Smoothing & Physics
				local minSampleDistance = 0.05
				local isGrounded = false
				local lastJumpTime = 0
				local landingCooldown = 0
 
				-- UI Constants
				local SAMPLE_RATE = 60
				local SAMPLE_INTERVAL = 1 / SAMPLE_RATE
				local currentSampleTime = 0
 
				-- Anti-Idle Tracking
				local wasMoving = false
 
				-- Recording Dot
				local recordingIndicator = nil
				local indicatorBlinking = false
 
				-- Font
				local UIFont = Font.new("rbxasset://fonts/families/GothamSSm.json")
 
				-- Color Scheme (Gray Theme)
				local Colors = {
					background = Color3.fromRGB(22, 22, 24),
					secondary = Color3.fromRGB(32, 32, 35),
					accent = Color3.fromRGB(110, 110, 120),
					accentHover = Color3.fromRGB(90, 90, 100),
					accentLight = Color3.fromRGB(160, 160, 170),
					border = Color3.fromRGB(55, 55, 62),
					text = Color3.fromRGB(240, 240, 245),
					textDim = Color3.fromRGB(140, 140, 150),
					success = Color3.fromRGB(80, 200, 120),
					warning = Color3.fromRGB(200, 170, 80),
					error = Color3.fromRGB(180, 80, 80),
					beamWalk = Color3.fromRGB(200, 200, 210),
					beamJump = Color3.fromRGB(160, 120, 200),
					nodeSelected = Color3.fromRGB(100, 220, 255)
				}
 
				-- Create ScreenGui
				local ScreenGui = Instance.new("ScreenGui")
				ScreenGui.Name = "RullzsyHUB_Recorder"
				ScreenGui.ResetOnSpawn = false
				ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
				pcall(function() ScreenGui.Parent = REC_CoreGui end)
				if ScreenGui.Parent ~= REC_CoreGui then
					ScreenGui.Parent = REC_LocalPlayer:WaitForChild("PlayerGui")
				end
 
				-- ==========================================================
				-- NOTIFICATION SYSTEM
				-- ==========================================================
				local NotificationFrame = Instance.new("Frame")
				NotificationFrame.Name = "NotificationFrame"
				NotificationFrame.Size = UDim2.new(0, 200, 0, 40)
				NotificationFrame.Position = UDim2.new(0.5, -100, 0, -50)
				NotificationFrame.BackgroundColor3 = Colors.secondary
				NotificationFrame.BorderSizePixel = 0
				NotificationFrame.ZIndex = 2000
				NotificationFrame.Parent = ScreenGui
 
				local NotifCorner = Instance.new("UICorner")
				NotifCorner.CornerRadius = UDim.new(0, 8)
				NotifCorner.Parent = NotificationFrame
 
				local NotifStroke = Instance.new("UIStroke")
				NotifStroke.Color = Colors.border
				NotifStroke.Thickness = 1
				NotifStroke.Parent = NotificationFrame
 
				local NotifLabel = Instance.new("TextLabel")
				NotifLabel.Size = UDim2.new(1, 0, 1, 0)
				NotifLabel.BackgroundTransparency = 1
				NotifLabel.Text = "Notification"
				NotifLabel.TextColor3 = Colors.text
				NotifLabel.TextSize = 14
				NotifLabel.Font = Enum.Font.Gotham
				NotifLabel.ZIndex = 2001
				NotifLabel.Parent = NotificationFrame
 
				local currentNotifTween = nil
 
				local function showNotification(text, color)
					if currentNotifTween then currentNotifTween:Cancel() end
					NotifLabel.Text = text
					NotifStroke.Color = color or Colors.text
					NotifLabel.TextColor3 = color or Colors.text
					NotificationFrame.Position = UDim2.new(0.5, -100, 0, -50)
					NotificationFrame.BackgroundTransparency = 0
					NotifLabel.TextTransparency = 0
					NotifStroke.Transparency = 0
					local tweenIn = REC_TweenService:Create(NotificationFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
						Position = UDim2.new(0.5, -100, 0, 30)
					})
					tweenIn:Play()
					currentNotifTween = tweenIn
					task.delay(1.5, function()
						if NotifLabel.Text == text then
							local tweenOut = REC_TweenService:Create(NotificationFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
								Position = UDim2.new(0.5, -100, 0, -50),
								BackgroundTransparency = 1
							})
							local tweenText = REC_TweenService:Create(NotifLabel, TweenInfo.new(0.3), {TextTransparency = 1})
							local tweenStroke = REC_TweenService:Create(NotifStroke, TweenInfo.new(0.3), {Transparency = 1})
							tweenOut:Play(); tweenText:Play(); tweenStroke:Play()
						end
					end)
				end
 
				-- ==========================================================
				-- MAIN FRAME
				-- ==========================================================
				local MainFrame = Instance.new("Frame")
				MainFrame.Size = UDim2.new(0, 300, 0, 650)
				MainFrame.Position = UDim2.new(0.5, -140, 0.5, -325)
				MainFrame.BackgroundColor3 = Colors.background
				MainFrame.BorderSizePixel = 0
				MainFrame.Active = true
				MainFrame.ClipsDescendants = true
				MainFrame.Parent = ScreenGui
 
				local Shadow = Instance.new("ImageLabel")
				Shadow.Name = "Shadow"
				Shadow.Size = UDim2.new(1, 30, 1, 30)
				Shadow.Position = UDim2.new(0, -15, 0, -15)
				Shadow.BackgroundTransparency = 1
				Shadow.Image = "rbxassetid://1316045217"
				Shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
				Shadow.ImageTransparency = 0.7
				Shadow.ZIndex = 0
				Shadow.Parent = MainFrame
 
				local Corner = Instance.new("UICorner")
				Corner.CornerRadius = UDim.new(0, 12)
				Corner.Parent = MainFrame
 
				local Stroke = Instance.new("UIStroke")
				Stroke.Color = Colors.accent
				Stroke.Thickness = 2
				Stroke.Transparency = 0.3
				Stroke.Parent = MainFrame
 
				-- Title Bar
				local TitleBar = Instance.new("Frame")
				TitleBar.Size = UDim2.new(1, 0, 0, 45)
				TitleBar.BackgroundColor3 = Colors.secondary
				TitleBar.BorderSizePixel = 0
				TitleBar.Parent = MainFrame
 
				local TitleCorner = Instance.new("UICorner")
				TitleCorner.CornerRadius = UDim.new(0, 12)
				TitleCorner.Parent = TitleBar
 
				local TitleLabel = Instance.new("TextLabel")
				TitleLabel.Size = UDim2.new(1, -130, 1, 0)
				TitleLabel.Position = UDim2.new(0, 10, 0, 0)
				TitleLabel.BackgroundTransparency = 1
				TitleLabel.Text = "RullzsyHUB - Recorder"
				TitleLabel.TextColor3 = Colors.text
				TitleLabel.TextSize = 16
				TitleLabel.FontFace = UIFont
				TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
				TitleLabel.Parent = TitleBar
 
				local CloseButton = Instance.new("TextButton")
				CloseButton.Size = UDim2.new(0, 35, 0, 35)
				CloseButton.Position = UDim2.new(1, -40, 0, 5)
				CloseButton.BackgroundColor3 = Colors.error
				CloseButton.BorderSizePixel = 0
				CloseButton.Text = "X"
				CloseButton.TextColor3 = Colors.text
				CloseButton.TextSize = 18
				CloseButton.FontFace = UIFont
				CloseButton.Parent = TitleBar
 
				local CloseCorner = Instance.new("UICorner")
				CloseCorner.CornerRadius = UDim.new(0, 8)
				CloseCorner.Parent = CloseButton
 
				local MinimizeButton = Instance.new("TextButton")
				MinimizeButton.Size = UDim2.new(0, 35, 0, 35)
				MinimizeButton.Position = UDim2.new(1, -80, 0, 5)
				MinimizeButton.BackgroundColor3 = Colors.border
				MinimizeButton.BorderSizePixel = 0
				MinimizeButton.Text = "â"
				MinimizeButton.TextColor3 = Colors.text
				MinimizeButton.TextSize = 20
				MinimizeButton.FontFace = UIFont
				MinimizeButton.Parent = TitleBar
 
				local MinCorner = Instance.new("UICorner")
				MinCorner.CornerRadius = UDim.new(0, 8)
				MinCorner.Parent = MinimizeButton
 
				-- ==========================================================
				-- CONTROLS PANEL
				-- ==========================================================
				local ControlsPanel = Instance.new("Frame")
				ControlsPanel.Size = UDim2.new(1, -24, 0, 358)
				ControlsPanel.Position = UDim2.new(0, 12, 0, 55)
				ControlsPanel.BackgroundColor3 = Colors.secondary
				ControlsPanel.BorderSizePixel = 0
				ControlsPanel.Parent = MainFrame
 
				local ControlsCorner = Instance.new("UICorner")
				ControlsCorner.CornerRadius = UDim.new(0, 10)
				ControlsCorner.Parent = ControlsPanel
 
				local ControlsStroke = Instance.new("UIStroke")
				ControlsStroke.Color = Colors.border
				ControlsStroke.Thickness = 1
				ControlsStroke.Transparency = 0.5
				ControlsStroke.Parent = ControlsPanel
 
				-- Row 1: Record + Resume Nearest
				local RecordButton = Instance.new("TextButton")
				RecordButton.Size = UDim2.new(0.5, -12, 0, 36)
				RecordButton.Position = UDim2.new(0, 8, 0, 8)
				RecordButton.BackgroundColor3 = Colors.accent
				RecordButton.BorderSizePixel = 0
				RecordButton.Text = "ð´ START RECORDING"
				RecordButton.TextColor3 = Colors.text
				RecordButton.TextSize = 10
				RecordButton.FontFace = UIFont
				RecordButton.Parent = ControlsPanel
 
				local RecordCorner = Instance.new("UICorner")
				RecordCorner.CornerRadius = UDim.new(0, 8)
				RecordCorner.Parent = RecordButton
 
				local RecordStroke = Instance.new("UIStroke")
				RecordStroke.Color = Colors.accentLight
				RecordStroke.Thickness = 1
				RecordStroke.Transparency = 0.5
				RecordStroke.Parent = RecordButton
 
				local ResumeNearestButton = Instance.new("TextButton")
				ResumeNearestButton.Size = UDim2.new(0.5, -12, 0, 36)
				ResumeNearestButton.Position = UDim2.new(0.5, 4, 0, 8)
				ResumeNearestButton.BackgroundColor3 = Colors.warning
				ResumeNearestButton.BorderSizePixel = 0
				ResumeNearestButton.Text = "ð¯ RESUME NEAREST"
				ResumeNearestButton.TextColor3 = Colors.text
				ResumeNearestButton.TextSize = 10
				ResumeNearestButton.FontFace = UIFont
				ResumeNearestButton.Parent = ControlsPanel
 
				local ResumeCorner = Instance.new("UICorner")
				ResumeCorner.CornerRadius = UDim.new(0, 8)
				ResumeCorner.Parent = ResumeNearestButton
 
				-- Row 2: Checkpoint Name + Save
				local CheckpointInput = Instance.new("TextBox")
				CheckpointInput.Size = UDim2.new(0.65, -10, 0, 32)
				CheckpointInput.Position = UDim2.new(0, 8, 0, 52)
				CheckpointInput.BackgroundColor3 = Colors.background
				CheckpointInput.BorderSizePixel = 0
				CheckpointInput.PlaceholderText = "Enter checkpoint name..."
				CheckpointInput.PlaceholderColor3 = Colors.textDim
				CheckpointInput.Text = ""
				CheckpointInput.TextColor3 = Colors.text
				CheckpointInput.TextSize = 12
				CheckpointInput.FontFace = UIFont
				CheckpointInput.ClearTextOnFocus = false
				CheckpointInput.Parent = ControlsPanel
 
				local InputCorner = Instance.new("UICorner")
				InputCorner.CornerRadius = UDim.new(0, 8)
				InputCorner.Parent = CheckpointInput
 
				local InputStroke = Instance.new("UIStroke")
				InputStroke.Color = Colors.border
				InputStroke.Thickness = 1
				InputStroke.Parent = CheckpointInput
 
				local SaveButton = Instance.new("TextButton")
				SaveButton.Size = UDim2.new(0.35, -10, 0, 32)
				SaveButton.Position = UDim2.new(0.65, 2, 0, 52)
				SaveButton.BackgroundColor3 = Colors.success
				SaveButton.BorderSizePixel = 0
				SaveButton.Text = "ð¾ Save"
				SaveButton.TextColor3 = Colors.text
				SaveButton.TextSize = 12
				SaveButton.FontFace = UIFont
				SaveButton.Parent = ControlsPanel
 
				local SaveCorner = Instance.new("UICorner")
				SaveCorner.CornerRadius = UDim.new(0, 8)
				SaveCorner.Parent = SaveButton
 
				-- Row 3: Speed + Loop + Anti-Fall
				local SettingsContainer = Instance.new("Frame")
				SettingsContainer.Size = UDim2.new(1, -16, 0, 36)
				SettingsContainer.Position = UDim2.new(0, 8, 0, 92)
				SettingsContainer.BackgroundTransparency = 1
				SettingsContainer.Parent = ControlsPanel
 
				local SpeedInput = Instance.new("TextBox")
				SpeedInput.Size = UDim2.new(0.3, 0, 1, 0)
				SpeedInput.Position = UDim2.new(0, 0, 0, 0)
				SpeedInput.BackgroundColor3 = Colors.background
				SpeedInput.BorderSizePixel = 0
				SpeedInput.PlaceholderText = "Speed"
				SpeedInput.PlaceholderColor3 = Colors.textDim
				SpeedInput.Text = tostring(playbackSpeed)
				SpeedInput.TextColor3 = Colors.text
				SpeedInput.TextSize = 11
				SpeedInput.FontFace = UIFont
				SpeedInput.Parent = SettingsContainer
 
				local SpeedCorner = Instance.new("UICorner")
				SpeedCorner.CornerRadius = UDim.new(0, 8)
				SpeedCorner.Parent = SpeedInput
 
				local SpeedStroke = Instance.new("UIStroke")
				SpeedStroke.Color = Colors.border
				SpeedStroke.Thickness = 1
				SpeedStroke.Parent = SpeedInput
 
				local LoopButton = Instance.new("TextButton")
				LoopButton.Size = UDim2.new(0.32, 0, 1, 0)
				LoopButton.Position = UDim2.new(0.33, 0, 0, 0)
				LoopButton.BackgroundColor3 = Colors.border
				LoopButton.BorderSizePixel = 0
				LoopButton.Text = "ð Loop"
				LoopButton.TextColor3 = Colors.text
				LoopButton.TextSize = 10
				LoopButton.FontFace = UIFont
				LoopButton.Parent = SettingsContainer
 
				local LoopCorner = Instance.new("UICorner")
				LoopCorner.CornerRadius = UDim.new(0, 8)
				LoopCorner.Parent = LoopButton
 
				local AntiFallButton = Instance.new("TextButton")
				AntiFallButton.Size = UDim2.new(0.32, 0, 1, 0)
				AntiFallButton.Position = UDim2.new(0.68, 0, 0, 0)
				AntiFallButton.BackgroundColor3 = Colors.border
				AntiFallButton.BorderSizePixel = 0
				AntiFallButton.Text = "ð¡ï¸ Safe: OFF"
				AntiFallButton.TextColor3 = Colors.text
				AntiFallButton.TextSize = 10
				AntiFallButton.FontFace = UIFont
				AntiFallButton.Parent = SettingsContainer
 
				local AntiFallCorner = Instance.new("UICorner")
				AntiFallCorner.CornerRadius = UDim.new(0, 8)
				AntiFallCorner.Parent = AntiFallButton
 
				-- Row 4: Sample Rate
				local SampleRateContainer = Instance.new("Frame")
				SampleRateContainer.Size = UDim2.new(1, -16, 0, 32)
				SampleRateContainer.Position = UDim2.new(0, 8, 0, 136)
				SampleRateContainer.BackgroundTransparency = 1
				SampleRateContainer.Parent = ControlsPanel
 
				local SampleRateLabel = Instance.new("TextLabel")
				SampleRateLabel.Size = UDim2.new(0.55, 0, 1, 0)
				SampleRateLabel.Position = UDim2.new(0, 0, 0, 0)
				SampleRateLabel.BackgroundTransparency = 1
				SampleRateLabel.Text = "ðï¸ Refresh Rate (Hz):"
				SampleRateLabel.TextColor3 = Colors.textDim
				SampleRateLabel.TextSize = 11
				SampleRateLabel.FontFace = UIFont
				SampleRateLabel.TextXAlignment = Enum.TextXAlignment.Left
				SampleRateLabel.Parent = SampleRateContainer
 
				local SampleRateInput = Instance.new("TextBox")
				SampleRateInput.Size = UDim2.new(0.4, 0, 1, 0)
				SampleRateInput.Position = UDim2.new(0.58, 0, 0, 0)
				SampleRateInput.BackgroundColor3 = Colors.background
				SampleRateInput.BorderSizePixel = 0
				SampleRateInput.Text = tostring(SAMPLE_RATE)
				SampleRateInput.PlaceholderText = "60"
				SampleRateInput.PlaceholderColor3 = Colors.textDim
				SampleRateInput.TextColor3 = Colors.text
				SampleRateInput.TextSize = 11
				SampleRateInput.FontFace = UIFont
				SampleRateInput.Parent = SampleRateContainer
 
				local SRCorner = Instance.new("UICorner")
				SRCorner.CornerRadius = UDim.new(0, 8)
				SRCorner.Parent = SampleRateInput
 
				local SRStroke = Instance.new("UIStroke")
				SRStroke.Color = Colors.border
				SRStroke.Thickness = 1
				SRStroke.Parent = SampleRateInput
 
				-- Row 5: Custom Record Keybind
				local KeybindContainer = Instance.new("Frame")
				KeybindContainer.Size = UDim2.new(1, -16, 0, 32)
				KeybindContainer.Position = UDim2.new(0, 8, 0, 176)
				KeybindContainer.BackgroundTransparency = 1
				KeybindContainer.Parent = ControlsPanel
 
				local KeybindLabel = Instance.new("TextLabel")
				KeybindLabel.Size = UDim2.new(0.52, 0, 1, 0)
				KeybindLabel.Position = UDim2.new(0, 0, 0, 0)
				KeybindLabel.BackgroundTransparency = 1
				KeybindLabel.Text = "ð® Record Keybind:"
				KeybindLabel.TextColor3 = Colors.textDim
				KeybindLabel.TextSize = 11
				KeybindLabel.FontFace = UIFont
				KeybindLabel.TextXAlignment = Enum.TextXAlignment.Left
				KeybindLabel.Parent = KeybindContainer
 
				local KeybindButton = Instance.new("TextButton")
				KeybindButton.Size = UDim2.new(0.45, 0, 1, 0)
				KeybindButton.Position = UDim2.new(0.55, 0, 0, 0)
				KeybindButton.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
				KeybindButton.BorderSizePixel = 0
				KeybindButton.Text = "[ " .. recordKeybind.Name .. " ]"
				KeybindButton.TextColor3 = Color3.fromRGB(180, 180, 195)
				KeybindButton.TextSize = 12
				KeybindButton.FontFace = UIFont
				KeybindButton.Parent = KeybindContainer
 
				local KeybindCorner = Instance.new("UICorner")
				KeybindCorner.CornerRadius = UDim.new(0, 8)
				KeybindCorner.Parent = KeybindButton
 
				local KeybindStroke = Instance.new("UIStroke")
				KeybindStroke.Color = Color3.fromRGB(90, 90, 105)
				KeybindStroke.Thickness = 1
				KeybindStroke.Parent = KeybindButton
 
				-- Row 6: Refresh + Stop Walk
				local RefreshButton = Instance.new("TextButton")
				RefreshButton.Size = UDim2.new(0.5, -12, 0, 34)
				RefreshButton.Position = UDim2.new(0, 8, 0, 216)
				RefreshButton.BackgroundColor3 = Colors.border
				RefreshButton.BorderSizePixel = 0
				RefreshButton.Text = "ð Refresh"
				RefreshButton.TextColor3 = Colors.text
				RefreshButton.TextSize = 12
				RefreshButton.FontFace = UIFont
				RefreshButton.Parent = ControlsPanel
 
				local RefreshCorner = Instance.new("UICorner")
				RefreshCorner.CornerRadius = UDim.new(0, 8)
				RefreshCorner.Parent = RefreshButton
 
				local StopWalkButton = Instance.new("TextButton")
				StopWalkButton.Size = UDim2.new(0.5, -12, 0, 34)
				StopWalkButton.Position = UDim2.new(0.5, 4, 0, 216)
				StopWalkButton.BackgroundColor3 = Colors.error
				StopWalkButton.BorderSizePixel = 0
				StopWalkButton.Text = "â  STOP WALK"
				StopWalkButton.TextColor3 = Colors.text
				StopWalkButton.TextSize = 14
				StopWalkButton.FontFace = UIFont
				StopWalkButton.Visible = false
				StopWalkButton.Parent = ControlsPanel
 
				local StopWalkCorner = Instance.new("UICorner")
				StopWalkCorner.CornerRadius = UDim.new(0, 8)
				StopWalkCorner.Parent = StopWalkButton
 
				-- Row 7: Save Pos + Load Pos
				local SavePosButton = Instance.new("TextButton")
				SavePosButton.Position = UDim2.new(0, 8, 0, 258)
				SavePosButton.Size = UDim2.new(0.5, -12, 0, 32)
				SavePosButton.BackgroundColor3 = Color3.fromRGB(65, 65, 75)
				SavePosButton.BorderSizePixel = 0
				SavePosButton.Text = "ð Save Pos"
				SavePosButton.TextColor3 = Colors.text
				SavePosButton.TextSize = 11
				SavePosButton.FontFace = UIFont
				SavePosButton.Parent = ControlsPanel
 
				local SavePosCorner = Instance.new("UICorner")
				SavePosCorner.CornerRadius = UDim.new(0, 8)
				SavePosCorner.Parent = SavePosButton
 
				local SavePosStroke = Instance.new("UIStroke")
				SavePosStroke.Color = Color3.fromRGB(110, 110, 125)
				SavePosStroke.Thickness = 1
				SavePosStroke.Transparency = 0.4
				SavePosStroke.Parent = SavePosButton
 
				local LoadPosButton = Instance.new("TextButton")
				LoadPosButton.Position = UDim2.new(0.5, 4, 0, 258)
				LoadPosButton.Size = UDim2.new(0.5, -12, 0, 32)
				LoadPosButton.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
				LoadPosButton.BorderSizePixel = 0
				LoadPosButton.Text = "ð Load Pos"
				LoadPosButton.TextColor3 = Colors.text
				LoadPosButton.TextSize = 11
				LoadPosButton.FontFace = UIFont
				LoadPosButton.Parent = ControlsPanel
 
				local LoadPosCorner = Instance.new("UICorner")
				LoadPosCorner.CornerRadius = UDim.new(0, 8)
				LoadPosCorner.Parent = LoadPosButton
 
				local LoadPosStroke = Instance.new("UIStroke")
				LoadPosStroke.Color = Color3.fromRGB(100, 100, 115)
				LoadPosStroke.Thickness = 1
				LoadPosStroke.Transparency = 0.4
				LoadPosStroke.Parent = LoadPosButton
 
				local LastPosLabel = Instance.new("TextLabel")
				LastPosLabel.Size = UDim2.new(1, -50, 0, 18)
				LastPosLabel.Position = UDim2.new(0, 8, 0, 298)
				LastPosLabel.BackgroundTransparency = 1
				LastPosLabel.Text = "ð No position saved"
				LastPosLabel.TextColor3 = Colors.textDim
				LastPosLabel.TextSize = 10
				LastPosLabel.FontFace = UIFont
				LastPosLabel.TextXAlignment = Enum.TextXAlignment.Left
				LastPosLabel.TextTruncate = Enum.TextTruncate.AtEnd
				LastPosLabel.Parent = ControlsPanel
 
				-- Clear Visuals Button
				local ClearVisualsButton = Instance.new("TextButton")
				ClearVisualsButton.Size = UDim2.new(0, 32, 0, 32)
				ClearVisualsButton.Position = UDim2.new(1, -40, 0, 322)
				ClearVisualsButton.BackgroundColor3 = Colors.border
				ClearVisualsButton.BorderSizePixel = 0
				ClearVisualsButton.Text = "ðï¸"
				ClearVisualsButton.TextColor3 = Colors.text
				ClearVisualsButton.TextSize = 16
				ClearVisualsButton.FontFace = UIFont
				ClearVisualsButton.Parent = ControlsPanel
 
				local ClearVisCorner = Instance.new("UICorner")
				ClearVisCorner.CornerRadius = UDim.new(0, 8)
				ClearVisCorner.Parent = ClearVisualsButton
 
				-- Row 8: Search
				local SearchInput = Instance.new("TextBox")
				SearchInput.Size = UDim2.new(1, -52, 0, 32)
				SearchInput.Position = UDim2.new(0, 8, 0, 322)
				SearchInput.BackgroundColor3 = Colors.background
				SearchInput.BorderSizePixel = 0
				SearchInput.PlaceholderText = "ð Search checkpoints..."
				SearchInput.PlaceholderColor3 = Colors.textDim
				SearchInput.Text = ""
				SearchInput.TextColor3 = Colors.text
				SearchInput.TextSize = 12
				SearchInput.FontFace = UIFont
				SearchInput.Parent = ControlsPanel
 
				local SearchCorner = Instance.new("UICorner")
				SearchCorner.CornerRadius = UDim.new(0, 8)
				SearchCorner.Parent = SearchInput
 
				local SearchStroke = Instance.new("UIStroke")
				SearchStroke.Color = Colors.border
				SearchStroke.Thickness = 1
				SearchStroke.Parent = SearchInput
 
				-- ==========================================================
				-- CHECKPOINT LIST
				-- ==========================================================
				local CheckpointLabel = Instance.new("Frame")
				CheckpointLabel.Size = UDim2.new(1, -24, 0, 24)
				CheckpointLabel.Position = UDim2.new(0, 12, 0, 421)
				CheckpointLabel.BackgroundColor3 = Colors.secondary
				CheckpointLabel.BorderSizePixel = 0
				CheckpointLabel.Parent = MainFrame
 
				local CheckpointLabelCorner = Instance.new("UICorner")
				CheckpointLabelCorner.CornerRadius = UDim.new(0, 8)
				CheckpointLabelCorner.Parent = CheckpointLabel
 
				local CheckpointLabelText = Instance.new("TextLabel")
				CheckpointLabelText.Size = UDim2.new(1, -20, 1, 0)
				CheckpointLabelText.Position = UDim2.new(0, 10, 0, 0)
				CheckpointLabelText.BackgroundTransparency = 1
				CheckpointLabelText.Text = "ð Saved Checkpoints"
				CheckpointLabelText.TextColor3 = Colors.text
				CheckpointLabelText.TextSize = 13
				CheckpointLabelText.FontFace = UIFont
				CheckpointLabelText.TextXAlignment = Enum.TextXAlignment.Left
				CheckpointLabelText.Parent = CheckpointLabel
 
				local CheckpointList = Instance.new("ScrollingFrame")
				CheckpointList.Size = UDim2.new(1, -24, 1, -478)
				CheckpointList.Position = UDim2.new(0, 12, 0, 453)
				CheckpointList.BackgroundColor3 = Colors.secondary
				CheckpointList.BorderSizePixel = 0
				CheckpointList.ScrollBarThickness = 8
				CheckpointList.ScrollBarImageColor3 = Colors.accent
				CheckpointList.CanvasSize = UDim2.new(0, 0, 0, 0)
				CheckpointList.Parent = MainFrame
 
				local ListCorner = Instance.new("UICorner")
				ListCorner.CornerRadius = UDim.new(0, 6)
				ListCorner.Parent = CheckpointList
 
				local ListStroke = Instance.new("UIStroke")
				ListStroke.Color = Colors.border
				ListStroke.Thickness = 1
				ListStroke.Transparency = 0.5
				ListStroke.Parent = CheckpointList
 
				local ListLayout = Instance.new("UIListLayout")
				ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
				ListLayout.Padding = UDim.new(0, 5)
				ListLayout.Parent = CheckpointList
 
				local ListPadding = Instance.new("UIPadding")
				ListPadding.PaddingTop = UDim.new(0, 8)
				ListPadding.PaddingBottom = UDim.new(0, 8)
				ListPadding.PaddingLeft = UDim.new(0, 8)
				ListPadding.PaddingRight = UDim.new(0, 8)
				ListPadding.Parent = CheckpointList
 
				-- Status Bar
				local StatusBar = Instance.new("Frame")
				StatusBar.Size = UDim2.new(1, 0, 0, 25)
				StatusBar.Position = UDim2.new(0, 0, 1, -25)
				StatusBar.BackgroundColor3 = Colors.secondary
				StatusBar.BorderSizePixel = 0
				StatusBar.Parent = MainFrame
 
				local StatusCorner = Instance.new("UICorner")
				StatusCorner.CornerRadius = UDim.new(0, 12)
				StatusCorner.Parent = StatusBar
 
				local StatusLabel = Instance.new("TextLabel")
				StatusLabel.Size = UDim2.new(1, -20, 1, 0)
				StatusLabel.Position = UDim2.new(0, 10, 0, 0)
				StatusLabel.BackgroundTransparency = 1
				StatusLabel.Text = "â Ready | Press F to Record"
				StatusLabel.TextColor3 = Colors.success
				StatusLabel.TextSize = 10
				StatusLabel.FontFace = UIFont
				StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
				StatusLabel.Parent = StatusBar
 
				-- Delete Confirmation Dialog
				local ConfirmDialog = Instance.new("Frame")
				ConfirmDialog.Name = "ConfirmDialog"
				ConfirmDialog.Size = UDim2.new(1, 0, 1, 0)
				ConfirmDialog.Position = UDim2.new(0, 0, 0, 0)
				ConfirmDialog.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				ConfirmDialog.BackgroundTransparency = 0.6
				ConfirmDialog.Active = false
				ConfirmDialog.ZIndex = 100
				ConfirmDialog.Visible = false
				ConfirmDialog.Parent = MainFrame
 
				local DialogBox = Instance.new("Frame")
				DialogBox.Size = UDim2.new(0, 260, 0, 140)
				DialogBox.Position = UDim2.new(0.5, -130, 0.5, -70)
				DialogBox.BackgroundColor3 = Colors.background
				DialogBox.BorderSizePixel = 0
				DialogBox.ZIndex = 101
				DialogBox.Parent = ConfirmDialog
 
				local DialogCorner = Instance.new("UICorner")
				DialogCorner.CornerRadius = UDim.new(0, 12)
				DialogCorner.Parent = DialogBox
 
				local DialogStroke = Instance.new("UIStroke")
				DialogStroke.Color = Colors.accent
				DialogStroke.Thickness = 2
				DialogStroke.Parent = DialogBox
 
				local DialogMessage = Instance.new("TextLabel")
				DialogMessage.Name = "DialogMessage"
				DialogMessage.Size = UDim2.new(1, -30, 0, 70)
				DialogMessage.Position = UDim2.new(0, 15, 0, 15)
				DialogMessage.BackgroundTransparency = 1
				DialogMessage.Text = "Are you sure you want to delete this checkpoint?\nThis action cannot be undone!"
				DialogMessage.TextColor3 = Colors.text
				DialogMessage.TextSize = 13
				DialogMessage.FontFace = UIFont
				DialogMessage.TextWrapped = true
				DialogMessage.ZIndex = 102
				DialogMessage.Parent = DialogBox
 
				local ConfirmDeleteButton = Instance.new("TextButton")
				ConfirmDeleteButton.Name = "ConfirmDelete"
				ConfirmDeleteButton.Size = UDim2.new(0.46, 0, 0, 38)
				ConfirmDeleteButton.Position = UDim2.new(0, 5, 1, -55)
				ConfirmDeleteButton.BackgroundColor3 = Colors.error
				ConfirmDeleteButton.BorderSizePixel = 0
				ConfirmDeleteButton.Text = "â Yes, Delete"
				ConfirmDeleteButton.TextColor3 = Colors.text
				ConfirmDeleteButton.TextSize = 12
				ConfirmDeleteButton.FontFace = UIFont
				ConfirmDeleteButton.ZIndex = 102
				ConfirmDeleteButton.Parent = DialogBox
 
				local ConfirmDelCorner = Instance.new("UICorner")
				ConfirmDelCorner.CornerRadius = UDim.new(0, 8)
				ConfirmDelCorner.Parent = ConfirmDeleteButton
 
				local CancelButton = Instance.new("TextButton")
				CancelButton.Name = "CancelDelete"
				CancelButton.Size = UDim2.new(0.43, 0, 0, 40)
				CancelButton.Position = UDim2.new(0.53, 0, 1, -55)
				CancelButton.BackgroundColor3 = Colors.border
				CancelButton.BorderSizePixel = 0
				CancelButton.Text = "X Cancel"
				CancelButton.TextColor3 = Colors.text
				CancelButton.TextSize = 12
				CancelButton.FontFace = UIFont
				CancelButton.ZIndex = 102
				CancelButton.Parent = DialogBox
 
				local CancelCorner = Instance.new("UICorner")
				CancelCorner.CornerRadius = UDim.new(0, 8)
				CancelCorner.Parent = CancelButton
 
				-- Recording Indicator
				local RecordingIndicator = Instance.new("Frame")
				RecordingIndicator.Name = "RecordingIndicator"
				RecordingIndicator.Size = UDim2.new(0, 60, 0, 60)
				RecordingIndicator.Position = UDim2.new(0, 20, 0.5, -30)
				RecordingIndicator.BackgroundColor3 = Colors.error
				RecordingIndicator.BorderSizePixel = 0
				RecordingIndicator.Visible = false
				RecordingIndicator.ZIndex = 200
				RecordingIndicator.Parent = ScreenGui
 
				local IndicatorCorner = Instance.new("UICorner")
				IndicatorCorner.CornerRadius = UDim.new(0, 30)
				IndicatorCorner.Parent = RecordingIndicator
 
				local IndicatorStroke = Instance.new("UIStroke")
				IndicatorStroke.Color = Colors.accentLight
				IndicatorStroke.Thickness = 3
				IndicatorStroke.Parent = RecordingIndicator
 
				local IndicatorLabel = Instance.new("TextLabel")
				IndicatorLabel.Size = UDim2.new(1, 0, 1, 0)
				IndicatorLabel.BackgroundTransparency = 1
				IndicatorLabel.Text = "ð´"
				IndicatorLabel.TextColor3 = Colors.text
				IndicatorLabel.TextSize = 28
				IndicatorLabel.FontFace = UIFont
				IndicatorLabel.Parent = RecordingIndicator
 
				local IndicatorButton = Instance.new("TextButton")
				IndicatorButton.Size = UDim2.new(1, 0, 1, 0)
				IndicatorButton.BackgroundTransparency = 1
				IndicatorButton.Text = ""
				IndicatorButton.ZIndex = 201
				IndicatorButton.Parent = RecordingIndicator
 
				recordingIndicator = RecordingIndicator
 
				-- ==========================================================
				-- PATH EDITOR GUI
				-- ==========================================================
				local EditorFrame = Instance.new("Frame")
				EditorFrame.Name = "PathEditor"
				EditorFrame.Size = UDim2.new(0, 200, 0, 220)
				EditorFrame.Position = UDim2.new(0.5, 170, 0.5, -110)
				EditorFrame.BackgroundColor3 = Colors.background
				EditorFrame.BorderSizePixel = 0
				EditorFrame.Visible = false
				EditorFrame.ZIndex = 1100
				EditorFrame.Parent = ScreenGui
 
				local EditorShadow = Instance.new("ImageLabel")
				EditorShadow.Size = UDim2.new(1, 30, 1, 30)
				EditorShadow.Position = UDim2.new(0, -15, 0, -15)
				EditorShadow.BackgroundTransparency = 1
				EditorShadow.Image = "rbxassetid://1316045217"
				EditorShadow.ImageColor3 = Color3.new(0, 0, 0)
				EditorShadow.ImageTransparency = 0.5
				EditorShadow.ZIndex = 1099
				EditorShadow.Parent = EditorFrame
 
				local EditorCorner = Instance.new("UICorner")
				EditorCorner.CornerRadius = UDim.new(0, 12)
				EditorCorner.Parent = EditorFrame
 
				local EditorStroke = Instance.new("UIStroke")
				EditorStroke.Color = Colors.warning
				EditorStroke.Thickness = 2
				EditorStroke.Parent = EditorFrame
 
				local EditorTitle = Instance.new("TextLabel")
				EditorTitle.Size = UDim2.new(1, 0, 0, 30)
				EditorTitle.BackgroundTransparency = 1
				EditorTitle.Text = "Edit Path Node"
				EditorTitle.TextColor3 = Colors.text
				EditorTitle.TextSize = 14
				EditorTitle.FontFace = UIFont
				EditorTitle.Parent = EditorFrame
 
				local function createEditBtn(text, pos, callback)
					local btn = Instance.new("TextButton")
					btn.Size = UDim2.new(0, 50, 0, 30)
					btn.Position = pos
					btn.BackgroundColor3 = Colors.secondary
					btn.Text = text
					btn.TextColor3 = Colors.text
					btn.FontFace = UIFont
					btn.Parent = EditorFrame
					local c = Instance.new("UICorner")
					c.CornerRadius = UDim.new(0, 6)
					c.Parent = btn
					local s = Instance.new("UIStroke")
					s.Color = Colors.border
					s.Thickness = 1
					s.Parent = btn
					btn.Activated:Connect(callback)
					return btn
				end
 
				local function moveNode(axis, amount)
					if not selectedNodeIndex or not currentEditingData or not selectedNodePart then return end
					local sample = currentEditingData[selectedNodeIndex]
					if not sample then return end
					sample.position[axis] = sample.position[axis] + amount
					local newPos = Vector3.new(sample.position.x, sample.position.y, sample.position.z)
					selectedNodePart.Position = newPos
				end
 
				createEditBtn("Up",   UDim2.new(0.5, -25, 0, 35),  function() moveNode("y",  editStepSize) end)
				createEditBtn("Down", UDim2.new(0.5, -25, 0, 115), function() moveNode("y", -editStepSize) end)
				createEditBtn("X-",   UDim2.new(0,   10,  0, 75),  function() moveNode("x", -editStepSize) end)
				createEditBtn("X+",   UDim2.new(1,  -60,  0, 75),  function() moveNode("x",  editStepSize) end)
				createEditBtn("Z-",   UDim2.new(0.3, -25, 0, 75),  function() moveNode("z", -editStepSize) end)
				createEditBtn("Z+",   UDim2.new(0.7, -25, 0, 75),  function() moveNode("z",  editStepSize) end)
 
				local StepLabel = Instance.new("TextLabel")
				StepLabel.Size = UDim2.new(1, 0, 0, 20)
				StepLabel.Position = UDim2.new(0, 0, 0, 150)
				StepLabel.BackgroundTransparency = 1
				StepLabel.Text = "Step Size: 0.5"
				StepLabel.TextColor3 = Colors.textDim
				StepLabel.TextSize = 12
				StepLabel.FontFace = UIFont
				StepLabel.Parent = EditorFrame
 
				local SaveEditsButton = Instance.new("TextButton")
				SaveEditsButton.Size = UDim2.new(1, -20, 0, 35)
				SaveEditsButton.Position = UDim2.new(0, 10, 1, -45)
				SaveEditsButton.BackgroundColor3 = Colors.success
				SaveEditsButton.Text = "ð¾ SAVE EDITS"
				SaveEditsButton.TextColor3 = Colors.text
				SaveEditsButton.FontFace = UIFont
				SaveEditsButton.Parent = EditorFrame
 
				local SECorner = Instance.new("UICorner")
				SECorner.CornerRadius = UDim.new(0, 8)
				SECorner.Parent = SaveEditsButton
 
				-- ==========================================================
				-- STORE MINIMIZE ELEMENTS
				-- ==========================================================
				local originalSize = MainFrame.Size
				local isMinimized = false
				local MinimizeElements = {ControlsPanel, CheckpointLabel, CheckpointList, StatusBar}
 
				-- ==========================================================
				-- DRAG LOGIC
				-- ==========================================================
				local isDragging = false
				local dragInput, dragStart, startPos
 
				TitleBar.InputBegan:Connect(function(input)
					if (input.UserInputType == Enum.UserInputType.MouseButton1) or
						(input.UserInputType == Enum.UserInputType.Touch) then
						isDragging = true
						dragStart = input.Position
						startPos = MainFrame.Position
						input.Changed:Connect(function()
							if input.UserInputState == Enum.UserInputState.End then
								isDragging = false
							end
						end)
					end
				end)
 
				REC_UserInputService.InputChanged:Connect(function(input)
					if (input.UserInputType == Enum.UserInputType.MouseMovement) or
						(input.UserInputType == Enum.UserInputType.Touch) then
						dragInput = input
					end
				end)
 
				REC_RunService.Heartbeat:Connect(function()
					if isDragging and dragInput then
						local delta = dragInput.Position - dragStart
						MainFrame.Position = UDim2.new(
							startPos.X.Scale, startPos.X.Offset + delta.X,
							startPos.Y.Scale, startPos.Y.Offset + delta.Y
						)
					end
				end)
 
				-- ==========================================================
				-- HELPER FUNCTIONS
				-- ==========================================================
				local function vectorToTable(vector)
					return {x = vector.X, y = vector.Y, z = vector.Z}
				end
 
				local function tableToVector(tbl)
					return Vector3.new(tbl.x, tbl.y, tbl.z)
				end
 
				local function updateStatus(message, color)
					StatusLabel.Text = message
					StatusLabel.TextColor3 = color or Colors.text
				end
 
				local function lerp(start, goal, alpha)
					return start + ((goal - start) * alpha)
				end
 
				local function lerpVector3(start, goal, alpha)
					return Vector3.new(
						lerp(start.X, goal.X, alpha),
						lerp(start.Y, goal.Y, alpha),
						lerp(start.Z, goal.Z, alpha)
					)
				end
 
				local function lerpAngle(start, goal, alpha)
					local diff = goal - start
					while diff > math.pi do diff = diff - (2 * math.pi) end
					while diff < -math.pi do diff = diff + (2 * math.pi) end
					return start + (diff * alpha)
				end
 
				local function shouldSamplePosition(currentPosition)
					if not lastRecordedPosition then return true end
					return (currentPosition - lastRecordedPosition).Magnitude >= minSampleDistance
				end
 
				local function UpdateTool(char, toolName)
					local hum = char:FindFirstChildOfClass("Humanoid")
					if not hum then return end
					local currentTool = char:FindFirstChildOfClass("Tool")
					if toolName then
						if currentTool and currentTool.Name == toolName then return end
						if currentTool then hum:UnequipTools() end
						local backpack = REC_LocalPlayer.Backpack
						local newTool = backpack:FindFirstChild(toolName)
						if newTool then hum:EquipTool(newTool) end
					else
						if currentTool then hum:UnequipTools() end
					end
				end
 
				local function GetCurrentTool()
					if not REC_Character then return nil end
					local currentTool = REC_Character:FindFirstChildOfClass("Tool")
					return currentTool and currentTool.Name or nil
				end
 
				-- ==========================================================
				-- EDITOR LOGIC
				-- ==========================================================
				local function openNodeEditor(index, part, data)
					selectedNodeIndex = index
					selectedNodePart = part
					currentEditingData = data
					if part then
						part.Color = Colors.nodeSelected
						part.Material = Enum.Material.Neon
					end
					EditorFrame.Visible = true
					updateStatus("â Editing Node #" .. index, Colors.warning)
				end
 
				local function clearVisualization(checkpointName)
					if checkpointName then
						local container = VisualizerFolder:FindFirstChild(checkpointName)
						if container then container:Destroy() end
						activeVisuals[checkpointName] = nil
					else
						VisualizerFolder:ClearAllChildren()
						activeVisuals = {}
						EditorFrame.Visible = false
						currentEditingCheckpoint = nil
						updateStatus("ðï¸ All visuals cleared", Colors.success)
					end
				end
 
				local function visualizePath(data, checkpointName)
					if activeVisuals[checkpointName] then
						clearVisualization(checkpointName)
						return
					end
					if not data or #data < 2 then return end
					currentEditingCheckpoint = checkpointName
					local container = Instance.new("Folder")
					container.Name = checkpointName
					container.Parent = VisualizerFolder
					activeVisuals[checkpointName] = true
					local lastAtt = nil
					for i, sample in ipairs(data) do
						local pos = tableToVector(sample.position)
						local isAir = sample.state == "Jumping" or sample.state == "Freefall" or sample.jumping
						local part = Instance.new("Part")
						part.Size = Vector3.new(0.8, 0.8, 0.8)
						part.Shape = Enum.PartType.Ball
						part.Position = pos
						part.Anchored = true
						part.CanCollide = false
						part.Material = Enum.Material.Plastic
						part.Color = isAir and Colors.beamJump or Colors.beamWalk
						part.Name = "Node_" .. i
						part.Transparency = 0.4
						part.Parent = container
						local cd = Instance.new("ClickDetector")
						cd.MaxActivationDistance = 500
						cd.Parent = part
						cd.MouseClick:Connect(function()
							if selectedNodePart and selectedNodePart.Parent then
								selectedNodePart.Material = Enum.Material.Plastic
								local prevData = currentEditingData and currentEditingData[selectedNodeIndex]
								if prevData then
									local wasAir = prevData.state == "Jumping" or prevData.state == "Freefall" or prevData.jumping
									selectedNodePart.Color = wasAir and Colors.beamJump or Colors.beamWalk
								end
							end
							openNodeEditor(i, part, data)
						end)
						local att = Instance.new("Attachment")
						att.Parent = part
						if lastAtt then
							local beam = Instance.new("Beam")
							beam.Attachment0 = lastAtt
							beam.Attachment1 = att
							beam.Width0 = 0.2
							beam.Width1 = 0.2
							beam.FaceCamera = true
							beam.Color = ColorSequence.new(isAir and Colors.beamJump or Colors.beamWalk)
							beam.Transparency = NumberSequence.new(0.2)
							beam.Parent = container
						end
						lastAtt = att
					end
					updateStatus("ðï¸ Visualizing & Editing: " .. checkpointName, Colors.warning)
				end
 
				SaveEditsButton.Activated:Connect(function()
					if not currentEditingCheckpoint or not currentEditingData then return end
					local fileName = currentEditingCheckpoint .. ".json"
					local filePath = CHECKPOINT_FOLDER .. "/" .. fileName
					local success, err = pcall(function()
						writefile(filePath, HttpService:JSONEncode(currentEditingData))
					end)
					if success then
						showNotification("ð¾ CHANGES SAVED!", Colors.success)
						updateStatus("â Path Updated!", Colors.success)
						EditorFrame.Visible = false
						local name = currentEditingCheckpoint
						clearVisualization(name)
						task.wait(0.1)
						visualizePath(currentEditingData, name)
					else
						showNotification("â SAVE FAILED", Colors.error)
						warn("Save Error:", err)
					end
				end)
 
				-- ==========================================================
				-- CORE FUNCTIONS
				-- ==========================================================
				local function enableToolLock()
					if toolLockEnabled then return end
					toolLockEnabled = true
					if toolLockConnection then toolLockConnection:Disconnect() end
					toolLockConnection = REC_Character.ChildAdded:Connect(function(child)
						if not toolLockEnabled or not isPlaying then return end
						if child:IsA("Tool") and child.Name ~= lastRecordedTool then
							task.wait(0.05)
							if child.Parent == REC_Character and REC_Humanoid then
								REC_Humanoid:UnequipTools()
								if lastRecordedTool then
									local correctTool = REC_LocalPlayer.Backpack:FindFirstChild(lastRecordedTool)
									if correctTool then REC_Humanoid:EquipTool(correctTool) end
								end
							end
						end
					end)
					updateStatus("ð Tool Lock: ACTIVE", Colors.warning)
				end
 
				local function disableToolLock()
					if not toolLockEnabled then return end
					toolLockEnabled = false
					if toolLockConnection then
						toolLockConnection:Disconnect()
						toolLockConnection = nil
					end
					updateStatus("ð Tool Lock: OFF", Colors.textDim)
				end
 
				local function startIndicatorBlinking()
					indicatorBlinking = true
					task.spawn(function()
						local alpha = 0
						local direction = 1
						while indicatorBlinking do
							alpha = alpha + (direction * 0.08)
							if alpha >= 1 then alpha = 1; direction = -1
							elseif alpha <= 0.3 then alpha = 0.3; direction = 1 end
							if recordingIndicator then recordingIndicator.BackgroundTransparency = 1 - alpha end
							task.wait(0.03)
						end
						if recordingIndicator then recordingIndicator.BackgroundTransparency = 0 end
					end)
				end
 
				local function stopIndicatorBlinking() indicatorBlinking = false end
 
				local function optimizeRecordedData(data)
					if #data <= 1 then return data end
					local optimized = {}
					local lastPosition = nil
					local distanceThreshold = 0.1
					for index, sample in ipairs(data) do
						local currentPos = tableToVector(sample.position)
						if index == 1 or index == #data or sample.jumping or sample.state == "Jumping" or sample.state == "Freefall" then
							table.insert(optimized, sample)
							lastPosition = currentPos
						elseif lastPosition then
							local distance = (currentPos - lastPosition).Magnitude
							if distance >= distanceThreshold then
								table.insert(optimized, sample)
								lastPosition = currentPos
							end
						end
					end
					if #optimized > 1 then
						local rawTimes = {}
						for i = 1, #optimized do rawTimes[i] = optimized[i].time end
						optimized[1].time = 0
						for i = 2, #optimized do
							local dt = rawTimes[i] - rawTimes[i - 1]
							if dt <= 0 or dt > 0.5 then dt = SAMPLE_INTERVAL end
							optimized[i].time = optimized[i - 1].time + dt
						end
					end
					return optimized
				end
 
				local function enableGodMode()
					if godModeEnabled then return end
					godModeEnabled = true
					if not REC_Humanoid then return end
					originalMaxHealth = REC_Humanoid.MaxHealth
					REC_Humanoid.MaxHealth = math.huge
					REC_Humanoid.Health = math.huge
					if healthConnection then healthConnection:Disconnect() end
					healthConnection = REC_Humanoid.HealthChanged:Connect(function(health)
						if godModeEnabled and health < math.huge then REC_Humanoid.Health = math.huge end
					end)
					if stateConnection then stateConnection:Disconnect() end
					stateConnection = REC_Humanoid.StateChanged:Connect(function(oldState, newState)
						if not godModeEnabled then return end
						if newState == Enum.HumanoidStateType.FallingDown or
							newState == Enum.HumanoidStateType.Ragdoll or
							newState == Enum.HumanoidStateType.Dead then
							REC_Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
						end
					end)
					if REC_HumanoidRootPart then REC_HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
					updateStatus("ð¡ï¸ God Mode: ACTIVE", Colors.warning)
				end
 
				local function disableGodMode()
					if not godModeEnabled then return end
					godModeEnabled = false
					if healthConnection then healthConnection:Disconnect(); healthConnection = nil end
					if stateConnection then stateConnection:Disconnect(); stateConnection = nil end
					if REC_Humanoid then REC_Humanoid.MaxHealth = originalMaxHealth; REC_Humanoid.Health = originalMaxHealth end
					updateStatus("ð¡ï¸ God Mode: OFF", Colors.textDim)
				end
 
				local function saveRecording(checkpointName)
					if #recordedData == 0 then
						updateStatus("â  No recording to save!", Colors.error)
						return false
					end
					local optimizedData = optimizeRecordedData(recordedData)
					local filePath = CHECKPOINT_FOLDER .. "/" .. checkpointName .. ".json"
					local success, err = pcall(function()
						writefile(filePath, HttpService:JSONEncode(optimizedData))
					end)
					if success then
						updateStatus("â Saved: " .. checkpointName, Colors.success)
						task.spawn(function() task.wait(0.1); refreshCheckpointList() end)
						return true
					else
						updateStatus("X Save failed!", Colors.error)
						return false
					end
				end
 
				local function loadRecording(checkpointName)
					local filePath = CHECKPOINT_FOLDER .. "/" .. checkpointName .. ".json"
					if not isfile(filePath) then updateStatus("X File not found!", Colors.error); return nil end
					local success, data = pcall(function()
						return HttpService:JSONDecode(readfile(filePath))
					end)
					if success then return data else return nil end
				end
 
				-- ==========================================================
				-- SAVE POSITION SYSTEM
				-- ==========================================================
				local function updateLastPosLabel()
					if savedPosition then
						LastPosLabel.Text = string.format("ð X:%.1f  Y:%.1f  Z:%.1f", savedPosition.x, savedPosition.y, savedPosition.z)
						LastPosLabel.TextColor3 = Color3.fromRGB(160, 160, 175)
					else
						LastPosLabel.Text = "ð No position saved"
						LastPosLabel.TextColor3 = Colors.textDim
					end
				end
 
				local function saveCurrentPosition()
					if not REC_Character or not REC_Character:FindFirstChild("HumanoidRootPart") then
						showNotification("â Character not found!", Colors.error); return
					end
					local rootPart = REC_Character.HumanoidRootPart
					local pos = rootPart.Position
					local _, yRot, _ = rootPart.CFrame:ToOrientation()
					savedPosition = {x = pos.X, y = pos.Y, z = pos.Z, ry = yRot}
					local ok, err = pcall(function()
						writefile(SAVED_POS_FILE, HttpService:JSONEncode(savedPosition))
					end)
					if ok then
						updateLastPosLabel()
						showNotification("ð POSITION SAVED!", Color3.fromRGB(160, 160, 175))
						updateStatus(string.format("ð Saved: %.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z), Color3.fromRGB(160, 160, 175))
					else
						showNotification("â Save failed!", Colors.error)
					end
				end
 
				local function loadAndTeleport()
					if isRecording then showNotification("â  Stop recording first!", Colors.error); return end
					if isPlaying then showNotification("â  Stop playback first!", Colors.error); return end
					if not isfile(SAVED_POS_FILE) then showNotification("â No saved position!", Colors.error); return end
					local ok, data = pcall(function()
						return HttpService:JSONDecode(readfile(SAVED_POS_FILE))
					end)
					if not ok or not data then showNotification("â Failed to load!", Colors.error); return end
					if not REC_Character or not REC_Character:FindFirstChild("HumanoidRootPart") then
						showNotification("â Character not found!", Colors.error); return
					end
					savedPosition = data
					updateLastPosLabel()
					local rootPart = REC_Character.HumanoidRootPart
					rootPart.Anchored = true
					rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
					rootPart.CFrame = CFrame.new(data.x, data.y, data.z) * CFrame.Angles(0, data.ry or 0, 0)
					task.wait(0.1)
					rootPart.Anchored = false
					showNotification("â TELEPORTED!", Color3.fromRGB(160, 160, 175))
					updateStatus(string.format("â TP to: %.1f, %.1f, %.1f", data.x, data.y, data.z), Color3.fromRGB(160, 160, 175))
				end
 
				local function loadSavedPosition()
					if isfile(SAVED_POS_FILE) then
						local ok, data = pcall(function()
							return HttpService:JSONDecode(readfile(SAVED_POS_FILE))
						end)
						if ok and data then savedPosition = data; updateLastPosLabel() end
					end
				end
 
				loadSavedPosition()
				SavePosButton.Activated:Connect(function() saveCurrentPosition() end)
				LoadPosButton.Activated:Connect(function() loadAndTeleport() end)
 
				-- ==========================================================
				-- RECORDING FUNCTIONS
				-- ==========================================================
				local function startRecording()
					if isPlaying then updateStatus("â  Stop playback first!", Colors.error); return end
					isRecording = true
					isWaitingForMovement = true
					recordedData = {}
					recordStartTime = tick()
					currentSampleTime = 0
					lastRecordedPosition = nil
					lastRecordedTool = nil
					lastSafePosition = nil
					realSafeCFrame = nil
					lastSafeIndex = 0
					wasMoving = false
 
					RecordButton.Text = "â  STOP RECORDING"
					RecordButton.BackgroundColor3 = Colors.warning
 
					if savedPosition then
						updateStatus(string.format("â  Waiting... | Last: %.0f, %.0f, %.0f", savedPosition.x, savedPosition.y, savedPosition.z), Colors.warning)
					else
						updateStatus("â  Waiting for movement...", Colors.warning)
					end
 
					MainFrame.Visible = false
					recordingIndicator.Visible = true
					startIndicatorBlinking()
				end
 
				local function stopRecording()
					isRecording = false
					isWaitingForMovement = false
					wasMoving = false
					RecordButton.Text = "ð´ START RECORDING"
					RecordButton.BackgroundColor3 = Colors.accent
					updateStatus("â Stopped - " .. #recordedData .. " samples recorded", Colors.success)
					lastRecordedPosition = nil
					lastRecordedTool = nil
					recordingIndicator.Visible = false
					stopIndicatorBlinking()
					MainFrame.Visible = true
					if isMinimized then
						isMinimized = false
						for _, element in ipairs(MinimizeElements) do element.Visible = true end
						MainFrame.Size = originalSize
						MinimizeButton.Text = "â"
					end
				end
 
				local function findInterpolationIndices(data, targetTime)
					if #data == 0 then return nil, nil, 0 end
					if targetTime <= data[1].time then return 1, 1, 0 end
					if targetTime >= data[#data].time then return #data, #data, 0 end
					local left, right = 1, #data
					while left < (right - 1) do
						local mid = math.floor((left + right) / 2)
						if data[mid].time <= targetTime then left = mid else right = mid end
					end
					local index1, index2 = left, right
					local timeDelta = data[index2].time - data[index1].time
					local alpha = 0
					if timeDelta > 0 then alpha = math.clamp((targetTime - data[index1].time) / timeDelta, 0, 1) end
					return index1, index2, alpha
				end
 
				local function findNearestFrame(data, position)
					if not data or #data == 0 then return 1, math.huge end
					local nearestFrame = 1
					local nearestDistance = math.huge
					for i, frame in ipairs(data) do
						local framePos = tableToVector(frame.position)
						local distance = (framePos - position).Magnitude
						if distance < nearestDistance then nearestDistance = distance; nearestFrame = i end
					end
					return nearestFrame, nearestDistance
				end
 
				local function getCurrentMoveState(humanoid)
					if not humanoid then return "Running" end
					local state = humanoid:GetState()
					if state == Enum.HumanoidStateType.Climbing then return "Climbing"
					elseif state == Enum.HumanoidStateType.Jumping then return "Jumping"
					elseif state == Enum.HumanoidStateType.Freefall then return "Freefall"
					elseif state == Enum.HumanoidStateType.Swimming then return "Swimming"
					else return "Running" end
				end
 
				local function getFrameVelocity(frame, moveState)
					if not frame or not frame.velocity then return Vector3.new(0, 0, 0) end
					local vel = tableToVector(frame.velocity)
					if moveState == "Running" or moveState == nil then vel = Vector3.new(vel.X, 0, vel.Z) end
					return vel
				end
 
				local function stopPlayback()
					isPlaying = false
					if playConnection then playConnection:Disconnect(); playConnection = nil end
					disableGodMode()
					disableToolLock()
					StopWalkButton.Visible = false
					if REC_Character and REC_Humanoid then
						local rp = REC_Character:FindFirstChild("HumanoidRootPart")
						if rp then
							rp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
							rp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
						end
						REC_Humanoid:Move(Vector3.new(0, 0, 0), false)
						local currentState = REC_Humanoid:GetState()
						if currentState ~= Enum.HumanoidStateType.Running then
							REC_Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
						end
					end
					isGrounded = false
					lastJumpTime = 0
					landingCooldown = 0
					playbackOffset = 0
					lastPlaybackState = nil
					lastStateChangeTime = 0
					lastRecordedTool = nil
					updateStatus("â  Playback stopped", Colors.success)
				end
 
				local function startPlayback(data, startFrame)
					startFrame = startFrame or 1
					if not data or #data == 0 then updateStatus("â  No data to play!", Colors.error); return end
					if isRecording then updateStatus("â  Stop recording first!", Colors.error); return end
					if isPlaying then stopPlayback() end
					enableGodMode()
					enableToolLock()
					if REC_Character and REC_Character:FindFirstChild("HumanoidRootPart") and data[startFrame] then
						local firstSample = data[startFrame]
						local startPosition = tableToVector(firstSample.position)
						local startRotation = firstSample.rotation or 0
						local recordedHipHeight = firstSample.hipHeight or 2
						local currentHipHeight = REC_Humanoid.HipHeight
						playbackOffset = currentHipHeight - recordedHipHeight
						local rootPart = REC_Character.HumanoidRootPart
						local adjustedY = startPosition.Y + playbackOffset
						rootPart.CFrame = CFrame.new(startPosition.X, adjustedY, startPosition.Z) * CFrame.Angles(0, startRotation, 0)
						rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
						rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
						if REC_Humanoid then REC_Humanoid:ChangeState(Enum.HumanoidStateType.Running) end
						updateStatus("ð¡ï¸ Teleported + God Mode ON", Colors.warning)
						task.wait(0.2)
					end
					isPlaying = true
					playStartTime = tick()
					local lastUpdateTime = playStartTime
					local playbackTime = (data[startFrame].time or 0)
					lastPlaybackState = nil
					lastStateChangeTime = 0
					lastRecordedTool = nil
					updateStatus("â¶ Playing from frame " .. startFrame, Colors.success)
					StopWalkButton.Visible = true
					if playConnection then playConnection:Disconnect() end
					playConnection = REC_RunService.Heartbeat:Connect(function(deltaTime)
						if not isPlaying then return end
						if not REC_Character or not REC_Character:FindFirstChild("HumanoidRootPart") then return end
						if not REC_Humanoid or REC_Humanoid.Parent ~= REC_Character then REC_Humanoid = REC_Character:FindFirstChild("Humanoid") end
						local currentTime = tick()
						local realDelta = currentTime - lastUpdateTime
						lastUpdateTime = currentTime
						realDelta = math.min(realDelta, 0.1)
						playbackTime = playbackTime + (realDelta * playbackSpeed)
						local maxTime = data[#data].time
						if playbackTime > maxTime then
							if isLooping then
								playbackTime = data[startFrame].time or 0
								playStartTime = tick()
								lastUpdateTime = playStartTime
								lastPlaybackState = nil
								lastStateChangeTime = 0
								lastRecordedTool = nil
								if REC_Character and REC_Character:FindFirstChild("HumanoidRootPart") and data[startFrame] then
									local firstSample = data[startFrame]
									local startPosition = tableToVector(firstSample.position)
									local startRotation = firstSample.rotation or 0
									local rootPart = REC_Character.HumanoidRootPart
									playbackOffset = REC_Humanoid.HipHeight - (data[startFrame].hipHeight or 2)
									local adjustedY = startPosition.Y + playbackOffset
									rootPart.CFrame = CFrame.new(startPosition.X, adjustedY, startPosition.Z) * CFrame.Angles(0, startRotation, 0)
									rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
									rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
									REC_Humanoid:ChangeState(Enum.HumanoidStateType.Running)
								end
							else
								local lastSample = data[#data]
								if REC_Character and REC_Character:FindFirstChild("HumanoidRootPart") then
									local rootPart = REC_Character.HumanoidRootPart
									local endPosition = tableToVector(lastSample.position)
									local endRotation = lastSample.rotation or 0
									local adjustedY = endPosition.Y + playbackOffset
									rootPart.CFrame = CFrame.new(endPosition.X, adjustedY, endPosition.Z) * CFrame.Angles(0, endRotation, 0)
									rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
									rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
									if REC_Humanoid then
										REC_Humanoid:Move(Vector3.new(0, 0, 0), false)
										REC_Humanoid:ChangeState(Enum.HumanoidStateType.Running)
									end
								end
								stopPlayback()
								return
							end
						end
						local index1, index2, alpha = findInterpolationIndices(data, playbackTime)
						local sample1, sample2 = data[index1], data[index2]
						if not sample1 or not sample2 then return end
						local pos1 = tableToVector(sample1.position)
						local pos2 = tableToVector(sample2.position)
						local rot1 = sample1.rotation or 0
						local rot2 = sample2.rotation or 0
						local moveDir1 = tableToVector(sample1.moveDirection or {x=0, y=0, z=0})
						local moveDir2 = tableToVector(sample2.moveDirection or {x=0, y=0, z=0})
						local targetPosition = lerpVector3(pos1, pos2, alpha)
						local targetRotation = lerpAngle(rot1, rot2, alpha)
						local targetMoveDir = lerpVector3(moveDir1, moveDir2, alpha)
						local rootPart = REC_Character.HumanoidRootPart
						local sampleState = sample1.state or "Running"
						if sampleState ~= "Jumping" and sampleState ~= "Freefall" and
							sampleState ~= "Climbing" and sampleState ~= "Swimming" then
							sampleState = "Running"
						end
						local frameVel = getFrameVelocity(sample1, sampleState)
						if frameVel.Y > JUMP_VELOCITY_THRESHOLD and sampleState ~= "Jumping" then
							sampleState = "Jumping"
						elseif frameVel.Y < -5 and sampleState == "Running" then
							sampleState = "Freefall"
						end
						local targetCFrame = CFrame.new(targetPosition.X, targetPosition.Y + playbackOffset, targetPosition.Z) * CFrame.Angles(0, targetRotation, 0)
						rootPart.CFrame = targetCFrame
						rootPart.AssemblyLinearVelocity = frameVel
						rootPart.AssemblyAngularVelocity = Vector3.zero
						if REC_Humanoid then REC_Humanoid:Move(targetMoveDir, false) end
						local toolName = sample1.tool
						if toolName ~= lastRecordedTool then
							UpdateTool(REC_Character, toolName)
							lastRecordedTool = toolName
							if not toolLockEnabled then enableToolLock() end
						end
						if sampleState ~= lastPlaybackState and (currentTime - lastStateChangeTime) >= STATE_CHANGE_COOLDOWN then
							if sampleState == "Jumping" then
								REC_Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
								lastPlaybackState = "Jumping"; lastStateChangeTime = currentTime
							elseif sampleState == "Freefall" then
								REC_Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
								lastPlaybackState = "Freefall"; lastStateChangeTime = currentTime
							elseif sampleState == "Climbing" then
								REC_Humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
								REC_Humanoid.PlatformStand = false
								lastPlaybackState = "Climbing"; lastStateChangeTime = currentTime
							elseif sampleState == "Swimming" then
								REC_Humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
								lastPlaybackState = "Swimming"; lastStateChangeTime = currentTime
							else
								if lastPlaybackState ~= "Running" then
									REC_Humanoid:ChangeState(Enum.HumanoidStateType.Running)
									lastPlaybackState = "Running"; lastStateChangeTime = currentTime
								end
							end
						end
					end)
				end
 
				local function resumeNearestCheckpoint()
					if not REC_Character or not REC_Character:FindFirstChild("HumanoidRootPart") then
						updateStatus("â  Character not found!", Colors.error); return
					end
					local currentPos = REC_Character.HumanoidRootPart.Position
					local files = listfiles(CHECKPOINT_FOLDER)
					local nearestCheckpoint = nil
					local nearestFrame = 1
					local nearestDistance = math.huge
					local nearestData = nil
					for _, filePath in pairs(files) do
						if filePath:match("%.json$") then
							local fileName = filePath:match("([^/\\]+)%.json$")
							if fileName then
								local data = loadRecording(fileName)
								if data then
									local frame, distance = findNearestFrame(data, currentPos)
									if distance < nearestDistance then
										nearestDistance = distance; nearestCheckpoint = fileName; nearestFrame = frame; nearestData = data
									end
								end
							end
						end
					end
					if nearestData and nearestDistance < 50 then
						updateStatus("ð¯ Resuming: " .. nearestCheckpoint .. " (frame " .. nearestFrame .. ", " .. math.floor(nearestDistance) .. "m)", Colors.warning)
						task.wait(0.5)
						startPlayback(nearestData, nearestFrame)
					else
						updateStatus("â  No nearby checkpoint found (max 50m)", Colors.error)
					end
				end
 
				-- ==========================================================
				-- CHECKPOINT LIST
				-- ==========================================================
				local function createCheckpointButton(checkpointName, layoutOrder)
					local ButtonFrame = Instance.new("Frame")
					ButtonFrame.Name = checkpointName
					ButtonFrame.Size = UDim2.new(1, -16, 0, 42)
					ButtonFrame.BackgroundColor3 = Colors.background
					ButtonFrame.BorderSizePixel = 0
					ButtonFrame.LayoutOrder = layoutOrder or 0
 
					local ButtonCorner = Instance.new("UICorner")
					ButtonCorner.CornerRadius = UDim.new(0, 8)
					ButtonCorner.Parent = ButtonFrame
 
					local ButtonStroke = Instance.new("UIStroke")
					ButtonStroke.Color = Colors.border
					ButtonStroke.Thickness = 1
					ButtonStroke.Parent = ButtonFrame
 
					local PlayButton = Instance.new("TextButton")
					PlayButton.Size = UDim2.new(1, -80, 1, 0)
					PlayButton.Position = UDim2.new(0, 0, 0, 0)
					PlayButton.BackgroundTransparency = 1
					PlayButton.Text = "â¶ " .. checkpointName
					PlayButton.TextColor3 = Colors.text
					PlayButton.TextSize = 12
					PlayButton.FontFace = UIFont
					PlayButton.TextXAlignment = Enum.TextXAlignment.Left
					PlayButton.TextTruncate = Enum.TextTruncate.AtEnd
					PlayButton.Parent = ButtonFrame
 
					local PlayPadding = Instance.new("UIPadding")
					PlayPadding.PaddingLeft = UDim.new(0, 12)
					PlayPadding.Parent = PlayButton
 
					PlayButton.Activated:Connect(function()
						local loadedData = loadRecording(checkpointName)
						if loadedData then startPlayback(loadedData) end
					end)
 
					local ViewButton = Instance.new("TextButton")
					ViewButton.Size = UDim2.new(0, 35, 0, 42)
					ViewButton.Position = UDim2.new(1, -77, 0, 0)
					ViewButton.BackgroundTransparency = 1
					ViewButton.BorderSizePixel = 0
					ViewButton.Text = "ðï¸"
					ViewButton.TextColor3 = Colors.text
					ViewButton.TextSize = 14
					ViewButton.FontFace = UIFont
					ViewButton.Parent = ButtonFrame
 
					ViewButton.Activated:Connect(function()
						local loadedData = loadRecording(checkpointName)
						if loadedData then visualizePath(loadedData, checkpointName) end
					end)
 
					local DeleteButton = Instance.new("TextButton")
					DeleteButton.Size = UDim2.new(0, 42, 0, 42)
					DeleteButton.Position = UDim2.new(1, -42, 0, 0)
					DeleteButton.BackgroundColor3 = Colors.error
					DeleteButton.BorderSizePixel = 0
					DeleteButton.Text = "X"
					DeleteButton.TextColor3 = Colors.text
					DeleteButton.TextSize = 16
					DeleteButton.FontFace = UIFont
					DeleteButton.Parent = ButtonFrame
 
					local DeleteCorner = Instance.new("UICorner")
					DeleteCorner.CornerRadius = UDim.new(0, 8)
					DeleteCorner.Parent = DeleteButton
 
					DeleteButton.Activated:Connect(function()
						ConfirmDialog.Visible = true
						ConfirmDialog.Name = checkpointName
					end)
 
					ButtonFrame.Parent = CheckpointList
					return ButtonFrame
				end
 
				local checkpointButtons = {}
 
				local function sortCheckpoints(name1, name2)
					local priorities = {["w1"]=1, ["waypoint"]=2, ["walk"]=3, ["point"]=4, ["checkpoint"]=5, ["cp"]=6, ["test"]=7}
					local lower1, lower2 = string.lower(name1), string.lower(name2)
					local p1, p2 = priorities[lower1], priorities[lower2]
					if p1 and p2 then return p1 < p2 elseif p1 then return true elseif p2 then return false end
					local pre1, num1 = string.match(lower1, "^([%a_]+)(%d+)$")
					local pre2, num2 = string.match(lower2, "^([%a_]+)(%d+)$")
					if num1 and num2 then
						pre1 = pre1 or ""; pre2 = pre2 or ""
						if pre1 == pre2 then return tonumber(num1) < tonumber(num2) else return pre1 < pre2 end
					elseif num1 then return false elseif num2 then return true end
					return lower1 < lower2
				end
 
				function refreshCheckpointList()
					for name, button in pairs(checkpointButtons) do
						if button and button.Parent then button:Destroy() end
					end
					checkpointButtons = {}
					updateStatus("â³ Scanning files...", Colors.warning)
					task.wait(0.1)
					local files = listfiles(CHECKPOINT_FOLDER)
					local checkpointNames = {}
					for _, filePath in pairs(files) do
						if filePath:match("%.json$") then
							local fileName = filePath:match("([^/\\]+)%.json$")
							if fileName then table.insert(checkpointNames, fileName) end
						end
					end
					table.sort(checkpointNames, sortCheckpoints)
					local count = 0
					CheckpointList.CanvasSize = UDim2.new(0, 0, 0, #checkpointNames * 48)
					for i, name in ipairs(checkpointNames) do
						checkpointButtons[name] = createCheckpointButton(name, i)
						count = count + 1
						if count % 10 == 0 then
							updateStatus("â³ Loading... (" .. count .. "/" .. #checkpointNames .. ")", Colors.warning)
							REC_RunService.RenderStepped:Wait()
						end
					end
					updateStatus("â Found " .. count .. " checkpoints | [" .. recordKeybind.Name .. "] to Record", Colors.success)
				end
 
				-- ==========================================================
				-- CUSTOM RECORD KEYBIND BINDING
				-- ==========================================================
				KeybindButton.Activated:Connect(function()
					if isBindingKey then return end
					isBindingKey = true
					KeybindButton.Text = "[ Press key... ]"
					KeybindButton.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
					KeybindButton.TextColor3 = Color3.fromRGB(230, 230, 240)
					showNotification("ð® Press any key...", Colors.warning)
					updateStatus("ð® Press any key to set keybind (Esc = cancel)", Colors.warning)
 
					local conn
					conn = REC_UserInputService.InputBegan:Connect(function(input, gameProcessed)
						if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
						if input.KeyCode == Enum.KeyCode.Escape then
							isBindingKey = false
							KeybindButton.Text = "[ " .. recordKeybind.Name .. " ]"
							KeybindButton.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
							KeybindButton.TextColor3 = Color3.fromRGB(180, 180, 195)
							updateStatus("â  Keybind binding cancelled", Colors.warning)
							conn:Disconnect()
							return
						end
						recordKeybind = input.KeyCode
						isBindingKey = false
						KeybindButton.Text = "[ " .. recordKeybind.Name .. " ]"
						KeybindButton.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
						KeybindButton.TextColor3 = Color3.fromRGB(180, 180, 195)
						showNotification("â Keybind: " .. recordKeybind.Name, Colors.success)
						updateStatus("â Record keybind: [" .. recordKeybind.Name .. "]", Colors.success)
						conn:Disconnect()
					end)
				end)
 
				-- ==========================================================
				-- BUTTON HANDLERS
				-- ==========================================================
				RecordButton.Activated:Connect(function()
					if isRecording then stopRecording() else startRecording() end
				end)
 
				IndicatorButton.Activated:Connect(function()
					if isRecording then stopRecording() end
				end)
 
				REC_UserInputService.InputBegan:Connect(function(input, gameProcessed)
					if gameProcessed then return end
					if isBindingKey then return end
					if input.KeyCode == recordKeybind then
						if isRecording then stopRecording() else startRecording() end
						return
					end
				end)
 
				StopWalkButton.Activated:Connect(function()
					if isPlaying then stopPlayback(); updateStatus("â  Walk stopped by user", Colors.warning) end
				end)
 
				ResumeNearestButton.Activated:Connect(function() resumeNearestCheckpoint() end)
 
				ClearVisualsButton.Activated:Connect(function() clearVisualization() end)
 
				SaveButton.Activated:Connect(function()
					local checkpointName = CheckpointInput.Text:gsub("%s", "_")
					if checkpointName == "" then
						local files = listfiles(CHECKPOINT_FOLDER)
						local usedNumbers = {}
						for _, filePath in pairs(files) do
							local fileName = filePath:match("([^/\\]+)%.json$")
							if fileName then
								local number = fileName:match("^checkpoint_(%d+)$")
								if number then usedNumbers[tonumber(number)] = true end
							end
						end
						local nextNumber = 1
						while usedNumbers[nextNumber] do nextNumber = nextNumber + 1 end
						checkpointName = "checkpoint_" .. nextNumber
						updateStatus("ð Auto-named: " .. checkpointName, Colors.success)
					end
					if saveRecording(checkpointName) then CheckpointInput.Text = "" end
				end)
 
				SearchInput:GetPropertyChangedSignal("Text"):Connect(function()
					local query = string.lower(SearchInput.Text)
					local visibleCount = 0
					for name, button in pairs(checkpointButtons) do
						if string.find(string.lower(name), query) then
							button.Visible = true; visibleCount = visibleCount + 1
						else
							button.Visible = false
						end
					end
					CheckpointList.CanvasSize = UDim2.new(0, 0, 0, visibleCount * 48)
				end)
 
				RefreshButton.Activated:Connect(function() refreshCheckpointList() end)
 
				CancelButton.Activated:Connect(function()
					ConfirmDialog.Visible = false; ConfirmDialog.Name = "ConfirmDialog"
				end)
 
				ConfirmDeleteButton.Activated:Connect(function()
					local checkpointName = ConfirmDialog.Name
					if checkpointName == "ConfirmDialog" then return end
					local filePath = CHECKPOINT_FOLDER .. "/" .. checkpointName .. ".json"
					if isfile(filePath) then
						local success, err = pcall(function() delfile(filePath) end)
						if success then
							updateStatus("â Deleted: " .. checkpointName, Colors.warning)
							clearVisualization(checkpointName)
						else
							updateStatus("X Error deleting file!", Colors.error)
							warn("Delete error:", err)
							ConfirmDialog.Visible = false; ConfirmDialog.Name = "ConfirmDialog"
							return
						end
					else
						updateStatus("â  File not found!", Colors.warning)
					end
					if checkpointButtons[checkpointName] then
						checkpointButtons[checkpointName]:Destroy()
						checkpointButtons[checkpointName] = nil
					end
					local count = 0
					for _ in pairs(checkpointButtons) do count = count + 1 end
					CheckpointList.CanvasSize = UDim2.new(0, 0, 0, count * 48)
					ConfirmDialog.Visible = false; ConfirmDialog.Name = "ConfirmDialog"
				end)
 
				SpeedInput.FocusLost:Connect(function()
					local speedValue = tonumber(SpeedInput.Text)
					if speedValue and speedValue > 0 then
						playbackSpeed = speedValue
						SpeedInput.Text = tostring(playbackSpeed)
						updateStatus("â Speed: " .. playbackSpeed .. "x", Colors.success)
					else
						playbackSpeed = 1
						SpeedInput.Text = "1"
						updateStatus("â  Invalid speed, reset to 1.0x", Colors.error)
					end
				end)
 
				SampleRateInput.FocusLost:Connect(function()
					local val = tonumber(SampleRateInput.Text)
					if val and val >= 1 and val <= 240 then
						SAMPLE_RATE = val
						SAMPLE_INTERVAL = 1 / SAMPLE_RATE
						SampleRateInput.Text = tostring(SAMPLE_RATE)
						updateStatus("â Sample Rate: " .. SAMPLE_RATE .. " Hz", Colors.success)
					else
						SAMPLE_RATE = 60
						SAMPLE_INTERVAL = 1 / SAMPLE_RATE
						SampleRateInput.Text = "60"
						updateStatus("â  Invalid Hz, reset to 60", Colors.error)
					end
				end)
 
				LoopButton.Activated:Connect(function()
					isLooping = not isLooping
					if isLooping then
						LoopButton.Text = "ð Loop: ON"; LoopButton.BackgroundColor3 = Colors.success
						updateStatus("â Looping enabled", Colors.success)
					else
						LoopButton.Text = "ð Loop: OFF"; LoopButton.BackgroundColor3 = Colors.border
						updateStatus("â  Looping disabled", Colors.warning)
					end
				end)
 
				local function ToggleAntiFall()
					antiFallEnabled = not antiFallEnabled
					if antiFallEnabled then
						AntiFallButton.Text = "ð¡ï¸ Safe: ON"
						AntiFallButton.BackgroundColor3 = Colors.success
						showNotification("ð¡ï¸ ANTI-FALL: ON", Colors.success)
						updateStatus("â Anti-Fall Enabled", Colors.success)
					else
						AntiFallButton.Text = "ð¡ï¸ Safe: OFF"
						AntiFallButton.BackgroundColor3 = Colors.border
						showNotification("ð« ANTI-FALL: OFF", Colors.error)
						updateStatus("â  Anti-Fall Disabled", Colors.warning)
					end
				end
 
				AntiFallButton.Activated:Connect(function() ToggleAntiFall() end)
 
				CloseButton.Activated:Connect(function()
					if isRecording then stopRecording() end
					if isPlaying then stopPlayback() end
					disableGodMode()
					disableToolLock()
					clearVisualization()
					ScreenGui:Destroy()
					recorderLoaded = false
				end)
 
				MinimizeButton.Activated:Connect(function()
					isMinimized = not isMinimized
					if isMinimized then
						for _, element in ipairs(MinimizeElements) do element.Visible = false end
						MainFrame.Size = UDim2.new(0, originalSize.X.Offset, 0, TitleBar.Size.Y.Offset)
						MinimizeButton.Text = "â¡"
					else
						for _, element in ipairs(MinimizeElements) do element.Visible = true end
						MainFrame.Size = originalSize
						MinimizeButton.Text = "â"
					end
				end)
 
				-- ==========================================================
				-- MAIN HEARTBEAT LOOP (RECORDING)
				-- ==========================================================
				REC_RunService.Heartbeat:Connect(function()
					if isRecovering then return end
 
					if not isRecording then
						realSafeCFrame = nil
						lastSafeIndex = 0
						isRecovering = false
						isWaitingForMovement = false
						wasMoving = false
						return
					end
 
					if not REC_Character or not REC_Character:FindFirstChild("HumanoidRootPart") then return end
 
					local rootPart = REC_Character.HumanoidRootPart
					local humanoid = REC_Character:FindFirstChild("Humanoid")
					if not humanoid then return end
 
					if isWaitingForMovement then
						local hvel = Vector3.new(
							rootPart.AssemblyLinearVelocity.X,
							0,
							rootPart.AssemblyLinearVelocity.Z
						).Magnitude
						local isActuallyMoving = hvel > 1.0 and humanoid.MoveDirection.Magnitude > 0.1
						if isActuallyMoving then
							isWaitingForMovement = false
							recordStartTime = tick()
							currentSampleTime = 0
							RecordButton.BackgroundColor3 = Colors.error
							updateStatus("ð´ Recording...", Colors.error)
						else
							return
						end
					end
 
					local velocity = rootPart.AssemblyLinearVelocity
					local hSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
					local humanoidState = humanoid:GetState()
					local isJumpingOrFalling = (humanoidState == Enum.HumanoidStateType.Jumping)
						or (humanoidState == Enum.HumanoidStateType.Freefall)
 
					local isClimbingOrSwimming = (humanoidState == Enum.HumanoidStateType.Climbing)
						or (humanoidState == Enum.HumanoidStateType.Swimming)
					local isMovingNow = hSpeed > 0.5 or isJumpingOrFalling or isClimbingOrSwimming
 
					if not isMovingNow then
						if wasMoving then
							updateStatus("â¸ Paused (idle)... | " .. #recordedData .. " frames", Colors.warning)
						end
						wasMoving = false
						recordStartTime = tick() - currentSampleTime
						return
					end
 
					if not wasMoving then
						updateStatus("ð´ Recording...", Colors.error)
					end
					wasMoving = true
 
					local currentTime = tick()
					local sampleTime = currentTime - recordStartTime
					if (sampleTime - currentSampleTime) < SAMPLE_INTERVAL then return end
 
					local position = rootPart.Position
 
					local grounded = math.abs(velocity.Y) < 3
						and humanoidState ~= Enum.HumanoidStateType.Freefall
						and humanoidState ~= Enum.HumanoidStateType.Jumping
 
					if not realSafeCFrame then
						realSafeCFrame = rootPart.CFrame
						lastSafeIndex = #recordedData
					end
					if grounded then
						local distFromLastSafe = (position - realSafeCFrame.Position).Magnitude
						if distFromLastSafe > 0.5 or #recordedData == 0 then
							realSafeCFrame = rootPart.CFrame
							lastSafeIndex = #recordedData
						end
					end
 
					if antiFallEnabled and (position.Y < realSafeCFrame.Position.Y - FALL_THRESHOLD) then
						isRecovering = true
						local cutIndex = math.max(1, lastSafeIndex - BUFFER_FRAMES)
						for i = #recordedData, cutIndex + 1, -1 do
							table.remove(recordedData, i)
						end
						local lastFrameData = recordedData[cutIndex]
						local targetRewindTime = 0
						if lastFrameData then
							local recordedPos = tableToVector(lastFrameData.position)
							local recordedRot = lastFrameData.rotation or 0
							realSafeCFrame = CFrame.new(recordedPos) * CFrame.Angles(0, recordedRot, 0)
							targetRewindTime = lastFrameData.time
							lastFrameData.velocity = {x=0, y=0, z=0}
						end
						currentSampleTime = targetRewindTime
						task.spawn(function()
							rootPart.Anchored = true
							rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
							rootPart.CFrame = realSafeCFrame
							updateStatus("ð¡ï¸ FALL DETECTED - RECOVERING!", Colors.accent)
							task.wait(0.5)
							if rootPart and humanoid then
								rootPart.Anchored = false
								rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
								humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
							end
							recordStartTime = tick() - targetRewindTime
							isRecovering = false
							updateStatus("ð´ Recording Resumed", Colors.error)
						end)
						return
					end
 
					currentSampleTime = sampleTime
 
					if not shouldSamplePosition(position) then return end
					lastRecordedPosition = position
 
					local _, yRotation, _ = rootPart.CFrame:ToOrientation()
					local stateName = getCurrentMoveState(humanoid)
					local currentTool = GetCurrentTool()
 
					local sample = {
						time = currentSampleTime,
						position = vectorToTable(position),
						rotation = yRotation,
						velocity = vectorToTable(velocity),
						moveDirection = vectorToTable(humanoid.MoveDirection),
						jumping = (humanoidState == Enum.HumanoidStateType.Jumping),
						state = stateName,
						hipHeight = humanoid.HipHeight,
						walkSpeed = humanoid.WalkSpeed,
						tool = currentTool
					}
 
					if currentTool ~= lastRecordedTool then
						lastRecordedTool = currentTool
						if currentTool then
							updateStatus("ð§ Tool: " .. currentTool, Colors.warning)
						else
							updateStatus("ð§ Tool unequipped", Colors.textDim)
						end
					end
 
					table.insert(recordedData, sample)
				end)
 
				-- ==========================================================
				-- CHARACTER RESPAWN
				-- ==========================================================
				REC_LocalPlayer.CharacterAdded:Connect(function(newCharacter)
					REC_Character = newCharacter
					REC_Humanoid = REC_Character:WaitForChild("Humanoid")
					REC_HumanoidRootPart = REC_Character:WaitForChild("HumanoidRootPart")
					if isRecording then stopRecording() end
					if isPlaying then stopPlayback() end
					disableGodMode()
					disableToolLock()
				end)
 
				-- ==========================================================
				-- INIT
				-- ==========================================================
				refreshCheckpointList()
				updateStatus("â RullzsyHUB Ready! [" .. recordKeybind.Name .. "] = Record", Colors.success)
 
				end) -- end task.spawn
			end -- end if state
		end
	})

	RecordTab:Divider()

end

setupRecordTab()

-- =========================
-- AUTO WALK | LOADER TAB
-- =========================
local function setupAutowalkTab()
    
    --| =========================================================== |--
    --| SERVICES & IMPORTS FOR AUTO WALK                            |--
    --| =========================================================== |--

    local RunService = game:GetService("RunService")
    local TweenService = game:GetService("TweenService")
    local UserInputService = game:GetService("UserInputService")
    local TeleportService = game:GetService("TeleportService")
    local Lighting = game:GetService("Lighting")
    
    
    local player = Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

    -- VISUAL PATH
    local showPath = false
    local pathColor = Color3.fromRGB(255, 0, 0)
    local pathFolder = nil
    
    --| =========================================================== |--
    --| AUTO WALK VARIABLES                                         |--
    --| =========================================================== |--

	local AUTOWALK_FOLDER = "RHUB_AUTOWALK_LOADER"
	if not isfolder(AUTOWALK_FOLDER) then
   		makefolder(AUTOWALK_FOLDER)
	end

	local MAPS_DATA_URL = "https://rullzsyhub.web.id/json/list_map.json"

	local trackFiles = {}
    local trackNames = {}
    local trackURLs = {}
    local trackLockStatus = {}
	local selectedTrackFile = nil
	local selectedTrackName = nil
    local mapsDataLoaded = false
    local selectedJsonURL = nil
    local cachedJsonData = nil
    local autoWalkGUI = nil
    local isWalking = false
    local playbackConnection = nil
    local playbackSpeed = 1.0
    local heightOffset = 0
    local isLoopEnabled = false
    local isAutoRespawnEnabled = false
    local lastPlaybackTime = 0
    local accumulatedTime = 0
    local lastFootstepTime = 0
    local footstepInterval = 0.35
    local leftFootstep = true
    local isReversed = false
    local isFlipped = false
    local FLIP_SMOOTHNESS = 0.20
    local currentFlipRotation = CFrame.new()
    local PATH_THRESHOLD = 8
    local ARRIVAL_THRESHOLD = 2
    local playStopKeybind = Enum.KeyCode.F
    local flipRotateKeybind = Enum.KeyCode.R
    local keybindConnection = nil
    local godModeEnabled = false
    local isAutoWalkVisible = false
    local currentRecordedTool = nil
    local toolLocked = false
    local toolLockConnection = nil
    local backpackConnection = nil
    local shouldRestartAfterRespawn = false
    local autoEquipToolEnabled = true
	local pathHeightOffset = 0

    --| =========================================================== |--
    --| LOAD MAPS DATA FROM EXTERNAL JSON                           |--
    --| =========================================================== |--

    local function loadMapsData()
        if mapsDataLoaded then
            return true
        end
        
        local success, response = pcall(function()
            return game:HttpGet(MAPS_DATA_URL)
        end)
        
        local ok, mapsData = pcall(function()
            return HttpService:JSONDecode(response)
        end)
                
        -- Clear existing data
        trackNames = {}
        trackURLs = {}
        trackLockStatus = {}
        
        -- Load new data
        for _, mapData in ipairs(mapsData.maps) do
            table.insert(trackNames, mapData.name)
            trackURLs[mapData.name] = mapData.url
            trackLockStatus[mapData.name] = mapData.locked or false
        end
        
        mapsDataLoaded = true

        return true
    end

    --| =========================================================== |--
    --| TRACK LOCK FUNCTIONS                                        |--
    --| =========================================================== |--
    
    local function isTrackLocked(trackName)
        return trackLockStatus[trackName] == true
    end
        
	local function getAvailableTracks()
		trackFiles = {}

		local files = listfiles(AUTOWALK_FOLDER)
		local values = {}

		for _, path in ipairs(files) do
			if path:sub(-5):lower() == ".json" then
				local name = path:match("([^/\\]+)%.json$")
				if name then
					trackFiles[name] = path
					table.insert(values, name)
				end
			end
		end

		if #values == 0 then
			table.insert(values, "[No JSON Found]")
		end

		table.sort(values)
		return values
	end

    local function cleanTrackName(displayName)
        return displayName:gsub(" ð", "")
    end

    --| =========================================================== |--
    --| UTILITY FUNCTIONS AUTO WALK                                 |--
    --| =========================================================== |--
    
    local function vecToTable(v3)
        return {x = v3.X, y = v3.Y, z = v3.Z}
    end
    
    local function tableToVec(t)
        return Vector3.new(t.x, t.y, t.z)
    end
    
    local function lerp(a, b, t)
        return a + (b - a) * t
    end
    
    local function lerpVector(a, b, t)
        return Vector3.new(lerp(a.X, b.X, t), lerp(a.Y, b.Y, t), lerp(a.Z, b.Z, t))
    end
    
    local function lerpAngle(a, b, t)
        local diff = (b - a)
        while diff > math.pi do diff = diff - 2*math.pi end
        while diff < -math.pi do diff = diff + 2*math.pi end
        return a + diff * t
    end
    
	local function loadJsonFromFile(filePath)
		if not isfile(filePath) then
			return nil, "File tidak ditemukan"
		end

		local success, content = pcall(readfile, filePath)
		if not success then
			return nil, "Gagal membaca file"
		end

		local ok, data = pcall(function()
			return HttpService:JSONDecode(content)
		end)

		if not ok then
			return nil, "Format JSON tidak valid"
		end

		return data
	end
    
    ------------------------------------------------
    -- VISUAL PATH FUNCTIONS
    ------------------------------------------------

--------------------------------
-- VISUAL PATH FUNCTIONS (DENGAN HEIGHT OFFSET)
--------------------------------

local function clearPath()
    if pathFolder then
        pathFolder:Destroy()
        pathFolder = nil
    end
end

local function drawPath(data)
    clearPath()

    if not data or #data < 2 then
        return
    end

    pathFolder = Instance.new("Folder")
    pathFolder.Name = "AutoWalk_Path"
    pathFolder.Parent = workspace

    local skipRate = 5
    local optimizedData = {}
    
    table.insert(optimizedData, data[1])
    
    for i = skipRate, #data, skipRate do
        table.insert(optimizedData, data[i])
    end
    
    if data[#data] ~= optimizedData[#optimizedData] then
        table.insert(optimizedData, data[#data])
    end

    local attachments = {}

    for i, frame in ipairs(optimizedData) do
        local part = Instance.new("Part")
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 1
        part.Size = Vector3.new(0.1, 0.1, 0.1)
        
        -- TERAPKAN HEIGHT OFFSET PADA POSISI Y
        local originalPos = tableToVec(frame.position)
        part.Position = Vector3.new(originalPos.X, originalPos.Y + pathHeightOffset, originalPos.Z)
        
        part.CastShadow = false
        part.Material = Enum.Material.SmoothPlastic
        part.Parent = pathFolder

        local att = Instance.new("Attachment")
        att.Parent = part

        table.insert(attachments, att)
    end

    for i = 1, #attachments - 1 do
        local beam = Instance.new("Beam")
        beam.Attachment0 = attachments[i]
        beam.Attachment1 = attachments[i + 1]

        beam.FaceCamera = true
        beam.Width0 = 0.2
        beam.Width1 = 0.2
        beam.LightEmission = 0.8 
        beam.LightInfluence = 0
        beam.Transparency = NumberSequence.new(0.1)
        beam.Color = ColorSequence.new(pathColor)
        beam.Texture = ""
        beam.Segments = 1

        beam.Parent = attachments[i]
    end
end

    local function updatePlayButtonText(newText)
        if autoWalkGUI and autoWalkGUI.Enabled then
            local mainFrame = autoWalkGUI:FindFirstChild("MainFrame")
            if mainFrame then
                local container = mainFrame:FindFirstChild("container")
                if container then
                    local playButton = container:FindFirstChild("PlayButton")
                    if playButton and playButton:IsA("TextButton") then
                        playButton.Text = newText
                        return true
                    end
                end
            end
        end
        return false
    end

    --| =========================================================== |--
    --| FOOTSTEP & MOVEMENT FUNCTIONS                               |--
    --| =========================================================== |--
    
    local function playFootstepSound()
        if not humanoid or not character then return end
    
        pcall(function()
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
    
            local rayOrigin = hrp.Position
            local rayDirection = Vector3.new(0, -5, 0)
            local raycastParams = RaycastParams.new()
            raycastParams.FilterDescendantsInstances = { character }
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    
            local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
            if rayResult and rayResult.Instance then
                local material = rayResult.Material
                local sound = Instance.new("Sound")
                sound.Volume = 0.8
                sound.RollOffMaxDistance = 100
                sound.RollOffMinDistance = 10
    
                local soundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
                if material == Enum.Material.Grass then
                    soundId = "rbxassetid://9118823107"
                elseif material == Enum.Material.Metal then
                    soundId = "rbxassetid://260433111"
                elseif material == Enum.Material.Sand then
                    soundId = "rbxassetid://9120089994"
                elseif material == Enum.Material.Wood then
                    soundId = "rbxassetid://9118828605"
                end
    
                sound.SoundId = soundId
                sound.Parent = hrp
                sound:Play()
                game:GetService("Debris"):AddItem(sound, 1)
            end
        end)
    end
    
    local function simulateNaturalMovement(moveDirection, velocity)
        if not humanoid or not character then return end
    
        local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
        local speed = horizontalVelocity.Magnitude
    
        local onGround = false
        pcall(function()
            local state = humanoid:GetState()
            onGround = (state == Enum.HumanoidStateType.Running or
                state == Enum.HumanoidStateType.RunningNoPhysics or
                state == Enum.HumanoidStateType.Landed)
        end)
    
        if speed > 0.5 and onGround then
            local currentTime = tick()
            local speedMultiplier = math.clamp(speed / 16, 0.3, 2)
            local adjustedInterval = footstepInterval / (speedMultiplier * playbackSpeed)
    
            if currentTime - lastFootstepTime >= adjustedInterval then
                playFootstepSound()
                lastFootstepTime = currentTime
                leftFootstep = not leftFootstep
            end
        end
    end
    
    -- Binary search to find interpolation indices
    local function findInterpolationIndices(data, targetTime)
        if #data == 0 then
            return nil, nil, 0
        end
        
        if targetTime <= data[1].time then
            return 1, 1, 0
        end
        
        if targetTime >= data[#data].time then
            return #data, #data, 0
        end
        
        local left, right = 1, #data
        
        while left < (right - 1) do
            local mid = math.floor((left + right) / 2)
            
            if data[mid].time <= targetTime then
                left = mid
            else
                right = mid
            end
        end
        
        local index1, index2 = left, right
        local timeDelta = data[index2].time - data[index1].time
        local alpha = 0
        
        if timeDelta > 0 then
            alpha = math.clamp((targetTime - data[index1].time) / timeDelta, 0, 1)
        end
        
        return index1, index2, alpha
    end
    
    --| =========================================================== |--
    --| PATH FINDING FUNCTIONS                                      |--
    --| =========================================================== |--
    
    local function findNearestPointInPath(data, currentPos)
        local nearestIndex = 1
        local nearestDistance = math.huge
        
        for i, frame in ipairs(data) do
            local framePos = tableToVec(frame.position)
            local distance = (currentPos - framePos).Magnitude
            
            if distance < nearestDistance then
                nearestDistance = distance
                nearestIndex = i
            end
        end
        
        return nearestIndex, nearestDistance
    end
    
    local function isPlayerOnPath(currentPos, data, threshold)
        threshold = threshold or PATH_THRESHOLD
        local _, nearestDistance = findNearestPointInPath(data, currentPos)
        return nearestDistance <= threshold, nearestDistance
    end
    
    --| =========================================================== |--
    --| TOOL MANAGEMENT FUNCTIONS                                   |--
    --| =========================================================== |--

    local function equipToolByName(toolName)
        if not player or not character then
            return false
        end
        
        local backpack = player:FindFirstChild("Backpack")
        if not backpack then
            return false
        end
        
        local currentTool = character:FindFirstChildOfClass("Tool")
        if currentTool and currentTool.Name == toolName then
            return true
        end

        if currentTool then
            currentTool.Parent = backpack
            task.wait(0.05)
        end

        local tool = backpack:FindFirstChild(toolName)
        if tool and tool:IsA("Tool") then
            humanoid:EquipTool(tool)
            return true
        end
        
        return false
    end

    local function unlockToolEquip()
        toolLocked = false
        currentRecordedTool = nil
        
        if toolLockConnection then
            toolLockConnection:Disconnect()
            toolLockConnection = nil
        end
        
        if backpackConnection then
            backpackConnection:Disconnect()
            backpackConnection = nil
        end
    end

    local function lockToolEquip()
        if toolLocked then
            return
        end
        
        toolLocked = true

        if toolLockConnection then
            toolLockConnection:Disconnect()
        end
        
        toolLockConnection = character.ChildAdded:Connect(function(child)
            if not isWalking or not toolLocked or not currentRecordedTool then
                return
            end
            
            if child:IsA("Tool") and child.Name ~= currentRecordedTool then
                task.wait(0.05)
                if child.Parent == character then
                    child.Parent = player.Backpack
                end
                task.wait(0.05)
                equipToolByName(currentRecordedTool)
            end
        end)
        
        if backpackConnection then
            backpackConnection:Disconnect()
        end
        
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            backpackConnection = backpack.ChildRemoved:Connect(function(child)
                if not isWalking or not toolLocked or not currentRecordedTool then
                    return
                end

                if child:IsA("Tool") and child.Name ~= currentRecordedTool then
                    task.wait(0.05)
                    if child.Parent == character then
                        child.Parent = backpack
                    end
                    task.wait(0.05)
                    local currentTool = character:FindFirstChildOfClass("Tool")
                    if not currentTool or currentTool.Name ~= currentRecordedTool then
                        equipToolByName(currentRecordedTool)
                    end
                end
            end)
        end
    end

    --| =========================================================== |--
    --| PLAYBACK CONTROL FUNCTIONS                                  |--
    --| =========================================================== |--
    local function stopPlayback()
        isWalking = false
        
        if playbackConnection then
            playbackConnection:Disconnect()
            playbackConnection = nil
        end

        if character and humanoid then
            humanoid:Move(Vector3.new(0, 0, 0), false)
            if humanoid:GetState() ~= Enum.HumanoidStateType.Running and
                humanoid:GetState() ~= Enum.HumanoidStateType.RunningNoPhysics then
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
        
        unlockToolEquip()
    end
    
    local function walkToPosition(targetPos, callback)
        if not humanoid or not character then
            if callback then callback(false) end
            return
        end
        
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            if callback then callback(false) end
            return
        end
        
        local distance = (hrp.Position - targetPos).Magnitude
        
        if distance < ARRIVAL_THRESHOLD then
            if callback then callback(true) end
            return
        end
        
        local moveConnection
        local reached = false
        local timeout = false
        
        moveConnection = humanoid.MoveToFinished:Connect(function(isReached)
            reached = true
            if moveConnection then
                moveConnection:Disconnect()
                moveConnection = nil
            end
        end)
        
        humanoid:MoveTo(targetPos)
        
        local startTime = tick()
        local maxWaitTime = 20
        local lastDistance = distance
        local stuckTime = 0
        local lastStuckCheck = tick()
        
        local monitorLoop
        monitorLoop = RunService.Heartbeat:Connect(function()
            if not hrp or not hrp.Parent then
                if monitorLoop then monitorLoop:Disconnect() end
                return
            end
            
            local currentDistance = (hrp.Position - targetPos).Magnitude
        
            if currentDistance <= ARRIVAL_THRESHOLD then
                reached = true
                if monitorLoop then monitorLoop:Disconnect() end
                return
            end
            
            if (tick() - startTime) >= maxWaitTime then
                timeout = true
                if monitorLoop then monitorLoop:Disconnect() end
                return
            end
            
            local timeSinceLastCheck = tick() - lastStuckCheck
            if timeSinceLastCheck >= 0.5 then
                if math.abs(currentDistance - lastDistance) < 0.5 then
                    stuckTime = stuckTime + timeSinceLastCheck
                    if stuckTime > 2 then
                        humanoid:MoveTo(targetPos)
                        stuckTime = 0
                    end
                else
                    stuckTime = 0
                end
                lastDistance = currentDistance
                lastStuckCheck = tick()
            end
        end)
        
        while not reached and not timeout do
            task.wait(0.1)
        end
        
        if monitorLoop then
            monitorLoop:Disconnect()
        end
        
        if moveConnection then
            moveConnection:Disconnect()
            moveConnection = nil
        end
        
        if callback then
            callback(reached and not timeout)
        end
    end
    
    local function killCharacter()
        if character and character:FindFirstChild("Humanoid") then
            character.Humanoid.Health = 0
        end
    end

    clearPath()

local function startPlayback(data, startFrame)
    startFrame = math.clamp(startFrame or 1, 1, #data)
    if not data or #data == 0 then return end
    
    if isWalking then stopPlayback() end

    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local hum = character and character:FindFirstChildOfClass("Humanoid")

    if autoEquipToolEnabled then
        local targetTool = data[startFrame] and data[startFrame].tool
        if targetTool then
            currentRecordedTool = targetTool
            equipToolByName(targetTool)
            task.wait(0.15)
            lockToolEquip()
        else
            currentRecordedTool = nil
            if hum then hum:UnequipTools() end
            unlockToolEquip()
        end
    end

    if hrp and hum and data[startFrame] then
        local firstSample = data[startFrame]
        local recordedHipHeight = firstSample.hipHeight or 2
        heightOffset = hum.HipHeight - recordedHipHeight
        
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end

    isWalking = true
    local playbackTime = (data[startFrame].time or 0)
    local lastToolCheck = 0
    local TOOL_CHECK_INTERVAL = 0.5
    local jumpTriggered = false
    local accumulatedTime = 0 
    local currentFlipRotation = 0 
    local isWaitingForLoop = false

    if playbackConnection then
        playbackConnection:Disconnect()
        playbackConnection = nil
    end

    playbackConnection = RunService.Heartbeat:Connect(function(deltaTime)
        -- CEK: Jika sedang menunggu loop, hentikan interpolasi
        if not isWalking or isWaitingForLoop or not hrp or not hum then return end
        
        local dt = math.min(deltaTime, 0.033)
        accumulatedTime += dt

        if isReversed then
            playbackTime = playbackTime - (dt * playbackSpeed)
            if playbackTime <= (data[1].time or 0) then
                if isLoopEnabled then 
                    playbackTime = data[#data].time 
                else 
                    stopPlayback() 
                    return 
                end
            end
        else
            playbackTime = playbackTime + (dt * playbackSpeed)
        end
        
        -- LOGIKA LOOP DENGAN AUTO RESPAWN
        local maxTime = data[#data].time
        
        if not isReversed and playbackTime > maxTime then
            if isLoopEnabled or isAutoRespawnEnabled then
                -- CEK: Auto Respawn aktif
                if isAutoRespawnEnabled then
                    -- Matikan walking dulu
                    isWaitingForLoop = true
                    isWalking = false
                    
                    -- Hentikan movement
                    if hum then
                        hum:Move(Vector3.new(0, 0, 0), false)
                    end
                    
                    if hrp then
                        hrp.AssemblyLinearVelocity = Vector3.zero
                    end
                    
                    -- Disconnect playback sementara
                    if playbackConnection then
                        playbackConnection:Disconnect()
                        playbackConnection = nil
                    end
                    
                    -- Kill character
                    if character and character:FindFirstChild("Humanoid") then
                        character.Humanoid.Health = 0
                    end
                    
                    -- Set flag untuk restart setelah respawn
                    shouldRestartAfterRespawn = true
                    return
                else
                    -- Loop biasa (tanpa respawn)
                    isWaitingForLoop = true
                    
                    if WindUI then
                        WindUI:Notify({
                            Title = "Enable Looping",
                            Content = "Tunggu sebentar...",
                            Duration = 2,
                            Icon = "refresh-cw",
                        })
                    end
                    
                    -- Delay 2 detik, lalu jalan ke awal
                    task.delay(2, function()
                        if not isWalking then isWaitingForLoop = false return end
            
                        if hrp and hrp.Parent and data[1] then
                            local firstPosTable = data[1].position
                            local firstPosition = Vector3.new(firstPosTable.x, firstPosTable.y, firstPosTable.z)
                            
                            -- Walk to first position
                            hum:MoveTo(firstPosition)
                            local reached = false
                            local connection
                            connection = hum.MoveToFinished:Connect(function()
                                reached = true
                            end)
            
                            -- Tunggu sampai sampai (timeout 10 detik)
                            local startTime = tick()
                            while not reached and (tick() - startTime) < 10 do
                                task.wait(0.1)
                                if hum then hum:MoveTo(firstPosition) end
                            end
                            
                            if connection then connection:Disconnect() end
                            
                            -- Reset playback
                            playbackTime = data[1].time or 0
                            accumulatedTime = 0
                            currentFlipRotation = 0
                            
                            -- Equip tool awal
                            if data[1].tool then
                                currentRecordedTool = data[1].tool
                                task.defer(function() equipToolByName(currentRecordedTool) end)
                            else
                                currentRecordedTool = nil
                                task.defer(function() if hum then hum:UnequipTools() end end)
                            end
                        end
            
                        isWaitingForLoop = false
                    end)
                    return
                end
            else
                stopPlayback()
                return
            end
            return
        end

        -- SISANYA: INTERPOLASI POSISI, ROTASI, DLL (TETAP SAMA)
        local index1, index2, alpha = findInterpolationIndices(data, playbackTime)
        local f0, f1 = data[index1], data[index2]
        if not f0 or not f1 then return end

        local p0, p1 = tableToVec(f0.position), tableToVec(f1.position)
        local v0, v1 = tableToVec(f0.velocity or {0,0,0}), tableToVec(f1.velocity or {0,0,0})
        
        local interpPos = p0:Lerp(p1, alpha)
        local interpVel = v0:Lerp(v1, alpha)
        
        local recordedYaw = lerpAngle(f0.rotation or 0, f1.rotation or f0.rotation, alpha)

        local targetFlip = (isFlipped) and math.pi or 0
        currentFlipRotation = lerpAngle(currentFlipRotation, targetFlip, 1 - math.exp(-14 * dt))
        
        local finalYaw = recordedYaw + currentFlipRotation

        if isReversed then
            interpVel = -interpVel
            finalYaw = finalYaw + math.pi
        end

        local targetCFrame = CFrame.new(interpPos.X, interpPos.Y + heightOffset, interpPos.Z) * CFrame.Angles(0, finalYaw, 0)
        local transitionScale = math.clamp(accumulatedTime * 1.5, 0.1, 1) 
        local lerpWeight = 1 - math.exp(-25 * dt) 
        
        hrp.CFrame = hrp.CFrame:Lerp(targetCFrame, lerpWeight * transitionScale)

        local stateNow = f0.state or "Running"
        local m0 = f0.moveDirection and tableToVec(f0.moveDirection) or Vector3.zero
        local m1 = f1.moveDirection and tableToVec(f1.moveDirection) or m0
        local interpMove = m0:Lerp(m1, alpha)

        if stateNow == "Jumping" or stateNow == "Freefall" or stateNow == "Climbing" or stateNow == "Swimming" or f0.jumping then
            hrp.AssemblyLinearVelocity = interpVel
            if not jumpTriggered then
                jumpTriggered = true
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
            hum:Move(interpMove * 0.1, false) 
        else
            hrp.AssemblyLinearVelocity = Vector3.new(interpVel.X, -0.4, interpVel.Z)
            jumpTriggered = false
            hum:Move(interpMove, false)
        end

        if autoEquipToolEnabled and (tick() - lastToolCheck) >= TOOL_CHECK_INTERVAL then
            lastToolCheck = tick()
            if f0.tool then
                if f0.tool ~= currentRecordedTool then
                    currentRecordedTool = f0.tool
                    task.defer(function() equipToolByName(currentRecordedTool) end)
                end
            else
                if currentRecordedTool ~= nil then
                    currentRecordedTool = nil
                    task.defer(function() if hum then hum:UnequipTools() end end)
                end
            end
        end

        if typeof(simulateNaturalMovement) == "function" then
            simulateNaturalMovement(interpMove, interpVel, hrp)
        end
    end)
end

    --| =========================================================== |--
    --| KEYBINDS HANDLER                                            |--
    --| =========================================================== |--

    local isLoadingTrack = false

	local function loadTrackData()
		if isLoadingTrack then return false end

		-- â CEK FILE BUKAN URL
		if not selectedTrackFile then
			WindUI:Notify({
				Title = "Auto Walk",
				Content = "Silakan pilih track terlebih dahulu!",
				Duration = 3,
				Icon = "triangle-alert",
			})
			return false
		end

		if not cachedJsonData then
			isLoadingTrack = true

			WindUI:Notify({
				Title = "Loading",
				Content = "Checking file json...",
				Duration = 1.5,
				Icon = "folder",
			})

			local jsonData, errorMsg = loadJsonFromFile(selectedTrackFile)

			if not jsonData then
				isLoadingTrack = false
				WindUI:Notify({
					Title = "Error",
					Content = errorMsg or "Gagal memuat track!",
					Duration = 4,
					Icon = "alert-triangle",
				})
				return false
			end

			cachedJsonData = jsonData
			isLoadingTrack = false

			WindUI:Notify({
				Title = "Success",
				Content = "Checkpoint siap!",
				Duration = 1.5,
				Icon = "check",
			})
		end

		return true
	end

    local function startAutoWalkFromNearest()
        if isWalking then return end

        if not loadTrackData() then 
            return 
        end
        
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            WindUI:Notify({
                Title = "Error",
                Content = "Character tidak ditemukan!",
                Duration = 2,
                Icon = "alert-triangle",
            })
            return
        end

        local currentPos = hrp.Position
        local nearestIndex, nearestDistance = findNearestPointInPath(cachedJsonData, currentPos)
        local MAX_PLAY_DISTANCE = 50
        
        if nearestDistance > MAX_PLAY_DISTANCE then
            WindUI:Notify({
                Title = "Auto Walk",
                Content = string.format("Terlalu jauh dari jalur (%.1f studs)!", nearestDistance),
                Duration = 3,
                Icon = "bot",
            })
            return
        end

        local onPath = isPlayerOnPath(currentPos, cachedJsonData, PATH_THRESHOLD)
        if onPath then
            startPlayback(cachedJsonData, nearestIndex)
        else
            local targetFrame = cachedJsonData[nearestIndex]
            local targetPos = tableToVec(targetFrame.position)
            walkToPosition(targetPos, function(success)
                if success then
                    startPlayback(cachedJsonData, nearestIndex)
                end
            end)
        end
    end

    local function stopAutoWalk()
        if not isWalking then return end
        stopPlayback()
    end

    local function toggleAutoWalkViaKeybind()
        if not isAutoWalkVisible then
            return
        end
        
        -- Toggle berdasarkan status isWalking saja
        if isWalking then
            stopAutoWalk()
        else
            startAutoWalkFromNearest()
        end
    end

    -- Setup keybind
    local function setupKeybinds()
        if keybindConnection then
            keybindConnection:Disconnect()
            keybindConnection = nil
        end
        
        keybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            
            if input.KeyCode == playStopKeybind then
                toggleAutoWalkViaKeybind()
            end
            
            if input.KeyCode == flipRotateKeybind then
                isFlipped = not isFlipped
                if autoWalkGUI and autoWalkGUI.Enabled then
                    local container = autoWalkGUI:FindFirstChild("MainFrame", true)
                    if container then
                        container = container:FindFirstChild("container")
                        if container then
                            for _, child in pairs(container:GetChildren()) do
                                if child:IsA("TextButton") and child.Text == "FLIP" then
                                    child.BackgroundColor3 = isFlipped and Color3.fromRGB(30, 180, 80) or Color3.fromRGB(35, 35, 40)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
    
    --| =========================================================== |--
    --| AUTO WALK GUI CONTROLLER                                    |--
    --| =========================================================== |--
    
	local function createAutoWalkGUI()
		if autoWalkGUI then
			autoWalkGUI.Enabled = true
			return
		end

		local playerGui = player:WaitForChild("PlayerGui")

		autoWalkGUI = Instance.new("ScreenGui")
		autoWalkGUI.Name = "AutoWalkControlGUI"
		autoWalkGUI.ResetOnSpawn = false
		autoWalkGUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

		local success = pcall(function()
			autoWalkGUI.Parent = game:GetService("CoreGui")
		end)
		if not success then
			autoWalkGUI.Parent = playerGui
		end

		local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		
		-- Main Container untuk semua elemen
		local mainContainer = Instance.new("Frame")
		mainContainer.Name = "MainContainer"
		if isMobile then
			mainContainer.Size = UDim2.new(0, 280, 0, 55)
			mainContainer.Position = UDim2.new(0.5, -140, 1, -100)
		else
			mainContainer.Size = UDim2.new(0, 420, 0, 90)
			mainContainer.Position = UDim2.new(0.5, -210, 1, -140)
		end
		mainContainer.BackgroundTransparency = 1
		mainContainer.Active = true
		mainContainer.Selectable = true
		mainContainer.Parent = autoWalkGUI

		-- LEFT WING BARS (2 garis vertikal di kiri)
		local leftWingContainer = Instance.new("Frame")
		leftWingContainer.Name = "LeftWingContainer"
		if isMobile then
			leftWingContainer.Size = UDim2.new(0, 16, 0, 48)
			leftWingContainer.Position = UDim2.new(0, 10, 0.5, -24)
		else
			leftWingContainer.Size = UDim2.new(0, 26, 0, 75)
			leftWingContainer.Position = UDim2.new(0, 15, 0.5, -37.5)
		end
		leftWingContainer.BackgroundTransparency = 1
		leftWingContainer.Active = true
		leftWingContainer.Parent = mainContainer

		-- Garis pertama (lebih kecil, paling luar)
		local leftBar1 = Instance.new("Frame")
		leftBar1.Name = "LeftBar1"
		if isMobile then
			leftBar1.Size = UDim2.new(0, 3, 0.7, 0)
			leftBar1.Position = UDim2.new(0, 0, 0.15, 0)
		else
			leftBar1.Size = UDim2.new(0, 6, 0.7, 0)
			leftBar1.Position = UDim2.new(0, 0, 0.15, 0)
		end
		leftBar1.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		leftBar1.BorderSizePixel = 0
		leftBar1.Parent = leftWingContainer
		
		local bar1Corner = Instance.new("UICorner")
		bar1Corner.CornerRadius = UDim.new(1, 0)
		bar1Corner.Parent = leftBar1
		
		local bar1Stroke = Instance.new("UIStroke")
		bar1Stroke.Color = Color3.fromRGB(70, 70, 70)
		bar1Stroke.Thickness = 1
		bar1Stroke.Parent = leftBar1

		-- Garis kedua (lebih besar, di dalam)
		local leftBar2 = Instance.new("Frame")
		leftBar2.Name = "LeftBar2"
		if isMobile then
			leftBar2.Size = UDim2.new(0, 5, 1, 0)
			leftBar2.Position = UDim2.new(0, 11, 0, 0)
		else
			leftBar2.Size = UDim2.new(0, 8, 1, 0)
			leftBar2.Position = UDim2.new(0, 18, 0, 0)
		end
		leftBar2.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		leftBar2.BorderSizePixel = 0
		leftBar2.Parent = leftWingContainer
		
		local bar2Corner = Instance.new("UICorner")
		bar2Corner.CornerRadius = UDim.new(1, 0)
		bar2Corner.Parent = leftBar2
		
		local bar2Stroke = Instance.new("UIStroke")
		bar2Stroke.Color = Color3.fromRGB(70, 70, 70)
		bar2Stroke.Thickness = 1
		bar2Stroke.Parent = leftBar2

		-- RIGHT WING BARS (2 garis vertikal di kanan)
		local rightWingContainer = Instance.new("Frame")
		rightWingContainer.Name = "RightWingContainer"
		if isMobile then
			rightWingContainer.Size = UDim2.new(0, 16, 0, 48)
			rightWingContainer.Position = UDim2.new(1, -27, 0.5, -24)
		else
			rightWingContainer.Size = UDim2.new(0, 26, 0, 75)
			rightWingContainer.Position = UDim2.new(1, -42, 0.5, -37.5)
		end
		rightWingContainer.BackgroundTransparency = 1
		rightWingContainer.Active = true
		rightWingContainer.Parent = mainContainer

		-- Garis kedua (lebih besar, di dalam)
		local rightBar2 = Instance.new("Frame")
		rightBar2.Name = "RightBar2"
		if isMobile then
			rightBar2.Size = UDim2.new(0, 5, 1, 0)
			rightBar2.Position = UDim2.new(0, 2, 0, 0)
		else
			rightBar2.Size = UDim2.new(0, 8, 1, 0)
			rightBar2.Position = UDim2.new(0, 2, 0, 0)
		end
		rightBar2.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		rightBar2.BorderSizePixel = 0
		rightBar2.Parent = rightWingContainer
		
		local rbar2Corner = Instance.new("UICorner")
		rbar2Corner.CornerRadius = UDim.new(1, 0)
		rbar2Corner.Parent = rightBar2
		
		local rbar2Stroke = Instance.new("UIStroke")
		rbar2Stroke.Color = Color3.fromRGB(70, 70, 70)
		rbar2Stroke.Thickness = 1
		rbar2Stroke.Parent = rightBar2

		-- Garis pertama (lebih kecil, paling luar)
		local rightBar1 = Instance.new("Frame")
		rightBar1.Name = "RightBar1"
		if isMobile then
			rightBar1.Size = UDim2.new(0, 3, 0.7, 0)
			rightBar1.Position = UDim2.new(1, -3, 0.15, 0)
		else
			rightBar1.Size = UDim2.new(0, 6, 0.7, 0)
			rightBar1.Position = UDim2.new(1, -6, 0.15, 0)
		end
		rightBar1.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		rightBar1.BorderSizePixel = 0
		rightBar1.Parent = rightWingContainer
		
		local rbar1Corner = Instance.new("UICorner")
		rbar1Corner.CornerRadius = UDim.new(1, 0)
		rbar1Corner.Parent = rightBar1
		
		local rbar1Stroke = Instance.new("UIStroke")
		rbar1Stroke.Color = Color3.fromRGB(70, 70, 70)
		rbar1Stroke.Thickness = 1
		rbar1Stroke.Parent = rightBar1

		-- CENTER FRAME (Controller utama)
		local mainFrame = Instance.new("Frame")
		mainFrame.Name = "MainFrame"
		if isMobile then
			mainFrame.Size = UDim2.new(0, 215, 0, 48)
			mainFrame.Position = UDim2.new(0.5, -107.5, 0.5, -24)
		else
			mainFrame.Size = UDim2.new(0, 320, 0, 75)
			mainFrame.Position = UDim2.new(0.5, -160, 0.5, -37.5)
		end
		mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		mainFrame.BorderSizePixel = 0
		mainFrame.Active = true
		mainFrame.Selectable = true
		mainFrame.Parent = mainContainer

		-- TOP DRAG BAR (mirror dari bottom)
		local topDragBar = Instance.new("Frame")
		topDragBar.Name = "TopDragBar"
		topDragBar.Size = UDim2.new(0.6, 0, 0, isMobile and 5 or 8)
		topDragBar.Position = UDim2.new(0.2, 0, 0, -(isMobile and 11 or 15))
		topDragBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		topDragBar.BorderSizePixel = 0
		topDragBar.Active = true
		topDragBar.Selectable = true
		topDragBar.Parent = mainFrame

		local topCorner = Instance.new("UICorner")
		topCorner.CornerRadius = UDim.new(1, 0)
		topCorner.Parent = topDragBar

		local topStroke = Instance.new("UIStroke")
		topStroke.Color = Color3.fromRGB(80, 80, 80)
		topStroke.Thickness = 1
		topStroke.Parent = topDragBar

		topDragBar.MouseEnter:Connect(function()
			topDragBar.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		end)
		topDragBar.MouseLeave:Connect(function()
			topDragBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		end)
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = mainFrame
		
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(60, 60, 60)
		stroke.Thickness = 1.5
		stroke.Parent = mainFrame
		
		local dragBar = Instance.new("Frame")
		dragBar.Name = "DragBar"
		dragBar.Size = UDim2.new(0.6, 0, 0, isMobile and 5 or 8)
		dragBar.Position = UDim2.new(0.2, 0, 1, isMobile and 4 or 7)
		dragBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		dragBar.BorderSizePixel = 0
		dragBar.Active = true
		dragBar.Selectable = true
		dragBar.Parent = mainFrame
		
		local dragCorner = Instance.new("UICorner")
		dragCorner.CornerRadius = UDim.new(1, 0)
		dragCorner.Parent = dragBar
		
		local dragStroke = Instance.new("UIStroke")
		dragStroke.Color = Color3.fromRGB(80, 80, 80)
		dragStroke.Thickness = 1
		dragStroke.Parent = dragBar
		
		dragBar.MouseEnter:Connect(function()
			dragBar.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		end)
		dragBar.MouseLeave:Connect(function()
			dragBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		end)

		local dragging = false
		local dragInput, dragStart, startPos

		local function update(input)
			local delta = input.Position - dragStart
			mainContainer.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end

		local function startDrag(input)
			dragging = true
			dragStart = input.Position
			startPos = mainContainer.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end

		local function connectDragArea(guiObject)
			guiObject.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or 
					input.UserInputType == Enum.UserInputType.Touch then
					startDrag(input)
				end
			end)

			guiObject.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement or
					input.UserInputType == Enum.UserInputType.Touch then
					dragInput = input
				end
			end)
		end

		connectDragArea(mainFrame)
		connectDragArea(dragBar)
		connectDragArea(leftWingContainer)
		connectDragArea(rightWingContainer)
		connectDragArea(topDragBar)

		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or 
					input.UserInputType == Enum.UserInputType.Touch) then
				update(input)
			end
		end)

		local container = Instance.new("Frame")
		container.Name = "container"
		container.Size = UDim2.new(1, -12, 1, -12)
		container.Position = UDim2.new(0, 6, 0, 6)
		container.BackgroundTransparency = 1
		container.Parent = mainFrame

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, isMobile and 6 or 12)
		layout.Parent = container

		local function createButton(icon, callback)
			local btn = Instance.new("TextButton")
			if isMobile then
				btn.Size = UDim2.new(0, 58, 0, 32)
			else
				btn.Size = UDim2.new(0, 88, 0, 48)
			end
			btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
			btn.BorderSizePixel = 0
			btn.Text = icon
			btn.TextColor3 = Color3.fromRGB(220, 220, 220)
			btn.TextSize = isMobile and 10 or 13
			btn.Font = Enum.Font.GothamBold
			btn.AutoButtonColor = false
			btn.Parent = container

			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, isMobile and 7 or 10)
			c.Parent = btn

			local s = Instance.new("UIStroke")
			s.Color = Color3.fromRGB(70, 70, 70)
			s.Thickness = isMobile and 1 or 1.5
			s.Parent = btn

			btn.MouseEnter:Connect(function()
				btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
			end)
			btn.MouseLeave:Connect(function()
				local currentColor = btn.BackgroundColor3
				if currentColor ~= Color3.fromRGB(80, 80, 80) and currentColor ~= Color3.fromRGB(100, 100, 100) then
					btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
				end
			end)

			btn.Activated:Connect(function()
				if callback then 
					callback(btn)
				end
			end)
			
			return btn
		end

		local playBtn = createButton("PLAY", function(btn)
			if not isWalking then
				
				btn.Text = "STOP"
				
				startAutoWalkFromNearest()
			else
				
				stopAutoWalk()
				btn.Text = "PLAY"
			end
		end)
		playBtn.Name = "PlayButton"

		local rollbackBtn = createButton("REV", function(btn)
			isReversed = not isReversed
			if isReversed then
				btn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
			else
				btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
			end
		end)

		local rotateBtn = createButton("FLIP", function(btn)
			isFlipped = not isFlipped
			if isFlipped then
				btn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			else
				btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
			end
		end)
		
		if isMobile and not UserInputService.KeyboardEnabled then
			WindUI:Notify({
				Title = "Mobile Mode",
				Content = "Gunakan tombol UI untuk kontrol",
				Duration = 2,
				Icon = "smartphone",
			})
		end
	end

	local function destroyAutoWalkGUI()
		if autoWalkGUI then
			autoWalkGUI:Destroy()
			autoWalkGUI = nil
		end
		
		if keybindConnection then
			keybindConnection:Disconnect()
			keybindConnection = nil
		end
	end

	local function hideAutoWalkGUI()
		if autoWalkGUI and autoWalkGUI.Parent then
			autoWalkGUI.Enabled = false
		end
	end



    --| =========================================================== |--
    --| GOD MODE FUNCTIONS                                          |--
    --| =========================================================== |--
    
    local function enableGodMode()
        godModeEnabled = true
        task.spawn(function()
            while godModeEnabled do
                local currentChar = player.Character or player.CharacterAdded:Wait()
                local currentHumanoid = currentChar:FindFirstChildOfClass("Humanoid")

                if currentHumanoid then
                    currentHumanoid.Health = currentHumanoid.MaxHealth
                    currentHumanoid.HealthChanged:Connect(function()
                        if godModeEnabled and currentHumanoid.Health < currentHumanoid.MaxHealth then
                            currentHumanoid.Health = currentHumanoid.MaxHealth
                        end
                    end)

                    currentHumanoid.Died:Connect(function()
                        if godModeEnabled then
                            task.wait(0.1)
                            player:LoadCharacter()
                            task.wait(1)
                            enableGodMode()
                        end
                    end)
                    for _, conn in pairs(getconnections(currentHumanoid.StateChanged)) do
                        conn:Disable()
                    end
                    currentHumanoid.BreakJointsOnDeath = false
                end

                task.wait(0.2)
            end
        end)
    end

    local function disableGodMode()
        godModeEnabled = false
    end
    
--| =========================================================== |--
--| CHARACTER RESPAWN HANDLER (FIXED VERSION - SCAN 50 STUDS)  |--
--| =========================================================== |--

player.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid = character:WaitForChild("Humanoid")
    humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    
    -- Matikan playback jika sedang berjalan
    if isWalking then
        stopPlayback()
    end

    -- CEK: Apakah perlu restart setelah respawn?
    if shouldRestartAfterRespawn then
        shouldRestartAfterRespawn = false
        
        -- Notifikasi respawn
        WindUI:Notify({
            Title = "Auto Respawn",
            Content = "Karakter telah respawn, tunggu 2 detik...",
            Duration = 2,
            Icon = "refresh-cw",
        })
        
        -- Delay 2 detik untuk memastikan character siap
        task.wait(2)
        
        -- Cek apakah data masih ada
        if cachedJsonData and #cachedJsonData > 0 then
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local currentPos = hrp.Position
                
                -- Scan titik awal JSON (frame 1)
                local firstPosTable = cachedJsonData[1].position
                local firstPosition = Vector3.new(firstPosTable.x, firstPosTable.y, firstPosTable.z)
                local distanceToStart = (currentPos - firstPosition).Magnitude
                
                -- CEK: Apakah dalam radius 50 studs?
                if distanceToStart <= 50 then
                    -- Berada dalam radius 50 studs, walk to position
                    
                    walkToPosition(firstPosition, function(success)
                        if success then
                            task.wait(0.5) -- Delay kecil setelah sampai
                            startPlayback(cachedJsonData, 1)
                            
                        else
                            WindUI:Notify({
                                Title = "Auto Respawn",
                                Content = "Gagal mencapai titik awal!",
                                Duration = 3,
                                Icon = "alert-triangle",
                            })
                        end
                    end)
                else
                    
                    -- RESET semua state
                    isWalking = false
                    isWaitingForLoop = false
                    isReversed = false
                    isFlipped = false
                    currentFlipRotation = 0
                    
                    -- Hapus cache path visual
                    clearPath()
                    
                    -- Reset tombol PLAY di GUI
                    task.spawn(function()
                        if autoWalkGUI and autoWalkGUI.Enabled then
                            local mainFrame = autoWalkGUI:FindFirstChild("MainFrame")
                            if mainFrame then
                                local container = mainFrame:FindFirstChild("container")
                                if container then
                                    local playButton = container:FindFirstChild("PlayButton")
                                    if playButton and playButton:IsA("TextButton") then
                                        playButton.Text = "PLAY"
                                    end
                                end
                            end
                        end
                    end)
                    
                    -- Notifikasi tambahan
                    WindUI:Notify({
                        Title = "Auto Walk",
                        Content = "Looping berhenti! Terlalu jauh dari titik awal jalur.",
                        Duration = 3,
                        Icon = "bot",
                    })
                end
            end
        else
            WindUI:Notify({
                Title = "Error",
                Content = "Data track tidak ditemukan!",
                Duration = 3,
                Icon = "alert-triangle",
            })
        end
    end
end)
    
    --| =========================================================== |--
    --| INITIALIZE KEYBINDS                                         |--
    --| =========================================================== |--
    setupKeybinds()

    --| =========================================================== |--
    --| USER INTERFACE > AUTO WALK                                  |--
    --| =========================================================== |--
    
    AutowalkTab:Section({ 
        Title = "Keybinds",
        TextTransparency = 0.05,
        TextXAlignment = "Left",
        TextSize = 17,
    })

    AutowalkTab:Keybind({
        Title = "[â] Play/Stop Keybind",
        Desc = "Keybind untuk Play/Stop auto walk (Default: F)",
        Value = "F",
        Callback = function(v)
            playStopKeybind = Enum.KeyCode[v]
        end
    })

    AutowalkTab:Keybind({
        Title = "[â] Flip/Rotate Keybind",
        Desc = "Keybind untuk Flip/Rotate (Default: R)",
        Value = "R",
        Callback = function(v)
            flipRotateKeybind = Enum.KeyCode[v]
        end
    })

    AutowalkTab:Section({ 
        Title = "Settings",
        TextTransparency = 0.05,
        TextXAlignment = "Left",
        TextSize = 17,
    })

    AutowalkTab:Toggle({
        Title = "[â] Enable Loop",
        Desc = "Anda dapat menjalankan auto walk berulang ulang.",
        Value = false,
        Callback = function(state)
            isLoopEnabled = state
        end
    })

    AutowalkTab:Toggle({
        Title = "[â] Auto Respawn",
        Desc = "Respawn otomatis saat mencapai puncak summit.",
        Value = false,
        Callback = function(state)
            isAutoRespawnEnabled = state
        end
    })

    AutowalkTab:Toggle({
        Title = "[â] Enable God Mode",
        Desc = "Karakter tidak akan terkena fall damage.",
        Value = false,
        Callback = function(state)
            if state then
                enableGodMode()
            else
                disableGodMode()
            end
        end
    })

    AutowalkTab:Slider({
        Title = "[â] Speed Auto Walk",
        Desc = "Mengatur kecepatan auto walk.",
        Step = 0.1,
        Value = {
            Min = 0.5,
            Max = 1.2,
            Default = 1.0,
        },
        Callback = function(value)
            playbackSpeed = value
        end
    })

    AutowalkTab:Section({ 
        Title = "Controller",
        TextTransparency = 0.05,
        TextXAlignment = "Left",
        TextSize = 17,
    })


    -- Load maps data saat pertama kali
	task.spawn(function()
		loadMapsData()
	end)

	AutowalkTab:Dropdown({
		Title = "[â] Select Track",
		Values = getAvailableTracks(),
		Multi = false,
		AllowNone = true,
		SearchBarEnabled = true,
		Callback = function(selectedName)
			if not selectedName or selectedName == "[No JSON Found]" then
				return
			end

			local cleanName = selectedName
			local filePath = trackFiles[cleanName]

			if not filePath then
				WindUI:Notify({
					Title = "Error",
					Content = "File track tidak ditemukan!",
					Duration = 3,
					Icon = "x-circle",
				})
				return
			end
			selectedTrackFile = filePath
			selectedTrackName = cleanName
			cachedJsonData = nil

			WindUI:Notify({
				Title = "Track",
				Content = "Track '" .. cleanName .. "' dipilih!",
				Duration = 2,
				Icon = "check",
			})

			-- VISUAL PATH
			if showPath then
				local jsonData, err = loadJsonFromFile(filePath)
				if jsonData then
					cachedJsonData = jsonData
					drawPath(jsonData)
				end
			end
		end

	})

    AutowalkTab:Toggle({
    Title = "[â] Show Controller",
    Desc = "Menampilkan controller auto walk.",
    Value = false,
    Callback = function(state)
        isAutoWalkVisible = state
        	if state == true then
            	createAutoWalkGUI()
        	else
            	hideAutoWalkGUI()
        	end
    	end
	})

	AutowalkTab:Toggle({
		Title = "[â] Auto Equip Coil",
		Desc = "Karakter akan memegang coil secara otomatis.",
		Value = true,
		Callback = function(state)
			autoEquipToolEnabled = state
			if not state then
				unlockToolEquip()
			end
		end
	})

    AutowalkTab:Section({ 
    	Title = "Visual Path",
    	TextTransparency = 0.05,
    	TextXAlignment = "Left",
    	TextSize = 17,
	})


	AutowalkTab:Toggle({
		Title = "[â] Enable Visual Path",
		Desc = "Menampilkan jalur auto walk.",
		Icon = "map",
		Value = false,
		Callback = function(state)
			showPath = state

			-- CEK: Apakah sudah ada track yang dipilih?
			if not selectedTrackFile and not selectedJsonURL then
				clearPath()
				WindUI:Notify({
					Title = "Visual Path",
					Content = "Pilih track terlebih dahulu!",
					Duration = 2,
					Icon = "alert-triangle",
				})
				return
			end

			if state then
				-- Jika belum ada cached data, load dulu
				if not cachedJsonData then
					if selectedTrackFile then
						-- Load dari local file
						local jsonData, err = loadJsonFromFile(selectedTrackFile)
						if jsonData then
							cachedJsonData = jsonData
						else
							WindUI:Notify({
								Title = "Error",
								Content = "Gagal load track data!",
								Duration = 3,
								Icon = "x-circle",
							})
							clearPath()
							return
						end
					elseif selectedJsonURL then
						-- Load dari URL
						cachedJsonData = loadJsonFromURL(selectedJsonURL)
					end
				end

				-- Draw path dengan data yang sudah ada
				if cachedJsonData then
					drawPath(cachedJsonData)
				end
			else
				clearPath()
			end
		end
	})

	AutowalkTab:Slider({
		Title = "[â] Set Height Path",
		Desc = "Mengatur ketinggian pada visual path.",
		Step = 1,
		Value = {
			Min = -5.0,  -- Turun maksimal 20 studs
			Max = 5.0,   -- Naik maksimal 20 studs
			Default = 0.0, -- Default normal
		},
		Callback = function(value)
			pathHeightOffset = value
			
			-- Redraw visual path jika sedang aktif
			if showPath and cachedJsonData then
				clearPath()
				drawPath(cachedJsonData)
			end
		end
	})

	AutowalkTab:Colorpicker({
		Title = "[â] Visual Path Color",
		Default = pathColor,
		Callback = function(color)
			pathColor = color

			-- Hanya redraw jika visual path sedang aktif
			if showPath and pathFolder then
				clearPath()
				
				if cachedJsonData then
					drawPath(cachedJsonData)
				else
					WindUI:Notify({
						Title = "Visual Path",
						Content = "Tidak ada data path untuk ditampilkan!",
						Duration = 2,
						Icon = "info",
					})
				end
			end
		end
	})
end

setupAutowalkTab()

-- =========================
-- SETUP SOCIAL TAB
-- =========================
local function setupSocialTab()

local Section = SocialTab:Section({ 
    Title = "RullzsyHUB | Social Media",
    TextXAlignment = "Left",
    TextSize = 18,
})

SocialTab:Divider()

SocialTab:Paragraph({
    Title = "Official Links",
    Desc = "Berikut link social media RullzsyHUB."
})

SocialTab:Button({
    Title = "[â] TikTok | tiktok.com/@rullzsy99",
    Icon = "clipboard",
    Callback = function()
        setclipboard("https://www.tiktok.com/@rullzsy99")
        WindUI:Notify({
            Title = "Social",
            Content = "Link TikTok berhasil disalin.",
            Duration = 3,
            Icon = "clipboard",
        })
    end
})

SocialTab:Button({
    Title = "[â] Website | rullzsyhub.web.id",
    Icon = "clipboard",
    Callback = function()
        setclipboard("https://rullzsyhub.web.id")
        WindUI:Notify({
            Title = "Social",
            Content = "Link website berhasil disalin.",
            Duration = 3,
            Icon = "clipboard",
        })
    end
})

SocialTab:Button({
    Title = "[â] Discord | dsc.gg/rullzsyhub",
    Icon = "clipboard",
    Callback = function()
        setclipboard("https://dsc.gg/rullzsyhub")
        WindUI:Notify({
            Title = "Social",
            Content = "Link Discord berhasil disalin.",
            Duration = 3,
            Icon = "clipboard",
        })
    end
})

SocialTab:Button({
    Title = "[â] Rscripts | rscripts.net/@RullzsyHUB",
    Icon = "clipboard",
    Callback = function()
        setclipboard("https://rscripts.net/@RullzsyHUB")
        WindUI:Notify({
            Title = "Social",
            Content = "Link Rscripts berhasil disalin.",
            Duration = 3,
            Icon = "clipboard",
        })
    end
})

end

setupSocialTab()
-- =========================
-- SETUP SOCIAL TAB - END
-- =========================

-- =========================
-- SETUP CREDITS TAB
-- =========================
local Section = CreditsTab:Section({ 
    Title = "RullzsyHUB | Credits",
    TextXAlignment = "Left",
    TextSize = 18,
})

CreditsTab:Divider()

local Paragraph = CreditsTab:Paragraph({
	Title = "Special Thanks",
	Desc = "â Copy Avatar | Kurama\nâ Sky Box | Rex Rebels\nâ Emot Menu | Vexro Emot\nâ Liblary UI | WindUI",
})

local Paragraph = CreditsTab:Paragraph({
	Title = "Project Lead & Main Developer",
	Desc = "â @rullzsy_",
})

local Paragraph = CreditsTab:Paragraph({
	Title = "Developer",
	Desc = "â @_zee4you\nâ @dimszy16_\nâ @itsmekurama.",
})
-- =========================
-- SETUP CREDITS TAB - END
-- =========================

-- =========================
-- SETUP SETTINGS TAB
-- =========================

local function setupSettingsTab()

local Section = SettingsTab:Section({ 
    Title = "RullzsyHUB | Themes",
    TextXAlignment = "Left",
    TextSize = 18,
})

SettingsTab:Divider()

local Paragraph = SettingsTab:Paragraph({
	Title = "Themes UI",
	Desc = "Berfungsi untuk mengatur tema ui menjadi dark, red, white themes.",
})

local themes = {}
for themeName, _ in pairs(WindUI:GetThemes()) do
	table.insert(themes, themeName)
end
table.sort(themes)

local canchangedropdown = true

local themeDropdown = SettingsTab:Dropdown({
	Title = "[â] Themes",
	Values = themes,
	Flag = "themeDropdown",
	SearchBarEnabled = true,
	MenuWidth = 280,
	Value = "",
	Callback = function(theme)
		canchangedropdown = false
		WindUI:SetTheme(theme)
		canchangedropdown = true
	end
})

-- =========================
-- BACKGROUND PRESET
-- =========================

local backgroundPresets = {
    ["Original"]  = "133699862172739",
    ["Preset 1"]  = "113681604071004",
    ["Preset 2"]  = "118466592212014",
    ["Preset 3"]  = "123590736105154",
    ["Preset 4"]  = "89039084745401",
    ["Preset 5"]  = "119946779786225",
    ["Preset 6"]  = "89163107846805",
    ["Preset 7"]  = "101597362507181",
    ["Preset 8"]  = "129665877158593",
    ["Preset 9"]  = "120747412932340",
    ["Preset 10"] = "119640043344252",
}

-- Urutan preset supaya tampil rapi di dropdown
local presetOrder = {
    "Original",
    "Preset 1",  "Preset 2",  "Preset 3",  "Preset 4",
    "Preset 5",  "Preset 6",  "Preset 7",  "Preset 8",
    "Preset 9",  "Preset 10",
}

local backgroundDropdown = SettingsTab:Dropdown({
	Title = "[â] Background",
	Values = presetOrder,
	Flag = "backgroundDropdown",
	SearchBarEnabled = false,
	MenuWidth = 280,
	Value = "Original",
	Callback = function(preset)
		local assetId = backgroundPresets[preset]
		if assetId then
			Window:SetBackgroundImage("rbxassetid://" .. assetId)
		end
	end
})

-- =========================
-- BACKGROUND PRESET - END
-- =========================

local transparencySlider = SettingsTab:Slider({
	Title = "[â] Transparency",
	Value = { 
		Min = 0,
		Max = 1,
		Default = 0.5,
	},
	Flag = "transparencySlider",
	Step = 0.1,
	Callback = function(value)
		Window:SetBackgroundTransparency(value)
		Window:SetBackgroundImageTransparency(value)
	end
})

local Section = SettingsTab:Section({ 
    Title = "Open UI",
    TextXAlignment = "Left",
    TextSize = 18,
})

SettingsTab:Divider()

local Paragraph = SettingsTab:Paragraph({
	Title = "Keybinds Menu",
	Desc = "Berfungsi untuk mengatur keybinds open/minimize ui teruntuk user (PC).",
})

local Keybind = SettingsTab:Keybind({
    Title = "[â] Set Keybinds",
    Desc = "Click disini untuk mengganti keybinds.",
    Value = "P",
    Callback = function(v)
        Window:SetToggleKey(Enum.KeyCode[v])
    end
})

end

setupSettingsTab()

-- =========================
-- SETUP SETTINGS TAB - END
-- =========================


-- =========================
-- LOGOUT TAB
-- =========================
LogoutTab:Section({
    Title = "RullzsyHUB | Logout",
    TextSize = 18,
})

LogoutTab:Divider()

LogoutTab:Paragraph({
    Title = "Logout Session",
    Desc = "Logout akan menutup seluruh UI dan menghapus session login saat ini."
})

LogoutTab:Divider()

LogoutTab:Button({
    Title = "[â] Logout & Close UI",
    Icon = "log-out",
    Callback = function()
        getgenv().AUTH_KEY = ""

        WindUI:Notify({
            Title = "Logout",
            Content = "Anda berhasil log-out!",
            Duration = 2,
            Icon = "log-out",
        })

        task.delay(1.2, function()
            if Window and Window.Destroy then
                Window:Destroy()
            end

            for _, v in ipairs(game:GetService("CoreGui"):GetChildren()) do
                if v.Name:lower():find("windui") 
                or v.Name:lower():find("rullzsy") then
                    pcall(function()
                        v:Destroy()
                    end)
                end
            end
        end)
    end
})
-- =========================
-- LOGOUT TAB - END
-- =========================
