# Desafio de Nivelamento — Infraestrutura

**Duração sugerida:** Parte 1 (Linux) ~2h · Partes 2 e 3 (Kubernetes e GKE) ~2h30 · Bônus opcional.

Este documento tem **tudo** o que você precisa fazer. No final, o avaliador roda um script no seu WSL que confere cada item e calcula a nota. **Siga os nomes, caminhos, portas e valores exatamente como estão escritos.** O script procura por eles.

## Setup do ambiente (faça antes de tudo)

O desafio troca hostname, SSH e `/etc/fstab` e cria usuários. Por isso ele roda numa distro WSL **nova e dedicada**, nunca na que você usa no dia a dia.

1. No **PowerShell do Windows**, crie a distro (o `--name` exige WSL 2.4.4 ou mais novo; confira com `wsl --version` e, se precisar, rode `wsl --update`):

   ```powershell
   wsl --install Ubuntu-24.04 --name desafio
   ```

   Na primeira abertura, crie o seu usuário e a sua senha do Linux.

2. No **Docker Desktop**: *Settings > Resources > WSL integration*, ligue a distro **`desafio`** e clique em *Apply & restart*.

3. Entre na distro e confira o ambiente:

   ```bash
   wsl -d desafio                      # no PowerShell
   systemctl is-system-running         # running (ou degraded)
   docker ps                           # lista sem erro
   kubectl version --client            # vem junto com o Docker Desktop
   ```

4. **Daqui em diante, todo comando do desafio roda dentro da distro `desafio`.** Depois da correção, siga a seção **LIMPEZA**, no fim deste documento.

## Regras

1. **Consulta permitida:** os PDFs de nivelamento (Linux e Kubernetes), `man`, `--help` e `kubectl explain`. **Proibido:** IA, fóruns e busca de soluções. A internet só pode ser usada para instalar pacotes e baixar ferramentas e imagens.
2. **Todos os comandos** rodam no terminal da distro WSL **`desafio`** (Ubuntu 24.04), inclusive `docker` e `kubectl`.
3. **Não existe script pronto.** Você monta tudo com os comandos que estudou. Este documento diz **o que** precisa existir, não **como** fazer.
4. **Não use atalhos perigosos.** `chmod 777`, imagens `:latest` e Secret com senha em arquivo **descontam pontos**.
5. Tudo o que você entrega fica em **`~/desafio/`**, com esta estrutura:

```
~/desafio/
├── linux/
│   ├── revisao.txt
│   └── relatorio.md
├── k8s/
│   ├── revisao.txt
│   ├── relatorio.md
│   ├── emissor/        (app.py + Dockerfile)
│   └── manifestos/     (seus YAMLs)
├── gke/                (YAMLs + DEPLOY.md)
└── terraform/          (bônus)
```

---

# PARTE 1 — LINUX

## 1.1 Revisão de código (sem executar nada)

O script abaixo foi deixado pelo time anterior. Ele tem **vários problemas**: riscos de segurança, erros que causam incidente e práticas que o material condena.

```
 1  #!/bin/bash
 2  BASE=$1
 3  apt upgrade -y && apt update
 4  apt install -y tree lsof openssh-server
 5  useradd -m -s /bin/bash svc-importador
 6  groupadd opsfiscal
 7  usermod -G opsfiscal operador
 8  mkdir -p $BASE/{entrada,processados,logs}
 9  chmod -R 777 $BASE/entrada
10  rm -rf $BASE/*
11  echo "/var/lib/discos/arq.img $BASE/arquivo ext4 loop,nofail 0 2" > /etc/fstab
12  cp /root/.ssh/id_ed25519 /home/operador/.ssh/authorized_keys
13  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
14  systemctl restart ssh
15  kill -9 $(pgrep -f importador.sh)
16  cat > /etc/systemd/system/importador.service <<FIM
17  [Service]
18  User=root
19  ExecStart=/opt/importador/importador.sh
20  FIM
21  systemctl daemon-reload
22  systemctl start importador
```

