# Container image for saas-exam-platform-backend, for building outside OpenShift
# (for example to push to Amazon ECR). In-cluster builds use the S2I BuildConfig instead.
#
# Build from a checkout of the backend repo:
#   docker build -f ../saas-exam-platform-deployment/backend/docker/Dockerfile -t exam-backend .

FROM registry.access.redhat.com/ubi9/openjdk-17:1.21 AS build
WORKDIR /home/default/app
COPY --chown=185:0 pom.xml .
RUN mvn -B -q dependency:go-offline
COPY --chown=185:0 src ./src
RUN mvn -B package -DskipTests && cp target/*.jar /tmp/app.jar

FROM registry.access.redhat.com/ubi9/openjdk-17-runtime:1.21
# run-java.sh in this image starts the single jar found in /deployments and sizes
# the heap from the container memory limit.
COPY --from=build --chown=185:0 /tmp/app.jar /deployments/app.jar
ENV SPRING_DATASOURCE_URL="jdbc:h2:file:/data/examdb;MODE=MySQL;DATABASE_TO_LOWER=TRUE;CASE_INSENSITIVE_IDENTIFIERS=TRUE"
VOLUME /data
EXPOSE 8080
USER 185
