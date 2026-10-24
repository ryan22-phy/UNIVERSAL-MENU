-- The interface is public. Lab permissions apply only to feature actions.
return function(import)
    local Cleanup=import("shared/CleanupManager")
    local ConfigManager=import("shared/ConfigManager")
    local Diagnostics=import("shared/Diagnostics")
    local ClientController={}
    function ClientController.Start()
        local environment=_G
        if type(getgenv)=="function" then
            local ok,value=pcall(getgenv)
            if ok and type(value)=="table" then environment=value
            else warn("[ VW ] environment/getgenv fallback: "..tostring(value)) end
        end
        local previous=environment.VWMenuLabRuntime
        if type(previous)=="table" and previous.Alive then
            if type(previous.Show)=="function" then previous:Show()
            elseif previous.Modules and previous.Modules.UI then previous.Modules.UI:Enable() end
            return previous
        end
        local services={}
        for _,name in ipairs({"Players","RunService","UserInputService","CollectionService","ReplicatedStorage","HttpService","TweenService","Workspace"}) do
            local ok,value=pcall(function() return game:GetService(name) end)
            if ok then services[name]=value else warn("[ VW ] service/"..name..": "..tostring(value)) end
        end
        local player=services.Players and services.Players.LocalPlayer
        assert(player,"[ VW ] environment/Players: LocalPlayer unavailable; execute in a Roblox client")
        local playerGui=player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui",10)
        assert(playerGui,"[ VW ] environment/PlayerGui: unavailable after 10s")
        local existing=playerGui:FindFirstChild("VWMenuLab")
        if existing then
            local reveal=existing:FindFirstChild("VWMenuReveal")
            if existing:GetAttribute("VWPublicRuntime")==true and reveal and reveal:IsA("BindableEvent") then
                reveal:Fire("Show")
                return {Alive=true,Show=function() reveal:Fire("Show") end,Destroy=function() reveal:Fire("Destroy") end}
            end
            error("[ VW ] duplicate/PlayerGui: VWMenuLab already exists without an ownership marker; unload the previous menu first",0)
        end
        local self={Alive=true,Modules={},Cleanup=Cleanup.new(),_profiles={},_fpsTime=0,_frames=0}
        local gui=Instance.new("ScreenGui")
        gui.Name="VWMenuLab"; gui.ResetOnSpawn=false; gui.Enabled=true; gui.IgnoreGuiInset=true
        gui.DisplayOrder=100; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
        gui:SetAttribute("VWPublicRuntime",true); gui.Parent=playerGui
        self.Cleanup:Add(gui)
        self.Context={Services=services,Player=player,Gui=gui,Cleanup=self.Cleanup}
        function self:Show()
            if not self.Alive then return end
            gui.Enabled=true
            local ui=self.Modules.UI
            if ui and type(ui.Show)=="function" then ui:Show()
            elseif self.Emergency then self.Emergency.Visible=true end
        end
        function self:Destroy()
            if not self.Alive then return end
            self.Alive=false
            for name,module in pairs(self.Modules) do
                for _,method in ipairs({"Disable","Destroy"}) do
                    if type(module[method])=="function" then
                        local ok,err=pcall(module[method],module)
                        if not ok then warn("[ VW ] unload/"..name.."/"..method..": "..tostring(err)) end
                    end
                end
            end
            self.Cleanup:Destroy()
            if environment.VWMenuLabRuntime==self then environment.VWMenuLabRuntime=nil end
        end
        local cached,cacheError=pcall(function() environment.VWMenuLabRuntime=self end)
        if not cached then warn("[ VW ] environment/cache: "..tostring(cacheError).."; PlayerGui marker remains active") end
        self.Cleanup:Add(gui.Destroying:Connect(function() self:Destroy() end))
        local reveal=Instance.new("BindableEvent"); reveal.Name="VWMenuReveal"; reveal.Parent=gui
        self.Cleanup:Add(reveal.Event:Connect(function(action)
            if action=="Show" then self:Show() elseif action=="Destroy" then self:Destroy() end
        end))
        local ok,failure=xpcall(function()
            local config=self.Cleanup:Add(ConfigManager.new())
            local diagnostics=self.Cleanup:Add(Diagnostics.new())
            local ctx=self.Context; ctx.Config=config; ctx.Diagnostics=diagnostics
            self.Config=config; self.Diagnostics=diagnostics
            local function report(name,stage,detail)
                local message=name.." | "..stage.." | "..tostring(detail).." | Fix: verify the installed module and compatible Roblox APIs"
                diagnostics:Log(name,"ERROR",message)
            end
            local insetOK,insetError=pcall(function() gui.ScreenInsets=Enum.ScreenInsets.None end)
            if not insetOK then diagnostics:Log("GUI","FALLBACK","ScreenInsets unavailable: "..tostring(insetError)) end
            local Policy={AllowedPlaceIds={},AuthorizedUserIds={},TargetUserIds={},AllowStudio=false,Version="4.0.0",VersionUrl=""}
            local policyOK,policyValue=pcall(import,"config/ClientPolicy")
            if policyOK and type(policyValue)=="table" then Policy=policyValue else report("ClientPolicy","import",policyValue) end
            local studio=false
            if services.RunService then
                local checked,value=pcall(function() return services.RunService:IsStudio() end)
                if checked then studio=value else report("RunService","IsStudio",value) end
            end
            local localAuthorized=(studio and Policy.AllowStudio==true) or
                (type(Policy.AllowedPlaceIds)=="table" and type(Policy.AuthorizedUserIds)=="table"
                and table.find(Policy.AllowedPlaceIds,game.PlaceId)~=nil and table.find(Policy.AuthorizedUserIds,player.UserId)~=nil)
            local function bridgeStub()
                return {Available=false,Latest={},Request=function(_,_,_,callback)
                    if callback then callback({Ok=false,Reason="LAB_SERVER_UNAVAILABLE",Data={Authorized=false}}) end
                    return false,"LAB_SERVER_UNAVAILABLE"
                end,Step=function() end}
            end
            local function entitiesStub() return {List=function() return {} end,Step=function() end} end
            ctx.Bridge=bridgeStub(); ctx.Entities=entitiesStub()
            ctx.IsAuthorized=function() return self.Alive and (localAuthorized or ctx.Bridge.Available==true) end
            diagnostics:Set("Version",Policy.Version or "4.0.0")
            diagnostics:Set("Interface.Public",true); diagnostics:Set("Authorization.Local",localAuthorized)
            diagnostics:Set("Environment",studio and "Studio" or "Roblox client; executor not certified")
            ctx.Actions={
                Unload=function() self:Destroy() end,
                Reset=function() config:Reset() end,
                Export=function() return services.HttpService:JSONEncode(config:Snapshot()) end,
                Import=function(json)
                    if type(json)~="string" or #json>16384 then return false,"JSON excede 16 KiB" end
                    local decoded, values=pcall(function() return services.HttpService:JSONDecode(json) end)
                    if not decoded then return false,"JSON inválido" end
                    return config:Import(values)
                end,
                SaveProfile=function(name)
                    if type(name)~="string" or #name<1 or #name>32 then return false,"Nome: 1–32 caracteres" end
                    local count=0; for _ in pairs(self._profiles) do count+=1 end
                    if not self._profiles[name] and count>=10 then return false,"Limite de 10 perfis em memória" end
                    self._profiles[name]=config:Snapshot(); return true
                end,
                LoadProfile=function(name)
                    if not self._profiles[name] then return false,"Perfil não encontrado" end
                    return config:Import(self._profiles[name])
                end,
                ListProfiles=function()
                    local names={};for name in pairs(self._profiles) do names[#names+1]=name end
                    table.sort(names);return names
                end,
                ApplyPreset=function(name) return config:ApplyPreset(name) end,
                ProbeHealth=function()
                    if not ctx.IsAuthorized() then diagnostics:Log("Health","REJECTED","Autorização necessária"); return false,"Autorização necessária" end
                    local module=self.Modules.Health
                    if module then return module:ProbeLocalHealth() end
                    return false,"Módulo de diagnóstico de saúde indisponível"
                end,
                RequestDamage=function()
                    local module=self.Modules.Health
                    if not module then return false,"Health diagnostics unavailable" end
                    return module:RequestDamage(10)
                end,
                RequestRestore=function()
                    local module=self.Modules.Health
                    if not module then return false,"Health diagnostics unavailable" end
                    return module:RestoreHealth()
                end,
                CheckVersion=function()
                    local url=Policy.VersionUrl
                    if url=="" then diagnostics:Log("Version","INFO","Configure ClientPolicy.VersionUrl com version.json Raw"); return end
                    if not url:match("^https://raw%.githubusercontent%.com/[^/]+/[^/]+/[^/]+/version%.json$") then
                        diagnostics:Log("Version","REJECTED","URL Raw de version.json inválida"); return
                    end
                    if self._checkingVersion then return end
                    self._checkingVersion=true
                    task.spawn(function()
                        local success, result=pcall(function()
                            local raw=game:HttpGet(url)
                            assert(type(raw)=="string" and #raw<8192,"Resposta de versão excedeu limite")
                            local data=services.HttpService:JSONDecode(raw)
                            assert(type(data)=="table" and type(data.version)=="string","Metadados inválidos")
                            return data.version
                        end)
                        if not self.Alive then return end
                        self._checkingVersion=false
                        diagnostics:Log("Version",success and "INFO" or "ERROR",success and ("Versão remota: "..result.."; atualização manual") or result)
                    end)
                end,
            }

            print("[ VW ] Initializing modules...")
            print("[ VW ] Creating interface...")
            local ui=import("shared/UIManager").new(ctx)
            self.Modules.UI=ui; ui:Init(); ui:Show()
            self.InterfaceReady=true
            diagnostics:Log("UI","READY","Public interface created; lab actions require authorization")
            print("[ VW ] Interface ready.")
            print("[VW] UI initialized")
            local function optional(name,path,constructor)
                local resource
                local loaded,value=pcall(function()
                    resource=constructor(import(path))
                    if resource.Init then resource:Init() end
                    return resource
                end)
                if loaded then
                    if type(value.Destroy)=="function" then self.Cleanup:Add(value) end
                    return value
                end
                if resource and resource.Destroy then
                    local cleaned,cleanupError=pcall(resource.Destroy,resource)
                    if not cleaned then report(name,"cleanup",cleanupError) end
                end
                report(name,"initialization",value)
                return nil
            end
            ctx.Bridge=optional("ServerBridge","client/ServerBridge",function(module) return module.new(ctx) end) or ctx.Bridge
            ctx.Adapters=optional("UniversalGameAdapter","client/UniversalGameAdapter",function(module) return module.new(ctx,Policy) end)
            ctx.Entities=optional("EntityRegistry","client/EntityRegistry",function(module) return module.new(ctx,Policy) end) or ctx.Entities
            local compatible,capabilities=pcall(function() return import("client/Compatibility").Probe(ctx) end)
            if compatible then self.Capabilities=capabilities else report("Compatibility","probe",capabilities) end
            local descriptors={{"Aim","client/AimAssist"},{"ESP","client/ESPManager"},{"Flight","client/FlightController"},{"Speed","client/SpeedController"},{"Health","client/HealthDiagnostics"}}
            local failed,active={},{UI=true}
            for _,descriptor in ipairs(descriptors) do
                local name,path=descriptor[1],descriptor[2]
                local made,result=pcall(function()
                    local module=import(path).new(ctx)
                    self.Modules[name]=module; module:Init()
                    return module
                end)
                if not made then
                    local partial=self.Modules[name]
                    if partial and partial.Destroy then
                        local cleaned,cleanupError=pcall(partial.Destroy,partial)
                        if not cleaned then report(name,"cleanup",cleanupError) end
                    end
                    self.Modules[name]=nil; failed[name]=true; report(name,"initialization",result)
                    diagnostics:Set(name..".Initialized",false);diagnostics:Set(name..".Status","ERROR")
                else
                    diagnostics:Set(name..".Initialized",true)
                    diagnostics:Set(name..".Status","MODULE READY")
                    print("[VW] "..(name=="Aim" and "AimAssist" or name).." initialized")
                end
            end
            print("[VW] Modules ready")
            self.Cleanup:Add(config:Subscribe(function(path,value)
                if path=="Settings.Adapter" and ctx.Entities.Invalidate then ctx.Entities:Invalidate() end
                for name,module in pairs(self.Modules) do
                    if name~="UI" and module.UpdateConfig and not failed[name] then
                        local updated,err=pcall(module.UpdateConfig,module,path,value)
                        if not updated then report(name,"configuration",err) end
                    end
                end
            end))
            local bridgeFailed,entitiesFailed=false,false
            local timings={}
            local function step(dt)
                if not self.Alive then return end
                if ctx.Adapters then
                    local stepped,err=pcall(ctx.Adapters.Step,ctx.Adapters,dt)
                    if not stepped then
                        report("UniversalGameAdapter","step",err)
                        pcall(ctx.Adapters.Destroy,ctx.Adapters);ctx.Adapters=nil
                    end
                end
                if not bridgeFailed then
                    local stepped,err=pcall(ctx.Bridge.Step,ctx.Bridge,dt)
                    if not stepped then bridgeFailed=true; ctx.Bridge.Available=false; report("ServerBridge","step",err) end
                end
                if not entitiesFailed then
                    local stepped,err=pcall(ctx.Entities.Step,ctx.Entities,dt)
                    if not stepped then entitiesFailed=true; ctx.Entities=entitiesStub(); report("EntityRegistry","step",err) end
                end
                local authorized=ctx.IsAuthorized(); diagnostics:Set("Authorization.Effective",authorized)
                for _,descriptor in ipairs(descriptors) do
                    local name=descriptor[1]; local module=self.Modules[name]
                    if module and not failed[name] then
                        local desired=authorized and (name=="Health" or config:Get(name..".Enabled")==true)
                        local configured=name=="Health" or config:Get(name..".Enabled")==true
                        diagnostics:Set(name..".Configured",configured)
                        diagnostics:Set(name..".Status",configured and not authorized and "SERVER RESTRICTION" or desired and "MODULE READY" or "MODULE DISABLED")
                        local started=os.clock()
                        local stepped,err=pcall(function()
                            if desired~=(active[name]==true) then
                                if desired then module:Enable() else module:Disable() end
                                active[name]=desired; diagnostics:Set(name..".Requested",desired)
                            end
                            if desired or name=="Health" then module:Step(dt) end
                        end)
                        local ms=(os.clock()-started)*1000
                        timings[name]=timings[name] and timings[name]*0.9+ms*0.1 or ms
                        if not stepped then
                            failed[name]=true; active[name]=false
                            local disabled,disableError=pcall(module.Disable,module)
                            if not disabled then report(name,"disable",disableError) end
                            report(name,"step",err)
                            diagnostics:Set(name..".Status","ERROR")
                        end
                    end
                end
                self._fpsTime+=dt; self._frames+=1
                if self._fpsTime>=0.5 then
                    diagnostics:Set("FPS",math.floor(self._frames/self._fpsTime+0.5))
                    local slowest,slowestMs="—",0
                    for name,ms in pairs(timings) do
                        diagnostics:Set("Timing."..name..".StepMs",math.floor(ms*1000)/1000)
                        if ms>slowestMs then slowest,slowestMs=name,ms end
                    end
                    diagnostics:Set("Timing.SlowestModule",slowest)
                    diagnostics:Set("Timing.Scope","Client Lua CPU sample (EWMA); excludes engine render/physics/server")
                    self._fpsTime=0; self._frames=0
                end
                if not failed.UI then
                    local rendered,err=pcall(ui.Step,ui,dt)
                    if not rendered then failed.UI=true; report("UI","step",err) end
                end
            end
            local binding="VWMenuLabStep_"..tostring(self)
            self.Cleanup:Add(function()
                local stopped,err=pcall(function() services.RunService:UnbindFromRenderStep(binding) end)
                if not stopped then warn("[ VW ] render/unbind: "..tostring(err)) end
            end)
            local bound,bindError=pcall(function() services.RunService:BindToRenderStep(binding,Enum.RenderPriority.Camera.Value+1,step) end)
            if bound then diagnostics:Set("Render.Scheduler","BindToRenderStep") end
            if not bound then
                report("RunService","BindToRenderStep",bindError)
                self.Cleanup:Add(services.RunService.Heartbeat:Connect(step))
                diagnostics:Set("Render.Scheduler","Heartbeat")
                diagnostics:Log("RunService","FALLBACK","Heartbeat scheduling active")
            end
        end,debug.traceback)
        if not ok then
            warn("[ VW ] initialization/ClientController: "..tostring(failure).." | Fix: inspect Diagnostics or run smoke-test.luau")
            if self.InterfaceReady and self.Modules.UI then
                self.Diagnostics:Set("Render.Scheduler","NONE")
                self.Diagnostics:Log("Bootstrap","ERROR",tostring(failure).." | Fix: UI remains public; inspect render/Heartbeat support before enabling lab modules")
                self.Context.Bridge.Available=false
                local refreshed,refreshError=pcall(function() self:Show(); self.Modules.UI:Step(0.5) end)
                if not refreshed then warn("[ VW ] UI/diagnostic refresh: "..tostring(refreshError)) end
                return self
            end
            local shown,showError=pcall(function()
                local partial=self.Modules.UI
                if partial then partial:Destroy(); self.Modules.UI=nil end
                local panel=Instance.new("TextLabel")
                panel.Name="VWInitializationError"; panel.Size=UDim2.new(0.8,0,0.5,0)
                panel.Position=UDim2.new(0.1,0,0.1,0); panel.TextWrapped=true
                panel.BackgroundColor3=Color3.fromRGB(8,13,23); panel.TextColor3=Color3.fromRGB(134,213,255)
                panel.Text="VW MENU — startup diagnostic\n"..tostring(failure).."\nFix: run smoke-test.luau and check module installation."
                panel.Parent=gui; self.Emergency=panel
                local close=Instance.new("TextButton"); close.Text="Unload VW MENU"
                close.Size=UDim2.fromOffset(180,32); close.Position=UDim2.new(0.1,0,0.62,0); close.Parent=gui
                self.Cleanup:Add(close.Activated:Connect(function() self:Destroy() end))
            end)
            if not shown then self:Destroy(); error("[ VW ] GUI emergency failure: "..tostring(showError).."; original: "..tostring(failure),0) end
        end
        return self
    end
    return ClientController
end
