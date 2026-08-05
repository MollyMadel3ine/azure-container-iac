# Prod: always warm (min 1 replica) so the live demo answers
# instantly — a deliberate ~$12/month trade for a standing portfolio
# demo. More CPU than dev to make the environments' difference
# visible in configuration, not just name.
environment_name = "prod"
min_replicas     = 1
max_replicas     = 3
container_cpu    = 0.5
container_memory = "1Gi"