Em `~/desafio/linux/revisao.txt`, escreva **uma linha por problema**, começando pelo **número da linha**:

```
7 | o que está errado | como deveria ser
```

Cada problema real soma pontos. Cada linha apontada sem problema desconta.

## 1.2 Montagem do servidor

### Contexto e pacotes

- [ ] O systemd está ativo no WSL.
- [ ] O hostname é **`nf-node-01`**.
- [ ] Os pacotes `tree`, `lsof`, `htop` e `openssh-server` estão instalados.
- [ ] O pacote `htop` **não pode ser atualizado** por um `apt upgrade` futuro.

### Usuários e grupos

- [ ] **`svc-importador`**: usuário **de serviço** (de sistema). É quem roda o importador e **não pode ter login interativo**.
- [ ] **`opsfiscal`**: grupo do time de operação.
- [ ] **`operador`**: usuário com home e shell bash, membro de `opsfiscal`.

### Diretórios e permissões

| Caminho | Dono:Grupo | Permissão |
|---|---|---|
| `/opt/importador` | `root:opsfiscal` | 750 |
| `/opt/importador/importador.sh` | `root:opsfiscal` | 750 |
| `/srv/nfdata` | `root:opsfiscal` | 750 |
| `/srv/nfdata/entrada` | `svc-importador:opsfiscal` | 770 |
| `/srv/nfdata/processados` | `svc-importador:opsfiscal` | 750 |
| `/srv/nfdata/logs` | `svc-importador:svc-importador` | 750 |
| `/srv/nfdata/conf` | `svc-importador:svc-importador` | 750 |
| `/srv/nfdata/conf/importador.conf` | `svc-importador:svc-importador` | 640 |
| `/srv/nfdata/arquivo` (**depois** de montado) | `svc-importador:opsfiscal` | 750 |

Conteúdo de `/srv/nfdata/conf/importador.conf`:

```
INTERVALO=5
DIR_ENTRADA=/srv/nfdata/entrada
DIR_PROCESSADOS=/srv/nfdata/processados
DIR_LOGS=/srv/nfdata/logs
```

Conteúdo de `/opt/importador/importador.sh` (**não altere**):

```bash
#!/bin/bash
set -eu
source /srv/nfdata/conf/importador.conf
while true; do
  for f in "$DIR_ENTRADA"/*.xml; do
    [ -e "$f" ] || continue
    mv "$f" "$DIR_PROCESSADOS"/
    echo "$(date '+%F %T') importado $(basename "$f")" | tee -a "$DIR_LOGS/importador.log"
  done
  sleep "$INTERVALO"
done
```

### Disco de arquivamento

- [ ] Existe o arquivo **`/var/lib/discos/arquivo-nf.img`**, com **200 MB** e formatado em **ext4**.
- [ ] Ele é montado em **`/srv/nfdata/arquivo`** de forma **permanente**, pelo `/etc/fstab`.
- [ ] A montagem usa as opções `loop`, `noatime` e `nofail`, com dump `0` e pass `2`.
- [ ] Depois de montado, o diretório tem o dono e a permissão da tabela acima.

### Serviço `importador`

Crie a unit `/etc/systemd/system/importador.service`. Ela precisa:

- [ ] rodar como `svc-importador`;
- [ ] executar `/opt/importador/importador.sh`;
- [ ] subir depois da rede;
- [ ] reiniciar sozinha **se falhar** (`on-failure`), esperando **5 segundos** entre as tentativas;
- [ ] estar **ativa agora** e **subir no boot**.

**Teste:** logado como `operador`, crie `/srv/nfdata/entrada/teste.xml`. Em até 5 segundos, o arquivo deve ir para `processados` e aparecer uma linha no log.

### SSH

- [ ] O SSH está ativo e habilitado.
- [ ] **O seu usuário** do WSL tem uma chave **ed25519** no caminho padrão.
- [ ] O comando **`ssh nfnode`**, executado pelo seu usuário, entra como `operador` em `localhost` **sem pedir senha**. O nome `nfnode` é um atalho configurado no SSH.
- [ ] Depois que o acesso por chave funcionar, o servidor **proíbe login como root** e **proíbe autenticação por senha**.

