> Histórico 1.x. Estado atual: [validação V4](V4_VALIDATION.md) e [plano V4](V4_PLAN.md).

# Validação e aceitação — 1.0.1 / 2026-10-24

## Correção pública 1.0.1

O loader 1.0.0 publicado foi inspecionado em main e abortava antes do HTTP por
placeholders obrigatórios. A correção usa proprietário/repositório reais e uma
release fixada, sem chaves ou whitelist para abrir a UI. Não existia key system;
as listas existentes autorizam somente os recursos do laboratório.

A suíte atual inclui testes do loader real e smoke independente, bootstrap real
com fronteiras simuladas, 94 verificações da UI e as regressões anteriores.
Os resultados exatos da última execução estão em verification-results.json.
O bootstrap cobre ausência de módulos opcionais, falha de Step/probe, fallback
de agendamento, abertura pública sem autorização e limpeza da execução.
O teste de bootstrap usa um stub de UI; ui.spec executa a UI real contra doubles.

Disponibilidade de GitHub/Raw é uma verificação de rede separada e não comprova
execução no cliente. scripts/check_public_urls.py compara cinco arquivos públicos
com os bytes locais; seu relatório pós-publicação acompanha a entrega local.

## Alcance da evidência

Não havia sessão Roblox Studio conectada, cliente Roblox de teste acessível ou
Xeno disponibilizado. Portanto **não se comprovou inicialização, ativação,
renderização, física ou replicação no Roblox/Xeno real**.

O ambiente local dispõe do compilador/CLI oficial Luau 0.744 e Python. O arquivo
[verification-results.json](verification-results.json) guarda saídas e códigos
de retorno da última suíte. Os testes com doubles executam os módulos reais com
objetos de fronteira simulados; não substituem a engine nem o servidor real.
Não foi executado luau-analyze com definições de tipos Roblox, nem Rojo build.
As verificações Rojo locais validam o JSON, caminhos e separação de arquivos.

## Matriz exigida por recurso

`Pendente` significa não observado em uma sessão real, e nunca aprovação implícita.

| Recurso / arquivos | Inicializou real | Ativou real | Funcionou local real | Observado no servidor real | Verificação disponível | API incompatível / correção necessária |
|---|---|---|---|---|---|---|
| Loader / loader.luau, dist/VWMenu.luau | Pendente | Pendente | Pendente | N/A | Sintaxe e build determinístico | HTTP/loadstring não sondados no Xeno; configurar dono/repo/commit e IDs |
| AimAssist / src/client/AimAssist.luau | Pendente | Pendente | Pendente | N/A para câmera; não dispara armas | Alvo, binds, obstáculos, lock, previsão, métricas angulares/aquisição/perdas e lifecycle com doubles | Câmera/raycast reais pendentes; executar casos R6/R15 e câmera |
| ESP / src/client/ESPManager.luau | Pendente | Pendente | Pendente | N/A para overlays | Orçamento, categorias, revogação/oclusão e cleanup com doubles | Render nativo pendente; corrigir conforme erro real de GUI/Highlight |
| Fly / src/client/FlightController.luau | Pendente | Pendente | Pendente | Pendente | Sintaxe e testes de lifecycle com doubles do harness de movimento | Constraints/hover/colisões e autoridade de rede pendentes |
| Speed / src/client/SpeedController.luau | Pendente | Pendente | Pendente | Pendente | Baseline, sprint, coalescing e lifecycle com doubles | Velocidade aceita e correções reais pendentes |
| Saúde/Godmode / HealthDiagnostics, DamageTestController | Pendente | Pendente | Pendente | Pendente | Política, lease e diagnóstico local com doubles | Integrar o gateway a cada fonte de dano; sem isso não protege esse dano |
| UI / src/shared/UIManager.luau | Pendente | Pendente | Pendente | N/A | 94 checks de lógica com GUI simulada | Inspeção visual, resolução/DPI e input reais pendentes |
| Serviço / ServerTestService, PermissionService | Pendente | Pendente | N/A | Pendente | Payloads, política, lease, revogação e baseline em testes puros | Habilitar explicitamente laboratório privado/Studio e testar dois clientes |

Todos os controles alteram ConfigManager. Isso é verificado no teste de UI;
a mudança de configuração só ativa um módulo se o runtime estiver autorizado.
O estado `Active` não comprova efeito no servidor. O protocolo registra respostas
`ACCEPTED`/`REJECTED`, saúde/velocidade observadas e escopo do gateway de dano.

