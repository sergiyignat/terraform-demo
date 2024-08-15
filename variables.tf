variable "region" {
  description = "Azure infrastructure region"
  type    = string
  default = "West Europe"
}

variable "env" {
  description = "Application env"
  type    = string
  default = "demo"
}

variable "prefix" {
  description = "Demo app type short name"
  type    = string
  default = "aca"
}