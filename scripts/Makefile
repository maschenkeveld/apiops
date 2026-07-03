# Local APIOps runner — wraps the scripts in a pinned Docker image so demos are
# reproducible on any host. Run from this directory: `make demo`, `make build`, etc.
#
# Override defaults inline, e.g.:
#   make demo CP=apiops-development APPS="alice bob"
#   make build APP=alice

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
IMAGE     ?= apiops-local
TAG       ?= latest
CP        ?= apiops-development
APP       ?= alice
APPS      ?= alice
ENV_FILE  := $(REPO_ROOT)/scripts/.env

# --env-file is added only if scripts/.env exists (build/lint/validate need no secrets).
DOCKER_RUN = docker run --rm -it \
  $(if $(wildcard $(ENV_FILE)),--env-file $(ENV_FILE),) \
  -v $(REPO_ROOT):/work -w /work $(IMAGE):$(TAG)

.PHONY: image demo dry-run validate build lint lint-global docs deploy deploy-global backup verify publish shell help

help:
	@echo "Targets: image | demo | dry-run | validate | build | lint | lint-global | docs |"
	@echo "         deploy | deploy-global | backup | verify | publish | shell"
	@echo "Vars:    CP=$(CP)  APP=$(APP)  APPS='$(APPS)'  IMAGE=$(IMAGE):$(TAG)"

image: ## Build the pinned tooling image (run once)
	docker build -t $(IMAGE):$(TAG) $(REPO_ROOT)/scripts

demo: ## Full flow for APPS: validate→build→lint→docs→deploy→verify→publish
	$(DOCKER_RUN) scripts/demo.sh $(CP) $(APPS)

dry-run: ## Same as demo but diff-only, no writes, no publish
	$(DOCKER_RUN) bash -c "DRY_RUN=1 scripts/demo.sh $(CP) $(APPS)"

validate: ## OpenAPI validate one APP (spectral + changelog/semver/breaking vs main)
	$(DOCKER_RUN) scripts/validate.sh $(APP)

build: ## Build the deck config for one APP
	$(DOCKER_RUN) scripts/build.sh $(APP)

lint: ## deck file lint the built config for one APP
	$(DOCKER_RUN) scripts/lint.sh $(APP)

lint-global: ## deck file lint the global deck files
	$(DOCKER_RUN) scripts/lint-global.sh

docs: ## build HTML docs for one APP
	$(DOCKER_RUN) scripts/docs.sh $(APP)

deploy: ## diff+sync one APP to CP (DRY_RUN=1 for diff only)
	$(DOCKER_RUN) bash -c "DRY_RUN=$${DRY_RUN:-0} scripts/deploy.sh $(APP) $(CP)"

deploy-global: ## diff+sync global components to CP (DRY_RUN=1 for diff only)
	$(DOCKER_RUN) bash -c "DRY_RUN=$${DRY_RUN:-0} scripts/deploy-global.sh $(CP)"

backup: ## dump CP state to backups/
	$(DOCKER_RUN) scripts/backup.sh $(CP) $(CP)

verify: ## ping CP
	$(DOCKER_RUN) scripts/verify.sh $(CP)

publish: ## publish one APP to the Dev Portal
	$(DOCKER_RUN) scripts/publish.sh $(APP) $(CP)

shell: ## open a shell in the tooling image
	$(DOCKER_RUN) bash
