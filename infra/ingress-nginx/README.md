# ingress-nginx (kind provider)

This uses the official kind-specific ingress-nginx manifest instead of the Helm
chart. The kind provider manifest already wires the controller to run on the
node labelled `ingress-ready=true` and binds host ports 80/443, which matches
`kind/cluster-config.yaml`.

Installed/removed via `scripts/install-ingress-nginx.sh`.
