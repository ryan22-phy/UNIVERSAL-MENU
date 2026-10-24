-- The runner injects the actual files into lexical Roblox API boundary doubles.
local actualCompiler = loadstring
local checks = 0
local failures = {}
local function expect(value, message)
    checks += 1
    assert(value, message)
end
local function test(name, callback)
    local ok, failure = pcall(callback)
    if not ok then table.insert(failures, name .. ": " .. tostring(failure)) end
end
local validSource = "-- VW MENU 1.0.1\nreturn { Alive=true, Show=function(self) self.Visible=true end }"
local releaseURL = "https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/v4.0.0/dist/VWMenu.luau"

local function fixture(options)
    options = options or {}
    local state = { logs={}, created={}, calls={}, env=options.env or {}, children={} }
    local function signal()
        local result = {}
        function result:Connect(callback) self.Callback = callback; return { Disconnect=function() end } end
        return result
    end
    local playerGui = {}
    function playerGui:FindFirstChild(name) return state.children[name] end
    local player = {}
    function player:FindFirstChildOfClass(name) return name == "PlayerGui" and playerGui or nil end
    function player:WaitForChild(name, timeout)
        expect(name=="PlayerGui" and timeout<=10, "PlayerGui wait must be bounded")
        return not options.noPlayerGui and playerGui or nil
    end
    if options.noPlayerGui then function player:FindFirstChildOfClass() return nil end end
    local players = { LocalPlayer=not options.noPlayer and player or nil }
    local Instance = { new=function(class)
        if options.instanceError then error("native GUI unavailable") end
        local object = { ClassName=class, Activated=signal() }
        function object:Destroy() self.Destroyed=true; state.children[self.Name]=nil end
        setmetatable(object, { __newindex=function(self, key, value)
            rawset(self,key,value)
            if key=="Parent" and value==playerGui then state.children[self.Name]=self end
        end })
        table.insert(state.created, object)
        return object
    end }
    local game = {}
    function game:GetService(name)
        if options.serviceError then error("Players service unavailable") end
        expect(name=="Players", "minimal loader/smoke GUI uses only Players service")
        return players
    end
    function game:HttpGet(url)
        table.insert(state.calls,url)
        if options.httpError then error(options.httpError) end
        return options.body == nil and validSource or options.body
    end
    local Enum = {
        ZIndexBehavior={ Sibling="Sibling" }, Font={ Gotham="Gotham", GothamBold="GothamBold", Code="Code" },
        TextXAlignment={ Left="Left" }, TextYAlignment={ Top="Top" },
    }
    local UDim2 = { new=function(...) return {...} end, fromOffset=function(...) return {...} end, fromScale=function(...) return {...} end }
    local Color3 = { fromRGB=function(...) return {...} end }
    local _G = state.env
    local getgenv = options.getgenv
    local loadstring = if options.noCompiler then false else (options.compiler or actualCompiler)
    local function log(...) local parts={...}; for i,v in ipairs(parts) do parts[i]=tostring(v) end; table.insert(state.logs,table.concat(parts," ")) end
    local print, warn = log, log
    local function executeLoader()
-- @LOADER_SOURCE@
    end
    local function executeSmoke()
-- @SMOKE_SOURCE@
    end
    state.run=function() return pcall(executeLoader) end
    state.smoke=function() return pcall(executeSmoke) end
    state.text=function() return table.concat(state.logs,"\n") end
    state.hasPanel=function(name) return state.children[name] ~= nil end
    state.playerGui=playerGui
    return state
end

