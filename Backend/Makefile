# Stash backend — common tasks (PRD §16).
# Run from the Backend/ directory.

# The app service name in docker-compose.yml.
SERVICE := app

.DEFAULT_GOAL := help
.PHONY: help build build-up test up down logs migrate

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build the release binary locally
	swift build -c release

test: ## Run the test suite
	swift test

build-up: ## Build the release in the container (docker compose up -d --build)
	docker compose down
	docker compose up -d --build

up: ## Start the stack in the background (docker compose up -d)
	docker compose up -d

down: ## Stop and remove the stack (docker compose down)
	docker compose down

logs: ## Tail the app container logs
	docker compose logs -f $(SERVICE)

migrate: ## Run Fluent migrations inside the running app container
	docker compose exec $(SERVICE) ./App migrate --yes --env production
