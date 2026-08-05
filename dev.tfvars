# Dev: scale to zero, minimal footprint. Cold starts are fine here.
environment_name = "dev"
min_replicas     = 0
max_replicas     = 2
container_cpu    = 0.25
container_memory = "0.5Gi"
