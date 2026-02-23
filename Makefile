IMAGE_NAME      ?= neo-planka
IMAGE_TAG       ?= latest
REGISTRY        ?=
PLATFORM        ?= linux/arm64

FULL_IMAGE  = $(if $(REGISTRY),$(REGISTRY)/,)$(IMAGE_NAME):$(IMAGE_TAG)
BUILDER     = neo-planka-multiarch

# ---------------------------------------------------------------------------
# Development (runs natively on your PC)
# ---------------------------------------------------------------------------

.PHONY: dev
dev: ## Start dev environment (server + client + postgres)
	docker compose --project-directory . -f docker/docker-compose-dev.yml up --build -d

.PHONY: dev-down
dev-down: ## Stop dev environment
	docker compose --project-directory . -f docker/docker-compose-dev.yml down

.PHONY: dev-clean
dev-clean: ## Stop dev environment and remove volumes
	docker compose --project-directory . -f docker/docker-compose-dev.yml down -v

# ---------------------------------------------------------------------------
# ARM64 build (cross-compile for Raspberry Pi)
# ---------------------------------------------------------------------------

.PHONY: builder
builder: ## Create buildx builder for multi-arch builds
	@docker buildx inspect $(BUILDER) >/dev/null 2>&1 || \
		docker buildx create --name $(BUILDER) --driver docker-container --bootstrap
	@docker buildx use $(BUILDER)

.PHONY: build-arm64
build-arm64: builder ## Build ARM64 image and export as tarball
	docker buildx build \
		--platform linux/arm64 \
		--file docker/Dockerfile \
		--tag $(FULL_IMAGE) \
		--output type=docker,dest=neo-planka-arm64.tar \
		.
	@echo ""
	@echo "Image saved to neo-planka-arm64.tar"
	@echo "Transfer to Pi:  scp neo-planka-arm64.tar pi@<pi-ip>:~/"
	@echo "Load on Pi:      docker load -i neo-planka-arm64.tar"

.PHONY: build-arm64-push
build-arm64-push: builder ## Build ARM64 image and push to registry
	docker buildx build \
		--platform linux/arm64 \
		--file docker/Dockerfile \
		--tag $(FULL_IMAGE) \
		--push \
		.

.PHONY: build-native
build-native: ## Build image for current architecture
	docker build -f docker/Dockerfile -t $(FULL_IMAGE) .

.PHONY: build-multi
build-multi: builder ## Build for both amd64 and arm64 (push to registry)
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--file docker/Dockerfile \
		--tag $(FULL_IMAGE) \
		--push \
		.

# ---------------------------------------------------------------------------
# Deploy helpers
# ---------------------------------------------------------------------------

.PHONY: deploy-tar
deploy-tar: build-arm64 ## Build ARM64 image + compose into a deployable bundle
	@rm -rf .deploy-stage
	@mkdir -p .deploy-stage
	@cp neo-planka-arm64.tar \
		docker/docker-compose-pi.yml \
		scripts/docker-backup.sh \
		scripts/docker-restore.sh \
		.env.example \
		.deploy-stage/
	@cp docker/Makefile.pi .deploy-stage/Makefile
	tar -C .deploy-stage -cf "$(CURDIR)/neo-planka-deploy.tar" .
	@rm -rf .deploy-stage
	@echo ""
	@echo "Deploy bundle: neo-planka-deploy.tar"
	@echo "On the Pi:"
	@echo "  tar xf neo-planka-deploy.tar"
	@echo "  cp .env.example .env  # then edit .env"
	@echo "  make deploy"

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
