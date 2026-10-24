-- Actual bootstrap + actual shared utilities, with simulated Roblox service boundaries.
-- The UI boundary is a small stub; rendering is not tested here (ui.spec tests UI logic).
local checks=0
local function check(value,reason) checks+=1; assert(value,reason) end
local function fixture(options)
    options=options or {}
    local state={Logs={},Objects={},Bindings={},UIFrames=0,FeatureEnables=0,FullUIRefreshes=0}
    local function signal()
        local listeners={}
        return {Connect=function(_,callback)
            local connection={Connected=true}
            function connection:Disconnect() self.Connected=false end
            connection.Destroy=connection.Disconnect
            listeners[#listeners+1]={Connection=connection,Callback=callback}
            return connection
        end,Fire=function(_,...)
            for _,listener in ipairs(listeners) do if listener.Connection.Connected then listener.Callback(...) end end
        end,Count=function()
            local count=0; for _,listener in ipairs(listeners) do if listener.Connection.Connected then count+=1 end end
            return count
        end}
    end
    local function object(class)
        local value={ClassName=class,Children={},Attributes={},Destroying=signal(),Activated=signal()}
        function value:IsA(name) return self.ClassName==name end
        function value:SetAttribute(k,v) self.Attributes[k]=v end
        function value:GetAttribute(k) return self.Attributes[k] end
        function value:FindFirstChild(name)
            for _,child in ipairs(self.Children) do if child.Name==name and not child.Destroyed then return child end end
        end
        function value:Destroy()
            if self.Destroyed then return end
            self.Destroyed=true; self.Destroying:Fire()
            for _,child in ipairs(self.Children) do child:Destroy() end
        end
        if class=="BindableEvent" then value.Event=signal(); function value:Fire(...) self.Event:Fire(...) end end
        setmetatable(value,{__newindex=function(self,key,v)
            rawset(self,key,v)
            if key=="Parent" and v then v.Children[#v.Children+1]=self end
        end})
        state.Objects[#state.Objects+1]=value
        return value
    end
    local playerGui=object("PlayerGui")
    local player={UserId=123,Character={}}
    function player:FindFirstChildOfClass() return playerGui end
    function player:WaitForChild(_,timeout) check(timeout<=10,"bounded PlayerGui wait"); return playerGui end
    local run={Heartbeat=signal()}
    if options.heartbeatFailure then function run.Heartbeat:Connect() error("heartbeat unavailable") end end
    function run:IsStudio() return false end
    function run:BindToRenderStep(name,_,callback)
        if options.bindFailure then error("render binding unsupported") end
        state.Bindings[name]=callback
    end
    function run:UnbindFromRenderStep(name) state.Bindings[name]=nil end
    local services={Players={LocalPlayer=player},RunService=run,UserInputService={},
        HttpService={JSONEncode=function() return "{}" end,JSONDecode=function() return {} end},
        Workspace={},CollectionService={},ReplicatedStorage={}}
    local game={PlaceId=999,GetService=function(_,name) return services[name] end}
    local Enum={ZIndexBehavior={Sibling=1},ScreenInsets={None=1},RenderPriority={Camera={Value=200}},KeyCode={GetEnumItems=function() return {} end}}
    local UDim2={new=function(...) return {...} end,fromOffset=function(...) return {...} end}
    local Color3={fromRGB=function(...) return {...} end}
    local Instance={new=object}
    local _G={}
    local print=function(...) state.Logs[#state.Logs+1]=table.concat({...}," ") end
    local warn=print
    local factories={}
    factories["shared/CleanupManager"]=(function()
-- @CLEANUP_SOURCE@
    end)()
    factories["shared/ConfigManager"]=(function()
-- @CONFIG_SOURCE@
    end)()
    factories["shared/Diagnostics"]=(function()
-- @DIAGNOSTICS_SOURCE@
    end)()
    factories["client/ClientController"]=(function()
-- @BOOTSTRAP_SOURCE@
    end)()
    local UI={new=function(ctx)
        local ui={Ctx=ctx}
        function ui:Init()
            if options.uiFailure then error("UI missing native class") end
            self.Window={Visible=true}; state.UI=self
        end
        function ui:Show() self.Window.Visible=true end
        function ui:Enable() self:Show() end
        function ui:Disable() if self.Window then self.Window.Visible=false end end
        function ui:Destroy() self.Destroyed=true end
        function ui:Step() state.UIFrames+=1 end
        function ui:UpdateConfig() state.FullUIRefreshes+=1 end
        return ui
    end}
    local cache={}
    local function import(name)
        if options.missing==name then error("Missing module: "..name) end
        if cache[name] then return cache[name] end
        local result
        if factories[name] then result=factories[name](import)
        elseif name=="shared/UIManager" then result=UI
        elseif name=="config/ClientPolicy" then result={AllowedPlaceIds={},AuthorizedUserIds={},TargetUserIds={},AllowStudio=false,Version="1.0.1"}
        elseif name=="client/Compatibility" then result={Probe=function() if options.probeFailure then error("probe failed") end; return {} end}
        elseif name=="client/ServerBridge" then result={new=function()
            return {Available=false,Latest={},Init=function() end,Request=function() return false end,
                Step=function() if options.bridgeFailure then error("bridge step failed") end end,Destroy=function() end}
        end}
        elseif name=="client/EntityRegistry" then result={new=function() return {Step=function() end,List=function() return {} end,Destroy=function() end} end}
        else result={new=function()
            return {Init=function() end,Enable=function() state.FeatureEnables+=1 end,Disable=function() end,
                Step=function() if options.featureFailure then error("feature step failed") end end,Destroy=function() end}
        end} end
        cache[name]=result; return result
    end
    state.start=function() return import("client/ClientController").Start() end
    state.newEnvironment=function() _G={} end
    state.step=function()
        for _,callback in pairs(state.Bindings) do callback(0.5) end
        run.Heartbeat:Fire(0.5)
    end
    state.player=player; state.playerGui=playerGui; state.run=run
    return state
end
local f=fixture(); local runtime=f.start()
check(runtime.Alive and f.UI.Window.Visible,"public first execution visible")
check(runtime.Context.IsAuthorized()==false,"lab remains unauthorized")
check(runtime.Context.Gui.Enabled and runtime.Context.Gui.ResetOnSpawn==false,"public GUI survives respawn")
runtime.Config:Set("Aim.Enabled",true); f.step()
check(f.FullUIRefreshes==0,"UI owns config subscription; feature loop must not settle UI animations")
check(f.FeatureEnables==0,"public UI does not grant privileged actions")
check(f.UIFrames==1,"UI frame executes without lab authorization")
f.UI.Window.Visible=false; local duplicate=f.start()
check(duplicate==runtime and f.UI.Window.Visible,"same environment duplicate reopens")
f.UI.Window.Visible=false; f.newEnvironment(); local proxy=f.start()
check(proxy.Alive and f.UI.Window.Visible,"ownership marker handles another environment")
runtime:Destroy(); check(not runtime.Alive and next(f.Bindings)==nil,"unload clears render binding")
runtime:Destroy(); check(runtime.Context.Gui.Destroyed,"idempotent unload destroys GUI")
for _,missing in ipairs({"client/AimAssist","client/ServerBridge","client/EntityRegistry","client/Compatibility","config/ClientPolicy"}) do
    local state=fixture({missing=missing}); local app=state.start(); state.step()
    check(app.Alive and state.UI.Window.Visible,"optional failure must preserve UI: "..missing)
    check(#app.Diagnostics:Snapshot().Events>=2,"optional failure recorded: "..missing)
    app:Destroy()
end
for _,options in ipairs({{bridgeFailure=true},{featureFailure=true},{probeFailure=true},{bindFailure=true}}) do
    local state=fixture(options); local app=state.start(); state.step(); state.step()
    check(app.Alive and state.UI.Window.Visible,"runtime fault preserves UI")
    check(state.UIFrames==2,"runtime fault must not stop UI Step")
    app:Destroy(); check(state.run.Heartbeat:Count()==0,"fallback connection cleanup")
end
local broken=fixture({uiFailure=true}); local app=broken.start()
check(app.Alive and app.Emergency and app.Emergency.Parent==app.Context.Gui,"essential UI failure has visible native diagnostic")
app:Destroy()
local scheduling=fixture({bindFailure=true,heartbeatFailure=true}); local visible=scheduling.start()
check(visible.InterfaceReady and scheduling.UI.Window.Visible and not scheduling.UI.Destroyed,"scheduler failure after READY must preserve usable public UI")
check(visible.Diagnostics:Snapshot().Values["Render.Scheduler"]=="NONE","scheduler failure reported accurately")
visible:Destroy()
print("PASS bootstrap: "..checks.." checks; native boundaries and UI stub, no rendering validation")
