-- ModelScene:CreateActor (WowTestKit #90): a ModelSceneActor widget, kept in
-- the scene's _actors, and not a frame.
dofile("kit.lua")
Kit.load({ build = "70532", api = Kit.API })

local scene = CreateFrame("ModelScene", nil, UIParent)
local frames = #WoW.frames
local a = scene:CreateActor()
local b = scene:CreateActor("KitActor", "ModelSceneActorTemplate")

check(WoW.isWidget(a), "an actor is a widget")
eq(a._type, "ModelSceneActor", "of type ModelSceneActor")
eq(a._parent, scene, "the scene is its parent")
eq(#scene._actors, 2, "the scene keeps its actors")
check(scene._actors[1] == a and scene._actors[2] == b, "in creation order")
eq(WoW.widgets[#WoW.widgets], b, "in WoW.widgets, as every widget")
eq(#WoW.frames, frames, "not a frame: not in WoW.frames")
eq(#scene._children, 0, "nor among the scene's children")
eq(rawget(_G, "KitActor"), nil, "its name isn't a global")

-- Its methods are the build's ModelSceneActor pairs.
eq(type(a.SetModelByCreatureDisplayID), "function", "an actor method reads as a method")
eq(a.SetFogColor, nil, "a model scene's own method doesn't")
eq(WoW.methodsCalled["ModelScene:CreateActor"], true, "CreateActor is recorded on the scene")
a:SetModelByCreatureDisplayID(1)
eq(WoW.methodsCalled["ModelSceneActor:SetModelByCreatureDisplayID"], true, "an actor call is recorded as ModelSceneActor's")

done("test_actor")
