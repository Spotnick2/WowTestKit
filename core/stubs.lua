-- core/stubs.lua: the mechanics of a WoW: Forever mock for Lua 5.1 tests,
-- driven through the WoW table. Lifted from GlassChat's and GlassPearls'
-- tests/wow_stubs.lua (themselves GlassMail's, GlassPanel's, GlassRaidFrames').
--
-- What it models, on purpose:
-- - STRICT globals (Kit.strict, called last by the consumer's stub): reading
--   any global nobody defined is an error. The stubs are an allowlist of APIs
--   verified present on the client; defining one Forever lacks is how a
--   missing API survives into a build.
-- - SECRETS as newproxy userdata: arithmetic, ordering, tostring, concat and
--   string.format on one throw. Lua 5.1 cannot make a truth test or == throw,
--   so those two misuses are NOT caught here (only in game / in review).
-- - EVENT names: RegisterEvent throws on a name the selected build doesn't
--   declare (data/forever-<build>/events.txt).
-- - METHOD calls: every widget method called is recorded as "Type:Method"
--   (WoW.methodsCalled); Kit.checkMethods checks each pair against the build.
--
-- What it does NOT hold: any client API beyond these mechanics (C_* tables,
-- unit, chat, bag functions...). Those stay in the consumer's own stub, each
-- verified in the dump. Every WoW.Methods entry here can be replaced there:
-- methods are looked up at call time.

WoW = {}
WoW.BUILD = Kit.BUILD

--------------------------------------------------------------------------------
-- Secrets
--------------------------------------------------------------------------------

local secrets = setmetatable({}, { __mode = "k" })
WoW.secrets = secrets   -- weak; for a consumer's own secret-aware stubs

function WoW.Secret(label)
    local p = newproxy(true)
    local mt = getmetatable(p)
    local function boom() error("secret value touched in Lua: " .. label, 2) end
    for _, k in ipairs({ "__tostring", "__concat", "__add", "__sub", "__mul", "__div", "__mod",
                         "__pow", "__unm", "__lt", "__le", "__len", "__index", "__newindex", "__call" }) do
        mt[k] = boom
    end
    secrets[p] = label
    return p
end

function issecretvalue(v) return secrets[v] ~= nil end

-- Mark an existing value secret for issecretvalue. The client's secrets keep
-- their type (a secret string is still type "string"), which a proxy can't
-- model; use this to reach `type(x) == "string"` branches. Returns v.
function WoW.MarkSecret(v, label) secrets[v] = label or "marked"; return v end

--------------------------------------------------------------------------------
-- Known events: the selected build's
--------------------------------------------------------------------------------

WoW.KNOWN_EVENTS = Kit.data("events")

--------------------------------------------------------------------------------
-- State. WoW.reset() clears the core's, then runs each WoW.onReset function
-- (a consumer adds its own state there).
--------------------------------------------------------------------------------

WoW.onReset = {}
function WoW.reset()
    WoW.frames = {}
    WoW.chat = {}
    WoW.methodsCalled = {}
    WoW.combat = false
    WoW.timers = {}
    WoW.blocked = {}
    for _, fn in ipairs(WoW.onReset) do fn() end
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Methods = {}   -- implementations by method name, looked up at call time
WoW.Methods = Methods

local function record(w, name)
    WoW.methodsCalled[w._type .. ":" .. name] = true
end

-- Any capitalised key is a method: recorded, then its implementation if one
-- exists, else nil. Lower-case keys are fields and read as nil.
local widgetMT = {
    __index = function(w, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end
        return function(self, ...)
            record(self, k)
            local impl = Methods[k]
            if impl then return impl(self, ...) end
            return nil
        end
    end,
}

local function newWidget(wtype, parent, name)
    return setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                          _scripts = {}, _events = {},
                          _level = parent and parent._level and (parent._level + 1) or 1,
                          _width = 0, _height = 0, _name = name }, widgetMT)
end
WoW.newWidget = newWidget

-- Templates: WoW.templates[name](frame) builds what that template adds
-- (parentKey children, scripts, _protected). A comma-separated list runs each
-- in order. Unknown templates add nothing.
WoW.templates = {}

function CreateFrame(ftype, name, parent, template)
    local w = newWidget(ftype, parent, name)
    w._template = template
    w._frame = true   -- a frame, not a region (SetParent moves it between children)
    if ftype == "StatusBar" then w._min, w._max, w._value = 0, 1, 0 end
    if template then
        for t in template:gmatch("[^,%s]+") do
            local build = WoW.templates[t]
            if build then build(w, t) end
        end
    end
    table.insert(WoW.frames, w)
    if parent then
        parent._children = parent._children or {}
        table.insert(parent._children, w)
    end
    if name then rawset(_G, name, w) end
    return w
end

-- A protected frame (w._protected, set by a secure template) refuses to show,
-- hide or move in combat, as the client does: nothing happens and the call is
-- recorded in WoW.blocked (porting guide, "Secure click-casting works").
local function refused(w, what)
    if WoW.combat and w._protected then
        table.insert(WoW.blocked, (w._name or w._type) .. ":" .. what)
        return true
    end
end
WoW.refused = refused

-- Visibility follows the parent's (WowTestKit #21). OnShow / OnHide fire on
-- the frame and on each shown descendant whose visibility changed, parents
-- first, and only on a change: Show on a shown frame fires nothing, and a
-- frame shown under a hidden ancestor gets OnShow when that ancestor shows.
-- The walk follows CreateFrame's children (w._children, kept by SetParent).
local function visible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end
local function fireDown(w, script)
    if w._scripts[script] then w._scripts[script](w) end
    for _, c in ipairs(w._children or {}) do
        if c._shown then fireDown(c, script) end
    end
end
-- Show or hide w with its scripts, without the combat refusal: what Show and
-- Hide do once allowed, and what secure code calls (a snippet's handle).
function WoW.setShown(w, shown)
    shown = shown and true or false
    local was = visible(w)
    w._shown = shown
    local now = visible(w)
    if now and not was then fireDown(w, "OnShow")
    elseif was and not now then fireDown(w, "OnHide") end
end
function Methods.Show(w)
    if refused(w, "Show") then return end
    WoW.setShown(w, true)
end
function Methods.Hide(w)
    if refused(w, "Hide") then return end
    WoW.setShown(w, false)
end
function Methods.SetShown(w, v) if v then Methods.Show(w) else Methods.Hide(w) end end
function Methods.IsShown(w) return w._shown end
function Methods.IsVisible(w) return visible(w) end
function Methods.SetPoint(w, ...)
    if refused(w, "SetPoint") then return end
    table.insert(w._points, { ... })
end
function Methods.ClearAllPoints(w)
    if refused(w, "ClearAllPoints") then return end
    w._points = {}
end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Methods.SetAllPoints(w, rel)
    if refused(w, "SetAllPoints") then return end   -- a re-anchor, like SetPoint
    table.insert(w._points, { "ALL", rel })
end
function Methods.SetSize(w, x, y) w._width, w._height = x, y end
function Methods.SetWidth(w, x) w._width = x end
function Methods.SetHeight(w, y) w._height = y end
function Methods.GetWidth(w) return w._width end
function Methods.GetHeight(w) return w._height end
-- A texture painted with SetGradient ignores a later SetAlpha (measured on
-- 70374, porting guide section 3, GlassChat #95): GetAlpha still reads what it
-- read before. Modelled, so a test of a gradient's alpha can't pass against it.
function Methods.SetAlpha(w, a) if not w._gradient then w._alpha = a end end
function Methods.GetAlpha(w) return w._alpha or 1 end
function Methods.GetParent(w) return w._parent end
-- Reparenting moves the frame between its parents' children, so GetChildren
-- and the OnShow / OnHide walk follow it. (Its OnShow / OnHide on a
-- visibility change by reparenting isn't modelled.)
local function moveIn(list, w, to)
    if list then
        for i, c in ipairs(list) do
            if c == w then table.remove(list, i); break end
        end
    end
    if to then table.insert(to, w) end
end
function Methods.SetParent(w, p)
    local old = w._parent
    if old == p then return end
    w._parent = p
    if w._frame then
        -- A frame CreateFrame made: in its parent's children.
        if p then p._children = p._children or {} end
        moveIn(old and old._children, w, p and p._children)
    elseif old and old._regions then
        -- A texture or font string: in its parent's regions.
        if p then p._regions = p._regions or {} end
        moveIn(old._regions, w, p and p._regions)
    end
end
function Methods.GetChildren(w) return unpack(w._children or {}) end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.SetFrameStrata(w, s) w._strata = s end
function Methods.GetFrameStrata(w) return w._strata or "MEDIUM" end
function Methods.EnableMouse(w, v) w._mouse = v end
function Methods.IsMouseEnabled(w) return w._mouse == true end
function Methods.SetMouseClickEnabled(w, on) w._clicks = on == true end
function Methods.SetMouseMotionEnabled(w, on) w._motion = on == true end
function Methods.GetName(w) return w._name end
function Methods.GetDebugName(w) return w._name or ("<" .. w._type .. ">") end
function Methods.GetObjectType(w) return w._type end
function Methods.IsForbidden(w) return false end

-- Attributes: recorded; refused on a protected frame in combat, as the client does.
function Methods.SetAttribute(w, k, v)
    if WoW.combat and w._protected then return end
    w._attrs = w._attrs or {}
    w._attrs[k] = v
end
function Methods.GetAttribute(w, k) return w._attrs and w._attrs[k] end

-- Scripts and events.
function Methods.SetScript(w, name, fn) w._scripts[name] = fn end
function Methods.GetScript(w, name) return w._scripts[name] end
function Methods.HookScript(w, name, fn)
    local old = w._scripts[name]
    w._scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. tostring(e) .. "\"", 2) end
    w._events[e] = true
    return true
end
function Methods.UnregisterEvent(w, e) w._events[e] = nil end
function Methods.UnregisterAllEvents(w) w._events = {} end
function Methods.IsEventRegistered(w, e) return w._events[e] == true end

-- Regions: in creation order for GetRegions (w._regions), as the client lists
-- a frame's textures and font strings; a named one is also a global.
local function addRegion(w, r)
    w._regions = w._regions or {}
    table.insert(w._regions, r)
    return r
end
WoW.addRegion = addRegion   -- for a consumer's own region makers (CreateLine)
function Methods.CreateTexture(w, name, layer, template, sublevel)
    local t = addRegion(w, newWidget("Texture", w, name))
    t._layer, t._sublevel = layer, sublevel
    if name then rawset(_G, name, t) end
    return t
end
function Methods.CreateFontString(w, name)
    local fs = addRegion(w, newWidget("FontString", w, name))
    if name then rawset(_G, name, fs) end
    return fs
end
function Methods.CreateMaskTexture(w) return newWidget("MaskTexture", w) end
function Methods.GetRegions(w) return unpack(w._regions or {}) end

-- Textures: one source at a time, as on the client (a file, an atlas or a colour).
function Methods.SetTexture(t, file) t._file, t._atlas, t._color = file, nil, nil; return true end
-- No return value (the dump declares none): ask C_Texture.GetAtlasInfo first.
function Methods.SetAtlas(t, name) t._atlas, t._file, t._color = name, nil, nil end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a }; t._file, t._atlas = nil, nil end
function Methods.SetBlendMode(t, mode) t._blend = mode end
function Methods.SetVertexColor(t, r, g, b, a) t._vertex = { r, g, b, a } end
function Methods.SetDesaturated(t, on) t._desaturated = on == true end
function Methods.SetGradient(t, orientation, c1, c2) t._gradient = { orientation, c1, c2 } end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end

-- Text. An EditBox runs its OnTextChanged on SetText, as the client does.
function Methods.SetText(fs, text)
    fs._text = text
    if fs._type == "EditBox" and fs._scripts.OnTextChanged then fs._scripts.OnTextChanged(fs, false) end
end
function Methods.GetText(fs) return fs._text end
-- The client formats natively and accepts secrets: with any secret argument,
-- the arguments are kept unformatted instead of calling string.format (which
-- would throw on the proxy).
function Methods.SetFormattedText(fs, fmt, ...)
    local n = select("#", ...)
    for i = 1, n do
        if secrets[(select(i, ...))] then fs._text = { secretFormat = fmt, n = n }; return end
    end
    fs._text = string.format(fmt, ...)
end
function Methods.SetFont(fs, file, size, flags) fs._font = { file, size, flags }; return true end
function Methods.GetFont(fs)
    local f = fs._font or { "Fonts\\FRIZQT__.TTF", 10, "" }
    return f[1], f[2], f[3]
end
function Methods.SetFontObject(fs, obj) fs._fontObject = obj end
function Methods.GetFontObject(fs) return fs._fontObject end
-- A SimpleHTML colours per text type ("P", "H1", ...), its first argument.
function Methods.SetTextColor(fs, ...)
    if fs._type == "SimpleHTML" then
        local textType, r, g, b, a = ...
        assert(type(textType) == "string", "SimpleHTML:SetTextColor needs a text type first")
        fs._htmlColor = fs._htmlColor or {}
        fs._htmlColor[textType] = { r, g, b, a }
        return
    end
    local r, g, b, a = ...
    fs._textColor = { r, g, b, a }
end
function Methods.GetTextColor(fs, textType)
    local c
    if fs._type == "SimpleHTML" then
        assert(type(textType) == "string", "SimpleHTML:GetTextColor needs a text type")
        c = fs._htmlColor and fs._htmlColor[textType]
    else
        c = fs._textColor
    end
    c = c or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end

-- Buttons: enabled until told otherwise.
function Methods.Enable(b) b._disabled = false end
function Methods.Disable(b) b._disabled = true end
function Methods.SetEnabled(b, v) b._disabled = not v end
function Methods.IsEnabled(b) return not b._disabled end
-- CheckButton.
function Methods.SetChecked(b, v) b._checked = v and true or false end
function Methods.GetChecked(b) return b._checked == true end
-- StatusBar and Slider. A slider's SetValue fires OnValueChanged on a change,
-- as the client's does.
function Methods.SetMinMaxValues(b, lo, hi) b._min, b._max = lo, hi end
function Methods.GetValue(b) return b._value end
function Methods.SetValue(b, v)
    local old = b._value
    b._value = v
    if b._type == "Slider" and v ~= old and b._scripts.OnValueChanged then b._scripts.OnValueChanged(b, v, false) end
end
function Methods.SetStatusBarColor(b, r, g, bl, a) b._color = { r, g, bl, a } end
function Methods.SetStatusBarTexture(b, file)
    b._fill = b._fill or newWidget("Texture", b)
    b._fill._file = file
    return true
end
function Methods.GetStatusBarTexture(b) return b._fill end
-- Animations: groups record whether they play.
function Methods.CreateAnimationGroup(w) return newWidget("AnimationGroup", w) end
function Methods.CreateAnimation(ag, atype) return newWidget(atype or "Animation", ag) end
function Methods.Play(ag) ag._playing = true end
function Methods.Stop(ag) ag._playing = false end
function Methods.IsPlaying(ag) return ag._playing == true end

--------------------------------------------------------------------------------
-- Globals the mechanics need (each in the dump's _G walk; UIParent is
-- FrameXML's, and a widget type of its own in the dump)
--------------------------------------------------------------------------------

UIParent = newWidget("Frame", nil, "UIParent")
UIParent._level = 0

-- A "|" the client would misread (GlassChat #55): it reads "|x" as an escape
-- and drops it ("off|watch|hide" showed as "offatchide", "|n" is a newline).
-- Only well-formed escapes are taken out: "||", colour pairs (|cAARRGGBB or
-- |cn...: up to |r), links (|H...|h...|h), textures, atlases and |K names.
-- Any "|" left is stray.
function WoW.StrayPipe(line)
    local s = line:gsub("||", "")
    s = s:gsub("|H[^|]*|h(.-)|h", "%1"):gsub("|T[^|]*|t", ""):gsub("|A[^|]*|a", ""):gsub("|K[^|]*|k", "?")
    local n
    repeat
        s, n = s:gsub("|c%x%x%x%x%x%x%x%x([^|]-)|r", "%1")
        local m
        s, m = s:gsub("|cn[^:|]*:([^|]-)|r", "%1")
        n = n + m
    until n == 0
    return s:find("|", 1, true) ~= nil
end
WoW.strays = {}

-- Every printed line goes to WoW.chat, and is checked for a stray "|"
-- (done() fails on one).
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    if WoW.StrayPipe(line) then WoW.strays[#WoW.strays + 1] = line end
    table.insert(WoW.chat, line)
end

function GetTime() return WoW.now or 0 end
function InCombatLockdown() return WoW.combat == true end
-- Client string alias (in the dump's _G walk); LibStub's version check uses it.
strmatch = string.match

-- The client's secure hook replaces t[name] with a wrapper: the sanctioned way
-- to hook a Blizzard function. WoW.hooked[t][name] counts the hooks, so a
-- "no field written" check can tell a hook from a field the addon wrote.
WoW.hooked = {}
local function pack(...) return { n = select("#", ...), ... } end
function hooksecurefunc(t, name, fn)
    if type(t) == "string" then t, name, fn = _G, t, name end
    WoW.hooked[t] = WoW.hooked[t] or {}
    WoW.hooked[t][name] = (WoW.hooked[t][name] or 0) + 1
    local orig = rawget(t, name) or t[name]
    rawset(t, name, function(...)
        local r = pack(orig(...))   -- n keeps trailing nils
        fn(...)
        return unpack(r, 1, r.n)
    end)
end

-- Timers. Two ways to run them:
-- - WoW.flushTimers(upTo): those whose delay is within upTo seconds (all when
--   nil), keeping the rest;
-- - WoW.advance(dt): a clock. WoW.now moves on by dt and the timers due by
--   then run in the order they fall due; a timer scheduled inside one counts
--   from the new now, so step a second at a time.
-- A ticker is recorded once, like a timer (it doesn't repeat here).
C_Timer = {}
function C_Timer.After(s, fn) table.insert(WoW.timers, { s = s, fn = fn, at = (WoW.now or 0) + s }) end
function C_Timer.NewTicker(s, fn)
    local t = { s = s, fn = fn, every = s, at = (WoW.now or 0) + s }
    table.insert(WoW.timers, t)
    return { Cancel = function() t.cancelled = true end }
end
function WoW.flushTimers(upTo)
    local run, keep = {}, {}
    for _, t in ipairs(WoW.timers) do
        if upTo == nil or t.s <= upTo then run[#run + 1] = t else keep[#keep + 1] = t end
    end
    WoW.timers = keep
    for _, t in ipairs(run) do if not t.cancelled then t.fn() end end
end
function WoW.advance(dt)
    WoW.now = (WoW.now or 0) + dt
    while true do
        local due, at
        for i, t in ipairs(WoW.timers) do
            local tAt = t.at or t.s or 0
            if tAt <= WoW.now and (not at or tAt < at) then due, at = i, tAt end
        end
        if not due then return end
        local t = table.remove(WoW.timers, due)
        if not t.cancelled then t.fn() end   -- a cancelled ticker never fires
    end
end

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- Fire an event at every frame registered for it. Errors are NOT caught: a
-- handler that throws fails the test.
function WoW.fire(event, ...)
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler and w._events[event] then handler(w, event, ...) end
    end
end

-- Every event any frame registered, fired once with no payload: strict
-- globals only catch code that actually runs.
function WoW.fireAllRegistered()
    local seen = {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do seen[e] = true end
    end
    local list = {}
    for e in pairs(seen) do list[#list + 1] = e end
    table.sort(list)   -- the same order on every run
    for _, e in ipairs(list) do WoW.fire(e) end
end

-- One rendered frame: OnUpdate on every visible frame.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

WoW.reset()

--------------------------------------------------------------------------------
-- Strict globals, installed by the consumer's stub as its last line
--------------------------------------------------------------------------------

-- The client globals this core defines, for the kit's own check that each is
-- in the build's globals list. FrameXML names (not in a function list) are
-- listed apart, each with where it comes from.
Kit.CORE_GLOBALS = { "CreateFrame", "issecretvalue", "print", "GetTime", "InCombatLockdown",
                     "strmatch", "hooksecurefunc", "C_Timer" }
Kit.CORE_FRAMEXML = { UIParent = "FrameXML UIParent.xml; a widget type of its own in the dump" }

-- allowNil: the names that may read as nil (the addon's own globals before
-- they're assigned, its SavedVariables, LibStub before a library creates it).
-- Any other read of an undefined global is an error.
-- It also forgets the method calls the stubs made while being built (a
-- prebuilt Blizzard frame's SetSize...): Kit.checkMethods then sees only what
-- the test made the addon call, and "nothing recorded" can fail.
function Kit.strict(allowNil)
    allowNil = allowNil or {}
    WoW.methodsCalled = {}
    setmetatable(_G, { __index = function(_, k)
        if allowNil[k] then return nil end
        error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
    end })
end
