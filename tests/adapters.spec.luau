-- Common-structure adapters, using object doubles rather than engine claims.
local Adapter = require("../src/client/UniversalGameAdapter")(nil)
local function object(class, name, parent)
    local o={ClassName=class,Name=name,Parent=parent,children={},attributes={}}
    function o:IsA(kind) return self.ClassName==kind or kind=="BasePart" and self.ClassName=="Part" end
    function o:FindFirstChild(n) return self.children[n] end
    function o:FindFirstChildOfClass(n) for _,c in pairs(self.children) do if c:IsA(n) then return c end end return nil end
    function o:FindFirstChildWhichIsA(n) return self:FindFirstChildOfClass(n) end
    function o:GetAttribute(n) return self.attributes[n] end
    function o:IsDescendantOf(p) local q=self.Parent;while q do if q==p then return true end;q=q.Parent end;return false end
    if parent and parent.children then parent.children[name]=o end
    return o
end
local world=object("Workspace","Workspace");world.StreamingEnabled=true
local model=object("Model","Dummy",world)
local head=object("Part","Head",model)
local torso=object("Part","Torso",model)
local root=object("Part","HumanoidRootPart",model)
local human=object("Humanoid","Humanoid",model);human.Health=100;human.RigType={Name="R6"}
local values={};local setting="Auto"
local ctx={Services={Workspace=world,Players={GetPlayers=function() return {} end}},Config={Get=function()return setting end},Diagnostics={Set=function(_,k,v)values[k]=v end,Log=function()end}}
local adapters=Adapter.new(ctx,{})
local record=adapters:Describe(model,nil,"NPC")
assert(record.Rig=="R6" and record.Head==head and record.Root==root,"R6 references")
assert(adapters:ResolveAimPart(record,{HeadPriority=true,Fallback=false})==head,"exclusive head when available")
assert(adapters:ResolveAimPart(record,{HeadPriority=false,Fallback=false})==head,"Head Only overrides disabled priority")
model.children.Head=nil;head.Parent=nil
assert(adapters:ResolveAimPart(record,{HeadPriority=true,Fallback=false})==nil,"destroyed head never retained")
assert(adapters:ResolveAimPart(record,{HeadPriority=false,Fallback=false})==nil,"Head Only never falls back with priority off")
assert(adapters:ResolveAimPart(record,{HeadPriority=true,Fallback=true,FallbackPart="Torso"})==torso,"explicit fallback")
model.children.Torso=nil
assert(adapters:ResolveAimPart(record,{HeadPriority=true,Fallback=true,FallbackPart="Torso"})==nil,"missing chosen fallback is not guessed")
local fresh=object("Part","Head",model)
assert(adapters:ResolveAimPart(record,{HeadPriority=true})==fresh,"replacement head refreshed")
model.children.HumanoidRootPart=nil;model.PrimaryPart=torso
local partial=adapters:Describe(model,nil,"NPC")
model.children.Head=nil
assert(adapters:ResolveAimPart(partial,{HeadPriority=true,Fallback=true,FallbackPart="HumanoidRootPart"})==nil,"explicit HRP fallback must not select a PrimaryPart")
model.children.HumanoidRootPart=root;model.children.Head=fresh
human.RigType={Name="R15"};assert(adapters:Describe(model,nil,"NPC").Rig=="R15","R15 detection")
local team={Name="Blue",TeamColor={Color="blue"}}
local a={Team=team,Neutral=false};local b={Team=team,Neutral=false}
assert(adapters:SameTeam(a,b,model),"official same team")
b.Neutral=true;assert(not adapters:SameTeam(a,b,model),"Neutral ignores stale Team")
a.Team=nil;b.Team=nil;a.Neutral=false;b.Neutral=false
assert(not adapters:SameTeam(a,b,model),"two teamless players are not teammates")
b.Team={Name="Other",TeamColor={Color="other"}};assert(not adapters:SameTeam(a,b,model),"different teams")
local custom=Adapter.new(ctx,{CustomAdapter={TeamAttribute="Faction",RootName="Core",HeadName="Sensor"}})
function a:GetAttribute(n)return n=="Faction" and "LabA" end
function b:GetAttribute(n)return n=="Faction" and "LabA" end
b.Team=nil
assert(custom:SameTeam(a,b,model),"explicit custom faction adapter")
b.Team=team;assert(not custom:SameTeam(a,b,model),"official Team takes precedence over custom faction")
local core=object("Part","Core",model);local sensor=object("Part","Sensor",model)
local c=custom:Describe(model,nil,"NPC")
assert(c.Root==core and c.Head==sensor and c.Adapter=="CustomGameAdapter","configured custom parts")
assert(custom:ResolveAimPart(c,{HeadPriority=true})==sensor,"custom head mapping")
local tool=object("Tool","LabTool",world);local handle=object("Part","Handle",tool)
local t=adapters:Describe(tool,nil,"Item","Tools")
assert(t.Root==handle and t.Subcategory=="Tools","tagged Tool.Handle")
assert(adapters:IsWorldItem(tool),"dropped tool")
tool.Parent=model;assert(not adapters:IsWorldItem(tool),"collected item excluded")
setting="CustomGameAdapter"
assert(adapters:Describe(model,nil,"NPC")==nil,"unconfigured custom mode degrades without guessing")
setting="GenericRobloxAdapter"
assert(adapters:Describe(model,nil,"NPC").Adapter=="GenericRobloxAdapter","manual generic mode")
assert(not adapters:Register({Name="Invalid"}),"validate registration")
adapters:Step(1);assert(values["Adapter.StreamingEnabled"]==true,"streaming limitation reported")
adapters:Destroy();assert(adapters:Describe(model,nil,"NPC")==nil,"destroyed adapter inert")
print("PASS adapters.spec: common rigs, teams, custom mappings, item lifecycle and fallback")

