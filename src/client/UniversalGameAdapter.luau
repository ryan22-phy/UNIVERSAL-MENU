-- Structural recognition only. Discovery never grants target or server permission.
return function(_import)
    local UniversalGameAdapter = {}
    UniversalGameAdapter.__index = UniversalGameAdapter
    local function namedPart(model, name)
        local part = model and model:FindFirstChild(name)
        return part and part:IsA("BasePart") and part.Parent and part:IsDescendantOf(model) and part or nil
    end
    local function rigName(humanoid)
        if not humanoid then return "Unknown" end
        local ok, name = pcall(function() return humanoid.RigType.Name end)
        return ok and (name=="R6" or name=="R15") and name or "Custom"
    end
    local function validName(name)
        return type(name)=="string" and #name>0 and #name<=64 and not name:find("[%c]")
    end
    local function generic(instance)
        local model = instance:IsA("Model") and instance or nil
        local humanoid = model and model:FindFirstChildOfClass("Humanoid")
        local root = instance:IsA("BasePart") and instance
            or instance:IsA("Tool") and namedPart(instance,"Handle")
            or model and (namedPart(model,"HumanoidRootPart") or model.PrimaryPart or namedPart(model,"Head")
                or model:FindFirstChildWhichIsA("BasePart",true))
        if not root or not root:IsA("BasePart") then return nil,"ROOT_NOT_FOUND" end
        if root~=instance and not root:IsDescendantOf(instance) then return nil,"INVALID_ROOT" end
        return {Root=root,Model=model,Humanoid=humanoid,Head=model and namedPart(model,"Head"),Rig=rigName(humanoid)}
    end
    local GenericRobloxAdapter={Name="GenericRobloxAdapter",Match=function() return true end,Resolve=generic}
    local function rigAdapter(name)
        return {Name=name.."CharacterAdapter",Match=function(instance)
            return instance:IsA("Model") and rigName(instance:FindFirstChildOfClass("Humanoid"))==name
        end,Resolve=generic}
    end
    local TaggedItemAdapter={Name="TaggedItemAdapter",Match=function(instance,category)
        return category=="Item" and (instance:IsA("Tool") or instance:IsA("Model") or instance:IsA("BasePart"))
    end,Resolve=generic}

    function UniversalGameAdapter.new(ctx,policy)
        local self=setmetatable({ctx=ctx,policy=policy or {},_registry={},_elapsed=1,_errors={},_destroyed=false},UniversalGameAdapter)
        local custom=self.policy.CustomAdapter
        if type(custom)=="table" then
            self.Custom={}
            for _,key in ipairs({"RootName","HeadName","TeamAttribute"}) do
                if validName(custom[key]) then self.Custom[key]=custom[key] end
            end
        end
        local CustomGameAdapter={Name="CustomGameAdapter",Match=function(instance,category)
            return self.Custom~=nil and category~="Item" and instance:IsA("Model")
        end,Resolve=function(instance)
            if not self.Custom then return nil,"CUSTOM_ADAPTER_NOT_CONFIGURED" end
            local record,reason=generic(instance)
            if not record then return nil,reason end
            if self.Custom.RootName then record.Root=namedPart(instance,self.Custom.RootName) end
            if self.Custom.HeadName then record.Head=namedPart(instance,self.Custom.HeadName) end
            if not record.Root then return nil,"CUSTOM_ROOT_NOT_FOUND" end
            record.HeadName=self.Custom.HeadName or "Head"
            record.RootName=self.Custom.RootName
            return record
        end}
        self:Register(CustomGameAdapter)
        self:Register(TaggedItemAdapter)
        self:Register(rigAdapter("R15"));self:Register(rigAdapter("R6"));self:Register(GenericRobloxAdapter)
        return self
    end

    function UniversalGameAdapter:Register(adapter)
        if self._destroyed or type(adapter)~="table" or not validName(adapter.Name)
            or type(adapter.Match)~="function" or type(adapter.Resolve)~="function" then return false,"INVALID_ADAPTER" end
        if #self._registry>=32 then return false,"ADAPTER_LIMIT" end
        for index,entry in ipairs(self._registry) do
            if entry.Name==adapter.Name then return false,"DUPLICATE_ADAPTER" end
            if entry.Name=="GenericRobloxAdapter" then table.insert(self._registry,index,adapter);return true end
        end
        self._registry[#self._registry+1]=adapter
        return true
    end

    function UniversalGameAdapter:_report(reason)
        if self._errors[reason] then return end
        local count=0;for _ in pairs(self._errors) do count+=1 end
        if count>=32 then return end
        -- The set is bounded by adapter/reason names, never by entity instance names.
        self._errors[reason]=true
        self.ctx.Diagnostics:Log("Adapter","UNSUPPORTED STRUCTURE",reason.."; configure ClientPolicy.CustomAdapter or use the generic mode")
    end

    function UniversalGameAdapter:Describe(instance,player,category,subcategory)
        if self._destroyed or not instance or not instance.Parent then return nil end
        local mode=self.ctx.Config and self.ctx.Config:Get("Settings.Adapter") or "Auto"
        mode=mode or "Auto"
        if mode=="CustomGameAdapter" and not self.Custom then self:_report("CUSTOM_ADAPTER_NOT_CONFIGURED");return nil end
        for _,adapter in ipairs(self._registry) do
            if mode=="Auto" or mode==adapter.Name then
                local ok,matched=pcall(adapter.Match,instance,category)
                if ok and matched then
                    local resolved,record,reason=pcall(adapter.Resolve,instance,category)
                    if resolved and type(record)=="table" then
                        local valid,rootValid=pcall(function()
                            return record.Root and record.Root:IsA("BasePart") and record.Root.Parent
                                and (record.Root==instance or record.Root:IsDescendantOf(instance))
                        end)
                        if not valid or not rootValid then self:_report(adapter.Name..":INVALID_ROOT");return nil end
                        if category~="Item" and not record.Humanoid then self:_report("HUMANOID_NOT_FOUND");return nil end
                        record.Instance=instance;record.Player=player;record.Category=category
                        record.Subcategory=subcategory or (category=="Item" and "TestObjects" or category)
                        record.Name=player and player.DisplayName or instance.Name
                        record.Adapter=adapter.Name
                        local _,color,label=self:TeamIdentity(player,record.Model)
                        record.TeamColor=color;record.TeamLabel=label
                        return record
                    end
                    self:_report(adapter.Name..":"..tostring(resolved and reason or record))
                elseif not ok then self:_report(adapter.Name..":MATCH_FAILED") end
            end
        end
        self:_report("NO_COMPATIBLE_STRUCTURE")
        return nil
    end

    function UniversalGameAdapter:TeamIdentity(player,model)
        -- Neutral players may retain a stale Team/TeamColor. Do not compare those values.
        if player and player.Neutral~=true and player.Team~=nil then
            local team=player.Team
            local ok,color=pcall(function() return team.TeamColor.Color end)
            local named,label=pcall(function() return team.Name end)
            return team,ok and color or nil,named and label or "Team"
        end
        local attribute=self.Custom and self.Custom.TeamAttribute
        if attribute then
            local source=player or model
            local ok,value=pcall(function() return source and source:GetAttribute(attribute) end)
            if ok and (type(value)=="string" and #value>0 and #value<=64 or type(value)=="number" and value==value and math.abs(value)<math.huge) then
                return "Custom:"..type(value)..":"..tostring(value),nil,tostring(value)
            end
        end
        return nil,nil,player and player.Neutral==true and "Neutral" or "No team"
    end

    function UniversalGameAdapter:SameTeam(localPlayer,targetPlayer,targetModel)
        local first=self:TeamIdentity(localPlayer,localPlayer and localPlayer.Character)
        local second=self:TeamIdentity(targetPlayer,targetModel)
        return first~=nil and second~=nil and first==second
    end

    function UniversalGameAdapter:ResolveAimPart(record,config)
        local model=record.Model
        local head=namedPart(model,record.HeadName or "Head")
        record.Head=head
        if config.Fallback==false then return head end
        if config.HeadPriority~=false and head then return head end
        local fallback=config.FallbackPart or "HumanoidRootPart"
        if fallback=="HumanoidRootPart" and record.RootName then fallback=record.RootName end
        return namedPart(model,fallback)
    end

    function UniversalGameAdapter:IsWorldItem(instance)
        local world=self.ctx.Services.Workspace
        if not instance:IsDescendantOf(world) then return false end
        local parent=instance.Parent
        for _=1,64 do
            if not parent or parent==world then return true end
            if parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then return false end
            parent=parent.Parent
        end
        return false
    end

    function UniversalGameAdapter:Step(dt)
        if self._destroyed then return end
        local world=self.ctx.Services.Workspace
        if world.CurrentCamera~=self._camera then
            self._camera=world.CurrentCamera
            self.ctx.Diagnostics:Set("Adapter.Camera",self._camera and "CURRENT_CAMERA" or "CAMERA NOT FOUND")
        end
        self._elapsed+=dt
        if self._elapsed<1 then return end
        self._elapsed=0
        local mode=self.ctx.Config and self.ctx.Config:Get("Settings.Adapter") or "Auto"
        self.ctx.Diagnostics:Set("Adapter.Mode",mode or "Auto")
        self.ctx.Diagnostics:Set("Adapter.StreamingEnabled",world.StreamingEnabled==true)
        self.ctx.Diagnostics:Set("Adapter.Replication","Only replicated instances; unstreamed/server-only content is unknown")
        local character=self.ctx.Player and self.ctx.Player.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        self.ctx.Diagnostics:Set("Adapter.CharacterRig",character and rigName(humanoid) or "CHARACTER NOT FOUND")
        local teams,count={},0
        for _,player in ipairs(self.ctx.Services.Players:GetPlayers()) do
            local team=self:TeamIdentity(player,player.Character)
            if team~=nil and not teams[team] then teams[team]=true;count+=1 end
        end
        self.ctx.Diagnostics:Set("Adapter.DetectedTeams",count)
    end

    function UniversalGameAdapter:Destroy()
        self._destroyed=true;self._camera=nil;table.clear(self._registry);table.clear(self._errors)
    end
    UniversalGameAdapter.GenericRobloxAdapter=GenericRobloxAdapter
    UniversalGameAdapter.TaggedItemAdapter=TaggedItemAdapter
    return UniversalGameAdapter
end
