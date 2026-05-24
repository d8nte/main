-- Ensure the old instance is completely closed

if _G.FishingBotInstance then
    _G.FishingBotInstance()
end

-- ============================================
-- Rayfield Loadstring
-- ============================================

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "Indo Voice Hub",
   LoadingTitle = "By D8nte",
   LoadingSubtitle = "Made with Love, Enjoy!",
   ConfigurationSaving = {
      Enabled = false,
   },
   Discord = {
      Enabled = false
   },
   KeySystem = false
})

-- ============================================
-- Services
-- ============================================

local VirtualInputManager = game:GetService("VirtualInputManager")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Character   = LocalPlayer.Character
local Humanoid    = Character and Character:FindFirstChildOfClass("Humanoid")

task.spawn(function()
    if not Humanoid then
        Character = LocalPlayer.CharacterAdded:Wait()
        Humanoid  = Character:WaitForChild("Humanoid")
    end
end)

-- ============================================
-- Config Default
-- ============================================

local Config = {
    CAST_HOLD_DURATION   = 0.7,
    POST_PULL_DELAY      = 1.8,  
    PRE_END_DELAY        = 0.0,
    POST_END_DELAY       = 0.3,
    PRE_CAST_DELAY       = 0.3,
    VERIFY_CAST_TIMEOUT  = 2.5,
    WAITING_PULL_TIMEOUT = 20.0,
    POST_PULL_TIMEOUT    = 5.0,
}

-- ============================================
-- Profile System
-- ============================================

local PROFILE_FOLDER  = "d8nte_profiles"
local activeProfile   = "default"
local isProfileLoading = false
local profileLocked = true
local configWarningShown = false

if not isfolder(PROFILE_FOLDER) then
    makefolder(PROFILE_FOLDER)
end

local function profilePath(name)
    return PROFILE_FOLDER .. "/" .. name .. ".json"
end

local function encodeConfig(cfg)
    local parts = {}
    for k, v in pairs(cfg) do
        table.insert(parts, '"' .. k .. '":' .. tostring(v))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function decodeConfig(raw)
    local cfg = {}
    for k, v in string.gmatch(raw, '"([^"]+)":([%d%.]+)') do
        cfg[k] = tonumber(v)
    end
    return cfg
end

local function listProfiles()
    local files = {}
    if isfolder(PROFILE_FOLDER) then
        for _, f in ipairs(listfiles(PROFILE_FOLDER)) do
            local name = f:match("([^/\\]+)%.json$")
            if name then
                table.insert(files, name)
            end
        end
    end
    return files
end

local function saveProfile(name)
    if isProfileLoading then return end
    isProfileLoading = true

    local path = profilePath(name)
    writefile(path, encodeConfig(Config))
    print("[PROFILE] Saved → " .. name)

    isProfileLoading = false
end

local function loadProfile(name)
    if isProfileLoading then return false end
    isProfileLoading = true

    local path = profilePath(name)
    if isfile(path) then
        local raw = readfile(path)
        local loaded = decodeConfig(raw)

        for k, v in pairs(loaded) do
            if Config[k] ~= nil then
                Config[k] = v
            end
        end

        activeProfile = name
        print("[PROFILE] Loaded → " .. name)

        isProfileLoading = false
        return true
    else
        warn("[PROFILE] File tidak ditemukan: " .. name)

        isProfileLoading = false
        return false
    end
end

local function deleteProfile(name)
    if isProfileLoading then return end
    isProfileLoading = true

    local path = profilePath(name)
    if isfile(path) then
        delfile(path)
        print("[PROFILE] Deleted → " .. name)

        isProfileLoading = false
        return true
    else
        warn("[PROFILE] Tidak ada profile bernama: " .. name)

        isProfileLoading = false
        return false
    end
end

if not isfile(profilePath("default")) then
    saveProfile("default")
end

-- ============================================
-- Fishing State Variables
-- ============================================

local FISHING_ANIMATION_ID = "rbxassetid://107858786510758"
local PULL_ANIMATION_ID    = "rbxassetid://136444937709795"

local isBotRunning         = false
local isRodDetached        = true
local isCharacterMoving    = false
local isScriptLoaded       = true

local currentStage         = "Idle"
local stageProgressTime    = 0
local activeAnimationConnection = nil