-- Registry integration: metadata and permission are independent.
local Registry=require("../src/client/EntityRegistry")(nil)
local function signal()
 local s={listeners={}}
 function s:Connect(fn)local c={Connected=true};function c:Disconnect()self.Connected=false end;self.listeners[#self.listeners+1]={fn,c};return c end
 function s:Fire()for _,e in ipairs(self.listeners)do if e[2].Connected then e[1]() end end end
 return s
end
setting="Auto";world.DescendantAdded=signal();world.DescendantRemoving=signal()
local tagged={}
ctx.Services.CollectionService={GetTagged=function(_,tag)return tagged[tag] or {} end}
ctx.Player={UserId=1};ctx.Adapters=Adapter.new(ctx,{})
model.attributes.VWLabAuthorized=true;tool.Parent=world;tool.attributes.VWLabAuthorized=true
tagged.VWTestTarget={model};tagged.ToolPickup={tool};tagged.Loot={tool}
local registry=Registry.new(ctx,{TargetUserIds={}});registry:Init();registry:Init();registry:Step(1)
local records=registry:List()
assert(#records==2,"deduplicate multiple item tags and keep authorized NPC")
local itemRecord=records[2]
assert(itemRecord.Category=="Item" and itemRecord.Subcategory=="Loot" and itemRecord.Root==handle,"classified Tool metadata")
tool.Parent=model;assert(#registry:List()==1,"collect removes existing item immediately")
local savedAdapter=ctx.Adapters;ctx.Adapters=nil
assert(#registry:List()==1,"collected item excluded even when optional adapter is unavailable")
ctx.Adapters=savedAdapter
tool.Parent=world;tool.attributes.VWLabAuthorized=false
world.DescendantAdded:Fire();registry:Step(0.11)
assert(#registry:List()==1,"replication discovery never grants authorization")
tool.attributes.VWLabAuthorized=true;registry:Step(0.5)
assert(#registry:List()==2,"newly authorized tagged item detected")
model.attributes.VWLabAuthorized=false
assert(#registry:List()==1,"NPC permission revoked immediately")
local many={}
for i=1,520 do local m=object("Model","Dummy"..i,world);m.attributes.VWLabAuthorized=true;object("Part","HumanoidRootPart",m);local h=object("Humanoid","Humanoid",m);h.Health=100;many[i]=m end
tagged.VWTestTarget=many;registry:Invalidate();registry:Step(0.01)
assert(#registry:List()==512,"registry has bounded capacity")
registry:Destroy();assert(#registry:List()==0,"registry release")
assert(#world.DescendantAdded.listeners==1 and not world.DescendantAdded.listeners[1][2].Connected,"one owned event subscription released")
ctx.Adapters:Destroy()
print("PASS adapter + registry integration: categories, opt-in, collect/removal, 512 cap and cleanup")
