# VW MENU — laboratório privado / entrada Xeno

Projeto Luau modular, com bundle único para um cliente Roblox autorizado e
serviço opcional no servidor da experiência. Sem chave, biblioteca externa,
Drawing obrigatório, gethui obrigatório ou download de módulos em cascata.

**Estado da entrega:** código e testes locais; a execução real no Roblox Studio
e no Xeno ainda precisa ser validada. Nenhuma instância Studio estava conectada
durante a criação. Consulte [VALIDATION.md](docs/VALIDATION.md) para evidências e
limitações por recurso. Uma compilação bem-sucedida não confirma física,
renderização, replicação nem compatibilidade com uma versão do executor.

## Começar

1. Edite `config/ClientPolicy.luau`: `AllowedPlaceIds`, `AuthorizedUserIds` e
   `TargetUserIds`. Use IDs numéricos, nunca nomes. Alternativamente, use o
   handshake autorizado do serviço privado descrito abaixo. Sem autorização,
   a UI abre para diagnóstico e os recursos permanecem bloqueados.
2. Execute `python scripts/build.py` com Python 3.9 ou posterior. Isso gera
   `dist/VWMenu.luau` e `dist/manifest.json` de forma determinística.
3. Publique **seus próprios arquivos revisados** em um repositório GitHub.
   Inclua `dist/`; o loader não compila os fontes Python nem baixa dependências.
4. Copie o SHA completo do commit que contém o bundle. Edite `OWNER`,
   `REPOSITORY` e `PINNED_COMMIT` em `loader.luau`.
5. Execute o conteúdo desse loader no Xeno, dentro do seu laboratório privado.
   Também é possível executar diretamente o bundle revisado, sem HTTP.

O loader usa `game:HttpGet` dentro de `pcall` e tenta `request`/`http_request`
quando presentes. Precisa de `loadstring`; se não existir, interrompe com erro
claro. Não habilite LoadStringEnabled no servidor para instalar este projeto.
O loader fixa o bundle em um commit. O cabeçalho verificado não é uma assinatura:
compare o SHA256 com `dist/manifest.json` fora do executor quando auditar a release.
O manifesto publicado no mesmo repositório também precisa ser confiável.

Depois de publicar, uma chamada curta pode apontar ao **loader configurado**:

```lua
-- Substitua dono, repo e SHA pelo seu commit; requer HTTP + loadstring.
local source = game:HttpGet("https://raw.githubusercontent.com/DONO/REPO/SHA/loader.luau")
local run, err = loadstring(source, "@VWMenuLoader")
assert(run, err)
return run()
```

Essa chamada curta depende de HttpGet; o fallback completo fica no próprio
`loader.luau`. Um repositório privado sem autenticação não pode ser carregado
anonimamente por Raw. Não coloque tokens GitHub em scripts do cliente. Nenhum
repositório foi criado ou publicado automaticamente nesta entrega.

## Instalação opcional no Studio

`default.project.json` separa cliente e servidor:

| Local | Conteúdo |
|---|---|
| ReplicatedStorage.VWMenuLab | ModuleScripts client, shared, config/ClientPolicy |
| StarterPlayer.StarterPlayerScripts.VWMenu | Main.client.luau |
| ServerScriptService.VWMenuLabServer | módulos server, config/ServerPolicy e bootstrap |

Com Rojo instalado: `rojo serve default.project.json`; conecte o plugin Rojo
na sua experiência de teste. Também pode executar `rojo build default.project.json
-o VWMenuLab.rbxlx`. Rojo não é necessário para o bundle do executor. Se instalar
manualmente, preserve nomes e hierarquia do JSON; cada módulo retorna uma factory
que os bootstraps resolvem por `import("pasta/Módulo")`.

Edite `src/config/ServerPolicy.luau`: habilite `EnableStudioTests` ou
`EnablePrivateServers` e preencha `UserIds`/`PlaceIds` conforme seu laboratório.
O servidor recusa sessões públicas. Usuários sintéticos negativos só são aceitos
no Studio com opt-in explícito. Não use essa opção para liberar contas reais.
O serviço fica fechado por padrão, mesmo que a política local autorize o cliente.