local isCastVerified       = false
local isPullDetected       = false

local totalFishCaught      = 0
local timeoutCount         = 0

local timeoutPerStage = {
    ["Verify Cast"]    = 0,
    ["Waiting Pull"]   = 0,
    ["Post Pull Wait"] = 0,
    ["Catch"]          = 0,
}

-- Keybind
local fishingKeybind = Enum.KeyCode.Unknown

-- ============================================
-- Tabs
-- ============================================

local MainTab    = Window:CreateTab("Info")
local SecondTab  = Window:CreateTab("Fishing")
local ConfigTab  = Window:CreateTab("Config")
local ProfileTab = Window:CreateTab("Profiles")
local UnloadTab  = Window:CreateTab("Unload")

-- ============================================
-- Info Tab Labels
-- ============================================

local VersionLabel = MainTab:CreateLabel("Version: 1.1.0")
local LabelRod        = MainTab:CreateLabel("Rod: -")
local LabelStage      = MainTab:CreateLabel("Stage: [Idle]")
local LabelCaught     = MainTab:CreateLabel("Caught: 0")
local LabelActiveProf = MainTab:CreateLabel("Profile: default")
local LabelKeybind    = MainTab:CreateLabel("Keybind: (none)")
local LabelTOVerify   = MainTab:CreateLabel("  Cast: 0  Pull: 0  PostPull: 0  Catch: 0")
local LabelTimeout    = MainTab:CreateLabel("  Total: 0")
MainTab:CreateLabel("Timeouts:")
ConfigTab:CreateLabel("                                                        ⚠️ WARNING!!")
ConfigTab:CreateLabel("Config sudah optimal, Jangan ubah config jika anda tidak tau masing masing fungsinya karna bisa menyebabkan kick/ban!")

-- ============================================
-- UI Update Helpers
-- ============================================

local function updateCaughtUI()
    LabelCaught:Set("Caught: " .. tostring(totalFishCaught))
end

local function updateTimeoutUI()
    LabelTOVerify:Set("  Cast: " .. timeoutPerStage["Verify Cast"] ..
        "  Pull: " .. timeoutPerStage["Waiting Pull"] ..
        "  PostPull: " .. timeoutPerStage["Post Pull Wait"] ..
        "  Catch: " .. timeoutPerStage["Catch"])
    LabelTimeout:Set("  Total: " .. tostring(timeoutCount))
end

local function updateKeybindLabel()
    local name = fishingKeybind == Enum.KeyCode.Unknown and "(none)" or tostring(fishingKeybind):gsub("Enum.KeyCode.", "")
    LabelKeybind:Set("Keybind: " .. name)
end

local function updateActiveProfUI()
    LabelActiveProf:Set("Profile: " .. activeProfile)
end

-- ============================================
-- Slider References (untuk update saat load profile)
-- ============================================

local sliderRefs = {}

-- ============================================
-- Config Tab — Sliders
-- ============================================

ConfigTab:CreateLabel("⏱ Timing Casting")

local function makeSlider(tab, name, key, range, increment, suffix)
    local s = tab:CreateSlider({
        Name         = name,
        Range        = range,
        Increment    = increment,
        Suffix       = suffix,
        CurrentValue = Config[key],
        Callback     = function(Value)
            Config[key] = Value
        end,
    })
    sliderRefs[key] = s
    return s
end

makeSlider(ConfigTab, "Pre Cast Delay (s)",      "PRE_CAST_DELAY",       {0, 3},   0.1, "s")
makeSlider(ConfigTab, "Cast Hold Duration (s)",  "CAST_HOLD_DURATION",   {0.1, 3}, 0.1, "s")
makeSlider(ConfigTab, "Verify Cast Timeout (s)", "VERIFY_CAST_TIMEOUT",  {1, 10},  0.5, "s")

ConfigTab:CreateLabel("⏱ Timing Pull & Catch")

makeSlider(ConfigTab, "Waiting Pull Timeout (s)", "WAITING_PULL_TIMEOUT", {0, 60},  1,   "s")
makeSlider(ConfigTab, "Post Pull Delay (s)",      "POST_PULL_DELAY",      {0, 5},   0.1, "s")
makeSlider(ConfigTab, "Post Pull Timeout (s)",    "POST_PULL_TIMEOUT",    {1, 10},  0.5, "s")

