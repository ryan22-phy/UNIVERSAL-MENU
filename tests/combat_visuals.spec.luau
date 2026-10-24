-- Standalone Roblox boundary doubles; generated runner replaces module markers.
local created = {}
local function signal()
    local result = { callbacks = {} }
    function result:Connect(callback)
        local connection = { Connected = true }
        function connection:Disconnect() self.Connected = false end
        table.insert(self.callbacks, { callback, connection })
        return connection
    end
    function result:Fire(...)
        for _, entry in self.callbacks do
            if entry[2].Connected then entry[1](...) end
        end
    end
    return result
end
local Vector3 = {}
local vectorMeta = {}
function Vector3.new(x, y, z) return setmetatable({ X=x, Y=y, Z=z }, vectorMeta) end
vectorMeta.__index = function(v, key)
    if key == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
    if key == "Unit" then return v / v.Magnitude end
    return nil
end
vectorMeta.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__mul = function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
vectorMeta.__div = function(a,b) return Vector3.new(a.X/b,a.Y/b,a.Z/b) end
local Vector2 = { new = function(x,y) return Vector3.new(x,y,0) end }
local CFrame = {}
local frameMeta = {}
function CFrame.new(position) return setmetatable({ Position=position, UpVector=Vector3.new(0,1,0), LookVector=Vector3.new(0,0,1) },frameMeta) end
function CFrame.lookAt(position, target) local f=CFrame.new(position); f.Target=target; f.LookVector=(target-position).Unit; return f end
frameMeta.__index = { Lerp = function(current, other, alpha)
    if current.HoldOrientation then current.Target=other.Target; current.Alpha=alpha; return current end
    other.Alpha=alpha; return other
end }
frameMeta.__mul = function(a,b) return a.Position+b end
local UDim2 = { new=function(...) return {...} end, fromOffset=function(...) return {...} end, fromScale=function(...) return {...} end }
local UDim = { new=function(...) return {...} end }
local Color3 = { fromRGB=function(...) return {...} end }
local Enum = {
    UserInputType={ MouseButton1="MouseButton1", MouseButton2="MouseButton2", MouseButton3="MouseButton3", Keyboard="Keyboard" },
    KeyCode={ Q="Q", Unknown="Unknown" },
    RaycastFilterType={ Exclude="Exclude" },
    HighlightDepthMode={ AlwaysOnTop="AlwaysOnTop", Occluded="Occluded" },
    Font={ Gotham="Gotham", GothamMedium="GothamMedium" },
    TextXAlignment={ Center="Center" },
    TextYAlignment={ Bottom="Bottom", Center="Center" },
    ZIndexBehavior={ Sibling="Sibling" },
}
local RaycastParams = { new=function() return {} end }
local Instance = {}
function Instance.new(class)
    local object={ ClassName=class, Parent=nil, Visible=true, Enabled=true }
    function object:IsA(name) return self.ClassName==name or (name=="BasePart" and self.ClassName=="Part") end
    function object:IsDescendantOf(ancestor) return self.Parent==ancestor or (self.Parent and self.Parent.IsDescendantOf and self.Parent:IsDescendantOf(ancestor)) or false end
    function object:Destroy() self.Destroyed=true; self.Parent=nil end
    table.insert(created, object)
    return object
