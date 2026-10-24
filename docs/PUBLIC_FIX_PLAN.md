# Correção pública 1.0.1 — 2026-10-24

Base inspecionada: main / 11c54d990e37704fc13dc01f8cc79b642ea8f230.
Repositório: https://github.com/ryan22-phy/UNIVERSAL-MENU.

## Diagnóstico confirmado

O loader publicado ainda exige OWNER=SEU_USUARIO e PINNED_COMMIT provisório.
Uma execução intacta falha no primeiro assert, antes de HTTP ou criação de GUI.
main/loader.luau e main/dist/VWMenu.luau existem e respondem publicamente.
O código 1.0.0 já separava a autorização dos recursos da criação nominal da
interface; não existe key system a remover. Não atribuir a falha a whitelist.
Há chamadas opcionais de bootstrap sem isolamento antes da construção da UI;
elas serão exercitadas com injeção de falhas, sem alegar execução Xeno.

## Implementação

- [x] Loader real, sem placeholders: proprietário/repositório conhecidos,
  release v1.0.1 como referência estável; main como canal de desenvolvimento.
  Diagnóstico por etapa, HTTP/fallback, compilação e execução protegidos.
- [x] smoke-test.luau independente: ScreenGui mínima, sem rede/importações.
- [x] UI primeiro: pública e visível; falhas de módulos opcionais permanecem
  em Diagnostics e não descarregam o menu. Reexecução reabre a instância.
- [x] Auditoria de UI e testes CTRL, navegação, drag, controles e cleanup.
- [x] Metadados/build 1.0.1 consistentes; nenhuma política de servidor removida.
- [x] Testes de regressão, compilação total e revisão independente.
- [x] Publicação em branch de correção, tag v1.0.1 e PR para main; verificar
  conteúdo Raw da tag, sem confundir publicação com validação de engine.
- [x] Atualizar os arquivos entregues, ZIP, diagnóstico e testes pendentes.

## Contratos entre tarefas

Cache global continua VWMenuLabRuntime. Runtime:Show() reabre sem duplicar;
UIManager:Show()/Hide() controlam apenas a janela. ctx.IsAuthorized protege
somente ações de laboratório. ServerPolicy/PermissionService não mudam.
Loader recebe override opcional VWMenuRef, com default v1.0.1 sem edição.

## Foco da revisão

Erro antes de PlayerGui; cache corrompido/reexecução entre ambientes; módulo
ausente ou Step lançando erro; UI pública sem permissões; HTTP/404/HTML/body
vazio; loadstring lançando vs retornando nil; conexão sobrando após unload.

## Verificação honesta

Roblox Studio: nenhuma sessão conectada durante inspeção. Xeno: sem sessão
acessível. Testes de engine, render e física permanecem pendentes. O resultado
local utiliza compilador oficial Luau 0.744 e testes dos módulos reais com doubles.

Resultado local final: 8/8 etapas; 32 arquivos Luau compilados; loader/smoke216,
bootstrap34, UI94, movimento50, política37, configuração25, bridge9 e entidades6.
Também passaram suíte CombatVisuals e seis testes Python de integridade/build.
