#!/usr/bin/env bash
# Corretor do Desafio de Nivelamento (versão simplificada).
# Confere no WSL do avaliado tudo o que o DESAFIO.md pede e calcula a nota.
#
# Uso (no WSL do avaliado, com o ambiente no ar):
#   sudo bash avaliar.sh
#
# O resultado aparece na tela e é salvo em ~/desafio/resultado-<data>.txt do avaliado.
# shellcheck disable=SC2034  # variáveis usadas dentro dos comandos avaliados por check()
set -u

[ "$(id -u)" -eq 0 ] || { echo "Rode com sudo: sudo bash $0"; exit 1; }

CAND="${SUDO_USER:-$(getent passwd 1000 | cut -d: -f1)}"
HC="$(getent passwd "$CAND" | cut -d: -f6)"
D="$HC/desafio"
mkdir -p "$D"
SAIDA="$D/resultado-$(date +%Y%m%d-%H%M).txt"
exec > >(tee "$SAIDA") 2>&1

# ------------------------------------------------------------ valores do DESAFIO.md
HOST=nf-node-01 SVC=svc-importador GRP=opsfiscal OPER=operador
BASE=/srv/nfdata ARQ=/srv/nfdata/arquivo IMGDISCO=/var/lib/discos/arquivo-nf.img INTERVALO=5
NS=notafacil CTX=k3d-prova ING=notafacil.local
FRASE="Portal Nota Facil" SENHA=S3nhaDesafio CHAVE=NFE-0001
IMG_GKE=southamerica-east1-docker.pkg.dev/desafio-nivelamento/notafacil/emissor:1.0

declare -A PESO=(
  [linux-revisao]=4 [linux-montagem]=21 [linux-incidentes]=12 [linux-relatorio]=3
  [k8s-revisao]=4 [k8s-montagem]=26 [k8s-incidentes]=12 [k8s-relatorio]=3
  [gke]=15 [bonus-terraform]=10
)
ORDEM=(linux-revisao linux-montagem linux-incidentes linux-relatorio
       k8s-revisao k8s-montagem k8s-incidentes k8s-relatorio gke bonus-terraform)
declare -A OBT MAX
SEC=""
PENAL=0

# ------------------------------------------------------------ utilitários
soma() { awk -v a="$1" -v b="$2" 'BEGIN{print a+b}'; }

secao() { SEC=$1; OBT[$SEC]=0; MAX[$SEC]=0; printf '\n■ %s\n' "$2"; }

# check <pontos> <descrição> <comando>: soma os pontos se o comando terminar com sucesso.
check() {
  local pts=$1 desc=$2 cmd=$3
  MAX[$SEC]=$(soma "${MAX[$SEC]}" "$pts")
  if ( eval "$cmd" ) >/dev/null 2>&1; then
    OBT[$SEC]=$(soma "${OBT[$SEC]}" "$pts")
    printf '  ✔ %-4s %s\n' "$pts" "$desc"
  else
    printf '  ✘ %-4s %s\n' "$pts" "$desc"
  fi
}

perm() { stat -c '%U:%G:%a' "$1" 2>/dev/null; }
como() { runuser -u "$1" -- bash -c "$2"; }

# Kubeconfig do avaliado ou do root (se ele criou o cluster com sudo).
KCFG="$HC/.kube/config"
grep -q "name: $CTX" "$KCFG" 2>/dev/null || KCFG=/root/.kube/config
k() { kubectl --kubeconfig "$KCFG" --context "$CTX" --request-timeout=15s "$@"; }
kn() { k -n "$NS" "$@"; }
jp() { kn get "$1" -o "jsonpath=$2" 2>/dev/null; }

