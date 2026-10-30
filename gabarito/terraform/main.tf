resource "google_container_cluster" "nf_prova" {
  name                = "nf-prova"
  location            = var.regiao
  enable_autopilot    = true
  deletion_protection = false
}

resource "google_artifact_registry_repository" "imagens" {
  location      = var.regiao
  repository_id = var.repositorio
  format        = "DOCKER"
}

# O valor do segredo é gravado pelo time de segurança fora do Terraform, para não ir parar no state.
resource "google_secret_manager_secret" "mongo_cred" {
  secret_id = "${var.repositorio}-mongo-cred"
  replication {
    auto {}
  }
}
