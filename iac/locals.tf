locals {
  image_rebuild_trigger = var.image_rebuild_trigger == "" ? timestamp() : var.image_rebuild_trigger
}
