-- These lists authorize lab FEATURES only. The public interface never uses them as an access gate.
return function(_import)
    return {
        AllowedPlaceIds = {}, -- e.g. { 1234567890 }
        AuthorizedUserIds = {}, -- your numeric Roblox UserId
        TargetUserIds = {}, -- participants who explicitly opted into this lab
        AllowStudio = false, -- explicit local Studio opt-in; server has its own policy
        Version = "1.0.1",
        -- Optional metadata only. UI checks JSON; it never executes an update.
        VersionUrl = "https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/main/version.json",
        Protocol = 1,
    }
end
