-- Server weapon scripts must use ApplyDamage for this service's protection to apply.
-- It cannot intercept damage from unrelated scripts, falls, resets or direct Health writes.
return function(import)
	local PermissionService = import("server/PermissionService")
	local DamageTestController = {}
	DamageTestController.__index = DamageTestController

	function DamageTestController.new(ctx)
		return setmetatable({ctx = ctx, protected = {}}, DamageTestController)
	end

	function DamageTestController:SetGodmode(player, enabled)
		self.protected[player] = if enabled then player.Character else nil
	end

	function DamageTestController:IsProtected(player)
		return self.protected[player] ~= nil and self.protected[player] == player.Character and (self.ctx.CanProtect == nil or self.ctx.CanProtect(player))
	end

	function DamageTestController:ApplyDamage(targetPlayer, amount)
		if not PermissionService.IsBounded(amount, 0, 1000000) then return false, "INVALID_DAMAGE" end
		local character = targetPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return false, "CHARACTER_UNAVAILABLE" end
		if self:IsProtected(targetPlayer) then return false, "GODMODE_BLOCKED" end
		humanoid:TakeDamage(amount)
		return true, "DAMAGE_APPLIED"
	end

	function DamageTestController:RestoreHealth(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return false, "CHARACTER_UNAVAILABLE" end
		if not PermissionService.IsBounded(humanoid.MaxHealth, 1, 1000000000) then return false, "INVALID_MAX_HEALTH" end
		humanoid.Health = humanoid.MaxHealth
		return true, "HEALTH_RESTORED"
	end

	function DamageTestController:Release(player)
		self.protected[player] = nil
	end

	function DamageTestController:Destroy()
		table.clear(self.protected)
	end

	return DamageTestController
end
