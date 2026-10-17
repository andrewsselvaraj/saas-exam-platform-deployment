# saas-exam-platform-deployment
OCP/Kubernetes deployment configuration for SaaS exam platform (backend, frontend, databases)

## Backend on OpenShift

Deploys the [saas-exam-platform-backend](https://github.com/andrewsselvaraj/saas-exam-platform-backend)
microservices (Spring Boot 3.5, Java 17) to OpenShift (tested on the Red Hat Developer Sandbox):

| Service            | Port | Database                                   | Exposed                 |
|--------------------|------|--------------------------------------------|-------------------------|
| `api-gateway`      | 8080 | none                                       | public HTTPS Route      |
| `catalog-service`  | 8081 | H2 `catalogdb` on a volume, or MySQL `m2its`  | inside the cluster only |
| `question-service` | 8082 | H2 `questiondb` on a volume, or MySQL `m2its` | inside the cluster only |
| `exam-service`     | 8083 | H2 `examdb` on a volume, or MySQL `m2its`     | inside the cluster only |

Clients only talk to the gateway, which routes `/api/**` to the owning service. The services call each other
through their in-cluster Service names (`http://catalog-service:8081`, ...).

```
backend/
  docker/Dockerfile                 image build outside the cluster, --build-arg SERVICE=...
  openshift/base/<service>/         ImageStream, BuildConfig (S2I), ConfigMap, Deployment, Service,
                                    plus PVC + secret.example.yaml (data services) or Route (gateway)
  openshift/overlays/sandbox/       current project, default storage class, 1Gi volumes, 1 gateway (H2)
  openshift/overlays/mysql/         sandbox + data services on the existing m2its MySQL server, no volumes
scripts/
  deploy-backend.sh                 creates the DB secrets, applies an overlay, builds all four services, rolls out
  remove-monolith.sh                removes the old single exam-backend deployment, after asking
```

### Deploy

Log in with the token from the web console (your name → **Copy login command**), then:

```bash
./scripts/deploy-backend.sh
```

This deploys into the current project (set `NAMESPACE` for another existing one), generates a `<service>-db` secret
for each data service, applies `backend/openshift/overlays/sandbox`, builds all four images from the backend repo's
`main` branch in parallel and waits for every rollout. It prints the public API URL, e.g. `https://<route-host>/api/orgs`.

Redeploy one service after pushing backend changes with `oc start-build <service> --follow`.
To build a different branch, change `spec.source.git.ref` in `backend/openshift/base/<service>/buildconfig.yaml`.

The Developer Sandbox scales deployments to zero after 12 hours; bring them back with
`oc scale deployment -l app.kubernetes.io/part-of=saas-exam-platform --replicas=1`.

If the old single-backend deployment (`exam-backend`) is still running in the project, remove it once the
microservices are up with `./scripts/remove-monolith.sh`. It deletes that deployment's data volume.

### Using the existing m2its MySQL database

`overlays/mysql` points the three data services at the existing `m2its` database on `63.142.240.31` instead of H2
volumes. It only connects: nothing is created in that database (`createDatabaseIfNotExist=false`, Flyway off,
Hibernate `ddl-auto=validate`). It needs the backend's MySQL support (driver, `*_v_two` table names).

1. On the MySQL server: `bind-address = 0.0.0.0`, allow TCP 3306 from the cluster's egress IP only, and make sure the
   app's MySQL login is allowed from that IP (`'<user>'@'<egress-ip>'`, or a `'<user>'@'%'` login with `REQUIRE SSL`).
   Find the egress IP with `oc run ip --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi-minimal -- curl -s https://checkip.amazonaws.com`.
2. Put that login in each service's secret:
   `oc set data secret/<service>-db SPRING_DATASOURCE_USERNAME=<user> SPRING_DATASOURCE_PASSWORD=<password>`
   (for `catalog-service`, `question-service` and `exam-service`).
3. `OVERLAY=mysql ./scripts/deploy-backend.sh`

Switching from H2 leaves the old `<service>-data` volumes in place; delete them with
`oc delete pvc catalog-service-data question-service-data exam-service-data` once you no longer need the H2 data.
The Developer Sandbox's egress IP is not guaranteed to stay the same; if the connection stops, check it again.

### How it is configured

- **Builds**: each BuildConfig runs the Red Hat OpenJDK 17 S2I builder on the multi-module repo with
  `-pl <service> -am`, so it builds only that service and `common-lib`; `MAVEN_S2I_ARTIFACT_DIRS` points the builder
  at that module's `target/` to pick up the jar.
- **Config**: each service's `application.yml` is overridden by its ConfigMap: `PORT`, `DB_URL` (the H2 file
  moves to `/data` on the service's volume, or the MySQL URL), the other services' URLs, and the H2 web console off.
- **Secrets**: `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD` come from each service's `<service>-db`
  Secret, which is never committed (see `secret.example.yaml`). With H2, the database is created with these
  credentials on first start, so don't change them afterwards.
- **Health**: probes use Spring Boot Actuator's `/actuator/health/liveness` and `/readiness`. The data services
  allow 5 minutes to start because the first start on H2 runs the Flyway seed.
- **Scaling**: H2 in file mode allows one process per database and the volumes are ReadWriteOnce, so with H2 the
  three data services run 1 replica each with the `Recreate` strategy. With MySQL they use rolling updates.
- **TLS**: the gateway Route uses edge termination on the cluster's default certificate and redirects HTTP to
  HTTPS. `/internal/**` endpoints are not routed by the gateway, so they stay inside the cluster.

### Building the images outside OpenShift

From a checkout of the backend repo, once per service:

```bash
docker build -f ../saas-exam-platform-deployment/backend/docker/Dockerfile \
  --build-arg SERVICE=catalog-service -t catalog-service .
```
