REGISTRY_URL_BASE=sfsenorthamerica-fcto-spc.registry.snowflakecomputing.com/plakhanpal/vicuna13bonrayserve/llm_repo
echo "Docker login to registry: ${REGISTRY_URL_BASE}"
docker login http://${REGISTRY_URL_BASE}