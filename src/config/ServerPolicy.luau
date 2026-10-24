-- Default deny. Configure this ModuleScript in a place you own before testing.
return function(_import)
	return {
		EnableStudioTests = false,
		EnablePrivateServers = false,
		UserIds = {}, -- Positive account IDs permitted in private servers / Studio.
		PlaceIds = {}, -- Empty means any place owned by this installation.
		SessionLeaseSeconds = 15,
		RateLimitPerSecond = 8,
		RateLimitBurst = 16,
		MaxFlightSpeed = 120,
		MaxVerticalSpeed = 90,
		MaxWalkSpeed = 80,
		MaxDiagnosticDamage = 100,
		AllowServerGodmode = true, -- Applies ONLY to DamageTestController:ApplyDamage.
		AllowRestoreHealth = true,
	}
end