## 1.3 Incidentes

Com a montagem concluída, **execute as simulações abaixo**. Cada uma quebra algo no servidor. Descubra **por que** quebrou e **corrija**, sem recriar nada do zero e sem perder dados.

**Incidente L1, disco cheio:**

```bash
sudo systemd-run --unit=nf-arquivo-sync bash -c "exec 3>/srv/nfdata/arquivo/.sync.tmp; head -c 140M /dev/zero >&3; rm -f /srv/nfdata/arquivo/.sync.tmp; exec sleep infinity"
```

> O volume `/srv/nfdata/arquivo` ficou quase 100% cheio, mas ninguém acha o arquivo culpado. **Libere o espaço** e mantenha o volume montado.

**Incidente L2, operador sem acesso:**

```bash
sudo chmod 666 /home/operador/.ssh/authorized_keys
```

> O `ssh nfnode` passou a ser recusado (`Permission denied (publickey)`). **Restaure o acesso por chave.**

**Incidente L3, importador parado:**

```bash
sudo chown root:root /srv/nfdata/conf/importador.conf
sudo chmod 600 /srv/nfdata/conf/importador.conf
sudo systemctl restart importador
for i in 1 2 3; do sudo -u operador touch /srv/nfdata/entrada/nfe-sim-$i.xml; done
```

> Os XMLs estão se acumulando em `entrada`. **Faça o importador voltar a processar.** Os 3 arquivos `nfe-sim-*.xml` precisam chegar em `processados`.

## 1.4 Relatório

Em `~/desafio/linux/relatorio.md`, escreva uma seção por incidente, neste formato:

```markdown
## Incidente L1
- Sintoma:
- Diagnóstico: (quais comandos você usou e o que eles mostraram)
- Causa raiz:
- Correção:
- Prevenção:
```

---

# PARTE 2 — CONTAINERS E KUBERNETES

**Regra de labels:** todo Pod usa o label **`app: <nome do workload>`**. Por exemplo, os Pods do `portal` levam `app: portal`.

## 2.1 Revisão de manifesto (sem aplicar)

```
 1  apiVersion: v1
 2  kind: Secret
 3  metadata: { name: mongo-cred }
 4  data: { MONGO_INITDB_ROOT_PASSWORD: U2VuaGExMjM= }
 5  ---
 6  apiVersion: apps/v1
 7  kind: Deployment
 8  metadata: { name: mongo }
 9  spec:
10    replicas: 3
11    selector: { matchLabels: { app: mongo } }
12    template:
13      metadata: { labels: { app: mongo } }
14      spec:
15        containers:
16        - name: mongo
17          image: mongo:latest
18          volumeMounts: [{ name: dados, mountPath: /data/db }]
19        volumes: [{ name: dados, persistentVolumeClaim: { claimName: mongo-dados } }]
20  ---
21  apiVersion: apps/v1
22  kind: Deployment
23  metadata: { name: emissor }
24  spec:
25    selector: { matchLabels: { app: emissor } }
26    template:
27      metadata: { labels: { app: emisor } }
28      spec:
29        containers:
30        - name: emissor
31          image: emissor:1.0
32          ports: [{ containerPort: 8000 }]
33  ---
34  apiVersion: v1
35  kind: Service
36  metadata: { name: emissor }
37  spec:
38    type: LoadBalancer
39    selector: { app: emissor }
40    ports: [{ port: 80, targetPort: 8080 }]
41  ---
42  apiVersion: autoscaling/v2
43  kind: HorizontalPodAutoscaler
44  metadata: { name: emissor }
45  spec:
46    scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: emissor }
47    minReplicas: 2
48    maxReplicas: 5
49    metrics: [{ type: Resource, resource: { name: cpu, target: { type: Utilization, averageUtilization: 50 } } }]
50  ---
51  apiVersion: policy/v1
52  kind: PodDisruptionBudget
53  metadata: { name: portal }
54  spec:
55    minAvailable: 1
56    selector: { matchLabels: { app: portal } }   # o portal roda com 1 réplica
57  ---
58  apiVersion: batch/v1
59  kind: Job
60  metadata: { name: carga }
61  spec:
62    template:
63      spec:
64        restartPolicy: Always
65        containers: [{ name: carga, image: busybox:1.36, command: ["sh", "-c", "echo ok"] }]
```

