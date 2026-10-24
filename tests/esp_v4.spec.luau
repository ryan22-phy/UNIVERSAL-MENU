-- Tests run the actual module, replacing only Roblox engine boundaries.
local created = {}
local Vector3 = {}
local vectorMeta = {}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end
vectorMeta.__index = function(v,key)
    if key == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
    return nil
end
vectorMeta.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__mul = function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
local Vector2 = {new=function(x,y) return Vector3.new(x,y,0) end}
local CFrame = {}
local frameMeta = {__mul=function(a,b) return a.Position+b end}
function CFrame.new(position) return setmetatable({Position=position},frameMeta) end
local UDim2 = {new=function(...) return {...} end,fromOffset=function(...) return {...} end,fromScale=function(...) return {...} end}
local Color3 = {fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end}
local Enum = {RaycastFilterType={Exclude="Exclude"},Font={Gotham="Gotham"},
    HighlightDepthMode={AlwaysOnTop="AlwaysOnTop",Occluded="Occluded"},
    HumanoidRigType={R6="R6",R15="R15"}}
local RaycastParams = {new=function() return {} end}
local Instance = {}
function Instance.new(class)
    local object={ClassName=class,Parent=nil,Visible=true,Enabled=true,Name=class}
    function object:IsA(name) return self.ClassName==name or (name=="BasePart" and self.ClassName=="Part") end
    function object:IsDescendantOf(parent)
        return self.Parent==parent or (self.Parent and self.Parent.IsDescendantOf and self.Parent:IsDescendantOf(parent)) or false
    end
    function object:GetChildren()
        local children={}
        for _,value in ipairs(created) do if value.Parent==self and not value.Destroyed then table.insert(children,value) end end
        return children
    end
    function object:GetDescendants()
        local descendants={}
        for _,value in ipairs(created) do if not value.Destroyed and value:IsDescendantOf(self) then table.insert(descendants,value) end end
        return descendants
    end
    function object:FindFirstChild(name)
        for _,value in ipairs(self:GetChildren()) do if value.Name==name then return value end end
        return nil
    end
    function object:Destroy()
        for _,child in ipairs(self:GetChildren()) do child:Destroy() end
        self.Destroyed=true; self.Parent=nil
    end
    table.insert(created,object)
    return object
end
local ESPFactory=(function()
-- @ESP_SOURCE@
end)()
local ESP=ESPFactory(function() error("No imports expected") end)
local function equalColor(a,b)
    return math.abs(a.R-b.R)<0.00001 and math.abs(a.G-b.G)<0.00001 and math.abs(a.B-b.B)<0.00001
end
local function countVisible(lines)
    local n=0
    for _,line in pairs(lines) do if line.Visible then n+=1 end end
    return n