Alvos NPC devem ter tag `VWTestTarget`, Humanoid e atributo booleano
`VWLabAuthorized=true`. Itens replicados precisam desse atributo e de uma tag:
`Loot`, `DroppedItem`, `TestCollectible`, `WeaponPickup` ou `Objective`.
Marque o `Model` ou `BasePart` que representa o item; para um `Tool`, marque
seu `Handle` com a tag e o atributo de autorização.
Jogadores precisam estar em `ClientPolicy.TargetUserIds` ou portar o atributo
`VWLabParticipant=true` definido pelo seu servidor após consentimento. Não use
esse atributo para substituir validação de permissões no servidor.
Instâncias fora do streaming ou não replicadas não podem ser descobertas.

## Controles

CTRL esquerdo ou direito abre/fecha o menu. Campos de texto e captura de atalho
suprimem ações de jogo. O menu já abre na inicialização.

| Página / recurso | Configuração e ativação | Resultado esperado |
|---|---|---|
| Combat / AimAssist | Toggle, tecla (padrão botão direito), Hold/Toggle, FOV 20–400 px, suavização, distância, obstáculos/equipe, lock/delay, prioridade e previsão | A câmera acompanha somente alvos autorizados vivos; indicador e métricas locais |
| Visuals / ESP | Jogadores/NPCs/itens, caixa, nome, vida, distância, linhas, paredes, limite/frequência | Elementos nativos para entidades replicadas e autorizadas |
| Movement / Fly | Toggle ou F, WASD, E/Q, Shift boost; velocidades e aceleração | Constraints locais com hover; restauração ao desligar |
| Movement / Speed | Toggle, WalkSpeed/sprint/multiplicador/aceleração; Shift padrão | Velocidade pedida, deslocamento efetivo e diagnóstico; resultado depende do servidor |
| Player / Godmode | Pedido de proteção no servidor, dano próprio de 10, restauração e probe local | Proteção somente no gateway autorizado; probe local não prova invulnerabilidade |
| Settings | Escala, JSON, salvar/carregar perfil, padrões, versão, unload | Perfis em memória; exporte JSON para guardar entre sessões |
| Diagnostics | FPS, capacidades, entidade/overlay, erros, respostas e saúde/velocidade observadas | Valores mensurados pelo contexto indicado; suspeitas não são confirmações |

Smoothness é taxa de resposta: valores maiores seguem o alvo mais rapidamente.
Previsão é um intervalo em segundos aplicado à velocidade do alvo. Não mede
balística ou tempo de projétil do seu sistema de armas. O projeto não dispara
armas, não concede acertos e não envia dano a alvos selecionados.

Diagnostics registra `Aim.AngularErrorDeg` após a interpolação, tempo aproximado
até adquirir o primeiro alvo (`Aim.AcquisitionMs`, inclui espera pelo frame)
e perdas de rastreamento (`Aim.TrackingLosses`). São métricas locais de câmera,
sem comprovação de acerto ou latência de rede.

## Autoridade e Godmode

Uma alteração de `Humanoid.Health` no cliente pode afetar apenas a visualização
local. O botão de probe deixa essa limitação explícita e compara a leitura com
o servidor quando ele está disponível. Sem resposta recente, não há confirmação.

O servidor só protege chamadas que passam por `DamageTestController:ApplyDamage`.
Para integrar suas armas/queda, use, em **scripts do servidor**:

```lua
local gateway = game:GetService("ServerScriptService"):WaitForChild("VWMenuLabDamage")
local applied, reason = gateway:Invoke(targetPlayer, validatedDamage)
```

Valide tiro, alcance, equipe, cadência e o dano antes de chamar o gateway. Ele
não valida o seu sistema de combate. Dano direto de outros scripts, destruição
do personagem, kill plane e `BreakJoints` não são bloqueados automaticamente.
Não há garantia de proteção contra queda sem adaptar a rotina de queda.
Desativar remove a proteção desse gateway sem alterar permanentemente MaxHealth.

Flight/Speed autorizados registram permissões e observam o personagem no servidor.
Eles não desativam o anticheat existente. Integre os limites de teste na lógica
do seu próprio servidor. `SuspectedCorrection` é uma heurística: colisões, saltos,
teleportes legítimos e latência também podem produzi-la.