Em `~/desafio/k8s/revisao.txt`, use o mesmo formato da Parte 1: `número da linha | problema | correção`.

## 2.2 Montagem

### Cluster

- [ ] O `kubectl` e o `k3d` estão instalados no WSL.
- [ ] Existe o cluster k3d **`prova`**, com **1 server e 2 agents**.
- [ ] O cluster publica no seu computador:
  - a porta **8080** para o Ingress (porta 80 do load balancer);
  - a porta **30080** para um NodePort.

> Defina as portas **na criação** do cluster.

### Imagem do emissor

Crie `~/desafio/k8s/emissor/app.py` com o conteúdo abaixo (**não altere**):

```python
"""Emissor: API de laboratório da Nota Fácil (responde também com o prefixo /api)."""
import json, os, socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def reservar_cache():
    """Reserva RESERVA_CACHE_MB de memória real na inicialização (pré-aquecimento de cache)."""
    mb = int(os.environ.get("RESERVA_CACHE_MB", "0") or 0)
    print(f"pre-aquecendo cache de {mb} MB", flush=True)
    cache = bytearray(mb * 1024 * 1024)
    for i in range(0, len(cache), 4096):
        cache[i] = 1
    return cache


class Handler(BaseHTTPRequestHandler):
    """Rotas: / (JSON), /saude, /saude/banco."""

    def responder(self, codigo, corpo, tipo="text/plain"):
        dados = corpo.encode()
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def do_GET(self):
        caminho = self.path.split("?")[0].removeprefix("/api").rstrip("/") or "/"
        if caminho == "/saude":
            self.responder(200, "ok\n")
        elif caminho == "/saude/banco":
            try:
                socket.create_connection((os.environ.get("MONGO_HOST", ""), 27017), timeout=2).close()
                self.responder(200, "ok\n")
            except OSError:
                self.responder(503, "banco indisponivel\n")
        else:
            corpo = {"servico": "emissor", "pod": socket.gethostname(), "ambiente": os.environ.get("AMBIENTE", "")}
            self.responder(200, json.dumps(corpo), "application/json")


if __name__ == "__main__":
    _cache = reservar_cache()
    print("emissor escutando na porta 8000", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
```

- [ ] Escreva `~/desafio/k8s/emissor/Dockerfile`:
  - base `python:3.12-slim`;
  - copia o `app.py`;
  - expõe a porta **8000**;
  - o processo principal é `python app.py`.
- [ ] Gere a imagem **`emissor:1.0`**.
- [ ] Leve a imagem para o cluster com `k3d image import emissor:1.0 -c prova`. Esse comando não está no material, por isso foi dado aqui.

### Objetos no namespace `notafacil`

Escreva **um arquivo YAML por etapa** em `~/desafio/k8s/manifestos/`. Um `kubectl apply -f ~/desafio/k8s/manifestos/` precisa recriar tudo, **exceto o Secret**.