test("public stable tag loads without configuration using the real compiler",function()
    local f=fixture(); local ok,result=f.run()
    expect(ok,tostring(result)); expect(result.Alive==true,"runtime result returned")
    expect(#f.calls==1 and f.calls[1]==releaseURL,"real public stable URL used")
    for _,stage in ipairs({"Starting loader...","Checking environment...","Downloading source...","Compiling source..."}) do
        expect(f.text():find(stage,1,true)~=nil,"missing stage "..stage)
    end
end)
test("safe tag and branch overrides reach the selected public bundle",function()
    for _,ref in ipairs({"main","v1.0.1","codex/fix-public-loader","11c54d990e37704fc13dc01f8cc79b642ea8f230"}) do
        local f=fixture({env={VWMenuRef=ref}}); local ok,result=f.run()
        expect(ok,tostring(result)); expect(f.calls[1]=="https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/"..ref.."/dist/VWMenu.luau","override URL preserved")
    end
end)
test("invalid refs fail before network and show actionable native diagnostics",function()
    for _,ref in ipairs({"", "../main", "main/../evil", "/main", "main/", "main//x", "main?x=1", "main#x", "main%2fsecret", "https://evil", 42}) do
        local f=fixture({env={VWMenuRef=ref}}); local ok,result=f.run()
        expect(not ok,"invalid ref accepted: "..tostring(ref)); expect(#f.calls==0,"invalid ref fetched")
        expect(tostring(result):find("environment",1,true)~=nil,"environment stage missing")
        expect(tostring(result):find("Fix:",1,true)~=nil,"fix missing")
        expect(f.hasPanel("VWMenuLoaderError"),"error panel missing")
    end
end)
test("missing compiler fails before HTTP with stage/file/fix",function()
    local f=fixture({noCompiler=true}); local ok,result=f.run()
    expect(not ok,"missing compiler accepted"); expect(#f.calls==0,"HTTP performed before compiler check")
    for _,part in ipairs({"environment","loader.luau","loadstring","Fix:"}) do expect(tostring(result):find(part,1,true)~=nil,"missing "..part) end
    expect(f.hasPanel("VWMenuLoaderError"),"native error panel missing")
end)
test("HttpGet failure falls back to request and remains visible in diagnostics",function()
    local f=fixture({httpError="network refused",env={request=function(options)
        expect(options.Url==releaseURL and options.Method=="GET","request boundary changed")
        return {StatusCode=200,Success=true,Body=validSource,Headers={}}
    end}})
    local ok,result=f.run(); expect(ok,tostring(result))
    expect(f.text():find("network refused",1,true)~=nil,"original fallback error hidden")
end)
test("http_request is tried when request fails",function()
    local f=fixture({httpError="HttpGet disabled",env={request=function() error("request disabled") end,http_request=function()
        return {StatusCode=200,Success=true,Body=validSource,Headers={}}
    end}})
    local ok,result=f.run(); expect(ok,tostring(result)); expect(f.text():find("request disabled",1,true)~=nil,"request failure hidden")
end)
test("malformed or failed request responses are not compiled",function()
    for _,response in ipairs({false, "bad", {}, {StatusCode="200",Success=true,Body=validSource}, {StatusCode=404,Success=false,Body="404: Not Found"}, {StatusCode=200,Success=false,Body=validSource}, {StatusCode=200,Success="yes",Body=validSource}, {StatusCode=200,Body=15}, {StatusCode=200,Body=""}, {StatusCode=200,Body="<html>sign in</html>"}}) do
        local compiled=false
        local f=fixture({httpError="transport failed",env={request=function() return response end},compiler=function() compiled=true; return function() return {} end end})
        local ok,result=f.run(); expect(not ok,"malformed response accepted"); expect(not compiled,"malformed response compiled")
        expect(tostring(result):find("download",1,true)~=nil,"download stage missing")
        expect(tostring(result):find("transport failed",1,true)~=nil,"original transport failure missing")
    end
end)
test("invalid HttpGet bodies fail before compilation",function()
    for _,body in ipairs({"", "  \n", "<html><body>404</body></html>", "404: Not Found", "-- another project", string.rep("x",2*1024*1024+1), false, 37}) do
        local compiled=false
        local f=fixture({body=body,compiler=function() compiled=true; return function() return {} end end})
        local ok,result=f.run(); expect(not ok,"invalid body accepted"); expect(not compiled,"invalid body compiled")
        expect(tostring(result):find("download",1,true)~=nil,"download stage missing")
    end
end)
test("compiler thrown errors and syntax returns keep original detail",function()
    for _,compiler in ipairs({function() error("compiler exploded") end,function() return nil,"unexpected token at line 9" end}) do
        local f=fixture({compiler=compiler}); local ok,result=f.run()
        expect(not ok,"compiler failure accepted"); expect(tostring(result):find("compile",1,true)~=nil,"compile stage missing")
        expect(tostring(result):find("dist/VWMenu.luau",1,true)~=nil,"bundle file missing")
        expect(tostring(result):find("Fix:",1,true)~=nil,"compiler fix missing")
    end
end)
test("runtime exceptions and missing runtime are actionable",function()
    for _,body in ipairs({"-- VW MENU 1.0.1\nerror('runtime exploded')","-- VW MENU 1.0.1\nreturn nil"}) do
        local f=fixture({body=body}); local ok,result=f.run()
        expect(not ok,"runtime failure accepted"); expect(tostring(result):find("runtime",1,true)~=nil,"runtime stage missing")
        expect(f.hasPanel("VWMenuLoaderError"),"runtime diagnostic panel missing")
    end
end)
test("duplicate execution reveals the existing live runtime without HTTP",function()
    local previous={Alive=true,Visible=false,Show=function(self) self.Visible=true end}
    local f=fixture({noCompiler=true,env={VWMenuLabRuntime=previous}}); local ok,result=f.run()
    expect(ok,tostring(result)); expect(result==previous and previous.Visible,"existing menu not reopened")
    expect(#f.calls==0,"duplicate execution fetched another bundle")
end)
test("duplicate reveal exceptions report the original runtime failure",function()
    local f=fixture({env={VWMenuLabRuntime={Alive=true,Show=function() error("reopen exploded") end}}})
    local ok,result=f.run(); expect(not ok,"reopen exception swallowed")
    expect(tostring(result):find("reopen exploded",1,true)~=nil,"original reopen error hidden")
end)
test("unloaded runtime permits a new initialization",function()
    local f=fixture({env={VWMenuLabRuntime={Alive=false}}}); local ok,result=f.run()
    expect(ok,tostring(result)); expect(result.Alive and #f.calls==1,"unloaded runtime prevented reload")
end)
test("getgenv errors are logged and the shared global fallback remains usable",function()
    local f=fixture({getgenv=function() error("getgenv unavailable") end}); local ok,result=f.run()
    expect(ok,tostring(result)); expect(f.text():find("getgenv unavailable",1,true)~=nil,"environment fallback hidden")
end)
test("diagnostic GUI failures do not hide the primary failure",function()
    local f=fixture({httpError="primary network failure",instanceError=true}); local ok,result=f.run()
    expect(not ok,"network failure accepted"); expect(tostring(result):find("primary network failure",1,true)~=nil,"primary error replaced")
    expect(f.text():find("native GUI unavailable",1,true)~=nil,"GUI failure hidden")
end)
test("smoke test creates a visible native GUI independently and removes duplicates",function()
    local f=fixture({noCompiler=true,httpError="HTTP must not be used"})
    local ok,result=f.smoke(); expect(ok,tostring(result)); expect(#f.calls==0,"smoke performed HTTP")
    expect(f.hasPanel("VWMenuSmokeTest"),"smoke ScreenGui missing")
    local first=result; expect(first.Enabled==true and first.Parent==f.playerGui,"smoke GUI not visible")
    local secondOK,second=f.smoke(); expect(secondOK,tostring(second)); expect(first.Destroyed and second~=first,"smoke duplicated old GUI")
end)

if #failures>0 then
    for _,failure in ipairs(failures) do print("FAIL "..failure) end
    error(tostring(#failures).." loader/smoke tests failed; "..checks.." checks executed",0)
end
print("PASS loader + independent smoke: "..checks.." checks")
