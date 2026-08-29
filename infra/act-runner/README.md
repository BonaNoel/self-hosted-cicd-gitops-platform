# Gitea Actions runner (act_runner)

Runs `gitea/act_runner` alongside a `docker:dind` sidecar in the `mgmt`
namespace, so workflow jobs can build and push container images.

- `GITEA_INSTANCE_URL` / job checkout URLs use `http://gitea.local` - CoreDNS
  is configured (see below) to resolve `gitea.local` in-cluster straight to
  the `ingress-nginx-controller` Service, so behavior matches host access.
- The runner talks to Docker over the shared `emptyDir` socket volume with
  the dind sidecar (`DOCKER_HOST=tcp://localhost:2376` with TLS, using the
  certs dind generates into a shared volume).
- Registration token is a one-time bootstrap secret (`act-runner-registration`);
  Gitea re-issues the runner its own long-lived token after first registration
  which act_runner persists in `/data` (backed by a PVC).

Installed via `scripts/install-act-runner.sh` (idempotent). CoreDNS rewrite
(`kubectl edit configmap coredns -n kube-system`) adds:

```
rewrite name gitea.local ingress-nginx-controller.ingress-nginx.svc.cluster.local
```
