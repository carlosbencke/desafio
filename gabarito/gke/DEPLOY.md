# Deploy da Nota Fácil no GKE

Pré-requisitos: `gcloud` autenticado no projeto `desafio-nivelamento`, cluster `nf-prova` criado, External Secrets Operator instalado com o `ClusterSecretStore` `gcp-secret-manager` e o segredo `notafacil-mongo-cred` (propriedades `username` e `password`) gravado no Secret Manager.

## 1. Publicar a imagem no Artifact Registry

```bash
gcloud auth configure-docker southamerica-east1-docker.pkg.dev
docker tag emissor:1.0 southamerica-east1-docker.pkg.dev/desafio-nivelamento/notafacil/emissor:1.0
docker push southamerica-east1-docker.pkg.dev/desafio-nivelamento/notafacil/emissor:1.0
```

## 2. Credenciais do cluster e conferência do contexto

```bash
gcloud container clusters get-credentials nf-prova --region southamerica-east1 --project desafio-nivelamento
kubectl config current-context    # deve terminar em _southamerica-east1_nf-prova
kubectl get nodes
```

## 3. Aplicar (nesta ordem)

```bash
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-config.yaml -f 02b-externalsecret.yaml
kubectl -n notafacil get externalsecret mongo-cred      # STATUS SecretSynced antes de seguir
kubectl apply -f 03-mongo.yaml
kubectl -n notafacil rollout status statefulset/mongo
kubectl apply -f 04-carga-inicial.yaml
kubectl apply -f 05-portal.yaml -f 06-emissor.yaml
kubectl apply -f 07-ingress.yaml -f 08-escala.yaml -f 09-rotinas.yaml
```

## 4. Verificar

```bash
kubectl -n notafacil rollout status deploy/portal
kubectl -n notafacil rollout status deploy/emissor
kubectl -n notafacil get pods,svc,ingress,hpa,pdb
kubectl -n notafacil describe ingress entrada      # backends HEALTHY; o IP externo pode levar alguns minutos
curl -H 'Host: notafacil.exemplo.com.br' http://<IP_DO_INGRESS>/api/saude/banco
```

## Rollback

```bash
kubectl -n notafacil rollout undo deploy/emissor
```
