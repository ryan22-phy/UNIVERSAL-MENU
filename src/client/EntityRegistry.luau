return function(_import)
    local EntityRegistry = {}
    EntityRegistry.__index = EntityRegistry
    local itemTags = { "Loot", "DroppedItem", "TestCollectible", "WeaponPickup", "Objective" }
    local function includes(list, value) return table.find(list, value) ~= nil end
    function EntityRegistry.new(ctx, policy)
        return setmetatable({ ctx=ctx, policy=policy, _records={}, _elapsed=1, _destroyed=false }, EntityRegistry)
    end
    function EntityRegistry:_permitted(record)
        if not record.Instance:IsDescendantOf(self.ctx.Services.Workspace) then return false end
        if record.Player then
            return record.Player.Parent == self.ctx.Services.Players
                and record.Player.Character == record.Model
                and (includes(self.policy.TargetUserIds, record.Player.UserId)
                    or record.Player:GetAttribute("VWLabParticipant") == true)
        end
        return record.Instance:GetAttribute("VWLabAuthorized") == true
    end
    function EntityRegistry:Step(dt)
        self._elapsed += dt
        if self._elapsed < 0.5 then return end
        self._elapsed = 0
        local records, seen = {}, {}
        local function add(object, player, category)
            if #records >= 512 or seen[object] then return end
            local model = object:IsA("Model") and object or nil
            local root = object:IsA("BasePart") and object
                or (model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                    or model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart", true)))
            if not root or not root:IsA("BasePart") then return end
            local record = { Instance=object, Model=model, Root=root, Player=player,
                Humanoid=model and model:FindFirstChildOfClass("Humanoid"), Category=category,
                Name=player and player.DisplayName or object.Name }
            if self:_permitted(record) then records[#records+1] = record; seen[object] = true end
        end
        for _, player in ipairs(self.ctx.Services.Players:GetPlayers()) do
            if player ~= self.ctx.Player and player.Character then add(player.Character, player, "Player") end
        end
        local tags = self.ctx.Services.CollectionService
        for _, object in ipairs(tags:GetTagged("VWTestTarget")) do
            if object:IsA("Model") and object:FindFirstChildOfClass("Humanoid") then add(object, nil, "NPC") end
        end
        for _, tag in ipairs(itemTags) do
            for _, object in ipairs(tags:GetTagged(tag)) do add(object, nil, "Item") end
        end
        self._records = records
        self.ctx.Diagnostics:Set("Entities.Tracked", #records)
        self.ctx.Diagnostics:Set("Entities.Replication", "Somente instâncias replicadas; conteúdo fora do streaming é desconhecido")
    end
    function EntityRegistry:List()
        local list = {}
        for _, record in ipairs(self._records) do
            if self:_permitted(record) and record.Root.Parent ~= nil then list[#list+1] = record end
        end
        return list
    end
    function EntityRegistry:Destroy() self._destroyed=true; table.clear(self._records) end
    return EntityRegistry
end
