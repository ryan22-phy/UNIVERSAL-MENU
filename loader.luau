-- VW MENU public loader. No key, account check, whitelist or private credentials.
local OWNER = "ryan22-phy"
local REPOSITORY = "UNIVERSAL-MENU"
local BRANCH = "main"
local RELEASE_REF = "v4.0.0"
local environment = _G
local function log(message) print("[ VW ] " .. message) end
local function errorPanel(message)
    local player=game:GetService("Players").LocalPlayer
    assert(player,"LocalPlayer unavailable")
    local parent=player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui",10)
    assert(parent,"PlayerGui unavailable")
    local old=parent:FindFirstChild("VWMenuLoaderError")
    if old then old:Destroy() end
    local gui=Instance.new("ScreenGui")
    gui.Name="VWMenuLoaderError"; gui.Enabled=true; gui.ResetOnSpawn=false
    gui.IgnoreGuiInset=true; gui.DisplayOrder=1000; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    gui.Parent=parent
    local label=Instance.new("TextLabel")
    label.Name="Failure"; label.BackgroundColor3=Color3.fromRGB(8,13,23)
    label.TextColor3=Color3.fromRGB(134,213,255); label.Font=Enum.Font.Code
    label.TextSize=14; label.TextWrapped=true; label.TextXAlignment=Enum.TextXAlignment.Left
    label.TextYAlignment=Enum.TextYAlignment.Top
    label.Size=UDim2.new(0.8,0,0.35,0); label.Position=UDim2.new(0.1,0,0.12,0)
    label.Text="VW MENU — INITIALIZATION ERROR\n\n"..message; label.Parent=gui
    local close=Instance.new("TextButton")
    close.Text="Fechar diagnóstico"; close.Size=UDim2.fromOffset(180,32)
    close.Position=UDim2.new(0.1,0,0.47,8); close.Parent=gui
    close.Activated:Connect(function() gui:Destroy() end)
end
local function fail(stage,file,original,fix)
    local message="[ VW ] "..stage.." | "..file.." | "..tostring(original).." | Fix: "..fix
    warn(message)
    local shown,why=pcall(errorPanel,message)
    if not shown then warn("[ VW ] diagnostic GUI unavailable: "..tostring(why)) end
    error(message,0)
end
log("Starting loader...")
print("[VW] Loader initialized")
log("Checking environment...")
if type(getgenv)=="function" then
    local ok,value=pcall(getgenv)
    if ok and type(value)=="table" then environment=value
    else warn("[ VW ] environment/getgenv fallback to _G: "..tostring(value)) end
end
local previous=environment.VWMenuLabRuntime
if type(previous)=="table" and previous.Alive then
    local ok,why=pcall(function()
        if type(previous.Show)=="function" then previous:Show()
        elseif previous.Modules and previous.Modules.UI and type(previous.Modules.UI.Enable)=="function" then previous.Modules.UI:Enable()
        else error("Live runtime has no reveal method; unload the previous version first") end
    end)
    if not ok then fail("runtime","ClientController",why,"Descarregue a execução anterior e execute novamente") end
    log("Existing interface reopened.")
    return previous
end
local compiler=type(loadstring)=="function" and loadstring or environment.loadstring
if type(compiler)~="function" then fail("environment","loader.luau","loadstring unavailable","Use um cliente compatível ou instale os ModuleScripts no Studio") end
local sourceRef=environment.VWMenuRef
if sourceRef==nil then sourceRef=RELEASE_REF or BRANCH end
if type(sourceRef)~="string" or sourceRef=="" or #sourceRef>180 or sourceRef:find("..",1,true)
    or not sourceRef:match("^[%w_./-]+$") or sourceRef:sub(1,1)=="/" or sourceRef:sub(-1)=="/" or sourceRef:find("//",1,true) then
    fail("environment","loader.luau","Invalid VWMenuRef: "..tostring(sourceRef),"Remova o override ou use uma tag, branch ou SHA deste repositório")
end
local url="https://raw.githubusercontent.com/"..OWNER.."/"..REPOSITORY.."/"..sourceRef.."/dist/VWMenu.luau"
print("[VW] Environment checked")
local function validBody(body)
    if type(body)~="string" then return false,"Body is not a string" end
    if #body==0 or #body>2*1024*1024 then return false,"Body empty or exceeds 2 MiB" end
    if body:sub(1,11)~="-- VW MENU " then return false,"Unexpected body/header (HTML, 404 or wrong file)" end
    return true
end
log("Downloading source...")
local failures={}
local source
local fetched,body=pcall(function() return game:HttpGet(url) end)
local valid,reason=validBody(body)
if fetched and valid then source=body
else
    local detail="HttpGet: "..tostring(fetched and reason or body)
    failures[#failures+1]=detail; warn("[ VW ] download fallback: "..detail)
end
if not source then
    for _,name in ipairs({"request","http_request"}) do
        local request=environment[name]
        if type(request)=="function" then
            local ok,response=pcall(request,{Url=url,Method="GET"})
            local accepted,why=false,"Malformed HTTP response"
            if ok and type(response)=="table" and response.StatusCode==200 and (response.Success==nil or response.Success==true) then
                accepted,why=validBody(response.Body)
            elseif not ok then why=tostring(response)
            elseif type(response)=="table" then why="HTTP status/Success: "..tostring(response.StatusCode).."/"..tostring(response.Success) end
            if accepted then source=response.Body; break end
            local detail=name..": "..tostring(why)
            failures[#failures+1]=detail; warn("[ VW ] download fallback: "..detail)
        end
    end
end
if not source then fail("download","dist/VWMenu.luau",table.concat(failures,"; "),"Verifique HTTP, a URL "..url.." e se a release/tag está publicada") end
log("Compiling source...")
local compiled,chunk,compileError=pcall(compiler,source,"@VWMenu/"..sourceRef)
if not compiled or type(chunk)~="function" then
    fail("compile","dist/VWMenu.luau",compiled and compileError or chunk,"Confira o bundle publicado e o suporte a Luau/loadstring do ambiente")
end
local ran,result=pcall(chunk)
if not ran or type(result)~="table" or result.Alive~=true then
    fail("runtime","dist/VWMenu.luau",ran and "Bundle did not return a live runtime" or result,"Consulte o erro original e execute smoke-test.luau para isolar o ambiente")
end
return result
