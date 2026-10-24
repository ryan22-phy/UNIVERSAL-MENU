# Protocolo do laboratório

O servidor inicia **negado por padrão**. `config/ServerPolicy` fica somente em
ServerScriptService. Para Studio, habilite `EnableStudioTests`: IDs sintéticos
negativos são aceitos somente no Studio; contas reais exigem `UserIds`.
Para servidor privado, habilite `EnablePrivateServers` e preencha `UserIds`.
Servidores públicos continuam negados. `PlaceIds` opcional restringe lugares.

Remotes: `ReplicatedStorage.VWMenuLabRemote.Request` e `.Response`, ambos
RemoteEvent. Nenhuma mensagem aceita Player/UserId fornecido pelo cliente.

Request: `{Id: integer 1..1e9, Action: string, Payload: table, Session?: string}`.
Response: `{Id, Ok: boolean, Reason: string, Session?: string, Data: table}`.
`Hello` cria uma sessão UUID vinculada a Player/Character. `Observe` renova a
concessão de 15 segundos; o cliente deve observar a cada 2 segundos. Sessões
expiradas, autorização revogada, troca de personagem, Release e saída do jogador
restauram WalkSpeed e removem a proteção. A resposta é assíncrona e pode se perder.

| Action | Payload |
| --- | --- |
| Hello / Observe / RestoreHealth / Release | `{}` |
| Flight | `{Enabled:boolean, Speed?:number, VerticalSpeed?:number}` |
| Speed | `{Enabled:boolean, WalkSpeed?:number, SprintSpeed?:number, Multiplier?:number}` |
| Godmode | `{Enabled:boolean}` |
| Damage | `{Amount:number}`; atinge somente o remetente, limitado por política |

Data contém `Authorized`, `Godmode`, `Health?`, `MaxHealth?`, `CharacterAlive`,
`Flight`, `Speed`, `ObservedHorizontalSpeed`, `PositionDelta`,
`DisplacementSpeed`, `SuspectedCorrection`, `CorrectionStatus="HEURISTIC_ONLY"`,
`ProtectionScope="DamageTestController.ApplyDamage ONLY"` e
`Policy={MaxFlightSpeed,MaxVerticalSpeed,MaxWalkSpeed}`. O servidor mede velocidade
horizontal real e deslocamento amostrado; saltos discrepantes são apenas uma
heurística. Teleporte, latência e colisão podem produzi-los. O resultado não prova
correção ou ação anticheat.

`Data.ConfirmedCorrection?={Sequence:number,Reason:string}` só é preenchido
pela instrumentação explícita do próprio jogo. Depois de aplicar uma correção,
um script de servidor pode notificar o hook **server-only**:

```luau
-- Execute depois da correção real feita pelo seu jogo.
game:GetService("ServerScriptService"):WaitForChild("VWMenuLabCorrection"):Fire(player, "Correção de posição aplicada pelo controlador do jogo")
```

O hook é um BindableEvent; valida jogador, sessão ativa e razão de 1–128 bytes.
Cada evento incrementa Sequence na sessão. Não movimenta o personagem, não
aplica correção nem aceita confirmação enviada pelo cliente. Release/respawn
remove o registro junto com a sessão. O cliente pode exibir `SERVER_REPORTED`
por três segundos após observar uma sequência nova. Esse sinal informado pelo
servidor é independente de `SuspectedCorrection`, que continua heurístico.

Payloads têm campos exatos, tipos simples, números finitos e limites. O servidor
limita requisições por jogador e mantém uma janela limitada de IDs duplicados.
Pacotes inválidos sem Id ou acima da taxa são descartados, portanto timeout é
possível. Somente Observe renova a concessão. Flight registra autorização, não
transfere controle da física ao servidor; Speed aplica um limite autorizado e
restaura o valor original do Humanoid ao encerrar.

## Proteção de saúde e armas do próprio jogo

`Godmode` bloqueia somente `DamageTestController:ApplyDamage`. Não há regeneração
em loop, alteração de MaxHealth, nem promessa de imunidade a scripts que escrevem
Health diretamente, resets, quedas ou sistemas de armas independentes.

As armas do servidor podem usar o gateway **server-only** criado pelo bootstrap:

```luau
local damageGate = game:GetService("ServerScriptService"):WaitForChild("VWMenuLabDamage")
local applied, reason = damageGate:Invoke(targetPlayer, 25)
```

A arma continua responsável por validar tiro, alcance, cadência, equipe e alvo
antes de chamar o gateway. O gateway não expõe RemoteFunction ao cliente. A
proteção só existe enquanto o jogador tem sessão autorizada válida, mesmo antes
da próxima limpeza periódica. `Damage` serve para teste próprio controlado;
`RestoreHealth` é uma ação explícita do laboratório, não ressuscita personagem.

`HealthDiagnostics:ProbeLocalHealth()` realiza uma única atribuição local de
Health ao MaxHealth atual e registra o resultado; não altera MaxHealth e não
concede proteção no servidor. Quando já está na saúde máxima, registra no-op.
O diagnóstico compara saúde local com a última observação real do servidor.
