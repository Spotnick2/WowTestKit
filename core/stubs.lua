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
-- Lua's compare error names no operand, and other userdata (a secure
-- handle) gives the same message (#47). It counts only while a secret proxy
-- is alive in the test; a handle compared while a secret lives is still
-- counted, a limit Lua 5.1 leaves no way around.
local function secretProxyAlive()
    for v in pairs(secrets) do
        if type(v) == "userdata" then return true end
    end
    return false
end
local function isSecretError(err)
    if type(err) ~= "string" then return false end
    if err:find("secret value touched in Lua", 1, true) then return true end
    return (err:find("attempt to compare %a+ with userdata") ~= nil
        or err:find("attempt to compare userdata with %a+") ~= nil) and secretProxyAlive()
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
-- The client's xpcall passes its extra arguments to f, as Lua 5.1's doesn't
-- (WowTestKit #91; Blizzard relies on it: xpcall(script, CallErrorHandler,
-- frame, ...), Blizzard_SharedXMLBase/FunctionUtil.lua:4, wow-ui-source
-- forever 70959).
function xpcall(f, handler, ...)
    local n, args = select("#", ...), { ... }
    local call = f
    if n > 0 then call = function() return f(unpack(args, 1, n)) end end
    return rawxpcall(call, function(err) countSecret(err); return handler(err) end)
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
-- WoW.reset({ keepFrames = true }) resets the client's state only
-- (WowTestKit #80), for a test file that loads the addon once and resets
-- between sections: the frames made so far are kept (WoW.frames, so events
-- and OnUpdate still reach them, with their parents and children), and so
-- are WoW.widgets and WoW.methodsCalled (Kit.checkMethods still sees the
-- load's calls), and so are their state drivers (#77), as their event
-- registrations are. Everything else is cleared as by WoW.reset(): chat,
-- combat, timers (a ticker started at load is dropped too), WoW.blocked...
-- Each WoW.onReset function gets the same opts.
function WoW.reset(opts)
    local keepFrames = type(opts) == "table" and opts.keepFrames == true
    -- The frames made so far are discarded: events and OnUpdate no longer
    -- reach them, and neither does a parent's OnShow / OnHide walk (#46).
    -- Each comes out of its parent's children, so a frame that survives the
    -- reset (UIParent, a frame the stub built) doesn't carry it on.
    for _, w in ipairs(not keepFrames and WoW.frames or {}) do
        local siblings = w._parent and w._parent._children
        for i, c in ipairs(siblings or {}) do
            if c == w then table.remove(siblings, i); break end
        end
    end
    WoW.frames = keepFrames and WoW.frames or {}
    WoW.chat = {}
    WoW.methodsCalled = keepFrames and WoW.methodsCalled or {}
    WoW.widgets = keepFrames and WoW.widgets or {}   -- every widget made since, in order (WowTestKit #67)
    WoW.combat = false
    WoW.locale = nil            -- GetLocale() reads "enUS" until a test sets one
    WoW.timers = {}
    WoW.blocked = {}
    WoW.forbidden = {}          -- refused registrations (WowTestKit #79)
    WoW.secretBlocked, WoW.secretBlockedFirst = 0, nil
    WoW.secureActions = {}      -- what secure buttons did (WowTestKit #20)
    WoW.overrideBindings = {}   -- [key] = { owner, name, button, priority }
    WoW.useKeyDown = true       -- the ActionButtonUseKeyDown CVar, the client's default
    WoW.focus = nil             -- the edit box with the keyboard focus (WowTestKit #89)
    WoW.useKeyHeldSpell = false -- the ActionButtonUseKeyHeldSpell CVar (press-and-hold casting, #88)
    -- [frame] = { [attribute] = values } (WowTestKit #77). A frame's drivers
    -- are its registrations, as its events are: kept with the frames.
    WoW.stateDrivers = keepFrames and WoW.stateDrivers or {}
    -- SecureStateDriverManager's throttle; nil while it's hidden.
    WoW.stateDriverTimer = keepFrames and WoW.stateDriverTimer or nil
    for _, fn in ipairs(WoW.onReset) do fn(opts) end
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
-- ones it relies on (SetParent...): WoW.PROTECTED.SetParent = true.
-- Sources: porting guide, "Secure click-casting works" (measured on 69913:
-- SetAttribute does nothing; a frame parenting secure buttons refuses to
-- hide, move, re-anchor, unclamp or stop a drag) and the action bar section
-- (RegisterForClicks); Apotheca #46 (StopMovingOrSizing on its bar);
-- LibGroupBuffsProbe's combat sweep (70959, LibGroupBuffs #74, wow-dev-tools
-- #49; WowTestKit #83): a frame parenting secure buttons refuses Show, Hide,
-- SetShown, SetPoint, ClearAllPoints, SetClampedToScreen, SetSize, SetWidth,
-- SetHeight, SetScale, SetFrameStrata, SetFrameLevel and EnableMouse, and the
-- secure button SetAttribute and SetWidth. Measured as allowed, so left out:
-- SetAlpha on the protected frame, and any write to its regions (a texture's
-- or font string's Show, Hide, SetShown, its texture). SetAllPoints,
-- RegisterForClicks, StartMoving and StopMovingOrSizing weren't in the sweep.
-- ClearPoint and StartSizing (#89, #92) are read, not measured: the build's
-- generated API documentation flags them IsProtectedFunction
-- (SimpleScriptRegionResizingAPIDocumentation.lua, SimpleFrameAPIDocumentation.lua,
-- wow-ui-source forever 70959), as it flags every method above that was
-- measured, and not SetAlpha, measured as allowed.
WoW.PROTECTED = {
    Show = true, Hide = true, SetShown = true,
    SetPoint = true, ClearAllPoints = true, SetAllPoints = true,
    SetAttribute = true, RegisterForClicks = true,
    SetSize = true, SetWidth = true, SetHeight = true, SetScale = true,
    SetFrameStrata = true, SetFrameLevel = true, EnableMouse = true,
    StartMoving = true, StopMovingOrSizing = true, SetClampedToScreen = true,
    ClearPoint = true, StartSizing = true,
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

-- Every call on a widget, in order, with its arguments (WowTestKit #67):
-- w._log holds one { name, n = argc, ... } per call made through the
-- widget's methods, logged before the combat refusal, so a refused call is
-- in it too (WoW.blocked says it was refused). A Methods implementation one
-- stub function calls directly (Methods.Show from Methods.SetShown) isn't a
-- call on the widget, and isn't logged. A hooksecurefunc on the widget logs
-- { "hooksecurefunc:<name>", n = 0 } (below). A test compares two logs (a
-- parity test) or a log's length before and after (nothing repainted).
local function log(self, k, ...)
    if type(self) ~= "table" then return end
    local l = rawget(self, "_log")
    if not l then l = {}; rawset(self, "_log", l) end   -- a stub's own widget table
    l[#l + 1] = { k, n = select("#", ...), ... }
end

-- A hook on every widget call (WowTestKit #81): each function in
-- WoW.onMethodCall runs as fn(widget, methodName, ...) on every call made
-- through a widget's methods, after the record and the log, before the
-- combat refusal, so it sees a call that will be refused too, and can read
-- WoW.combat and WoW.isProtected(widget) as they are at the call. What it
-- returns is ignored; an error it raises fails the call. Like w._log, it
-- doesn't see a Methods implementation one stub function calls directly. A
-- call the hook makes on a widget runs the hooks again. WoW.reset keeps the
-- list (the stub adds its hooks once, as with WoW.onReset); a fresh client
-- starts with an empty one, which the consumer's stub fills again.
WoW.onMethodCall = {}

-- A method: records "Type:Method" for the widget it's called on, logs the
-- call, runs the WoW.onMethodCall hooks, refuses a protected one in combat,
-- then runs the implementation (nil without one).
local function method(k)
    return function(self, ...)
        record(self, k)
        log(self, k, ...)
        for _, fn in ipairs(WoW.onMethodCall) do fn(self, k, ...) end
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
local methodTables, widgetMTs, widgetMTSet = {}, {}, {}
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
        widgetMTSet[widgetMTs[wtype]] = true
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
                             _children = {}, _regions = {}, _maskTextures = {},
                             _level = parent and parent._level and (parent._level + 1) or 1,
                             _width = 0, _height = 0, _name = name, _log = {} }, widgetMT(wtype))
    w._vis = visible(w)
    -- Every widget made, in creation order (WowTestKit #67): frames,
    -- regions, masks, a status bar's fill, animations, and a stub's own
    -- (WoW.newWidget). WoW.reset clears it; UIParent, made before the first
    -- reset, isn't in it.
    if WoW.widgets then WoW.widgets[#WoW.widgets + 1] = w end
    return w
end
WoW.newWidget = newWidget
-- Whether v is a widget the core made (its metatable is a widget type's).
local function isWidget(v) return type(v) == "table" and widgetMTSet[getmetatable(v)] == true end
WoW.isWidget = isWidget

-- A named widget is a global, as on the client. WoW.published remembers each
-- name the core set, so a fresh client can take the old client's off (#45).
WoW.published = {}
local function publish(name, w)
    rawset(_G, name, w)
    WoW.published[name] = w
end

-- Templates: WoW.templates[name](frame) builds what that template adds
-- (parentKey children, scripts, _protected). A comma-separated list runs each
-- in order. Unknown templates add nothing.
WoW.templates = {}

-- XML intrinsics (WowTestKit #85): a frame type Blizzard's XML declares with
-- intrinsic="true" is a widget of its base element's type with a mixin, not
-- a widget type of its own (the build's lists have none of these). CreateFrame
-- makes one as its base type (w._type), keeps the name asked for in
-- w._intrinsic, and the calls are recorded on the base type, so the mixin's
-- methods are Kit.allowMethods entries on it ("Button:SetupMenu"), like any
-- other mixin's. GetObjectType returns the base type here; what the client's
-- returns for an intrinsic is unmeasured. The intrinsic's own XML (its mixin,
-- enableMouse, scripts) isn't applied: a template given to CreateFrame is.
-- Every intrinsic in wow-ui-source forever 70959 (Interface/AddOns/...):
-- Blizzard_SharedXML/Shared/Frame/EventFrame.xml:3, EventButton.xml:3,
-- EventEditBox.xml:3, EventScrollFrame.xml:3; Blizzard_Menu/DropdownButton.xml:3;
-- Blizzard_SharedXML/DropDownToggleButton.xml:4, AlertFrameIntrinsic.xml:4;
-- Blizzard_ItemButton/Shared/ItemButtonTemplate.xml:4;
-- Blizzard_AuraContainer/Blizzard_AuraButton.xml:5, Blizzard_AuraContainer.xml:5;
-- Blizzard_AccessibilityTemplates/AccessibilityIntrinsics.xml:3. Except
-- ScrollingMessageFrame (Blizzard_SharedXML/ScrollingMessageFrame.xml:3, an
-- intrinsic Frame): the dump made one with CreateFrame("ScrollingMessageFrame")
-- and lists its methods under that name, so the build's lists, WoW.KIND_OF
-- and consumers' pairs treat it as a type. A consumer adds its own:
-- WoW.INTRINSIC.MyIntrinsic = "Frame".
WoW.INTRINSIC = {
    EventFrame = "Frame", EventButton = "Button", EventEditBox = "EditBox",
    EventScrollFrame = "ScrollFrame", DropdownButton = "Button", DropDownToggleButton = "Button",
    ContainedAlertFrame = "Button", ItemButton = "Button", AuraButton = "Button",
    AuraContainer = "Frame", UIThemeContainerFrame = "Frame",
}

function CreateFrame(ftype, name, parent, template)
    local base = WoW.INTRINSIC[ftype]
    local w = newWidget(base or ftype, parent, name)
    w._intrinsic = base and ftype or nil
    w._template = template
    w._frame = true   -- a frame, not a region (SetParent moves it between children)
    if w._type == "StatusBar" then w._min, w._max, w._value = 0, 1, 0 end
    if w._type == "GameTooltip" then w._lines, w._linesRight = {}, {} end   -- no lines yet (#89)
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
    if name then publish(name, w) end
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
-- the frame and on each descendant whose visibility changed, children
-- before their parent, and only on a change: Show on a shown frame fires
-- nothing, and a frame shown under a hidden ancestor gets OnShow when that
-- ancestor shows. The order is measured (WowTestKitProbe, /fp steps tk
-- reparent, 70959, 2026-11-18; WowTestKit #99): Hide, Show and a SetParent
-- that changes visibility each ran the child's script before its parent's,
-- for a frame and its one child (siblings' order and deeper trees unmeasured).
-- Each frame keeps the visibility its scripts last reported (w._vis). A
-- show or hide walks the subtree and fires where the live visibility differs
-- from it, so a script that shows or hides something while the walk runs
-- (an OnShow that hides its own frame, an OnHide that hides a child) leaves
-- each frame with one script per real change, never a stale one.
-- The walk follows CreateFrame's children (w._children, kept by SetParent).
local function settle(w)
    local children = {}
    for i, c in ipairs(w._children or {}) do children[i] = c end   -- a script may reparent
    for _, c in ipairs(children) do settle(c) end
    local now = visible(w)
    if now ~= w._vis then
        w._vis = now
        local script = w._scripts[now and "OnShow" or "OnHide"]
        if script then script(w) end
    end
end
-- The same walk without the scripts: the subtree's visibility is taken as
-- reported (a region reparented: textures and font strings have no OnShow).
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
-- One anchor per point (WowTestKit #92): SetPoint on a point the frame
-- already has replaces that anchor; only ClearAllPoints and ClearPoint
-- remove one. GetPoint(i), GetNumPoints and ClearPoint read the same list,
-- w._points. A replaced anchor moves to the end of the list (the order
-- GetPoint(i) gives on the client isn't measured). Blizzard's code relies on
-- the replacement: SecureGroupHeaders.lua's configureChildren re-anchors
-- each shown child on every pass with no ClearAllPoints (:202-211,
-- wow-ui-source forever 70959). A secure
-- handle's SetPoint does the same. SetAllPoints's { "ALL", rel } is one
-- point here, replaced the same way.
local function dropPoint(w, point)
    for i = #w._points, 1, -1 do
        if w._points[i][1] == point then table.remove(w._points, i) end
    end
end
local function anchor(w, point, ...)
    dropPoint(w, point)
    table.insert(w._points, { point, ... })
end
function Methods.SetPoint(w, ...)
    if refused(w, "SetPoint") then return end
    anchor(w, ...)
end
-- Removes that point's anchor; one the frame doesn't have is ignored.
function Methods.ClearPoint(w, point) dropPoint(w, point) end
function Methods.ClearAllPoints(w)
    if refused(w, "ClearAllPoints") then return end
    w._points = {}
end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
-- The anchors GetPoint reads (WowTestKit #89).
function Methods.GetNumPoints(w) return #w._points end
function Methods.SetAllPoints(w, rel)
    if refused(w, "SetAllPoints") then return end   -- a re-anchor, like SetPoint
    anchor(w, "ALL", rel)
end
function Methods.SetSize(w, x, y) w._width, w._height = x, y end
function Methods.SetWidth(w, x) w._width = x end
function Methods.SetHeight(w, y) w._height = y end
function Methods.GetWidth(w) return w._width end
function Methods.GetHeight(w) return w._height end
-- GetSize() -> width, height (SimpleScriptRegionAPI; WowTestKit #78): what
-- SetSize / SetWidth / SetHeight set, as GetWidth and GetHeight read it.
-- Its ignoreRect argument changes nothing here (no layout).
function Methods.GetSize(w) return w._width, w._height end
-- The widget's own scale, 1 until set (WowTestKit #89); a frame's and a
-- region's (SimpleFrameAPI, SimpleRegionAPI). GetEffectiveScale multiplies
-- it up the parents (below). SetScale is refused in combat on a protected
-- frame (WoW.PROTECTED).
function Methods.SetScale(w, s) w._scale = s end
function Methods.GetScale(w) return w._scale or 1 end
-- A texture with a gradient ignores SetAlpha, in either order (measured on
-- 70374, porting guide section 3, "A gradient texture ignores SetAlpha"; LibGlass
-- r7 probe): GetAlpha reads 1 and the gradient's colours alone set its alpha.
-- SetGradient drops an alpha set before it (WowTestKit #37), and SetAlpha after
-- it does nothing. Modelled, so a test of a gradient's alpha can't pass against it.
function Methods.SetAlpha(w, a) if not w._gradient then w._alpha = a end end
function Methods.GetAlpha(w) return w._alpha or 1 end
function Methods.GetParent(w) return w._parent end
-- Reparenting moves the frame between its parents' children, so GetChildren
-- and the OnShow / OnHide walk follow it. Measured on 70959 (WowTestKitProbe,
-- /fp steps tk reparent, 2026-11-18; WowTestKit #99):
-- - A frame whose visibility the move changes gets its OnShow / OnHide, and
--   so do its descendants, children first, during the call, with GetParent
--   already the new parent. A move that leaves it visible (or hidden) fires
--   nothing. The same held under a UIParent hidden by Alt+Z.
-- - Its frame level becomes the new parent's + 1 (0 with no parent), raised or
--   lowered (7 under a 10 became 11, 50 under a 3 became 4), and its child
--   moved with it, one above, every time (even after the frame's own
--   SetFrameLevel(50)). Here each descendant is put one above its parent; a
--   descendant given a level of its own wasn't measured.
-- - Measured, not modelled: a frame with SetFixedFrameLevel(true) kept its
--   level, and the frame took a HIGH parent's strata.
-- Takes w out of list; true if it was there.
local function takeOut(list, w)
    for i, c in ipairs(list or {}) do
        if c == w then table.remove(list, i); return true end
    end
    return false
end
-- Puts each of w's descendants one level above its parent.
local function relevel(w)
    for _, c in ipairs(w._children or {}) do
        c._level = w._level + 1
        relevel(c)
    end
end
function Methods.SetParent(w, p)
    local old = w._parent
    if old == p then return end
    w._parent = p
    if w._frame then
        -- A frame CreateFrame made: in its parent's children.
        if old then takeOut(old._children, w) end
        if p then p._children = p._children or {}; table.insert(p._children, w) end
    elseif old and takeOut(old._regions, w) then
        -- A texture or font string made by CreateTexture / CreateFontString:
        -- in its parent's regions. Another widget (a status bar's fill) was
        -- in no list, and joins none.
        if p then p._regions = p._regions or {}; table.insert(p._regions, w) end
    elseif old and takeOut(old._maskTextures, w) then
        -- A mask made by CreateMaskTexture: in its parent's masks (#82).
        if p then p._maskTextures = p._maskTextures or {}; table.insert(p._maskTextures, w) end
    end
    if w._frame then
        w._level = p and ((p._level or 0) + 1) or 0
        relevel(w)
        settle(w)   -- after the lists, so a script reads its new parent and siblings
    else
        resync(w)
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
-- The drag state a test reads (WowTestKit #89): w._moving from StartMoving,
-- w._sizing from StartSizing (w._sizingPoint its resize point), both false
-- after StopMovingOrSizing. The frame doesn't follow the cursor, and
-- StartMoving on a frame that isn't movable isn't refused (unmeasured).
-- StartMoving and StopMovingOrSizing are refused in combat on a protected
-- frame (WoW.PROTECTED), so a drag stopped then stays on. SetResizeBounds
-- is kept as given in w._resizeBounds ({ minW, minH, maxW, maxH }); sizes
-- aren't clamped to it.
function Methods.SetMovable(w, on) w._movable = on == true end
function Methods.IsMovable(w) return w._movable == true end
function Methods.StartMoving(w) w._moving = true end
function Methods.StartSizing(w, point) w._sizing, w._sizingPoint = true, point end
function Methods.StopMovingOrSizing(w) w._moving, w._sizing, w._sizingPoint = false, false, nil end
function Methods.SetResizeBounds(w, minW, minH, maxW, maxH) w._resizeBounds = { minW, minH, maxW, maxH } end
function Methods.GetName(w) return w._name end
function Methods.GetDebugName(w) return w._name or ("<" .. w._type .. ">") end
function Methods.GetObjectType(w) return w._type end
function Methods.IsForbidden(w) return false end
-- A frame's ID, 0 until set (WowTestKit #41): GetID returns a non-nilable
-- number (SimpleFrameAPIDocumentation.lua), which Blizzard's code compares
-- with 0 unchecked (SecureTemplates.lua:671, PartyFrame.lua:196); bag
-- windows keep the bag and slot in it (ContainerFrame.lua:1845). SetID is
-- a protected function there too; it isn't in WoW.PROTECTED, which holds
-- what was measured: a test relying on the refusal adds it.
function Methods.SetID(w, id) w._id = id end
function Methods.GetID(w) return w._id or 0 end

-- The widget hierarchy (WowTestKit #68): IsObjectType(t) is true for the
-- widget's own type and every type it derives from, so a CheckButton (an
-- action, stance or pet button) is a Button and a Frame, as on the client.
-- WoW.KIND_OF[type] is the type it derives from. Each pair is checked
-- against the build's method lists (tests/test_geometry.lua: the type has
-- every method of the one it derives from); Line and MaskTexture aren't
-- Textures there. Abstract types (Region, ScriptRegion, Object, ...) aren't
-- measured on Forever and read false; a stub that relies on one adds it
-- (WoW.KIND_OF.Texture = "Region"). The name is matched without case:
-- Blizzard's own code asks IsObjectType("frame") of a frame
-- (Blizzard_Dispatcher.lua:368, wow-ui-source forever 70959).
WoW.KIND_OF = {
    Button = "Frame", CheckButton = "Button",
    Model = "Frame", PlayerModel = "Model",
    CinematicModel = "PlayerModel", DressUpModel = "PlayerModel", TabardModel = "PlayerModel",
    Browser = "Frame", ColorSelect = "Frame", Cooldown = "Frame", EditBox = "Frame",
    GameTooltip = "Frame", MessageFrame = "Frame", Minimap = "Frame", ModelScene = "Frame",
    MovieFrame = "Frame", OffScreenFrame = "Frame", ScrollFrame = "Frame",
    ScrollingMessageFrame = "Frame", SimpleHTML = "Frame", Slider = "Frame", StatusBar = "Frame",
    UnitPositionFrame = "Frame",
}
for atype in pairs(Kit.ANIMATION_TYPES) do WoW.KIND_OF[atype] = "Animation" end
function Methods.IsObjectType(w, t)
    if type(t) ~= "string" then return false end
    t = t:lower()
    local k, seen = w._type, 0
    while k and seen < 16 do   -- a stub's cycle can't hang the test
        if k:lower() == t then return true end
        k, seen = WoW.KIND_OF[k], seen + 1
    end
    return false
end

-- Geometry as the client reports it (WowTestKit #68): plain fields a test
-- sets, in the widget's own units, nil while unset (no rect yet, as on the
-- client before layout). w._left, w._right, w._top, w._bottom are the
-- edges; GetCenter is their midpoint, nil unless all four are set.
-- w._escale, set, is the effective scale (below). A test may put a secret
-- in any of them; GetCenter then returns secrets. The core's secure handles read
-- these through the same methods ($cursor, GetMousePosition).
function Methods.GetLeft(w) return w._left end
function Methods.GetRight(w) return w._right end
function Methods.GetTop(w) return w._top end
function Methods.GetBottom(w) return w._bottom end
function Methods.GetCenter(w)
    local l, r, t, b = w._left, w._right, w._top, w._bottom
    if l == nil or r == nil or t == nil or b == nil then return nil end
    if issecretvalue(l) or issecretvalue(r) or issecretvalue(t) or issecretvalue(b) then
        return WoW.Secret("GetCenter x"), WoW.Secret("GetCenter y")
    end
    return (l + r) / 2, (b + t) / 2
end
-- Unset, it's the product of every SetScale up the parents, the widget's own
-- included (WowTestKit #89; porting guide, "GetCenter is in the frame's OWN
-- space": the client's GetScaledCenter does this, FrameUtil.lua:226), so 1
-- while nothing is scaled. A set w._escale wins over the chain.
function Methods.GetEffectiveScale(w)
    if w._escale ~= nil then return w._escale end
    local s, p, depth = 1, w, 0
    while p and depth < 64 do   -- a stub's cycle can't hang the test
        s, p, depth = s * (p._scale or 1), p._parent, depth + 1
    end
    return s
end
-- The pointer over the widget: w._mouseOver (true, or a secret, as the
-- dump's SecretWhenAnchoringSecret allows). The offsets aren't modelled.
function Methods.IsMouseOver(w)
    local v = w._mouseOver
    if issecretvalue(v) then return v end
    return v == true
end

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
-- The events the client refuses to register (WowTestKit #79): RegisterEvent
-- returns false without throwing, registers nothing, and the client raises
-- ADDON_ACTION_FORBIDDEN (not BLOCKED), recorded here in WoW.forbidden as
-- "name:RegisterEvent:EVENT". Measured: COMBAT_LOG_EVENT_UNFILTERED, though
-- the build's events.txt lists it (porting guide, "Registering
-- COMBAT_LOG_EVENT_UNFILTERED is itself a forbidden action"; Stakeout's
-- docs/FOREVER-PROBE.md). A consumer adds one it measured:
-- WoW.REFUSED_EVENTS.SOME_EVENT = true. RegisterUnitEvent isn't measured
-- with one, so it doesn't consult the set.
WoW.REFUSED_EVENTS = { COMBAT_LOG_EVENT_UNFILTERED = true }
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. tostring(e) .. "\"", 2) end
    if WoW.REFUSED_EVENTS[e] then
        table.insert(WoW.forbidden, (w._name or w._type) .. ":RegisterEvent:" .. e)
        return false
    end
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
    if name then publish(name, t) end
    return t
end
-- The template is a font (a font object's name, "GameFontNormal"): it gives
-- the font string its font (WowTestKit #69), kept in _fontTemplate.
function Methods.CreateFontString(w, name, layer, template)
    local fs = addRegion(w, newWidget("FontString", w, name))
    fs._fontTemplate = template
    if name then publish(name, fs) end
    return fs
end
-- A frame's mask textures, in creation order, are in w._maskTextures
-- (WowTestKit #82), so a test can walk the masks a frame made. Not in
-- w._regions, so GetRegions doesn't return them: whether the client's
-- GetRegions lists a MaskTexture is unmeasured, and Blizzard's source
-- (forever 70959) doesn't settle it (no caller of GetRegions there checks
-- for one, and the API documentation, SimpleFrameAPIDocumentation.lua,
-- doesn't say). Not to be mixed up with a texture's t._masks, the masks
-- AddMaskTexture put on it.
function Methods.CreateMaskTexture(w)
    local m = newWidget("MaskTexture", w)
    w._maskTextures = w._maskTextures or {}   -- a stub's own widget table
    table.insert(w._maskTextures, m)
    return m
end
function Methods.GetRegions(w) return unpack(w._regions or {}) end

-- Textures: one source at a time, as on the client (a file, an atlas or a colour).
function Methods.SetTexture(t, file) t._file, t._atlas, t._color = file, nil, nil; return true end
-- The file SetTexture set, nil for an atlas or a colour (WowTestKit #89;
-- what the client returns for an atlas isn't measured).
function Methods.GetTexture(t) return t._file end
-- No return value (the dump declares none): ask C_Texture.GetAtlasInfo first.
function Methods.SetAtlas(t, name) t._atlas, t._file, t._color = name, nil, nil end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a }; t._file, t._atlas = nil, nil end
function Methods.SetBlendMode(t, mode) t._blend = mode end
function Methods.SetVertexColor(t, r, g, b, a) t._vertex = { r, g, b, a } end
-- The colour SetVertexColor set (WowTestKit #97): four numbers, never nil
-- (SimpleRegionAPIDocumentation.lua, forever 70959). Unset, it reads white,
-- and an alpha left out of SetVertexColor (it's nilable there) reads 1:
-- neither default is measured.
function Methods.GetVertexColor(t)
    local v = t._vertex or { 1, 1, 1, 1 }
    return v[1], v[2], v[3], v[4] or 1
end
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
-- How many masks AddMaskTexture put on it, 0 for none (WowTestKit #97).
function Methods.GetNumMaskTextures(t) return t._masks and #t._masks or 0 end
-- Takes that mask off (WowTestKit #68); one it doesn't have is ignored.
function Methods.RemoveMaskTexture(t, m)
    for i, x in ipairs(t._masks or {}) do
        if x == m then table.remove(t._masks, i); return end
    end
end

-- Text. An EditBox runs its OnTextChanged on SetText, as the client does.
-- A FontString with no font refuses SetText (WowTestKit #69): on 70959 it
-- throws "FontString:SetText(): Font not set" (measured in LibGlass's probe,
-- /fp steps lg button, 2026-11-18: hotkey and count strings made with
-- CreateFontString(nil, "OVERLAY") and no template). A font comes from
-- SetFont, SetFontObject or CreateFontString's template. Every text throws
-- here, "" and nil too: the check is on the font, but only a non-empty text
-- was measured. SetFormattedText isn't measured and doesn't throw here. An
-- EditBox, a Button or a SimpleHTML isn't a FontString, and isn't affected.
-- The error names the caller's line: level 3, since the method dispatch
-- tail-calls this, and Lua 5.1 leaves a tail-call frame at level 2.
function Methods.SetText(fs, text)
    -- A GameTooltip's text is its first line, the others cleared (its lines, below).
    if fs._type == "GameTooltip" then fs._lines, fs._linesRight = { text }, {}; return end
    if fs._type == "FontString" and fs._font == nil and fs._fontObject == nil and fs._fontTemplate == nil then
        error("FontString:SetText(): Font not set", 3)
    end
    fs._text = text
    if fs._type == "EditBox" and fs._scripts.OnTextChanged then fs._scripts.OnTextChanged(fs, false) end
end
function Methods.GetText(fs) return fs._text end
-- String metrics (WowTestKit #89). The client measures the text in its font;
-- the core can't, so these are a deterministic APPROXIMATION, not measured:
-- 6 units per character (bytes, escape codes included) and 14 per line.
-- GetStringWidth is the longest line's ("\n" breaks a line), not wrapped.
-- GetStringHeight wraps each line at the width set (SetWidth / SetSize:
-- floor(width / 6) characters a line), unwrapped with no width; 0 with no
-- text. A secret text (SetFormattedText) reads as none. A consumer that
-- needs other numbers replaces WoW.Methods.GetStringWidth / GetStringHeight.
local function textLines(fs)
    local text = fs._text
    if type(text) == "number" then text = tostring(text) end
    if type(text) ~= "string" or text == "" then return {} end
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    return lines
end
function Methods.GetStringWidth(fs)
    local widest = 0
    for _, line in ipairs(textLines(fs)) do widest = math.max(widest, #line) end
    return widest * 6
end
function Methods.GetStringHeight(fs)
    local perLine = (fs._width or 0) > 0 and math.max(1, math.floor(fs._width / 6)) or math.huge
    local n = 0
    for _, line in ipairs(textLines(fs)) do n = n + math.max(1, math.ceil(#line / perLine)) end
    return n * 14
end
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
-- The clicks the button takes, as given (WowTestKit #89): w._registeredClicks,
-- { "AnyUp" } or { "LeftButtonDown", "RightButtonDown" }; a later call
-- replaces them. Refused in combat on a protected button (WoW.PROTECTED).
function Methods.RegisterForClicks(b, ...) b._registeredClicks = { ... } end
-- A button's state textures (WowTestKit #70): Set<State>Texture(asset)
-- sets the file on the button's own texture for that state, a Texture made
-- on first use with the button as parent, as SetTexture does (one source at
-- a time); Get<State>Texture returns it, nil until set. Given a Texture, the
-- button takes that texture. SetHighlightTexture's blend mode, when given,
-- is set on it, as SetBlendMode does. A nil asset with no texture yet makes
-- none. Normal, Pushed, Highlight and Disabled (SimpleButtonAPI) and a
-- CheckButton's Checked (SimpleCheckboxAPI): the states consumers' stubs
-- had (GlassActionBars', Apotheca's, LibGlass's). Not modelled: Clear*Texture,
-- the textures' draw layers, a default blend mode, and whether they're in
-- the button's GetRegions (unmeasured: here they aren't).
local function setStateTexture(b, key, asset, blend)
    if type(asset) == "table" then
        b[key] = asset
    elseif asset ~= nil or b[key] then
        b[key] = b[key] or newWidget("Texture", b)
        Methods.SetTexture(b[key], asset)
    end
    if blend ~= nil and b[key] then Methods.SetBlendMode(b[key], blend) end
end
for _, state in ipairs({ "Normal", "Pushed", "Highlight", "Disabled", "Checked" }) do
    local key = "_" .. state:lower() .. "Texture"
    Methods["Set" .. state .. "Texture"] = function(b, asset, blend)
        setStateTexture(b, key, asset, state == "Highlight" and blend or nil)
    end
    Methods["Get" .. state .. "Texture"] = function(b) return b[key] end
end
-- CheckButton.
function Methods.SetChecked(b, v) b._checked = v and true or false end
function Methods.GetChecked(b) return b._checked == true end
-- StatusBar and Slider. A slider's SetValue fires OnValueChanged on a change,
-- as the client's does.
function Methods.SetMinMaxValues(b, lo, hi) b._min, b._max = lo, hi end
-- 0, 0 until set (WowTestKit #89); a StatusBar starts at 0, 1 (CreateFrame).
function Methods.GetMinMaxValues(b) return b._min or 0, b._max or 0 end
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
-- A model scene's actors (WowTestKit #90), kept in scene._actors in creation
-- order, as AltStable's and Gnomesweeper's stubs did. A widget of type
-- ModelSceneActor, so Kit.checkMethods checks its calls against the build's
-- ModelSceneActor pairs (the dump's FrameAPIModelSceneFrameActor and ...Base
-- functions); the client's GetObjectType() for an actor is unmeasured. Like an
-- animation, it isn't a frame: not in WoW.frames or the scene's _children, so
-- no event, OnUpdate or OnShow / OnHide walk reaches it. Its name isn't made
-- a global and its template adds nothing (neither measured).
function Methods.CreateActor(scene, name, template)
    local a = newWidget("ModelSceneActor", scene, name)
    a._template = template
    scene._actors = scene._actors or {}   -- a stub's own scene table
    table.insert(scene._actors, a)
    return a
end

-- GameTooltip's own (C) lines and owner (WowTestKit #89), the model
-- Shatter's, GlassMiniMap's, GlassPanel's, GlassPearls' and GlassUI's stubs
-- shared; not measured on Forever. tt._lines holds each line's left text, in
-- order, and tt._linesRight[i] the right text of an AddDoubleLine (nil for a
-- single line). Colours and wrapping aren't kept. SetText (above) makes the
-- text the only line; SetOwner takes the owner and clears the lines, as
-- re-owning a tooltip starts it again; ClearLines clears them. Neither
-- shows or hides the tooltip. The setters from TooltipDataHandlerMixin
-- (SetItemByID...) are Lua and the consumer's (Kit.allowMethods).
local function tooltipLines(tt)
    tt._lines, tt._linesRight = tt._lines or {}, tt._linesRight or {}
    return tt._lines, tt._linesRight
end
function Methods.SetOwner(tt, owner, anchor, x, y)
    tt._owner, tt._ownerAnchor = owner, { anchor, x, y }
    tt._lines, tt._linesRight = {}, {}
end
function Methods.GetOwner(tt) return tt._owner end
function Methods.AddLine(tt, text)
    local left = tooltipLines(tt)
    left[#left + 1] = text
end
function Methods.AddDoubleLine(tt, leftText, rightText)
    local left, right = tooltipLines(tt)
    left[#left + 1] = leftText
    right[#left] = rightText
end
function Methods.ClearLines(tt) tt._lines, tt._linesRight = {}, {} end
function Methods.NumLines(tt) return #(tt._lines or {}) end

-- ScrollFrame (WowTestKit #89): the scroll child as set (not reparented
-- here), and the vertical offset, 0 until set. A change fires the frame's
-- OnVerticalScroll(offset): Blizzard's scroll bars rely on it (the bar's
-- OnValueChanged only calls SetVerticalScroll, and the frame's
-- OnVerticalScroll updates the bar and its buttons: SecureScrollTemplates.lua
-- :23 and :134, wow-ui-source forever 70959; read, not measured). The
-- offset isn't clamped. GetVerticalScrollRange reads w._yrange, a test's,
-- 0 unset.
function Methods.SetScrollChild(sf, child) sf._scrollChild = child end
function Methods.GetScrollChild(sf) return sf._scrollChild end
function Methods.SetVerticalScroll(sf, offset)
    local old = sf._verticalScroll or 0
    sf._verticalScroll = offset
    if offset ~= old and sf._scripts.OnVerticalScroll then sf._scripts.OnVerticalScroll(sf, offset) end
end
function Methods.GetVerticalScroll(sf) return sf._verticalScroll or 0 end
function Methods.GetVerticalScrollRange(sf) return sf._yrange or 0 end

-- EditBox focus (WowTestKit #89): one edit box at a time has the keyboard
-- focus, WoW.focus (the client's GetCurrentKeyBoardFocus is one frame).
-- SetFocus takes it from the one that had it (its OnEditFocusLost first),
-- then fires OnEditFocusGained; ClearFocus fires OnEditFocusLost. Each only
-- on a change. Which script runs first isn't measured, and hiding an edit
-- box doesn't take its focus here (unmodelled). WoW.reset() clears it.
function Methods.SetFocus(e)
    if WoW.focus == e then return end
    if WoW.focus then Methods.ClearFocus(WoW.focus) end
    WoW.focus = e
    if e._scripts.OnEditFocusGained then e._scripts.OnEditFocusGained(e) end
end
function Methods.ClearFocus(e)
    if WoW.focus ~= e then return end
    WoW.focus = nil
    if e._scripts.OnEditFocusLost then e._scripts.OnEditFocusLost(e) end
end
function Methods.HasFocus(e) return WoW.focus == e end

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
-- The client's locale code (dump: GetLocale() -> localeName:cstring). A test
-- sets WoW.locale ("deDE", "koKR"...); enUS until it does (WowTestKit #62).
function GetLocale() return WoW.locale or "enUS" end
function InCombatLockdown() return WoW.combat == true end
-- Client string alias (in the dump's _G walk); LibStub's version check uses it.
strmatch = string.match

-- The client's secure hook replaces t[name] with a wrapper: the sanctioned way
-- to hook a Blizzard function. WoW.hooked[t][name] counts the hooks, so a
-- "no field written" check can tell a hook from a field the addon wrote.
-- A hook on a widget goes in its call log (w._log, WowTestKit #67), so a
-- parity test compares the hooks installed too.
WoW.hooked = {}
local function pack(...) return { n = select("#", ...), ... } end
function hooksecurefunc(t, name, fn)
    if type(t) == "string" then t, name, fn = _G, t, name end
    if isWidget(t) then log(t, "hooksecurefunc:" .. tostring(name)) end
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
-- - WoW.advance(dt): a clock. The timers due by now + dt run in the order
--   they fall due, each with WoW.now at its due time (or now, if it was
--   already overdue), as on the client a C_Timer.After(2, fn) runs at about
--   2 s and reads that from GetTime(); a timer scheduled inside one counts
--   from that time. Then WoW.now is now + dt (WowTestKit #86). So one long
--   advance runs what stepping through it would, 0-second tickers aside.
--
-- A ticker repeats, as on the client (WowTestKit #18): it stays in
-- WoW.timers after it fires, until cancelled or its iterations are used up.
-- Its handle has Cancel and IsCancelled, and the callback gets the handle
-- (UITimerDocumentation: NewTicker's callback is a TickerCallback(cb)).
-- - advance re-arms it at at + every, so a dt spanning several periods
--   fires it once per period (a 0-second ticker once per advance,
--   advance(0) included: one advance is one frame for it);
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
    WoW.now = WoW.now or 0
    local target = WoW.now + dt
    local once = {}   -- the 0-second tickers this advance has fired
    while true do
        local due, at
        for i, t in ipairs(WoW.timers) do
            local tAt = t.at or t.s or 0
            if tAt <= target and not once[t] and (not at or tAt < at) then due, at = i, tAt end
        end
        if not due then break end
        local t = table.remove(WoW.timers, due)
        if at > WoW.now then WoW.now = at end   -- never back: max(due, now)
        -- A 0-second ticker is due again at once: on the client it fires once
        -- a frame, so here once an advance, advance(0) included (WowTestKit
        -- #76). It is re-armed at the time it fired, so the next advance
        -- fires it first thing, with the clock where that advance started.
        local nextAt = at + (t.every or 0)
        if t.every and t.every <= 0 then once[t], nextAt = true, WoW.now end
        fireTimer(t, nextAt)   -- a cancelled one never fires
    end
    if WoW.now < target then WoW.now = target end   -- a callback's own advance may be past it
end

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- SecureStateDriverManager's OnUpdate and OnEvent (#77, below).
local driveStates, wakeStateDrivers

-- Fire an event at every frame registered for it. Errors are NOT caught: a
-- handler that throws fails the test.
function WoW.fire(event, ...)
    wakeStateDrivers(event)
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
-- WoW.fireAllRegistered(units) (WowTestKit #94): a list of units for the
-- plain registrations too, as the client sends a plainly registered unit
-- event once per unit, with it as payload. An event some frame registered
-- plainly fires once per unit in the list, as well as for its
-- RegisterUnitEvent units; the kit can't tell a unit event from another, so
-- every plain event gets them. Events in name order, each one's units in
-- sorted order (once each); an event with no unit fires once with no
-- payload, as without a list. Returns the events fired, sorted.
function WoW.fireAllRegistered(plainUnits)
    if plainUnits ~= nil and type(plainUnits) ~= "table" then
        error("WoW.fireAllRegistered: units must be a list, got " .. type(plainUnits), 2)
    end
    local seen, units = {}, {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do
            seen[e] = true
            for _, u in ipairs(plainUnits or {}) do
                units[e] = units[e] or {}
                units[e][u] = true
            end
        end
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

-- OnUpdate on every visible frame made so far, with elapsed.
local function runOnUpdates(elapsed)
    driveStates(elapsed)   -- Blizzard's frame, made before any addon's (the order isn't measured)
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

-- One rendered frame: the clock moves on by elapsed, then OnUpdate runs on
-- every visible frame with it. On the client a frame's elapsed and GetTime()
-- move together, so code that times something by GetTime() inside its
-- OnUpdate sees time pass (WowTestKit #9). A tick runs no timer: WoW.step
-- below is a frame with its timers.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    WoW.now = (WoW.now or 0) + elapsed
    runOnUpdates(elapsed)
end

-- One rendered frame with its timers (WowTestKit #66): the timers due by
-- now + dt run at their due times (WoW.advance), then OnUpdate runs with
-- the same dt. The clock moves once. WoW.advance(dt) then WoW.tick(0) is
-- not the same: every OnUpdate gets elapsed = 0, so one that adds up elapsed
-- to throttle itself (`self.t = self.t + elapsed; if self.t < 0.1 then
-- return end`) never runs (Apotheca#99: 14 test files failed that way).
-- Timers before OnUpdate within the frame is the order consumers' own step
-- helpers used; the client's order inside one frame isn't measured.
function WoW.step(dt)
    dt = dt or 0.02
    WoW.advance(dt)
    runOnUpdates(dt)
end

--------------------------------------------------------------------------------
-- Secure handlers (WowTestKit #20), from the client's own source
-- (wow-ui-source forever, 70862: Blizzard_RestrictedAddOnEnvironment's
-- SecureHandlers.lua, RestrictedFrames.lua, RestrictedExecution.lua,
-- RestrictedEnvironment.lua; Blizzard_FrameXML's SecureTemplates.lua).
-- Secure snippets run on Forever since 70425, in combat too (porting guide,
-- "Secure click-casting works").
--
-- Modelled: SecureHandlerWrapScript / UnwrapScript on OnClick, OnEnter,
-- OnLeave, OnShow and OnHide (#93), SecureHandlerSetFrameRef,
-- SecureHandlerExecute, one environment per protected frame, frame handles
-- with the methods below, the secure action button's own click
-- (WoW.secureActionClick, with modified attributes: *type1, shift-type1...,
-- #88), and WoW.click / WoW.pressKey / WoW.enter / WoW.leave to drive them.
-- Not modelled: other wrapped scripts (OnDoubleClick, PreClick, PostClick,
-- OnDragStart, OnReceiveDrag, OnMouseWheel, OnAttributeChanged), the header
-- templates' own snippet attributes (_onclick, _onstate-...), and a
-- snippet's error being caught (here it fails the test).
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

-- UIPanelScrollFrameTemplate's frames (WowTestKit #66), from the client's
-- source (wow-ui-source forever, 70959: Blizzard_SharedXML's
-- SecureScrollTemplates.xml:44, the ScrollBar Slider at :46, its
-- UIPanelScrollBarTemplate at :7): sf.ScrollBar ("$parentScrollBar"), and on
-- it ScrollUpButton and ScrollDownButton ("$parentScrollUpButton",
-- "$parentScrollDownButton"). Their scripts, anchors, sizes and thumb
-- texture aren't modelled. Without it, sf.ScrollBar reads nil and code
-- testing `if sf.ScrollBar then` takes the branch the client never runs.
WoW.templates.UIPanelScrollFrameTemplate = function(sf)
    local function named(parent, suffix) return parent._name and (parent._name .. suffix) end
    local bar = CreateFrame("Slider", named(sf, "ScrollBar"), sf)
    sf.ScrollBar = bar
    bar.ScrollUpButton = CreateFrame("Button", named(bar, "ScrollUpButton"), bar)
    bar.ScrollDownButton = CreateFrame("Button", named(bar, "ScrollDownButton"), bar)
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
function HANDLE:IsObjectType(t) return Methods.IsObjectType(anyFrameOf(self), t) end
function HANDLE:GetAttribute(k) local w = frameOf(self); return w._attrs and w._attrs[k] end
-- RestrictedFrames.lua:522: a name starting with "_" is the frame's own
-- (snippets, private state) and refused; a value is a string, number,
-- boolean, nil or a frame handle, never a table (#43).
function HANDLE:SetAttribute(k, v)
    if type(k) ~= "string" or k:match("^_") then error("Invalid attribute name", 2) end
    local tv = type(v)
    if tv ~= "string" and tv ~= "number" and tv ~= "boolean" and tv ~= "nil"
            and not (tv == "userdata" and handleFrame[v]) then
        error("Invalid attribute value", 2)
    end
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
-- RestrictedFrames.lua:446 (#44): relPoint may be left out (the offsets
-- move up) and defaults to point; the offsets default to 0. Both points are
-- one of the nine anchor names. The relative frame is a handle to a
-- PROTECTED frame, in or out of combat ("**MUST** be protected"), or nil /
-- "$screen" (the screen), "$parent", or "$cursor" (the cursor, as an offset
-- from the screen's bottom left).
local SET_POINTS = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true,
                     TOPLEFT = true, BOTTOMLEFT = true, TOPRIGHT = true, BOTTOMRIGHT = true }
function HANDLE:SetPoint(point, rel, relPoint, x, y)
    if type(relPoint) == "number" then relPoint, x, y = nil, relPoint, x end
    if relPoint == nil then relPoint = point end
    if x == nil and y == nil then x, y = 0, 0 else x, y = tonumber(x), tonumber(y) end
    if not SET_POINTS[point] then error("Invalid point '" .. tostring(point) .. "'", 2) end
    if not SET_POINTS[relPoint] then error("Invalid relative point '" .. tostring(relPoint) .. "'", 2) end
    if not (x and y) then error("Invalid offset", 2) end
    local w = frameOf(self)
    local relFrame
    if type(rel) == "userdata" then
        relFrame = handleFrame[rel]
        if not relFrame or not relFrame._protected then error("Invalid relative frame handle", 2) end
    elseif rel == nil or rel == "$screen" then
        relFrame = nil
    elseif rel == "$cursor" then
        local e = Methods.GetEffectiveScale(w)
        local cx, cy = GetCursorPosition()
        x, y, relPoint, relFrame = x + cx / e, y + cy / e, "BOTTOMLEFT", nil
    elseif rel == "$parent" then
        relFrame = w._parent
    else
        error("Invalid relative frame id '" .. tostring(rel) .. "'", 2)
    end
    anchor(w, point, relFrame, relPoint, x, y)   -- one anchor per point (#92)
end
function HANDLE:GetWidth() return frameOf(self)._width end
function HANDLE:GetHeight() return frameOf(self)._height end
function HANDLE:SetWidth(v) frameOf(self)._width = v end
function HANDLE:SetHeight(v) frameOf(self)._height = v end
-- RestrictedFrames.lua:108 and :410: a non-number id sets 0.
function HANDLE:GetID() return Methods.GetID(frameOf(self)) end
function HANDLE:SetID(id) frameOf(self)._id = tonumber(id) or 0 end
-- The cursor as a fraction of the frame's rect, nil outside it
-- (RestrictedFrames.lua:307): GetCursorPosition() over the effective scale,
-- less the rect's left and bottom. The rect: GetLeft / GetBottom (0 unset)
-- and the frame's size; the effective scale: GetEffectiveScale (#68).
function HANDLE:GetMousePosition()
    local w = frameOf(self)
    local width, height = w._width, w._height
    if not width or not height or width == 0 or height == 0 then return nil end
    local e = Methods.GetEffectiveScale(w)
    local x, y = GetCursorPosition()
    x, y = x / e - (Methods.GetLeft(w) or 0), y / e - (Methods.GetBottom(w) or 0)
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
-- A snippet run in this frame's environment, with this handle as control
-- and another frame's handle (or nil) as self (RestrictedFrames.lua:725).
function HANDLE:RunFor(other, body, ...)
    local w = frameOf(self)
    if other ~= nil and not (type(other) == "userdata" and handleFrame[other]) then
        error("Invalid handle for other frame", 2)
    end
    if type(body) ~= "string" then error("Invalid function body", 2) end
    return runSnippet(envOf(w), w, "self,...", body, other, ...)
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

-- Wrapped_OnEnter / Wrapped_OnLeave (SecureHandlers.lua:292, :312, #93):
-- the pre snippet runs (self only) when motion is true, an enter marks the
-- frame entered (its _wrapentered attribute, set from secure code), and a
-- leave runs it only on an entered frame and clears the mark; false
-- cancels. Then the script that was there (with motion), then the post
-- snippet (self, message) when the pre gave a message.
local function wrappedEnter(wrap, self, motion, ...)
    local allow, message
    if motion then
        self._attrs = self._attrs or {}
        self._attrs._wrapentered = true
        if not WoW.combat or isProtected(self) then
            allow, message = runSnippet(envOf(wrap.header), wrap.header, "self", wrap.pre, handleOf(self))
        end
        if allow == false then return end
    end
    if wrap.old then wrap.old(self, motion, ...) end
    if wrap.post and message ~= nil then
        runSnippet(envOf(wrap.header), wrap.header, "self,message", wrap.post, handleOf(self), message)
    end
end
local function wrappedLeave(wrap, self, motion, ...)
    local allow, message
    if motion and self._attrs and self._attrs._wrapentered then
        self._attrs._wrapentered = nil
        if not WoW.combat or isProtected(self) then
            allow, message = runSnippet(envOf(wrap.header), wrap.header, "self", wrap.pre, handleOf(self))
            if allow == false then return end
        end
    end
    if wrap.old then wrap.old(self, motion, ...) end
    if wrap.post and message ~= nil then
        runSnippet(envOf(wrap.header), wrap.header, "self,message", wrap.post, handleOf(self), message)
    end
end
-- Wrapped_ShowHide (SecureHandlers.lua:349, #93): the pre snippet (self)
-- when eligible, false cancels, the script, the post (self, message).
local function wrappedShowHide(wrap, self, ...)
    local allow, message
    if not WoW.combat or isProtected(self) then
        allow, message = runSnippet(envOf(wrap.header), wrap.header, "self", wrap.pre, handleOf(self))
        if allow == false then return end
    end
    if wrap.old then wrap.old(self, ...) end
    if wrap.post and message ~= nil then
        runSnippet(envOf(wrap.header), wrap.header, "self,message", wrap.post, handleOf(self), message)
    end
end
-- The scripts the core wraps (SecureHandlers.lua:396's LOCAL_Wrap_Handlers).
local WRAPPERS = { OnClick = wrappedClick, OnEnter = wrappedEnter, OnLeave = wrappedLeave,
                   OnShow = wrappedShowHide, OnHide = wrappedShowHide }

local wraps = setmetatable({}, { __mode = "k" })   -- wrapper function -> its wrap
function SecureHandlerWrapScript(frame, script, header, preBody, postBody)
    if type(frame) ~= "table" then error("Invalid frame", 2) end
    if type(script) ~= "string" then error("Invalid script id", 2) end
    local wrapper = WRAPPERS[script]
    if not wrapper then error("WowTestKit wraps OnClick, OnEnter, OnLeave, OnShow and OnHide only (#93): " .. script, 2) end
    if type(header) ~= "table" or not header._protected then error("Header frame must be explicitly protected", 2) end
    if type(preBody) ~= "string" then error("Invalid pre-handler body", 2) end
    if postBody ~= nil and type(postBody) ~= "string" then error("Invalid post-handler body", 2) end
    if apiRefused("SecureHandlerWrapScript") then return end
    local wrap = { header = header, pre = preBody, post = postBody, old = frame._scripts[script] }
    local fn = function(self, ...) return wrapper(wrap, self, ...) end
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

-- Modified attributes (WowTestKit #88): SecureButton_GetModifiedAttribute
-- (SecureTemplates.lua:119, wow-ui-source forever 70959). The prefix is the
-- modifiers held, "alt-ctrl-shift-" in that order (:70), read from the
-- stub's IsAltKeyDown / IsControlKeyDown / IsShiftKeyDown when it defines
-- them (none held otherwise); the suffix is the mouse button's number
-- (LeftButton 1, RightButton 2, MiddleButton 3, Button4..31 its number,
-- any other "-<button>": :101). The lookup is the C side's
-- GetAttribute(prefix, name, suffix), not in the Lua source; its order is
-- the Warcraft wiki's (SecureActionButtonTemplate, "Modified attributes"):
-- prefix..name..suffix, "*"..name..suffix, prefix..name.."*",
-- "*"..name.."*", name, which fits SecureTemplates.lua:4-28's comment.
-- Nothing there: useparent-<name> / useparent* ask the parent (or
-- frame.bar). ATTRIBUTE_NOOP ("") reads nil. The "modifiers" attribute
-- (IsModifiedClick) isn't modelled: a button that sets it is an error.
local MOUSE_SUFFIX = { LeftButton = "1", RightButton = "2", MiddleButton = "3" }
local function buttonSuffix(button)
    if MOUSE_SUFFIX[button] then return MOUSE_SUFFIX[button] end
    if button and button ~= "" then
        local n = tonumber(tostring(button):match("^Button(%d+)$"))
        if n and n >= 4 and n <= 31 then return tostring(n) end
        return "-" .. tostring(button)
    end
    return ""
end
local function modifierPrefix(frame)
    if frame._attrs and frame._attrs.modifiers ~= nil then
        error("WowTestKit doesn't model the modifiers attribute (IsModifiedClick) (#88)", 0)
    end
    local function held(name) local fn = rawget(_G, name); return fn and fn() end
    local prefix = ""
    if held("IsShiftKeyDown") then prefix = "shift-" .. prefix end
    if held("IsControlKeyDown") then prefix = "ctrl-" .. prefix end
    if held("IsAltKeyDown") then prefix = "alt-" .. prefix end
    return prefix
end
local function modifiedAttribute(frame, name, button, prefix, suffix)
    prefix = prefix or modifierPrefix(frame)
    suffix = suffix or buttonSuffix(button)
    local a = frame._attrs or {}
    local value = a[prefix .. name .. suffix]
    if value == nil then value = a["*" .. name .. suffix] end
    if value == nil then value = a[prefix .. name .. "*"] end
    if value == nil then value = a["*" .. name .. "*"] end
    if value == nil then value = a[name] end
    if not value and (a["useparent-" .. name] or a["useparent*"]) then
        local parent = frame.bar or frame._parent
        if parent then value = modifiedAttribute(parent, name, button, prefix, suffix) end
    end
    if value == "" then value = nil end
    return value
end

-- The secure action button's own OnClick (SecureActionButton_OnClick,
-- SecureTemplates.lua:802): it acts only on the edge where down ==
-- useOnKeyDown (the attribute, else the ActionButtonUseKeyDown CVar:
-- WoW.useKeyDown; a pressAndHoldAction attribute makes it the down edge).
-- Measured on Forever, so one click uses an item once (Apotheca AGENTS.md,
-- "Secure buttons register both mouse edges"). The other edge, when it's the
-- up one, is the press-and-hold release under pressAndHoldAction or the
-- ActionButtonUseKeyHeldSpell CVar (WoW.useKeyHeldSpell): it acts on
-- typerelease, never type (porting guide, "Registering both edges"), and
-- does nothing without one. Every attribute is resolved as a modified
-- attribute for the button (above); on the down edge a downbutton attribute
-- remaps the button first. What it did goes to WoW.secureActions, with the
-- resolved values (release = true for a typerelease); an edge whose type
-- resolves to nothing does nothing (PerformAction, :730) and records
-- nothing. Returns whether it took the edge. Not modelled: unitsuffix, the harmbutton / helpbutton
-- remap, mouseover / self / focus cast, the unit having to exist, the
-- item's bag / slot fallback, and the client's real mouse press (always on
-- the up edge): every click here is an addon's or a key's.
local function recordAction(self, button, mouse, actionType, release)
    local function get(name) return modifiedAttribute(self, name, button) end
    table.insert(WoW.secureActions, {
        button = self._name, mouse = mouse, type = actionType, item = get("item"), spell = get("spell"),
        macro = get("macro"), macrotext = get("macrotext"), unit = get("unit"),
        targetBag = get("target-bag"), targetSlot = get("target-slot"), release = release,
    })
end
function WoW.secureActionClick(self, button, down)
    local pressAndHold = modifiedAttribute(self, "pressAndHoldAction", nil, "", "")
    local onDown = modifiedAttribute(self, "useOnKeyDown", nil, "", "")
    if onDown == nil then onDown = WoW.useKeyDown end
    onDown = (onDown or pressAndHold) and true or false
    if (down and true or false) == onDown then
        local effective = button
        if down then effective = modifiedAttribute(self, "downbutton", button) or button end
        local actionType = modifiedAttribute(self, "type", effective)
        if actionType then recordAction(self, effective, button, actionType) end
        return true
    elseif not down and (pressAndHold or WoW.useKeyHeldSpell) then
        local actionType = modifiedAttribute(self, "typerelease", button)
        if actionType then recordAction(self, button, button, actionType, true) end
        return true
    end
    return false
end

-- One edge of a click on a button, as the client runs it: PreClick, OnClick
-- (a wrap's snippets and the secure action inside it), PostClick. A disabled
-- button doesn't click. Button:Click(button, down) does the same.
-- A CheckButton's click toggles its checked state first, so OnClick reads
-- the new one (WowTestKit #87; Blizzard's handlers rely on it:
-- CinematicsMenuSubtitlesCheckboxMixin:OnClick saves self:GetChecked(),
-- Blizzard_GlueXML/Mainline/CinematicsMenu.lua:276, wow-ui-source forever
-- 70959). Unmeasured: whether PreClick already sees it, and which edge of
-- a mouse click toggles; here each call is one click, and toggles once.
function WoW.click(b, button, down)
    button, down = button or "LeftButton", down and true or false
    if b._disabled then return end
    if b._type == "CheckButton" then b._checked = not b._checked end
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

-- The pointer enters or leaves a frame (#93): its OnEnter / OnLeave with
-- motion (true unless given: a mouse move; false is a frame appearing under
-- or leaving the cursor). Whether the frame takes the mouse isn't checked,
-- and IsMouseOver doesn't follow (w._mouseOver).
function WoW.enter(w, motion)
    if motion == nil then motion = true end
    if w._scripts.OnEnter then w._scripts.OnEnter(w, motion) end
end
function WoW.leave(w, motion)
    if motion == nil then motion = true end
    if w._scripts.OnLeave then w._scripts.OnLeave(w, motion) end
end

-- The cursor, in screen pixels (GetCursorPosition). A stub may set it, or
-- define GetCursorPosition itself.
WoW.cursorX, WoW.cursorY = WoW.cursorX or 0, WoW.cursorY or 0
function GetCursorPosition() return WoW.cursorX, WoW.cursorY end

--------------------------------------------------------------------------------
-- Secure state drivers (WowTestKit #77), from the client's own source
-- (wow-ui-source forever, 70959: Blizzard_RestrictedAddOnEnvironment's
-- SecureStateDriver.lua). They work on Forever since 70425, in combat too
-- (porting guide, "Secure click-casting works": a RegisterStateDriver's
-- "[combat] in; out" delivered out, then in in combat).
--
-- RegisterStateDriver(f, s, v) is RegisterAttributeDriver(f, "state-" .. s,
-- v). The driver is resolved at once, then by SecureStateDriverManager's
-- OnUpdate every 0.2 s (here: on WoW.tick / WoW.step, before the frames'
-- own OnUpdate), and on the next frame after one of the events below
-- (WoW.fire of PLAYER_REGEN_DISABLED... sets its timer to 0). So a test that
-- enters combat fires PLAYER_REGEN_DISABLED then steps, or steps 0.2 s.
-- "state-visibility": "show" / "hide" show or hide the frame from secure code
-- (no combat refusal: WoW.setShown) and clear or set "statehidden". Any other
-- attribute gets the value ("nil" clears it, a number string is a number).
-- Not modelled: OnAttributeChanged (so a state header's _onstate-<s>
-- snippet), which the core's SetAttribute fires nowhere; RegisterUnitWatch.
-- The registration goes through SecureStateDriverManager:SetAttribute, a
-- protected frame's (SecureFrameTemplate): from addon code in combat that's
-- refused, so it does nothing and is recorded in WoW.blocked (read in the
-- source, not measured). WoW.stateDrivers[frame][attribute] is the values.
--------------------------------------------------------------------------------

-- The macro conditions (SecureCmdOptionParse, a C function: not in the
-- Lua source). "[c1,c2][c3] a; [c4] b; c": the first clause one of whose
-- [...] groups holds (every condition in it true) gives its value, trimmed;
-- a clause with no group, or "[]", always holds. Returns the value and the
-- group's target (@unit or target=unit), or nil when no clause holds. A
-- clause that holds with no value gives "" (Blizzard's slash commands test
-- the result for truth: SlashCommands.lua:359).
-- WoW.CONDITIONS[name](args, target) says whether a condition holds: args is
-- its ":a/b" list (nil without one). "no<name>" is its negation. The core
-- has [combat] (WoW.combat); a stub adds the others it relies on
-- (WoW.CONDITIONS.mod, .exists, ...), and any other is an error naming it.
-- [group], [party] and [raid] read false in combat whatever the stub says
-- (measured on 70425 and 70450, porting guide, "Secure click-casting works":
-- [@mouseover,party] and a state driver's [group:raid] read false in combat).
WoW.CONDITIONS = {
    combat = function() return WoW.combat == true end,
}
WoW.FALSE_IN_COMBAT = { group = true, party = true, raid = true }

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function condition(c, target)
    local neg, name, args = false, c:match("^([%w_]+)%s*:?%s*(.-)$")
    if not name then error("SecureCmdOptionParse: can't read the condition [" .. c .. "]", 0) end
    name = name:lower()
    if not WoW.CONDITIONS[name] and not WoW.FALSE_IN_COMBAT[name] and name:match("^no.") then
        neg, name = true, name:sub(3)
    end
    local list
    if args ~= "" then
        list = {}
        for a in args:gmatch("[^/]+") do list[#list + 1] = trim(a) end
    end
    local holds
    if WoW.FALSE_IN_COMBAT[name] and WoW.combat then
        holds = false
    else
        local fn = WoW.CONDITIONS[name]
        if not fn then
            error("WowTestKit doesn't model the [" .. name .. "] condition (#77): the stub adds WoW.CONDITIONS."
                  .. name, 0)
        end
        holds = fn(list, target) and true or false
    end
    if neg then return not holds end
    return holds
end

-- One [...] group's contents: true and its target when every condition holds.
local function group(body)
    local target
    local conds = {}
    for c in body:gmatch("[^,]+") do
        c = trim(c)
        local unit = c:match("^@(.+)$") or c:match("^target%s*=%s*(.+)$")
        if unit then target = trim(unit) elseif c ~= "" then conds[#conds + 1] = c end
    end
    for _, c in ipairs(conds) do
        if not condition(c, target) then return false end
    end
    return true, target
end

function SecureCmdOptionParse(msg)
    if type(msg) ~= "string" then return nil end
    for clause in (msg .. ";"):gmatch("([^;]*);") do
        local rest = trim(clause)
        local any, holds, target = false, false, nil
        while rest:sub(1, 1) == "[" do
            local body, after = rest:match("^%[([^%]]*)%](.*)$")
            if not body then error("SecureCmdOptionParse: an unclosed [ in " .. msg, 0) end
            any = true
            if not holds then
                local ok, t = group(body)
                if ok then holds, target = true, t end
            end
            rest = trim(after)
        end
        if holds or not any then return rest, target end
    end
    return nil
end

-- SecureStateDriver.lua's resolveDriver.
local function resolveDriver(frame, attribute, values)
    local newValue = SecureCmdOptionParse(values)
    frame._attrs = frame._attrs or {}
    if attribute == "state-visibility" then
        if newValue == "show" then
            WoW.setShown(frame, true)
            frame._attrs.statehidden = nil
        elseif newValue == "hide" then
            WoW.setShown(frame, false)
            frame._attrs.statehidden = true
        end
    elseif newValue then
        if newValue == "nil" then newValue = nil else newValue = tonumber(newValue) or newValue end
        frame._attrs[attribute] = newValue
    end
end

-- Every 0.2 s while the manager is shown (from its first registration).
local STATE_DRIVER_UPDATE_THROTTLE = 0.2
driveStates = function(elapsed)
    if WoW.stateDriverTimer == nil then return end
    WoW.stateDriverTimer = WoW.stateDriverTimer - elapsed
    if WoW.stateDriverTimer > 0 then return end
    WoW.stateDriverTimer = STATE_DRIVER_UPDATE_THROTTLE
    local list = {}   -- a show or hide runs scripts, which may register drivers
    for frame, drivers in pairs(WoW.stateDrivers) do
        for attribute, values in pairs(drivers) do list[#list + 1] = { frame, attribute, values } end
    end
    for _, d in ipairs(list) do resolveDriver(d[1], d[2], d[3]) end
end

-- The events that bring the next update forward (SecureStateDriver.lua's
-- RegisterEvent list).
WoW.STATE_DRIVER_EVENTS = {
    MODIFIER_STATE_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true,
    PLAYER_ENTERING_WORLD = true, UPDATE_SHAPESHIFT_FORM = true, UPDATE_STEALTH = true,
    PLAYER_TARGET_CHANGED = true, PLAYER_FOCUS_CHANGED = true, PLAYER_REGEN_DISABLED = true,
    PLAYER_REGEN_ENABLED = true, UNIT_PET = true, GROUP_ROSTER_UPDATE = true,
}
wakeStateDrivers = function(event)
    if WoW.STATE_DRIVER_EVENTS[event] and WoW.stateDriverTimer then WoW.stateDriverTimer = 0 end
end

-- SecureStateDriverManager's OnAttributeChanged: "setframe" (shows the
-- manager), then "setstate" "<attribute> <values>" (empty values remove the
-- driver), or "delframe".
local function driverRefused(what)
    if WoW.combat then
        table.insert(WoW.blocked, "SecureStateDriverManager:SetAttribute (" .. what .. ")")
        return true
    end
end
local function setState(frame, setstate)
    if type(frame) ~= "table" then error("Invalid frame", 3) end
    WoW.stateDrivers[frame] = WoW.stateDrivers[frame] or {}
    if WoW.stateDriverTimer == nil then WoW.stateDriverTimer = 0 end
    local attribute, values = string.match(setstate, "^(%S+)%s*(.*)$")
    if values == "" then
        WoW.stateDrivers[frame][attribute] = nil
    else
        WoW.stateDrivers[frame][attribute] = values
        resolveDriver(frame, attribute, values)
    end
end

function RegisterAttributeDriver(frame, attribute, values)
    if attribute and values and attribute:sub(1, 1) ~= "_" then
        if driverRefused("RegisterAttributeDriver") then return end
        setState(frame, attribute .. " " .. values)
    end
end
function UnregisterAttributeDriver(frame, attribute)
    if driverRefused("UnregisterAttributeDriver") then return end
    if attribute then
        setState(frame, attribute)
    elseif frame ~= nil then
        WoW.stateDrivers[frame] = nil
    end
end
function RegisterStateDriver(frame, state, values) RegisterAttributeDriver(frame, "state-" .. state, values) end
function UnregisterStateDriver(frame, state) UnregisterAttributeDriver(frame, "state-" .. state) end

WoW.reset()

--------------------------------------------------------------------------------
-- Strict globals, installed by the consumer's stub as its last line
--------------------------------------------------------------------------------

-- The client globals this core defines, for the kit's own check that each is
-- in the build's globals list. FrameXML names (not in a function list) are
-- listed apart, each with where it comes from.
Kit.CORE_GLOBALS = { "CreateFrame", "issecretvalue", "print", "GetTime", "GetLocale", "InCombatLockdown",
                     "strmatch", "hooksecurefunc", "C_Timer", "pcall", "xpcall", "GetCursorPosition",
                     "SecureHandlerSetFrameRef", "SecureHandlerExecute", "SecureHandlerWrapScript",
                     "SecureHandlerUnwrapScript", "SecureCmdOptionParse", "RegisterAttributeDriver",
                     "UnregisterAttributeDriver", "RegisterStateDriver", "UnregisterStateDriver" }
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
