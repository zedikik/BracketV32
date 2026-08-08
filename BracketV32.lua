local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local InsertService = game:GetService("InsertService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local PlayerService = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")


local Bracket
local Runtime = {
    Connections = {},
    Screens = {},
    Windows = {},
    Destroyed = false,
    Generation = 0,
    HiddenContainer = nil,
    RefreshByInstance = setmetatable({}, {__mode = "k"}),
    SearchEntries = {},
    Sections = {},
    BindRegistry = {},
    SearchQuery = "",
    ConfirmDialog = nil,
}

local function TrackConnection(connection)
    if connection then
        Runtime.Connections[#Runtime.Connections + 1] = connection
    end
    return connection
end

local function Connect(signal, callback)
    if Runtime.Destroyed then return nil end
    return TrackConnection(signal:Connect(callback))
end

local function DisconnectConnection(connection)
    if connection then
        pcall(function() connection:Disconnect() end)
    end
end

local function GetRefresh(instance)
    local current = instance
    while current do
        local refresh = Runtime.RefreshByInstance[current]
        if refresh then return refresh end
        current = current.Parent
    end
    return nil
end

local function QueueRefresh(instance)
    local refresh = GetRefresh(instance)
    if refresh then refresh() end
end

local function EnsureHiddenContainer(screenAsset)
    if Runtime.HiddenContainer and Runtime.HiddenContainer.Parent then
        return Runtime.HiddenContainer
    end
    local folder = Instance.new("Folder")
    folder.Name = "BracketHiddenElements"
    folder.Parent = screenAsset
    Runtime.HiddenContainer = folder
    return folder
end

local function AttachVisibility(api, asset)
    if not api or not asset then return end
    api._Asset = asset
    api._Visible = true
    api._SearchVisible = true
    api._OriginalParent = asset.Parent
    api._OriginalLayoutOrder = asset.LayoutOrder
    api._OriginalVisible = asset:IsA("GuiObject") and asset.Visible or nil
    api._OriginalActive = asset:IsA("GuiObject") and asset.Active or nil

    local function applyVisibility()
        local value = api._Visible == true and api._SearchVisible ~= false
        if value then
            local parent = api._OriginalParent
            if parent and parent.Parent then
                asset.LayoutOrder = api._OriginalLayoutOrder
                asset.Parent = parent
                if asset:IsA("GuiObject") then
                    asset.Visible = api._OriginalVisible ~= false
                    asset.Active = api._OriginalActive == true
                end
            end
        else
            if asset.Parent and asset.Parent ~= Runtime.HiddenContainer then
                api._OriginalParent = asset.Parent
                api._OriginalLayoutOrder = asset.LayoutOrder
                if asset:IsA("GuiObject") then
                    api._OriginalVisible = asset.Visible
                    api._OriginalActive = asset.Active
                end
            end
            if asset:IsA("GuiObject") then
                asset.Visible = false
                asset.Active = false
            end
            for _, screen in ipairs(Runtime.Screens) do
                if screen and screen.Parent then
                    local optionContainer = screen:FindFirstChild("OptionContainer")
                    local palette = screen:FindFirstChild("Palette")
                    if optionContainer then optionContainer.Visible = false end
                    if palette then palette.Visible = false end
                end
            end
            asset.Parent = Runtime.HiddenContainer
        end
        QueueRefresh(api._OriginalParent or asset)
    end

    function api:SetVisible(value)
        value = value == true
        if self._Visible == value then return end
        self._Visible = value
        applyVisibility()
    end
    function api:_SetSearchVisible(value)
        value = value == true
        if self._SearchVisible == value then return end
        self._SearchVisible = value
        applyVisibility()
    end
    function api:IsVisible()
        return self._Visible == true
    end
    function api:IsEffectivelyVisible()
        return self._Visible == true and self._SearchVisible ~= false
    end
    api._ApplyVisibility = applyVisibility
end

local function RegisterSearchEntry(api, name, section, tab)
    if not api then return end
    api._SearchName = tostring(name or "")
    api._SearchSection = section
    api._SearchTab = tab
    Runtime.SearchEntries[#Runtime.SearchEntries + 1] = api
end

local function IsRuntimeVisible(api)
    if not api or api._Visible == false or api._SearchVisible == false then return false end
    local current = api._Asset
    if not current or not current.Parent then return false end
    while current do
        if current == Runtime.HiddenContainer then return false end
        current = current.Parent
    end
    return true
end

local Debug,LocalPlayer = false,PlayerService.LocalPlayer
local MainAssetFolder = Debug and ReplicatedStorage.BracketV32
	or InsertService:LoadLocalAsset("rbxassetid://9153139105")

	local function GetAsset(AssetPath)
		AssetPath = AssetPath:split("/")
		local Asset = MainAssetFolder
		for Index,Name in pairs(AssetPath) do
			Asset = Asset[Name]
		end return Asset:Clone()
	end
local function GetLongest(A,B)
	return A > B and A or B
end
local function GetType(Object,Default,Type)
	if typeof(Object) == Type then
		return Object
	end
	return Default
end

local function MakeDraggable(Dragger,Object,Callback)
	local StartPosition,StartDrag = nil,nil
	Connect(Dragger.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			StartPosition = UserInputService:GetMouseLocation()
			StartDrag = Object.AbsolutePosition
		end
	end)
	Connect(UserInputService.InputChanged, function(Input)
		if StartDrag and Input.UserInputType == Enum.UserInputType.MouseMovement then
			local Mouse = UserInputService:GetMouseLocation()
			local Delta = Mouse - StartPosition
			StartPosition = Mouse
			Object.Position = Object.Position + UDim2.new(0,Delta.X,0,Delta.Y)
		end
	end)
	Connect(Dragger.InputEnded, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			StartPosition,StartDrag = nil,nil
			Callback(Object.Position)
		end
	end)
end

local function MakeResizeable(Dragger,Object,MinSize,Callback)
	local StartPosition,StartSize = nil,nil
	Connect(Dragger.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			StartPosition = UserInputService:GetMouseLocation()
			StartSize = Object.AbsoluteSize
		end
	end)
	Connect(UserInputService.InputChanged, function(Input)
		if StartPosition and Input.UserInputType == Enum.UserInputType.MouseMovement then
			local Mouse = UserInputService:GetMouseLocation()
			local Delta = Mouse - StartPosition

			local Size = StartSize + Delta
			local SizeX = math.max(MinSize.X,Size.X)
			local SizeY = math.max(MinSize.Y,Size.Y)
			Object.Size = UDim2.fromOffset(SizeX,SizeY)
		end
	end)
	Connect(Dragger.InputEnded, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			StartPosition,StartSize = nil,nil
			Callback(Object.Size)
		end
	end)
end

local function ChooseTab(ScreenAsset,TabButtonAsset,TabAsset)
	for Index,Instance in pairs(ScreenAsset:GetChildren()) do
		if Instance.Name == "Palette" or Instance.Name == "OptionContainer" then
			Instance.Visible = false
		end
	end
	for Index,Instance in pairs(ScreenAsset.Window.TabContainer:GetChildren()) do
		if Instance:IsA("ScrollingFrame") and Instance ~= TabAsset then
			Instance.Visible = false
		else
			Instance.Visible = true
		end
	end
	for Index,Instance in pairs(ScreenAsset.Window.TabButtonContainer:GetChildren()) do
		if Instance:IsA("TextButton") then
			Instance.Highlight.Visible = Instance == TabButtonAsset
		end
	end
end
local function ChooseTabSide(TabAsset,Mode)
	if Mode == "Longest" then
		if TabAsset.LeftSide.ListLayout.AbsoluteContentSize.Y > TabAsset.RightSide.ListLayout.AbsoluteContentSize.Y then
			return TabAsset.LeftSide
		else
			return TabAsset.RightSide
		end
	elseif Mode == "Left" then
		return TabAsset.LeftSide
	elseif Mode == "Right" then
		return TabAsset.RightSide
	else
		if TabAsset.LeftSide.ListLayout.AbsoluteContentSize.Y > TabAsset.RightSide.ListLayout.AbsoluteContentSize.Y then
			return TabAsset.RightSide
		else
			return TabAsset.LeftSide
		end
	end
end

local function GetConfigs(PFName)
	if not isfolder(PFName) then makefolder(PFName) end
	if not isfolder(PFName.."\\Configs") then makefolder(PFName.."\\Configs") end
	if not isfile(PFName.."\\DefaultConfig.txt") then writefile(PFName.."\\DefaultConfig.txt","") end

	local Configs = {}
	for Index,Config in pairs(listfiles(PFName.."\\Configs") or {}) do
		Config = Config:gsub(PFName.."\\Configs\\","")
		Config = Config:gsub(".json","")
		Configs[Index] = Config
	end
	return Configs
end
local function ConfigsToList(PFName)
	if not isfolder(PFName) then makefolder(PFName) end
	if not isfolder(PFName.."\\Configs") then makefolder(PFName.."\\Configs") end
	if not isfile(PFName.."\\DefaultConfig.txt") then writefile(PFName.."\\DefaultConfig.txt","") end

	local Configs = {}
	for Index,Config in pairs(listfiles(PFName.."\\Configs") or {}) do
		Config = Config:gsub(PFName.."\\Configs\\","")
		Config = Config:gsub(".json","")
		local DefaultConfig = readfile(PFName.."\\DefaultConfig.txt")
		Configs[Index] = {Name = Config,Mode = "Button",
			Value = Config == DefaultConfig}
	end
	return Configs
end

local function InitToolTip(Parent,ScreenAsset,Text)
	Connect(Parent.MouseEnter, function()
		ScreenAsset.ToolTip.Text = Text
		ScreenAsset.ToolTip.Size = UDim2.new(0,ScreenAsset.ToolTip.TextBounds.X + 2,0,ScreenAsset.ToolTip.TextBounds.Y + 2)
		ScreenAsset.ToolTip.Visible = true
	end)
	Connect(Parent.MouseLeave, function()
		ScreenAsset.ToolTip.Visible = false
	end)
end
local function InitScreen()
	local ScreenAsset = GetAsset("Screen/Bracket")
	if not Debug and type(sethiddenproperty) == "function" then
		pcall(sethiddenproperty, ScreenAsset, "OnTopOfCoreBlur", true)
	end
	ScreenAsset.Name = "Bracket " .. game:GetService("HttpService"):GenerateGUID(false)
	ScreenAsset.Parent = Debug and LocalPlayer:FindFirstChildOfClass("PlayerGui") or CoreGui
	Runtime.Screens[#Runtime.Screens + 1] = ScreenAsset
	EnsureHiddenContainer(ScreenAsset)
	--[[if Debug then
		ScreenAsset.Parent = LocalPlayer.PlayerGui
	else
		Parvus.Utilities.Misc:HideObject(ScreenAsset)
	end]]
	return {ScreenAsset = ScreenAsset}
end
local function InitWindow(ScreenAsset,Window)
	local WindowAsset = GetAsset("Window/Window")

	WindowAsset.Parent = ScreenAsset
	WindowAsset.Visible = Window.Enabled
	WindowAsset.Title.Text = Window.Name
	WindowAsset.Position = Window.Position
	WindowAsset.Size = Window.Size

    local uiScale = Instance.new("UIScale")
    uiScale.Name = "BracketUIScale"
    uiScale.Scale = 1
    uiScale.Parent = WindowAsset
    Window._UIScale = uiScale

	MakeDraggable(WindowAsset.Drag,WindowAsset,function(Position)
		Window.Position = Position
	end)
	MakeResizeable(WindowAsset.Resize,WindowAsset,Vector2.new(760,540),function(Size)
		Window.Size = Size
	end)

	Connect(WindowAsset.TabButtonContainer.ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
		WindowAsset.TabButtonContainer.CanvasSize = UDim2.new(0,WindowAsset.TabButtonContainer.ListLayout.AbsoluteContentSize.X,0,0)
	end)
    pcall(function()
        WindowAsset.TabButtonContainer.ListLayout.Padding = UDim.new(0, 2)
        WindowAsset.TabButtonContainer.ScrollingDirection = Enum.ScrollingDirection.X
        WindowAsset.TabButtonContainer.ScrollBarThickness = 3
        WindowAsset.TabButtonContainer.ElasticBehavior = Enum.ElasticBehavior.Never
    end)

    local searchBox = Instance.new("TextBox")
    searchBox.Name = "GlobalSearch"
    searchBox.BackgroundColor3 = Color3.fromRGB(22,22,22)
    searchBox.BorderColor3 = Window.Color
    searchBox.BorderSizePixel = 1
    searchBox.ClearTextOnFocus = false
    searchBox.PlaceholderText = "Search all tabs..."
    searchBox.PlaceholderColor3 = Color3.fromRGB(135,135,135)
    searchBox.Text = ""
    searchBox.TextColor3 = Color3.fromRGB(235,235,235)
    searchBox.TextSize = 12
    searchBox.Font = Enum.Font.Code
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.Position = UDim2.new(1,-250,0,3)
    searchBox.Size = UDim2.new(0,244,0,18)
    searchBox.ZIndex = 25
    searchBox.Parent = WindowAsset
    Window.SearchBox = searchBox

    local function applySearch(query)
        query = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        Runtime.SearchQuery = query
        local sectionMatches = setmetatable({}, {__mode = "k"})
        local firstMatchingTab = nil
        for _, api in ipairs(Runtime.SearchEntries) do
            if api and api._Asset then
                local haystack = table.concat({
                    tostring(api._SearchName or ""),
                    tostring(api._SearchSection and api._SearchSection.Name or ""),
                    tostring(api._SearchTab and api._SearchTab.Name or ""),
                }, " "):lower()
                local match = query == "" or haystack:find(query, 1, true) ~= nil
                if api._SearchSection and match then sectionMatches[api._SearchSection] = true end
                if match and not firstMatchingTab then firstMatchingTab = api._SearchTab end
                if type(api._SetSearchVisible) == "function" then api:_SetSearchVisible(match) end
            end
        end
        for _, section in ipairs(Runtime.Sections) do
            if section and section._Asset and type(section._SetSearchVisible) == "function" then
                local ownMatch = query == "" or tostring(section.Name or ""):lower():find(query, 1, true) ~= nil
                local match = ownMatch or sectionMatches[section] == true
                section:_SetSearchVisible(match)
                if type(section._SetSearchExpanded) == "function" then
                    section:_SetSearchExpanded(query ~= "" and match)
                end
                if match and query ~= "" and not firstMatchingTab then firstMatchingTab = section._Tab end
            end
        end
        if query ~= "" and firstMatchingTab and type(firstMatchingTab.Select) == "function" then
            firstMatchingTab:Select()
        end
        for _, window in ipairs(Runtime.Windows) do
            for _, tab in ipairs(window.Tabs or {}) do
                if tab and type(tab.RefreshLayout) == "function" then tab:RefreshLayout() end
            end
        end
    end
    function Window:ApplySearch(query)
        searchBox.Text = tostring(query or "")
        applySearch(query)
    end
    function Window:GetSearchQuery() return Runtime.SearchQuery end
    Connect(searchBox:GetPropertyChangedSignal("Text"), function() applySearch(searchBox.Text) end)

    Window.CustomFonts = Window.CustomFonts or {}
    function Window:RegisterFont(fontName, fontFace)
        fontName = tostring(fontName or "")
        if fontName == "" or typeof(fontFace) ~= "Font" then return false end
        Window.CustomFonts[fontName] = fontFace
        if Window.Font == fontName then Window:SetFont(fontName) end
        return true
    end
    function Window:SetScale(scale)
        -- Compatibility-only; V1.5.1 intentionally exposes no UI Scale control.
        scale = math.clamp(tonumber(scale) or 1, 0.65, 1.5)
        Window.Scale = scale
        uiScale.Scale = scale
    end
    function Window:SetFont(fontName)
        fontName = tostring(fontName or "Code")
        local customFont = Window.CustomFonts[fontName]
        local enumFont = fontName == "Minecraft" and Enum.Font.Arcade or (Enum.Font[fontName] or Enum.Font.Code)
        Window.Font = fontName
        Window.Flags["UI/Font"] = fontName
        for _, object in ipairs(WindowAsset:GetDescendants()) do
            if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                pcall(function()
                    if customFont then object.FontFace = customFont else object.Font = enumFont end
                end)
            end
        end
    end
    function Window:SetTheme(themeName)
        themeName = tostring(themeName or "Dark")
        Window.Theme = themeName
        Window.Flags["UI/Theme"] = themeName
        local background = themeName == "Light" and Color3.fromRGB(225,225,225)
            or themeName == "Darker" and Color3.fromRGB(10,10,10)
            or Color3.fromRGB(18,18,18)
        local textColor = themeName == "Light" and Color3.fromRGB(25,25,25) or Color3.fromRGB(235,235,235)
        local accentObjects = {}
        for _, object in ipairs(Window.Colorable) do accentObjects[object] = true end
        for _, object in ipairs(WindowAsset:GetDescendants()) do
            if object:IsA("Frame") and object.BackgroundTransparency < 0.95 and not accentObjects[object] then
                pcall(function() object.BackgroundColor3 = background end)
            elseif object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                pcall(function() object.TextColor3 = textColor end)
            end
        end
        searchBox.BackgroundColor3 = background
        searchBox.TextColor3 = textColor
        -- Re-apply accent-bearing control visuals after the theme pass.
        for _, element in ipairs(Window.Elements or {}) do
            if type(element._RefreshVisual) == "function" then pcall(element._RefreshVisual) end
        end
    end
    function Window:GetBindConflicts()
        local byKey, conflicts = {}, {}
        for _, element in ipairs(Window.Elements or {}) do
            if element._IsKeybind and element.Value and element.Value ~= "NONE" then
                byKey[element.Value] = byKey[element.Value] or {}
                table.insert(byKey[element.Value], element)
            end
        end
        for key, items in pairs(byKey) do if #items > 1 then conflicts[key] = items end end
        return conflicts
    end
	Connect(RunService.RenderStepped, function()
		if WindowAsset.Visible then
			ScreenAsset.ToolTip.Position = UDim2.new(0,UserInputService:GetMouseLocation().X + 5,0,UserInputService:GetMouseLocation().Y - 5)
		end
	end)
	Connect(RunService.RenderStepped, function()
		Window.RainbowHue = os.clock()%10/10
		--[[if Window.RainbowHue < 1 then
			Window.RainbowHue = Window.RainbowHue + 0.001
		else
			Window.RainbowHue = 0
		end]]
	end)
	function Window:SetName(Name)
		Window.Name = Name
		WindowAsset.Title.Text = Name
	end
	function Window:SetSize(Size)
        local width = math.max(760, tonumber(Size.X.Offset) or 760)
        local height = math.max(540, tonumber(Size.Y.Offset) or 540)
        Window.Size = UDim2.fromOffset(width, height)
        WindowAsset.Size = Window.Size
        Window.Flags["UI/Window/Size"] = {width, height}
	end
	function Window:SetPosition(Position)
        Window.Position = Position
        WindowAsset.Position = Position
        Window.Flags["UI/Window/Position"] = {Position.X.Scale,Position.X.Offset,Position.Y.Scale,Position.Y.Offset}
	end
	function Window:SetColor(Color)
		if Color.R < 5/255
		and Color.G < 5/255
		and Color.B < 5/255 then
			Color = Color3.fromRGB(5,5,5)
		end

		for Index,Instance in pairs(Window.Colorable) do
			if Instance.BackgroundColor3 == Window.Color then
				Instance.BackgroundColor3 = Color
			end
			if Instance.BorderColor3 == Window.Color then
				Instance.BorderColor3 = Color
			end
		end
		Window.Color = Color
	end
	function Window:Toggle(Boolean)
		Window.Enabled = Boolean
		WindowAsset.Visible = Window.Enabled

		if not Debug then
		RunService:SetRobloxGuiFocused(Window.Enabled and Window.Flags["UI/Blur"]) end
		if not Window.Enabled then for Index,Instance in pairs(ScreenAsset:GetChildren()) do
			if Instance.Name == "Palette" or Instance.Name == "OptionContainer" then
				Instance.Visible = false
			end
		end end
	end

	function Window:SetValue(Flag,Value)
		for Index,Element in pairs(Window.Elements) do
			if Element.Flag == Flag then
				Element:SetValue(Value)
			end
		end
	end

	function Window:GetValue(Flag)
		for Index,Element in pairs(Window.Elements) do
			if Element.Flag == Flag then
				return Window.Flags[Element.Flag]
			end
		end
	end

	function Window:Watermark(Watermark)
		Watermark = GetType(Watermark,{},"table")
		Watermark.Title = GetType(Watermark.Title,"","string")
		Watermark.Enabled = GetType(Watermark.Enabled,false,"boolean")
		Watermark.Flag = GetType(Watermark.Flag,"UI/Watermark/Position","string")

		ScreenAsset.Watermark.Visible = Watermark.Enabled
		ScreenAsset.Watermark.Title.Text = Watermark.Title
		ScreenAsset.Watermark.Position = UDim2.new(0.95,0,0,10)
		ScreenAsset.Watermark.Size = UDim2.new(
		0,ScreenAsset.Watermark.Title.TextBounds.X + 6,
		0,ScreenAsset.Watermark.Title.TextBounds.Y + 6)
		MakeDraggable(ScreenAsset.Watermark,ScreenAsset.Watermark,function(Position)
			Window.Flags[Watermark.Flag] = 
			{Position.X.Scale,Position.X.Offset,
			Position.Y.Scale,Position.Y.Offset}
		end)

		function Watermark:Toggle(Boolean)
			Watermark.Enabled = Boolean
			ScreenAsset.Watermark.Visible = Watermark.Enabled
		end
		function Watermark:Transparency(Number)
			ScreenAsset.Watermark.BackgroundTransparency = Number
			ScreenAsset.Watermark.Stroke.Transparency = Number
			ScreenAsset.Watermark.Title.TextTransparency = Number
		end
		function Watermark:SetTitle(Text)
			Watermark.Title = Text
			ScreenAsset.Watermark.Title.Text = Watermark.Title
			ScreenAsset.Watermark.Size = UDim2.new(0,ScreenAsset.Watermark.Title.TextBounds.X + 6,0,ScreenAsset.Watermark.Title.TextBounds.Y + 6)
		end
		function Watermark:SetValue(Table)
			if not Table then return end
			ScreenAsset.Watermark.Position = UDim2.new(
				Table[1],Table[2],
				Table[3],Table[4]
			)
		end

		Window.Elements[#Window.Elements + 1] = Watermark
		Window.Watermark = Watermark
	end

	function Window:SaveConfig(PFName,Name)
		local Config = {}
		if table.find(GetConfigs(PFName),Name) then
			Config = HttpService:JSONDecode(readfile(PFName.."\\Configs\\"..Name..".json"))
		end
		for Index,Element in pairs(Window.Elements) do
			if not Element.IgnoreFlag then
				Config[Element.Flag] = Window.Flags[Element.Flag]
			end
		end
		writefile(PFName.."\\Configs\\"..Name..".json",HttpService:JSONEncode(Config))
	end
	function Window:LoadConfig(PFName,Name)
		if table.find(GetConfigs(PFName),Name) then
			local DecodedJSON = HttpService:JSONDecode(readfile(PFName.."\\Configs\\"..Name..".json"))
			for Index,Element in pairs(Window.Elements) do
				if DecodedJSON[Element.Flag] ~= nil then
					Element:SetValue(DecodedJSON[Element.Flag])
				end
			end
		end
	end
	function Window:DeleteConfig(PFName,Name)
		if table.find(GetConfigs(PFName),Name) then
			delfile(PFName.."\\Configs\\"..Name..".json")
		end
	end
	function Window:GetDefaultConfig(PFName)
		if not isfolder(PFName) then makefolder(PFName) end
		if not isfolder(PFName.."\\Configs") then makefolder(PFName.."\\Configs") end
		if not isfile(PFName.."\\DefaultConfig.txt") then writefile(PFName.."\\DefaultConfig.txt","") end

		local DefaultConfig = readfile(PFName.."\\DefaultConfig.txt")
		if table.find(GetConfigs(PFName),DefaultConfig) then
			return DefaultConfig
		end
	end
	function Window:LoadDefaultConfig(PFName)
		if not isfolder(PFName) then makefolder(PFName) end
		if not isfolder(PFName.."\\Configs") then makefolder(PFName.."\\Configs") end
		if not isfile(PFName.."\\DefaultConfig.txt") then writefile(PFName.."\\DefaultConfig.txt","") end

		local DefaultConfig = readfile(PFName.."\\DefaultConfig.txt")
		if table.find(GetConfigs(PFName),DefaultConfig) then
			Window:LoadConfig(PFName,DefaultConfig)
		end
	end

    Window.Flags["UI/Window/Size"] = {Window.Size.X.Offset,Window.Size.Y.Offset}
    Window.Flags["UI/Window/Position"] = {Window.Position.X.Scale,Window.Position.X.Offset,Window.Position.Y.Scale,Window.Position.Y.Offset}
    Window.Flags["UI/Theme"] = Window.Theme or "Dark"
    Window.Flags["UI/Font"] = Window.Font or "Code"
    local sizeElement = {Flag = "UI/Window/Size", IgnoreFlag = false}
    function sizeElement:SetValue(value)
        if type(value) == "table" and tonumber(value[1]) and tonumber(value[2]) then
            Window:SetSize(UDim2.fromOffset(tonumber(value[1]), tonumber(value[2])))
        end
    end
    local positionElement = {Flag = "UI/Window/Position", IgnoreFlag = false}
    function positionElement:SetValue(value)
        if type(value) == "table" and #value >= 4 then
            Window:SetPosition(UDim2.new(tonumber(value[1]) or 0.5,tonumber(value[2]) or 0,tonumber(value[3]) or 0.5,tonumber(value[4]) or 0))
        end
    end
    local themeElement = {Flag = "UI/Theme", IgnoreFlag = false}
    function themeElement:SetValue(value) Window:SetTheme(value) end
    local fontElement = {Flag = "UI/Font", IgnoreFlag = false}
    function fontElement:SetValue(value) Window:SetFont(value) end
    Window.Elements[#Window.Elements+1] = sizeElement
    Window.Elements[#Window.Elements+1] = positionElement
    Window.Elements[#Window.Elements+1] = themeElement
    Window.Elements[#Window.Elements+1] = fontElement

	Window.Background = WindowAsset.Background
	return WindowAsset
end
local function InitTab(ScreenAsset,WindowAsset,Window,Tab)
	local TabButtonAsset = GetAsset("Tab/TabButton")
	local TabAsset = GetAsset("Tab/Tab")

	TabButtonAsset.Parent = WindowAsset.TabButtonContainer
	TabButtonAsset.Text = Tab.Name
	TabButtonAsset.Highlight.BackgroundColor3 = Window.Color
	TabButtonAsset.Size = UDim2.new(0,math.max(72,TabButtonAsset.TextBounds.X + 18),1,-1)
	TabAsset.Parent = WindowAsset.TabContainer
	TabAsset.Visible = false
	TabAsset.ScrollingEnabled = true
	TabAsset.ScrollingDirection = Enum.ScrollingDirection.Y
	TabAsset.ScrollBarThickness = 6
	TabAsset.ScrollBarImageTransparency = 0.15
	TabAsset.ElasticBehavior = Enum.ElasticBehavior.Never
	TabAsset.VerticalScrollBarInset = Enum.ScrollBarInset.None

	local leftLayout = TabAsset.LeftSide.ListLayout
	local rightLayout = TabAsset.RightSide.ListLayout
	local updateQueued = false
	local updating = false
	local lastHeight = -1
	local CONTENT_PADDING = 21

	local function scheduleUpdate()
		if updateQueued or Runtime.Destroyed then return end
		updateQueued = true
		local generation = Runtime.Generation
		task.defer(function()
			updateQueued = false
			if Runtime.Destroyed or generation ~= Runtime.Generation or updating or not TabAsset.Parent then return end
			updating = true
			local height = math.ceil(math.max(
				leftLayout.AbsoluteContentSize.Y,
				rightLayout.AbsoluteContentSize.Y
			) + CONTENT_PADDING)
			height = math.max(0, height)
			if math.abs(height - lastHeight) >= 1 then
				lastHeight = height
				TabAsset.CanvasSize = UDim2.fromOffset(0, height)
			end
			updating = false
		end)
	end

	Runtime.RefreshByInstance[TabAsset] = scheduleUpdate
	Runtime.RefreshByInstance[TabAsset.LeftSide] = scheduleUpdate
	Runtime.RefreshByInstance[TabAsset.RightSide] = scheduleUpdate
	table.insert(Window.Colorable,TabButtonAsset.Highlight)
	Connect(leftLayout:GetPropertyChangedSignal("AbsoluteContentSize"), scheduleUpdate)
	Connect(rightLayout:GetPropertyChangedSignal("AbsoluteContentSize"), scheduleUpdate)
	Connect(TabButtonAsset.MouseButton1Click, function()
		ChooseTab(ScreenAsset,TabButtonAsset,TabAsset)
	end)

	if #WindowAsset.TabContainer:GetChildren() == 1 then
		ChooseTab(ScreenAsset,TabButtonAsset,TabAsset)
	end

	function Tab:SetName(Name)
		Tab.Name = Name
		TabButtonAsset.Text = Name
		TabButtonAsset.Size = UDim2.new(0,math.max(72,TabButtonAsset.TextBounds.X + 18),1,-1)
	end
    function Tab:Select()
        ChooseTab(ScreenAsset,TabButtonAsset,TabAsset)
    end
	function Tab:RefreshLayout()
		scheduleUpdate()
	end
    Tab._Button = TabButtonAsset
	Tab._Asset = TabAsset
	Tab._ScheduleUpdate = scheduleUpdate
	scheduleUpdate()

	return function(Side)
		return ChooseTabSide(TabAsset,Side)
	end
end
local function InitSection(Parent,Section)
	local SectionAsset = GetAsset("Section/Section")

	SectionAsset.Parent = Parent
	SectionAsset.Title.Text = Section.Name
	SectionAsset.Title.Size = UDim2.new(1,-30,0,math.max(14,SectionAsset.Title.TextBounds.Y + 2))
	local listLayout = SectionAsset.Container.ListLayout
	local updateQueued = false
	local lastHeight = -1
	local tabRefresh = GetRefresh(Parent)

	local function refreshLayout()
		if updateQueued or Runtime.Destroyed then return end
		updateQueued = true
		local generation = Runtime.Generation
		task.defer(function()
			updateQueued = false
			if Runtime.Destroyed or generation ~= Runtime.Generation or not SectionAsset.Parent then return end
			local height = math.ceil(listLayout.AbsoluteContentSize.Y + 15)
			if math.abs(height - lastHeight) >= 1 then
				lastHeight = height
				SectionAsset.Size = UDim2.new(1,0,0,height)
			end
			if tabRefresh then tabRefresh() end
		end)
	end

	Runtime.RefreshByInstance[SectionAsset] = refreshLayout
	Runtime.RefreshByInstance[SectionAsset.Container] = refreshLayout
	Connect(listLayout:GetPropertyChangedSignal("AbsoluteContentSize"), refreshLayout)

	function Section:SetName(Name)
		Section.Name = Name
		SectionAsset.Title.Text = Name
		SectionAsset.Title.Size = UDim2.new(1,-30,0,math.max(14,SectionAsset.Title.TextBounds.Y + 2))
		refreshLayout()
	end
    Section.Collapsed = Section.Collapsed == true
    Section._Container = SectionAsset.Container
    Section._ExpandedHeight = nil
    Section._SearchExpanded = false
    local collapseButton = Instance.new("TextButton")
    collapseButton.Name = "CollapseToggle"
    collapseButton.BackgroundTransparency = 1
    collapseButton.BorderSizePixel = 0
    collapseButton.Text = Section.Collapsed and "+" or "−"
    collapseButton.TextColor3 = SectionAsset.Title.TextColor3
    collapseButton.TextSize = math.max(12, SectionAsset.Title.TextSize)
    collapseButton.Font = SectionAsset.Title.Font
    collapseButton.AutoButtonColor = false
    collapseButton.AnchorPoint = Vector2.new(1, 0)
    collapseButton.Position = UDim2.new(1, -4, 0, 0)
    collapseButton.Size = UDim2.new(0, 22, 0, 16)
    collapseButton.ZIndex = math.max(SectionAsset.Title.ZIndex, 2) + 1
    collapseButton.Parent = SectionAsset
    Section._CollapseButton = collapseButton
    pcall(function()
        SectionAsset.Title.Active = true
        SectionAsset.Title.Size = UDim2.new(1, -30, 0, math.max(14, SectionAsset.Title.TextBounds.Y + 2))
    end)
    local function applyCollapsedVisual()
        local collapsed = Section.Collapsed and not Section._SearchExpanded
        SectionAsset.Container.Visible = not collapsed
        collapseButton.Text = collapsed and "+" or "−"
        if collapsed then
            SectionAsset.Size = UDim2.new(1,0,0,18)
            if tabRefresh then tabRefresh() end
        else
            refreshLayout()
        end
    end
    function Section:SetCollapsed(value)
        value = value == true
        if Section.Collapsed == value and not Section._SearchExpanded then return end
        Section.Collapsed = value
        applyCollapsedVisual()
    end
    function Section:_SetSearchExpanded(value)
        value = value == true
        if Section._SearchExpanded == value then return end
        Section._SearchExpanded = value
        applyCollapsedVisual()
    end
    function Section:IsCollapsed() return Section.Collapsed == true end
    Connect(collapseButton.MouseButton1Click, function()
        if Section._SearchExpanded then return end
        Section:SetCollapsed(not Section.Collapsed)
    end)
    Connect(SectionAsset.Title.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not Section._SearchExpanded then
            Section:SetCollapsed(not Section.Collapsed)
        end
    end)
	function Section:RefreshLayout()
        if Section.Collapsed and not Section._SearchExpanded then
            SectionAsset.Size = UDim2.new(1,0,0,18)
            if tabRefresh then tabRefresh() end
        else
            refreshLayout()
        end
	end
	AttachVisibility(Section, SectionAsset)
    Runtime.Sections[#Runtime.Sections + 1] = Section
	refreshLayout()

	return SectionAsset.Container, SectionAsset
end
local function InitDivider(Parent,Divider)
	local DividerAsset = GetAsset("Divider/Divider")

	DividerAsset.Parent = Parent
	DividerAsset.Title.Text = Divider.Text

	Connect(DividerAsset.Title:GetPropertyChangedSignal("TextBounds"), function()
		if DividerAsset.Title.TextBounds.X > 0 then
			DividerAsset.Size = UDim2.new(1,0,0,DividerAsset.Title.TextBounds.Y)
			DividerAsset.Left.Size = UDim2.new(0.5,-(DividerAsset.Title.TextBounds.X / 2) - 5,0,2)
			DividerAsset.Right.Position = UDim2.new(0.5,(DividerAsset.Title.TextBounds.X / 2) + 5,0.5,0)
			DividerAsset.Right.Size = UDim2.new(0.5,-(DividerAsset.Title.TextBounds.X / 2) - 5,0,2)
		else
			DividerAsset.Size = UDim2.new(1,0,0,2)
			DividerAsset.Left.Size = UDim2.new(1,0,0,2)
			DividerAsset.Right.Position = UDim2.new(0,0,0.5,0)
			DividerAsset.Right.Size = UDim2.new(1,0,0,2)
		end
	end)

	function Divider:SetText(Text)
		Divider.Text = Text
		DividerAsset.Title.Text = Text
	end
	AttachVisibility(Divider, DividerAsset)
    RegisterSearchEntry(Divider, Divider.Text, Divider._Section, Divider._Tab)
end
local function InitLabel(Parent,Label)
	local LabelAsset = GetAsset("Label/Label")

	LabelAsset.Parent = Parent
	LabelAsset.Text = Label.Text

	Connect(LabelAsset:GetPropertyChangedSignal("TextBounds"), function()
		LabelAsset.Size = UDim2.new(1,0,0,LabelAsset.TextBounds.Y)
	end)

	function Label:SetText(Text)
		Label.Text = Text
		LabelAsset.Text = Text
	end
	AttachVisibility(Label, LabelAsset)
    RegisterSearchEntry(Label, Label.Text, Label._Section, Label._Tab)
end
local function InitButton(Parent,ScreenAsset,Window,Button)
	local ButtonAsset = GetAsset("Button/Button")

	ButtonAsset.Parent = Parent
	ButtonAsset.Title.Text = Button.Name

	table.insert(Window.Colorable,ButtonAsset)
	Button.Connection = Connect(ButtonAsset.MouseButton1Click, Button.Callback)

	Connect(ButtonAsset.MouseButton1Down, function()
		ButtonAsset.BorderColor3 = Window.Color
	end)
	Connect(ButtonAsset.MouseButton1Up, function()
		ButtonAsset.BorderColor3 = Color3.new(0,0,0)
	end)
	Connect(ButtonAsset.MouseLeave, function()
		ButtonAsset.BorderColor3 = Color3.new(0,0,0)
	end)
	Connect(ButtonAsset.Title:GetPropertyChangedSignal("TextBounds"), function()
		ButtonAsset.Size = UDim2.new(1,0,0,ButtonAsset.Title.TextBounds.Y + 2)
	end)

	function Button:SetName(Name)
		Button.Name = Name
		ButtonAsset.Title.Text = Name
	end
	function Button:SetCallback(Callback)
		Button.Callback = Callback
		Button.Connection:Disconnect()
		Button.Connection = Connect(ButtonAsset.MouseButton1Click, Callback)
	end
	function Button:ToolTip(Text)
		InitToolTip(ButtonAsset,ScreenAsset,Text)
	end
	AttachVisibility(Button, ButtonAsset)
    RegisterSearchEntry(Button, Button.Name, Button._Section, Button._Tab)
end
local function GetKeybindConflicts(Window, Keybind, proposedKey)
    local conflicts = {}
    proposedKey = tostring(proposedKey or "NONE")
    if proposedKey == "NONE" then return conflicts end
    for _, element in ipairs(Window.Elements or {}) do
        if element ~= Keybind and element._IsKeybind and tostring(element.Value or "NONE") == proposedKey then
            conflicts[#conflicts + 1] = element
        end
    end
    return conflicts
end

local function ResolveKeybindConflict(Window, Keybind, proposedKey, applyCallback, cancelCallback)
    proposedKey = tostring(proposedKey or "NONE")
    Keybind.WaitingForBind = false
    local conflicts = GetKeybindConflicts(Window, Keybind, proposedKey)
    if #conflicts == 0 or proposedKey == "NONE" then
        applyCallback(proposedKey)
        return
    end
    local names = {}
    for _, element in ipairs(conflicts) do names[#names + 1] = tostring(element.Name or element.Flag or "another action") end
    local function replace()
        for _, element in ipairs(conflicts) do
            if type(element.SetValue) == "function" then pcall(function() element:SetValue("NONE") end) end
        end
        applyCallback(proposedKey)
    end
    local function cancel()
        if cancelCallback then cancelCallback() end
    end
    if Bracket and type(Bracket.Confirm) == "function" then
        Bracket:Confirm({
            Title = "Bind Conflict",
            Description = string.format("%s is already used by %s.", proposedKey, table.concat(names, ", ")),
            ConfirmText = "Replace",
            CancelText = "Cancel",
            OnConfirm = replace,
            OnCancel = cancel,
        })
    else
        cancel()
    end
end

local function InitToggle(Parent,ScreenAsset,Window,Toggle)
	local ToggleAsset = GetAsset("Toggle/Toggle")

	ToggleAsset.Parent = Parent
	ToggleAsset.Title.Text = Toggle.Name
    local function InitializeToggleVisual()
        ToggleAsset.Tick.BackgroundColor3 = Toggle.Value and Window.Color or Color3.fromRGB(60,60,60)
        ToggleAsset.Tick.Visible = true
    end
    Toggle._RefreshVisual = InitializeToggleVisual
    InitializeToggleVisual()
    task.defer(InitializeToggleVisual)

	table.insert(Window.Colorable,ToggleAsset.Tick)
	Connect(ToggleAsset.MouseButton1Click, function()
		Toggle.Value = not Toggle.Value
		Window.Flags[Toggle.Flag] = Toggle.Value
		Toggle.Callback(Toggle.Value)
		ToggleAsset.Tick.BackgroundColor3 = Toggle.Value and Window.Color or Color3.fromRGB(60,60,60)
	end)
	Connect(ToggleAsset.Title:GetPropertyChangedSignal("TextBounds"), function()
		ToggleAsset.Size = UDim2.new(1,0,0,ToggleAsset.Title.TextBounds.Y)
	end)

	function Toggle:SetName(Name)
		Toggle.Name = Name
		ToggleAsset.Title.Text = Name
	end
	function Toggle:SetValue(Boolean)
		Toggle.Value = Boolean
		Window.Flags[Toggle.Flag] = Toggle.Value
		Toggle.Callback(Toggle.Value)
		ToggleAsset.Tick.BackgroundColor3 = Toggle.Value and Window.Color or Color3.fromRGB(60,60,60)
	end
	function Toggle:SetCallback(Callback)
		Toggle.Callback = Callback
	end
	function Toggle:ToolTip(Text)
		InitToolTip(ToggleAsset,ScreenAsset,Text)
	end
	function Toggle:Keybind(Keybind)
		Keybind = GetType(Keybind,{},"table")
		Keybind.Flag = GetType(Keybind.Flag,Toggle.Flag.."/Keybind","string")

		Keybind.Name = GetType(Keybind.Name,Toggle.Name .. " Keybind","string")
		Keybind.Value = GetType(Keybind.Value,"NONE","string")
		Keybind.Callback = GetType(Keybind.Callback,function() end,"function")
		Keybind.Blacklist = GetType(Keybind.Blacklist,{"W","A","S","D","Slash","Tab","Backspace","Escape","Space","Delete","Unknown","Backquote"},"table")
		Keybind.AcceptedInputs = setmetatable({}, {__mode = "k"})

		Window.Elements[#Window.Elements + 1] = Keybind
		Window.Flags[Keybind.Flag] = Keybind.Value

		ToggleAsset.Keybind.Visible = true
		ToggleAsset.Keybind.Text = "[ " .. Keybind.Value .. " ]"
		Keybind.WaitingForBind = false

        local function applyKey(key, fireCallback)
            key = tostring(key or "NONE")
            ToggleAsset.Keybind.Text = "[ " .. key .. " ]"
            Keybind.Value = key
            Keybind.WaitingForBind = false
            Window.Flags[Keybind.Flag] = key
            if fireCallback ~= false then Keybind.Callback(key,false) end
        end
        local function cancelBinding()
            ToggleAsset.Keybind.Text = "[ " .. tostring(Keybind.Value or "NONE") .. " ]"
            Keybind.WaitingForBind = false
        end

		Connect(ToggleAsset.Keybind.MouseButton1Click, function()
            if not IsRuntimeVisible(Keybind) then return end
			ToggleAsset.Keybind.Text = "[ ... ]"
			Keybind.WaitingForBind = true
		end)
		Connect(ToggleAsset.Keybind:GetPropertyChangedSignal("TextBounds"), function()
			ToggleAsset.Keybind.Size = UDim2.new(0,ToggleAsset.Keybind.TextBounds.X,1,0)
			ToggleAsset.Title.Size = UDim2.new(1,-ToggleAsset.Keybind.Size.X.Offset - 20,1,0)
		end)

		Connect(UserInputService.InputBegan, function(Input, Processed)
            if Processed or UserInputService:GetFocusedTextBox() or (Runtime.ConfirmDialog and Runtime.ConfirmDialog.Parent) or not IsRuntimeVisible(Keybind) then return end
			local keyboardKey = tostring(Input.KeyCode):gsub("Enum.KeyCode.","")
			if Keybind.WaitingForBind and Input.UserInputType == Enum.UserInputType.Keyboard then
                local proposed = table.find(Keybind.Blacklist,keyboardKey) and (Keybind.DoNotClear and Keybind.Value or "NONE") or keyboardKey
                ResolveKeybindConflict(Window, Keybind, proposed, function(key) applyKey(key, true) end, cancelBinding)
			elseif Input.UserInputType == Enum.UserInputType.Keyboard and keyboardKey == Keybind.Value then
                Keybind.AcceptedInputs[Input] = Keybind.Value
				Toggle.Value = not Toggle.Value
				Window.Flags[Toggle.Flag] = Toggle.Value
				Toggle.Callback(Toggle.Value)
				Keybind.Callback(Keybind.Value,true)
				ToggleAsset.Tick.BackgroundColor3 = Toggle.Value and Window.Color or Color3.fromRGB(60,60,60)
			end
			if Keybind.Mouse then
				local mouseKey = tostring(Input.UserInputType):gsub("Enum.UserInputType.","")
                local isMouse = Input.UserInputType == Enum.UserInputType.MouseButton1
                    or Input.UserInputType == Enum.UserInputType.MouseButton2
                    or Input.UserInputType == Enum.UserInputType.MouseButton3
				if Keybind.WaitingForBind and isMouse then
                    ResolveKeybindConflict(Window, Keybind, mouseKey, function(key) applyKey(key, true) end, cancelBinding)
				elseif isMouse and mouseKey == Keybind.Value then
                    Keybind.AcceptedInputs[Input] = Keybind.Value
					Toggle.Value = not Toggle.Value
					Window.Flags[Toggle.Flag] = Toggle.Value
					Toggle.Callback(Toggle.Value)
					Keybind.Callback(Keybind.Value,true)
					ToggleAsset.Tick.BackgroundColor3 = Toggle.Value and Window.Color or Color3.fromRGB(60,60,60)
				end
			end
		end)
		Connect(UserInputService.InputEnded, function(Input)
            local acceptedKey = Keybind.AcceptedInputs[Input]
            if not acceptedKey then return end
            Keybind.AcceptedInputs[Input] = nil
			Keybind.Callback(acceptedKey,false)
		end)
		function Keybind:SetValue(Key)
            applyKey(Key, true)
		end
		function Keybind:SetCallback(Callback)
			Keybind.Callback = Callback
		end

        Keybind._IsKeybind = true
		AttachVisibility(Keybind, ToggleAsset.Keybind)
        RegisterSearchEntry(Keybind, Toggle.Name .. " Keybind", Toggle._Section, Toggle._Tab)
		return Keybind
	end
	AttachVisibility(Toggle, ToggleAsset)
    RegisterSearchEntry(Toggle, Toggle.Name, Toggle._Section, Toggle._Tab)
end
local function InitSlider(Parent,ScreenAsset,Window,Slider)
	local SliderAsset = GetAsset("Slider/Slider")

	SliderAsset.Parent = Parent
	SliderAsset.Title.Text = Slider.Name
	Slider.Value = tonumber(string.format("%." .. Slider.Precise .. "f",Slider.Value))
	SliderAsset.Background.Bar.Size = UDim2.new((Slider.Value - Slider.Min) / (Slider.Max - Slider.Min),0,1,0)
	SliderAsset.Background.Bar.BackgroundColor3 = Window.Color
    local function InitializeSliderVisual()
        local range = Slider.Max - Slider.Min
        local alpha = range ~= 0 and math.clamp((Slider.Value - Slider.Min) / range, 0, 1) or 0
        SliderAsset.Background.Bar.Size = UDim2.new(alpha,0,1,0)
        SliderAsset.Background.Bar.BackgroundColor3 = Window.Color
        SliderAsset.Background.Bar.Visible = true
    end
    Slider._RefreshVisual = InitializeSliderVisual
    task.defer(InitializeSliderVisual)
	table.insert(Window.Colorable,SliderAsset.Background.Bar)

	if #Slider.Unit == 0 then
		SliderAsset.Value.PlaceholderText = Slider.Value
	else
		SliderAsset.Value.PlaceholderText = Slider.Value .. " " .. Slider.Unit
	end

	local function UpdateVisual(Value)
		Slider.Value = tonumber(string.format("%." .. Slider.Precise .. "f",Value))
		SliderAsset.Background.Bar.Size = UDim2.new((Slider.Value - Slider.Min) / (Slider.Max - Slider.Min),0,1,0)
		if #Slider.Unit == 0 then
			SliderAsset.Value.PlaceholderText = Slider.Value
		else
			SliderAsset.Value.PlaceholderText = Slider.Value .. " " .. Slider.Unit
		end

		Window.Flags[Slider.Flag] = Slider.Value
		Slider.Callback(Slider.Value)
	end
	local function AttachToMouse(Input)
		local XScale = math.clamp((Input.Position.X - SliderAsset.Background.AbsolutePosition.X) / SliderAsset.Background.AbsoluteSize.X,0,1)
		local SliderPrecise = math.clamp(XScale * (Slider.Max - Slider.Min) + Slider.Min,Slider.Min,Slider.Max)
		UpdateVisual(SliderPrecise)
	end

	function Slider:SetName(Name)
		Slider.Name = Name
		SliderAsset.Title.Text = Name
	end
	function Slider:SetValue(Value)
		UpdateVisual(Value)
	end
	function Slider:SetCallback(Callback)
		Slider.Callback = Callback
	end
	function Slider:ToolTip(Text)
		InitToolTip(SliderAsset,ScreenAsset,Text)
	end

	Connect(SliderAsset.Title:GetPropertyChangedSignal("TextBounds"), function()
		SliderAsset.Value.Size = UDim2.new(0,SliderAsset.Value.TextBounds.X,0,16)
		SliderAsset.Title.Size = UDim2.new(1,-SliderAsset.Value.Size.X.Offset,0,16)
		SliderAsset.Size = UDim2.new(1,0,0,SliderAsset.Title.TextBounds.Y + 8)
	end)
	Connect(SliderAsset.Value:GetPropertyChangedSignal("TextBounds"), function()
		SliderAsset.Value.Size = UDim2.new(0,SliderAsset.Value.TextBounds.X,0,16)
		SliderAsset.Title.Size = UDim2.new(1,-SliderAsset.Value.Size.X.Offset,0,16)
	end)
	Connect(SliderAsset.Value.FocusLost, function()
		if not tonumber(SliderAsset.Value.Text) then
			SliderAsset.Value.Text = Slider.Value
		elseif tonumber(SliderAsset.Value.Text) <= Slider.Min then
			SliderAsset.Value.Text = Slider.Min
		elseif tonumber(SliderAsset.Value.Text) >= Slider.Max then
			SliderAsset.Value.Text = Slider.Max
		end
		UpdateVisual(SliderAsset.Value.Text)
		SliderAsset.Value.Text = ""
	end)
	Connect(SliderAsset.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			AttachToMouse(Input)
			Slider.Active = true
		end
	end)
	Connect(SliderAsset.InputEnded, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			Slider.Active = false
		end
	end)
	Connect(UserInputService.InputChanged, function(Input)
		if Slider.Active and Input.UserInputType == Enum.UserInputType.MouseMovement then
			AttachToMouse(Input)
		end
	end)
	AttachVisibility(Slider, SliderAsset)
    RegisterSearchEntry(Slider, Slider.Name, Slider._Section, Slider._Tab)
end
local function InitTextbox(Parent,ScreenAsset,Window,Textbox)
	local TextboxAsset = GetAsset("Textbox/Textbox")

	TextboxAsset.Parent = Parent
	TextboxAsset.Title.Text = Textbox.Name
	TextboxAsset.Background.Input.Text = Textbox.Value
	TextboxAsset.Background.Input.PlaceholderText = Textbox.Placeholder

	Connect(TextboxAsset.Title:GetPropertyChangedSignal("TextBounds"), function()
		TextboxAsset.Size = UDim2.new(1,0,0,(TextboxAsset.Title.TextBounds.Y + 2) + (TextboxAsset.Background.Input.TextBounds.Y + 2))
	end)
	Connect(TextboxAsset.Background.Input:GetPropertyChangedSignal("TextBounds"), function()
		TextboxAsset.Background.Size = UDim2.new(1,0,0,TextboxAsset.Background.Input.TextBounds.Y + 2)
	end)
	Connect(TextboxAsset.Background.Input.FocusLost, function(EnterPressed)
		if not EnterPressed then return end
		Textbox.Value = TextboxAsset.Background.Input.Text
		Window.Flags[Textbox.Flag] = Textbox.Value
		Textbox.Callback(Textbox.Value)
		if Textbox.AutoClear then
			TextboxAsset.Background.Input.Text = ""
		end
	end)

	function Textbox:SetName(Name)
		Textbox.Name = Name
		TextboxAsset.Title.Text = Name
	end
	function Textbox:SetValue(Text)
		Textbox.Value = Text
		Window.Flags[Textbox.Flag] = Textbox.Value
		TextboxAsset.Background.Input.Text = Textbox.Value
		Textbox.Callback(Textbox.Value)
	end
	function Textbox:SetPlaceholder(Text)
		Textbox.Placeholder = Text
		TextboxAsset.Background.Input.PlaceholderText = Textbox.Placeholder
	end
	function Textbox:SetCallback(Callback)
		Textbox.Callback = Callback
	end
	function Textbox:ToolTip(Text)
		InitToolTip(TextboxAsset,ScreenAsset,Text)
	end
	AttachVisibility(Textbox, TextboxAsset)
    RegisterSearchEntry(Textbox, Textbox.Name, Textbox._Section, Textbox._Tab)
end
local function InitKeybind(Parent,ScreenAsset,Window,Keybind)
	local KeybindAsset = GetAsset("Keybind/Keybind")

	KeybindAsset.Parent = Parent
	KeybindAsset.Title.Text = Keybind.Name
	KeybindAsset.Value.Text = "[ " .. Keybind.Value .. " ]"
	Keybind.WaitingForBind = false
    Keybind.AcceptedInputs = setmetatable({}, {__mode = "k"})

    local function applyKey(key, fireCallback)
        key = tostring(key or "NONE")
        KeybindAsset.Value.Text = "[ " .. key .. " ]"
        Keybind.Value = key
        Keybind.WaitingForBind = false
        Window.Flags[Keybind.Flag] = key
        if fireCallback ~= false then Keybind.Callback(key,false,Keybind.Toggle) end
    end
    local function cancelBinding()
        KeybindAsset.Value.Text = "[ " .. tostring(Keybind.Value or "NONE") .. " ]"
        Keybind.WaitingForBind = false
    end

	Connect(KeybindAsset.MouseButton1Click, function()
        if not IsRuntimeVisible(Keybind) then return end
		KeybindAsset.Value.Text = "[ ... ]"
		Keybind.WaitingForBind = true
	end)
	Connect(KeybindAsset.Title:GetPropertyChangedSignal("TextBounds"), function()
		KeybindAsset.Size = UDim2.new(1,0,0,KeybindAsset.Title.TextBounds.Y)
	end)
	Connect(KeybindAsset.Value:GetPropertyChangedSignal("TextBounds"), function()
		KeybindAsset.Value.Size = UDim2.new(0,KeybindAsset.Value.TextBounds.X,1,0)
		KeybindAsset.Title.Size = UDim2.new(1,-KeybindAsset.Value.Size.X.Offset,1,0)
	end)
	Connect(UserInputService.InputBegan, function(Input, Processed)
        if Processed or UserInputService:GetFocusedTextBox() or (Runtime.ConfirmDialog and Runtime.ConfirmDialog.Parent) or not IsRuntimeVisible(Keybind) then return end
		local keyboardKey = tostring(Input.KeyCode):gsub("Enum.KeyCode.","")
		if Keybind.WaitingForBind and Input.UserInputType == Enum.UserInputType.Keyboard then
            local proposed = table.find(Keybind.Blacklist,keyboardKey) and (Keybind.DoNotClear and Keybind.Value or "NONE") or keyboardKey
            ResolveKeybindConflict(Window, Keybind, proposed, function(key) applyKey(key, true) end, cancelBinding)
		elseif Input.UserInputType == Enum.UserInputType.Keyboard and keyboardKey == Keybind.Value then
            Keybind.AcceptedInputs[Input] = Keybind.Value
			Keybind.Toggle = not Keybind.Toggle
			Keybind.Callback(Keybind.Value,true,Keybind.Toggle)
		end
		if Keybind.Mouse then
			local mouseKey = tostring(Input.UserInputType):gsub("Enum.UserInputType.","")
            local isMouse = Input.UserInputType == Enum.UserInputType.MouseButton1
                or Input.UserInputType == Enum.UserInputType.MouseButton2
                or Input.UserInputType == Enum.UserInputType.MouseButton3
			if Keybind.WaitingForBind and isMouse then
                ResolveKeybindConflict(Window, Keybind, mouseKey, function(key) applyKey(key, true) end, cancelBinding)
			elseif isMouse and mouseKey == Keybind.Value then
                Keybind.AcceptedInputs[Input] = Keybind.Value
				Keybind.Toggle = not Keybind.Toggle
				Keybind.Callback(Keybind.Value,true,Keybind.Toggle)
			end
		end
	end)
	Connect(UserInputService.InputEnded, function(Input)
        local acceptedKey = Keybind.AcceptedInputs[Input]
        if not acceptedKey then return end
        Keybind.AcceptedInputs[Input] = nil
		Keybind.Callback(acceptedKey,false,Keybind.Toggle)
	end)

	function Keybind:SetName(Name)
		Keybind.Name = Name
		KeybindAsset.Title.Text = Name
	end
	function Keybind:SetValue(Key)
        applyKey(Key, true)
	end
	function Keybind:SetCallback(Callback)
		Keybind.Callback = Callback
	end
	function Keybind:ToolTip(Text)
		InitToolTip(KeybindAsset,ScreenAsset,Text)
	end
    Keybind._IsKeybind = true
	AttachVisibility(Keybind, KeybindAsset)
    RegisterSearchEntry(Keybind, Keybind.Name, Keybind._Section, Keybind._Tab)
end
local function InitDropdown(Parent,ScreenAsset,Window,Dropdown)
	local DropdownAsset = GetAsset("Dropdown/Dropdown")
	local OptionContainerAsset = GetAsset("Dropdown/OptionContainer")
	DropdownAsset.Parent = Parent
	DropdownAsset.Title.Text = Dropdown.Name
	OptionContainerAsset.Parent = ScreenAsset
	local ContainerRender = nil

	Connect(DropdownAsset.MouseButton1Click, function()
		if not OptionContainerAsset.Visible and OptionContainerAsset.ListLayout.AbsoluteContentSize.Y ~= 0 then
			ContainerRender = Connect(RunService.RenderStepped, function()
				if not OptionContainerAsset.Visible then ContainerRender:Disconnect() end
				OptionContainerAsset.Position = UDim2.new(0,DropdownAsset.Background.AbsolutePosition.X,0,
				DropdownAsset.Background.AbsolutePosition.Y + DropdownAsset.Background.AbsoluteSize.Y + 42)
				OptionContainerAsset.Size = UDim2.new(0,DropdownAsset.Background.AbsoluteSize.X,0,OptionContainerAsset.ListLayout.AbsoluteContentSize.Y + 2)
			end)
			OptionContainerAsset.Visible = true
		else
			if ContainerRender then
				ContainerRender:Disconnect()
			end
			OptionContainerAsset.Visible = false
		end
	end)
	Connect(DropdownAsset.Title:GetPropertyChangedSignal("TextBounds"), function()
		DropdownAsset.Title.Size = UDim2.new(1,0,0,DropdownAsset.Title.TextBounds.Y + 2)
		DropdownAsset.Background.Position = UDim2.new(0.5,0,0,DropdownAsset.Title.Size.Y.Offset)
		DropdownAsset.Size = UDim2.new(1,0,0,DropdownAsset.Title.Size.Y.Offset + DropdownAsset.Background.Size.Y.Offset)
	end)
	--[[DropdownAsset.Background.Value:GetPropertyChangedSignal("TextBounds"):Connect(function()
		DropdownAsset.Background.Size = UDim2.new(1,0,0,DropdownAsset.Background.Value.TextBounds.Y + 2)
		DropdownAsset.Size = UDim2.new(1,0,0,DropdownAsset.Title.Size.Y.Offset + DropdownAsset.Background.Size.Y.Offset)
	end)]]

	local function SetOptionState(Option,Toggle)
		local Selected = {}

		-- Value Setting
		if Option.Mode == "Button" then
			for Index, Option in pairs(Dropdown.List) do
				if Option.Mode == "Button" then
					if Option.Instance then
						Option.Instance.BorderColor3 = Color3.fromRGB(60,60,60)
					end
					Option.Value = false
				end
			end
			Option.Value = true
			OptionContainerAsset.Visible = false
		elseif Option.Mode == "Toggle" then
			Option.Value = Toggle
		end

		Option.Instance.BorderColor3 = Option.Value
			and Window.Color or Color3.fromRGB(60,60,60)

		-- Selected Setting
		for Index, Option in pairs(Dropdown.List) do
			if Option.Value then
				Selected[#Selected + 1] = Option.Name
			end
		end

		-- Dropdown Title Setting
		if #Selected == 0 then
			DropdownAsset.Background.Value.Text = "..."
		else
			DropdownAsset.Background.Value.Text = table.concat(Selected,", ")
		end

		Dropdown.Value = Selected
		if Option.Callback then
			Option.Callback(Dropdown.Value,Option)
		end
		Window.Flags[Dropdown.Flag] = Dropdown.Value
	end

	for Index, Option in pairs(Dropdown.List) do
		local OptionAsset = GetAsset("Dropdown/Option")
		OptionAsset.Parent = OptionContainerAsset
		OptionAsset.Title.Text = Option.Name
		Option.Instance = OptionAsset

		table.insert(Window.Colorable, OptionAsset)
		Connect(OptionAsset.MouseButton1Click, function()
			SetOptionState(Option,not Option.Value)
		end)
		Connect(OptionAsset.Title:GetPropertyChangedSignal("TextBounds"), function()
			OptionAsset.Size = UDim2.new(1,0,0,OptionAsset.Title.TextBounds.Y + 2)
		end)
	end
	for Index, Option in pairs(Dropdown.List) do
		if Option.Value then
			SetOptionState(Option,Option.Value)
		end
	end

	function Dropdown:BulkAdd(Table)
		for Index,Option in pairs(Table) do
			local OptionAsset = GetAsset("Dropdown/Option")
			OptionAsset.Parent = OptionContainerAsset
			OptionAsset.Title.Text = Option.Name
			Option.Instance = OptionAsset

			table.insert(Window.Colorable, OptionAsset)
			table.insert(Dropdown.List,Option)
			Connect(OptionAsset.MouseButton1Click, function()
				SetOptionState(Option,not Option.Value)
			end)
			Connect(OptionAsset.Title:GetPropertyChangedSignal("TextBounds"), function()
				OptionAsset.Size = UDim2.new(1,0,0,OptionAsset.Title.TextBounds.Y + 2)
			end)
		end
		for Index, Option in pairs(Dropdown.List) do
			if Option.Value then
				SetOptionState(Option,Option.Value)
			end
		end
	end
	function Dropdown:RemoveOption(Name)
		for Index, Option in pairs(Dropdown.List) do
			if Option.Name == Name then
				Option.Instance:Destroy()
				Dropdown.List[Index] = nil
			end
		end
	end
	function Dropdown:Clear()
		for Index, Option in pairs(Dropdown.List) do
			Option.Instance:Destroy()
			Dropdown.List[Index] = nil
		end
	end
	function Dropdown:SetValue(Options)
		Options = type(Options) == "table" and Options or {}
		local wanted = {}
		for _, name in ipairs(Options) do wanted[name] = true end
		local selected = {}
		for _, option in pairs(Dropdown.List) do
			option.Value = wanted[option.Name] == true
			if option.Instance then
				option.Instance.BorderColor3 = option.Value and Window.Color or Color3.fromRGB(60,60,60)
			end
			if option.Value then selected[#selected + 1] = option.Name end
		end
		Dropdown.Value = selected
		Window.Flags[Dropdown.Flag] = Dropdown.Value
		DropdownAsset.Background.Value.Text = #selected > 0 and table.concat(selected, ", ") or "..."
		for _, option in pairs(Dropdown.List) do
			if option.Callback then option.Callback(Dropdown.Value, option) end
		end
	end

	function Dropdown:SetName(Name)
		Dropdown.Name = Name
		DropdownAsset.Title.Text = Name
	end
	function Dropdown:ToolTip(Text)
		InitToolTip(DropdownAsset,ScreenAsset,Text)
	end
	AttachVisibility(Dropdown, DropdownAsset)
    RegisterSearchEntry(Dropdown, Dropdown.Name, Dropdown._Section, Dropdown._Tab)
end
local function InitColorpicker(Parent,ScreenAsset,Window,Colorpicker)
	local ColorpickerAsset = GetAsset("Colorpicker/Colorpicker")
	local PaletteAsset = GetAsset("Colorpicker/Palette")
	ColorpickerAsset.Parent = Parent
	ColorpickerAsset.Title.Text = Colorpicker.Name
	PaletteAsset.Parent = ScreenAsset

	local PaletteRender = nil
	local SVRender = nil
	local HueRender = nil
	local AlphaRender = nil

	local function TableToColor(Table)
		if type(Table) ~= "table" then return Table end
		return Color3.fromHSV(Table[1],Table[2],Table[3])
	end
	local function FormatToString(Color)
		return math.round(Color.R * 255) .. "," .. math.round(Color.G * 255) .. "," .. math.round(Color.B * 255)
	end

	local function Update()
		Colorpicker.Value[6] = TableToColor(Colorpicker.Value)
		ColorpickerAsset.Color.BackgroundColor3 = Colorpicker.Value[6]
		PaletteAsset.SVPicker.BackgroundColor3 = Color3.fromHSV(Colorpicker.Value[1],1,1)
		PaletteAsset.SVPicker.Pin.Position = UDim2.new(Colorpicker.Value[2],0,1 - Colorpicker.Value[3],0)
		PaletteAsset.Hue.Pin.Position = UDim2.new(1 - Colorpicker.Value[1],0,0.5,0)

		PaletteAsset.Alpha.Pin.Position = UDim2.new(Colorpicker.Value[4],0,0.5,0)
		PaletteAsset.Alpha.Value.Text = Colorpicker.Value[4]
		PaletteAsset.Alpha.BackgroundColor3 = Colorpicker.Value[6]

		PaletteAsset.RGB.RGBBox.PlaceholderText = FormatToString(Colorpicker.Value[6])
		PaletteAsset.HEX.HEXBox.PlaceholderText = Colorpicker.Value[6]:ToHex()
		Window.Flags[Colorpicker.Flag] = Colorpicker.Value
		Colorpicker.Callback(Colorpicker.Value,Colorpicker.Value[6])
	end
    local function InitializeColorpickerVisual()
        Update()
        ColorpickerAsset.Color.Visible = true
    end
    Colorpicker._RefreshVisual = InitializeColorpickerVisual
	InitializeColorpickerVisual()
    task.defer(InitializeColorpickerVisual)

	Connect(ColorpickerAsset.Title:GetPropertyChangedSignal("TextBounds"), function()
		ColorpickerAsset.Size = UDim2.new(1,0,0,ColorpickerAsset.Title.TextBounds.Y)
	end)
	Connect(ColorpickerAsset.MouseButton1Click, function()
		if not PaletteAsset.Visible then
			PaletteAsset.Visible = true
			PaletteRender = Connect(RunService.RenderStepped, function()
				if not PaletteAsset.Visible then PaletteRender:Disconnect() end
				PaletteAsset.Position = UDim2.new(0,(ColorpickerAsset.Color.AbsolutePosition.X - PaletteAsset.AbsoluteSize.X) + 20,0,ColorpickerAsset.Color.AbsolutePosition.Y + 52)
			end)
		else
			PaletteRender:Disconnect()
			PaletteAsset.Visible = false
		end
	end)
	Connect(PaletteAsset.SVPicker.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if SVRender then
				SVRender:Disconnect()
			end
			SVRender = Connect(RunService.RenderStepped, function()
				if not PaletteAsset.Visible then SVRender:Disconnect() end
				local Mouse = UserInputService:GetMouseLocation()
				local ColorX = math.clamp(Mouse.X - PaletteAsset.SVPicker.AbsolutePosition.X,0,PaletteAsset.SVPicker.AbsoluteSize.X) / PaletteAsset.SVPicker.AbsoluteSize.X

				local ColorY = math.clamp(Mouse.Y - (PaletteAsset.SVPicker.AbsolutePosition.Y + 36),0,PaletteAsset.SVPicker.AbsoluteSize.Y) / PaletteAsset.SVPicker.AbsoluteSize.Y
				Colorpicker.Value[2] = ColorX
				Colorpicker.Value[3] = 1 - ColorY
				Update()
			end)
		end
	end)
	Connect(PaletteAsset.SVPicker.InputEnded, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if SVRender then
				SVRender:Disconnect()
			end
		end
	end)
	Connect(PaletteAsset.Hue.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if HueRender then
				HueRender:Disconnect()
			end
			HueRender = Connect(RunService.RenderStepped, function()
				if not PaletteAsset.Visible then HueRender:Disconnect() end
				local Mouse = UserInputService:GetMouseLocation()
				local ColorX = math.clamp(Mouse.X - PaletteAsset.Hue.AbsolutePosition.X,0,PaletteAsset.Hue.AbsoluteSize.X) / PaletteAsset.Hue.AbsoluteSize.X
				Colorpicker.Value[1] = 1 - ColorX
				Update()
			end)
		end
	end)
	Connect(PaletteAsset.Hue.InputEnded, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if HueRender then
				HueRender:Disconnect()
			end
		end
	end)
	Connect(PaletteAsset.Alpha.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if AlphaRender then
				AlphaRender:Disconnect()
			end
			AlphaRender = Connect(RunService.RenderStepped, function()
				if not PaletteAsset.Visible then AlphaRender:Disconnect() end
				local Mouse = UserInputService:GetMouseLocation()
				local ColorX = math.clamp(Mouse.X - PaletteAsset.Alpha.AbsolutePosition.X,0,PaletteAsset.Alpha.AbsoluteSize.X) / PaletteAsset.Alpha.AbsoluteSize.X
				Colorpicker.Value[4] = math.floor(ColorX * 10^2) / (10^2) -- idk %.2f little bit broken with this
				Update()
			end)
		end
	end)
	Connect(PaletteAsset.Alpha.InputEnded, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if AlphaRender then
				AlphaRender:Disconnect()
			end
		end
	end)

	function Colorpicker:SetName(Name)
		Colorpicker.Name = Name
		ColorpickerAsset.Title.Text = Name
	end
	function Colorpicker:SetCallback(Callback)
		Colorpicker.Callback = Callback
	end
	function Colorpicker:SetValue(HSVAR)
		Colorpicker.Value = HSVAR
		Update()
	end
	function Colorpicker:ToolTip(Text)
		InitToolTip(ColorpickerAsset,ScreenAsset,Text)
	end

	table.insert(Window.Colorable,PaletteAsset.Rainbow.Tick)
	PaletteAsset.Rainbow.Tick.BackgroundColor3 = Colorpicker.Value[5] and Window.Color or Color3.fromRGB(60,60,60)
	Connect(PaletteAsset.Rainbow.MouseButton1Click, function()
		Colorpicker.Value[5] = not Colorpicker.Value[5]
		PaletteAsset.Rainbow.Tick.BackgroundColor3 = Colorpicker.Value[5] and Window.Color or Color3.fromRGB(60,60,60)
	end)
	Connect(RunService.Heartbeat, function()
		if Colorpicker.Value[5] then
			if PaletteAsset.Visible then
				Colorpicker.Value[1] = Window.RainbowHue
				Update()
			else 
				Colorpicker.Value[1] = Window.RainbowHue
				Colorpicker.Value[6] = TableToColor(Colorpicker.Value)
				ColorpickerAsset.Color.BackgroundColor3 = Colorpicker.Value[6]
				Window.Flags[Colorpicker.Flag] = Colorpicker.Value
				Colorpicker.Callback(Colorpicker.Value,Colorpicker.Value[6])
			end
		end
	end)

	Connect(PaletteAsset.RGB.RGBBox.FocusLost, function(Enter)
		if not Enter then return end
		local ColorString = string.split(string.gsub(PaletteAsset.RGB.RGBBox.Text," ",""),",")
		local Hue,Saturation,Value = Color3.fromRGB(ColorString[1],ColorString[2],ColorString[3]):ToHSV()
		PaletteAsset.RGB.RGBBox.Text = ""
		Colorpicker.Value[1] = Hue
		Colorpicker.Value[2] = Saturation
		Colorpicker.Value[3] = Value
		Update()
	end)
	Connect(PaletteAsset.HEX.HEXBox.FocusLost, function(Enter)
		if not Enter then return end
		local Hue,Saturation,Value = Color3.fromHex("#" .. PaletteAsset.HEX.HEXBox.Text):ToHSV()
		PaletteAsset.RGB.RGBBox.Text = ""
		Colorpicker.Value[1] = Hue
		Colorpicker.Value[2] = Saturation
		Colorpicker.Value[3] = Value
		Update()
	end)
	AttachVisibility(Colorpicker, ColorpickerAsset)
    RegisterSearchEntry(Colorpicker, Colorpicker.Name, Colorpicker._Section, Colorpicker._Tab)
end

Bracket = InitScreen()
Bracket.Version = "3.2-skuff.5"
function Bracket:Window(Window)
	Window = GetType(Window,{},"table")
	Window.Name = GetType(Window.Name,"Window","string")
	Window.Color = GetType(Window.Color,Color3.new(1,0.5,0.25),"Color3")
	Window.Size = GetType(Window.Size,UDim2.new(0,496,0,496),"UDim2")
	Window.Position = GetType(Window.Position,UDim2.new(0.5,-248,0.5,-248),"UDim2")
	Window.Enabled = GetType(Window.Enabled,true,"boolean")

	Window.RainbowHue = 0
	Window.Colorable = {}
	Window.Elements = {}
	Window.Flags = {}
    Window.Tabs = {}

	local WindowAsset = InitWindow(Bracket.ScreenAsset,Window)
	Runtime.Windows[#Runtime.Windows + 1] = Window
	Window._Asset = WindowAsset
	function Window:Destroy()
		Bracket:Destroy()
	end
	function Window:Tab(Tab)
		Tab = GetType(Tab,{},"table")
		Tab.Name = GetType(Tab.Name,"Tab","string")
        Window.Tabs[#Window.Tabs + 1] = Tab
		local ChooseTab = InitTab(Bracket.ScreenAsset,WindowAsset,Window,Tab)

		function Tab:AddConfigSection(PFName,Side)
			local ConfigSection = Tab:Section({Name = "Config Manager",Side = Side}) do
				local ConfigList, ConfigDropdown = ConfigsToList(PFName), nil
				local function UpdateList(Name)
					ConfigDropdown:Clear()
					ConfigList = ConfigsToList(PFName)
					ConfigDropdown:BulkAdd(ConfigList)
					ConfigDropdown:SetValue({Name or (ConfigList[1] and ConfigList[1].Name) or nil})
				end

				ConfigSection:Textbox({Name = "Create",IgnoreFlag = true,
					AutoClear = true,Placeholder = "Name",Callback = function(Text)
						Window:SaveConfig(PFName,Text)
						UpdateList(Text)
					end})
				ConfigDropdown = ConfigSection:Dropdown({Name = "List",IgnoreFlag = true,
					List = ConfigList})
				ConfigSection:Button({Name = "Save",Callback = function()
					if ConfigDropdown.Value and ConfigDropdown.Value[1] then
						Window:SaveConfig(PFName,ConfigDropdown.Value[1])
					end
				end})
				ConfigSection:Button({Name = "Load",Callback = function()
					if ConfigDropdown.Value and ConfigDropdown.Value[1] then
						Window:LoadConfig(PFName,ConfigDropdown.Value[1])
					end
				end})
				ConfigSection:Button({Name = "Delete",Callback = function()
					if ConfigDropdown.Value and ConfigDropdown.Value[1] then
						Window:DeleteConfig(PFName,ConfigDropdown.Value[1])
						UpdateList()
					end
				end})

				local DefaultConfig = Window:GetDefaultConfig(PFName)
				local ConfigDivider = ConfigSection:Divider({Text = DefaultConfig
					and "Default Config\n<font color=\"rgb(189,189,189)\">[ "..DefaultConfig.." ]</font>"
					or "Default Config"})
				ConfigSection:Button({Name = "Set",Callback = function()
					if ConfigDropdown.Value and ConfigDropdown.Value[1] then
						DefaultConfig = ConfigDropdown.Value[1]
						writefile(PFName.."\\DefaultConfig.txt",DefaultConfig)
						ConfigDivider:SetText(
							"Default Config\n<font color=\"rgb(189,189,189)\">[ "..DefaultConfig.." ]</font>")
					end
				end})
				ConfigSection:Button({Name = "Clear",Callback = function()
					writefile(PFName.."\\DefaultConfig.txt","")
					ConfigDivider:SetText("Default Config")
				end})
			end
		end

		function Tab:Divider(Divider)
			Divider = GetType(Divider,{},"table")
			Divider.Text = GetType(Divider.Text,"","string")
            Divider._Tab = Tab
			InitDivider(ChooseTab(Divider.Side),Divider)
			return Divider
		end
		function Tab:Label(Label)
			Label = GetType(Label,{},"table")
			Label.Text = GetType(Label.Text,"Label","string")
            Label._Tab = Tab
			InitLabel(ChooseTab(Label.Side),Label)
			return Label
		end
		function Tab:Button(Button)
			Button = GetType(Button,{},"table")
			Button.Name = GetType(Button.Name,"Button","string")
			Button.Callback = GetType(Button.Callback,function() end,"function")
            Button._Tab = Tab
			InitButton(ChooseTab(Button.Side),Bracket.ScreenAsset,Window,Button)
			return Button
		end
		function Tab:Toggle(Toggle)
			Toggle = GetType(Toggle,{},"table")
			Toggle.Name = GetType(Toggle.Name,"Toggle","string")
			Toggle.Flag = GetType(Toggle.Flag,Toggle.Name,"string")

			Toggle.Value = GetType(Toggle.Value,false,"boolean")
			Toggle.Callback = GetType(Toggle.Callback,function() end,"function")
			Window.Elements[#Window.Elements + 1] = Toggle
			Window.Flags[Toggle.Flag] = Toggle.Value

            Toggle._Tab = Tab
			InitToggle(ChooseTab(Toggle.Side),Bracket.ScreenAsset,Window,Toggle)
			return Toggle
		end
		function Tab:Slider(Slider)
			Slider = GetType(Slider,{},"table")
			Slider.Name = GetType(Slider.Name,"Slider","string")
			Slider.Flag = GetType(Slider.Flag,Slider.Name,"string")

			Slider.Min = GetType(Slider.Min,0,"number")
			Slider.Max = GetType(Slider.Max,100,"number")
			Slider.Precise = GetType(Slider.Precise,0,"number")
			Slider.Unit = GetType(Slider.Unit,"","string")
			Slider.Value = GetType(Slider.Value,Slider.Max / 2,"number")
			Slider.Callback = GetType(Slider.Callback,function() end,"function")
			Window.Elements[#Window.Elements + 1] = Slider
			Window.Flags[Slider.Flag] = Slider.Value

            Slider._Tab = Tab
			InitSlider(ChooseTab(Slider.Side),Bracket.ScreenAsset,Window,Slider)
			return Slider
		end
		function Tab:Textbox(Textbox)
			Textbox = GetType(Textbox,{},"table")
			Textbox.Name = GetType(Textbox.Name,"Textbox","string")
			Textbox.Flag = GetType(Textbox.Flag,Textbox.Name,"string")

			Textbox.Value = GetType(Textbox.Value,"","string")
			Textbox.NumbersOnly = GetType(Textbox.NumbersOnly,false,"boolean")
			Textbox.Placeholder = GetType(Textbox.Placeholder,"Input here","string")
			Textbox.Callback = GetType(Textbox.Callback,function() end,"function")
			Window.Elements[#Window.Elements + 1] = Textbox
			Window.Flags[Textbox.Flag] = Textbox.Value

            Textbox._Tab = Tab
			InitTextbox(ChooseTab(Textbox.Side),Bracket.ScreenAsset,Window,Textbox)
			return Textbox
		end
		function Tab:Keybind(Keybind)
			Keybind = GetType(Keybind,{},"table")
			Keybind.Name = GetType(Keybind.Name,"Keybind","string")
			Keybind.Flag = GetType(Keybind.Flag,Keybind.Name,"string")

			Keybind.Value = GetType(Keybind.Value,"NONE","string")
			Keybind.Mouse = GetType(Keybind.Mouse,false,"boolean")
			Keybind.Callback = GetType(Keybind.Callback,function() end,"function")
			Keybind.Blacklist = GetType(Keybind.Blacklist,{"W","A","S","D","Slash","Tab","Backspace","Escape","Space","Delete","Unknown","Backquote"},"table")
			Window.Elements[#Window.Elements + 1] = Keybind
			Window.Flags[Keybind.Flag] = Keybind.Value

            Keybind._Tab = Tab
			InitKeybind(ChooseTab(Keybind.Side),Bracket.ScreenAsset,Window,Keybind)
			return Keybind
		end
		function Tab:Dropdown(Dropdown)
			Dropdown = GetType(Dropdown,{},"table")
			Dropdown.Name = GetType(Dropdown.Name,"Dropdown","string")
			Dropdown.Flag = GetType(Dropdown.Flag,Dropdown.Name,"string")
			Dropdown.List = GetType(Dropdown.List,{},"table")
			Window.Elements[#Window.Elements + 1] = Dropdown
			Window.Flags[Dropdown.Flag] = Dropdown.Value

            Dropdown._Tab = Tab
			InitDropdown(ChooseTab(Dropdown.Side),Bracket.ScreenAsset,Window,Dropdown)
			return Dropdown
		end
		function Tab:Colorpicker(Colorpicker)
			Colorpicker = GetType(Colorpicker,{},"table")
			Colorpicker.Name = GetType(Colorpicker.Name,"Colorpicker","string")
			Colorpicker.Flag = GetType(Colorpicker.Flag,Colorpicker.Name,"string")

			Colorpicker.Value = GetType(Colorpicker.Value,{1,1,1,0,false},"table")
			Colorpicker.Callback = GetType(Colorpicker.Callback,function() end,"function")
			Window.Elements[#Window.Elements + 1] = Colorpicker
			Window.Flags[Colorpicker.Flag] = Colorpicker.Value

            Colorpicker._Tab = Tab
			InitColorpicker(ChooseTab(Colorpicker.Side),Bracket.ScreenAsset,Window,Colorpicker)
			return Colorpicker
		end
		function Tab:Section(Section)
			Section = GetType(Section,{},"table")
			Section.Name = GetType(Section.Name,"Section","string")
            Section._Tab = Tab
			local SectionContainer, SectionAsset = InitSection(ChooseTab(Section.Side),Section)
            RegisterSearchEntry(Section, Section.Name, Section, Tab)

			function Section:Divider(Divider)
				Divider = GetType(Divider,{},"table")
				Divider.Text = GetType(Divider.Text,"","string")
				InitDivider(SectionContainer,Divider)
				return Divider
			end
			function Section:Label(Label)
				Label = GetType(Label,{},"table")
				Label.Text = GetType(Label.Text,"Label","string")
				InitLabel(SectionContainer,Label)
				return Label
			end
			function Section:Button(Button)
				Button = GetType(Button,{},"table")
				Button.Name = GetType(Button.Name,"Button","string")
				Button.Callback = GetType(Button.Callback,function() end,"function")
				InitButton(SectionContainer,Bracket.ScreenAsset,Window,Button)
				return Button
			end
			function Section:Toggle(Toggle)
				Toggle = GetType(Toggle,{},"table")
				Toggle.Name = GetType(Toggle.Name,"Toggle","string")
				Toggle.Flag = GetType(Toggle.Flag,Toggle.Name,"string")

				Toggle.Value = GetType(Toggle.Value,false,"boolean")
				Toggle.Callback = GetType(Toggle.Callback,function() end,"function")
				Window.Elements[#Window.Elements + 1] = Toggle
				Window.Flags[Toggle.Flag] = Toggle.Value

				InitToggle(SectionContainer,Bracket.ScreenAsset,Window,Toggle)
				return Toggle
			end
			function Section:Slider(Slider)
				Slider = GetType(Slider,{},"table")
				Slider.Name = GetType(Slider.Name,"Slider","string")
				Slider.Flag = GetType(Slider.Flag,Slider.Name,"string")

				Slider.Min = GetType(Slider.Min,0,"number")
				Slider.Max = GetType(Slider.Max,100,"number")
				Slider.Precise = GetType(Slider.Precise,0,"number")
				Slider.Unit = GetType(Slider.Unit,"","string")
				Slider.Value = GetType(Slider.Value,Slider.Max / 2,"number")
				Slider.Callback = GetType(Slider.Callback,function() end,"function")
				Window.Elements[#Window.Elements + 1] = Slider
				Window.Flags[Slider.Flag] = Slider.Value

				InitSlider(SectionContainer,Bracket.ScreenAsset,Window,Slider)
				return Slider
			end
			function Section:Textbox(Textbox)
				Textbox = GetType(Textbox,{},"table")
				Textbox.Name = GetType(Textbox.Name,"Textbox","string")
				Textbox.Flag = GetType(Textbox.Flag,Textbox.Name,"string")

				Textbox.Value = GetType(Textbox.Value,"","string")
				Textbox.NumbersOnly = GetType(Textbox.NumbersOnly,false,"boolean")
				Textbox.Placeholder = GetType(Textbox.Placeholder,"Input here","string")
				Textbox.Callback = GetType(Textbox.Callback,function() end,"function")
				Window.Elements[#Window.Elements + 1] = Textbox
				Window.Flags[Textbox.Flag] = Textbox.Value

				InitTextbox(SectionContainer,Bracket.ScreenAsset,Window,Textbox)
				return Textbox
			end
			function Section:Keybind(Keybind)
				Keybind = GetType(Keybind,{},"table")
				Keybind.Name = GetType(Keybind.Name,"Keybind","string")
				Keybind.Flag = GetType(Keybind.Flag,Keybind.Name,"string")

				Keybind.Value = GetType(Keybind.Value,"NONE","string")
				Keybind.Mouse = GetType(Keybind.Mouse,false,"boolean")
				Keybind.Callback = GetType(Keybind.Callback,function() end,"function")
				Keybind.Blacklist = GetType(Keybind.Blacklist,{"W","A","S","D","Slash","Tab","Backspace","Escape","Space","Delete","Unknown","Backquote"},"table")
				Window.Elements[#Window.Elements + 1] = Keybind
				Window.Flags[Keybind.Flag] = Keybind.Value

				InitKeybind(SectionContainer,Bracket.ScreenAsset,Window,Keybind)
				return Keybind
			end
			function Section:Dropdown(Dropdown)
				Dropdown = GetType(Dropdown,{},"table")
				Dropdown.Name = GetType(Dropdown.Name,"Dropdown","string")
				Dropdown.Flag = GetType(Dropdown.Flag,Dropdown.Name,"string")
				Dropdown.List = GetType(Dropdown.List,{},"table")
				Window.Elements[#Window.Elements + 1] = Dropdown
				Window.Flags[Dropdown.Flag] = Dropdown.Value

				InitDropdown(SectionContainer,Bracket.ScreenAsset,Window,Dropdown)
				return Dropdown
			end
			function Section:Colorpicker(Colorpicker)
				Colorpicker = GetType(Colorpicker,{},"table")
				Colorpicker.Name = GetType(Colorpicker.Name,"Colorpicker","string")
				Colorpicker.Flag = GetType(Colorpicker.Flag,Colorpicker.Name,"string")

				Colorpicker.Value = GetType(Colorpicker.Value,{1,1,1,0,false},"table")
				Colorpicker.Callback = GetType(Colorpicker.Callback,function() end,"function")
				Window.Elements[#Window.Elements + 1] = Colorpicker
				Window.Flags[Colorpicker.Flag] = Colorpicker.Value

				InitColorpicker(SectionContainer,Bracket.ScreenAsset,Window,Colorpicker)
				return Colorpicker
			end
			return Section
		end
		return Tab
	end
	return Window
end

function Bracket:Confirm(options)
    options = type(options) == "table" and options or {}
    if Runtime.Destroyed or not Bracket.ScreenAsset or not Bracket.ScreenAsset.Parent then return end
    if Runtime.ConfirmDialog and Runtime.ConfirmDialog.Parent then Runtime.ConfirmDialog:Destroy() end
    local overlay = Instance.new("Frame")
    overlay.Name = "BracketConfirmDialog"
    overlay.BackgroundColor3 = Color3.fromRGB(0,0,0)
    overlay.BackgroundTransparency = 0.25
    overlay.Size = UDim2.fromScale(1,1)
    overlay.ZIndex = 200
    overlay.Parent = Bracket.ScreenAsset
    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5,0.5)
    frame.Position = UDim2.fromScale(0.5,0.5)
    frame.Size = UDim2.fromOffset(390,150)
    frame.BackgroundColor3 = Color3.fromRGB(18,18,18)
    frame.BorderColor3 = Color3.fromRGB(255,128,64)
    frame.ZIndex = 201
    frame.Parent = overlay
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(12,10)
    title.Size = UDim2.new(1,-24,0,24)
    title.Font = Enum.Font.Code
    title.TextSize = 15
    title.TextColor3 = Color3.new(1,1,1)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = tostring(options.Title or "Confirm")
    title.ZIndex = 202
    title.Parent = frame
    local description = Instance.new("TextLabel")
    description.BackgroundTransparency = 1
    description.Position = UDim2.fromOffset(12,38)
    description.Size = UDim2.new(1,-24,0,58)
    description.Font = Enum.Font.Code
    description.TextSize = 13
    description.TextWrapped = true
    description.TextColor3 = Color3.fromRGB(220,220,220)
    description.Text = tostring(options.Description or "Continue?")
    description.ZIndex = 202
    description.Parent = frame
    local function button(text, x, callback)
        local b = Instance.new("TextButton")
        b.Position = UDim2.new(x, x == 0 and 12 or -152, 1, -42)
        b.Size = UDim2.fromOffset(140,30)
        b.BackgroundColor3 = Color3.fromRGB(45,45,45)
        b.BorderColor3 = Color3.fromRGB(90,90,90)
        b.Font = Enum.Font.Code
        b.TextSize = 13
        b.TextColor3 = Color3.new(1,1,1)
        b.Text = text
        b.ZIndex = 202
        b.Parent = frame
        Connect(b.MouseButton1Click, function()
            if overlay.Parent then overlay:Destroy() end
            Runtime.ConfirmDialog = nil
            if callback then callback() end
        end)
    end
    button(tostring(options.CancelText or "Cancel"), 0, options.OnCancel)
    button(tostring(options.ConfirmText or "Confirm"), 1, options.OnConfirm)
    Runtime.ConfirmDialog = overlay
end

function Bracket:Destroy()
	if Runtime.Destroyed then return end
	Runtime.Destroyed = true
	Runtime.Generation = Runtime.Generation + 1
	for _, connection in ipairs(Runtime.Connections) do
		DisconnectConnection(connection)
	end
	Runtime.Connections = {}
	for _, screen in ipairs(Runtime.Screens) do
		if screen and screen.Parent then
			pcall(function() screen:Destroy() end)
		end
	end
	Runtime.Screens = {}
	Runtime.Windows = {}
	Runtime.HiddenContainer = nil
	Runtime.RefreshByInstance = setmetatable({}, {__mode = "k"})
    Runtime.SearchEntries = {}
    Runtime.Sections = {}
    Runtime.BindRegistry = {}
    Runtime.SearchQuery = ""
    Runtime.ConfirmDialog = nil
	pcall(function() RunService:SetRobloxGuiFocused(false) end)
end

function Bracket:RefreshAllLayouts()
	for instance, refresh in pairs(Runtime.RefreshByInstance) do
		if instance and instance.Parent and refresh then refresh() end
	end
end

function Bracket:TableToColor(Table)
	if type(Table) ~= "table" then return Table end
	return Color3.fromHSV(Table[1],Table[2],Table[3])
end

function Bracket:Notification(Notification)
	if Runtime.Destroyed or not Bracket.ScreenAsset or not Bracket.ScreenAsset.Parent then return end
	Notification = GetType(Notification,{},"table")
	Notification.Title = GetType(Notification.Title,"Title","string")
	Notification.Description = GetType(Notification.Description,"Description","string")

	local NotificationAsset = GetAsset("Notification/ND")
	NotificationAsset.Parent = Bracket.ScreenAsset.NDHandle
	NotificationAsset.Title.Text = Notification.Title
	NotificationAsset.Description.Text = Notification.Description
	NotificationAsset.Title.Size = UDim2.new(1,0,0,NotificationAsset.Title.TextBounds.Y)
	NotificationAsset.Description.Size = UDim2.new(1,0,0,NotificationAsset.Description.TextBounds.Y)
	NotificationAsset.Size = UDim2.new(
		0,GetLongest(
			NotificationAsset.Title.TextBounds.X,
			NotificationAsset.Description.TextBounds.X
		) + 24,
		0,NotificationAsset.ListLayout.AbsoluteContentSize.Y + 8
	)

	if Notification.Duration then
		task.spawn(function()
			for Time = Notification.Duration,1,-1 do
				if Runtime.Destroyed or not NotificationAsset.Parent then return end
				NotificationAsset.Title.Close.Text = Time
				task.wait(1)
			end
			NotificationAsset.Title.Close.Text = 0

			if Notification.Callback then
				Notification.Callback()
			end
			NotificationAsset:Destroy()
		end)
	else
		Connect(NotificationAsset.Title.Close.MouseButton1Click, function()
			NotificationAsset:Destroy()
		end)
	end
end

function Bracket:Notification2(Notification)
	if Runtime.Destroyed or not Bracket.ScreenAsset or not Bracket.ScreenAsset.Parent then return end
	Notification = GetType(Notification,{},"table")
	Notification.Title = GetType(Notification.Title,"Title","string")
	Notification.Duration = GetType(Notification.Duration,5,"number")
	Notification.Color = GetType(Notification.Color,Color3.new(1,0.5,0.25),"Color3")

	local NotificationAsset = GetAsset("Notification/NL")
	NotificationAsset.Parent = Bracket.ScreenAsset.NLHandle
	NotificationAsset.Main.Title.Text = Notification.Title
	NotificationAsset.Main.GLine.BackgroundColor3 = Notification.Color
	NotificationAsset.Main.Size = UDim2.new(
		0,NotificationAsset.Main.Title.TextBounds.X + 10,
		0,NotificationAsset.Main.Title.TextBounds.Y + 6
	)
	NotificationAsset.Size = UDim2.new(
		0,0,0,NotificationAsset.Main.Size.Y.Offset + 4
	)

	local function TweenSize(X,Y,Callback)
		NotificationAsset:TweenSize(
			UDim2.new(0,X,0,Y),
			Enum.EasingDirection.InOut,
			Enum.EasingStyle.Linear,
			0.25,false,Callback
		)
	end

	TweenSize(NotificationAsset.Main.Size.X.Offset + 4,
	NotificationAsset.Main.Size.Y.Offset + 4,function()
		task.wait(Notification.Duration)
		if Runtime.Destroyed or not NotificationAsset.Parent then return end
		TweenSize(0,
		NotificationAsset.Main.Size.Y.Offset + 4,function()
			if Notification.Callback then
				Notification.Callback()
			end NotificationAsset:Destroy()
		end)
	end)
end

return Bracket
