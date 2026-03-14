FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder
WORKDIR /workspace

COPY pom.xml .
COPY src ./src

RUN mvn -q -DskipTests package

FROM eclipse-temurin:21-jdk-alpine AS jre-builder

# Build a minimized Java runtime with only modules commonly needed by Spring Boot web apps.
RUN $JAVA_HOME/bin/jlink \
	--add-modules java.base,java.desktop,java.instrument,java.logging,java.management,java.naming,java.net.http,java.security.jgss,java.sql,java.xml,jdk.crypto.ec,jdk.unsupported,jdk.zipfs \
	--strip-debug \
	--no-man-pages \
	--no-header-files \
	--compress=2 \
	--output /opt/jre

FROM alpine:3.21
WORKDIR /app

RUN apk add --no-cache libstdc++ ca-certificates && \
	addgroup -S spring && adduser -S spring -G spring

ENV JAVA_HOME=/opt/jre
ENV PATH="/opt/jre/bin:${PATH}"

COPY --from=jre-builder /opt/jre /opt/jre

COPY --from=builder /workspace/target/pipeline-pilot-0.0.1-SNAPSHOT.jar app.jar

RUN chown spring:spring /app/app.jar

USER spring

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
