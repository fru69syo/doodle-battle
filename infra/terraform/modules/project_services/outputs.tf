output "enabled_services" {
  description = "APIs enabled by this module. Other modules depend on this output so that APIs are on before resources are created."
  value       = sort([for s in google_project_service.this : s.service])
}
