output "service_id" {
  description = "ID of the Jenkins controller docker service"
  value       = docker_service.controller.id
}

output "wait_for_service_id" {
  description = "ID of the null resource waiting for the controller service"
  value       = null_resource.wait_for_service.id
}

output "casc_config" {
  value = yamlencode(var.casc_config)
}