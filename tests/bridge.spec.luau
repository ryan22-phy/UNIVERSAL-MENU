-- Mock transport exercises our correlation/timeout logic, not Roblox replication.
local Bridge = require("../src/client/ServerBridge")(function(name)
    assert(name == "shared/CleanupManager")
    return require("../src/shared/CleanupManager")(nil)
end)
local requests, callback, values = {}, nil, {}
local requestEvent = { IsA=function(_,name) return name == "RemoteEvent" end,
    FireServer=function(_,packet) requests[#requests+1]=packet end }
local responseEvent = { IsA=function(_,name) return name == "RemoteEvent" end,
    OnClientEvent={ Connect=function(_,fn) callback=fn; return function() callback=nil end end } }
local folder = { FindFirstChild=function(_,name) return name == "Request" and requestEvent or responseEvent end }
local ctx = { Services={ReplicatedStorage={FindFirstChild=function() return folder end}},
    Diagnostics={Set=function(_,k,v) values[k]=v end, Log=function() end} }
local b = Bridge.new(ctx); b:Init(); b:Step(0)
assert(#requests == 1 and requests[1].Action == "Hello", "discover must handshake")
callback({Id=requests[1].Id,Ok=true,Session="test-session",Data={Authorized=true}})
assert(b.Available and b.Latest.Authorized, "authorized handshake")
local answered, source=0,nil
b:Request("Observe",{},function(response) if response.Ok then answered+=1 end;source=response.Source end)
local id = requests[#requests].Id
callback({Id=id+100,Ok=true,Data={Authorized=false}})
assert(b.Available and answered==0, "unmatched response cannot revoke session")
callback({Id=id,Ok=true,Source="UNTRUSTED",Data={Authorized=true,Health=90,ConfirmedCorrection={Sequence=1,Reason="TEST_SERVER_HOOK"}}})
assert(answered==1 and b.Latest.Health==90, "correlated response")
assert(source=="SERVER","provenance assigned only at correlated receive")
assert(b.LastCorrectionAt>0 and values["Server.ConfirmedCorrection"]=="TEST_SERVER_HOOK", "only correlated server reports confirm correction")
callback({Id=id,Ok=true,Data={Authorized=false}})
assert(b.Available and answered==1, "duplicate response ignored")
for _=1,16 do b:Request("Observe",{},nil) end
local failedReason,failedSource
local sent=b:Request("Speed",{Enabled=true},function(response) failedReason=response.Reason;failedSource=response.Source end)
assert(not sent and failedReason=="QUEUE_FULL", "queue failure must complete callback")
assert(failedSource=="LOCAL","queue failure is not a server rejection")
b:Request("Observe",{},nil)
callback({Id=requests[#requests].Id,Ok=false,Reason="DENIED",Data={Authorized=false}})
assert(not b.Available, "permission revocation")
b:Destroy()
assert(not b:Request("Observe",{},nil), "unload blocks requests")
print("PASS bridge.spec: 11 assertions (mock transport)")