end
local AimFactory = (function()
-- @AIM_SOURCE@
end)()
local ESPFactory = (function()
-- @ESP_SOURCE@
end)()
local Aim = AimFactory(function() error("No imports expected") end)
local ESP = ESPFactory(function() error("No imports expected") end)
local function fixture()
    local config={ ["Aim.Mode"]="Hold", ["Aim.Key"]="MouseButton2", ["Aim.Smoothness"]=0 }
    local diagnostics={}
    local input={ InputBegan=signal(), InputEnded=signal(), WindowFocusReleased=signal() }
    function input:GetFocusedTextBox() return nil end
    local workspace=Instance.new("Workspace")
    local camera=Instance.new("Camera")
    camera.Parent=workspace
    camera.CFrame=CFrame.new(Vector3.new(0,0,0))
    camera.ViewportSize=Vector2.new(800,600)
    function camera:WorldToViewportPoint(p) return Vector3.new(400+p.X*10,300-p.Y*10,p.Z), p.Z>0 end
    workspace.CurrentCamera=camera
    local raycastHit=nil
    function workspace:Raycast(_,_,_) return raycastHit end
    local records={}
    local authorized=true
    local ctx={ Services={ Workspace=workspace, UserInputService=input }, Player={Team="Blue",Neutral=false}, Gui=Instance.new("ScreenGui") }
    ctx.Config={ Get=function(_,key) return config[key] end }
    ctx.Diagnostics={ Set=function(_,key,value) diagnostics[key]=value end, Log=function() end }
    ctx.IsAuthorized=function() return authorized end
    ctx.Entities={ List=function() return records end }
    local function entity(x,z, category)
        local model=Instance.new("Model"); model.Parent=workspace
        local root=Instance.new("Part"); root.Parent=model; root.Position=Vector3.new(x,0,z); root.CFrame=CFrame.new(root.Position); root.Size=Vector3.new(2,4,2); root.AssemblyLinearVelocity=Vector3.new(0,0,0)
        local head=Instance.new("Part"); head.Parent=model; head.Position=root.Position; head.AssemblyLinearVelocity=root.AssemblyLinearVelocity
        function model:FindFirstChild(name) if name=="Head" then return head end; if name=="HumanoidRootPart" then return root end; return nil end
        function model:GetBoundingBox() return root.CFrame, root.Size end
        return { Instance=model, Model=model, Root=root, Humanoid={Health=100,MaxHealth=100}, Category=category or "NPC", Name="Lab Dummy" }
    end
    return { ctx=ctx, config=config, input=input, camera=camera, workspace=workspace, diagnostics=diagnostics, records=records, entity=entity,
        authorize=function(value) authorized=value end, occlude=function(value) raycastHit=value end }
end
local function press(f) f.input.InputBegan:Fire({ UserInputType="MouseButton2",KeyCode="Unknown" }, false) end
local f=fixture()
f.config["Aim.SwitchDelay"]=2
local aim=Aim.new(f.ctx)
aim:Init(); aim:Init(); aim:Enable(); press(f)
table.insert(f.records,f.entity(3,20)); table.insert(f.records,f.entity(1,30))
aim:Step(1/60)
assert(f.camera.CFrame.Target and f.camera.CFrame.Target.X==1,"Angle priority must acquire nearest projected target")
assert(type(f.diagnostics["Aim.AcquisitionMs"])=="number" and f.diagnostics["Aim.AcquisitionMs"]>=0,"Acquisition telemetry must measure input activation to first target")
assert(math.abs(f.diagnostics["Aim.AngularErrorDeg"])<0.00001,"Angular error must be measured against the applied camera orientation")
table.insert(f.records,f.entity(0.25,10)); aim:Step(1/60)
assert(f.camera.CFrame.Target.X==1,"TargetLock must retain a valid authorized target")
local retained=f.camera.CFrame
table.clear(f.records)
aim:Step(1/60)
assert(f.camera.CFrame==retained,"Removed registry target must never remain locked")
aim:Step(0.3)
assert(f.diagnostics["Aim.TrackingLosses"]==1,"An active registry invalidation must increment tracking loss once")
table.insert(f.records,f.entity(2,20)); aim:Step(1/60)
assert(f.camera.CFrame==retained,"Loss must respect SwitchDelay before acquiring a replacement")
aim:Step(3)
assert(f.camera.CFrame.Target.X==2,"A replacement must be acquired after SwitchDelay")
f.ctx.InputCaptured=true; aim:Step(1/60)
local captureFrame=f.camera.CFrame
f.ctx.InputCaptured=false; aim:Step(1/60)
assert(f.camera.CFrame==captureFrame,"Rebinding capture must clear held activation")
f.authorize(false); aim:Step(1/60)
assert(aim._enabled==false,"Authorization revocation must disable aiming immediately")
aim:Destroy(); aim:Destroy()
for _,entries in { f.input.InputBegan.callbacks, f.input.InputEnded.callbacks, f.input.WindowFocusReleased.callbacks } do
    for _,entry in entries do assert(not entry[2].Connected,"Destroy must disconnect every input connection") end