# Converte quantidade de memória do Kubernetes (128Mi, 1Gi, 512M) para MiB.
mi() {
  local v=${1:-0}
  case $v in
    *Gi) echo $(( ${v%Gi} * 1024 )) ;;
    *Mi) echo "${v%Mi}" ;;
    *G)  echo $(( ${v%G} * 1000000000 / 1048576 )) ;;
    *M)  echo $(( ${v%M} * 1000000 / 1048576 )) ;;
    *Ki) echo $(( ${v%Ki} / 1024 )) ;;
    *)   echo $(( v / 1048576 )) ;;
  esac
}

# revisao <arquivo> <defeitos> <linhas neutras>
# Defeitos separados por ';' e, dentro de cada um, as linhas aceitas separadas por ','.
revisao() {
  local arq=$1 defeitos=$2 neutras=" $3 " apont validas=" " hits=0 fp=0 n=0 d l ok
  local -a lista
  apont=" $(grep -oE '^[[:space:]]*[0-9]+' "$arq" 2>/dev/null | tr -d ' \t' | sort -un | tr '\n' ' ') "
  IFS=';' read -ra lista <<< "$defeitos"
  for d in "${lista[@]}"; do
    n=$((n + 1)); ok=0
    for l in ${d//,/ }; do
      validas+="$l "
      [[ $apont == *" $l "* ]] && ok=1
    done
    hits=$((hits + ok))
  done
  for l in $apont; do
    [[ $validas == *" $l "* || $neutras == *" $l "* ]] || fp=$((fp + 1))
  done
  MAX[$SEC]=$n
  OBT[$SEC]=$(awk -v h="$hits" -v f="$fp" 'BEGIN{x = h - 0.5 * f; print (x < 0 ? 0 : x)}')
  [ -f "$arq" ] || echo "  ✘ arquivo $arq não encontrado"
  echo "  problemas encontrados: $hits de $n · linhas apontadas sem problema: $fp"
}

# relatorio <arquivo>: cada campo obrigatório precisa aparecer preenchido nos 3 incidentes.
relatorio() {
  local arq=$1
  check 1 "Causa raiz descrita nos 3 incidentes" "[ \$(grep -ciE '^[-* ]*causa raiz:[[:space:]]*[^[:space:]]' '$arq') -ge 3 ]"
  check 1 "Correção descrita nos 3 incidentes"   "[ \$(grep -ciE '^[-* ]*corre(ç|c)(ã|a)o:[[:space:]]*[^[:space:]]' '$arq') -ge 3 ]"
  check 1 "Prevenção descrita nos 3 incidentes"  "[ \$(grep -ciE '^[-* ]*preven(ç|c)(ã|a)o:[[:space:]]*[^[:space:]]' '$arq') -ge 3 ]"
}

teste_importador() {
  local f="teste-avaliador-$$.xml"
  como "$OPER" "echo '<nfe/>' > $BASE/entrada/$f" || return 1
  sleep $((INTERVALO + 3))
  [ -e "$BASE/processados/$f" ] && grep -q "$f" "$BASE/logs/importador.log"
}

# findmnt --verify sem erro ([E]) no bloco do ponto de montagem do desafio.
fstab_ok() {
  ! findmnt --verify 2>&1 | awk -v t="$ARQ" '/^[^ \t]/ {cur = $0} cur == t && /\[E\]/ {bad = 1} END {exit !bad}'
}

unit() { grep -Eq "^[[:space:]]*$1[[:space:]]*=[[:space:]]*$2[[:space:]]*$" /etc/systemd/system/importador.service; }

ssh_nfnode() {
  como "$CAND" "ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new nfnode id -nG" | grep -qw "$GRP"
}

alias_nfnode() {
  local cfg
  cfg=$(como "$CAND" "ssh -G nfnode")
  grep -qx "user $OPER" <<< "$cfg" && grep -Eqx "hostname (localhost|127\.0\.0\.1|::1)" <<< "$cfg"
}

hardening() {
  mkdir -p /run/sshd
  local t
  t=$(sshd -T 2>/dev/null)
  grep -qx "permitrootlogin no" <<< "$t" && grep -qx "passwordauthentication no" <<< "$t"
}

doc_existe() {
  local n
  n=$(kn exec mongo-0 -- mongosh --quiet -u admin -p "$SENHA" --authenticationDatabase admin \
      --eval "db.getSiblingDB('fiscal').notas.countDocuments({chave:'$CHAVE'})" 2>/dev/null | tail -1 | tr -dc '0-9')
  [ "${n:-0}" -ge 1 ]
}

ingress() { curl -s -m 8 -H "Host: $ING" "http://localhost:8080$1"; }

yamls() { find "$1" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null; }
tem_latest() { yamls "$1" | xargs -r grep -hE '^[[:space:]]*-?[[:space:]]*image:' | grep -Eq ':latest|image:[[:space:]]*[^:]+$'; }
tem_secret() { yamls "$1" | xargs -r grep -lE '^kind:[[:space:]]*Secret[[:space:]]*$' | grep -q .; }

echo "Desafio de Nivelamento — correção de $CAND ($(date '+%F %T'))"

# ============================================================ PARTE 1 — LINUX
secao linux-revisao "Linux · Revisão de código"
revisao "$D/linux/revisao.txt" "3;5;7;9;2,10;11;12;13,14;15;18;16,17,20,22" "1 4 6 8 19 21"

secao linux-montagem "Linux · Montagem do servidor"
check 1   "systemd ativo"                         '[[ $(systemctl is-system-running) =~ ^(running|degraded)$ ]]'
check 1   "hostname nf-node-01"                   '[ "$(hostname)" = "$HOST" ]'
check 1   "pacotes tree, lsof, htop e openssh-server" 'for p in tree lsof htop openssh-server; do dpkg -s $p | grep -q "ok installed" || exit 1; done'
check 1   "htop travado (hold)"                   'apt-mark showhold | grep -qx htop'
check 1   "svc-importador é usuário de sistema sem login" '[ "$(id -u $SVC)" -lt 1000 ] && getent passwd $SVC | grep -Eq "(nologin|false)$"'
check 1   "operador com home, bash e no grupo opsfiscal" 'getent passwd $OPER | grep -q "/bin/bash$" && [ -d /home/$OPER ] && id -nG $OPER | grep -qw $GRP'
check 0.5 "/opt/importador root:opsfiscal 750"    '[ "$(perm /opt/importador)" = "root:$GRP:750" ]'
check 0.5 "importador.sh root:opsfiscal 750"      '[ "$(perm /opt/importador/importador.sh)" = "root:$GRP:750" ]'
check 0.5 "/srv/nfdata root:opsfiscal 750"        '[ "$(perm $BASE)" = "root:$GRP:750" ]'
check 0.5 "entrada svc-importador:opsfiscal 770"  '[ "$(perm $BASE/entrada)" = "$SVC:$GRP:770" ]'
check 0.5 "processados svc-importador:opsfiscal 750" '[ "$(perm $BASE/processados)" = "$SVC:$GRP:750" ]'
check 0.5 "logs e conf svc-importador 750"        '[ "$(perm $BASE/logs)" = "$SVC:$SVC:750" ] && [ "$(perm $BASE/conf)" = "$SVC:$SVC:750" ]'
check 0.5 "importador.conf 640 com o conteúdo pedido" '[ "$(perm $BASE/conf/importador.conf)" = "$SVC:$SVC:640" ] && grep -qx "INTERVALO=5" $BASE/conf/importador.conf && grep -qx "DIR_ENTRADA=$BASE/entrada" $BASE/conf/importador.conf && grep -qx "DIR_PROCESSADOS=$BASE/processados" $BASE/conf/importador.conf && grep -qx "DIR_LOGS=$BASE/logs" $BASE/conf/importador.conf'
check 1   "disco em arquivo de 200 MB em ext4"    's=$(stat -c %s $IMGDISCO); [ $s -ge 199000000 ] && [ $s -le 230686720 ] && [ "$(blkid -o value -s TYPE $IMGDISCO)" = ext4 ]'
check 1   "linha do fstab (loop, noatime, nofail, 0 2)" 'awk -v m=$ARQ -v i=$IMGDISCO '"'"'$1==i && $2==m && $3=="ext4" && $4~/loop/ && $4~/noatime/ && $4~/nofail/ && $5=="0" && $6=="2" {ok=1} END{exit !ok}'"'"' /etc/fstab'
check 1   "disco montado com noatime e fstab válido" 'findmnt -n --mountpoint $ARQ -o OPTIONS | grep -q noatime && fstab_ok'
check 1   "disco montado com dono e permissão corretos" 'findmnt -n --mountpoint $ARQ && [ "$(perm $ARQ)" = "$SVC:$GRP:750" ]'
check 0.5 "unit: User=svc-importador"             'unit User $SVC'
check 0.5 "unit: Restart=on-failure e RestartSec=5" 'unit Restart on-failure && unit RestartSec "5s?"'
check 0.5 "unit: After=network e WantedBy=multi-user.target" 'grep -Eq "^After=.*network" /etc/systemd/system/importador.service && unit WantedBy multi-user.target'
check 1   "importador ativo e habilitado"         'systemctl is-active -q importador && systemctl is-enabled -q importador'
check 2   "teste ponta a ponta: operador grava, importador processa e registra no log" 'teste_importador'
check 0.5 "SSH ativo e habilitado"                '(systemctl is-active -q ssh || systemctl is-active -q ssh.socket) && (systemctl is-enabled -q ssh || systemctl is-enabled -q ssh.socket)'
check 0.5 "chave ed25519 do avaliado (600)"       '[ "$(perm $HC/.ssh/id_ed25519)" = "$CAND:$(id -gn $CAND):600" ] && [ -f $HC/.ssh/id_ed25519.pub ]'
check 0.5 "atalho nfnode no ~/.ssh/config"       'alias_nfnode'
check 1.5 "ssh nfnode entra como operador sem senha" 'ssh_nfnode'
check 1   "sshd: root e senha proibidos"          'hardening'

secao linux-incidentes "Linux · Incidentes"
check 2   "L1: volume continua montado e sem arquivo apagado preso a processo" 'findmnt -n --mountpoint $ARQ && ! lsof +L1 2>/dev/null | grep -qF "$ARQ"'
check 2   "L1: uso do volume abaixo de 50%"       'findmnt -n --mountpoint $ARQ && [ "$(df --output=pcent $ARQ | tail -1 | tr -dc 0-9)" -lt 50 ]'
check 2   "L2: authorized_keys do operador de volta a 600" '[ "$(perm /home/$OPER/.ssh/authorized_keys)" = "$OPER:$OPER:600" ]'
check 2   "L2: acesso por chave restaurado"       'ssh_nfnode'
check 1   "L3: importador.conf de volta a svc-importador 640" '[ "$(perm $BASE/conf/importador.conf)" = "$SVC:$SVC:640" ]'
check 1   "L3: importador ativo"                  'systemctl is-active -q importador'
check 2   "L3: os 3 XMLs simulados foram processados" 'for i in 1 2 3; do [ -e $BASE/processados/nfe-sim-$i.xml ] || exit 1; done'

secao linux-relatorio "Linux · Relatório"
relatorio "$D/linux/relatorio.md"

# ============================================================ PARTE 2 — KUBERNETES
secao k8s-revisao "Kubernetes · Revisão de manifesto"
revisao "$D/k8s/revisao.txt" "2,3,4;7,10,19;17;25,27;29,30,31,32,49;40;38;55,56;64" "8 11 13 16 18 23 36 44 46 47 48 53 60 65"

secao k8s-montagem "Kubernetes · Montagem"
check 1   "cluster prova com 3 nós Ready"         '[ "$(k get nodes --no-headers | grep -cw Ready)" -eq 3 ]'
check 1   "portas 8080 e 30080 publicadas na criação do cluster" 'p=$(docker ps --format "{{.Names}} {{.Ports}}" | grep "^k3d-prova-"); grep -q ":8080->80/tcp" <<< "$p" && grep -q ":30080->30080/tcp" <<< "$p"'
check 1   "Dockerfile (python:3.12-slim, app.py, EXPOSE 8000, CMD)" 'f=$D/k8s/emissor/Dockerfile; grep -Eqi "^FROM[[:space:]]+python:3\.12-slim" $f && grep -Eqi "^COPY.*app\.py" $f && grep -Eqi "^EXPOSE[[:space:]]+8000" $f && grep -Eqi "^(CMD|ENTRYPOINT).*app\.py" $f'
check 0.5 "imagem emissor:1.0 gerada"             'docker image inspect emissor:1.0'
check 0.5 "namespace notafacil"                   'k get namespace $NS'
check 0.5 "ConfigMap portal-html com a frase"     'jp configmap/portal-html "{.data.index\.html}" | grep -q "$FRASE"'
check 0.5 "ConfigMap emissor-config (AMBIENTE e MONGO_HOST)" '[ "$(jp configmap/emissor-config "{.data.AMBIENTE}")" = laboratorio ] && jp configmap/emissor-config "{.data.MONGO_HOST}" | grep -Eq "^mongo-0\.mongo(\.$NS(\.svc(\.cluster\.local)?)?)?$"'
check 0.5 "Secret mongo-cred com a senha"         '[ "$(jp secret/mongo-cred "{.data.MONGO_INITDB_ROOT_PASSWORD}" | base64 -d)" = "$SENHA" ]'
check 1   "mongo é StatefulSet pronto"            '[ "$(jp statefulset/mongo "{.status.readyReplicas}")" = 1 ]'
check 0.5 "Service mongo headless"                '[ "$(jp svc/mongo "{.spec.clusterIP}")" = None ]'
check 0.5 "PVC do mongo-0 Bound"                  'kn get pvc --no-headers | grep -E -- "-mongo-0[[:space:]]" | grep -qw Bound'
check 0.5 "mongo com requests, limits e readiness" '[ -n "$(jp statefulset/mongo "{.spec.template.spec.containers[0].resources.requests}")" ] && [ -n "$(jp statefulset/mongo "{.spec.template.spec.containers[0].resources.limits}")" ] && [ -n "$(jp statefulset/mongo "{.spec.template.spec.containers[0].readinessProbe}")" ]'
check 0.5 "Job carga-inicial concluído, com credenciais do Secret" '[ "$(jp job/carga-inicial "{.status.succeeded}")" -ge 1 ] && jp job/carga-inicial "{.spec}" | grep -q mongo-cred && ! jp job/carga-inicial "{.spec}" | grep -q "$SENHA"'
check 1   "documento NFE-0001 no banco"           'doc_existe'
check 0.5 "portal com 3 réplicas prontas"         '[ "$(jp deploy/portal "{.status.readyReplicas}")" -ge 3 ]'
check 0.5 "portal servindo o ConfigMap"           'jp deploy/portal "{.spec.template.spec.volumes[*].configMap.name}" | grep -qw portal-html'
check 0.5 "Service portal interno (ClusterIP) porta 80" '[ "$(jp svc/portal "{.spec.type}")" = ClusterIP ] && jp svc/portal "{.spec.ports[*].port}" | grep -qw 80'
check 1   "emissor com imagem emissor:1.0 e 2+ réplicas prontas" 'jp deploy/emissor "{.spec.template.spec.containers[0].image}" | grep -Eq "(^|/)emissor:1\.0$" && [ "$(jp deploy/emissor "{.status.readyReplicas}")" -ge 2 ]'
check 0.5 "emissor recebe emissor-config"         'jp deploy/emissor "{.spec.template.spec.containers[0].envFrom[*].configMapRef.name}" | grep -qw emissor-config'
check 0.5 "emissor com probes HTTP em /saude"     '[ "$(jp deploy/emissor "{.spec.template.spec.containers[0].readinessProbe.httpGet.path}")" = /saude ] && [ "$(jp deploy/emissor "{.spec.template.spec.containers[0].livenessProbe.httpGet.path}")" = /saude ]'
check 0.5 "emissor com requests e limit de CPU pedidos" '[ "$(jp deploy/emissor "{.spec.template.spec.containers[0].resources.requests.cpu}")" = 50m ] && [ "$(mi "$(jp deploy/emissor "{.spec.template.spec.containers[0].resources.requests.memory}")")" -eq 64 ] && [ "$(jp deploy/emissor "{.spec.template.spec.containers[0].resources.limits.cpu}")" = 250m ]'
check 0.5 "Service emissor interno 80 → 8000"     '[ "$(jp svc/emissor "{.spec.type}")" = ClusterIP ] && [ "$(jp svc/emissor "{.spec.ports[0].port}-{.spec.ports[0].targetPort}")" = 80-8000 ]'
check 1   "emissor-externo responde em localhost:30080" '[ "$(jp svc/emissor-externo "{.spec.type}")" = NodePort ] && curl -s -m 8 http://localhost:30080/ | grep -q "\"emissor\""'
check 0.5 "Ingress entrada (traefik, notafacil.local)" '[ "$(jp ingress/entrada "{.spec.ingressClassName}")" = traefik ] && [ "$(jp ingress/entrada "{.spec.rules[0].host}")" = "$ING" ]'
check 1   "portal pelo Ingress"                   'ingress / | grep -q "$FRASE"'
check 1   "emissor pelo Ingress (/api)"           'ingress /api | grep -q "\"emissor\""'
check 0.5 "banco acessível pela API (/api/saude/banco)" 'ingress /api/saude/banco | grep -qx ok'
check 1   "HPA do emissor 2–5, alvo 50% de CPU"   '[ "$(jp hpa/emissor "{.spec.minReplicas}-{.spec.maxReplicas}-{.spec.metrics[0].resource.target.averageUtilization}")" = 2-5-50 ]'
check 0.5 "HPA lendo métrica (não <unknown>)"     '[ -n "$(jp hpa/emissor "{.status.currentMetrics[0].resource.current.averageUtilization}")" ]'
check 0.5 "PDB do portal com minAvailable 2"      'kn get pdb -o jsonpath="{range .items[*]}{.spec.selector.matchLabels.app}={.spec.minAvailable}{\"\n\"}{end}" | grep -qx "portal=2"'
check 0.5 "CronJob limpeza a cada 2 min, Forbid, histórico 3" '[ "$(jp cronjob/limpeza "{.spec.schedule}|{.spec.concurrencyPolicy}|{.spec.successfulJobsHistoryLimit}")" = "*/2 * * * *|Forbid|3" ]'
check 0.5 "CronJob limpeza já executou com sucesso" '[ -n "$(jp cronjob/limpeza "{.status.lastSuccessfulTime}")" ]'
check 0.5 "DaemonSet agente-nf com 1 Pod em cada um dos 3 nós" '[ "$(jp daemonset/agente-nf "{.status.desiredNumberScheduled}-{.status.numberReady}")" = 3-3 ] && [ -n "$(jp daemonset/agente-nf "{.spec.template.spec.containers[0].resources.limits}")" ]'
check 1   "manifestos versionados (5+ arquivos, aplicáveis)" '[ "$(yamls $D/k8s/manifestos | wc -l)" -ge 5 ] && k apply --dry-run=client -f $D/k8s/manifestos/'
check 0.5 "nenhum Secret e nenhum :latest nos manifestos" '! tem_secret $D/k8s/manifestos && ! tem_latest $D/k8s/manifestos'

secao k8s-incidentes "Kubernetes · Incidentes"
check 1   "K1: reserva de cache mantida (RESERVA_CACHE_MB=200)" 'jp deploy/emissor "{.spec.template.spec.containers[0].env[?(@.name==\"RESERVA_CACHE_MB\")].value}" | grep -qx 200'
check 1   "K1: limit de memória do emissor ≥ 256Mi" '[ "$(mi "$(jp deploy/emissor "{.spec.template.spec.containers[0].resources.limits.memory}")")" -ge 256 ]'
check 1   "K1: rollout completo e réplicas prontas" '[ "$(jp deploy/emissor "{.status.updatedReplicas}")" = "$(jp deploy/emissor "{.status.readyReplicas}")" ] && [ "$(jp deploy/emissor "{.status.readyReplicas}")" -ge 2 ]'
check 1   "K1: correção registrada no manifesto"  'yamls $D/k8s/manifestos | xargs grep -l RESERVA_CACHE_MB | grep -q .'
check 2   "K2: targetPort do portal de volta a 80" '[ "$(jp svc/portal "{.spec.ports[0].targetPort}")" = 80 ]'
check 2   "K2: portal abre pelo Ingress"          'ingress / | grep -q "$FRASE"'
check 2   "K3: nenhum nó bloqueado (cordon)"      '[ "$(k get nodes --no-headers | wc -l)" -eq 3 ] && ! k get nodes --no-headers | grep -q SchedulingDisabled'
check 2   "K3: mongo-0 pronto e documento preservado" '[ "$(jp pod/mongo-0 "{.status.containerStatuses[0].ready}")" = true ] && doc_existe'

secao k8s-relatorio "Kubernetes · Relatório"
relatorio "$D/k8s/relatorio.md"

# ============================================================ PARTE 3 — GKE
secao gke "Entrega para o GKE"
G="$D/gke"
gk() { yamls "$G" | xargs -r cat 2>/dev/null; }
check 1   "manifestos na pasta gke (5+ arquivos)" '[ "$(yamls $G | wc -l)" -ge 5 ]'
check 1   "nenhum Secret na entrega"              '[ "$(yamls $G | wc -l)" -ge 1 ] && ! tem_secret $G'
check 2   "ExternalSecret mongo-cred via gcp-secret-manager" 'gk | grep -Eq "^kind:[[:space:]]*ExternalSecret" && gk | grep -q "gcp-secret-manager" && gk | grep -q "notafacil-mongo-cred" && gk | grep -q "ClusterSecretStore"'
check 1   "Ingress com ingressClassName gce"      'gk | grep -Eq "ingressClassName:[[:space:]]*gce"'
check 1   "host notafacil.exemplo.com.br"         'gk | grep -q "notafacil.exemplo.com.br"'
check 1   "mongo com storageClassName standard-rwo" 'gk | grep -Eq "storageClassName:[[:space:]]*standard-rwo"'
check 1   "imagem do Artifact Registry"           'gk | grep -q "$IMG_GKE"'
check 1   "sem NodePort, LoadBalancer ou emissor-externo" '! gk | grep -Eq "type:[[:space:]]*(NodePort|LoadBalancer)|emissor-externo"'
check 1   "anotação NEG nos Services portal e emissor" '[ "$(gk | grep -c "cloud.google.com/neg")" -ge 2 ]'
check 1   "nenhuma imagem :latest"                '[ "$(yamls $G | wc -l)" -ge 1 ] && ! tem_latest $G'
check 1   "DEPLOY.md: docker tag e docker push"   'grep -q "docker tag" $G/DEPLOY.md && grep -q "docker push" $G/DEPLOY.md'
check 1   "DEPLOY.md: get-credentials"            'grep -q "get-credentials" $G/DEPLOY.md'
check 1   "DEPLOY.md: confere o contexto antes de aplicar" 'grep -Eq "current-context|get-contexts" $G/DEPLOY.md'
check 1   "DEPLOY.md: kubectl apply e verificação" 'grep -q "kubectl apply" $G/DEPLOY.md && grep -Eq "rollout status|get pods|get all" $G/DEPLOY.md'

# ============================================================ BÔNUS — TERRAFORM
secao bonus-terraform "Bônus · Terraform"
T="$D/terraform"
tf() { cat "$T"/*.tf 2>/dev/null; }
tfdocker() { timeout 300 docker run --rm -v "$T":/w -w /w hashicorp/terraform:1.9.8 "$@"; }
check 1   "recurso google_container_cluster"      'tf | grep -q "resource \"google_container_cluster\""'
check 1   "recurso google_artifact_registry_repository" 'tf | grep -q "resource \"google_artifact_registry_repository\""'
check 1   "recurso google_secret_manager_secret"  'tf | grep -q "resource \"google_secret_manager_secret\""'
check 1   "variáveis para projeto e região"       'tf | grep -Eq "variable \"[^\"]*proje" && tf | grep -Eq "variable \"[^\"]*(regiao|region|location)"'
check 1   "nenhum valor de segredo no código"     'ls $T/*.tf && ! tf | grep -q "secret_data"'
check 2   "terraform fmt -check"                  'ls $T/*.tf && tfdocker fmt -check'
check 3   "terraform init + validate"             'ls $T/*.tf && tfdocker init -backend=false -input=false && tfdocker validate'
rm -rf "$T/.terraform" "$T/.terraform.lock.hcl" 2>/dev/null

# ============================================================ DESCONTOS
printf '\n■ Descontos\n'
desconto() { PENAL=$(soma "$PENAL" "$1"); printf '  ✘ %-4s %s\n' "$1" "$2"; }
# Remove trechos entre aspas e exige chmod em posição de comando: texto da revisão digitado
# no terminal (echo '9 | chmod 777 ...', grep 'chmod 777') não pode gerar desconto.
cat "$HC/.bash_history" /root/.bash_history 2>/dev/null | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" \
  | grep -Eq '(^|;|&&|\|\||sudo|xargs|-exec)[[:space:]]*chmod[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(0?777|a\+rwx|ugo\+rwx)' \
  && desconto -5 "chmod 777 no histórico de comandos"
{ tem_latest "$D/k8s/manifestos" || tem_latest "$G"; } && desconto -3 "imagem :latest (ou sem tag) nos manifestos"
{ tem_secret "$D/k8s/manifestos" || tem_secret "$G"; } && desconto -5 "Secret com senha em arquivo"
[ "$PENAL" = 0 ] && echo "  nenhum"

# ============================================================ NOTA
printf '\n%-24s %10s %8s\n' "SEÇÃO" "ACERTOS" "PONTOS"
TOTAL=0
for s in "${ORDEM[@]}"; do
  [ "$s" = bonus-terraform ] && continue
  p=$(awk -v o="${OBT[$s]}" -v m="${MAX[$s]}" -v w="${PESO[$s]}" 'BEGIN{printf "%.1f", (m > 0 ? o / m * w : 0)}')
  TOTAL=$(soma "$TOTAL" "$p")
  printf '%-24s %10s %5s/%-3s\n' "$s" "${OBT[$s]}/${MAX[$s]}" "$p" "${PESO[$s]}"
done
BONUS=$(awk -v o="${OBT[bonus-terraform]}" -v m="${MAX[bonus-terraform]}" 'BEGIN{printf "%.1f", (m > 0 ? o / m * 10 : 0)}')
NOTA=$(awk -v t="$TOTAL" -v p="$PENAL" 'BEGIN{x = t + p; printf "%.1f", (x < 0 ? 0 : x)}')
FAIXA=$(awk -v n="$NOTA" 'BEGIN{print (n >= 80 ? "Pronto para plantão acompanhado" : n >= 60 ? "Júnior operacional" : "Precisa de trilha")}')

printf '\nSubtotal %s · Descontos %s\n' "$TOTAL" "$PENAL"
printf 'NOTA FINAL: %s / 100   (+ bônus Terraform %s / 10)\n' "$NOTA" "$BONUS"
printf 'Faixa: %s\n' "$FAIXA"
printf 'Resultado salvo em %s\n' "$SAIDA"
