.PHONY: help compile test cover regenerate clean publish escript bump-version retire-version
APP=$(shell sed -nE '/app:/{s/.*app:\s*:([a-z_]+).*/\1/p; q}' mix.exs)

all: compile escript

compile: remove-crushdump
	mix compile --warnings-as-errors

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  compile              Compile the project"
	@echo "  test                 Run the test suite"
	@echo "  cover                Run tests with coverage (fails if below 80%)"
	@echo "  clean                Remove build artefacts and dependencies"
	@echo "  escript              Build the dbml standalone executable"
	@echo "  publish              Publish to Hex (pass replace=1 to replace an existing version)"
	@echo "  bump-version         Bump patch version"
	@echo "  retire-version       Retire a version on Hex (pass version=X.Y.Z)"
	@echo "  show-versions        Show active package versions on Hex"
	@echo "  help                 Show this help message"

test:
	mix test

remove-crushdump:
	@rm -f erl_crash.dump

cover:
	@mix test --cover | \
	awk '/Total/{ \
	  gsub(/[^0-9.]/,""); coverage=$$0 \
	} END { \
	  if (coverage < 80.0) { \
	    printf "Coverage %.2f%% is below threshold 80.0%%\n", coverage; exit 1 \
	  } else { \
	    printf "==> Total coverage: %.2f%%\n", coverage \
	  } \
	}'

escript:
	mix escript.build

clean:
	mix clean
	rm -rf _build deps .cover dbml erl_crash.dump

doc docs:
	mix docs

publish:
	mix hex.publish$(if $(replace), --replace)

bump-version: AMEND=$(if $(amend), --amend)
bump-version:
	@CURRENT=$$(grep -m1 'version:' mix.exs | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/'); \
	MAJOR=$$(echo $$CURRENT | cut -d. -f1); \
	MINOR=$$(echo $$CURRENT | cut -d. -f2); \
	PATCH=$$(echo $$CURRENT | cut -d. -f3); \
	NEW=$$(echo "$${MAJOR}.$${MINOR}.$$((PATCH + 1))" | tr -d '\n'); \
	echo "Bumping version from $${CURRENT} to $${NEW}"; \
	sed -i "s/version:\([[:space:]]*\)\"$${CURRENT}\"/version:\1\"$${NEW}\"/" mix.exs; \
	echo "Changed: version: \"$${CURRENT}\" -> version: \"$${NEW}\""; \
	echo ""; \
	[ -z $(AMEND) ] && read -p "Commit this change ([Aa] - amend)? [Y/n/a] " -n 1 -r || true; \
	echo ""; \
	if [ -n $(AMEND) ] || [[ $${REPLY} =~ ^[Aa]$$ ]]; then AMEND=" --amend"; fi; \
	if [[ $${REPLY} =~ ^[YyAa]$$ ]] || [[ -z $${REPLY} ]]; then \
		git commit$${AMEND} -am "Bump version to $${NEW}"; \
	else \
		echo "Aborted. Reverting mix.exs..."; \
		git checkout mix.exs; \
		exit 1; \
	fi

retire-version: VSN=$(shell mix hex.info $(APP) | grep "^Releases:" | sed 's/Releases: //; s/, /\n/g' | sed '/retired/d; /\.\.\./d' | sed -n '$$p')
retire-version:
	@echo "VSN: $(VSN)"
	@if [ -z "$(VSN)" ]; then \
		echo "$(APP): no stale versions were found on Hex"; \
	else \
		echo "Retiring version $(VSN) of $(APP) on Hex..."; \
		mix hex.retire $(APP) $(VSN) deprecated --message "Deprecated"; \
	fi

show-versions:
	@mix hex.info $(APP) | grep "^Releases:" | sed 's/Releases: //; s/, /\n/g' | sed '/retired/d; /\.\.\./d'