ConfigTab:CreateLabel("⏱ Timing End Cycle")

makeSlider(ConfigTab, "Pre End Delay (s)",  "PRE_END_DELAY",  {0, 3}, 0.1, "s")
makeSlider(ConfigTab, "Post End Delay (s)", "POST_END_DELAY", {0, 5}, 0.1, "s")

ConfigTab:CreateLabel("🎣 Timeout → rod otomatis re-equip")

-- ============================================
-- Profile Tab — Create / Save / Load / List / Delete / Choose
-- ============================================

ProfileTab:CreateLabel("── Profile Management ──")

-- Label status operasi
local LabelProfileStatus = ProfileTab:CreateLabel("Status: Not Working")

local function setStatus(msg)
    LabelProfileStatus:Set("Status: " .. msg)
end

-- Label daftar profile
local LabelProfileList = ProfileTab:CreateLabel("Profiles: (loading...)")

local function refreshProfileListUI()
    local profiles = listProfiles()
    if #profiles == 0 then
        LabelProfileList:Set("Profiles: (kosong)")
    else
        LabelProfileList:Set("Profiles: " .. table.concat(profiles, ", "))
    end
end

refreshProfileListUI()

-- ── INPUT: Nama Profile ──────────────────────────────────────

local currentInputName = ""

ProfileTab:CreateInput({
    Name        = "Nama Profile",
    PlaceholderText = "Ketik nama profile...",
    RemoveTextAfterFocusLost = false,
    Callback    = function(Value)
        currentInputName = Value
    end,
})

-- ── CREATE ───────────────────────────────────────────────────

ProfileTab:CreateButton({
    Name     = "Create & Save Profile Baru",
    Callback = function()

        if profileLocked then return end

        local name = currentInputName:match("^%s*(.-)%s*$") -- trim
        if name == "" then
            setStatus("❌ Nama profile kosong!")
            return
        end
        if isfile(profilePath(name)) then
            setStatus("⚠️ Profile '" .. name .. "' sudah ada. Pakai Save untuk update.")
            return
        end
        saveProfile(name)
        activeProfile = name
        updateActiveProfUI()
        refreshProfileListUI()
        setStatus("✅ Profile '" .. name .. "' berhasil dibuat!")
    end,
})

-- ── SAVE ─────────────────────────────────────────────────────

ProfileTab:CreateButton({
    Name     = "Save ke Profile Aktif",
    Callback = function()

    if profileLocked then return end

        saveProfile(activeProfile)
        setStatus("💾 Saved ke profile '" .. activeProfile .. "'")
    end,
})

ProfileTab:CreateButton({
    Name     = "Save ke Profile (dari Input)",
    Callback = function()

        if profileLocked then return end    

        local name = currentInputName:match("^%s*(.-)%s*$")
        if name == "" then
            setStatus("❌ Nama profile kosong!")
            return
        end
        saveProfile(name)
        activeProfile = name
        updateActiveProfUI()
        refreshProfileListUI()
        setStatus("💾 Saved ke profile '" .. name .. "'")
    end,
})

-- ── LOAD ─────────────────────────────────────────────────────

ProfileTab:CreateButton({
    Name     = "Load Profile (dari Input)",
    Callback = function()

        if profileLocked then return end

        local name = currentInputName:match("^%s*(.-)%s*$")
        if name == "" then
            setStatus("❌ Nama profile kosong!")
            return
        end
        if loadProfile(name) then
            updateActiveProfUI()
            setStatus("📂 Loaded profile '" .. name .. "'")
            Rayfield:Notify({
                Title    = "Profile Loaded",
                Content  = "Profile '" .. name .. "' berhasil dimuat.\nConfig aktif sudah diperbarui.",
                Duration = 4,
            })
        else
            setStatus("❌ Profile '" .. name .. "' tidak ditemukan!")
        end
    end,
})

-- ── CHOOSE / LIST ─────────────────────────────────────────────

