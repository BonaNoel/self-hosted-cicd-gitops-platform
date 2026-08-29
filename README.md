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


## Repository structure

- `apps/pipeline-pilot/` – Spring Boot demo app, Helm chart, Dockerfile, and Kubernetes manifests
- `infra/` – Helm values and notes for shared platform components (ingress-nginx, Gitea, ...)
- `scripts/` – bootstrap and runtime helper scripts
- `kind/` – local Kubernetes cluster definition
- `observability/` – Prometheus and log/monitoring configuration files
- `plan.txt` – original thesis plan and architecture notes
- `LICENSE` – project license


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

## Platform components (mgmt namespace)

The kind cluster has `mgmt` (platform tooling) and `dev` (app workloads) namespaces.
Install order so far:

```bash
./scripts/create-kind-cluster.sh
./scripts/install-ingress-nginx.sh   # kind-specific ingress-nginx manifest
./scripts/install-gitea.sh           # Helm install into mgmt namespace
```

- `infra/ingress-nginx/` – notes on the kind-provider ingress-nginx manifest used
- `infra/gitea/values.yaml` – Helm values for `gitea-charts/gitea`, using SQLite
  and in-process cache/queue/session backends (no Postgres/Redis) to keep the
  local demo lightweight; Gitea Actions is enabled for a later CI step.

Add `127.0.0.1 gitea.local` to `/etc/hosts`, then browse to http://gitea.local
(admin login `gitea_admin` / `ChangeMe123!`, defined in `infra/gitea/values.yaml`).

### Container registry

Gitea's built-in OCI container registry (Packages feature) is used instead of a
separate registry service - one less moving part, same auth/users. Images live
at `gitea.local/<owner>/<image>:<tag>`.

```bash
docker login gitea.local -u gitea_admin -p 'ChangeMe123!'
docker tag pipeline-pilot:latest gitea.local/gitea_admin/pipeline-pilot:latest
docker push gitea.local/gitea_admin/pipeline-pilot:latest
```

In-cluster pulls authenticate via a `regcred` `docker-registry` Secret (created
in the `mgmt` and `dev` namespaces from a `read:package`-scoped Gitea token),
referenced by the Helm chart's `imagePullSecrets` (see
`apps/pipeline-pilot/helm/pipeline-pilot/values.yaml`).

### CI: Gitea Actions

- `infra/act-runner/` – `gitea/act_runner` + a privileged `docker:dind`
  sidecar, deployed into `mgmt` via `scripts/install-act-runner.sh`. Jobs run
  in `catthehacker/ubuntu:act-latest` containers via the runner's Docker
  connection to the sidecar.
- CoreDNS has a rewrite rule (`gitea.local` → `ingress-nginx-controller` in
  the `ingress-nginx` namespace) so `gitea.local` resolves the same way
  in-cluster (for the runner/checkout/registry) as it does on the host.
- Workflow: `.gitea/workflows/pipeline-pilot-ci.yml` - runs `mvn verify`, then
  builds and pushes the image to the Gitea container registry on every push
  touching `apps/pipeline-pilot/**`. Registry credentials are stored as
  repo-level Actions secrets (`REGISTRY_USERNAME` / `REGISTRY_PASSWORD`).

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


## Thesis roadmap next steps

The current repo establishes the foundation. The next implementation phases are:

1. Create the kind cluster, have a basic config for it which can be updates as needed.
2. Install Gitea in kind, setup and wire in app repo.
3. Come up with artifactory, where we can store built image so that is also self hosted.
4. Create Gitea Actions CI (tests, image build, image publish).
5. Add GitOps automation with Argo CD (and optionally Flux comparison).
6. Add load generation and autoscaling scenarios to demonstrate scaling behavior.
7. Connect obesrvability into the app stack and validate log collection.

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
- Gitea Actions: https://docs.gitea.com/usage/actions/overview
- Gitea Runner: https://docs.gitea.com/runner/

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
