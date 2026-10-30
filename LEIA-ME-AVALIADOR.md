# Desafio de Nivelamento (versão simplificada): guia do avaliador

## O que tem na pasta

| Arquivo | Para quem | Uso |
|---|---|---|
| `DESAFIO.md` | Avaliado | Todos os passos, do início ao fim. É o único arquivo que ele recebe |
| `avaliar.sh` | Avaliador | Confere tudo no WSL do avaliado e calcula a nota |
| `gabarito/` | Avaliador | Solução de referência (manifestos, GKE, Terraform, Dockerfile). **Não entregar** |
| `LEIA-ME-AVALIADOR.md` | Avaliador | Este guia |

## Como aplicar

1. Entregue o `DESAFIO.md` ao avaliado.
2. **Pré-requisitos da máquina:** WSL com Ubuntu e Docker Desktop com integração WSL habilitada.
3. O avaliado segue o documento até a seção **ENTREGA**. Sugestão: Parte 1 num dia, Partes 2 e 3 em outro.
4. No fim, com o ambiente dele ainda no ar, copie o `avaliar.sh` para o WSL dele e rode:

   ```bash
   sudo bash avaliar.sh
   ```

5. A nota aparece na tela e fica salva em `~/desafio/resultado-<data>.txt`. Se precisar corrigir de novo, rode outra vez; o script só lê o ambiente, não altera nada.

> Entregue o `avaliar.sh` **só na hora da correção**. Ele mostra exatamente o que é verificado.

## Nota

| Seção | Pontos | Como é medido |
|---|---|---|
| Linux: revisão | 4 | Linhas certas apontadas em `~/desafio/linux/revisao.txt`. Linha apontada sem problema desconta meio acerto |
| Linux: montagem | 21 | Usuários, permissões, disco/fstab, serviço, teste real do importador, SSH |
| Linux: incidentes | 12 | Estado final depois das 3 simulações |
| Linux: relatório | 3 | Causa raiz, correção e prevenção preenchidas nos 3 incidentes |
| K8s: revisão | 4 | Igual à do Linux |
| K8s: montagem | 26 | Objetos no cluster e testes com `curl` pelo Ingress e pelo NodePort |
| K8s: incidentes | 12 | Estado final depois das 3 simulações (inclusive a correção no manifesto) |
| K8s: relatório | 3 | Igual ao do Linux |
| Entrega GKE | 15 | Conferência dos arquivos em `~/desafio/gke` |
| Bônus Terraform | +10 | Recursos, variáveis e `terraform fmt`/`validate` via Docker |
| Descontos | até −13 | `chmod 777` no histórico (−5), `:latest` (−3), Secret com senha em arquivo (−5) |

**Faixas:** ≥80 pronto para plantão acompanhado · 60–79 júnior operacional · <60 precisa de trilha.

## Gabarito da revisão

**Linux** (11 problemas):

| Linha | Problema |
|---|---|
| 3 | `upgrade` antes do `update` |
| 5 | Usuário de serviço com login e bash |
| 7 | `usermod -G` sem `-a` |
| 9 | `chmod 777` |
| 2/10 | `rm -rf $BASE/*` com variável possivelmente vazia |
| 11 | `>` sobrescreve o fstab |
| 12 | Chave **privada** copiada para o authorized_keys |
| 13/14 | Desliga senha e reinicia sem `sshd -t` e sem testar a chave |
| 15 | `kill -9` de primeira |
| 18 | Serviço rodando como root |
| 16/17/20/22 | Unit sem `[Install]` e `start` sem `enable` |

Linhas neutras (não descontam): 4, 6, 8, 19 e 21.

**Kubernetes** (9 problemas):

| Linha | Problema |
|---|---|
| 2–4 | Secret versionado |
| 7/10/19 | Banco em Deployment com 3 réplicas e PVC RWO |
| 17 | `:latest` |
| 25/27 | Label não casa com o selector |
| 29–32/49 | HPA de CPU sem requests |
| 38 | LoadBalancer em vez de Ingress |
| 40 | `targetPort` errado |
| 55/56 | PDB igual ao número de réplicas trava o drain |
| 64 | `restartPolicy: Always` em Job |

Linhas neutras: 11, 13, 18, 46, 47 e 48.

## Gabarito dos incidentes

| Incidente | Causa | Correção esperada |
|---|---|---|
| L1 | Arquivo apagado ainda aberto por um processo (`lsof +L1`) | Encerrar com SIGTERM (`systemctl stop nf-arquivo-sync` ou `kill <pid>`) |
| L2 | `authorized_keys` com 666, recusado pelo StrictModes | `chmod 600` |
| L3 | Conf ilegível para o usuário de serviço | `chown svc-importador:` + `chmod 640`; o serviço volta sozinho |
| K1 | Reserva de 200 MB maior que o limit de 128Mi (OOMKilled) | Manter a variável e subir o limit (≥256Mi) **no manifesto** + `apply` |
| K2 | `targetPort` 8080 em vez de 80 | Reaplicar o manifesto ou corrigir o Service |
| K3 | Nó em cordon e PV local-path preso a ele | `kubectl uncordon <nó>`, sem apagar o PVC |

## Limites desta versão

- **As simulações estão no documento**, então o avaliado sabe o que foi quebrado. O script mede se ele **resolveu**, não **como** diagnosticou. Para medir o diagnóstico, use o kit completo em `desafio-nivelamento/` (incidentes às cegas, teach-back e índice de hábitos).
- **Valores fixos para todos:** dá para copiar do colega. Se for aplicar na mesma sala, separe as pessoas ou use o kit completo, que tem fichas individuais.
- **Faça um piloto antes**, seguindo o `gabarito/`, para confirmar que a nota fica perto de 100 nas máquinas de vocês.
