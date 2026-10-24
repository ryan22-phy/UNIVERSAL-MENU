-- Independent native GUI probe: no HTTP, loadstring, modules, key or whitelist.
print("[ VW ] smoke: checking PlayerGui...")
local player=game:GetService("Players").LocalPlayer
assert(player,"[ VW ] smoke/environment: LocalPlayer unavailable; run in a Roblox client")
local parent=player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui",10)
assert(parent,"[ VW ] smoke/PlayerGui: missing after 10 seconds")
local previous=parent:FindFirstChild("VWMenuSmokeTest")
if previous then previous:Destroy() end
local gui=Instance.new("ScreenGui")
gui.Name="VWMenuSmokeTest"; gui.Enabled=true; gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true; gui.DisplayOrder=999; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=parent
local label=Instance.new("TextLabel")
label.Size=UDim2.new(0.7,0,0,110); label.Position=UDim2.new(0.15,0,0.15,0)
label.BackgroundColor3=Color3.fromRGB(8,13,23); label.TextColor3=Color3.fromRGB(134,213,255)
label.Font=Enum.Font.GothamBold; label.TextSize=18; label.TextWrapped=true
label.Text="VW MENU · GUI TEST\nSe este painel aparece, a criação básica da ScreenGui funcionou.\nIsso não testa o bundle ou os módulos."
label.Parent=gui
local close=Instance.new("TextButton")
close.Text="Fechar teste"; close.Size=UDim2.fromOffset(160,32)
close.Position=UDim2.new(0.15,0,0.15,118); close.Parent=gui
close.Activated:Connect(function() gui:Destroy() end)
print("[ VW ] smoke: ScreenGui created; visual observation is still required.")
return gui
