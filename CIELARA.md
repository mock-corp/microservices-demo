# Online Boutique — Cielara Configuration

## Workload Discovery

Workloads are individual microservices under `src/`. Each subdirectory of `src/` is a
separate workload with its own language runtime and Dockerfile.

| Workload Folder              | Language | Description                        |
|------------------------------|----------|------------------------------------|
| `src/adservice`              | Java     | Context-based text ad serving      |
| `src/cartservice`            | C#       | Shopping cart backed by Redis      |
| `src/checkoutservice`        | Go       | Orchestrates checkout flow         |
| `src/currencyservice`        | Node.js  | Currency conversion (highest QPS)  |
| `src/emailservice`           | Python   | Order confirmation emails          |
| `src/frontend`               | Go       | Web UI and session management      |
| `src/loadgenerator`          | Python   | Locust-based synthetic traffic     |
| `src/paymentservice`         | Node.js  | Credit card charge processing      |
| `src/productcatalogservice`  | Go       | Product listing and search         |
| `src/recommendationservice`  | Python   | Cart-based product recommendations |
| `src/shippingservice`        | Go       | Shipping cost estimates            |
| `src/shoppingassistantservice`| Go      | AI shopping assistant              |

## Runtime Mapping

All workloads deploy to a single GKE Autopilot cluster provisioned by `terraform/`.
Kubernetes manifests live in two locations:

- `kubernetes-manifests/` — raw YAML per service (used for direct `kubectl apply`)
- `kustomize/base/` — Kustomize base manifests (used by Terraform deployment)

Both locations contain equivalent Deployment definitions.

### Environment: Production (wm-eval-customer-mock)

| Property    | Value                  |
|-------------|------------------------|
| Cloud       | GCP                    |
| Project     | wm-eval-customer-mock  |
| Cluster     | online-boutique        |
| Region      | us-central1            |
| Namespace   | default                |
| Deployment  | Terraform + Kustomize  |

### Workload-to-Deployment Mapping

To map a workload source folder to its running Kubernetes Deployment:

1. Take the folder basename: `src/<name>` → `<name>`
2. The Deployment is defined in `kubernetes-manifests/<name>.yaml` (and equivalently in `kustomize/base/<name>.yaml`)
3. The Deployment `metadata.name` equals `<name>`
4. The Service `metadata.name` equals `<name>`
5. The ServiceAccount `metadata.name` equals `<name>`

Explicit mapping:

| Source Folder                  | K8s Deployment              | K8s Service              | Port  |
|--------------------------------|-----------------------------|--------------------------|-------|
| `src/adservice`                | `adservice`                 | `adservice`              | 9555  |
| `src/cartservice`              | `cartservice`               | `cartservice`            | 7070  |
| `src/checkoutservice`          | `checkoutservice`           | `checkoutservice`        | 5050  |
| `src/currencyservice`          | `currencyservice`           | `currencyservice`        | 7000  |
| `src/emailservice`             | `emailservice`              | `emailservice`           | 8080  |
| `src/frontend`                 | `frontend`                  | `frontend`               | 8080  |
| `src/loadgenerator`            | `loadgenerator`             | —                        | —     |
| `src/paymentservice`           | `paymentservice`            | `paymentservice`         | 50051 |
| `src/productcatalogservice`    | `productcatalogservice`     | `productcatalogservice`  | 3550  |
| `src/recommendationservice`    | `recommendationservice`     | `recommendationservice`  | 8080  |
| `src/shippingservice`          | `shippingservice`           | `shippingservice`        | 50051 |
| `src/shoppingassistantservice` | `shoppingassistantservice`  | `shoppingassistantservice`| 80   |

Additional runtime resources not tied to a specific workload source:

| Resource         | K8s Deployment | K8s Service  | Port | Notes                     |
|------------------|----------------|--------------|------|---------------------------|
| Redis (cart)     | `redis-cart`   | `redis-cart` | 6379 | Defined in `cartservice.yaml` |

### External Access

The frontend is exposed via a `LoadBalancer` Service named `frontend-external` on port 80.

### Infrastructure

| Component        | Location             | Tool      |
|------------------|----------------------|-----------|
| GKE cluster      | `terraform/`         | Terraform |
| K8s manifests    | `kustomize/base/`    | Kustomize |
| Raw manifests    | `kubernetes-manifests/` | kubectl |
| Dockerfiles      | `src/<service>/Dockerfile` | Docker |

### Monitoring & Alerting

Alerts are configured in GCP Cloud Monitoring and route to PagerDuty via a notification channel.
Alert policies are created via `gcloud monitoring policies` (not Terraform-managed).
