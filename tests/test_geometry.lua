-- IsObjectType through the hierarchy, IsMouseOver, GetEffectiveScale, the
-- edges and centre, and RemoveMaskTexture (WowTestKit #68).
dofile("kit.lua")
Kit.load({ build = "70959", api = Kit.API })

-- IsObjectType walks the hierarchy: Blizzard's action buttons are CheckButtons.
local action = CreateFrame("CheckButton", nil, UIParent)
check(action:IsObjectType("CheckButton"), "a CheckButton is a CheckButton")
check(action:IsObjectType("Button"), "and a Button (LibGlass's Glass.Button asks this)")
check(action:IsObjectType("Frame"), "and a Frame")
check(not action:IsObjectType("Slider"), "but not a Slider")
check(action:IsObjectType("button"), "the name is matched without case (Blizzard_Dispatcher.lua:368)")
local button = CreateFrame("Button", nil, UIParent)
check(button:IsObjectType("Frame") and not button:IsObjectType("CheckButton"), "a Button is a Frame, not a CheckButton")
local model = CreateFrame("DressUpModel", nil, UIParent)
check(model:IsObjectType("PlayerModel") and model:IsObjectType("Model") and model:IsObjectType("Frame"),
    "a DressUpModel is a PlayerModel, a Model and a Frame")
local frame = CreateFrame("Frame", nil, UIParent)
local tex = frame:CreateTexture()
local fs = frame:CreateFontString()
check(tex:IsObjectType("Texture") and not tex:IsObjectType("Frame"), "a Texture is a Texture, not a Frame")
check(fs:IsObjectType("FontString") and not fs:IsObjectType("Texture"), "a FontString is neither")
check(not tex:IsObjectType("Region"), "abstract types read false (unmeasured)")
WoW.KIND_OF.Texture = "Region"
check(tex:IsObjectType("Region"), "until a stub adds one")
WoW.KIND_OF.Texture = nil
local mask = frame:CreateMaskTexture()
check(not mask:IsObjectType("Texture"), "a MaskTexture isn't a Texture")
local alpha = frame:CreateAnimationGroup():CreateAnimation("Alpha")
check(alpha:IsObjectType("Alpha") and alpha:IsObjectType("Animation"), "an Alpha is an Animation")
check(not frame:IsObjectType(nil), "a nil type is false")
check(WoW.methodsCalled["CheckButton:IsObjectType"], "the call is recorded as the widget's own type")

-- Each pair is the build's: a type has every method of the one it derives from.
local known = Kit.data("widgetMethods")
local byType = {}
for pair in pairs(known) do
    local t, m = pair:match("^([%w_]+):([%w_]+)$")
    if t then byType[t] = byType[t] or {}; byType[t][m] = true end
end
for child, parent in pairs(WoW.KIND_OF) do
    if not Kit.ANIMATION_TYPES[child] then
        check(byType[child] and byType[parent], child .. " and " .. parent .. " are types on the build")
        local missing
        for m in pairs(byType[parent] or {}) do
            if not (byType[child] or {})[m] then missing = m; break end
        end
        check(missing == nil, child .. " has every method of " .. parent .. (missing and (": lacks " .. missing) or ""))
    end
end

-- The pointer: w._mouseOver, a secret kept as is.
check(frame:IsMouseOver() == false, "IsMouseOver is false unset")
frame._mouseOver = true
check(frame:IsMouseOver() == true, "true when set")
frame._mouseOver = 1
check(frame:IsMouseOver() == false, "only true is true")
local secretHover = WoW.Secret("hover")
frame._mouseOver = secretHover
check(frame:IsMouseOver() == secretHover, "a secret comes back as is")
frame._mouseOver = nil

-- The edges, the centre and the effective scale.
eq(frame:GetLeft(), nil, "no edge before a test sets one")
eq(frame:GetCenter(), nil, "nor a centre")
eq(frame:GetEffectiveScale(), 1, "the effective scale is 1 unset")
eq(tex:GetEffectiveScale(), 1, "a texture's too")
frame._left, frame._right, frame._top, frame._bottom, frame._escale = 100, 300, 500, 400, 0.75
eq(frame:GetLeft(), 100, "GetLeft reads _left")
eq(frame:GetRight(), 300, "GetRight _right")
eq(frame:GetTop(), 500, "GetTop _top")
eq(frame:GetBottom(), 400, "GetBottom _bottom")
local cx, cy = frame:GetCenter()
check(cx == 200 and cy == 450, "GetCenter is the midpoint (" .. tostring(cx) .. ", " .. tostring(cy) .. ")")
eq(frame:GetEffectiveScale(), 0.75, "GetEffectiveScale reads _escale")
frame._right = nil
eq(frame:GetCenter(), nil, "no centre while an edge is unset")
frame._right = 300
frame._left = WoW.Secret("left")
local sx, sy = frame:GetCenter()
check(issecretvalue(sx) and issecretvalue(sy), "a secret edge makes a secret centre")
check(rawequal(frame:GetLeft(), frame._left), "and a secret edge comes back as is")

-- The secure handles read the same methods.
local ring = CreateFrame("Frame", "KitGeoRing", UIParent, "SecureHandlerBaseTemplate")
ring._width, ring._height, ring._escale = 200, 100, 2
WoW.Methods.GetLeft = function() return 100 end   -- a stub's own geometry
WoW.cursorX, WoW.cursorY = 400, 200                 -- 200, 100 in the frame's units
SecureHandlerExecute(ring, [[ px, py = self:GetMousePosition() ]])
local env = WoW.secureEnvironment(ring)
check(env.px == 0.5 and env.py == 1, "GetMousePosition goes through GetLeft and GetEffectiveScale ("
    .. tostring(env.px) .. ", " .. tostring(env.py) .. ")")
WoW.Methods.GetLeft = function(w) return w._left end
SecureHandlerExecute(ring, [[ isButton = self:IsObjectType("Button"); isFrame = self:IsObjectType("frame") ]])
check(env.isFrame == true and env.isButton == false, "a handle's IsObjectType is the frame's")
local secureCheck = CreateFrame("CheckButton", "KitGeoCheck", UIParent, "SecureActionButtonTemplate")
SecureHandlerSetFrameRef(ring, "check", secureCheck)
SecureHandlerExecute(ring, [[ refIsButton = self:GetFrameRef("check"):IsObjectType("Button") ]])
eq(env.refIsButton, true, "through the hierarchy too")

-- RemoveMaskTexture takes the mask out of _masks.
local m2 = frame:CreateMaskTexture()
tex:AddMaskTexture(mask)
tex:AddMaskTexture(m2)
tex:RemoveMaskTexture(mask)
eq(#tex._masks, 1, "RemoveMaskTexture takes one mask off")
eq(tex._masks[1], m2, "the other stays")
tex:RemoveMaskTexture(mask)
eq(#tex._masks, 1, "removing one it doesn't have does nothing")
frame:CreateTexture():RemoveMaskTexture(m2)
check(true, "nor on a texture with no masks")

done("test_geometry")
