locals {
  image_rebuild_trigger = var.image_rebuild_trigger == "" ? timestamp() : var.image_rebuild_trigger
  docker_build_args     = join(" ", [for k, v in var.docker_build_args : "--build-arg ${k}=${v}"])
}
