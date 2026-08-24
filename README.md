# Self-hosted CI/CD Pipeline thesis repo

This repository is the practical foundation for the MSc thesis project focused on a self-hosted CI/CD pipeline. The goal is to demonstrate how a team can achieve local, reproducible delivery automation with a Git server, a CI engine, a private container registry, a Kubernetes runtime, deployment automation, and observability tooling.

The project is designed to be both educational and practical: it contains a sample Spring Boot application, a local Docker-based infrastructure baseline, and a Kubernetes-ready deployment model that can be used to explain modern DevOps and GitOps concepts in a thesis context.

## Thesis objective

The major research objective is to show that a self-hosted delivery pipeline can:

- increase development workflow automation,
- reduce reliance on external cloud services,
- improve traceability and control over builds and deployments,
- provide a realistic local environment for experimenting with CI/CD processes,
- and expose system health, performance, and behavior through observability tooling.

The repository therefore combines three layers:

1. application code for a demo service,
2. local infrastructure for CI/CD and observability,
3. documentation and deployment steps for repeatable thesis use.

## Architecture at a glance

The intended pipeline architecture is:

Developer -> Gitea -> Woodpecker CI -> Docker Registry -> kind/Kubernetes -> Observability stack

The local baseline currently includes the following working pieces:

- Gitea: Git hosting and repository management
- Docker Registry: private image registry for local build artifacts
- Prometheus: metrics collection
- Grafana: dashboards and observability visualization
- Spring Boot demo app: `pipeline-pilot`

The full target architecture includes the following next-stage components:

- Woodpecker CI for pipeline orchestration
- kind cluster for local Kubernetes execution
- Flux or Argo CD for GitOps-style deployment
- Loki and Promtail for centralized log collection
- load generation and scaling validation scenarios for the thesis

## Repository structure

- `apps/pipeline-pilot/` – Spring Boot demo app, Helm chart, Dockerfile, and Kubernetes manifests
- `scripts/` – bootstrap and runtime helper scripts
- `kind/` – local Kubernetes cluster definition
- `observability/` – Prometheus, Loki, and Promtail configuration files
- `docker-compose.yml` – local baseline Docker services
- `plan.txt` – original thesis plan and architecture notes
- `LICENSE` – project license

## Local prerequisite stack

You need the following installed on the machine that is running WSL:

- WSL2 with Ubuntu 22.04+
- Git
- Docker Desktop with WSL integration enabled
- Internet access for downloading toolchains and container images

Important: Docker Desktop is required for the local container and kind workflow. The bootstrap script installs the Java/Maven/Kubernetes toolchain inside WSL, but the Docker engine still has to be available from WSL through Docker Desktop.

## Bootstrapping the developer toolchain

From the repo root:

```bash
cd <repo-root>
chmod +x scripts/*.sh
./scripts/bootstrap-local.sh
source ~/.bashrc
```

This installs the following tools locally under `~/.local`:

- Java 21
- Maven
- kind
- kubectl
- Helm

## Starting the local infrastructure baseline

The repo includes a stable local baseline that is useful for the thesis environment before deeper CI/CD automation is added:

```bash
cd <repo-root>
./scripts/start-local-stack.sh
```

The services started by this script include:

- Gitea: http://localhost:3000
- Docker Registry: http://localhost:5000/v2/
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3001

To stop the stack:

```bash
./scripts/stop-local-stack.sh
```

If you call scripts with `sh` by habit, these scripts now re-run themselves with Bash automatically.

If Docker access fails with `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`:

- make sure Docker Desktop is running,
- verify WSL integration is enabled for your distro in Docker Desktop,
- and check your current user can access `/var/run/docker.sock`.

When you first open Gitea, complete the setup wizard and create an admin account. The initial stack is intentionally left in a ready-to-configure state.

## Building and testing the demo app

### Run unit/integration tests

```bash
cd <repo-root>
./scripts/test-demo.sh
```

### Build the application JAR

```bash
cd <repo-root>/apps/pipeline-pilot
mvn clean package
```

### Run the application locally

```bash
cd <repo-root>
./scripts/run-demo.sh
```

The application listens on port 8080 by default. You can check the health endpoint:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/users
curl "http://localhost:8080/simulate-load?cpuMillis=250&ioMillis=100&complexity=5000"
```

## Demo app endpoints

The Spring Boot service exposes the following API endpoints:

- `GET /health`
- `GET /users`
- `POST /orders`
- `GET /orders`
- `GET /simulate-load?cpuMillis=250&ioMillis=100&complexity=5000`
- `GET /actuator/prometheus`

These endpoints are useful for:

- app health validation,
- API behavior demonstration,
- load testing and resource profiling,
- and application metrics exposure for Prometheus scraping.

## Docker image workflow

Build the application image locally:

```bash
docker build -t pipeline-pilot:local ./apps/pipeline-pilot
```

Push it to the local registry:

```bash
docker tag pipeline-pilot:local localhost:5000/pipeline-pilot:latest
docker push localhost:5000/pipeline-pilot:latest
```

This is the basic pattern that the thesis can use to demonstrate a self-hosted build-and-publish flow.

## Kubernetes and kind setup

A local Kubernetes environment is part of the thesis target architecture. The repo includes a kind cluster config for this purpose:

```bash
cd <repo-root>
./scripts/create-kind-cluster.sh
kubectl cluster-info --context kind-thesis-cluster
```

To delete the cluster:

```bash
./scripts/delete-kind-cluster.sh
```

The cluster config is located at:

- `kind/cluster-config.yaml`

## Observability layer

The project includes a baseline observability stack for future thesis extension:

- Prometheus for metrics scraping
- Grafana for dashboard visualization
- Loki and Promtail for log aggregation
- Spring Boot Actuator metrics endpoint at `/actuator/prometheus`

This setup is intentionally small enough for local testing, but realistic enough to act as a lab environment for discussing system visibility and performance analysis.

## Thesis roadmap next steps

The current repo establishes the foundation. The next implementation phases are:

1. Wire Gitea as the source repository and create a real project flow.
2. Add Woodpecker CI and connect it to repository events.
3. Add a kind-based deployment path and validate application rollout.
4. Add GitOps automation with Flux or Argo CD.
5. Add load generation and autoscaling scenarios to demonstrate scaling behavior.
6. Connect Loki and Promtail into the app stack and validate log collection.
7. Finalize the architecture chapter and evaluation section based on the working local setup.

## Useful references

- Spring Boot: https://spring.io/projects/spring-boot
- Docker Desktop: https://www.docker.com/products/docker-desktop/
- Kubernetes: https://kubernetes.io/
- kind: https://kind.sigs.k8s.io/
- Helm: https://helm.sh/
- Prometheus: https://prometheus.io/
- Grafana: https://grafana.com/
- Loki: https://grafana.com/oss/loki/
- Gitea: https://about.gitea.com/
- Woodpecker CI: https://woodpecker-ci.org/

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
