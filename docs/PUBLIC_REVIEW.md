# Revisão da correção pública 1.0.1

Revisão independente de loader, smoke, bootstrap, mudanças de UI e fronteira de
autorização. Foi encontrado um problema importante: falha simultânea no binding
de render e no fallback Heartbeat entrava no handler externo e destruía uma UI
já pronta. A regressão reproduziu a perda da janela antes da correção.

O bootstrap agora preserva a interface pronta, registra Render.Scheduler=NONE e
expõe o erro original. O fallback normal por Heartbeat continua disponível quando
suportado. Ausência de agendamento não significa que módulos de física funcionam.

Nenhum outro defeito importante foi encontrado no escopo revisado. O revisor
confirmou que a abertura pública não remove as permissões de laboratório nem
as validações de sessão/identidade do servidor. A revisão não executou Roblox,
Xeno, física, renderização ou replicação reais.

Evidência reexecutável: tests/bootstrap.spec.luau, tests/loader.spec.luau e
docs/verification-results.json. O HTTP público é conferido após a publicação,
sem executar o conteúdo baixado.
