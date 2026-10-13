# saas-exam-platform-deployment
OCP/Kubernetes deployment configuration for SaaS exam platform (backend, frontend, databases)

## Backend on OpenShift (ROSA on AWS)

Deploys [saas-exam-platform-backend](https://github.com/andrewsselvaraj/saas-exam-platform-backend)
(Spring Boot 3.5, Java 17, H2 file database, port 8080) to Red Hat OpenShift Service on AWS.

```
backend/
  docker/Dockerfile                 image build outside the cluster (e.g. for Amazon ECR)
  openshift/base/                   ImageStream, BuildConfig (S2I), ConfigMap, PVC,
                                    Deployment, Service, Route, secret.example.yaml
  openshift/overlays/rosa/          namespace saas-exam, gp3-csi storage class
scripts/
  rosa-create-cluster.sh            creates a ROSA classic STS cluster
  deploy-backend.sh                 creates the DB secret, applies the overlay, builds, rolls out
```

### 1. Create the cluster (skip if you already have one)

Needs the `aws` and `rosa` CLIs, ROSA enabled in the AWS account, and `rosa login`.

```bash
CLUSTER_NAME=saas-exam AWS_REGION=ap-south-1 ./scripts/rosa-create-cluster.sh
```

Then `oc login` with the admin credentials it prints.

### 2. Deploy the backend

```bash
./scripts/deploy-backend.sh
```

This creates project `saas-exam`, generates the `exam-backend-db` secret if it is missing,
applies `backend/openshift/overlays/rosa`, builds the image from the backend repo's `main`
branch and waits for the rollout. It prints the public URLs:

- API: `https://<route-host>/api/orgs`
- Swagger UI: `https://<route-host>/swagger-ui.html`

Redeploy after pushing backend changes with `oc start-build exam-backend --follow -n saas-exam`.
To build a different branch, change `spec.source.git.ref` in `backend/openshift/base/buildconfig.yaml`.

### How it is configured

- **Config**: `application.yml` is overridden with environment variables from the
  `exam-backend-config` ConfigMap. The H2 file moves to `/data/examdb` on a 5Gi EBS (gp3) volume,
  and the H2 web console is turned off because the route is public.
- **Secrets**: `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD` come from the
  `exam-backend-db` Secret, which is never committed (see `secret.example.yaml`). H2 creates the
  database with these credentials on first start, so don't change them afterwards.
- **Health**: the backend has no Spring Boot Actuator, so the readiness and startup probes call
  `GET /api/orgs`. The startup probe allows 5 minutes because the first start runs the Flyway seed.
- **Scaling**: H2 in file mode allows one process per database and the EBS volume is
  ReadWriteOnce, so the Deployment runs 1 replica with the `Recreate` strategy. To scale out,
  move the data to a server database such as Amazon RDS for MySQL and raise `replicas`.
- **TLS**: the Route uses edge termination on the cluster's default certificate and redirects HTTP to HTTPS.

### Building the image outside OpenShift

From a checkout of the backend repo:

```bash
docker build -f ../saas-exam-platform-deployment/backend/docker/Dockerfile -t exam-backend .
```
