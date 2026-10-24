# Auditoria do projeto existente

Base: main 2c1563cbf4739f7756e406f2ce4bf1948b50b6d7. Inventário inicial: 59 arquivos; fontes e seus consumidores/testes inspecionados por domínio antes de modificar. O bundle foi reconhecido como gerado e comparado com o grafo do build. Documentos e relatórios 1.x foram mantidos como histórico. Nenhum segundo menu paralelo foi criado.

| Caminho inicial | Bytes UTF-8 | Papel inspecionado |
|---|---:|---|
| .gitattributes | 19 | Entrada / documentação / metadados |
| .gitignore | 50 | Entrada / documentação / metadados |
| CHANGELOG.md | 1480 | Entrada / documentação / metadados |
| README.md | 7775 | Entrada / documentação / metadados |
| config.example.json | 1092 | Entrada / documentação / metadados |
| config/ClientPolicy.luau | 661 | Entrada / documentação / metadados |
| default.project.json | 1641 | Entrada / documentação / metadados |
| dist/VWMenu.luau | 137993 | Bundle gerado |
| dist/manifest.json | 606 | Entrada / documentação / metadados |
| docs/IMPLEMENTATION.md | 4585 | Documento / evidência histórica |
| docs/PUBLICATION.json | 648 | Documento / evidência histórica |
| docs/PUBLIC_FIX_PLAN.md | 2831 | Documento / evidência histórica |
| docs/PUBLIC_REVIEW.md | 1104 | Documento / evidência histórica |
| docs/REVIEW.md | 1155 | Documento / evidência histórica |
| docs/SERVER_PROTOCOL.md | 4656 | Documento / evidência histórica |
| docs/VALIDATION.md | 8612 | Documento / evidência histórica |
| docs/github-main-check.json | 1870 | Documento / evidência histórica |
| docs/github-tag-check.json | 1882 | Documento / evidência histórica |
| docs/verification-results.json | 6039 | Documento / evidência histórica |
| loader.luau | 5962 | Entrada / documentação / metadados |
| scripts/build.py | 3761 | Build / validação / distribuição |
| scripts/check_public_urls.py | 2541 | Build / validação / distribuição |
| scripts/package.py | 1861 | Build / validação / distribuição |
| scripts/verify.py | 3921 | Build / validação / distribuição |
| smoke-test.luau | 1491 | Entrada / documentação / metadados |
| src/ServerBootstrap.server.luau | 1617 | Entrada / documentação / metadados |
| src/client/AimAssist.luau | 16828 | Módulo cliente e dependências |
| src/client/ClientController.luau | 18758 | Módulo cliente e dependências |
| src/client/Compatibility.luau | 2110 | Módulo cliente e dependências |
| src/client/ESPManager.luau | 15601 | Módulo cliente e dependências |
| src/client/EntityRegistry.luau | 3234 | Módulo cliente e dependências |
| src/client/FlightController.luau | 8461 | Módulo cliente e dependências |
| src/client/HealthDiagnostics.luau | 6381 | Módulo cliente e dependências |
| src/client/Main.client.luau | 848 | Módulo cliente e dependências |
| src/client/ServerBridge.luau | 6955 | Módulo cliente e dependências |
| src/client/SpeedController.luau | 5513 | Módulo cliente e dependências |
| src/config/ServerPolicy.luau | 619 | Backend / política privada |
| src/server/DamageTestController.luau | 1949 | Backend / política privada |
| src/server/PermissionService.luau | 4345 | Backend / política privada |
| src/server/ServerTestService.luau | 14588 | Backend / política privada |
| src/shared/CleanupManager.luau | 1215 | Configuração / UI / ciclo de vida |
| src/shared/ConfigManager.luau | 8225 | Configuração / UI / ciclo de vida |
| src/shared/Diagnostics.luau | 932 | Configuração / UI / ciclo de vida |
| src/shared/UIManager.luau | 41282 | Configuração / UI / ciclo de vida |
| tests/bootstrap.spec.luau | 8908 | Harness / regressão |
| tests/bridge.spec.luau | 2452 | Harness / regressão |
| tests/combat_visuals.spec.luau | 13699 | Harness / regressão |
| tests/config.spec.luau | 2586 | Harness / regressão |
| tests/entities.spec.luau | 1847 | Harness / regressão |
| tests/loader.spec.luau | 11984 | Harness / regressão |
| tests/movement.spec.luau | 14726 | Harness / regressão |
| tests/run_bootstrap_tests.py | 1221 | Harness / regressão |
| tests/run_combat_tests.py | 1196 | Harness / regressão |
| tests/run_loader_tests.py | 1310 | Harness / regressão |
| tests/run_movement_tests.py | 1790 | Harness / regressão |
| tests/server_policy.spec.luau | 5872 | Harness / regressão |
| tests/test_build.py | 3092 | Harness / regressão |
| tests/ui.spec.luau | 13634 | Harness / regressão |
| version.json | 386 | Entrada / documentação / metadados |

Novos arquivos V4: UniversalGameAdapter, alias GameAdapterManager, suite adapters, suite/runner ESP V4, brief visual e documentos V4. Segurança mantém política server-only fora do bundle; a UI pública não altera permissões.
