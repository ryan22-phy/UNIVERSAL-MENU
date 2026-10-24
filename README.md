# VW MENU / UNIVERSAL-MENU — 1.0.1

Interface pública e gratuita, sem key system, cadastro, token ou whitelist para
abrir o menu. Aim/ESP/movimento/dano continuam limitados ao laboratório privado
autorizado. Tornar a UI pública não concede permissões em experiências de terceiros.

## Executar

A entrada pública é [loader.luau na main](https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/main/loader.luau):

~~~lua
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/main/loader.luau"
))()
~~~

Esse loader usa a release fixada em **v1.0.1**, sem placeholders. Para uma entrada
completamente fixada, use [o loader da tag](https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/v1.0.1/loader.luau).
O bundle correspondente é [dist/VWMenu.luau](https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/v1.0.1/dist/VWMenu.luau).

Revise o código remoto antes de executá-lo. Os URLs acima não exigem credenciais.
A chamada curta precisa de HttpGet e loadstring. O loader completo também tenta
request e http_request, quando disponíveis; copie seu conteúdo diretamente se o
HttpGet externo da chamada curta não funcionar. Também é possível executar o
bundle revisado sem baixar módulos. Nenhum código desconhecido é importado.

**A execução real no Xeno/Roblox continua pendente:** a release passou por
compilação Luau e testes locais com doubles. Não houve uma sessão Studio/Xeno
acessível para comprovar desenho da UI, física ou replicação. Veja
[VALIDATION.md](docs/VALIDATION.md) e [o relatório local](docs/verification-results.json).

## Se nada aparecer