## Limitações conhecidas

- Um executor sem HTTP pode usar o bundle diretamente, se conseguir compilar
  Luau. Sem compilação, use os ModuleScripts no Studio. Presença de API não
  comprova compatibilidade de uma implementação do Xeno.
- Highlight acompanha o controle de caixas. Bounds que cruzam o plano próximo
  da câmera são ocultados para evitar caixas invertidas. ESP em modo visível
  usa raio até Root e não calcula visibilidade parcial de cada membro.
- A assistência muda a câmera e não valida balística/acertos do seu sistema.
  A previsão usa segundos e velocidade replicada; não há garantia de precisão.
- Fly/Speed não substituem a política de movimento/anticheat do seu servidor.
  Sinais de discrepância são heurísticos. Um relatório confirmado só existe
  quando o servidor instrumentado informa uma correção pelo hook documentado.
- Godmode só protege o gateway `DamageTestController.ApplyDamage` e não desfaz
  dano arbitrário de outros scripts. Health local nunca é prova de imunidade.
- Perfis só persistem na memória desta execução. Exportação JSON é manual.
- APIs de Drawing/gethui/arquivos não são necessárias. Detecção por presença
  é separada da construção de classes nativas e da execução das operações.

## Checklist a executar no laboratório

Antes: configure IDs, habilite política somente no ambiente privado, crie um
NPC R6, um R15, obstáculo, item marcado e dois participantes consentidos.
Registre versão do cliente, Xeno/build, PlaceId, rig, FPS e hora para cada teste.

1. Inicie pelo bundle. Confirme uma UI; repita a entrada e conte ScreenGuis e
   conexões. Abra/feche com os dois CTRL, mantenha pressionado e digite em campos.
2. Sem autorização, tente todos os toggles: nenhuma câmera/constraint/WalkSpeed
   deve ser controlada pelo menu. Confirme diagnóstico de bloqueio.
3. Aim: ative Hold e Toggle com teclado e mouse 1/2/3, varie FOV e smoothness,
   prioridades, equipes, lock/delay, Head/fallback e previsão. Meça erro angular,
   aquisição/perdas. Atravesse um obstáculo e troque a CurrentCamera.
4. ESP: varie categorias, caixas, nome/vida/distância/linhas e paredes. Crie e
   destrua itens; retire tags/autorizações. Force streaming-out e confira limpeza.
5. Fly: WASD/E/Q, hover e Shift; altere velocidades, encoste em obstáculos,
   desative no ar e verifique constraints, AutoRotate e velocidade residual.
6. Speed: registre baseline antes do teste, altere a velocidade normal pelo
   servidor e só então ative. Teste sprint/multiplicador e confirme restauração.
7. Movimento: registre posição/velocidade simultaneamente no cliente e servidor.
   Faça uma correção pelo seu servidor e notifique o hook; confirme o indicador
   `SERVER_REPORTED`. Não classifique `SUSPECTED_LOCAL_ONLY` como confirmação.
8. Saúde: aplique dano pelo gateway com proteção OFF/ON/OFF. Compare Health em
   ambos os contextos. Faça probe local e dano externo ao gateway; a UI deve
   manter explícito que não há invulnerabilidade geral comprovada.
9. Segurança: envie usuário não permitido, place público, sessão expirada,
   token antigo, Id repetido, NaN/infinito, tipo/string/nested extra e parâmetros
   acima dos limites. Confirme recusa e ausência de mutação no servidor.
10. Rate limit: exceda a taxa em sessão controlada; confirme descarte/timeout sem
    sobrecarga. Volte à taxa normal e recupere handshake.
11. Respawn R6/R15 com vários módulos ativos; deixe Character/Camera ausentes
    temporariamente. Revogue a autorização do servidor e verifique desativação.
12. Importe perfil inválido, troca válida de teclas, Reset, dez perfis, JSON e
    mudança de escala. Confira touch/viewport pequeno, drag e legibilidade.
13. Unload com todos ativos e com pedido em trânsito. Confirme ausência de GUI,
    highlights, attachments, constraints e input/render bindings; WalkSpeed e
    AutoRotate restaurados. Se Release se perder, confirme término pela lease.

Para cada caso registre: `módulo, inicializou, ativou, resultado local,
resultado no servidor, API/erro, parâmetros, correção, evidência`. Guarde saída
do cliente e servidor, além de captura visual quando o resultado for gráfico.
Atualize esta matriz apenas depois de observar cada resultado.
