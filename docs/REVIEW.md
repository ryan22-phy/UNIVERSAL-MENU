# Revisão de integração

Revisão independente dos fontes, seguida de regressões locais. Sem execução
da engine ou do Xeno. Correções relevantes:

- Configuração rejeita teclas inexistentes, gamepad não implementado, CTRL
  reservado e binds em conflito. Mouse 1/2/3 são aceitos pela assistência.
- Reset aplica os padrões atomicamente, incluindo perfis com teclas trocadas.
- Fila cheia conclui o callback com falha; não deixa pedidos sem resposta.
- Saúde invalida callbacks antigos ao desativar e remove pedido de proteção
  rejeitado, sem afirmar invulnerabilidade por uma alteração local.
- O servidor acompanha a WalkSpeed normal enquanto o laboratório não possui
  seu controle e restaura o baseline anterior ao teste.
- Captura de atalho limpa ativação da mira mesmo com CurrentCamera ausente.
- Correção confirmada depende de um hook server-only; heurísticas permanecem
  identificadas separadamente.

Os testes reexecutáveis e suas saídas estão em `tests/` e
`docs/verification-results.json`. Nenhum resultado local deve ser interpretado
como validação de física, renderização, anticheat ou replicação real.
