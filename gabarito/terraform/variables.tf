variable "projeto" {
  description = "ID do projeto GCP"
  type        = string
  default     = "desafio-nivelamento"
}

variable "regiao" {
  description = "Região dos recursos"
  type        = string
  default     = "southamerica-east1"
}

variable "repositorio" {
  description = "Nome do repositório de imagens e prefixo do segredo"
  type        = string
  default     = "notafacil"
}
