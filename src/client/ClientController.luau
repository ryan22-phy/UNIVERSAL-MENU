return function(import)
    local Cleanup = import("shared/CleanupManager")
    local ConfigManager = import("shared/ConfigManager")
    local Diagnostics = import("shared/Diagnostics")
    local Policy = import("config/ClientPolicy")
    local ClientController = {}

    function ClientController.Start()
        local environment = _G
        pcall(function() if type(getgenv)=="function" and type(getgenv())=="table" then environment=getgenv() end end)
        local previous = environment.VWMenuLabRuntime
        if type(previous)=="table" and previous.Alive then return previous end
        local self = { Alive=true, Modules={}, Cleanup=Cleanup.new(), _profiles={}, _fpsTime=0, _frames=0 }
        function self:Destroy()
            if not self.Alive then return end
            self.Alive=false
            for _, module in pairs(self.Modules) do
                if module.Disable then pcall(function() module:Disable() end) end
                if module.Destroy then pcall(function() module:Destroy() end) end
            end
            self.Cleanup:Destroy()
            if environment.VWMenuLabRuntime==self then environment.VWMenuLabRuntime=nil end
        end
        environment.VWMenuLabRuntime=self
        local ok, failure = xpcall(function()
            local services = {}
            for _, name in ipairs({"Players","RunService","UserInputService","CollectionService","ReplicatedStorage","HttpService","Workspace"}) do
                services[name]=game:GetService(name)
            end
            local player = services.Players.LocalPlayer
            assert(player, "VW MENU deve executar no cliente")
            local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
            assert(playerGui, "PlayerGui ausente após 10s")
            local config = self.Cleanup:Add(ConfigManager.new())
            local diagnostics = self.Cleanup:Add(Diagnostics.new())
            local gui = Instance.new("ScreenGui")
            gui.Name="VWMenuLab"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true
            pcall(function() gui.ScreenInsets=Enum.ScreenInsets.None end)
            gui.DisplayOrder=100; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
            gui.Parent=playerGui; self.Cleanup:Add(gui)
            local ctx = { Services=services, Player=player, Config=config, Diagnostics=diagnostics, Cleanup=self.Cleanup, Gui=gui }
            self.Context=ctx
            local studio = services.RunService:IsStudio()
            local localAuthorized = (studio and Policy.AllowStudio == true)
                or (table.find(Policy.AllowedPlaceIds, game.PlaceId)~=nil
                    and table.find(Policy.AuthorizedUserIds, player.UserId)~=nil)
            ctx.IsAuthorized=function() return self.Alive and (localAuthorized or ctx.Bridge.Available) end
            ctx.Bridge=self.Cleanup:Add(import("client/ServerBridge").new(ctx)); ctx.Bridge:Init()
            ctx.Entities=self.Cleanup:Add(import("client/EntityRegistry").new(ctx, Policy))
            self.Capabilities=import("client/Compatibility").Probe(ctx)
            self.Config=config; self.Diagnostics=diagnostics
            diagnostics:Set("Version", Policy.Version)
            diagnostics:Set("Authorization.Local", localAuthorized)
            diagnostics:Set("Environment", studio and "Studio" or "Roblox client / executor não identificado")
            diagnostics:Log("Runtime", "INITIALIZED", "Menu local criado; recursos dependem de autorização")

            local descriptors = {
                {"Aim","client/AimAssist"}, {"ESP","client/ESPManager"},
                {"Flight","client/FlightController"}, {"Speed","client/SpeedController"},
                {"Health","client/HealthDiagnostics"},
            }
            local failed, active = {}, {}
            for _, descriptor in ipairs(descriptors) do
                local name, path=descriptor[1], descriptor[2]
                local made, result=pcall(function()
                    local module=import(path).new(ctx)
                    self.Modules[name]=module
                    module:Init()
                    return module
                end)
                if not made then
                    diagnostics:Log(name,"ERROR",result); failed[name]=true
                    local partial=self.Modules[name]
                    if partial and partial.Destroy then pcall(function() partial:Destroy() end) end
                    self.Modules[name]=nil
                else diagnostics:Set(name..".Initialized",true) end
            end

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
                ProbeHealth=function()
                    if not ctx.IsAuthorized() then diagnostics:Log("Health","REJECTED","Autorização necessária"); return false,"Autorização necessária" end
                    local module=self.Modules.Health
                    if module then return module:ProbeLocalHealth() end
                    return false,"Módulo de diagnóstico de saúde indisponível"
                end,
                RequestDamage=function()
                    return ctx.Bridge:Request("Damage",{Amount=10})
                end,
                RequestRestore=function() return ctx.Bridge:Request("RestoreHealth",{}) end,
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
            local ui=import("shared/UIManager").new(ctx)
            self.Modules.UI=ui; ui:Init()
            self.Cleanup:Add(config:Subscribe(function(path,value)
                for name,module in pairs(self.Modules) do
                    if module.UpdateConfig and not failed[name] then
                        local updated,err=pcall(function() module:UpdateConfig(path,value) end)
                        if not updated then diagnostics:Log(name,"ERROR",err) end
                    end
                end
            end))
            self.Cleanup:Add(gui.Destroying:Connect(function() self:Destroy() end))
            local binding="VWMenuLabStep"
            self.Cleanup:Add(function() services.RunService:UnbindFromRenderStep(binding) end)
            services.RunService:BindToRenderStep(binding,Enum.RenderPriority.Camera.Value+1,function(dt)
                if not self.Alive then return end
                ctx.Bridge:Step(dt); ctx.Entities:Step(dt)
                local authorized=ctx.IsAuthorized()
                diagnostics:Set("Authorization.Effective",authorized)
                for _,descriptor in ipairs(descriptors) do
                    local name=descriptor[1]; local module=self.Modules[name]
                    if module and not failed[name] then
                        local desired=authorized and (name=="Health" or config:Get(name..".Enabled")==true)
                        local stepped,err=pcall(function()
                            if desired~= (active[name]==true) then
                                if desired then module:Enable() else module:Disable() end
                                active[name]=desired
                                diagnostics:Set(name..".Active",desired)
                            end
                            module:Step(dt)
                        end)
                        if not stepped then
                            failed[name]=true; active[name]=false
                            pcall(function() module:Disable() end)
                            diagnostics:Set(name..".Active",false); diagnostics:Log(name,"ERROR",err)
                        end
                    end
                end
                self._fpsTime+=dt; self._frames+=1
                if self._fpsTime>=0.5 then
                    diagnostics:Set("FPS",math.floor(self._frames/self._fpsTime+0.5))
                    self._fpsTime=0; self._frames=0
                end
                local rendered,err=pcall(function() ui:Step(dt) end)
                if not rendered and not failed.UI then failed.UI=true; diagnostics:Log("UI","ERROR",err) end
            end)
        end,debug.traceback)
        if not ok then self:Destroy(); error("VW MENU inicialização: "..tostring(failure),0) end
        return self
    end
    return ClientController
end
