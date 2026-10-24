-- Roblox Studio entry. Xeno entry is dist/VWMenu.luau, generated from modules.
local storage=game:GetService("ReplicatedStorage")
local root=storage:WaitForChild("VWMenuLab",10)
assert(root,"Instale os ModuleScripts VWMenuLab em ReplicatedStorage (default.project.json)")
local cache,loading={},{}
local function import(name)
    if cache[name] then return cache[name] end
    assert(not loading[name],"Dependência circular: "..name)
    loading[name]=true
    local current=root
    for segment in name:gmatch("[^/]+") do
        current=current:FindFirstChild(segment)
        assert(current,"Módulo ausente: "..name)
    end
    assert(current:IsA("ModuleScript"),"Esperado ModuleScript: "..name)
    local value=require(current)(import)
    cache[name]=value; loading[name]=nil
    return value
end
import("client/ClientController").Start()
