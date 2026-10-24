return function(import)
    local Cleanup = import("shared/CleanupManager")
    local ServerBridge = {}
    ServerBridge.__index = ServerBridge
    function ServerBridge.new(ctx)
        return setmetatable({ ctx=ctx, Available=false, Latest={}, LastSeen=0, Session=nil, LastCorrectionAt=0,
            _nextId=0, _pending={}, _elapsed=2, _helloAt=-10, _destroyed=false,
            _cleanup=Cleanup.new(), _remoteCleanup=nil }, ServerBridge)
    end
    function ServerBridge:Init() end

    function ServerBridge:_receive(response)
        if self._destroyed or type(response) ~= "table" then return end
        local pending = self._pending[response.Id]
        if not pending or type(response.Ok) ~= "boolean" then return end
        -- Provenance is assigned at the correlated RemoteEvent boundary, not trusted from payload.
        response.Source = "SERVER"
        self._pending[response.Id] = nil
        self.LastSeen = os.clock()
        if type(response.Data) == "table" then
            self.Latest = response.Data
            if response.Data.Authorized == false then self.Available=false; self.Session=nil end
        end
        if pending.Action == "Hello" then
            self.Available = response.Ok and self.Latest.Authorized == true and type(response.Session) == "string"
            self.Session = self.Available and response.Session or nil
        end
        local correction=self.Latest.ConfirmedCorrection
        if self.Available and type(correction)=="table" and type(correction.Sequence)=="number" and type(correction.Reason)=="string" then
            local token=tostring(self.Session)..":"..tostring(correction.Sequence)
            if token~=self._correctionToken then
                self._correctionToken=token; self.LastCorrectionAt=os.clock()
                self.ctx.Diagnostics:Set("Server.ConfirmedCorrection",correction.Reason)
                self.ctx.Diagnostics:Log("Movement","SERVER_REPORTED_CORRECTION",correction.Reason)
            end
        end
        self.ctx.Diagnostics:Set("Server.Available", self.Available)
        self.ctx.Diagnostics:Set("Server.LastAction", pending.Action .. ": " .. tostring(response.Reason or response.Ok))
        self.ctx.Diagnostics:Set("Server.ResponseMs", math.floor((os.clock()-pending.Time)*1000))
        self.ctx.Diagnostics:Set("Server.Health", self.Latest.Health or "indisponível")
        self.ctx.Diagnostics:Set("Server.Speed", self.Latest.ObservedHorizontalSpeed or "indisponível")
        if pending.Action ~= "Observe" then
            self.ctx.Diagnostics:Log("Server", response.Ok and "ACCEPTED" or "REJECTED", pending.Action .. ": " .. tostring(response.Reason))
        end
        if pending.Callback then
            local ok, err = pcall(pending.Callback, response)
            if not ok then self.ctx.Diagnostics:Log("Bridge", "ERROR", err) end
        end
    end

    function ServerBridge:Request(action, payload, callback)
        if self._destroyed then return false, "UNLOADED" end
        if not self._request then
            if callback then callback({Ok=false,Reason="NO_SERVER",Source="LOCAL",Data={Authorized=false}}) end
            return false, "NO_SERVER"
        end
        if action ~= "Hello" and not self.Available then
            if callback then callback({Ok=false,Reason="NO_AUTHORIZED_SESSION",Source="LOCAL",Data={Authorized=false}}) end
            return false, "NO_AUTHORIZED_SESSION"
        end
        local pendingCount = 0
        for _ in pairs(self._pending) do pendingCount += 1 end
        if pendingCount >= 16 then
            if callback then
                local completed, err=pcall(callback,{Ok=false,Reason="QUEUE_FULL",Source="LOCAL",Data={Authorized=false}})
                if not completed then self.ctx.Diagnostics:Log("Bridge","ERROR",err) end
            end
            return false, "QUEUE_FULL"
        end
        self._nextId = (self._nextId % 1000000000) + 1
        local id = self._nextId
        self._pending[id] = { Action=action, Time=os.clock(), Callback=callback }
        local ok, err = pcall(function()
            self._request:FireServer({Id=id,Action=action,Payload=payload or {},Session=self.Session})
        end)
        if not ok then
            self._pending[id] = nil
            if callback then callback({Ok=false,Reason=tostring(err),Source="LOCAL",Data={Authorized=false}}) end
            return false, tostring(err)
        end
        return true
    end

    function ServerBridge:Step(dt)
        if self._destroyed then return end
        local now = os.clock()
        self.ctx.Diagnostics:Set("Server.CorrectionStatus", self.Available and self.LastCorrectionAt>0 and now-self.LastCorrectionAt<3 and "SERVER_REPORTED" or "NO_RECENT_SERVER_REPORT")
        for id, pending in pairs(self._pending) do
            if now - pending.Time > 4 then
                self._pending[id] = nil
                self.ctx.Diagnostics:Log("Bridge", "TIMEOUT", pending.Action)
                if pending.Callback then pcall(pending.Callback, {Ok=false,Reason="TIMEOUT",Source="LOCAL",Data={Authorized=false}}) end
            end
        end
        if self.Available and now - self.LastSeen > 6 then
            self.Available=false; self.Session=nil
            self.ctx.Diagnostics:Log("Bridge", "STALE", "Servidor sem resposta; autorização remota suspensa")
        end
        self.ctx.Diagnostics:Set("Server.Available", self.Available)
        self._elapsed += dt
        if self._elapsed < 2 then return end
        self._elapsed=0
        local folder = self.ctx.Services.ReplicatedStorage:FindFirstChild("VWMenuLabRemote")
        local request = folder and folder:FindFirstChild("Request")
        local response = folder and folder:FindFirstChild("Response")
        if not request or not response or not request:IsA("RemoteEvent") or not response:IsA("RemoteEvent") then
            if self._remoteCleanup then self._remoteCleanup:Destroy(); self._remoteCleanup=nil end
            self._request=nil; self._response=nil; self.Available=false; self.Session=nil
            self.ctx.Diagnostics:Set("Server.Available", false)
            return
        end
        if self._request ~= request or self._response ~= response then
            if self._remoteCleanup then self._remoteCleanup:Destroy() end
            self._remoteCleanup=Cleanup.new(); self._request=request; self._response=response
            table.clear(self._pending); self.Available=false; self.Session=nil
            self._remoteCleanup:Add(response.OnClientEvent:Connect(function(packet) self:_receive(packet) end))
            self._helloAt=-10
        end
        if self.Available then self:Request("Observe", {})
        elseif now-self._helloAt >= 10 then self._helloAt=now; self:Request("Hello", {}) end
    end

    function ServerBridge:Destroy()
        if self._destroyed then return end
        if self.Available then self:Request("Release", {}) end
        self._destroyed=true; self.Available=false; self.Session=nil
        if self._remoteCleanup then self._remoteCleanup:Destroy() end
        self._cleanup:Destroy(); table.clear(self._pending)
    end
    return ServerBridge
end
