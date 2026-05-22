local cloneref = (cloneref or clonereference or function(instance: any)
    return instance
end)
local clonefunction = (clonefunction or copyfunction or function(func) 
    return func 
end)

local HttpService: HttpService = cloneref(game:GetService("HttpService"))
local isfolder, isfile, listfiles = isfolder, isfile, listfiles
local unpackFn = table.unpack or unpack

if typeof(clonefunction) == "function" then
    local function tryCloneFileFunction(fn)
        local success, cloned = pcall(clonefunction, fn)
        return success and cloned or nil
    end

    local isfolder_copy = tryCloneFileFunction(isfolder)
    local isfile_copy = tryCloneFileFunction(isfile)
    local listfiles_copy = tryCloneFileFunction(listfiles)

    if typeof(isfolder_copy) == "function"
        and typeof(isfile_copy) == "function"
        and typeof(listfiles_copy) == "function"
    then
        local isfolder_success, isfolder_result = pcall(function()
            return isfolder_copy("test" .. tostring(math.random(1000000, 9999999)))
        end)

        if isfolder_success and typeof(isfolder_result) == "boolean" then
            isfolder = isfolder_copy
            isfile = isfile_copy
            listfiles = listfiles_copy
        else
            isfolder = function(folder)
                local success, data = pcall(isfolder_copy, folder)
                return (if success then data else false)
            end

            isfile = function(file)
                local success, data = pcall(isfile_copy, file)
                return (if success then data else false)
            end

            listfiles = function(folder)
                local success, data = pcall(listfiles_copy, folder)
                return (if success then data else {})
            end
        end
    end
end

