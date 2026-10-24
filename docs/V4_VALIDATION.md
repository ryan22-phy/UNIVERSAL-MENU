# Validação V4 — evidências e limites

Release: 4.0.0. Base: main 2c1563cbf4739f7756e406f2ce4bf1948b50b6d7. Data: 2026-10-24.

## Resultado executado

O verificador integrado passou **9/9 etapas**. Compilador oficial Luau 0.744: **36 arquivos Luau**. Build determinístico: **16 módulos**, fonte única. Os hashes e saídas completas estão em [verification-results.json](verification-results.json).

| Verificação local | Resultado observado |
|---|---|
| Build / grafo / segregação cliente-servidor | PASS; 6 testes Python, versão/tag e mapeamento explícito de todos os módulos verificados |
| Adapters + registro | PASS; R6/R15, cabeça substituída, fallback exato, Head Only, equipes oficiais/neutras/customizadas, tags, coleta, revogação, 512 entidades e limpeza |
| Bridge | 11 assertions; correlação, duplicatas, revogação, fila e origem local/servidor simulada |
| Config | 45 assertions; validação, atomicidade, RGB, presets, binds e reset |
| Registro básico | 7 assertions; opt-in, streaming/removal, revogação e Destroy |
| Política/payloads de servidor | 37 assertions; somente lógica com doubles, sem servidor Roblox |
| UI | 187 verificações; seis páginas, CTRL, captura, perfis, JSON, componentes, tema, busca, notificações, animações/fallback e descarregamento |
| Combate | PASS; seleção, lock/delay, FOV/obstáculos, equipe durante lock, neutros, ausência de Humanoid, próprio modelo, parte destruída, previsão, suavização, estabilidade e câmera substituída |
| ESP V4 | PASS; recursos independentes, skeleton R6/R15, cores/equipe, categorias/tipo nos rótulos, seleção, instâncias estáveis, clipping, câmera e orçamento com 100 entidades simuladas |
| Movimento/saúde | 94 assertions; snapshots de velocidade, restauro, respawn, rejeições síncronas, callbacks antigos, correção confirmada e dano/restauração com proveniência |
| Loader/smoke | 216 verificações; fonte real compilada nos testes, download/fallback, falhas, duplicação, entrada fixada e GUI mínima simulada |
| Bootstrap | 35 verificações; interface pública, isolamento de falhas, autorização, scheduler, duplicação e assinatura exclusiva da UI à configuração |

O código dos módulos é real; somente os objetos/serviços do Roblox nos limites são simulados. As suítes não reproduzem o motor, o executor, a renderização nem a rede. Não se soma essas verificações como porcentagem de compatibilidade.

## Estado por recurso

Nesta tabela, “PASS lógico” refere-se exclusivamente ao harness CLI. Não significa execução visual ou aceitação em um servidor Roblox.

| Recurso | Inicializou / ativou no harness | Efeito local no Roblox | Resultado observado no servidor Roblox | API no Xeno | Correção / próximo teste |
|---|---|---|---|---|---|
| UI / CTRL / componentes | PASS lógico | NÃO EXECUTADO | não se aplica à aparência | NÃO CERTIFICADA | Conferir desenho, texto, scroll, foco, escala, animações e toque no Studio/cliente |
| AimAssist / Head / Team Check | PASS lógico | NÃO EXECUTADO | não houve tiro/dano; câmera é local | NÃO CERTIFICADA | Rodar R6/R15 em movimento, primeira/terceira pessoa, obstáculos e troca real de equipe |
| ESP jogadores / NPCs / itens | PASS lógico | NÃO EXECUTADO | sem observação multiplayer | NÃO CERTIFICADA | Verificar projeção, Highlight/skeleton, categorias e StreamingEnabled no motor |
| UniversalGameAdapter / tags | PASS lógico | NÃO EXECUTADO | somente conteúdo replicado será visível | APIs nativas detectadas em runtime | Instalar mapeamentos próprios quando aparecer estrutura incompatível |
| Fly | PASS lógico | física NÃO EXECUTADA | NÃO OBSERVADO | Constraints não certificadas no Xeno | Verificar hover, E/Q, orientação, queda/desligamento e correções reais |
| Speed / sprint | PASS lógico | física NÃO EXECUTADA | NÃO OBSERVADO | WalkSpeed não certificado no Xeno | Comparar solicitado/aplicado/efetivo e snapshots remotos em dois clientes |
| Saúde / gate de dano | PASS lógico | NÃO EXECUTADO | NÃO OBSERVADO | Sem alegação de invulnerabilidade | Instalar backend autorizado e testar DamageTestController + dano que não passa pelo gate |
| Loader / duplicação | PASS lógico + HTTP público após publicação | Xeno NÃO EXECUTADO | não instala servidor | Compatibilidade pendente | Executar smoke primeiro e registrar etapa/erro em sessão real |

