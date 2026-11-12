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

-- string.format on a secret proxy: Lua's own argument check refuses the
-- userdata before any metamethod runs ("bad argument #2 to 'format'"), which
-- says nothing about a secret. The core's format raises the secret error
-- instead, naming the secret, so a pcall that swallows it is counted (below).
-- Lua's own is kept on Kit: this file runs again for a fresh client.
Kit.rawformat = Kit.rawformat or string.format
local rawformat = Kit.rawformat
function string.format(fmt, ...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "userdata" and secrets[v] then
            error("secret value touched in Lua: " .. secrets[v] .. " (string.format)", 2)
        end
    end
    return rawformat(fmt, ...)
end

-- A blocked operation on a secret that a pcall caught still counts
-- (WowTestKit #13): the client writes every one to Logs/taint.log, caught or
-- not (Apotheca measured 106 lines in one session from health and mana
-- reads). pcall and xpcall count each in WoW.secretBlocked (WoW.reset clears
-- it), and done() fails on one. Two shapes reach them: a proxy's metamethod
-- ("secret value touched in Lua"), and an ordering against a number or a
-- string, which Lua 5.1 refuses before any metamethod runs ("attempt to
-- compare number with userdata"). A test that touches a secret on purpose
-- reads the count, then sets it back to 0; WoW.rawpcall doesn't count.
local function isSecretError(err)
    return type(err) == "string" and (err:find("secret value touched in Lua", 1, true) ~= nil
        or err:find("attempt to compare %a+ with userdata") ~= nil
        or err:find("attempt to compare userdata with %a+") ~= nil)
end
local function countSecret(err)
    if isSecretError(err) then
        WoW.secretBlocked = (WoW.secretBlocked or 0) + 1
        WoW.secretBlockedFirst = WoW.secretBlockedFirst or err
    end
end
-- Lua's own, kept on Kit: this file runs again for a fresh client
-- (Kit.freshClient), and must not wrap its own counting pcall.
Kit.rawpcall, Kit.rawxpcall = Kit.rawpcall or pcall, Kit.rawxpcall or xpcall
local rawpcall, rawxpcall = Kit.rawpcall, Kit.rawxpcall
WoW.rawpcall = rawpcall
local function counted(ok, ...)
    if not ok then countSecret((...)) end
    return ok, ...
end
function pcall(f, ...) return counted(rawpcall(f, ...)) end
function xpcall(f, handler)
    return rawxpcall(f, function(err) countSecret(err); return handler(err) end)
end

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
    WoW.secretBlocked, WoW.secretBlockedFirst = 0, nil
    WoW.secureActions = {}      -- what secure buttons did (WowTestKit #20)
    WoW.overrideBindings = {}   -- [key] = { owner, name, button, priority }
    WoW.useKeyDown = true       -- the ActionButtonUseKeyDown CVar, the client's default
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

-- The methods a protected frame refuses in combat (WowTestKit #12). The
-- refusal is silent on the client (the call does nothing and raises
-- ADDON_ACTION_BLOCKED): here it's recorded in WoW.blocked as "name:Method".
-- Checked when the call is made, before any implementation, so a consumer
-- that replaces one of these Methods keeps the refusal. A consumer adds the
-- ones it relies on (SetParent, SetScale...): WoW.PROTECTED.SetScale = true.
-- Sources: porting guide, "Secure click-casting works" (measured on 69913:
-- SetAttribute does nothing; a frame parenting secure buttons refuses to
-- hide, move, re-anchor, unclamp or stop a drag) and the action bar section
-- (RegisterForClicks); Apotheca #46 (StopMovingOrSizing on its bar). Resizing
-- is the client's standard lockdown, not measured on Forever separately.
WoW.PROTECTED = {
    Show = true, Hide = true, SetShown = true,
    SetPoint = true, ClearAllPoints = true, SetAllPoints = true,
    SetAttribute = true, RegisterForClicks = true,
    SetSize = true, SetWidth = true, SetHeight = true,
    StartMoving = true, StopMovingOrSizing = true, SetClampedToScreen = true,
}

-- Animation subtypes may call their own methods (the dump's
-- SimpleAnim<Type>API) or any Animation method.
Kit.ANIMATION_TYPES = { Alpha = true, Translation = true, Scale = true, Rotation = true, Path = true,
                        LineScale = true, LineTranslation = true, FlipBook = true, VertexColor = true,
                        TextureCoordTranslation = true }

-- Methods a Blizzard mixin adds in Lua (BackdropTemplateMixin's SetBackdrop,
-- MapCanvasMixin's GetMapID...), which the dump's widget walk can't see:
-- Kit.allowMethods({ ["Frame:SetBackdrop"] = "BackdropTemplateMixin (Backdrop.lua)" })
-- before the addon loads. Each needs its reason. They read as methods, and
-- Kit.checkMethods accepts them. Kept across Kit.freshClient().
Kit.allowedMethods = Kit.allowedMethods or {}
function Kit.allowMethods(map)
    for pair, why in pairs(map) do
        if type(pair) ~= "string" or not pair:match("^[%w_]+:[%w_]+$") then
            error("Kit.allowMethods: a pair reads Type:Method, got " .. tostring(pair), 2)
        end
        if type(why) ~= "string" or why == "" then
            error("Kit.allowMethods: " .. pair .. " needs its reason (the Blizzard file that adds it)", 2)
        end
        Kit.allowedMethods[pair] = why
    end
end

-- Whether a widget of this type has this method on the selected build, so
-- that feature detection (`if type(f.GetModel) == "function"`) behaves as
-- on the client (WowTestKit #22).
local buildTypes
local function hasMethod(wtype, k)
    local known = Kit.data("widgetMethods")
    if not buildTypes then
        buildTypes = {}
        for pair in pairs(known) do buildTypes[pair:match("^([%w_]+):")] = true end
    end
    local pair = wtype .. ":" .. k
    if known[pair] or Kit.allowedMethods[pair] then return true end
    if Kit.ANIMATION_TYPES[wtype] and known["Animation:" .. k] then return true end
    -- A type the build doesn't have (a test's own): Kit.checkMethods names it.
    return not buildTypes[wtype]
end

-- A method: records "Type:Method" for the widget it's called on, refuses a
-- protected one in combat, then runs the implementation (nil without one).
local function method(k)
    return function(self, ...)
        record(self, k)
        if WoW.PROTECTED[k] and WoW.refused(self, k) then return nil end
        local impl = Methods[k]
        if impl then return impl(self, ...) end
        return nil
    end
end

-- One method table per widget type, the __index of that type's metatable,
-- as on the client (WowTestKit #7): an addon can call the type's method on
-- a widget whose own field shadows it,
--   local W = getmetatable(CreateFrame("Frame")).__index
--   W.SetPoint(btn, ...)
-- A capitalised key is a method when the type has it on the build, when a
-- Methods implementation exists, or when it's allowed (Kit.allowMethods).
-- The build's and the allowed ones are kept in the table, so every read
-- gives the same function, as on the client; an implementation-only one is
-- looked up again on each read. Any other key reads as nil, as on the
-- client, so a call to it fails where it's made (lower-case keys too:
-- they're fields).
local methodTables, widgetMTs = {}, {}
local function widgetMT(wtype)
    if not widgetMTs[wtype] then
        local t = setmetatable({}, { __index = function(tbl, k)
            if type(k) ~= "string" or not k:match("^%u") then return nil end
            if hasMethod(wtype, k) then
                local fn = method(k)
                rawset(tbl, k, fn)
                return fn
            end
            if Methods[k] then return method(k) end
            return nil
        end })
        methodTables[wtype], widgetMTs[wtype] = t, { __index = t }
    end
    return widgetMTs[wtype]
end

-- Whether w is visible: shown, and every ancestor shown.
local function visible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end

local function newWidget(wtype, parent, name)
    local w = setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                             _scripts = {}, _events = {}, _unitEvents = {},
                             -- Lists from the start (WowTestKit #38), so ipairs(f._children)
                             -- works on a frame with none.
                             _children = {}, _regions = {},
                             _level = parent and parent._level and (parent._level + 1) or 1,
                             _width = 0, _height = 0, _name = name }, widgetMT(wtype))
    w._vis = visible(w)
    return w
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
        parent._children = parent._children or {}   -- a stub's own parent table
        table.insert(parent._children, w)
    end
    if name then rawset(_G, name, w) end
    w._vis = visible(w)   -- the visibility its OnShow / OnHide last reported (below)
    return w
end

-- Protection. A secure template makes a frame protected EXPLICITLY
-- (w._protected). A frame that parents a protected frame, at any depth, is
-- protected too (porting guide, "Secure click-casting works", measured on
-- 69913: a frame that parents secure buttons refuses to hide or move in
-- combat; #42). IsProtected returns both, as the client's does (the dump:
-- isProtected, isProtectedExplicitly). A secure header needs the explicit one.
local function isProtected(w)
    if w._protected then return true end
    for _, c in ipairs(w._children or {}) do
        if isProtected(c) then return true end
    end
    return false
end
WoW.isProtected = isProtected
function Methods.IsProtected(w) return isProtected(w), w._protected == true end

-- A protected frame refuses the WoW.PROTECTED methods in combat, as the
-- client does: nothing happens and the call is recorded in WoW.blocked. The
-- dispatch above checks it; the methods below also call it, for a direct
-- Methods.Show(w) from a stub.
local function refused(w, what)
    if WoW.combat and isProtected(w) then
        table.insert(WoW.blocked, (w._name or w._type) .. ":" .. what)
        return true
    end
end
WoW.refused = refused

-- Visibility follows the parent's (WowTestKit #21). OnShow / OnHide fire on
-- the frame and on each descendant whose visibility changed, parents first,
-- and only on a change: Show on a shown frame fires nothing, and a frame
-- shown under a hidden ancestor gets OnShow when that ancestor shows.
-- Each frame keeps the visibility its scripts last reported (w._vis). A
-- show or hide walks the subtree and fires where the live visibility differs
-- from it, so a script that shows or hides something while the walk runs
-- (an OnShow that hides its own frame, an OnHide that hides a child) leaves
-- each frame with one script per real change, never a stale one.
-- The walk follows CreateFrame's children (w._children, kept by SetParent).
local function settle(w)
    local now = visible(w)
    if now ~= w._vis then
        w._vis = now
        local script = w._scripts[now and "OnShow" or "OnHide"]
        if script then script(w) end
    end
    local children = {}
    for i, c in ipairs(w._children or {}) do children[i] = c end   -- a script may reparent
    for _, c in ipairs(children) do settle(c) end
end
-- The same walk without the scripts: the subtree's visibility is taken as
-- reported (reparenting, whose OnShow / OnHide isn't modelled).
local function resync(w)
    w._vis = visible(w)
    for _, c in ipairs(w._children or {}) do resync(c) end
end
-- Show or hide w with its scripts, without the combat refusal: what Show and
-- Hide do once allowed, and what secure code calls (a snippet's handle).
function WoW.setShown(w, shown)
    w._shown = shown and true or false
    settle(w)
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
-- A texture with a gradient ignores SetAlpha, in either order (measured on
-- 70374, porting guide section 3, "A gradient texture ignores SetAlpha"; LibGlass
-- r7 probe): GetAlpha reads 1 and the gradient's colours alone set its alpha.
-- SetGradient drops an alpha set before it (WowTestKit #37), and SetAlpha after
-- it does nothing. Modelled, so a test of a gradient's alpha can't pass against it.
function Methods.SetAlpha(w, a) if not w._gradient then w._alpha = a end end
function Methods.GetAlpha(w) return w._alpha or 1 end
function Methods.GetParent(w) return w._parent end
-- Reparenting moves the frame between its parents' children, so GetChildren
-- and the OnShow / OnHide walk follow it. (Its OnShow / OnHide on a
-- visibility change by reparenting isn't modelled.)
-- Takes w out of list; true if it was there.
local function takeOut(list, w)
    for i, c in ipairs(list or {}) do
        if c == w then table.remove(list, i); return true end
    end
    return false
end
function Methods.SetParent(w, p)
    local old = w._parent
    if old == p then return end
    w._parent = p
    resync(w)
    if w._frame then
        -- A frame CreateFrame made: in its parent's children.
        if old then takeOut(old._children, w) end
        if p then p._children = p._children or {}; table.insert(p._children, w) end
    elseif old and takeOut(old._regions, w) then
        -- A texture or font string made by CreateTexture / CreateFontString:
        -- in its parent's regions. Another widget (a status bar's fill) was
        -- in no list, and joins none.
        if p then p._regions = p._regions or {}; table.insert(p._regions, w) end
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

-- Attributes: recorded; refused (and recorded in WoW.blocked) on a protected
-- frame in combat, as the client does.
function Methods.SetAttribute(w, k, v)
    if refused(w, "SetAttribute") then return end
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
-- RegisterUnitEvent(event, unit1, unit2, ...) (WowTestKit #17): the event
-- reaches the frame only when its first payload argument is one of those
-- units. The dump declares units with StrideIndex 1, and Blizzard's own code
-- passes several ("player", "pet"). w._unitEvents[event] is the set of units
-- (w._unitEventOrder[event] the same units in the order given); a later call
-- replaces them. A plain RegisterEvent of the same event gets every unit's.
function Methods.RegisterUnitEvent(w, e, ...)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. tostring(e) .. "\"", 2) end
    local units, order = {}, {}
    for i = 1, select("#", ...) do
        local u = select(i, ...)
        if u ~= nil and not units[u] then units[u] = true; order[#order + 1] = u end
    end
    w._unitEvents[e] = units
    w._unitEventOrder = w._unitEventOrder or {}
    w._unitEventOrder[e] = order
    return true
end
function Methods.UnregisterEvent(w, e)
    w._events[e], w._unitEvents[e] = nil, nil
    if w._unitEventOrder then w._unitEventOrder[e] = nil end
end
function Methods.UnregisterAllEvents(w) w._events, w._unitEvents, w._unitEventOrder = {}, {}, {} end
-- IsEventRegistered(event) -> isRegistered, units... (SimpleFrameAPI: units
-- with StrideIndex 1): a unit registration's units follow, in the order given.
function Methods.IsEventRegistered(w, e)
    local order = w._unitEvents[e] and w._unitEventOrder and w._unitEventOrder[e]
    if order then return true, unpack(order) end
    return w._events[e] == true
end

-- Regions: in creation order for GetRegions (w._regions), as the client lists
-- a frame's textures and font strings; a named one is also a global.
local function addRegion(w, r)
    w._regions = w._regions or {}   -- a stub's own widget (WoW.addRegion)
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
-- SetGradient(orientation, minColor, maxColor): the colours are colour
-- objects (the dump's colorRGBA, made by CreateColor), not numbers.
function Methods.SetGradient(t, orientation, c1, c2)
    if type(c1) ~= "table" or type(c2) ~= "table" then
        error("SetGradient(orientation, minColor, maxColor): the colours are colour objects (CreateColor), got "
            .. type(c1) .. ", " .. type(c2), 2)
    end
    t._gradient = { orientation, c1, c2 }
    t._alpha = nil   -- a gradient's alpha is its colours' (GetAlpha reads 1)
end
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
-- The bar's colour is its fill texture's vertex colour, and setting it
-- replaces a gradient painted on the fill (measured on 70450, LibGlass#64:
-- GetVertexColor reads the new colour, the gradient's stripes are gone). With
-- SetAlpha ignored on a gradient (above), this decides a repainted bar's
-- opacity.
function Methods.SetStatusBarColor(b, r, g, bl, a)
    b._color = { r, g, bl, a }
    if b._fill then b._fill._gradient, b._fill._vertex = nil, { r, g, bl, a } end
end
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
--
-- A ticker repeats, as on the client (WowTestKit #18): it stays in
-- WoW.timers after it fires, until cancelled or its iterations are used up.
-- Its handle has Cancel and IsCancelled, and the callback gets the handle
-- (UITimerDocumentation: NewTicker's callback is a TickerCallback(cb)).
-- - advance re-arms it at at + every, so a dt spanning several periods
--   fires it once per period (a 0-second ticker once per advance);
-- - flushTimers runs it once and re-arms it from now, so flushTimers() again
--   runs it again: a loop flushing until WoW.timers is empty never ends
--   while a ticker lives.
-- Whether IsCancelled reads true after the last iteration is unmeasured:
-- here it reads false unless Cancel was called.
C_Timer = {}
function C_Timer.After(s, fn) table.insert(WoW.timers, { s = s, fn = fn, at = (WoW.now or 0) + s }) end
function C_Timer.NewTicker(s, fn, iterations)
    local t = { s = s, fn = fn, every = s, at = (WoW.now or 0) + s, iterations = iterations, fired = 0 }
    t.handle = {
        Cancel = function() t.cancelled = true end,
        IsCancelled = function() return t.cancelled == true end,
    }
    table.insert(WoW.timers, t)
    return t.handle
end

-- Runs one due timer or ticker. A ticker with iterations left goes back in
-- WoW.timers, re-armed at nextAt, before its callback runs (so a Cancel from
-- inside the callback holds). Only the core's tickers repeat (they carry
-- their handle): a record a stub put in WoW.timers itself runs once, as
-- before tickers repeated (WowTestKit #34).
local function fireTimer(t, nextAt)
    if t.cancelled then return end
    if not t.handle then return t.fn() end
    t.fired = t.fired + 1
    if not (t.iterations and t.fired >= t.iterations) then
        t.at = nextAt
        table.insert(WoW.timers, t)
    end
    t.fn(t.handle)
end

function WoW.flushTimers(upTo)
    local run, keep = {}, {}
    for _, t in ipairs(WoW.timers) do
        if t.cancelled then -- dropped
        elseif upTo == nil or t.s <= upTo then run[#run + 1] = t else keep[#keep + 1] = t end
    end
    WoW.timers = keep
    local now = WoW.now or 0
    for _, t in ipairs(run) do fireTimer(t, now + (t.every or 0)) end
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
        -- A 0-second ticker would fall due again at once: next advance.
        local nextAt = t.every and t.every > 0 and at + t.every or WoW.now + 1e-9
        fireTimer(t, nextAt)   -- a cancelled one never fires
    end
end

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- Fire an event at every frame registered for it. Errors are NOT caught: a
-- handler that throws fails the test.
function WoW.fire(event, ...)
    local unit = ...
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler then
            local units = w._unitEvents[event]
            if w._events[event] or (units and unit ~= nil and units[unit]) then handler(w, event, ...) end
        end
    end
end

-- Every event any frame registered, so strict globals catch the code that
-- handles it. A plain event fires once with no payload. A unit event (some
-- frame registered it with RegisterUnitEvent) fires once per unit any frame
-- registered it for, with that unit as its payload, so a handler that
-- indexes by unit runs; plain registrations of it get each of those.
-- Returns the events fired, sorted.
function WoW.fireAllRegistered()
    local seen, units = {}, {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do seen[e] = true end
        for e, set in pairs(w._unitEvents) do
            seen[e] = true
            units[e] = units[e] or {}
            for u in pairs(set) do units[e][u] = true end
        end
    end
    local list = {}
    for e in pairs(seen) do list[#list + 1] = e end
    table.sort(list)   -- the same order on every run
    for _, e in ipairs(list) do
        if units[e] then
            local us = {}
            for u in pairs(units[e]) do us[#us + 1] = u end
            table.sort(us)
            for _, u in ipairs(us) do WoW.fire(e, u) end
        else
            WoW.fire(e)
        end
    end
    return list
end

-- One rendered frame: the clock moves on by elapsed, then OnUpdate runs on
-- every visible frame with it. On the client a frame's elapsed and GetTime()
-- move together, so code that times something by GetTime() inside its
-- OnUpdate sees time pass (WowTestKit #9). Timers stay with WoW.advance and
-- WoW.flushTimers: a test that wants both calls WoW.advance(dt), then
-- WoW.tick(0).
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    WoW.now = (WoW.now or 0) + elapsed
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

--------------------------------------------------------------------------------
-- Secure handlers (WowTestKit #20), from the client's own source
-- (wow-ui-source forever, 70862: Blizzard_RestrictedAddOnEnvironment's
-- SecureHandlers.lua, RestrictedFrames.lua, RestrictedExecution.lua,
-- RestrictedEnvironment.lua; Blizzard_FrameXML's SecureTemplates.lua).
-- Secure snippets run on Forever since 70425, in combat too (porting guide,
-- "Secure click-casting works").
--
-- Modelled: SecureHandlerWrapScript / UnwrapScript on OnClick,
-- SecureHandlerSetFrameRef, SecureHandlerExecute, one environment per
-- protected frame, frame handles with the methods below, the secure action
-- button's own click (WoW.secureActionClick), and WoW.click /
-- WoW.pressKey to drive them. Not modelled: other wrapped scripts, modified
-- attributes (*type1, shift-type1...), the header templates' own snippet
-- attributes (_onclick, _onstate-...), and a snippet's error being caught
-- (here it fails the test).
--------------------------------------------------------------------------------

-- Templates that make a frame explicitly protected. A consumer that defines
-- one of these again replaces it; the secure action button's must then set
-- its OnClick to WoW.secureActionClick itself.
for _, t in ipairs({ "SecureFrameTemplate", "SecureHandlerBaseTemplate", "SecureHandlerClickTemplate",
                     "SecureHandlerStateTemplate", "SecureHandlerAttributeTemplate",
                     "SecureHandlerShowHideTemplate", "SecureHandlerEnterLeaveTemplate" }) do
    WoW.templates[t] = function(w) w._protected = true end
end
WoW.templates.SecureActionButtonTemplate = function(w)
    w._protected = true
    w._scripts.OnClick = function(...) return WoW.secureActionClick(...) end
end

-- What a snippet sees besides its environment's own names: the restricted
-- scope (RestrictedEnvironment.lua's RESTRICTED_FUNCTIONS_SCOPE and
-- RestrictedExecution.lua's LOCAL_Restricted_Global_Functions), with plain
-- tables standing in for restricted ones.
local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
WoW.SECURE_SCOPE = {
    math = math, string = string, select = select, tonumber = tonumber, tostring = tostring,
    type = type, pairs = pairs, ipairs = ipairs, next = next, unpack = unpack,
    -- ENV.print (RestrictedEnvironment.lua:237): the global print, values scrubbed.
    print = function(...) return print(...) end,
    newtable = function(...) return { ... } end, copytable = copy,
    wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end,
    tinsert = table.insert, tremove = table.remove,
    table = { maxn = table.maxn, insert = table.insert, remove = table.remove, sort = table.sort,
              concat = table.concat, new = function(...) return { ... } end,
              wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end },
    format = string.format, gsub = string.gsub, strfind = string.find, strlen = string.len,
    strlower = string.lower, strupper = string.upper, strmatch = string.match, strrep = string.rep,
    strsub = string.sub, strbyte = string.byte, strchar = string.char,
    abs = math.abs, ceil = math.ceil, floor = math.floor, max = math.max, min = math.min,
    mod = math.fmod, random = math.random, sqrt = math.sqrt,
}

-- Frame handles: one per frame, userdata as on the client.
local handleFrame = setmetatable({}, { __mode = "k" })   -- handle -> frame
local frameHandle = setmetatable({}, { __mode = "k" })   -- frame -> handle
local HANDLE = {}
local function handleOf(w)
    if w == nil then return nil end
    local h = frameHandle[w]
    if not h then
        h = newproxy(true)
        local mt = getmetatable(h)
        mt.__index = HANDLE
        mt.__tostring = function() return "handle: " .. tostring(w._name or w._type) end
        handleFrame[h], frameHandle[w] = w, h
    end
    return h
end
WoW.handleOf = handleOf
-- The frame behind a handle (RestrictedFrames.lua's GetHandleFrame): in
-- combat only a protected frame's; an unprotected frame's handle is then an
-- "Invalid frame handle" error, as in the client. GetName, GetObjectType,
-- IsObjectType and IsProtected use the unguarded path (anyFrameOf).
local function anyFrameOf(h)
    local w = handleFrame[h]
    if not w then error("Invalid frame handle", 3) end
    return w
end
local function frameOf(h)
    local w = handleFrame[h]
    if not w or (WoW.combat and not isProtected(w)) then error("Invalid frame handle", 3) end
    return w
end
WoW.frameOf = function(h) return handleFrame[h] end

-- One environment per protected frame (GetManagedEnvironment): its globals
-- persist across that frame's snippets; `owner` is its handle, `control`
-- the handle of the header running the snippet.
local envs = setmetatable({}, { __mode = "k" })
local function envOf(w)
    if not w._protected then error("Invalid access of managed environments table (not protected)", 3) end
    local e = envs[w]
    if not e then
        e = {}
        e._G, e.owner = e, handleOf(w)
        envs[w] = e
    end
    return e
end
WoW.secureEnvironment = envOf

-- Run a snippet as CallRestrictedClosure does: body checked, compiled with
-- the signature's names as parameters, run in env with the restricted scope
-- behind it.
local function runSnippet(env, control, signature, body, ...)
    if type(body) ~= "string" then return end
    if body:match("function") then error("The function keyword is not permitted", 3) end
    if body:match("[{}]") then error("Direct table creation is not permitted", 3) end
    local def, err = loadstring("return function (" .. signature .. ") " .. body .. "\nend", "snippet")
    if not def then error(err, 3) end
    local fn = def()
    local controlHandle = control and handleOf(control)
    setfenv(fn, setmetatable({}, {
        __index = function(_, k)
            local v = env[k]
            if v == nil then v = WoW.SECURE_SCOPE[k] end
            if v == nil and k == "control" then return controlHandle end
            return v
        end,
        __newindex = env,
    }))
    return fn(...)
end

-- Handle methods (RestrictedFrames.lua). Changes are secure: allowed in
-- combat on protected frames, never recorded in WoW.blocked.
function HANDLE:GetName() return anyFrameOf(self)._name end
function HANDLE:GetObjectType() return anyFrameOf(self)._type end
function HANDLE:IsObjectType(t) return anyFrameOf(self)._type == t end
function HANDLE:GetAttribute(k) local w = frameOf(self); return w._attrs and w._attrs[k] end
function HANDLE:SetAttribute(k, v)
    local w = frameOf(self)
    w._attrs = w._attrs or {}
    w._attrs[k] = v
end
function HANDLE:Show() WoW.setShown(frameOf(self), true) end
function HANDLE:Hide() WoW.setShown(frameOf(self), false) end
function HANDLE:IsShown() return frameOf(self)._shown end
function HANDLE:IsVisible() return Methods.IsVisible(frameOf(self)) end
function HANDLE:IsProtected()
    local w = anyFrameOf(self)
    return isProtected(w), w._protected == true
end
function HANDLE:GetParent() return handleOf(frameOf(self)._parent) end
function HANDLE:ClearAllPoints() frameOf(self)._points = {} end
function HANDLE:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "userdata" then rel = frameOf(rel) end
    table.insert(frameOf(self)._points, { point, rel, relPoint, x, y })
end
function HANDLE:GetWidth() return frameOf(self)._width end
function HANDLE:GetHeight() return frameOf(self)._height end
function HANDLE:SetWidth(v) frameOf(self)._width = v end
function HANDLE:SetHeight(v) frameOf(self)._height = v end
-- The cursor as a fraction of the frame's rect, nil outside it
-- (RestrictedFrames.lua:307): GetCursorPosition() over the effective scale,
-- less the rect's left and bottom. The rect: _left / _bottom (0 unset) and
-- the frame's size; the effective scale: the stub's GetEffectiveScale, else 1.
function HANDLE:GetMousePosition()
    local w = frameOf(self)
    local width, height = w._width, w._height
    if not width or not height or width == 0 or height == 0 then return nil end
    local e = Methods.GetEffectiveScale and Methods.GetEffectiveScale(w) or 1
    local x, y = GetCursorPosition()
    x, y = x / e - (w._left or 0), y / e - (w._bottom or 0)
    if x < 0 or x > width or y < 0 or y > height then return nil end
    return x / width, y / height
end
function HANDLE:GetFrameRef(label)
    if type(label) ~= "string" then return nil end
    local w = frameOf(self)
    local v = w._attrs and w._attrs["frameref-" .. label]
    if handleFrame[v] then return v end
    return nil
end
-- A snippet stored in an attribute, run with this frame as self, in its own
-- environment, with the caller's handle as control.
function HANDLE:RunAttribute(attr, ...)
    local w = frameOf(self)
    if type(attr) ~= "string" then error("Invalid snippet attribute", 2) end
    local body = w._attrs and w._attrs[attr]
    if type(body) ~= "string" then error("Invalid snippet body", 2) end
    return runSnippet(envOf(w), w, "self,...", body, self, ...)
end
-- Override bindings owned by the frame (SetOverrideBindingClick's), in
-- WoW.overrideBindings[key] = { owner, name, button, priority }.
function HANDLE:SetBindingClick(priority, key, name, button)
    if type(name) == "userdata" and handleFrame[name] then name = handleFrame[name]._name end
    if type(name) ~= "string" or name:match(":") then error("Invalid click target name", 2) end
    if button ~= nil and type(button) ~= "string" then error("Invalid button name", 2) end
    WoW.overrideBindings[key] = { owner = frameOf(self), name = name, button = button, priority = priority }
end
function HANDLE:ClearBinding(key)
    local b = WoW.overrideBindings[key]
    if b and b.owner == frameOf(self) then WoW.overrideBindings[key] = nil end
end
function HANDLE:ClearBindings()
    local w = frameOf(self)
    for key, b in pairs(WoW.overrideBindings) do
        if b.owner == w then WoW.overrideBindings[key] = nil end
    end
end

-- The SecureHandler* API goes through a protected frame of Blizzard's
-- (SecureHandlersUpdateFrame, a SecureFrameTemplate) by SetAttribute: from
-- addon code in combat that's refused, so these do nothing then and record
-- the refusal (read in the source, not measured).
local function apiRefused(what)
    if WoW.combat then
        table.insert(WoW.blocked, "SecureHandlersUpdateFrame:SetAttribute (" .. what .. ")")
        return true
    end
end

function SecureHandlerSetFrameRef(frame, label, refFrame)
    if type(frame) ~= "table" then error("Invalid frame", 2) end
    if type(label) ~= "string" then error("Invalid body", 2) end
    if type(refFrame) ~= "table" then error("Invalid reference frame", 2) end
    if apiRefused("SecureHandlerSetFrameRef") then return end
    frame._attrs = frame._attrs or {}
    frame._attrs["frameref-" .. label] = handleOf(refFrame)
end

function SecureHandlerExecute(frame, body)
    if type(frame) ~= "table" then error("Invalid header frame", 2) end
    if not frame._protected then error("Header frame must be explicitly protected", 2) end
    if type(body) ~= "string" then error("Invalid body", 2) end
    if apiRefused("SecureHandlerExecute") then return end
    runSnippet(envOf(frame), frame, "self", body, handleOf(frame))
end

-- Wrapped_Click (SecureHandlers.lua:272): the header's pre snippet runs
-- (when the frame is eligible: out of combat, or protected); false cancels
-- the click, a string replaces the button, a second value is the message.
-- Then the script that was there runs, then the post snippet when there's a
-- message.
local function wrappedClick(wrap, self, button, down, ...)
    local message, newbutton
    if not WoW.combat or isProtected(self) then
        newbutton, message = runSnippet(envOf(wrap.header), wrap.header, "self,button,down", wrap.pre,
                                        handleOf(self), button, down)
        if newbutton == false then return end
        if newbutton then button = tostring(newbutton) end
    end
    if wrap.old then wrap.old(self, button, down, ...) end
    if wrap.post and message ~= nil then
        runSnippet(envOf(wrap.header), wrap.header, "self,message,button,down", wrap.post,
                   handleOf(self), message, button, down)
    end
end

local wraps = setmetatable({}, { __mode = "k" })   -- wrapper function -> its wrap
function SecureHandlerWrapScript(frame, script, header, preBody, postBody)
    if type(frame) ~= "table" then error("Invalid frame", 2) end
    if type(script) ~= "string" then error("Invalid script id", 2) end
    if script ~= "OnClick" then error("WowTestKit wraps OnClick only (#20): " .. script, 2) end
    if type(header) ~= "table" or not header._protected then error("Header frame must be explicitly protected", 2) end
    if type(preBody) ~= "string" then error("Invalid pre-handler body", 2) end
    if postBody ~= nil and type(postBody) ~= "string" then error("Invalid post-handler body", 2) end
    if apiRefused("SecureHandlerWrapScript") then return end
    local wrap = { header = header, pre = preBody, post = postBody, old = frame._scripts[script] }
    local fn = function(self, ...) return wrappedClick(wrap, self, ...) end
    wraps[fn] = wrap
    frame._scripts[script] = fn
end

-- Takes off the outermost wrap and returns its header and snippets.
function SecureHandlerUnwrapScript(frame, script)
    if type(frame) ~= "table" then error("Invalid frame", 2) end
    if type(script) ~= "string" then error("Invalid script id", 2) end
    local wrap = wraps[frame._scripts[script]]
    if not wrap then return end
    if apiRefused("SecureHandlerUnwrapScript") then return end
    frame._scripts[script] = wrap.old
    return wrap.header, wrap.pre, wrap.post
end

-- The secure action button's own OnClick (SecureActionButton_OnClick): it
-- acts only on the edge where down == useOnKeyDown (the attribute, else the
-- ActionButtonUseKeyDown CVar: WoW.useKeyDown). Measured on Forever, so one
-- click uses an item once (Apotheca AGENTS.md, "Secure buttons register both
-- mouse edges"). What it did goes to WoW.secureActions. Returns whether it
-- acted.
function WoW.secureActionClick(self, button, down)
    local attrs = self._attrs or {}
    local onDown = attrs.useOnKeyDown
    if onDown == nil then onDown = WoW.useKeyDown end
    if (down and true or false) ~= (onDown and true or false) then return false end
    table.insert(WoW.secureActions, {
        button = self._name, mouse = button, type = attrs.type, item = attrs.item, spell = attrs.spell,
        macro = attrs.macro, macrotext = attrs.macrotext, unit = attrs.unit,
        targetBag = attrs["target-bag"], targetSlot = attrs["target-slot"],
    })
    return true
end

-- One edge of a click on a button, as the client runs it: PreClick, OnClick
-- (a wrap's snippets and the secure action inside it), PostClick. A disabled
-- button doesn't click. Button:Click(button, down) does the same.
function WoW.click(b, button, down)
    button, down = button or "LeftButton", down and true or false
    if b._disabled then return end
    if b._scripts.PreClick then b._scripts.PreClick(b, button, down) end
    if b._scripts.OnClick then b._scripts.OnClick(b, button, down) end
    if b._scripts.PostClick then b._scripts.PostClick(b, button, down) end
end
function Methods.Click(b, button, down) WoW.click(b, button, down) end

-- A key on an override binding clicks the button it names (CLICK
-- <name>:<button>), hidden or not. Returns whether a binding took it.
function WoW.pressKey(key, down)
    local b = WoW.overrideBindings[key]
    if not b then return false end
    local target = rawget(_G, b.name)
    if not target then error("no frame named " .. tostring(b.name) .. " for the binding of " .. key, 2) end
    WoW.click(target, b.button or "LeftButton", down)
    return true
end

-- The cursor, in screen pixels (GetCursorPosition). A stub may set it, or
-- define GetCursorPosition itself.
WoW.cursorX, WoW.cursorY = WoW.cursorX or 0, WoW.cursorY or 0
function GetCursorPosition() return WoW.cursorX, WoW.cursorY end

WoW.reset()

--------------------------------------------------------------------------------
-- Strict globals, installed by the consumer's stub as its last line
--------------------------------------------------------------------------------

-- The client globals this core defines, for the kit's own check that each is
-- in the build's globals list. FrameXML names (not in a function list) are
-- listed apart, each with where it comes from.
Kit.CORE_GLOBALS = { "CreateFrame", "issecretvalue", "print", "GetTime", "InCombatLockdown",
                     "strmatch", "hooksecurefunc", "C_Timer", "pcall", "xpcall", "GetCursorPosition",
                     "SecureHandlerSetFrameRef", "SecureHandlerExecute", "SecureHandlerWrapScript",
                     "SecureHandlerUnwrapScript" }
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