ProfileTab:CreateButton({
    Name     = "List Semua Profile",
    Callback = function()

        if profileLocked then return end

        refreshProfileListUI()
        local profiles = listProfiles()
        local msg = #profiles > 0
            and "📋 Ditemukan " .. #profiles .. " profile:\n" .. table.concat(profiles, "\n")
            or  "📋 Tidak ada profile tersimpan."
        setStatus(msg)
        print("[PROFILE LIST]")
        for _, p in ipairs(profiles) do
            print("  - " .. p .. (p == activeProfile and " ◀ aktif" or ""))
        end
    end,
})

ProfileTab:CreateButton({
    Name     = "Choose: Load Profile dari Daftar (via Input)",
    Callback = function()

        if profileLocked then return end

        local name = currentInputName:match("^%s*(.-)%s*$")
        if name == "" then
            local profiles = listProfiles()
            setStatus("Ketik salah satu: " .. table.concat(profiles, ", "))
            return
        end
        if loadProfile(name) then
            updateActiveProfUI()
            refreshProfileListUI()
            setStatus("✅ Aktif → '" .. name .. "'")
            Rayfield:Notify({
                Title    = "Profile Dipilih",
                Content  = "Profile aktif sekarang: " .. name,
                Duration = 3,
            })
        else
            local profiles = listProfiles()
            setStatus("❌ Tidak ada '" .. name .. "'. Tersedia: " .. table.concat(profiles, ", "))
        end
    end,
})

-- ── DELETE ────────────────────────────────────────────────────

ProfileTab:CreateButton({
    Name     = "Delete Profile (dari Input)",
    Callback = function()

        if profileLocked then return end

        local name = currentInputName:match("^%s*(.-)%s*$")
        if name == "" then
            setStatus("❌ Nama profile kosong!")
            return
        end
        if name == "default" then
            setStatus("⛔ Profile 'default' tidak bisa dihapus!")
            return
        end
        if name == activeProfile then
            setStatus("⚠️ Tidak bisa hapus profile yang sedang aktif!")
            return
        end
        if deleteProfile(name) then
            refreshProfileListUI()
            setStatus("🗑️ Profile '" .. name .. "' dihapus.")
        else
            setStatus("❌ Profile '" .. name .. "' tidak ditemukan!")
        end
    end,
})

ProfileTab:CreateLabel("─────────────────────────────")
ProfileTab:CreateLabel("💡 Ketik nama di input → klik tombol.")

-- ============================================
-- Rod Equip System
-- ============================================

local equipDebounce = false

local function getCurrentRod()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("Tool") and string.find(string.lower(v.Name), "rod") then
            return v
        end
    end
    return nil
end

local function getRodFromBackpack()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return nil end
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and string.find(string.lower(tool.Name), "rod") then
            return tool
        end
    end
    return nil
end

local function equipRod()
    if equipDebounce then return end
    equipDebounce = true

    local char = LocalPlayer.Character
    if not char then
        equipDebounce = false
        return
    end

    if getCurrentRod() then
        equipDebounce = false
        return
    end

    local rod = getRodFromBackpack()
    if rod then
        rod.Parent = char
        print("[ROD] Equipped: " .. rod.Name)
    else
        warn("[ROD] Tidak ada rod di backpack!")
    end

    task.wait(0.2)
    equipDebounce = false
end

local function reequipRod()
    local char = LocalPlayer.Character
    if not char then return end

    local current = getCurrentRod()
    if current then
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            current.Parent = backpack
            print("[ROD] Unequipped: " .. current.Name)
        end
    end

    task.wait(0.3)
    equipRod()
end

-- ============================================
-- Timeout Reset Helper (dengan Re-equip Rod)
-- ============================================

local function timeoutReset(stageName)
    timeoutCount = timeoutCount + 1
    if timeoutPerStage[stageName] ~= nil then
        timeoutPerStage[stageName] = timeoutPerStage[stageName] + 1
    end
    updateTimeoutUI()
    warn("[TIMEOUT] Stage '" .. stageName .. "' → unequip & re-equip rod. Total: " .. timeoutCount)

    if activeAnimationConnection then
        activeAnimationConnection:Disconnect()
        activeAnimationConnection = nil
    end

    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)

    currentStage        = "Idle"
    stageProgressTime   = 0
    isCastVerified      = false
    isPullDetected      = false

    task.spawn(reequipRod)
end