Execute primeiro [smoke-test.luau](https://raw.githubusercontent.com/ryan22-phy/UNIVERSAL-MENU/v1.0.1/smoke-test.luau)
colando o conteúdo completo no cliente. Ele não usa HTTP, loadstring ou módulos;
cria somente uma ScreenGui em PlayerGui e permite fechá-la.

- Se o painel mínimo não aparecer, confira o erro original, o contexto cliente,
  LocalPlayer, PlayerGui e APIs nativas da sessão.
- Se o teste mínimo aparecer, execute o loader e registre a última etapa e o
  erro completo. Confira Diagnostics e o painel nativo de erro do loader.
- Uma segunda execução reabre o menu existente. Use Unload para trocar versões.

O erro da versão 1.0.0 publicada foi identificado antes do download: OWNER e
PINNED_COMMIT ainda eram valores provisórios. Isso não era um bloqueio de
whitelist. Detalhes em [PUBLIC_FIX_PLAN.md](docs/PUBLIC_FIX_PLAN.md).

## Comportamento da interface

A janela abre automaticamente, com fundo preto e tons de azul. CTRL esquerdo ou
direito abre/fecha sem repetir enquanto está pressionado e ignora campos de texto.
A barra superior arrasta a janela. A navegação contém Combat, Visuals, Movement,
Player, Settings e Diagnostics. Fechar apenas oculta; Settings permite descarregar.

Sliders, toggles, dropdowns e keybinds alteram ConfigManager. Todos podem configurar
preferências públicas, mas ativação das funções de laboratório exige autorização.
A UI permanece disponível se um módulo opcional falhar ou estiver ausente. O
registro informa módulo, etapa, mensagem original e correção sugerida.

## Laboratório privado opcional

Somente para suas experiências e participantes autorizados:

1. Configure config/ClientPolicy.luau para recursos locais (AllowedPlaceIds,
   AuthorizedUserIds, TargetUserIds ou AllowStudio). Essas listas nunca bloqueiam
   a abertura da interface.
2. Instale os módulos do servidor e configure src/config/ServerPolicy.luau para
   Studio ou servidores privados. A política continua fechada por padrão e recusa
   pedidos de contas/sessões não autorizadas.
3. NPC: Model com Humanoid, tag VWTestTarget e atributo VWLabAuthorized=true.
   Itens: Model/BasePart com esse atributo e tag Loot, DroppedItem, TestCollectible,
   WeaponPickup ou Objective. Para Tool, marque Handle. Jogadores precisam de
   consentimento e TargetUserIds ou VWLabParticipant definido pelo seu servidor.

| Módulo | Uso | Limite de autoridade |
|---|---|---|
| AimAssist | Cabeça R6/R15, FOV, suavização, obstáculos/equipe, lock, distância, previsão, Hold/Toggle e bind | Muda a câmera local; não dispara nem concede dano/acertos |
| ESPManager | Categorias autorizadas, caixas/contornos, nome/vida/distância e linhas | Somente instâncias replicadas e dentro do streaming |
| FlightController | F, WASD, E/Q, Shift; velocidade, aceleração e hover | Constraints locais; o servidor da experiência pode corrigir movimento |
| SpeedController | WalkSpeed, sprint, multiplicador e aceleração | Compara pedido/efeito local e observação do servidor quando disponível |
| HealthDiagnostics | Probe local, pedido de proteção, dano próprio e restauração | Health local não comprova invulnerabilidade |

Godmode só bloqueia dano que passa por DamageTestController:ApplyDamage. Integre
suas armas/queda ao gateway server-only VWMenuLabDamage e valide tiro/alcance,
equipe, cadência e dano antes da chamada. Nenhum dano de outros sistemas é
bloqueado automaticamente. Não há bypass de anticheat.

O hook server-only VWMenuLabCorrection informa uma correção que o seu próprio
servidor já aplicou. SERVER_REPORTED é separado de SUSPECTED_LOCAL_ONLY; colisão,
latência e teleporte legítimo também podem causar discrepâncias heurísticas.
Veja [SERVER_PROTOCOL.md](docs/SERVER_PROTOCOL.md).

## Studio / Rojo

~~~text
rojo serve default.project.json
~~~

ReplicatedStorage.VWMenuLab contém client/shared/ClientPolicy;
StarterPlayerScripts.VWMenu executa Main.client.luau; ServerScriptService.
VWMenuLabServer contém o backend e ServerPolicy. Nenhuma política de servidor é
incluída no bundle do cliente. Studio não precisa de loadstring nem LoadStringEnabled.

## Build e testes

Use Python 3.9+ e as ferramentas oficiais [Luau](https://github.com/luau-lang/luau/releases):

~~~text
python scripts/build.py
python scripts/verify.py --luau CAMINHO/luau.exe --compiler CAMINHO/luau-compile.exe
python scripts/check_public_urls.py --ref v1.0.1
~~~

O build incorpora os módulos em um único script; não é bytecode universal de
executor. O compilador verifica a sintaxe. Os testes de bootstrap e GUI utilizam
doubles e não equivalem a renderização real. O teste Raw lê arquivos públicos e
compara seus bytes locais/remotos sem executá-los.

config.example.json contém defaults flat. JSON é validado antes de importar.
Perfis da UI ficam na memória; exporte manualmente para guardar entre sessões.
Reset desativa recursos e restaura padrões, inclusive binds trocados.

## Atualização e rollback

A release v1.0.1 é imutável. A main é o canal de desenvolvimento. Para uma próxima
release: revise os fontes, atualize version.json/ClientPolicy/RELEASE_REF do loader,
rode build e testes, publique o commit e crie uma nova tag com o mesmo ref do loader.
Só distribua após confirmar HTTP200 e conteúdo do loader/bundle daquela tag.

Usuários da entrada main não precisam preencher placeholders. O mantenedor pode
atualizar a release apontada pela main, mantendo releases anteriores para rollback.
Para voltar, descarregue o menu e execute o loader da tag anterior revisada. Não
mova uma tag já publicada para apontar a código diferente.

Para testar explicitamente a main, defina VWMenuRef="main" no mesmo ambiente do
executor antes do loader. Isso é opcional; o default é v1.0.1. Nenhuma consulta de
metadados executa uma atualização automaticamente.

Referências nativas: [Camera](https://create.roblox.com/docs/reference/engine/classes/Camera),
[Highlight](https://create.roblox.com/docs/reference/engine/classes/Highlight) e
[mover constraints](https://create.roblox.com/docs/physics/mover-constraints).
