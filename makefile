# -------------------------------
# Configurable Variables
# -------------------------------

MIGRATION_DIR      := migrations
AWS_ACCOUNT_ID     := 021891619529
AWS_DEFAULT_REGION := ap-south-1
AWS_ECR_DOMAIN     := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_DEFAULT_REGION).amazonaws.com
GIT_SHA            := $(shell git rev-parse HEAD)
BUILD_IMAGE        := $(AWS_ECR_DOMAIN)/fem-fd-service
BUILD_TAG          := $(if $(BUILD_TAG),$(BUILD_TAG),latest)
PLATFORM           := linux/amd64

# Check if GOOSE_DBSTRING is set (for safety) unless only building images
ifeq ($(filter-out build-image%,$(MAKECMDGOALS)),)
else
ifndef GOOSE_DBSTRING
$(warning ⚠️  GOOSE_DBSTRING is not set — migration commands may fail!)
endif
endif

DOCKERIZE_HOST     := $(shell echo $(GOOSE_DBSTRING) | cut -d "@" -f 2 | cut -d ":" -f 1)
DOCKERIZE_URL      := tcp://$(if $(DOCKERIZE_HOST),$(DOCKERIZE_HOST):5432,localhost:5432)

.DEFAULT_GOAL := build


# -------------------------------
# Build Commands
# -------------------------------

# Build Go binary locally
build:
	go build -o ./goals main.go

# Build multi-stage Docker images (build stage + final image)
build-image:
	docker buildx build \
		--platform "$(PLATFORM)" \
		--tag "$(BUILD_IMAGE):$(GIT_SHA)-build" \
		--target "build" \
		.
	docker buildx build \
		--cache-from "$(BUILD_IMAGE):$(GIT_SHA)-build" \
		--platform "$(PLATFORM)" \
		--tag "$(BUILD_IMAGE):$(GIT_SHA)" \
		.

# Authenticate Docker to AWS ECR
build-image-login:
	aws ecr get-login-password --region $(AWS_DEFAULT_REGION) | docker login \
		--username AWS \
		--password-stdin \
		$(AWS_ECR_DOMAIN)

# Push Docker image to ECR
build-image-push: build-image-login
	docker image push $(BUILD_IMAGE):$(BUILD_TAG)

# Pull image from ECR (if needed)
build-image-pull: build-image-login
	docker image pull $(BUILD_IMAGE):$(GIT_SHA)

# Image Promotion (with login first)
build-image-promote: build-image-login
	docker image tag $(BUILD_IMAGE):$(GIT_SHA) $(BUILD_IMAGE):$(BUILD_TAG)
	docker image push $(BUILD_IMAGE):$(BUILD_TAG)


# -------------------------------
# Database Migrations via Dockerized Goose
# -------------------------------

build-image-migrate:
	docker container run \
		--entrypoint "dockerize" \
		--network "host" \
		--rm \
		$(BUILD_IMAGE):$(GIT_SHA) \
		-timeout 30s -wait $(DOCKERIZE_URL)
	docker container run \
		--entrypoint "goose" \
		--env "GOOSE_DBSTRING=$(GOOSE_DBSTRING)" \
		--env "GOOSE_DRIVER=$(GOOSE_DRIVER)" \
		--network "host" \
		--rm \
		$(BUILD_IMAGE):$(GIT_SHA) \
		-dir $(MIGRATION_DIR) status
	docker container run \
		--entrypoint "goose" \
		--env "GOOSE_DBSTRING=$(GOOSE_DBSTRING)" \
		--env "GOOSE_DRIVER=$(GOOSE_DRIVER)" \
		--network "host" \
		--rm \
		$(BUILD_IMAGE):$(GIT_SHA) \
		-dir $(MIGRATION_DIR) validate
	docker container run \
		--entrypoint "goose" \
		--env "GOOSE_DBSTRING=$(GOOSE_DBSTRING)" \
		--env "GOOSE_DRIVER=$(GOOSE_DRIVER)" \
		--network "host" \
		--rm \
		$(BUILD_IMAGE):$(GIT_SHA) \
		-dir $(MIGRATION_DIR) up


# -------------------------------
# Docker Compose Utilities
# -------------------------------

down:
	docker compose down --remove-orphans --volumes

up: down
	docker compose up --detach


# -------------------------------
# Local Migration Utilities
# -------------------------------

migrate:
	goose -dir "$(MIGRATION_DIR)" up

migrate-status:
	goose -dir "$(MIGRATION_DIR)" status

migrate-validate:
	goose -dir "$(MIGRATION_DIR)" validate


# -------------------------------
# Local Application Run
# -------------------------------

start: build
	./goals
