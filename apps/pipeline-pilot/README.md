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
docker build -t localhost:5000/pipeline-pilot:latest .
docker push localhost:5000/pipeline-pilot:latest
```

## Deploy to Kubernetes with Helm

```bash
helm upgrade --install pipeline-pilot ./helm/pipeline-pilot \
	--set image.repository=localhost:5000/pipeline-pilot \
	--set image.tag=latest
```

Check rendered manifests before deploy:

```bash
helm template pipeline-pilot ./helm/pipeline-pilot
```

## Optional: raw Kubernetes YAML

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
```

## Example load simulation calls

```bash
curl "http://localhost:8080/simulate-load?cpuMillis=1500&ioMillis=500&complexity=15000"
```

For higher sustained load, use `hey`:

```bash
hey -n 2000 -c 50 "http://localhost:8080/simulate-load?cpuMillis=300&ioMillis=50&complexity=8000"
```
