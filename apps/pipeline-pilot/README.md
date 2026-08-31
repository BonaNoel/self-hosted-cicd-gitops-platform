# pipeline-pilot

Spring Boot demo app for self-hosted CI/CD pipeline experiments.

## Endpoints

- `GET /health`
- `GET /users`
- `POST /orders`
- `GET /orders`
- `GET /simulate-load?cpuMillis=250&ioMillis=100&complexity=5000`
- `GET /actuator/prometheus`

## Local run

```bash
mvn spring-boot:run
```

## Build JAR

```bash
mvn clean package
```

## Build image

```bash
docker build -t pipeline-pilot:local .
```

## Manual registry test

The normal image build and push path is the Gitea Actions workflow. To test the
Gitea registry manually, use a Gitea account or token with package write access:

```bash
docker login gitea.local -u gitea_admin
docker tag pipeline-pilot:local gitea.local/gitea_admin/pipeline-pilot:manual
docker push gitea.local/gitea_admin/pipeline-pilot:manual
```

## Helm deployment model

Argo CD deploys this chart automatically from the `development` branch. Check
the rendered manifests locally before changing Helm values:

```bash
helm template pipeline-pilot ./helm/pipeline-pilot
```

The CI workflow updates `helm/pipeline-pilot/image-tag.yaml` after it publishes
an image. Argo CD then synchronizes that image tag into the `dev` namespace.

## Load simulation

```bash
curl "http://localhost:8080/simulate-load?cpuMillis=1500&ioMillis=500&complexity=15000"
```

For the cluster-wide observability experiment, use the configurable traffic
runner from the repository root: `bash scripts/run-observability-traffic-test.sh`.
Its Kubernetes Job manifest is at `traffic-test/job.yaml`.