-- ============================================
-- Rod & State Checker
-- ============================================

local function isRod(toolName)
    return string.find(string.lower(toolName), "rod")
end

local function checkRodAndState()
    if not isScriptLoaded then return end

    local tool = Character and Character:FindFirstChildOfClass("Tool")
    if tool and isRod(tool.Name) then
        isRodDetached = false
    else
        isRodDetached = true
        if activeAnimationConnection then
            activeAnimationConnection:Disconnect()
            activeAnimationConnection = nil
        end
        if isBotRunning then
            currentStage      = "Idle"
            stageProgressTime = 0
        end
    end

    if Humanoid then
        if Humanoid.MoveDirection.Magnitude > 0.1 then
            isCharacterMoving = true
            if activeAnimationConnection then
                activeAnimationConnection:Disconnect()
                activeAnimationConnection = nil
            end
            if isBotRunning and currentStage == "Casting" then
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            end
        else
            isCharacterMoving = false
        end
    end
end

local childAddedConn, childRemovedConn

local function setupCharacterEvents(char)
    Character = char
    Humanoid  = char:WaitForChild("Humanoid")

    if childAddedConn  then childAddedConn:Disconnect()  end
    if childRemovedConn then childRemovedConn:Disconnect() end

    childAddedConn   = char.ChildAdded:Connect(checkRodAndState)
    childRemovedConn = char.ChildRemoved:Connect(checkRodAndState)

    checkRodAndState()
end

LocalPlayer.CharacterAdded:Connect(setupCharacterEvents)
if Character then setupCharacterEvents(Character) end

local heartbeatConnection
heartbeatConnection = RunService.Heartbeat:Connect(function()
    if not isScriptLoaded then
        heartbeatConnection:Disconnect()
        return
    end
    checkRodAndState()
end)

-- ============================================
-- Main Fishing Engine
-- ============================================