local SaveManager = {} do
    SaveManager.Folder = "MidgardLibSettings"
    SaveManager.Ignore = {
        ["BackgroundColor"] = true, ["MainColor"] = true, ["AccentColor"] = true, ["OutlineColor"] = true, 
        ["FontColor"] = true, ["FontFace"] = true, ["ToggleColor"] = true, ["SliderColor"] = true,
    }
    SaveManager.IgnoreExport = {}
    SaveManager.Library = nil
    SaveManager.CustomSave = nil
    SaveManager.CustomExport = nil
    SaveManager.CustomLoad = nil
    SaveManager.CustomValidate = nil
    SaveManager.CurrentConfig = nil
    SaveManager.ManualAutoload = nil
    SaveManager.ConfigVersion = nil
    SaveManager.UseCustomStateAsPrimary = false
    SaveManager.AutoSaveDebounce = 1
    SaveManager.PendingLoads = {}
    SaveManager.PendingLoadWorker = nil
    SaveManager.AutoSaveDirty = false
    SaveManager._autoSaveTimer = nil
    SaveManager._objectChangedConnection = nil
    SaveManager.DebugEnabled = false
    SaveManager.DebugScopes = {}

    local BaseIgnore = table.clone(SaveManager.Ignore)
    local BaseIgnoreExport = table.clone(SaveManager.IgnoreExport)

    local function safeReadFile(path)
        if type(path) ~= "string" or path == "" or not isfile(path) then
            return false, nil, "invalid file"
        end
        local ok, data = pcall(readfile, path)
        if not ok or type(data) ~= "string" then
            return false, nil, "read error"
        end
        return true, data
    end

    local function safeWriteFile(path, data)
        if type(path) ~= "string" or path == "" then
            return false, "invalid path"
        end
        if type(data) ~= "string" then
            return false, "invalid data"
        end
        local ok, err = pcall(writefile, path, data)
        if not ok then
            return false, tostring(err)
        end
        return true
    end

    local function safeDeleteFile(path)
        if type(path) ~= "string" or path == "" or not isfile(path) then
            return true
        end
        local ok, err = pcall(delfile, path)
        if not ok then
            return false, tostring(err)
        end
        return true
    end

    local function decodeJsonText(text)
        if type(text) ~= "string" or text:gsub("%s+", "") == "" then
            return false, nil, "empty json"
        end
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, text)
        if not ok or type(decoded) ~= "table" then
            return false, nil, "decode error"
        end
        return true, decoded
    end

    local function writeJsonFileAtomic(path, encodedJson)
        local tmpPath = path .. ".tmp"
        safeDeleteFile(tmpPath)

        local tmpWriteOk, tmpWriteErr = safeWriteFile(tmpPath, encodedJson)
        if not tmpWriteOk then
            return false, "failed to write temp file: " .. tostring(tmpWriteErr)
        end

        local readOk, writtenText, readErr = safeReadFile(tmpPath)
        if not readOk then
            safeDeleteFile(tmpPath)
            return false, "failed to verify temp file: " .. tostring(readErr)
        end

        local decodeOk = decodeJsonText(writtenText)
        if not decodeOk then
            safeDeleteFile(tmpPath)
            return false, "temp file verification failed"
        end

        local finalWriteOk, finalWriteErr = safeWriteFile(path, writtenText)
        safeDeleteFile(tmpPath)
        if not finalWriteOk then
            return false, tostring(finalWriteErr)
        end

        return true
    end

    do
        local ok, plr = pcall(function()
            return game:GetService("Players").LocalPlayer
        end)
        SaveManager.SubFolder = (ok and plr and plr.Name) or ""
    end

    SaveManager.Parser = {
        Toggle = {
            Save = function(idx, object)
                return { type = "Toggle", idx = idx, value = object.Value }
            end,
            Load = function(idx, data)
                local lib = SaveManager.Library
                if not (lib and lib.Toggles) then return end
                local object = lib.Toggles[idx]
                if object and object.Value ~= data.value then
                    object:SetValue(data.value)
                end
            end,
        },
        Slider = {
            Save = function(idx, object)
                return { type = "Slider", idx = idx, value = tostring(object.Value) }
            end,
            Load = function(idx, data)
                local lib = SaveManager.Library
                if not (lib and lib.Options) then return end
                local object = lib.Options[idx]
                local numValue = tonumber(data.value)
                if object and numValue ~= nil and object.Value ~= numValue then
                    object:SetValue(numValue)
                end
            end,
        },
        Dropdown = {
            Save = function(idx, object)
                local value = object.Value
                local label = nil
                local entries = nil
                if object.SpecialType == "Player" then
                    if object.Multi then
                        local names = {}
                        for k, v in value or {} do
                            if typeof(k) == "Instance" and k:IsA("Player") then
                                names[k.Name] = v
                            else
                                names[tostring(k)] = v
                            end
                        end
                        value = names
                    else
                        if typeof(value) == "Instance" and value:IsA("Player") then
                            value = value.Name
                        end
                    end
                elseif object.Multi then
                    entries = {}
                    for selectedValue, active in value or {} do
                        if active then
                            table.insert(entries, {
                                value = selectedValue,
                                label = tostring(selectedValue),
                            })
                        end
                    end
                else
                    label = value ~= nil and tostring(value) or nil
                end

                return {
                    type = "Dropdown",
                    idx = idx,
                    value = value,
                    label = label,
                    entries = entries,
                    multi = object.Multi,
                }
            end,
            Load = function(idx, data)
                local lib = SaveManager.Library
                if not (lib and lib.Options) then return end
                local object = lib.Options[idx]
                if not object then return end

                local function resolveSingleDropdownValue(rawValue, fallbackLabel)
                    if rawValue == nil then
                        return nil
                    end

                    if table.find(object.Values, rawValue) then
                        return rawValue
                    end

                    if fallbackLabel ~= nil then
                        for _, candidate in object.Values or {} do
                            if tostring(candidate) == tostring(fallbackLabel) then
                                return candidate
                            end
                        end
                    end

                    return rawValue
                end

                local function resolveMultiDropdownValue(rawTable, fallbackEntries)
                    local resolved = {}

                    if typeof(rawTable) == "table" then
                        for rawKey, active in rawTable do
                            local candidate = nil
                            if table.find(object.Values, rawKey) then
                                candidate = rawKey
                            else
                                for _, optionValue in object.Values or {} do
                                    if tostring(optionValue) == tostring(rawKey) then
                                        candidate = optionValue
                                        break
                                    end
                                end
                            end

                            if candidate ~= nil and active then
                                resolved[candidate] = true
                            end
                        end
                    end

                    if typeof(fallbackEntries) == "table" then
                        for _, entry in fallbackEntries do
                            local candidate = resolveSingleDropdownValue(entry.value, entry.label)
                            if candidate ~= nil then
                                resolved[candidate] = true
                            end
                        end
                    end

                    return resolved
                end

                local value = data.value
                if object.SpecialType == "Player" then
                    local Players = game:GetService("Players")
                    if data.multi then
                        if typeof(value) == "table" then
                            local resolved = {}
                            for name, v in value do
                                local player = Players:FindFirstChild(tostring(name))
                                if player and player:IsA("Player") then
                                    resolved[player] = v
                                end
                            end
                            value = resolved
                        end
                    else
                        if typeof(value) == "string" and value ~= "" then
                            local player = Players:FindFirstChild(value)
                            if player and player:IsA("Player") then
                                value = player
                            else
                                return
                            end
                        end
                    end
                elseif data.multi then
                    value = resolveMultiDropdownValue(value, data.entries)
                else
                    value = resolveSingleDropdownValue(value, data.label)
                end

                if object.Value ~= value then
                    if type(object.SetPendingValue) == "function" then
                        object:SetPendingValue(value)
                    else
                        object:SetValue(value)
                    end
                end
            end,
        },
        KeyPicker = {
            Save = function(idx, object)
                return { type = "KeyPicker", idx = idx, mode = object.Mode, key = object.Value, modifiers = object.Modifiers }
            end,
            Load = function(idx, data)
                local lib = SaveManager.Library
                if not (lib and lib.Options) then return end
                local object = lib.Options[idx]
                if object then
                    object:SetValue({ data.key, data.mode, data.modifiers or {} })
                end
            end,
        },
        Input = {
            Save = function(idx, object)
                return { type = "Input", idx = idx, text = object.Value }
            end,
            Load = function(idx, data)
                local lib = SaveManager.Library
                if not (lib and lib.Options) then return end
                local object = lib.Options[idx]
                if object and object.Value ~= data.text and type(data.text) == "string" then
                    object:SetValue(data.text)
                end
            end,
        },
    }

    -- Library
    function SaveManager:SetLibrary(library)
        self.Library = library
    end

    function SaveManager:SetDebugEnabled(enabled, scopes)
        self.DebugEnabled = enabled == true
        self.DebugScopes = type(scopes) == "table" and table.clone(scopes) or {}
    end

    function SaveManager:DebugLog(scope, message, ...)
        if not self.DebugEnabled then
            return
        end

        if next(self.DebugScopes) and not self.DebugScopes[scope] then
            return
        end

        local formatted = tostring(message or "")
        local ok, result = pcall(string.format, formatted, ...)
        if ok then
            formatted = result
        end

        warn(string.format("[SaveManager:%s] %s", tostring(scope or "General"), formatted))
    end

    function SaveManager:GetDiagnostics()
        local pendingLoadCount = 0
        for _ in self.PendingLoads or {} do
            pendingLoadCount += 1
        end

        return {
            CurrentConfig = self.CurrentConfig,
            ManualAutoload = self.ManualAutoload,
            LoadingMetadata = self.LoadingMetadata == true,
            AutoSaveDirty = self.AutoSaveDirty == true,
            AutoSaveTimerActive = self._autoSaveTimer ~= nil,
            PendingLoadCount = pendingLoadCount,
            Initialized = self.Initialized == true,
            AutoSaveDebounce = self.AutoSaveDebounce,
            UseCustomStateAsPrimary = self.UseCustomStateAsPrimary == true,
        }
    end

    function SaveManager:CloneValue(value)
        if type(value) ~= "table" then
            return value
        end

        local cloned = {}
        for key, nestedValue in next, value do
            cloned[key] = self:CloneValue(nestedValue)
        end
        return cloned
    end

    function SaveManager:CloneShallowMap(source)
        if type(source) ~= "table" then
            return {}
        end

        local cloned = {}
        for key, value in next, source do
            cloned[key] = value
        end
        return cloned
    end

    function SaveManager:CloneBooleanKeyMap(source)
        return self:CloneShallowMap(source)
    end

    function SaveManager:NormalizeControlSnapshot(snapshot)
        if type(snapshot) ~= "table" then
            return {
                Toggles = {},
                Options = {},
            }
        end

        return {
            Toggles = type(snapshot.Toggles) == "table" and snapshot.Toggles or {},
            Options = type(snapshot.Options) == "table" and snapshot.Options or {},
        }
    end

    function SaveManager:GetCustomSavePayload(context, configName)
        local customSave = self.CustomSave
        if context == "export" then
            customSave = self.CustomExport or self.CustomSave
        end

        if type(customSave) ~= "function" then
            return true, nil
        end

        return pcall(customSave, context, configName)
    end

    -- Custom state
    function SaveManager:ConfigureCustomState(options)
        if type(options) ~= "table" then
            return false, "invalid custom state options"
        end

        if type(options.Save) == "function" then
            self.CustomSave = options.Save
        elseif type(options.Build) == "function" then
            self.CustomSave = options.Build
        end

        if type(options.Export) == "function" then
            self.CustomExport = options.Export
        elseif self.CustomSave and options.Export == nil then
            self.CustomExport = self.CustomSave
        end

        if type(options.Validate) == "function" then
            self.CustomValidate = options.Validate
        end

        if type(options.Load) == "function" then
            self.CustomLoad = options.Load
        elseif type(options.Apply) == "function" then
            self.CustomLoad = options.Apply
        end

        if type(options.UseAsPrimary) == "boolean" then
            self.UseCustomStateAsPrimary = options.UseAsPrimary
        end

        return true
    end

    -- Async
    function SaveManager:RunAsync(scope, callback, ...)
        if type(callback) ~= "function" then
            return nil
        end

        local args = { n = select("#", ...), ... }
        return task.spawn(function()
            local ok, err = pcall(function()
                if type(unpackFn) == "function" then
                    callback(unpackFn(args, 1, args.n))
                else
                    callback()
                end
            end)
            if not ok then
                warn(string.format("[SaveManager:%s] %s", tostring(scope or "Async"), tostring(err)))
            end
        end)
    end

    -- Pending queue
    function SaveManager:QueuePendingLoad(option)
        if type(option) ~= "table" or type(option.idx) ~= "string" or option.idx == "" then
            return
        end

        self.PendingLoads[option.idx] = option
        self:DebugLog("PendingLoad", "Queued %s (%s)", tostring(option.idx), tostring(option.type))
        self:StartPendingLoadWorker()
    end

    -- Pending apply
    function SaveManager:TryApplyPendingLoads()
        local lib = self.Library
        if not (lib and lib.Options and lib.Toggles) then
            return false
        end

        local appliedAny = false
        for idx, option in self.PendingLoads do
            local optionType = option and option.type
            local parser = optionType and self.Parser[optionType]
            if not parser or self.Ignore[idx] then
                self.PendingLoads[idx] = nil
            else
                local object = if optionType == "Toggle" then lib.Toggles[idx] else lib.Options[idx]
                if object then
                    self.PendingLoads[idx] = nil
                    appliedAny = true
                    self:DebugLog("PendingLoad", "Applying queued %s (%s)", tostring(idx), tostring(optionType))
                    self:RunAsync("PendingLoad", parser.Load, idx, option)
                end
            end
        end

        return appliedAny
    end

    -- Pending worker
    function SaveManager:StartPendingLoadWorker()
        if self.PendingLoadWorker then
            return
        end

        self.PendingLoadWorker = self:RunAsync("PendingLoadWorker", function()
            for _ = 1, 60 do
                self:TryApplyPendingLoads()

                if next(self.PendingLoads) == nil then
                    break
                end

                task.wait(0.25)
            end

            self.PendingLoadWorker = nil
        end)
    end

    -- Section ignore
    function SaveManager:IgnoreSection(section, shouldIgnore)
        if typeof(section) ~= "table" then return end

        local ignore = shouldIgnore ~= false
        local elements = section.Elements
        if typeof(elements) ~= "table" then return end

        for _, element in elements do
            local idx = typeof(element) == "table" and element.Idx or nil
            if type(idx) == "string" and idx ~= "" then
                self.Ignore[idx] = ignore
            end
        end
    end

    -- Folders
    function SaveManager:GetSettingsRootPath()
        return self.Folder
    end

    -- Subfolder path
    function SaveManager:GetSubFolderPath()
        if typeof(self.SubFolder) ~= "string" or self.SubFolder == "" then
            return nil
        end

        return self:GetSettingsRootPath() .. "/" .. self.SubFolder
    end

    -- Subfolder check
    function SaveManager:CheckSubFolder(createFolder)
        if typeof(self.SubFolder) ~= "string" or self.SubFolder == "" then return false end

        if createFolder == true then
            local subFolder = self:GetSubFolderPath()
            if subFolder and not isfolder(subFolder) then
                makefolder(subFolder)
            end
        end

        return true
    end

    -- Paths
    function SaveManager:GetPaths()
        local paths = {}
        local seen = {}
        local function addPath(path)
            if type(path) == "string" and path ~= "" and not seen[path] then
                seen[path] = true
                paths[#paths + 1] = path
            end
        end

        local parts = self.Folder:split("/")
        for idx = 1, #parts do
            addPath(table.concat(parts, "/", 1, idx))
        end

        addPath(self:GetSettingsRootPath())

        if self:CheckSubFolder(false) then
            local subFolder = self:GetSubFolderPath()
            parts = subFolder:split("/")

            for idx = 1, #parts do
                addPath(table.concat(parts, "/", 1, idx))
            end
        end

        return paths
    end

    -- Folder tree
    function SaveManager:BuildFolderTree()
        local paths = self:GetPaths()

        for i = 1, #paths do
            local str = paths[i]
            if isfolder(str) then continue end
            makefolder(str)
        end
    end

    -- Folder check
    function SaveManager:CheckFolderTree()
        if not isfolder(self.Folder) then
            makefolder(self.Folder)
        end

        return true
    end

    -- Settings path
    function SaveManager:GetSettingsPath(createFolder)
        if createFolder ~= false then
            self:CheckFolderTree()
        end

        if self:CheckSubFolder(createFolder ~= false) then
            return self:GetSubFolderPath()
        end

        return self:GetSettingsRootPath()
    end

    -- Metadata path
    function SaveManager:GetAutoSaveMetadataPath(createFolder)
        return self:GetSettingsPath(createFolder) .. "/autosave_meta.json"
    end

    -- Ignore list
    function SaveManager:SetIgnoreIndexes(list)
        self.Ignore = table.clone(BaseIgnore)
        for _, key in list do
            self.Ignore[key] = true
        end
    end

    -- Set folder
    function SaveManager:SetFolder(folder)
        self.Folder = folder
        self:BuildFolderTree()
    end

    -- Set subfolder
    function SaveManager:SetSubFolder(folder)
        self.SubFolder = folder
        self:BuildFolderTree()
    end

    -- Project config
    function SaveManager:ConfigureProject(options)
        if type(options) ~= "table" then return end
        if options.Library then
            self:SetLibrary(options.Library)
        end
        if type(options.Folder) == "string" and options.Folder ~= "" then
            self:SetFolder(options.Folder)
        end
        if type(options.SubFolder) == "string" and options.SubFolder ~= "" then
            self:SetSubFolder(options.SubFolder)
        end
        if type(options.Ignore) == "table" then
            self:SetIgnoreIndexes(options.Ignore)
        end
        if type(options.IgnoreExport) == "table" then
            self:SetIgnoreExportIndexes(options.IgnoreExport)
        end
        if type(options.UseCustomStateAsPrimary) == "boolean" then
            self.UseCustomStateAsPrimary = options.UseCustomStateAsPrimary
        end
        if type(options.ConfigVersion) == "number" then
            self.ConfigVersion = options.ConfigVersion
        end
        if type(options.AutoSaveDebounce) == "number" and options.AutoSaveDebounce >= 0 then
            self.AutoSaveDebounce = options.AutoSaveDebounce
        end
        if type(options.DebugEnabled) == "boolean" then
            self.DebugEnabled = options.DebugEnabled
        end
        if type(options.DebugScopes) == "table" then
            self.DebugScopes = table.clone(options.DebugScopes)
        end
    end

    -- Export ignore
    function SaveManager:SetIgnoreExportIndexes(list)
        self.IgnoreExport = table.clone(BaseIgnoreExport)
        for _, key in list do
            self.IgnoreExport[key] = true
        end
    end

    -- Config path
    function SaveManager:ResolvePath(name)
        if not name or name == "" then return nil end
        return self:GetSettingsPath(true) .. "/" .. name
    end

    -- Serialize
    function SaveManager:SerializeCurrentState(name, context)
        local data = self.UseCustomStateAsPrimary and {} or { objects = {} }
        local lib = self.Library
        if not lib then return false, "library not set" end

        if not self.UseCustomStateAsPrimary then
            for idx, option in lib.Options do
                local optionType = option.type or option.Type
                if not self.Parser[optionType] then continue end
                if self.Ignore[idx] then continue end
                if name ~= "autosave" and self.IgnoreExport[idx] then continue end
                table.insert(data.objects, self.Parser[optionType].Save(idx, option))
            end

            for idx, toggle in lib.Toggles do
                if self.Ignore[idx] then continue end
                if name ~= "autosave" and self.IgnoreExport[idx] then continue end
                table.insert(data.objects, self.Parser.Toggle.Save(idx, toggle))
            end
        end

        local payloadContext = context or (name == "export" and "export" or "serialize")
        local ok, custom = self:GetCustomSavePayload(payloadContext, name)
        if ok and custom then data.custom = custom end

        if type(self.ConfigVersion) == "number" then
            data.Version = self.ConfigVersion
        end

        return true, data
    end

    -- Apply decoded
    function SaveManager:ApplyDecodedConfig(decoded, controlScope, configName)
        if type(decoded) ~= "table" then
            return false, "decode error"
        end

        if not self.UseCustomStateAsPrimary and type(decoded.objects) == "table" then
            local lib = self.Library
            if not (lib and lib.Options and lib.Toggles) then
                return false, "library not set"
            end

            for _, option in decoded.objects do
                local optionType = option and option.type
                if not optionType then continue end
                if not self.Parser[optionType] then continue end
                if self.Ignore[option.idx] then continue end
                local object = if optionType == "Toggle" then lib.Toggles[option.idx] else lib.Options[option.idx]
                if object then
                    self:RunAsync(controlScope or "LoadControl", self.Parser[optionType].Load, option.idx, option)
                else
                    self:QueuePendingLoad(option)
                end
            end
        end

        local customPayload = decoded.custom
        if self.UseCustomStateAsPrimary and type(customPayload) ~= "table" then
            return false, "invalid custom config"
        end

        if self.CustomValidate and customPayload then
            local ok, valid, err = pcall(self.CustomValidate, customPayload)
            if not ok then
                return false, "custom config validation failed"
            end
            if valid == false then
                return false, err or "invalid custom config"
            end
        end

        if self.CustomLoad and customPayload then
            self:RunAsync("LoadCustomLoad", self.CustomLoad, customPayload)
            if configName then
                self:DebugLog("Load", "Custom payload applied for %s", tostring(configName))
            end
        end

        return true
    end

    -- Save
    function SaveManager:Save(name, silent)
        if not name then
            return false, "no config file is selected"
        end
        local fullPath = self:GetSettingsPath(true) .. "/" .. name .. ".json"

        local stateOk, data = self:SerializeCurrentState(name, "save")
        if not stateOk then
            return false, data
        end

        local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
        if not success then
            return false, "failed to encode data"
        end

        local successWrite, err = writeJsonFileAtomic(fullPath, encoded)
        if not successWrite then
            return false, "failed to write file: " .. tostring(err)
        end

        self:DebugLog("Save", "Saved config %s", tostring(name))

        if not silent then
            self.CurrentConfig = name
        end

        return true
    end

    -- Import
    function SaveManager:LoadConfigData(rawText)
        if type(rawText) ~= "string" or rawText:gsub("%s+", "") == "" then
            return false, "empty config text"
        end

        rawText = rawText:match("^%s*(.-)%s*$")

        if rawText:match("^https?://") then
            local resolvedUrl = rawText
            local pastebinId = rawText:match("^https?://pastebin%.com/([%w]+)$")
            if pastebinId then
                resolvedUrl = "https://pastebin.com/raw/" .. pastebinId
            end

            local okFetch, fetched = pcall(function()
                return game:HttpGet(resolvedUrl)
            end)

            if not okFetch or type(fetched) ~= "string" or fetched == "" then
                return false, "failed to fetch config url"
            end

            rawText = fetched
        end

        local success, decoded = pcall(HttpService.JSONDecode, HttpService, rawText)
        if not success or type(decoded) ~= "table" then
            return false, "invalid config json"
        end

        return self:ApplyDecodedConfig(decoded, "ImportControl")
    end

    -- Export
    function SaveManager:ExportToClipboard()
        if typeof(setclipboard) ~= "function" then
            return false, "clipboard unavailable"
        end

        local success, data = self:SerializeCurrentState("export")
        if not success then
            return false, data
        end

        local encodedSuccess, encoded = pcall(HttpService.JSONEncode, HttpService, data)
        if not encodedSuccess then
            return false, "failed to encode config"
        end

        local clipboardSuccess, clipboardErr = pcall(setclipboard, encoded)
        if not clipboardSuccess then
            return false, tostring(clipboardErr)
        end

        return true
    end

    -- Load
    function SaveManager:Load(name)
        if not name then
            return false, "no config file is selected"
        end
        local file = self:GetSettingsPath(true) .. "/" .. name .. ".json"

        local readOk, rawText, readErr = safeReadFile(file)
        if not readOk then
            return false, readErr or "invalid file"
        end

        local previousConfig = self.CurrentConfig
        self.CurrentConfig = name

        local success, decoded, decodeErr = decodeJsonText(rawText)
        if not success or type(decoded) ~= "table" then
            self.CurrentConfig = previousConfig
            return false, decodeErr or "decode error"
        end
        self:DebugLog("Load", "Loading config %s", tostring(name))

        local applied, applyErr = self:ApplyDecodedConfig(decoded, "LoadControl", name)
        if not applied then
            self.CurrentConfig = previousConfig
            return false, applyErr or "invalid config"
        end

        self:SaveAutoSaveMetadata()

        return true
    end

    -- Delete
    function SaveManager:Delete(name)
        if not name then
            return false, "no config file is selected"
        end

        local file = self:GetSettingsPath(true) .. "/" .. name .. ".json"

        if not isfile(file) then return false, "invalid file" end

        local success, err = safeDeleteFile(file)
        if not success then return false, "delete file error: " .. tostring(err) end

        if self:GetAutoloadConfig() == name then
            self:DeleteAutoLoadConfig()
            if self.AutoloadConfigLabel then
                self.AutoloadConfigLabel:SetVisible(false)
            end
        end

        return true
    end

    -- Config list
    local InternalConfigFiles = {
        autosave = true,
        autosave_meta = true,
    }

    function SaveManager:RefreshConfigList()
        local success, data = pcall(function()
            local list = {}
            local out = {}

            list = listfiles(self:GetSettingsPath(true))
            if typeof(list) ~= "table" then list = {} end

            for i = 1, #list do
                local file = list[i]
                local name = type(file) == "string" and not file:match("%.tmp$") and file:match("([^/\\]+)%.json$")
                if name and not InternalConfigFiles[name] then
                    table.insert(out, name)
                end
            end

            return out
        end)

        if not success then
            warn("Failed to Load Config List: " .. tostring(data))
            return {}
        end

        return data
    end

    -- Autoload read
    function SaveManager:GetAutoloadConfig()
        local autoLoadPath = self:GetSettingsPath(true) .. "/autoload.txt"

        if isfile(autoLoadPath) then
            local successRead, name = safeReadFile(autoLoadPath)
            if not successRead then
                return "none"
            end
            return if name == "" or name == "none" then "" else name
        end

        return ""
    end

    -- Autoload load
    function SaveManager:LoadAutoloadConfig()
        local path = self:GetSettingsPath(true) .. "/autoload.txt"

        if isfile(path) then
            local successRead, name = safeReadFile(path)
            if not successRead then return end

            name = name:gsub("^%s*(.-)%s*$", "%1")
            if name == "" then return end

            local success, err = self:Load(name)
            if not success then
                warn("Failed to Load Autoload Config: " .. tostring(err))
                self:DeleteAutoLoadConfig()
            end
        end
    end

    -- Autoload save
    function SaveManager:SaveAutoloadConfig(name, preserveAutoSave)
        -- Avoid competing sources.
        local lib = self.Library
        if not preserveAutoSave and lib and lib.Toggles.SaveManager_AutoSave and lib.Toggles.SaveManager_AutoSave.Value then
            lib.Toggles.SaveManager_AutoSave:SetValue(false)
        end

        local autoLoadPath = self:GetSettingsPath(true) .. "/autoload.txt"

        local success, err = safeWriteFile(autoLoadPath, name)
        if not success then return false, "write file error: " .. tostring(err) end

        -- Manual autoload
        if name and name ~= "none" and name ~= "" then
            self.ManualAutoload = name
            self:SaveAutoSaveMetadata()
        end

        return true, ""
    end

    -- Autoload clear
    function SaveManager:DeleteAutoLoadConfig()
        local path = self:GetSettingsPath(true) .. "/autoload.txt"

        -- Sync file state.
        if isfile(path) then
            local success, err = safeDeleteFile(path)
            if not success then return false, err end
        end

        self.ManualAutoload = nil
        local autoSaveEnabled = self.Library
            and self.Library.Toggles
            and self.Library.Toggles.SaveManager_AutoSave
            and self.Library.Toggles.SaveManager_AutoSave.Value == true
        if not autoSaveEnabled then
            self.CurrentConfig = nil
        end
        self:SaveAutoSaveMetadata()

        return true
    end

    -- Autoload label
    function SaveManager:UpdateAutoloadLabel(name)
        if not self.AutoloadConfigLabel then return end
        local text = (name == nil or name == "" or name == "none") and "" or ("Autoload: " .. tostring(name))
        self.AutoloadConfigLabel:SetText(text)
        self.AutoloadConfigLabel:SetVisible(text ~= "")
    end

    -- Autosave policy
    function SaveManager:ApplyAutoSavePolicy(enabled)
        if self.LoadingMetadata then
            self:SaveAutoSaveMetadata()
            return true
        end

        if enabled then
            self:CancelAutoSaveTimer()
            self.CurrentConfig = "autosave"
            local saveSuccess, saveErr = self:Save("autosave")
            if not saveSuccess then
                return false, saveErr
            end
            local autoloadSuccess, autoloadErr = self:SaveAutoloadConfig("autosave", true)
            if not autoloadSuccess then
                return false, autoloadErr
            end
            self:UpdateAutoloadLabel("autosave")
            self:DebugLog("AutoSave", "Enabled autosave policy")
        else
            self:CancelAutoSaveTimer()
            local deleteSuccess, deleteErr = self:DeleteAutoLoadConfig()
            if not deleteSuccess then
                return false, deleteErr
            end
            self.CurrentConfig = nil
            self:UpdateAutoloadLabel("")
            self:DebugLog("AutoSave", "Disabled autosave policy")
        end

        self:SaveAutoSaveMetadata()
        return true
    end

    -- Reset
    function SaveManager:ResetConfig()
        local lib = self.Library
        if not (lib and lib.Toggles and lib.Options) then
            return
        end

        for idx, toggle in lib.Toggles do
            if self.Ignore[idx] then continue end
            local defaultVal = toggle.InitialValue
            if defaultVal == nil then defaultVal = toggle.Default end
            if defaultVal ~= nil then
                toggle:SetValue(defaultVal)
            end
        end

        for idx, option in lib.Options do
            if self.Ignore[idx] then continue end
            local defaultVal = option.InitialValue
            if defaultVal == nil then defaultVal = option.Default end
            if defaultVal ~= nil then
                if option.Type == "Dropdown" then
                    if type(defaultVal) == "table" and not option.Multi then
                        -- First default entry
                        local firstIndex = defaultVal[1]
                        if firstIndex and option.Values and option.Values[firstIndex] then
                            option:SetValue(option.Values[firstIndex])
                        else
                            option:SetValue(nil)
                        end
                    elseif type(defaultVal) == "table" and option.Multi then
                        local mapped = {}
                        for _, idxVal in defaultVal do
                            if type(idxVal) == "number" and option.Values and option.Values[idxVal] then
                                mapped[option.Values[idxVal]] = true
                            elseif type(idxVal) == "string" then
                                mapped[idxVal] = true
                            end
                        end
                        option:SetValue(mapped)
                    else
                        option:SetValue(defaultVal)
                    end
                elseif option.Type == "KeyPicker" then
                    option:SetValue({ defaultVal, option.Mode, option.DefaultModifiers })
                else
                    option:SetValue(defaultVal)
                end
            end
        end
    end

    -- Config UI
    function SaveManager:BuildManagedConfigSection(tab)
        assert(self.Library, "Must set SaveManager.Library")

        local section = tab

        section:AddToggle("SaveManager_AutoSave", { Text = "Save Configuration", Default = false }):OnChanged(function()
            local success, err = self:ApplyAutoSavePolicy(self.Library.Toggles.SaveManager_AutoSave.Value)
            if not success then
                warn("Failed to Update Autosave: " .. tostring(err))
            end
        end)

        section:AddDivider()

        section:AddInput("SaveManager_ConfigName", { Text = "Configuration Name" })
        section:AddButton("Create", function()
            local name = self.Library.Options.SaveManager_ConfigName.Value

            if name:gsub(" ", "") == "" then
                warn("Invalid Config Name (Empty)")
                return
            end

            local success, err = self:Save(name)
            if not success then
                warn("Failed to Create Config: " .. tostring(err))
                return
            end

            self.Library.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            self.Library.Options.SaveManager_ConfigList:SetValue(nil)
        end):AddButton("Reset", function()
            self:ResetConfig()
        end)

        section:AddDropdown("SaveManager_ConfigList", { Text = "Configuration List", Values = self:RefreshConfigList(), AllowNull = true })
        section:AddButton("Load", function()
            local name = self.Library.Options.SaveManager_ConfigList.Value

            local success, err = self:Load(name)
            if not success then
                warn("Failed to Load Config: " .. tostring(err))
                return
            end

        end):AddButton("Overwrite", function()
            local name = self.Library.Options.SaveManager_ConfigList.Value

            local success, err = self:Save(name)
            if not success then
                warn("Failed to Overwrite Config: " .. tostring(err))
                return
            end
        end)

        section:AddButton("Refresh", function()
            self.Library.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            self.Library.Options.SaveManager_ConfigList:SetValue(nil)
        end):AddButton("Delete", function()
            local name = self.Library.Options.SaveManager_ConfigList.Value

            local success, err = self:Delete(name)
            if not success then
                warn("Failed to Delete Config: " .. tostring(err))
                return
            end

            self.Library.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            self.Library.Options.SaveManager_ConfigList:SetValue(nil)
        end)

        section:AddButton("Set Autoload", function()
            local name = self.Library.Options.SaveManager_ConfigList.Value

            local success, err = self:SaveAutoloadConfig(name)
            if not success then
                warn("Failed to Set Autoload Config: " .. tostring(err))
                return
            end

            self:UpdateAutoloadLabel(name)
        end):AddButton("Reset Autoload", function()
            local success, err = self:DeleteAutoLoadConfig()
            if not success then
                warn("Failed to Reset Autoload Config: " .. tostring(err))
                return
            end

            self:UpdateAutoloadLabel("")
        end)

        self.AutoloadConfigLabel = section:AddLabel("", false, true)
        self:UpdateAutoloadLabel(self:GetAutoloadConfig())

        section:AddDivider()
        section:AddInput("Config_Paste_Box", { Text = "Paste Configuration", Placeholder = "JSON Code..." })
        section:AddButton("Import", function()
            local text = self.Library.Options.Config_Paste_Box and self.Library.Options.Config_Paste_Box.Value or ""
            local success, err = self:LoadConfigData(text)
            if not success then
                warn("Failed to Import Config: " .. tostring(err))
                return
            end
        end):AddButton("Export", function()
            local success, err = self:ExportToClipboard()
            if not success then
                warn("Failed to Export Config: " .. tostring(err))
                return
            end
        end)

        self:LoadAutoSaveMetadata()
        self:Initialize()
        self:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName", "SaveManager_AutoSave", "Config_Paste_Box" })
    end

    -- Config alias
    function SaveManager:BuildConfigSection(tab)
        return self:BuildManagedConfigSection(tab)
    end

    -- Autosave cancel
    function SaveManager:CancelAutoSaveTimer(clearDirty)
        if self._autoSaveTimer then
            pcall(task.cancel, self._autoSaveTimer)
            self._autoSaveTimer = nil
        end
        if clearDirty ~= false then
            self.AutoSaveDirty = false
        end
    end

    -- Autosave flush
    function SaveManager:FlushAutoSave()
        local toggle = self.Library and self.Library.Toggles and self.Library.Toggles.SaveManager_AutoSave
        self._autoSaveTimer = nil

        if self.LoadingMetadata or not self.AutoSaveDirty or not (toggle and toggle.Value) then
            return false
        end

        self.AutoSaveDirty = false
        self.CurrentConfig = "autosave"
        local ok, err = self:Save("autosave", true)
        if ok then
            self:SaveAutoSaveMetadata()
            self:DebugLog("AutoSave", "Flushed autosave")
        end

        return ok, err
    end

    -- Autosave schedule
    function SaveManager:ScheduleAutoSave()
        local toggle = self.Library and self.Library.Toggles and self.Library.Toggles.SaveManager_AutoSave
        if self.LoadingMetadata or not (toggle and toggle.Value) then
            return
        end

        self:CancelAutoSaveTimer(false)
        local debounceDelay = tonumber(self.AutoSaveDebounce) or 1
        self:DebugLog("AutoSave", "Scheduled autosave in %.2fs", math.max(0, debounceDelay))
        self._autoSaveTimer = task.delay(math.max(0, debounceDelay), function()
            self:FlushAutoSave()
        end)
    end

    -- Autosave dirty
    function SaveManager:MarkAutoSaveDirty()
        self.AutoSaveDirty = true
        self:DebugLog("AutoSave", "Marked autosave dirty")
        self:ScheduleAutoSave()
    end

    -- Init
    function SaveManager:Initialize()
        if self.Initialized then return end
        local lib = self.Library
        if not (lib and lib.OnObjectChanged and lib.OnObjectChanged.Event) then
            return false, "library event unavailable"
        end
        self.Initialized = true

        if self._objectChangedConnection then
            pcall(function()
                self._objectChangedConnection:Disconnect()
            end)
            self._objectChangedConnection = nil
        end

        self._objectChangedConnection = lib.OnObjectChanged.Event:Connect(function()
            local toggle = lib.Toggles and lib.Toggles.SaveManager_AutoSave
            if not self.LoadingMetadata and toggle and toggle.Value then
                self:MarkAutoSaveDirty()
            end
        end)
    end

    -- Destroy
    function SaveManager:Destroy()
        self:CancelAutoSaveTimer()

        if self.PendingLoadWorker then
            pcall(task.cancel, self.PendingLoadWorker)
            self.PendingLoadWorker = nil
        end

        if self._objectChangedConnection then
            pcall(function()
                self._objectChangedConnection:Disconnect()
            end)
            self._objectChangedConnection = nil
        end

        table.clear(self.PendingLoads)
        self.Initialized = false
        self.LoadingMetadata = false

        self.Library = nil
        self.AutoloadConfigLabel = nil
        self.CurrentConfig = nil
        self.ManualAutoload = nil
        self.CustomSave = nil
        self.CustomExport = nil
        self.CustomLoad = nil
        self.CustomValidate = nil
        self.UseCustomStateAsPrimary = false
        self.Ignore = table.clone(BaseIgnore)
        self.IgnoreExport = table.clone(BaseIgnoreExport)

        local env = getgenv and getgenv() or _G
        if env.SaveManager == self then
            env.SaveManager = nil
        end
        if env.MidgardSaveManager == self then
            env.MidgardSaveManager = nil
        end
    end

    -- Metadata save
    function SaveManager:SaveAutoSaveMetadata()
        if self.LoadingMetadata then return end

        local lib = self.Library
        if not (lib and lib.Toggles) then return end

        local path = self:GetAutoSaveMetadataPath(true)
        local autoSaveEnabled = lib.Toggles.SaveManager_AutoSave and lib.Toggles.SaveManager_AutoSave.Value == true
        local manualAutoload = self.ManualAutoload
        if autoSaveEnabled and manualAutoload == self.CurrentConfig then
            manualAutoload = nil
        end

        local data = {
            Enabled = autoSaveEnabled,
            CurrentConfig = self.CurrentConfig,
            ManualAutoload = manualAutoload or nil,
        }
        local encodedSuccess, encoded = pcall(HttpService.JSONEncode, HttpService, data)
        if not encodedSuccess then return false, "failed to encode autosave metadata" end

        local writeSuccess, writeErr = writeJsonFileAtomic(path, encoded)
        if not writeSuccess then return false, "failed to write autosave metadata: " .. tostring(writeErr) end

        return true
    end

    -- Metadata load
    function SaveManager:LoadAutoSaveMetadata()
        if self.LoadingMetadata then
            return false, "metadata already loading"
        end

        local path = self:GetAutoSaveMetadataPath(true)
        local readPath = path

        if not isfile(readPath) then
            return true
        end

        self.LoadingMetadata = true
        local readOk, rawMetadata, readErr = safeReadFile(readPath)
        local decodeOk, decoded, decodeErr = false, nil, nil
        if readOk then
            decodeOk, decoded, decodeErr = decodeJsonText(rawMetadata)
        end
        if not readOk or not decodeOk or type(decoded) ~= "table" then
            warn("Failed to Load Autosave Metadata: " .. tostring(readErr or decodeErr or "invalid autosave metadata"))
            self.ManualAutoload = nil
            self.CurrentConfig = nil
            safeDeleteFile(readPath)
            self.LoadingMetadata = false
            return false, readErr or decodeErr or "invalid autosave metadata"
        end

        self:DebugLog("Metadata", "Loading autosave metadata")

        -- Normalize old metadata.
        self.ManualAutoload = (decoded.ManualAutoload ~= "" and decoded.ManualAutoload) or nil
        if decoded.Enabled == true and self.ManualAutoload == decoded.CurrentConfig then
            self.ManualAutoload = nil
        end

        -- Load priority
        local configToLoad = self.ManualAutoload or ((decoded.Enabled == true) and decoded.CurrentConfig or nil)
        if configToLoad and configToLoad ~= "" then
            self.CurrentConfig = configToLoad
            local loaded, loadErr = self:Load(self.CurrentConfig)
            if not loaded then
                warn("Failed to Restore Config: " .. tostring(loadErr))
                if self.ManualAutoload == configToLoad then
                    self.ManualAutoload = nil
                end
                self.CurrentConfig = nil
                decoded.Enabled = false
                safeDeleteFile(readPath)
            end
        end

        local lib = self.Library
        if decoded.Enabled ~= nil and lib and lib.Toggles and lib.Toggles.SaveManager_AutoSave then
            lib.Toggles.SaveManager_AutoSave:SetValue(decoded.Enabled)
        end

        self:DebugLog("Metadata", "Autosave metadata applied")

        -- Label sync
        if self.AutoloadConfigLabel then
            local labelConfig = self.ManualAutoload or (decoded.Enabled and self.CurrentConfig) or nil
            if labelConfig and labelConfig ~= "" then
                self.AutoloadConfigLabel:SetText("Autoload: " .. labelConfig)
                self.AutoloadConfigLabel:SetVisible(true)
            else
                self.AutoloadConfigLabel:SetVisible(false)
            end
        end

        self.LoadingMetadata = false
        return true
    end

end

local env = getgenv and getgenv() or _G
env.MidgardSaveManager = SaveManager
env.SaveManager = SaveManager
return SaveManager
