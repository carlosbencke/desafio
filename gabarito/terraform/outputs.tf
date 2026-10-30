output "cluster" {
  value = google_container_cluster.nf_prova.name
}

output "repositorio_imagens" {
  value = "${var.regiao}-docker.pkg.dev/${var.projeto}/${google_artifact_registry_repository.imagens.repository_id}"
}

output "segredo_mongo" {
  value = google_secret_manager_secret.mongo_cred.secret_id
}
