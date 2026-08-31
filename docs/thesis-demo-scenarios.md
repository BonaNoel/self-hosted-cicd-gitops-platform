# Thesis demonstration scenarios

Concrete, repeatable experiments to run and capture (screenshots/logs/timestamps)
for the thesis results chapter. Each scenario lists exact commands, where to look,
and what to record.

Prerequisites: cluster up, all installers run (see README.md "Fresh local
installation"), `grafana.local` / `prometheus.local` / `argocd.local` reachable.

---

## 1. Autoscaling under load (HPA scale-out / scale-in)

Demonstrates the HPA reacting to sustained CPU pressure and Grafana visualizing it.

```bash
kubectl get hpa -n dev -w
```

In a second terminal:

```bash
WORKERS=8 REQUESTS=200 CPU_MILLIS=600 IO_MILLIS=25 COMPLEXITY=20000 PAUSE_SECONDS=0 \
  bash scripts/run-observability-traffic-test.sh
```

**Record:**
- Timestamp load starts
- Timestamp HPA `TARGETS` column crosses 60%
- Timestamp replicas increase (2 → higher)
- Timestamp new pods become `Ready` (`kubectl get pods -n dev -w`)
- Grafana `Pipeline Pilot Overview` dashboard screenshot: `HPA Current and
  Desired Replicas`, `Application CPU Utilization`, `HTTP Request Rate` panels
  during load
- Timestamp load ends, timestamp replicas scale back to baseline (2) after the
  HPA stabilization window

---

## 2. Failure and recovery (bad image tag)

Demonstrates GitOps failure visibility and recovery, not just happy-path deploys.

1. Edit `apps/pipeline-pilot/helm/pipeline-pilot/image-tag.yaml` in the Gitea
   `development` branch, set `tag` to a nonexistent value (e.g. `does-not-exist`).
2. Push the change.
3. Watch Argo CD: `http://argocd.local` — application goes `OutOfSync` then
   `Degraded`.
4. Watch Kubernetes: `kubectl get pods -n dev -w` — new pod shows
   `ImagePullBackOff` / `ErrImagePull`.
5. Screenshot Argo CD app view (red/degraded) and `kubectl describe pod` events.
6. Revert `image-tag.yaml` to a valid tag (or push a new commit / let CI publish
   a new one) and push.
7. Watch Argo CD return to `Synced` / `Healthy`, and the deployment reach the
   desired replica count with the old pod removed.

**Record:**
- Timestamp bad tag deployed
- Timestamp Argo CD shows Degraded
- Timestamp fix pushed
- Timestamp Argo CD shows Healthy again
- Recovery time = (Healthy timestamp) − (fix pushed timestamp)

---

## 3. Alerting

Demonstrates observability is actionable, not just visual.

Rules are in `infra/observability/pipeline-pilot-alerts.yaml`. To trigger one on
demand:

```bash
# High CPU utilization alert (target: >90% of requested CPU for 5 minutes)
WORKERS=10 REQUESTS=400 CPU_MILLIS=800 IO_MILLIS=10 COMPLEXITY=20000 PAUSE_SECONDS=0 \
  bash scripts/run-observability-traffic-test.sh
```

Or force `PipelinePilotDeploymentUnavailable` / `PipelinePilotDown`:

```bash
kubectl scale deployment/pipeline-pilot -n dev --replicas=0
# ...wait 5 minutes, observe alert firing...
kubectl scale deployment/pipeline-pilot -n dev --replicas=2
```

**Record:**
- Screenshot of `http://prometheus.local/alerts` showing the alert transition
  `inactive` → `pending` → `firing`
- Screenshot of the same alert in Alertmanager or Grafana's Alerting view
- Timestamp fired, timestamp resolved after remediation

---

## 4. Delivery lead-time measurement

Demonstrates end-to-end delivery speed of the self-hosted pipeline.

Make a trivial code change (e.g. a comment or log message) in
`apps/pipeline-pilot/`, push to `development`, and record each stage:

| Event | Where to check | Timestamp |
|---|---|---|
| Commit pushed | `git log` / Gitea commit view | |
| CI workflow starts | Gitea Actions run view | |
| `mvn verify` completes | Gitea Actions job log | |
| Image pushed to registry | Gitea Actions job log (docker push step) | |
| `image-tag.yaml` bumped | Gitea commit history (CI bot commit) | |
| Argo CD sync completes | Argo CD app history / UI | |
| New pod `Ready` | `kubectl get pods -n dev -w` | |

Lead time = (new pod Ready timestamp) − (commit pushed timestamp).

Repeat 2-3 times for an average and to show consistency.

---

## 5. Architecture and flow evidence

Already in `README.md` as Mermaid diagrams (Architecture, CI/CD Delivery Flow).
For the thesis document itself:
- Paste each Mermaid block into https://mermaid.live and export as SVG/PNG.
- Consider adding a failure/recovery sequence diagram and a namespace boundary
  diagram (`mgmt`, `dev`, `argocd`, `observability`) if scenario 2 above is used
  as a formal result.

---

## Quick reference: URLs and logins

| Service | URL | Login |
|---|---|---|
| Gitea | http://gitea.local | `gitea_admin` / `ChangeMe123!` |
| Argo CD | http://argocd.local | `admin` / (see README: initial-admin-secret) |
| Grafana | http://grafana.local | `admin` / `ChangeMe123!` |
| Prometheus | http://prometheus.local | — |