end
local function fixture()
    local config,records,diagnostics={}, {}, {}
    local workspace=Instance.new("Workspace")
    local camera=Instance.new("Camera"); camera.Parent=workspace
    camera.CFrame=CFrame.new(Vector3.new(0,0,0)); camera.ViewportSize=Vector2.new(800,600)
    workspace.CurrentCamera=camera
    local projections,raycasts,lists,logs=0,0,0,0
    function camera:WorldToViewportPoint(point)
        projections+=1
        return Vector3.new(400+point.X*10,300-point.Y*10,point.Z),point.Z>0
    end
    local hit=nil
    function workspace:Raycast() raycasts+=1; return hit end
    local authorized=true
    local ctx={Services={Workspace=workspace},Gui=Instance.new("ScreenGui"),Player={Neutral=true}}
    ctx.Config={Get=function(_,key) return config[key] end}
    ctx.Diagnostics={Set=function(_,key,value) diagnostics[key]=value end,Log=function() logs+=1 end}
    ctx.Entities={List=function() lists+=1; return records end}
    ctx.IsAuthorized=function() return authorized end
    local function part(model,name,x,y,z)
        local value=Instance.new("Part"); value.Name=name; value.Parent=model
        value.Position=Vector3.new(x,y,z); value.CFrame=CFrame.new(value.Position); value.Size=Vector3.new(2,2,2)
        return value
    end
    local function entity(x,z,category,rig,subcategory)
        local model=Instance.new("Model"); model.Parent=workspace; model.Name="Dummy"
        local root=part(model,"HumanoidRootPart",x,0,z)
        root.Size=Vector3.new(4,8,2)
        local head=part(model,"Head",x,3,z)
        if rig=="R6" then
            part(model,"Torso",x,1,z)
            part(model,"Left Arm",x-2,1,z); part(model,"Right Arm",x+2,1,z)
            part(model,"Left Leg",x-1,-2,z); part(model,"Right Leg",x+1,-2,z)
        elseif rig=="R15" then
            part(model,"UpperTorso",x,2,z); part(model,"LowerTorso",x,0,z)
            for _,side in ipairs({"Left","Right"}) do
                local sign=side=="Left" and -1 or 1
                part(model,side.."UpperArm",x+sign*2,2,z)
                part(model,side.."LowerArm",x+sign*3,1,z)
                part(model,side.."Hand",x+sign*3,0,z)
                part(model,side.."UpperLeg",x+sign,-1,z)
                part(model,side.."LowerLeg",x+sign,-2,z)
                part(model,side.."Foot",x+sign,-3,z)
            end
        end
        function model:GetBoundingBox() return root.CFrame,root.Size end
        return {Instance=model,Model=model,Root=root,Head=head,Rig=rig,Category=category or "NPC",
            Subcategory=subcategory,Humanoid=category~="Item" and {Health=100,MaxHealth=100,RigType=rig} or nil,Name="Lab Dummy"}
    end
    return {ctx=ctx,config=config,records=records,diagnostics=diagnostics,camera=camera,workspace=workspace,entity=entity,
        authorize=function(value) authorized=value end,occlude=function(value) hit=value end,
        counters=function() return projections,raycasts,lists,logs end}
end
local function start(f)
    local manager=ESP.new(f.ctx); manager:Init(); manager:Init(); manager:Enable(); manager:Step(1)
    return manager
end
local function refresh(f,manager,key,value)
    f.config["ESP."..key]=value; manager:UpdateConfig(); manager:Step(1)
end

local controls=fixture()
local controlled=controls.entity(0,20,"NPC","R6")
table.insert(controls.records,controlled)
local controlsManager=start(controls)
local controlsEntry=controlsManager._entries[controlled.Instance]
assert(controlsEntry.Highlight.DepthMode==Enum.HighlightDepthMode.Occluded,"Default Highlight mode must use official Occluded")
refresh(controls,controlsManager,"Names",false)
refresh(controls,controlsManager,"Distance",false)
refresh(controls,controlsManager,"Health",false)
assert(not controlsEntry.Name.Visible and not controlsEntry.Details.Visible and not controlsEntry.Health.Visible,"Names, distance, health labels and health bar must toggle independently")
refresh(controls,controlsManager,"Lines",true)
assert(controlsEntry.Tracer.Visible and type(controlsEntry.Tracer.Rotation)=="number","Tracer must use a rotated native Frame")
controls.ctx.SelectedTarget=controlled.Instance
refresh(controls,controlsManager,"TargetIndicator",false)
assert(not controlsEntry.TargetIndicator.Visible,"Target indicator toggle must hide an active selected target")
refresh(controls,controlsManager,"NPCColor","#102030")
assert(equalColor(controlsEntry.Stroke.Color,Color3.fromRGB(16,32,48)),"Optional hash-prefixed six-digit colors must apply")
refresh(controls,controlsManager,"NPCs",false)
assert(controls.diagnostics["ESP.Rendered"]==0,"NPC toggle must prune NPC overlays")
controlsManager:Destroy()