local function startFishingEngine()
    while isBotRunning and isScriptLoaded do
        if not Character or not Humanoid then task.wait(0.5) continue end

        if isRodDetached or isCharacterMoving then
            task.wait(0.1)
            continue
        end

        -- ── IDLE ──────────────────────────────────────────────────
        if currentStage == "Idle" then
            local tool = Character:FindFirstChildOfClass("Tool")
            if tool and isRod(tool.Name) and not isCharacterMoving then
                task.wait(Config.PRE_CAST_DELAY)
                if isCharacterMoving or isRodDetached or not isBotRunning or not isScriptLoaded then continue end

                currentStage      = "Casting"
                stageProgressTime = 0
                isCastVerified    = false
                isPullDetected    = false

                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            end

        -- ── CASTING ───────────────────────────────────────────────
        elseif currentStage == "Casting" then
            if stageProgressTime < Config.CAST_HOLD_DURATION then
                stageProgressTime = stageProgressTime + 0.05
                task.wait(0.05)
            else
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                currentStage      = "Verify Cast"
                stageProgressTime = 0
            end

        -- ── VERIFY CAST ───────────────────────────────────────────
        elseif currentStage == "Verify Cast" then
            if not activeAnimationConnection then
                activeAnimationConnection = Humanoid.AnimationPlayed:Connect(function(animationTrack)
                    if animationTrack.Animation.AnimationId == FISHING_ANIMATION_ID then
                        isCastVerified = true
                        if activeAnimationConnection then activeAnimationConnection:Disconnect() end
                    end
                end)
            end

            if isCastVerified then
                activeAnimationConnection = nil
                currentStage      = "Waiting Pull"
                stageProgressTime = 0
            else
                stageProgressTime = stageProgressTime + 0.05
                if stageProgressTime > Config.VERIFY_CAST_TIMEOUT then
                    timeoutReset("Verify Cast")
                end
                task.wait(0.05)
            end

        -- ── WAITING PULL ──────────────────────────────────────────
        elseif currentStage == "Waiting Pull" then
            if not activeAnimationConnection then
                activeAnimationConnection = Humanoid.AnimationPlayed:Connect(function(animationTrack)
                    if animationTrack.Animation.AnimationId == PULL_ANIMATION_ID then
                        isPullDetected = true
                        if activeAnimationConnection then activeAnimationConnection:Disconnect() end
                    end
                end)
            end

            if isPullDetected then
                activeAnimationConnection = nil
                currentStage      = "Post Pull Wait"
                stageProgressTime = 0
            else
                stageProgressTime = stageProgressTime + 0.05
                if Config.WAITING_PULL_TIMEOUT > 0 and stageProgressTime > Config.WAITING_PULL_TIMEOUT then
                    timeoutReset("Waiting Pull")
                end
                task.wait(0.05)
            end

        -- ── POST PULL WAIT ────────────────────────────────────────
        elseif currentStage == "Post Pull Wait" then
            if stageProgressTime < Config.POST_PULL_DELAY then
                stageProgressTime = stageProgressTime + 0.05
                task.wait(0.05)
                if stageProgressTime > Config.POST_PULL_TIMEOUT then
                    timeoutReset("Post Pull Wait")
                end
            else
                currentStage      = "Catch"
                stageProgressTime = 0
            end

        -- ── CATCH ─────────────────────────────────────────────────
        elseif currentStage == "Catch" then
            local tool        = Character:FindFirstChildOfClass("Tool")
            local catchRemote = tool and tool:FindFirstChild("Catch")

            if catchRemote then
                catchRemote:FireServer(true)
                totalFishCaught = totalFishCaught + 1
                updateCaughtUI()
                currentStage      = "Pre End Wait"
                stageProgressTime = 0
            else
                warn("[CATCH] RemoteEvent 'Catch' tidak ditemukan — reset ke Idle.")
                timeoutReset("Catch")
            end

        -- ── PRE END WAIT ──────────────────────────────────────────
        elseif currentStage == "Pre End Wait" then
            if stageProgressTime < Config.PRE_END_DELAY then
                stageProgressTime = stageProgressTime + 0.05
                task.wait(0.05)
            else
                currentStage      = "End"
                stageProgressTime = 0
            end

        -- ── END ───────────────────────────────────────────────────
        elseif currentStage == "End" then
            local playerGui = LocalPlayer:WaitForChild("PlayerGui")
            for _, gui in pairs(playerGui:GetChildren()) do
                if gui:IsA("ScreenGui") and gui:FindFirstChild("FishingHolder", true) then
                    gui:Destroy()
                    break
                end
            end
            currentStage      = "Post End Wait"
            stageProgressTime = 0

        -- ── POST END WAIT ─────────────────────────────────────────
        elseif currentStage == "Post End Wait" then
            if stageProgressTime < Config.POST_END_DELAY then
                stageProgressTime = stageProgressTime + 0.05
                task.wait(0.05)
            else
                currentStage      = "Idle"
                stageProgressTime = 0
            end
        end

        task.wait()
    end
end

-- ============================================
-- Auto Equip State
-- ============================================

local isAutoEquipRunning     = false
local isAutoEquipWithFishing = false

local function startAutoEquipLoop()
    task.spawn(function()
        while isScriptLoaded do
            local shouldRun = isAutoEquipRunning or (isAutoEquipWithFishing and isBotRunning)
            if not shouldRun then
                task.wait(0.5)
            else
                equipRod()
                task.wait(2)
            end
        end
    end)
end

-- ============================================
-- Fishing Tab Buttons & Toggles
-- ============================================

SecondTab:CreateButton({
    Name     = "Sell All Fish",
    Callback = function()
        local ReplicatedStorage   = game:GetService("ReplicatedStorage")
        local GameRemoteFunctions = ReplicatedStorage:FindFirstChild("GameRemoteFunctions")
        local SellAllFishFunction = GameRemoteFunctions and GameRemoteFunctions:FindFirstChild("SellAllFishFunction")

        if SellAllFishFunction then
            local success, result = pcall(function()
                return SellAllFishFunction:InvokeServer()
            end)
            if success then
                print("[SELL] All fish sold successfully!")
            else
                warn("[SELL GAGAL] Server menolak:", result)
            end
        else
            warn("[ERR] SellAllFishFunction tidak ditemukan!")
        end
    end,
})

local autoFishingToggleRef = nil
local isListeningKeybind   = false

local function setAutoFishing(value)
    isBotRunning = value
    if isBotRunning then
        currentStage = "Idle"
        task.spawn(startFishingEngine)
    else
        if activeAnimationConnection then
            activeAnimationConnection:Disconnect()
            activeAnimationConnection = nil
        end
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end
end

