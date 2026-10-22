GO ?= go
HELM ?= helm
KUBECTL ?= kubectl
CONTAINER_ENGINE ?= podman
GOLANGCI_LINT_VERSION ?= v2.15.0
GOLANGCI_LINT ?= go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)
MODULE_DIR := filesystem
IMAGE_REGISTRY ?= ghcr.io/llm-d-incubation
IMAGE_NAME ?= kv-cache-evictor
FILESYSTEM_BINARY_NAME ?= pvc-evictor
IMAGE_TAG ?= latest
IMAGE := $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

.DEFAULT_GOAL := help
.PHONY: help test lint build image fmt fmt-check chart-lint chart-render kustomize-render verify

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F ':.*?## ' '{printf "  %-12s %s\n", $$1, $$2}'

test: ## Run Go tests
	$(GO) test -C $(MODULE_DIR) ./...

lint: ## Run golangci-lint
	cd $(MODULE_DIR) && $(GOLANGCI_LINT) run ./...

build: ## Build the evictor binary
	$(GO) build -C $(MODULE_DIR) -o bin/$(FILESYSTEM_BINARY_NAME) ./cmd/pvc-evictor

image: ## Build the container image
	cd $(MODULE_DIR) && $(CONTAINER_ENGINE) build -t $(IMAGE) .

fmt: ## Format Go files
	cd $(MODULE_DIR) && gofmt -w cmd internal

fmt-check: ## Check Go formatting
	cd $(MODULE_DIR) && test -z "$$(gofmt -l cmd internal)"

chart-lint: ## Lint the Helm chart
	$(HELM) lint $(MODULE_DIR)/deploy/helm

chart-render: ## Render the Helm chart in both modes
	$(HELM) template kv-cache-evictor $(MODULE_DIR)/deploy/helm \
		--namespace llm-d-cache --set-string events.endpoint=tcp://*:5570 \
		--set events.service.enabled=true >/dev/null
	$(HELM) template kv-cache-evictor $(MODULE_DIR)/deploy/helm \
		--namespace llm-d-cache --set mode=sidecar \
		--set sidecar.volumeName=cache-storage >/dev/null

kustomize-render: ## Render the standalone Kustomize manifests
	$(KUBECTL) kustomize $(MODULE_DIR)/deploy/kustomize/standalone >/dev/null

verify: fmt-check test lint build chart-lint chart-render kustomize-render ## Run formatting, tests, lint, build, and deployment checks