## Matriz de mapas do laboratório

Nenhum mapa Roblox foi efetivamente aberto nesta sessão. Todos os cenários abaixo estão **PENDENTES NO MOTOR**, ainda que haja regressão de lógica correspondente no CLI.

| Cenário de laboratório | Ações a observar | Critério de aceite |
|---|---|---|
| Arena padrão R6 e R15 | Entrada, UI, CTRL, head, morte/respawn, alvos em movimento | Sem erro; mira na parte informada; liberação de alvo morto e novas referências |
| Equipes e neutros | Team Check ON/OFF; mudar Team/Neutral durante lock | Colega ignorado só com filtro ativo; nil/neutral não forma equipe fictícia |
| Obstáculos e câmeras | Parede; alvo fora do FOV; primeira/terceira pessoa; CurrentCamera nova/nil | Sem lock indevido; câmera atual usada; ausência temporária não derruba UI |
| CustomRig / facções | Core/Sensor e atributo explícito de facção | Adapter selecionado/motivo exibido; sem inferência por roupas/nomes |
| Tags / streaming | DroppedItem/Loot/Weapon/Tool/Collectible/Objective/TestObject; coletar/destruir/stream-out | Filtros/rótulos corretos; elementos removidos; conteúdo não replicado permanece desconhecido |
| Carga de dezenas de entidades | 24/64/96/128; Low/Balanced/High; toggles simultâneos | Instâncias limitadas, sem conexão duplicada; registrar FPS e CPU por módulo reais |
| Movimento autorizado | Fly/Sprint juntos e separados; respawn/desativação; câmera vertical | Restauro correto; diagnóstico distingue efeitos locais de confirmação remota |
| Servidor privado | Usuário autorizado/negado; lease expirada; dano/restauração; correção instrumentada | Servidor mantém autoridade; mensagens de aceitação/negação/correção correspondem a eventos reais |
| Falhas e reexecução | API ausente, módulo com erro, loader repetido, unload/reload | Interface pública preservada; mensagem contém módulo/causa; limpeza sem duplicação |

## Limitações conhecidas

- Não há sessão Studio conectada, executável Xeno acessível ou jogo certificado. Não há captura de tela nem nota visual de produção.
- 2D bounds que cruzam o plano próximo da câmera são ocultados de forma conservadora. Visibility Only usa raycast para o root; não calcula exposição por cada membro.
- Skeleton reconhece as ligações padrão R6/R15; rigs customizados precisam de adaptação própria. Não há tentativa de descobrir corpos por nomes parecidos.
- O limite de 31 Highlights é um orçamento conservador **do menu**, sem reservar recursos usados pela experiência; disponibilidade real depende do motor.
- ESP depende de instâncias/tags/atributos replicados e do opt-in do laboratório. Eventos são coalescidos; descoberta ocorre em até 0,5 s, com atualização antecipada limitada a 10 Hz.
- Estabilidade da mira é desvio padrão do erro angular em até 60 amostras do alvo atual. Não é precisão de tiro, FPS ou garantia de acerto. Aquisição inclui o tempo até o primeiro frame elegível.
- Timing é amostra de CPU Lua EWMA no cliente; não mede GPU, servidor ou custo completo do motor. Os presets definem orçamento, não desempenho garantido.
- Alteração local de Health não é invulnerabilidade. Proteção confirmada só cobre o gate de dano instalado no próprio servidor.
- Não foram executados Luau Language Server/Selene com definições Roblox nem build Rojo; sintaxe foi compilada, e o mapeamento Rojo foi validado por testes de caminhos.

## Reprodução

~~~text
python scripts/verify.py --luau CAMINHO/luau.exe --compiler CAMINHO/luau-compile.exe --work-dir CAMINHO/gravação-temporária
python scripts/check_public_urls.py --ref v4.0.0
python scripts/check_public_urls.py --ref main --report docs/github-main-check.json
~~~

Testes Raw somente leem HTTP e comparam bytes. Resultados de publicação estão em [PUBLICATION.json](PUBLICATION.json), [tag](github-tag-check.json) e [main](github-main-check.json). Relatórios antigos 1.x são históricos; este documento descreve o estado V4.
