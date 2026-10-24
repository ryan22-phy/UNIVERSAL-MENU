-- Tests authorization/streaming boundaries using object doubles; no engine behavior claimed.
local Registry=require("../src/client/EntityRegistry")(nil)
local world, players={},{}
local root={Parent=world,IsA=function(_,name) return name=="BasePart" end}
local object={Name="Target",authorized=false,streamed=true}
function object:IsA(name) return name=="Model" end
function object:FindFirstChild() return root end
function object:FindFirstChildOfClass(name) return name=="Humanoid" and {} or nil end
function object:IsDescendantOf(parent) return parent==world and self.streamed end
function object:GetAttribute(name) return name=="VWLabAuthorized" and self.authorized end
local participant={UserId=123,Character=object,Parent=players,DisplayName="Participant",authorized=false}
function participant:GetAttribute() return self.authorized end
local localPlayer={UserId=10}
function players:GetPlayers() return {localPlayer,participant} end
local ctx={Services={Workspace=world,Players=players,CollectionService={GetTagged=function(_,tag)
    if tag=="VWTestTarget" then return {object} end
    return {}
end}},Player=localPlayer,Diagnostics={Set=function() end}}
local registry=Registry.new(ctx,{TargetUserIds={}})
registry:Step(1); assert(#registry:List()==0,"deny unmarked targets")
object.authorized=true; registry:Step(1)
assert(#registry:List()==1 and registry:List()[1].Category=="NPC","opt-in tagged NPC")
object.authorized=false
assert(#registry:List()==0,"revocation immediate without refresh")
participant.authorized=true; registry:Step(1)
assert(#registry:List()==1 and registry:List()[1].Category=="Player","authorized participant")
object.streamed=false
assert(#registry:List()==0,"streamed out removed immediately")
registry:Destroy(); assert(#registry:List()==0,"cleanup")
print("PASS entities.spec: 6 assertions (object doubles)")