| Objeto | Requisitos |
|---|---|
| Namespace `notafacil` | — |
| ConfigMap `portal-html` | Chave `index.html` contendo o texto **`Portal Nota Facil`** |
| ConfigMap `emissor-config` | `AMBIENTE=laboratorio` e `MONGO_HOST`, que é o **nome DNS estável da réplica 0 do banco** |
| Secret `mongo-cred` | **Criado por comando, nunca em arquivo.** `MONGO_INITDB_ROOT_USERNAME=admin` e `MONGO_INITDB_ROOT_PASSWORD=S3nhaDesafio` |
| `mongo` | `mongo:7.0`, 1 réplica, **identidade e disco próprios por réplica** (1Gi). Credenciais do Secret. Requests, limits e readinessProbe. Service que permita o **DNS por réplica** |
| `carga-inicial` | Roda **uma vez até terminar** (`mongo:7.0`). Insere no banco `fiscal`, coleção `notas`, o documento `{ chave: "NFE-0001", status: "autorizada" }`. As credenciais vêm do Secret |
| `portal` | `nginx:1.27`, **3 réplicas**, serve o `index.html` do ConfigMap. Requests, limits e readinessProbe HTTP. Service `portal`, **só interno**, porta 80 |
| `emissor` | `emissor:1.0`, 2 réplicas, todas as chaves de `emissor-config` como variáveis. readinessProbe e livenessProbe HTTP em `/saude`, porta 8000. Requests `cpu 50m` e `memory 64Mi`; limits `cpu 250m` e `memory 128Mi`. Service `emissor`, **só interno**, porta 80 → 8000 |
| Service `emissor-externo` | Expõe o emissor em **`http://localhost:30080`** |
| Ingress `entrada` | Classe `traefik`, host **`notafacil.local`**. `/api` vai para o `emissor` e `/` vai para o `portal` |
| Autoescala do emissor | De **2 a 5** réplicas, alvo de **50% de CPU** |
| Disponibilidade do portal | Uma manutenção de nó **nunca pode deixar menos de 2** Pods do portal |
| `limpeza` | Roda **a cada 2 minutos** (`busybox:1.36`) e imprime a data e `limpeza ok`. Sem execuções simultâneas; guarda as 3 últimas com sucesso |
| `agente-nf` | **Um Pod por nó** (`busybox:1.36`), imprimindo o nome do nó a cada 30 s. Com requests e limits |

**Testes:**

```bash
curl -H 'Host: notafacil.local' http://localhost:8080/               # mostra "Portal Nota Facil"
curl -H 'Host: notafacil.local' http://localhost:8080/api            # JSON do emissor
curl -H 'Host: notafacil.local' http://localhost:8080/api/saude/banco   # ok
curl http://localhost:30080/                                          # JSON do emissor
```

O HPA também deve mostrar o uso de CPU, e não `<unknown>`.

## 2.3 Incidentes

**Incidente K1, emissor reiniciando:**

```bash
kubectl -n notafacil set env deploy/emissor RESERVA_CACHE_MB=200
```

> O emissor passou a acumular RESTARTS. O time de produto avisa: **a reserva de cache é requisito e deve continuar ligada.** Corrija **também no seu manifesto**: um novo `kubectl apply` não pode desfazer a reserva nem trazer o problema de volta.

**Incidente K2, portal fora do ar:**

```bash
kubectl -n notafacil patch svc portal --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":8080}]'
```

> O portal não abre pelo Ingress, mas todos os Pods estão `Running`. **Restaure o acesso.**

**Incidente K3, banco não volta:**

```bash
NODE=$(kubectl -n notafacil get pod mongo-0 -o jsonpath='{.spec.nodeName}')
kubectl cordon "$NODE"
kubectl -n notafacil delete pod mongo-0
```

> O `mongo-0` não volta. **Restaure o banco sem perder o documento `NFE-0001`.**

## 2.4 Relatório

Em `~/desafio/k8s/relatorio.md`, use o mesmo formato da Parte 1, com seções `## Incidente K1`, `K2` e `K3`.

---

# PARTE 3 — ENTREGA PARA O GOOGLE CLOUD (GKE)

Nada será executado no Google Cloud. Copie seus manifestos para **`~/desafio/gke/`** e adapte-os seguindo esta tabela:

| No laboratório (k3d) | Na entrega (GKE) |
|---|---|
| `ingressClassName: traefik` | `ingressClassName: gce` |
| Host `notafacil.local` | Host `notafacil.exemplo.com.br` |
| StorageClass padrão | `storageClassName: standard-rwo`, explícita no `mongo` |
| Imagem `emissor:1.0` | `southamerica-east1-docker.pkg.dev/desafio-nivelamento/notafacil/emissor:1.0` |
| Secret criado por comando | **ExternalSecret** `mongo-cred`, lendo do `ClusterSecretStore` **`gcp-secret-manager`** o segredo **`notafacil-mongo-cred`**, propriedades `username` e `password` |
| Service `emissor-externo` | **Remover.** Nenhum Service `NodePort` ou `LoadBalancer` |
| Services `portal` e `emissor` | Anotação `cloud.google.com/neg: '{"ingress": true}'` |

