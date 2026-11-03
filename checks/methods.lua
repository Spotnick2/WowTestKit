-- checks/methods.lua: every widget method the tests made the addon call must
-- exist on the client for that widget type.
--
-- The stub answers any capitalised method (a no-op for one it doesn't
-- implement), so a call to a method Forever lacks would otherwise pass
-- silently. Exercise the addon first (load it, fire its events, open its
-- windows, run its slash commands), then:
--
--   Kit.checkMethods({ allow = { ["Alpha:SetFromAlpha"] = "why it's real (source)" } })
--
-- Each recorded "Type:Method" must be that exact pair in the build's widget
-- methods. An animation subtype (Alpha, Translation, ...) may call its own
-- methods (the dump's SimpleAnim<Type>API) or any Animation method. Methods a
-- Blizzard mixin adds in Lua (MapCanvasMixin's GetMapID...) aren't in the
-- dump's widget walk: allow each pair, naming the Blizzard file. It fails,
-- never skips, when nothing was recorded.

local ANIMATIONS = { Alpha = true, Translation = true, Scale = true, Rotation = true, Path = true,
                     LineScale = true, LineTranslation = true, FlipBook = true, VertexColor = true,
                     TextureCoordTranslation = true }

function Kit.checkMethods(opts)
    opts = opts or {}
    local allow = opts.allow or {}
    local known = Kit.data("widgetMethods")
    local types = {}
    for pair in pairs(known) do types[pair:match("^(%a+):")] = true end

    local list = {}
    for name in pairs(WoW.methodsCalled) do list[#list + 1] = name end
    table.sort(list)
    check(#list > 0, "recorded the addon's widget method calls (" .. #list .. "): exercise it before checking")

    for _, name in ipairs(list) do
        local wtype, method = name:match("^([%w_]+):([%w_]+)$")
        if allow[name] then
            check(type(allow[name]) == "string" and allow[name] ~= "", "allowed with a reason: " .. name)
        elseif not wtype then
            check(false, "a recorded call reads Type:Method: " .. name)
        elseif ANIMATIONS[wtype] then
            -- Its own (from the dump's SimpleAnim<Type>API) or every animation's.
            check(known[name] or known["Animation:" .. method],
                "method exists on Forever " .. Kit.BUILD .. ": " .. name .. " (its own or Animation's)")
        elseif types[wtype] then
            check(known[name], "method exists on Forever " .. Kit.BUILD .. ": " .. name)
        else
            check(false, "widget type exists on Forever " .. Kit.BUILD .. ": " .. name)
        end
    end
    return #list
end