Para um indicador confirmado, instrumente uma correção **já aplicada** pelo
seu próprio servidor:

```lua
local hook = game:GetService("ServerScriptService"):WaitForChild("VWMenuLabCorrection")
hook:Fire(player, "Reposicionamento aplicado pelo validador do laboratório")
```

O hook apenas registra a informação; não move o personagem. O painel marca
`SERVER_REPORTED` quando recebe esse relatório correlacionado do servidor.

Sessões expiram em 15 s sem renovação; o cliente suspende autorização remota
sem resposta recente. Release, respawn, saída e revogação removem o estado do
laboratório. Se o cliente perder a conexão antes de enviar Release, a lease
é a recuperação do servidor. Consulte [SERVER_PROTOCOL.md](docs/SERVER_PROTOCOL.md).

## Configurações, atualizações e rollback

`config.example.json` contém os defaults no formato flat usado pela UI
(`Aim.FOV`, `Flight.Speed` etc.). Importação valida tipos, números finitos,
limites e opções antes de alterar o perfil. Um perfil pode ativar recursos:
revise toggles antes de importar. Reset desativa os módulos e restaura os padrões.
Perfis da UI são temporários, sem APIs de arquivo, clipboard ou DataStore.

Depois de alterar os fontes/políticas, rode build e testes, revise o bundle e
publique um novo commit. Atualize manualmente o SHA do loader. Para rollback,
restaure o SHA anterior e execute o loader em uma nova sessão, ou descarregue
antes pela UI. Reexecutar enquanto o menu está ativo devolve a instância atual.
`ClientPolicy.VersionUrl` permite consultar `version.json` via Raw pela UI;
essa ação só lê JSON e nunca executa atualizações.

## Verificar e resolver erros

Instale as ferramentas da release oficial de [Luau](https://github.com/luau-lang/luau/releases)
fora do projeto e execute:

```text
python scripts/build.py
python scripts/verify.py --luau CAMINHO/luau.exe --compiler CAMINHO/luau-compile.exe
```

O script compila todos os fontes/entradas/bundle, executa testes Luau com doubles
e testa integridade do build em Python. Ele falha quando qualquer etapa falha.
Não é substituto para os testes de aceitação do [checklist](docs/VALIDATION.md).

| Sintoma | Verificação / correção |
|---|---|
| Menu bloqueado | Configure IDs locais ou obtenha handshake do servidor privado autorizado |
| Sem alvos/itens | Confira tags, consentimento/atributos, Humanoid, distância e streaming |
| Aim não acompanha | Ative o módulo e bind, confira FOV, obstáculos/equipe e câmera atual |
| ESP não aparece | Confira categorias, distância, orçamento e diagnóstico da classe nativa |
| Fly/Speed volta à posição anterior | Compare telemetria local/servidor e limites do seu próprio sistema de movimento |
| Godmode sem efeito | Confira ack recente e se a origem do dano usa o gateway |
| Raw 404 ou HTML | Confira caminho, commit publicado, repositório público e bundle incluso |
| Sem HTTP/loadstring | Execute o bundle revisado diretamente se houver compilação; caso contrário use Studio |
| Erro de uma API | Confira Diagnostics; o módulo com falha é desativado, registre executor/build e mensagem |
| Unload durante falha de rede | Aguarde a lease do servidor e confirme restauração da velocidade no servidor |

As capacidades exibidas são sondagens do ambiente em execução. A presença de
uma função não certifica que a implementação do Xeno daquela versão execute
todas as operações. Não foi usada uma distribuição de executor nesta entrega.

## Referências de API

[Camera / projeção](https://create.roblox.com/docs/reference/engine/classes/Camera),
[Highlight](https://create.roblox.com/docs/reference/engine/classes/Highlight),
[Mover constraints](https://create.roblox.com/docs/physics/mover-constraints) e
[Luau](https://github.com/luau-lang/luau). Dependências de build: Python padrão e
ferramentas oficiais Luau. Não há minificação, ofuscação ou código externo oculto.