autoFishingToggleRef = SecondTab:CreateToggle({
    Name         = "Auto Fishing",
    CurrentValue = false,
    Callback     = function(Value)
        setAutoFishing(Value)
    end,
})

local keybindLabelFishing = SecondTab:CreateLabel("Keybind: (none) — klik Set lalu pencet key")

local keybindConn = nil

SecondTab:CreateButton({
    Name     = "Set Keybind - Bug ketika menekan keybind Cast tidak sesuai config",
    Callback = function()
        if isListeningKeybind then return end
        isListeningKeybind = true
        keybindLabelFishing:Set("Keybind: [Pencet key...]")

        local inputConn
        inputConn = game:GetService("UserInputService").InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

            inputConn:Disconnect()
            fishingKeybind = input.KeyCode

            local keyName = tostring(fishingKeybind):gsub("Enum.KeyCode.", "")
            keybindLabelFishing:Set("Keybind: " .. keyName)
            updateKeybindLabel()

            task.delay(0.1, function()
                isListeningKeybind = false
            end)
        end)
    end,
})

SecondTab:CreateButton({
    Name     = "Hapus Keybind",
    Callback = function()
        fishingKeybind = Enum.KeyCode.Unknown
        keybindLabelFishing:Set("Keybind: (none) — klik Set lalu pencet key")
        updateKeybindLabel()
    end,
})

game:GetService("UserInputService").InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if isListeningKeybind then return end
    if fishingKeybind == Enum.KeyCode.Unknown then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if input.KeyCode ~= fishingKeybind then return end

    local newVal = not isBotRunning
    setAutoFishing(newVal)
    if autoFishingToggleRef then
        autoFishingToggleRef:Set(newVal)
    end
    print("[KEYBIND] Auto Fishing toggled → " .. tostring(newVal))
end)

SecondTab:CreateToggle({
    Name         = "Auto Equip Rod",
    CurrentValue = false,
    Callback     = function(Value)
        isAutoEquipRunning = Value
        if Value then
            print("[AUTO EQUIP] Aktif (standalone)")
        else
            print("[AUTO EQUIP] Nonaktif")
        end
    end,
})

SecondTab:CreateToggle({
    Name         = "Auto Equip (saat Auto Fishing nyala)",
    CurrentValue = false,
    Callback     = function(Value)
        isAutoEquipWithFishing = Value
        if Value then
            print("[AUTO EQUIP] Aktif (mode gabungan dengan Auto Fishing)")
        else
            print("[AUTO EQUIP] Mode gabungan dinonaktifkan")
        end
    end,
})

SecondTab:CreateButton({
    Name     = "Reset Timeout Counter",
    Callback = function()
        timeoutCount = 0
        for k in pairs(timeoutPerStage) do
            timeoutPerStage[k] = 0
        end
        updateTimeoutUI()
        print("[INFO] Timeout counter direset.")
    end,
})

-- ============================================
-- Unload Tab
-- ============================================

local function unloadAllScriptProcesses()
    isScriptLoaded = false
    isBotRunning   = false

    if activeAnimationConnection then activeAnimationConnection:Disconnect() end
    if childAddedConn            then childAddedConn:Disconnect()            end
    if childRemovedConn          then childRemovedConn:Disconnect()          end
    if heartbeatConnection       then heartbeatConnection:Disconnect()       end

    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    Rayfield:Destroy()
end

UnloadTab:CreateButton({
    Name     = "Unload Script",
    Callback = unloadAllScriptProcesses,
})

_G.FishingBotInstance = unloadAllScriptProcesses

startAutoEquipLoop()

-- ============================================
-- UI Refresh Loop
-- ============================================

task.spawn(function()
    while isScriptLoaded do
        if not Character or not Humanoid then
            task.wait(0.5)
            continue
        end

        local tool = Character:FindFirstChildOfClass("Tool")
        local rodName = (tool and string.find(string.lower(tool.Name), "rod")) and tool.Name or "None"

        LabelRod:Set("Rod: " .. rodName)
        LabelStage:Set("Stage: [" .. currentStage .. "]")

        task.wait(0.3)
    end
end)
