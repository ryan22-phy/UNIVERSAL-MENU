-- Edit before building. Local policy permits local tests; it grants no server power.
return function(_import)
    return {
        AllowedPlaceIds = {}, -- e.g. { 1234567890 }
        AuthorizedUserIds = {}, -- your numeric Roblox UserId
        TargetUserIds = {}, -- participants who explicitly opted into this lab
        AllowStudio = false, -- explicit local Studio opt-in; server has its own policy
        Version = "1.0.0",
        -- Optional metadata only. UI checks JSON; it never executes an update.
        VersionUrl = "",
        Protocol = 1,
    }
end
