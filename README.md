# saas-exam-platform-deployment
OCP/Kubernetes deployment configuration for SaaS exam platform (backend, frontend, databases)

## Backend on OpenShift (ROSA on AWS)

Deploys the [saas-exam-platform-backend](https://github.com/andrewsselvaraj/saas-exam-platform-backend)
microservices (Spring Boot 3.5, Java 17) to Red Hat OpenShift Service on AWS:

| Service            | Port | Database (H2 on a 5Gi gp3 volume) | Exposed                      |
|--------------------|------|-----------------------------------|------------------------------|
| `api-gateway`      | 8080 | none                              | public HTTPS Route, 2 copies |
| `catalog-service`  | 8081 | `catalogdb`                       | inside the cluster only      |
| `question-service` | 8082 | `questiondb`                      | inside the cluster only      |
| `exam-service`     | 8083 | `examdb`                          | inside the cluster only      |

Clients only talk to the gateway, which routes `/api/**` to the owning service. The services call each other
through their in-cluster Service names (`http://catalog-service:8081`, ...).

```
backend/
  docker/Dockerfile                 image build outside the cluster (e.g. for Amazon ECR), --build-arg SERVICE=...
  openshift/base/<service>/         ImageStream, BuildConfig (S2I), ConfigMap, Deployment, Service,
                                    plus PVC + secret.example.yaml (data services) or Route (gateway)
  openshift/overlays/rosa/          namespace saas-exam, gp3-csi storage class
scripts/
  rosa-create-cluster.sh            creates a ROSA classic STS cluster
  deploy-backend.sh                 creates the DB secrets, applies the overlay, builds all four services, rolls out
  remove-monolith.sh                removes the old single exam-backend deployment, after asking
```

### 1. Create the cluster (skip if you already have one)

Needs the `aws` and `rosa` CLIs, ROSA enabled in the AWS account, and `rosa login`.

```bash
CLUSTER_NAME=saas-exam AWS_REGION=ap-south-1 ./scripts/rosa-create-cluster.sh
```

Then `oc login` with the admin credentials it prints.

### 2. Deploy the services

```bash
./scripts/deploy-backend.sh
```

This creates project `saas-exam`, generates a `<service>-db` secret for each service that owns a database,
applies `backend/openshift/overlays/rosa`, builds all four images from the backend repo's `main` branch in
parallel and waits for every rollout. It prints the public API URL, e.g. `https://<route-host>/api/orgs`.

Redeploy one service after pushing backend changes with `oc start-build <service> --follow -n saas-exam`.
To build a different branch, change `spec.source.git.ref` in `backend/openshift/base/<service>/buildconfig.yaml`.

If the old single-backend deployment (`exam-backend`) is still running in the project, remove it once the
microservices are up with `./scripts/remove-monolith.sh`. It deletes that deployment's data volume.

### How it is configured

- **Builds**: each BuildConfig runs the Red Hat OpenJDK 17 S2I builder on the multi-module repo with
  `-pl <service> -am`, so it builds only that service and `common-lib`.
- **Config**: each service's `application.yml` is overridden by its ConfigMap: `PORT`, `DB_URL` (the H2 file
  moves to `/data` on the service's volume), the other services' URLs, and the H2 web console turned off.
- **Secrets**: `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD` come from each service's `<service>-db`
  Secret, which is never committed (see `secret.example.yaml`). H2 creates the database with these credentials on
  first start, so don't change them afterwards.
- **Health**: probes use Spring Boot Actuator's `/actuator/health/liveness` and `/readiness`. The data services
  allow 5 minutes to start because the first start runs the Flyway seed.
- **Scaling**: H2 in file mode allows one process per database and the EBS volumes are ReadWriteOnce, so the
  three data services run 1 replica each with the `Recreate` strategy. The gateway is stateless and runs 2 with
  rolling updates. To scale a data service, move its data to a server database such as Amazon RDS.
- **TLS**: the gateway Route uses edge termination on the cluster's default certificate and redirects HTTP to
  HTTPS. `/internal/**` endpoints are not routed by the gateway, so they stay inside the cluster.

### Building the images outside OpenShift

From a checkout of the backend repo, once per service:

```bash
docker build -f ../saas-exam-platform-deployment/backend/docker/Dockerfile \
  --build-arg SERVICE=catalog-service -t catalog-service .
```
