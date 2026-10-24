-- VW MENU / Xeno entry. Edit these three values after publishing your repository.
-- PINNED_COMMIT must be the full 40-character SHA reviewed by you.
local OWNER = "SEU_USUARIO"
local REPOSITORY = "VW-MENU-LAB"
local PINNED_COMMIT = "COLOQUE_O_SHA_DO_COMMIT_AQUI"

assert(OWNER ~= "SEU_USUARIO", "VW: configure OWNER no loader")
assert(OWNER:match("^[%w-]+$") and REPOSITORY:match("^[%w_.-]+$"), "VW: proprietário/repositório inválido")
assert(#PINNED_COMMIT == 40 and PINNED_COMMIT:match("^%x+$"), "VW: use o SHA completo de um commit revisado")
local url = "https://raw.githubusercontent.com/"..OWNER.."/"..REPOSITORY.."/"..PINNED_COMMIT.."/dist/VWMenu.luau"
local environment = _G
pcall(function() if type(getgenv)=="function" and type(getgenv())=="table" then environment=getgenv() end end)
local compiler = type(loadstring)=="function" and loadstring or environment.loadstring
assert(type(compiler)=="function", "VW: loadstring não está disponível; use a instalação Studio")

local function download()
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body)=="string" and #body>0 then return body end
    local request = environment.request or environment.http_request
    if type(request)=="function" then
        local sent, response = pcall(request, {Url=url,Method="GET"})
        if sent and type(response)=="table" and response.StatusCode==200 and type(response.Body)=="string" then return response.Body end
    end
    error("VW: download Raw falhou. Verifique HTTP do executor, URL/commit e repositório público. Detalhe: "..tostring(body), 0)
end
local source = download()
assert(#source < 2*1024*1024, "VW: bundle excede limite de 2 MiB")
assert(source:find("-- VW MENU 1.0.0",1,true)==1, "VW: resposta não é o bundle esperado")
-- A header and a pinned URL are not cryptographic verification. Compare manifest SHA256 externally.
local chunk, compileError = compiler(source,"@VWMenu")
assert(type(chunk)=="function", "VW: compilação indisponível/incompatível: "..tostring(compileError))
local ran, result = pcall(chunk)
assert(ran,"VW: falha na inicialização: "..tostring(result))
return result