local independent=fixture()
local subject=independent.entity(0,20,"NPC","R6"); table.insert(independent.records,subject)
independent.config["ESP.Boxes"]=false
local manager=start(independent)
local entry=manager._entries[subject.Instance]
assert(entry and entry.Highlight.Enabled and not entry.Box.Visible,"Highlight must be independent of Boxes")
refresh(independent,manager,"Highlight",false)
assert(manager._entries[subject.Instance]==entry and not entry.Highlight.Enabled,"Configuration must reuse native overlay instances")
refresh(independent,manager,"Boxes",true)
assert(entry.Box.Visible and not entry.Highlight.Enabled,"Boxes must remain independent of Highlight")
refresh(independent,manager,"Skeleton",true)
assert(countVisible(entry.Skeleton)==5,"R6 skeleton must render the five standard part links")
refresh(independent,manager,"HeadMarker",true)
assert(entry.HeadMarker.Visible,"Head marker must use the authorized valid Head")
independent.ctx.SelectedTarget=subject.Instance; manager:Step(1)
assert(entry.TargetIndicator.Visible,"Selected registry instance must have a target indicator")
assert(equalColor(entry.TargetIndicator.TextColor3,Color3.fromRGB(255,255,255)),"Target indicator must use configured target color")
independent.ctx.SelectedTarget=nil; manager:Step(1)
assert(not entry.TargetIndicator.Visible,"Cleared selection must hide the indicator")
subject.Model:FindFirstChild("Left Arm"):Destroy(); manager:Step(1)
assert(countVisible(entry.Skeleton)==4,"Removed body parts must remove their skeleton segment")
subject.Head:Destroy(); manager:Step(1)
assert(not entry.HeadMarker.Visible and countVisible(entry.Skeleton)==3,"Removed head must hide marker and connected skeleton")
local replacementHead=Instance.new("Part"); replacementHead.Name="Head"; replacementHead.Parent=subject.Model
replacementHead.Position=Vector3.new(0,3,20)
manager:Step(1)
assert(entry.HeadMarker.Visible,"A replaced Head must recover even while registry Head metadata is temporarily stale")
local allocations=#created
for _=1,60 do manager:Step(1/20) end
assert(#created==allocations,"Steady state rendering must not allocate native objects each frame")
independent.workspace.CurrentCamera=nil; manager:Step(1)
assert(independent.diagnostics["ESP.Rendered"]==0 and not entry.Frame.Visible,"Missing camera must hide owned overlays")
independent.workspace.CurrentCamera=independent.camera; manager:Step(1)
assert(manager._entries[subject.Instance]==entry,"Camera replacement must reuse cached overlay instances")
subject.Root:Destroy(); manager:Step(0.001)
assert(manager._entries[subject.Instance]==nil,"Removed root must be pruned before render throttling")
manager:Destroy(); manager:Destroy()
assert(independent.diagnostics["ESP.VisualObjects"]==0,"Destroyed manager must report no owned visual objects")
assert(independent.diagnostics["ESP.Status"]=="DESTROYED","Destroyed state must be available to module diagnostics")

local missingCamera=fixture()
local removed=missingCamera.entity(0,20,"NPC","R6")
table.insert(missingCamera.records,removed)
local missingManager=start(missingCamera)
missingCamera.workspace.CurrentCamera=nil; table.clear(missingCamera.records)
missingManager:Step(0.001)
assert(missingManager._entries[removed.Instance]==nil,"Registry revocation must clean entries even without a camera")
missingManager:Destroy()

local clipping=fixture()
local edge=clipping.entity(39,30,"NPC","R15")
table.insert(clipping.records,edge)
clipping.config["ESP.Skeleton"]=true; clipping.config["ESP.Lines"]=true
local clippingManager=start(clipping)
local edgeEntry=clippingManager._entries[edge.Instance]
assert(edgeEntry.Frame.Position[1]>=0 and edgeEntry.Frame.Position[2]>=0
    and edgeEntry.Frame.Position[1]+edgeEntry.Frame.Size[1]<=800
    and edgeEntry.Frame.Position[2]+edgeEntry.Frame.Size[2]<=600,"Partially projected bounds must be clipped to the viewport")
for _,line in pairs(edgeEntry.Skeleton) do
    if line.Visible then
        assert(line.Size[1]>=0 and line.Size[1]<=1000 and line.Rotation==line.Rotation,"Clipped skeleton Frames must have finite bounded lengths and rotation")
    end
end
function clipping.camera:WorldToViewportPoint() return Vector3.new(0/0,math.huge,-1),false end
clippingManager:Step(1)
assert(clipping.diagnostics["ESP.Rendered"]==0,"Nonfinite or behind-camera projection must not create overlays")
clippingManager:Destroy()

local nearPlane=fixture()
table.insert(nearPlane.records,nearPlane.entity(0,0.5,"NPC","R6"))
local nearManager=start(nearPlane)
assert(nearPlane.diagnostics["ESP.Rendered"]==0,"Near-plane intersections must not produce inverted or unbounded boxes")
nearManager:Destroy()

local rigs=fixture()
local r15=rigs.entity(0,30,"NPC","R15"); local unknown=rigs.entity(3,30,"NPC","Custom")
table.insert(rigs.records,r15); table.insert(rigs.records,unknown)
rigs.config["ESP.Skeleton"]=true
local rigManager=start(rigs)
assert(countVisible(rigManager._entries[r15.Instance].Skeleton)==14,"R15 skeleton must render the fourteen standard links")
assert(countVisible(rigManager._entries[unknown.Instance].Skeleton)==0,"Unknown rigs must not receive guessed skeleton connections")
local _,_,_,beforeLogs=rigs.counters()
for _=1,20 do rigManager:Step(1) end
local _,_,_,afterLogs=rigs.counters()
assert(afterLogs==beforeLogs,"Unsupported structure diagnostics must be bounded")
rigManager:Destroy()

local fallbackRig=fixture()
local humanoidRig=fallbackRig.entity(0,30,"NPC","R6")
humanoidRig.Rig="Unknown"
table.insert(fallbackRig.records,humanoidRig); fallbackRig.config["ESP.Skeleton"]=true
local fallbackRigManager=start(fallbackRig)
assert(countVisible(fallbackRigManager._entries[humanoidRig.Instance].Skeleton)==5,"Official Humanoid.RigType must work when optional adapter Rig metadata is unknown")
fallbackRigManager:Destroy()

local partial=fixture()
local sparse=partial.entity(0,30,"NPC","R15")
sparse.Head:Destroy()
local misleading=partial.entity(3,30,"NPC","CustomR6")
-- Even a complete standard-looking layout does not identify an unknown rig.
misleading.Model:FindFirstChild("Head").Name="OldHead"
local standard=partial.entity(6,30,"NPC","R6")
for _,bodyPart in ipairs(standard.Model:GetChildren()) do bodyPart.Parent=misleading.Model end
standard.Model:Destroy()
table.insert(partial.records,sparse); table.insert(partial.records,misleading)
partial.config["ESP.Skeleton"]=true
local partialManager=start(partial)
local sparseEntry=partialManager._entries[sparse.Instance]
assert(countVisible(sparseEntry.Skeleton)==13,"Partially streamed rigs must still show remaining standard links")
assert(countVisible(partialManager._entries[misleading.Instance].Skeleton)==0,"CustomR6 is not a known R6 identity")
refresh(partial,partialManager,"Skeleton",false)
assert(countVisible(sparseEntry.Skeleton)==0,"Sparse skeleton pools must all hide when Skeleton is disabled")
refresh(partial,partialManager,"Skeleton",true)
partial.workspace.CurrentCamera=nil; partialManager:Step(1)
assert(countVisible(sparseEntry.Skeleton)==0,"Missing camera must hide every sparse skeleton line")
partialManager:Destroy()

local team=fixture()
local playerEntity=team.entity(0,20,"Player","R6")
playerEntity.Player={Neutral=false,Team={Name="Blue Team"},TeamColor={Color=Color3.fromRGB(0,80,240)}}
table.insert(team.records,playerEntity)
team.config["ESP.ColorByTeam"]=true; team.config["ESP.TeamIdentification"]=true
local teamManager=start(team)
local teamEntry=teamManager._entries[playerEntity.Instance]
assert(equalColor(teamEntry.Stroke.Color,playerEntity.Player.TeamColor.Color),"Non-neutral player must use real TeamColor.Color")
assert(string.find(teamEntry.Details.Text,"Blue Team",1,true),"Team identification must include the actual team name")
playerEntity.Player.Neutral=true; teamManager:Step(1)
assert(equalColor(teamEntry.Stroke.Color,Color3.fromRGB(38,139,255)),"Neutral player must use configured player color")
team.ctx.Adapters={TeamIdentity=function() return "tagged",Color3.fromRGB(100,20,40),"Tagged team" end}
teamManager:Step(1)
assert(equalColor(teamEntry.Stroke.Color,Color3.fromRGB(100,20,40)) and string.find(teamEntry.Details.Text,"Tagged team",1,true),"Optional adapter color/label must be respected")
refresh(team,teamManager,"PlayerColor","ABCDEF")
team.ctx.Adapters=nil; teamManager:Step(1)
assert(equalColor(teamEntry.Stroke.Color,Color3.fromRGB(171,205,239)),"Custom six-digit hex colors must apply")
refresh(team,teamManager,"PlayerColor","BADHEX")
assert(equalColor(teamEntry.Stroke.Color,Color3.fromRGB(38,139,255)),"Malformed colors must fall back safely")
team.ctx.Adapters={TeamIdentity=function() error("Unsupported adapter layout") end}
teamManager:Step(1)
assert(equalColor(teamEntry.Stroke.Color,Color3.fromRGB(38,139,255)),"Failed optional team adapters must fall back safely")
refresh(team,teamManager,"Players",false)
assert(team.diagnostics["ESP.Rendered"]==0,"Player toggle must prune player overlays")
refresh(team,teamManager,"Players",true)
playerEntity.Humanoid.Health=0; teamManager:Step(0.001)
assert(teamManager._entries[playerEntity.Instance]==nil,"Dead entities must hide by default even between render refreshes")
refresh(team,teamManager,"ShowDead",true)
assert(teamManager._entries[playerEntity.Instance]~=nil,"ShowDead must explicitly permit dead registered entities")
teamManager:Destroy()

local items=fixture()
local itemKinds={"DroppedItems","Loot","Weapons","Tools","Collectibles","Objectives","TestObjects"}
for i,kind in ipairs(itemKinds) do table.insert(items.records,items.entity(i-4,20,"Item",nil,kind)) end
local itemManager=start(items)
assert(items.diagnostics["ESP.Rendered"]==#itemKinds,"All canonical tagged item types must default to enabled")
refresh(items,itemManager,"Names",false)
refresh(items,itemManager,"Distance",false)
for _,item in ipairs(items.records) do
    local details=itemManager._entries[item.Instance].Details
    assert(details.Visible and string.find(details.Text,"Item",1,true)
        and string.find(details.Text,item.Subcategory,1,true) and string.find(details.Text,"Model",1,true),
        "Item category/subcategory and actual instance type must remain visible without name/distance labels")
end
local lootDetails=itemManager._entries[items.records[2].Instance].Details.Text
local weaponDetails=itemManager._entries[items.records[3].Instance].Details.Text
assert(lootDetails~=weaponDetails and string.find(lootDetails,"Loot",1,true)
    and string.find(weaponDetails,"Weapons",1,true),"Loot and Weapons must have distinguishable item category labels")
for index,kind in ipairs(itemKinds) do
    refresh(items,itemManager,kind,false)
    assert(items.diagnostics["ESP.Rendered"]==#itemKinds-index,"Tagged item filter must act on canonical Subcategory: "..kind)
end
refresh(items,itemManager,"Items",false)
assert(items.diagnostics["ESP.Rendered"]==0,"Master item toggle must remove all item overlays")
itemManager:Destroy()

local toolItem=fixture()
local tool=Instance.new("Tool"); tool.Parent=toolItem.workspace
local handle=Instance.new("Part"); handle.Name="Handle"; handle.Parent=tool
handle.Position=Vector3.new(0,0,20); handle.CFrame=CFrame.new(handle.Position); handle.Size=Vector3.new(2,2,2)
table.insert(toolItem.records,{Instance=tool,Root=handle,Category="Item",Subcategory="Tools",Name="Dropped Tool"})
local toolManager=start(toolItem)
assert(toolManager._entries[tool].Highlight.Adornee==handle,"Tool item Highlights must adorn their valid BasePart Handle")
assert(string.find(toolManager._entries[tool].Details.Text,"Tool",1,true),"Dropped Tool details must report the actual Tool instance type")
toolManager:Destroy()

local unknownItem=fixture()
local unknownRecord=unknownItem.entity(0,20,"Item",nil,nil)
table.insert(unknownItem.records,unknownRecord)
unknownItem.config["ESP.Names"]=false; unknownItem.config["ESP.Distance"]=false
local unknownItemManager=start(unknownItem)
assert(string.find(unknownItemManager._entries[unknownRecord.Instance].Details.Text,"Unknown category",1,true),"Missing item subcategory must have an explicit unknown label")
unknownItemManager:Destroy()

local capped=fixture()
capped.config["ESP.MaxElements"]=40; capped.config["ESP.Skeleton"]=true
for i=1,100 do table.insert(capped.records,capped.entity((i%15)-7,200+i,"NPC","R15")) end
-- Near offscreen candidates must not consume the available visible overlay slots.
for i=1,45 do capped.records[i].Root.Position=Vector3.new(60,0,2+i*0.1); capped.records[i].Root.CFrame=CFrame.new(capped.records[i].Root.Position) end
local capManager=start(capped)
assert(capped.diagnostics["ESP.Rendered"]==40,"Offscreen candidates must not starve later on-screen candidates under the cap")
local highlights=0
for _,value in pairs(capManager._entries) do if value.Highlight and value.Highlight.Enabled then highlights+=1 end end
assert(highlights<=31,"Owned active Highlights must stay within the conservative native 31-slot budget")
local nativeCount=capped.diagnostics["ESP.VisualObjects"]
assert(nativeCount>40 and nativeCount<=40*30+1,"Native object count must include skeleton and UI children and stay bounded")
local actualOwned=0
for _,object in ipairs(created) do
    if not object.Destroyed and (object==capManager._root or object:IsDescendantOf(capManager._root)
        or object.Name=="VWLabHighlight") then actualOwned+=1 end
end
assert(nativeCount==actualOwned,"VisualObjects must count actual owned native objects, including nested GUI children")
local steadyCount=#created
for _=1,30 do capManager:Step(1/20) end
assert(#created==steadyCount and capped.diagnostics["ESP.VisualObjects"]==nativeCount,"100-entity workload must preserve the native instance budget")
table.remove(capped.records,46); capManager:Step(0.001)
assert(capped.diagnostics["ESP.Rendered"]==39,"Registry removal must promptly destroy its owned entry")
refresh(capped,capManager,"MaxElements",128)
assert(capManager._cfg.MaxElements==128,"Overlay configuration must support a budget of at least 128")
capped.occlude({Instance=Instance.new("Part")}); capManager:Step(1)
assert(capped.diagnostics["ESP.Rendered"]==0,"Occluded entities must hide when ThroughWalls is false")
refresh(capped,capManager,"ThroughWalls",true)
for _,value in pairs(capManager._entries) do
    if value.Highlight then assert(value.Highlight.DepthMode==Enum.HighlightDepthMode.AlwaysOnTop,"ThroughWalls must use official AlwaysOnTop depth mode") end
end
capped.authorize(false); capManager:Step(1)
assert(not capManager._enabled and capped.diagnostics["ESP.VisualObjects"]==0,"Authorization revocation must destroy every owned overlay")
local beforeP,beforeR,beforeL=capped.counters()
for _=1,100 do capManager:Step(1/60) end
local afterP,afterR,afterL=capped.counters()
assert(beforeP==afterP and beforeR==afterR and beforeL==afterL,"Disabled ESP must do no registry, projection, or raycast work")
capManager:Destroy()
print("ESP V4: independent native features, R6/R15 skeletons, teams/colors, seven item filters, selection, lifecycle and 100-entity budgets passed")
