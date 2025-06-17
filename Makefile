# -------------------------------
# Configurable Variables
# -------------------------------

MIGRATION_DIR      := migrations
AWS_ACCOUNT_ID     := 021891619529
AWS_DEFAULT_REGION := ap-south-1
AWS_ECR_DOMAIN     := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_DEFAULT_REGION).amazonaws.com
PLATFORM           := linux/amd64

# fallback GIT_SHA if git command fails
GIT_SHA ?= $(shell git rev-parse HEAD 2>NUL || echo "latest")

BUILD_IMAGE        := $(AWS_ECR_DOMAIN)/fem-fd-service
BUILD_TAG          ?= latest

# Warn if no DBSTRING set when needed
ifeq ($(filter-out build-image%,$(MAKECMDGOALS)),)
else
ifndef GOOSE_DBSTRING
$(warning ⚠️  GOOSE_DBSTRING is not set — migration commands may fail!)
endif
endif

# Handle DOCKERIZE_HOST extraction safely (without 'cut')
ifdef GOOSE_DBSTRING
DOCKERIZE_HOST := $(word 2, $(subst @, ,$(GOOSE_DBSTRING)))
else
DOCKERIZE_HOST := postgresql://postgres.csjqnigawgqmmhwchejs:XVV5Uz!RjaP7Z6-@aws-0-ap-south-1.pooler.supabase.com:5432/postgres
endif

DOCKERIZE_URL := tcp://$(DOCKERIZE_HOST):5432

.DEFAULT_GOAL := build

# -------------------------------
# Build Commands
# -------------------------------

build:
	go build -o ./goals main.go

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

build-image-login:
	aws ecr get-login-password --region $(AWS_DEFAULT_REGION) | docker login --username AWS --password-stdin $(AWS_ECR_DOMAIN)

build-image-push: build-image-login
	docker image push $(BUILD_IMAGE):$(GIT_SHA)

build-image-promote: build-image-login
	@echo "Promoting $(GIT_SHA) to $(BUILD_TAG)"
	docker image tag $(BUILD_IMAGE):$(GIT_SHA) $(BUILD_IMAGE):$(BUILD_TAG)
	docker image push $(BUILD_IMAGE):$(BUILD_TAG)

build-image-pull: build-image-login
	docker image pull $(BUILD_IMAGE):$(GIT_SHA)


# -------------------------------
# Database Migrations via Dockerized Goose
# -------------------------------

build-image-migrate:
	docker container run --entrypoint "dockerize" --network "host" --rm $(BUILD_IMAGE):$(GIT_SHA) -timeout 30s -wait $(DOCKERIZE_URL)
	docker container run --entrypoint "sh" --network "host" --rm $(BUILD_IMAGE):$(GIT_SHA) -c "sleep 3"
	docker container run --entrypoint "goose" --env "GOOSE_DBSTRING=$(GOOSE_DBSTRING)" --env "GOOSE_DRIVER=$(GOOSE_DRIVER)" --network "host" --rm $(BUILD_IMAGE):$(GIT_SHA) -dir $(MIGRATION_DIR) status
	docker container run --entrypoint "goose" --env "GOOSE_DBSTRING=$(GOOSE_DBSTRING)" --env "GOOSE_DRIVER=$(GOOSE_DRIVER)" --network "host" --rm $(BUILD_IMAGE):$(GIT_SHA) -dir $(MIGRATION_DIR) validate
	docker container run --entrypoint "goose" --env "GOOSE_DBSTRING=$(GOOSE_DBSTRING)" --env "GOOSE_DRIVER=$(GOOSE_DRIVER)" --network "host" --rm $(BUILD_IMAGE):$(GIT_SHA) -dir $(MIGRATION_DIR) up

# -------------------------------
# Docker Compose Utilities
# ----------------------------

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