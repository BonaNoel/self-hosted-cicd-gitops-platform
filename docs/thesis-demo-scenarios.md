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

Or use the measurement runner, which samples the HPA and pod resources every
5 seconds while the traffic Job runs. It saves results outside this repository
under `~/thesis-writing/meresek/<run-id>/` by default:

```bash
bash scripts/run-hpa-measurement.sh
```

Set `WORKERS`, `REQUESTS`, `CPU_MILLIS`, `IO_MILLIS`, `COMPLEXITY`,
`PAUSE_SECONDS`, or `SAMPLE_INTERVAL_SECONDS` to customize the run. `RUN_LABEL`
sets a recognizable experiment label. While it runs, watch Grafana and save
screenshots in that run's `screenshots/` subdirectory. The output includes
`hpa-samples.csv`, `pod-resources.tsv`, `traffic.log`, pre/post YAML snapshots,
and `metadata.txt` with the exact workload profile and timestamps.

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
demand, run the alert measurement script. It temporarily scales the application
Deployment to zero, samples the alert state and workload status, holds the alert
firing for screenshots, then restores the original replica count automatically.
This causes a brief planned outage; run it only in the demo environment:

```bash
RUN_LABEL=alert-trial-01 bash scripts/run-alerting-measurement.sh
```

The default wait matches `PipelinePilotDown`'s 2-minute `for` duration. Configure
`HOLD_SECONDS` to extend the screenshot window. Results are saved outside the
repository under `~/thesis-writing/meresek/<run-id>/`.

The script measures `PipelinePilotDown`. The other rules have different
thresholds and require separate controlled load or failure scenarios.

**Record:**
- Screenshot of `http://prometheus.local/alerts` showing the alert transition
  `inactive` → `pending` → `firing`
- Screenshot of the same alert in Alertmanager or Grafana's Alerting view
- Timestamp fired, timestamp resolved after remediation

---

## 4. Delivery lead-time measurement

Demonstrates end-to-end delivery speed of the self-hosted pipeline.

Start the watcher first:

```bash
RUN_LABEL=trial-01 bash scripts/run-deployment-lead-time-measurement.sh
```

When it reports that it is watching, make a small, real application change in
`apps/pipeline-pilot/` and push it to the Gitea `development` branch. The script
records when it first observes the remote revision, when Argo CD sees the new
revision, and when Argo CD is `Synced`/`Healthy` and all desired application pods
are `Ready`. Its polling interval is 2 seconds by default, and can be changed
with `POLL_SECONDS`.

The result directory is created outside the repository at
`~/thesis-writing/meresek/<run-id>/`. It includes `deployment-timeline.csv`,
`metadata.txt`, and before/after YAML snapshots. The reported lead time starts
when the script first observes the remote branch change, not at the exact push
timestamp; the uncertainty is bounded by the polling interval. If an exact push
timestamp is needed, record it separately at push time.

The script captures the deployment milestones automatically. For the CI stages,
also record these timestamps from the Gitea Actions run:

| Event | Where to check | Timestamp |
|---|---|---|
| CI workflow starts | Gitea Actions run view | |
| `mvn verify` completes | Gitea Actions job log | |
| Image pushed to registry | Gitea Actions job log (docker push step) | |
| `image-tag.yaml` bumped | Gitea commit history (CI bot commit) | |
| Push time (record separately for exact end-to-end lead time) | Gitea / terminal clock | |

End-to-end lead time = (all desired pods Ready) − (commit pushed timestamp).
The script also reports observed deployment time = (all desired pods Ready) −
(remote revision first observed).

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
