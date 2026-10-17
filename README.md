# saas-exam-platform-deployment
OCP/Kubernetes deployment configuration for SaaS exam platform (backend, frontend, databases)

## Backend on OpenShift

Deploys the [saas-exam-platform-backend](https://github.com/andrewsselvaraj/saas-exam-platform-backend)
microservices (Spring Boot 3.5, Java 17) to OpenShift (tested on the Red Hat Developer Sandbox).
The data services use the existing MySQL schema `etfdb_dev` on `63.142.240.31`:

| Service            | Port | Database                 | Exposed                 |
|--------------------|------|--------------------------|-------------------------|
| `api-gateway`      | 8080 | none                     | public HTTPS Route      |
| `catalog-service`  | 8081 | MySQL `etfdb_dev`        | inside the cluster only |
| `question-service` | 8082 | MySQL `etfdb_dev`        | inside the cluster only |
| `exam-service`     | 8083 | MySQL `etfdb_dev`        | inside the cluster only |

Clients only talk to the gateway, which routes `/api/**` to the owning service. The services call each other
through their in-cluster Service names (`http://catalog-service:8081`, ...).

```
backend/
  docker/Dockerfile                 image build outside the cluster, --build-arg SERVICE=...
  openshift/base/<service>/         ImageStream, BuildConfig (S2I), ConfigMap, Deployment, Service (+ Route for the gateway)
  openshift/base/secret.example.yaml  template for the saas-exam-mysql login (never applied)
  openshift/overlays/sandbox/       Developer Sandbox: current project, one gateway copy
scripts/
  deploy-backend.sh                 checks the MySQL secret, applies the overlay, builds all four services, rolls out
  remove-monolith.sh                removes the old single exam-backend deployment, after asking
```

### Before the first deploy

1. **Network**: the MySQL server must accept connections on 3306 from the cluster: `bind-address = 0.0.0.0`, the
   firewall allowing the cluster's egress IPs, and the MySQL login allowed from them. Find the egress IP with
   `oc run ip --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi-minimal -- curl -s https://checkip.amazonaws.com`.
   The Developer Sandbox uses more than one egress IP and they can change.
2. **Login**: store the MySQL login once (never in git):
   ```bash
   oc create secret generic saas-exam-mysql \
     --from-literal=SPRING_DATASOURCE_USERNAME=<user> --from-literal=SPRING_DATASOURCE_PASSWORD=<password>
   ```
3. **Schema**: `etfdb_dev` must already have `org_info`, `class_info`, `subject_info`, `chapter_info`,
   `question_info_v_two`, `answer_info_v_two` and `exam_info` (the layout of the legacy `m2its` dump).

### Deploy

Log in with the token from the web console (your name → **Copy login command**), then:

```bash
./scripts/deploy-backend.sh
```

This deploys into the current project (set `NAMESPACE` for another existing one), applies
`backend/openshift/overlays/sandbox`, builds all four images from the backend repo's `main` branch in parallel and
waits for every rollout. It prints the public API URL, e.g. `https://<route-host>/api/orgs`.

Redeploy one service after pushing backend changes with `oc start-build <service> --follow`.
To build a different branch, change `spec.source.git.ref` in `backend/openshift/base/<service>/buildconfig.yaml`.

The Developer Sandbox scales deployments to zero after 12 hours; bring them back with
`oc scale deployment -l app.kubernetes.io/part-of=saas-exam-platform --replicas=1`.

If the old single-backend deployment (`exam-backend`) is still running in the project, remove it once the
microservices are up with `./scripts/remove-monolith.sh`. It deletes that deployment's data volume.

Projects that ran the earlier H2 setup still have its volumes and secrets; remove them with
`oc delete pvc catalog-service-data question-service-data exam-service-data` and
`oc delete secret catalog-service-db question-service-db exam-service-db`.

### How it is configured

- **Builds**: each BuildConfig runs the Red Hat OpenJDK 17 S2I builder on the multi-module repo with
  `-pl <service> -am`, so it builds only that service and `common-lib`; `MAVEN_S2I_ARTIFACT_DIRS` points the builder
  at that module's `target/` to pick up the jar.
- **Database**: each data service's ConfigMap sets `DB_URL` to `etfdb_dev` and only connects: nothing is ever created
  in the database (`createDatabaseIfNotExist=false`, `SPRING_FLYWAY_ENABLED=false`, Hibernate `ddl-auto=validate`,
  which stops the service at startup if a table does not match the code). TLS is required (`sslMode=REQUIRED`).
- **Secrets**: `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD` come from the `saas-exam-mysql` Secret,
  shared by the three data services (see `base/secret.example.yaml`).
- **Health**: probes use Spring Boot Actuator's `/actuator/health/liveness` and `/readiness`.
- **Scaling**: the services are stateless (the data is in MySQL), so they roll without downtime and can run more copies.
  Each Deployment keeps 2 old ReplicaSets; the Developer Sandbox allows 30 per project.
- **TLS**: the gateway Route uses edge termination on the cluster's default certificate and redirects HTTP to
  HTTPS. `/internal/**` endpoints are not routed by the gateway, so they stay inside the cluster.

### Building the images outside OpenShift

From a checkout of the backend repo, once per service:

```bash
docker build -f ../saas-exam-platform-deployment/backend/docker/Dockerfile \
  --build-arg SERVICE=catalog-service -t catalog-service .
```