end
local h=fixture()
h.config["Aim.Priority"]="Distance"; h.config["Aim.Prediction"]=0.5
h.config["Aim.Smoothness"]=12
local near=h.entity(3,10)
h.camera.CFrame.HoldOrientation=true
near.Model:FindFirstChild("Head").AssemblyLinearVelocity=Vector3.new(2,0,0)
table.insert(h.records,h.entity(1,30)); table.insert(h.records,near)
local predicted=Aim.new(h.ctx); predicted:Enable(); press(h); predicted:Step(1/60)
assert(h.camera.CFrame.Target.X==4,"Distance priority and prediction seconds must select and lead the near target")
assert(math.abs(h.camera.CFrame.Alpha-(1-math.exp(-12/60)))<0.00001,"Smoothing must use exponential delta-time alpha")
local expectedAngular=math.deg(math.acos(10/math.sqrt(116)))
assert(math.abs(h.diagnostics["Aim.AngularErrorDeg"]-expectedAngular)<0.00001,"Angular error must expose remaining orientation error after interpolation")
local preOcclusion=h.camera.CFrame
h.occlude({Instance=Instance.new("Part")}); predicted:Step(1/60)
assert(h.camera.CFrame==preOcclusion and predicted._targetKey==nil,"A newly occluded aim target must lose its lock immediately")
predicted:Destroy()
local fallback=fixture()
fallback.config["Aim.Fallback"]=false
local bodyOnly=fallback.entity(1,20)
function bodyOnly.Model:FindFirstChild(_) return nil end
table.insert(fallback.records,bodyOnly)
local bodyAim=Aim.new(fallback.ctx); bodyAim:Enable(); press(fallback); bodyAim:Step(1/60)
assert(fallback.camera.CFrame.Target==nil,"Missing heads must be rejected when Fallback is false")
fallback.config["Aim.Fallback"]=true; bodyAim:UpdateConfig(); press(fallback); bodyAim:Step(1/60)
assert(fallback.camera.CFrame.Target~=nil,"Headless authorized targets must fall back to their Root")
bodyOnly.Humanoid.Health=0; local preDeath=fallback.camera.CFrame; bodyAim:Step(1/60)
assert(fallback.camera.CFrame==preDeath and bodyAim._targetKey==nil,"Dead targets must lose their aim lock immediately")
bodyAim:Destroy()
local sameTeam=fixture()
local teammate=sameTeam.entity(1,20,"Player"); teammate.Player={Team="Blue",Neutral=false}
table.insert(sameTeam.records,teammate)
local filtered=Aim.new(sameTeam.ctx); filtered:Enable(); press(sameTeam); filtered:Step(1/60)
assert(sameTeam.camera.CFrame.Target==nil,"TeamCheck must exclude teammates")
sameTeam.config["Aim.TeamCheck"]=false; filtered:UpdateConfig(); press(sameTeam); filtered:Step(1/60)
assert(sameTeam.camera.CFrame.Target~=nil,"Disabling TeamCheck must permit an authorized teammate")
filtered:Destroy()
local revoked=fixture()
table.insert(revoked.records,revoked.entity(1,20))
local revokedAim=Aim.new(revoked.ctx); revokedAim:Enable(); press(revoked); revokedAim:Step(1/60)
revoked.authorize(false); revokedAim:Step(1/60); revokedAim:Step(1/60)
assert(revoked.diagnostics["Aim.TrackingLosses"]==1,"Permission revocation while tracking must count exactly one loss")
revokedAim:Destroy()
local toggle=fixture()
toggle.config["Aim.Mode"]="Toggle"; toggle.config["Aim.Key"]="Q"
table.insert(toggle.records,toggle.entity(1,20))
local toggled=Aim.new(toggle.ctx); toggled:Enable()
toggle.input.InputBegan:Fire({UserInputType="Keyboard",KeyCode="Q"},false)
toggle.input.InputEnded:Fire({UserInputType="Keyboard",KeyCode="Q"})
toggled:Step(1/60)
assert(toggle.camera.CFrame.Target~=nil,"Keyboard toggle activation must survive key release")
local cameraMissingFrame=toggle.camera.CFrame
toggle.workspace.CurrentCamera=nil; toggle.ctx.InputCaptured=true; toggled:Step(1/60)
toggle.workspace.CurrentCamera=toggle.camera; toggle.ctx.InputCaptured=false; toggled:Step(1/60)
assert(toggle.camera.CFrame==cameraMissingFrame,"Input capture must clear activation even during a camera replacement")
toggle.input.InputBegan:Fire({UserInputType="Keyboard",KeyCode="Q"},false)
toggle.input.InputEnded:Fire({UserInputType="Keyboard",KeyCode="Q"})
toggle.input.WindowFocusReleased:Fire(); local focusFrame=toggle.camera.CFrame; toggled:Step(1/60)
assert(toggle.camera.CFrame==focusFrame,"Focus loss must clear toggle activation")
toggled:Destroy()
for _,mouseName in {"MouseButton1","MouseButton3"} do
    local mouse=fixture()
    mouse.config["Aim.Key"]=mouseName
    table.insert(mouse.records,mouse.entity(1,20))
    local mouseAim=Aim.new(mouse.ctx); mouseAim:Enable()
    mouse.input.InputBegan:Fire({UserInputType=mouseName,KeyCode="Unknown"},false)
    mouseAim:Step(1/60)
    assert(mouse.camera.CFrame.Target~=nil,mouseName.." must activate aiming when configured")
    local releaseFrame=mouse.camera.CFrame
    mouse.input.InputEnded:Fire({UserInputType=mouseName,KeyCode="Unknown"})
    mouseAim:Step(1/60)
    assert(mouse.camera.CFrame==releaseFrame,mouseName.." release must clear Hold activation")
    mouseAim:Destroy()
