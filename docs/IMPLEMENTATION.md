# VW MENU — desenho e plano de implementação original (1.0.0)

Histórico preservado. A correção pública 1.0.1 está em PUBLIC_FIX_PLAN.md e README.md.

Data: 2026-10-24. Especificação: pedido e master prompt fornecidos pelo usuário.
O usuário autorizou implementação contínua, sem aprovação entre fases.

## Decisões

Fontes Luau modulares sem dependências externas. Cada ModuleScript exporta
`function(import) -> módulo`; import recebe nomes `shared/ConfigManager`.
O build incorpora os módulos em `dist/VWMenu.luau` sem downloads de módulos.
`loader.luau` baixa somente esse bundle de um commit GitHub configurado.
Uma entrada Studio separada usa ModuleScripts e não utiliza loadstring.
UI nativa em PlayerGui; não depende de Drawing, gethui ou APIs de arquivo.
Não há repositório remoto ou credenciais fornecidos: entrega local publicável.

ClientPolicy limita PlaceIds/UserIds e alvos. Sem autorização local ou
handshake autorizado do laboratório, o menu abre em diagnóstico e os módulos
ficam bloqueados. Serviço opcional funciona apenas em Studio/servidor privado
e valida permissões, payloads, limites, rate limit e sessão no servidor.
Flags locais não concedem privilégios no servidor.

## Contrato compartilhado

Todos os módulos de recurso exportam `.new(ctx)` e instâncias implementam
`Init`, `Enable`, `Disable`, `UpdateConfig`, `Destroy`, `Step(dt)`.
`ctx` contém: Services (Players, RunService, UserInputService,
CollectionService, ReplicatedStorage, HttpService, Workspace), Player,
Config (`Get(path)`, `Set(path,value)`, `Subscribe(callback)`, `Snapshot()`),
Diagnostics (`Set(key,value)`, `Log(module,status,detail,parameters?)`),
Cleanup (`Add(resource)`), Gui (ScreenGui com IgnoreGuiInset=true),
IsAuthorized() -> bool, Entities (`List()` -> array de
`{Instance, Model?, Root, Humanoid?, Player?, Category, Name}`),
Bridge (`Request(action,payload,callback?)`, `Latest`, `Available`).
Camera sempre obtida de Workspace.CurrentCamera.

Config usa caminhos com ponto:
Aim.Enabled=false, FOV=120, Smoothness=12, MaxDistance=1000,
VisibilityCheck=true, TeamCheck=true, HeadPriority=true, Fallback=true,
TargetLock=true, SwitchDelay=0.2, Mode="Hold", Key="MouseButton2",
Priority="Angle", Prediction=0, ShowFOV=true.
ESP.Enabled=false, Players=true, NPCs=true, Items=true, Boxes=true,
Names=true, Health=true, Distance=true, Lines=false, ThroughWalls=false,
MaxDistance=1500, MaxElements=64, RefreshRate=20.
Flight.Enabled=false, Speed=40, VerticalSpeed=30, Acceleration=8,
Boost=1.5, Key="F".
Speed.Enabled=false, WalkSpeed=24, SprintSpeed=36, Multiplier=1,
Acceleration=8, SprintKey="LeftShift".
Player.ServerGodmode=false.
Settings.MenuKey="LeftControl", Scale=1.
Chaves acima são prefixadas pelo grupo, inclusive quando abreviadas na lista.

## Responsabilidades / etapas

- [x] Core: ConfigManager, CleanupManager, Diagnostics, Compatibility,
  EntityRegistry, ServerBridge, ClientController; testar validação de
  configurações, autorização, ciclo de vida e degradação sem servidor.
- [x] Combat/Visuals: AimAssist e ESPManager; selecionar apenas entidades
  autorizadas, raycast, deltaTime, orçamento e destruição de overlays.
- [x] Movement/servidor: FlightController, SpeedController,
  HealthDiagnostics, PermissionService, DamageTestController,
  ServerTestService; validar números finitos, rate limit e opt-in privado.
- [x] UIManager: sidebar e controles ligados ao Config, import/export,
  perfis em memória, diagnóstico, descarregar e restauração.
- [x] Build/entrega: bundler determinístico, loader fixado em commit,
  Rojo, configuração exemplo, README, changelog, matriz e pacote ZIP.
- [x] Verificação local: compilação Luau, testes puros e
  revisão independente; testes Roblox/Xeno ficam explicitamente pendentes
  quando não houver sessão conectada. Não simular evidência de execução.

## Foco da revisão

Respawn e câmera trocada; revogação de autorização; requests atrasados após
unload; alternância simultânea fly/speed; perfis inválidos/não finitos;
projeção atrás da câmera; quedas de HTTP/compilação; saúde local divergente.

## UI

Paleta do pedido: #080D17 / #111D30 / #123C75 / #39A9FF / #86D5FF.
Janela compacta 780×510 com escala para viewport, sidebar, header,
ScrollingFrame por página e status no rodapé. Controles editáveis,
tooltip, nenhum gradiente, CTRL ignora campos de texto e repetição.
Estado sem permissão/servidor é visível. Controles continuam editando
configurações, mas o runtime não ativa recursos sem autorização.
