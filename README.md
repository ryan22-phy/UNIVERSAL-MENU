# VW MENU — UNIVERSAL EDITION v4.0

Interface pública em Luau, sem key para abrir. O projeto mantém os módulos existentes e adiciona reconhecimento de estruturas comuns, configurações avançadas e diagnósticos para testes autorizados. Não há certificação universal de jogos ou do executor Xeno.

## Carregar

~~~lua
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/main/loader.luau"
))()
~~~

O loader da main aponta para a release **v4.0.0**. Entrada fixada: [loader da tag v4.0.0](https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/v4.0.0/loader.luau). [Bundle único](https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/v4.0.0/dist/VWMenu.luau). Revise os fontes antes de executar. A chamada curta exige HttpGet/loadstring; o loader completo detecta funções e tenta request/http_request quando disponíveis. Copiar o bundle revisado evita download de módulos. Não há dependências externas ocultas.

**Validação real de renderização, física, Xeno e replicação continua pendente:** não há Studio conectado. Compilação e testes locais executam os módulos reais com objetos simulados nos limites do Roblox. [Resultados](docs/verification-results.json), [matriz e limitações V4](docs/V4_VALIDATION.md).

## Interface e configuração

A janela abre automaticamente. CTRL esquerdo/direito abre ou fecha, sem repetir enquanto segurado. Digitação e captura de atalhos suspendem os binds. A barra superior arrasta; Settings permite descarregar e restaurar recursos locais. As seis páginas continuam Combat, Visuals, Movement, Player, Settings e Diagnostics.

A V4 usa fundo #080B12, sidebar #0D1422, painéis #131D2E e acentos #268BFF/#67C9FF. Controles reutilizáveis: ToggleSwitch, ModernSlider, KeybindPicker, ColorPicker RGB hexadecimal, Dropdown, MultiSelect, SearchBox, SectionHeader, StatusIndicator, Tooltip, Notification e ProfileSelector. Busca filtra os controles. Cores, tema Blue/Cyan, escala e presets alteram estado real. Animações nativas curtas usam fallback imediato quando indisponíveis.

Perfis ficam **na memória desta sessão** (até dez). Save/Load usam a lista de nomes reais. Export/Import transportam JSON pelo campo editável, sem exigir arquivos/clipboard do executor. Valores, cores, opções e conflitos entre binds são validados antes de aplicar; Reset desativa funções e restaura padrões.

| Preset | Overlays máximos | Atualização | Skeleton / Head Marker |
|---|---:|---:|---|
| Low | 24 | 10 Hz | desligados |
| Balanced | 64 | 20 Hz | desligados |
| High | 96 | 30 Hz | ligados |

Presets preservam os toggles de ativação. Ajustes manuais podem alterar esses valores depois; o nome do preset indica a última aplicação. Estes são orçamentos configurados, sem benchmark de FPS no Roblox.

## Recursos e autoridade

| Módulo | V4 | Alcance da evidência |
|---|---|---|
| AimAssist | Head R6/R15, fallback escolhido, FOV, distância, Team/Neutral, visibilidade, lock/delay, previsão, Hold/Toggle | Câmera local; não dispara. Diagnostics mostra parte, erro angular, dispersão do erro nas últimas 60 amostras e aquisição aproximada |
| ESPManager | Boxes, skeleton padrão, nome, vida, distância, equipe/cor, cabeça, alvo, tracers e Highlight independentes; jogadores/NPCs/itens | Somente entidades autorizadas e replicadas; cache limitado, até 31 Highlights próprios |
| UniversalGameAdapter | Generic, R6, R15, TaggedItem e Custom; câmera/streaming/equipes | Identifica estrutura; não concede permissão nem revela conteúdo exclusivo do servidor |
| Fly | Direção horizontal da câmera, E/Q, aceleração/hover, boost e restauração por personagem | Pedido, comando e velocidade local medida distintos; servidor pode corrigir |
| Speed | WalkSpeed, sprint, multiplicador, aceleração e baseline por Humanoid | Solicitação, WalkSpeed aplicado, velocidade efetiva e observação remota distintas |
| HealthDiagnostics | Probe local, dano próprio e gate de dano autorizado | Health visual não prova invulnerabilidade. Apenas respostas correlacionadas são rotuladas como recebidas do servidor |

MODULE READY significa inicialização concluída; não comprova efeito no servidor. Correções suspeitas são heurísticas locais. SERVER_REPORTED exige instrumentação do próprio servidor. Diagnostics mostra FPS amostrado, capacidades detectadas, entidades, instâncias visuais, erros e custo CPU relativo dos módulos. Timing exclui renderização/physics/servidor.

## Preparar o laboratório

A UI nunca exige whitelist. Ações do laboratório continuam fechadas por padrão:

1. Configure config/ClientPolicy.luau: AllowedPlaceIds + AuthorizedUserIds, ou AllowStudio. TargetUserIds identifica participantes que consentiram; VWLabParticipant também pode ser definido pelo servidor do seu laboratório.
2. Instale o backend opcional e configure src/config/ServerPolicy.luau para Studio ou servidor privado. Sessões, payloads, limites e rate limit são validados no servidor. O cliente não instala código no ServerScriptService via executor.
3. NPCs: Model com Humanoid, tag VWTestTarget e atributo VWLabAuthorized=true.
4. Itens: Model, BasePart ou Tool com Handle; atributo VWLabAuthorized=true na instância marcada e uma tag abaixo. Itens dentro de personagens são excluídos após coleta.

| Tag | Categoria / filtro |
|---|---|
| DroppedItem | DroppedItems |
| Loot | Loot |
| WeaponPickup | Weapons |
| ToolPickup | Tools |
| TestCollectible | Collectibles |
| Objective | Objectives |
| VWTestItem / TestObject | TestObjects |

Não há varredura heurística por nomes, roupas ou objetos desconhecidos. Personagens fora do streaming e objetos não replicados permanecem desconhecidos. A descoberta usa eventos, atualização limitada e revalidação de permissão/removal.

## Adaptadores de experiências próprias

Settings > Adapter permite Auto, GenericRobloxAdapter ou CustomGameAdapter. Em config/ClientPolicy.luau, configure mapeamentos explícitos quando necessário:

~~~lua
CustomAdapter = { RootName="Core", HeadName="Sensor", TeamAttribute="LabFaction" },
CustomItemTags = { MyAuthorizedPickup="Tools" },
~~~

Player.Team tem prioridade quando Neutral=false. Sem equipe oficial, somente um TeamAttribute configurado identifica facções próprias. Dois jogadores neutros/sem equipe não são tratados como colegas por terem nil no Team. Nunca se usa cor de roupa como equipe. Cada parte escolhida precisa existir e pertencer ao modelo atual.

UniversalGameAdapter:Register aceita extensões locais auditadas com Name, Match(instance,category) e Resolve(instance,category). Resolve devolve Root, Model, Humanoid, Head e Rig; extensões não mudam a autorização do registro. Limite de 32 adapters e erros limitados. GameAdapterManager é um alias para a mesma implementação. Estruturas diferentes exigem mapeamento/código próprio e teste; não há promessa de suporte a todo mapa.

## Saúde e servidor

Godmode bloqueia exclusivamente dano que passa por DamageTestController.ApplyDamage, no servidor autorizado. Integre suas armas/dano ao gateway server-only VWMenuLabDamage após validar regras do jogo. Alterações diretas de Health, BreakJoints ou outros sistemas não são interceptadas automaticamente. [Protocolo](docs/SERVER_PROTOCOL.md).

Damage/Restore mostram SERVER_ACCEPTED, SERVER_REJECTED ou SERVER_BLOCKED somente para respostas correlacionadas do RemoteEvent. Falhas de fila/timeout/ausência do servidor são locais. O hook VWMenuLabCorrection deve ser disparado pelo jogo após uma correção real; não corrige movimento por si só.

## Studio, build e publicação

~~~text
rojo serve default.project.json
python scripts/build.py
python scripts/verify.py --luau CAMINHO/luau.exe --compiler CAMINHO/luau-compile.exe
python scripts/check_public_urls.py --ref v4.0.0
python scripts/package.py
~~~

Use Python 3.9+ e o [Luau oficial](https://github.com/luau-lang/luau/releases). Rojo mapeia client/shared/ClientPolicy no ReplicatedStorage e o backend/política no ServerScriptService. Studio usa ModuleScripts e não precisa de loadstring. O bundle é fonte Luau único, não bytecode universal.

Para nova release, atualize version.json, ClientPolicy.Version e RELEASE_REF; execute build/testes/revisão, publique código e crie **nova** tag com esse nome. Verifique Raw HTTP200 e igualdade dos bytes. Nunca mova tags publicadas. A tag v1.0.1 continua disponível para rollback: descarregue a sessão atual e use seu loader. VWMenuRef="main" é um override opcional de desenvolvimento; não é necessário para abrir a interface.

## Se a interface não aparecer

Execute [smoke-test.luau](https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/v4.0.0/smoke-test.luau) colando o conteúdo inteiro. Ele testa apenas ScreenGui/PlayerGui, sem HTTP/loadstring/dependências. Se não desenhar, registre erro original e contexto cliente. Se desenhar, execute o loader e registre última etapa, módulo e erro completo. Uma execução repetida reabre o menu atual; para mudar de versão, descarregue antes.

Logs de inicialização identificam loader, ambiente, UI, AimAssist, ESP e módulos. Um módulo secundário incompatível não deve impedir a abertura pública. Sem APIs nativas essenciais, o painel de erro tenta informar causa e correção. Presença de API não equivale a certificação de executor.

Referências oficiais: [Player](https://create.roblox.com/docs/reference/engine/classes/Player), [Camera](https://create.roblox.com/docs/reference/engine/classes/Camera), [Highlight](https://create.roblox.com/docs/reference/engine/classes/Highlight), [Motor6D](https://create.roblox.com/docs/reference/engine/classes/Motor6D), [TweenService](https://create.roblox.com/docs/reference/engine/classes/TweenService).