end
local g=fixture()
g.config["ESP.MaxElements"]=2
local esp=ESP.new(g.ctx)
esp:Init(); esp:Enable()
table.insert(g.records,g.entity(0,10)); table.insert(g.records,g.entity(0,20)); table.insert(g.records,g.entity(0,30))
esp:Step(1)
assert(g.diagnostics["ESP.Rendered"]==2,"Overlay cap must be enforced")
table.remove(g.records,1); esp:Step(0.001)
assert(g.diagnostics["ESP.Rendered"]==1,"Registry revocation must prune overlays before next throttled refresh")
table.insert(g.records,g.entity(0,10))
g.occlude({Instance=Instance.new("Part")}); esp:Step(1)
assert(g.diagnostics["ESP.Rendered"]==0,"Occluded targets must hide when ThroughWalls is false")
g.config["ESP.ThroughWalls"]=true; esp:UpdateConfig(); esp:Step(1)
assert(g.diagnostics["ESP.Rendered"]==2,"ThroughWalls must allow authorized occluded targets")
g.config["ESP.NPCs"]=false; esp:UpdateConfig(); esp:Step(1)
assert(g.diagnostics["ESP.Rendered"]==0,"Category changes must remove stale overlays")
g.authorize(false); esp:Step(1)
assert(esp._enabled==false,"Authorization revocation must disable overlays immediately")
esp:Destroy(); esp:Destroy()
print("CombatVisuals: lifecycle, priorities, locking/delay, head fallback, death, prediction, smoothing, input capture, revocation, occlusion and cap checks passed")