Crie também **`~/desafio/gke/DEPLOY.md`**, o roteiro que o time de nuvem vai seguir. Ele precisa conter:

1. os comandos para publicar a imagem no Artifact Registry (`docker tag` e `docker push`);
2. como obter as credenciais do cluster (`gcloud container clusters get-credentials`);
3. como **conferir que está no cluster certo** antes de aplicar;
4. a ordem do `kubectl apply` e como verificar o resultado.

---

# BÔNUS — TERRAFORM (opcional, +10 pontos)

**Só comece depois de terminar as Partes 1 a 3.** Em `~/desafio/terraform/`, escreva o código que cria no projeto `desafio-nivelamento`:

- um cluster GKE `nf-prova`;
- um repositório Artifact Registry Docker `notafacil`;
- um segredo Secret Manager `notafacil-mongo-cred`, **sem valor**.

Use **variáveis** para projeto e região. Para validar sem credenciais do Google:

```bash
cd ~/desafio/terraform
docker run --rm -v "$PWD":/w -w /w hashicorp/terraform:1.9.8 fmt -check
docker run --rm -v "$PWD":/w -w /w hashicorp/terraform:1.9.8 init -backend=false
docker run --rm -v "$PWD":/w -w /w hashicorp/terraform:1.9.8 validate
```

---

# ENTREGA

1. Confira se tudo está em `~/desafio/`.
2. **Deixe o ambiente no ar:** WSL, Docker Desktop e o cluster `prova`.
3. Feche os terminais com `exit`, para que o histórico seja gravado, e chame o avaliador.

## Pontuação

| Parte | Pontos |
|---|---|
| Linux: revisão | 4 |
| Linux: montagem | 21 |
| Linux: incidentes | 12 |
| Linux: relatório | 3 |
| Kubernetes: revisão | 4 |
| Kubernetes: montagem | 26 |
| Kubernetes: incidentes | 12 |
| Kubernetes: relatório | 3 |
| Entrega GKE | 15 |
| **Total** | **100** |
| Bônus Terraform | +10 |
| Descontos: `chmod 777` (−5), `:latest` (−3), Secret com senha em arquivo (−5) | até −13 |

---

# LIMPEZA (depois da correção)

Só faça isto **depois** que o avaliador rodar o `avaliar.sh`. A limpeza apaga tudo o que o desafio criou. A ordem importa: o cluster k3d roda dentro do **Docker Desktop**, não na distro, e **não some** com o `wsl --unregister`.

1. **Dentro da distro `desafio`**, guarde o que quiser manter e apague o cluster e as imagens:

   ```bash
   cp -r ~/desafio /mnt/c/Users/<seu-usuario-windows>/desafio-backup   # opcional
   k3d cluster delete prova
   docker image rm emissor:1.0 hashicorp/terraform:1.9.8
   docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E 'rancher/k3s|k3d-io/k3d-(proxy|tools)' | xargs -r docker image rm
   ```

2. **No PowerShell do Windows**, apague a distro (isso remove usuários, disco loop, fstab e serviços junto com ela):

   ```powershell
   wsl --terminate desafio
   wsl --unregister desafio
   ```

3. **No Docker Desktop**: em *Settings > Resources > WSL integration*, se a distro `desafio` ainda aparecer, desligue-a e clique em *Apply & restart*.

4. **Confira** que não sobrou nada:

   ```powershell
   wsl -l -v                                         # 'desafio' não aparece
   docker ps -a --filter name=k3d-prova              # nenhum container
   docker network ls --filter name=k3d-prova         # nenhuma rede
   docker volume ls --filter name=k3d-prova          # nenhum volume
   ```
