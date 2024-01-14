.PHONY: feature bugfix push build release patch minor major playground development staging qa production

# List of projects (you need to change these)
PROJECTS := gateway data measurement components
REGISTRY := <your registry domain>

# Function to create a branch
define create_branch
	cd $(1) && \
	git checkout -b $(2) && \
	git push -u origin $(2) && \
	cd ..
endef

# Function to get the latest tag and increment the version
get_next_version = $(shell \
	LATEST_TAG=$$(cd $(1) && git tag --sort=-v:refname | grep '^v' | head -n 1); \
	if [ -z "$$LATEST_TAG" ]; then \
		echo "v1.0.0"; \
	else \
		MAJOR=$$(echo $$LATEST_TAG | cut -d. -f1 | cut -dv -f2); \
		MINOR=$$(echo $$LATEST_TAG | cut -d. -f2); \
		PATCH=$$(echo $$LATEST_TAG | cut -d. -f3); \
		if [ "$(2)" = "major" ]; then \
			MAJOR=$$((MAJOR + 1)); MINOR=0; PATCH=0; \
		elif [ "$(2)" = "minor" ]; then \
			MINOR=$$((MINOR + 1)); PATCH=0; \
		else \
			PATCH=$$((PATCH + 1)); \
		fi; \
		echo "v$$MAJOR.$$MINOR.$$PATCH"; \
	fi)

# Function to push changes in a project and tag it
define release_project
	$(eval NEW_TAG := $(call get_next_version,$(1),$(2)))
	cd $(1) && \
	git add . && \
	git commit -m "release $(NEW_TAG)" || true && \
	git tag $(NEW_TAG) && \
	git push origin master && \
	git push origin $(NEW_TAG) && \
	cd ..
endef

# Function to build Docker image for a project
define build_project
	docker build -t $(REGISTRY)/$(1):$(2) $(1)
	docker push $(REGISTRY)/$(1):$(2)
endef

# Function to update Kubernetes manifests
define update_manifests
	$(eval NEW_TAG := $(call get_next_version,$(1),patch))
	sed -i 's/namespace: .*/namespace: $(2)/' $(1)/.kube/deployment.yml
	sed -i 's/namespace: .*/namespace: $(2)/' $(1)/.kube/service.yml
	sed -i 's|$(REGISTRY)/$(1):.*|$(REGISTRY)/$(1)-service:$(NEW_TAG)|' $(1)/.kube/deployment.yml
	kubectl apply -f $(1)/.kube/
endef

# Targets to create feature and bugfix branches
feature bugfix:
	@$(foreach project,$(PROJECTS),$(call create_branch,$(project),$(1)/$(2)))

# Target to release new version for all projects
release: patch minor major

# Targets to increment version parts and release
patch minor major:
	@$(foreach project,$(PROJECTS),$(call release_project,$(project),$@))
	@$(foreach project,$(PROJECTS),$(call build_project,$(project),$(call get_next_version,$(project),$@)))

# Targets for different environments
playground development staging qa production:
	@$(foreach project,$(PROJECTS),$(call update_manifests,$(project),$@))

