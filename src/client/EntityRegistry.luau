-- Opt-in registry: adapters describe structure; this service owns permission and discovery.
return function(_import)
    local EntityRegistry = {}
    EntityRegistry.__index = EntityRegistry
    local categoryTags = {
        {"DroppedItem","DroppedItems"},{"Loot","Loot"},{"WeaponPickup","Weapons"},
        {"ToolPickup","Tools"},{"TestCollectible","Collectibles"},{"Objective","Objectives"},
        {"VWTestItem","TestObjects"},{"TestObject","TestObjects"},
    }
    local validCategories={DroppedItems=true,Loot=true,Weapons=true,Tools=true,Collectibles=true,Objectives=true,TestObjects=true}
    local function includes(list,value) return type(list)=="table" and table.find(list,value)~=nil end
    function EntityRegistry.new(ctx,policy)
        local tags=table.clone(categoryTags)
        local extra=policy and policy.CustomItemTags
        if type(extra)=="table" then
            local count=0
            for tag,category in pairs(extra) do
                if count>=32 then break end
                if type(tag)=="string" and #tag>0 and #tag<=64 and validCategories[category] then
                    tags[#tags+1]={tag,category};count+=1
                end
            end
        end
        return setmetatable({ctx=ctx,policy=policy or {},_records={},_tags=tags,_elapsed=1,_destroyed=false,_connections={},_dirty=true},EntityRegistry)
    end
    function EntityRegistry:Init()
        if self._initialized or self._destroyed then return end
        self._initialized=true
        local function listen(signal)
            if signal then self._connections[#self._connections+1]=signal:Connect(function() self._dirty=true end) end
        end
        local players,world,tags=self.ctx.Services.Players,self.ctx.Services.Workspace,self.ctx.Services.CollectionService
        listen(players.PlayerAdded);listen(players.PlayerRemoving)
        listen(world.DescendantAdded);listen(world.DescendantRemoving)
        if type(tags.GetInstanceAddedSignal)=="function" then
            local names={"VWTestTarget"};for _,entry in ipairs(self._tags) do names[#names+1]=entry[1] end
            for _,name in ipairs(names) do listen(tags:GetInstanceAddedSignal(name));listen(tags:GetInstanceRemovedSignal(name)) end
        end
    end
    function EntityRegistry:_permitted(record)
        if not record.Instance:IsDescendantOf(self.ctx.Services.Workspace) then return false end
        if record.Player then
            return record.Player~=self.ctx.Player and record.Player.Parent==self.ctx.Services.Players
                and record.Player.Character==record.Model
                and (includes(self.policy.TargetUserIds,record.Player.UserId) or record.Player:GetAttribute("VWLabParticipant")==true)
        end
        if record.Instance:GetAttribute("VWLabAuthorized")~=true then return false end
        if record.Category=="Item" then
            -- Item lifecycle belongs to the registry even when adapters are unavailable.
            local parent=record.Instance.Parent
            for _=1,64 do
                if not parent or parent==self.ctx.Services.Workspace then return true end
                if parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then return false end
                parent=parent.Parent
            end
            return false
        end
        return true
    end
    function EntityRegistry:_describe(object,player,category,subcategory)
        if self.ctx.Adapters then return self.ctx.Adapters:Describe(object,player,category,subcategory) end
        -- Compatibility fallback if the optional adapter module could not initialize.
        local model=object:IsA("Model") and object or nil
        local root=object:IsA("BasePart") and object or (object:IsA("Tool") and object:FindFirstChild("Handle"))
            or model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart",true))
        if not root or not root:IsA("BasePart") then return nil end
        return {Instance=object,Model=model,Root=root,Player=player,Humanoid=model and model:FindFirstChildOfClass("Humanoid"),
            Category=category,Subcategory=subcategory,Name=player and player.DisplayName or object.Name,Rig="Unknown"}
    end
    function EntityRegistry:Step(dt)
        if self._destroyed then return end
        self._elapsed+=dt
        if self._elapsed<0.5 and (not self._dirty or self._elapsed<0.1) then return end
        self._elapsed=0;self._dirty=false
        local records,seen={},{}
        local function add(object,player,category,subcategory)
            if #records>=512 or seen[object] then return end
            local record=self:_describe(object,player,category,subcategory)
            if record and self:_permitted(record) then records[#records+1]=record;seen[object]=true end
        end
        for _,player in ipairs(self.ctx.Services.Players:GetPlayers()) do
            if player~=self.ctx.Player and player.Character then add(player.Character,player,"Player") end
        end
        local tags=self.ctx.Services.CollectionService
        for _,object in ipairs(tags:GetTagged("VWTestTarget")) do
            if object:IsA("Model") and object:FindFirstChildOfClass("Humanoid") then add(object,nil,"NPC") end
        end
        for _,entry in ipairs(self._tags) do for _,object in ipairs(tags:GetTagged(entry[1])) do add(object,nil,"Item",entry[2]) end end
        self._records=records
        local items,npcs=0,0
        for _,record in ipairs(records) do if record.Category=="Item" then items+=1 elseif record.Category=="NPC" then npcs+=1 end end
        self.ctx.Diagnostics:Set("Entities.Tracked",#records)
        self.ctx.Diagnostics:Set("Adapter.DetectedItems",items);self.ctx.Diagnostics:Set("Adapter.DetectedNPCs",npcs)
        self.ctx.Diagnostics:Set("Entities.Replication","Only opt-in replicated entities; unstreamed/server-only content is unknown")
    end
    function EntityRegistry:List()
        if self._destroyed then return {} end
        local list={}
        for _,record in ipairs(self._records) do
            if self:_permitted(record) then
                if not record.Root.Parent or (record.Root~=record.Instance and not record.Root:IsDescendantOf(record.Instance)) then
                    local replacement=self:_describe(record.Instance,record.Player,record.Category,record.Subcategory)
                    if replacement then record=replacement;self._dirty=true end
                end
                if record.Root.Parent~=nil and (record.Root==record.Instance or record.Root:IsDescendantOf(record.Instance)) then
                    if record.Model then record.Humanoid=record.Model:FindFirstChildOfClass("Humanoid") end
                    list[#list+1]=record
                end
            end
        end
        return list
    end
    function EntityRegistry:Invalidate() self._dirty=true;self._elapsed=0.5 end
    function EntityRegistry:Destroy()
        if self._destroyed then return end
        self._destroyed=true
        for _,connection in ipairs(self._connections) do connection:Disconnect() end
        table.clear(self._connections);table.clear(self._records)
    end
    return EntityRegistry
end
