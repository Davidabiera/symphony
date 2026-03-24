.PHONY: help all setup deps build fmt fmt-check lint test coverage ci dialyzer e2e eval-validate eval-smoke

MIX ?= mix
EVAL_SMOKE_DATASET ?= test/fixtures/eval/dataset_smoke.json
EVAL_SMOKE_RUBRIC ?= test/fixtures/eval/rubric_smoke.json
EVAL_SMOKE_OUTPUT ?= tmp/evals/T-EVAL-001
EVAL_SMOKE_ID ?= T-EVAL-001
EVAL_REL_GATE_ID ?= RG-P0-001

help:
	@echo "Targets: setup, deps, build, fmt, fmt-check, lint, test, coverage, dialyzer, e2e, eval-validate, eval-smoke, ci"

setup:
	$(MIX) setup

deps:
	$(MIX) deps.get

build:
	$(MIX) build

fmt:
	$(MIX) format

fmt-check:
	$(MIX) format --check-formatted

lint:
	$(MIX) lint

coverage:
	$(MIX) test --cover

test:
	$(MIX) test

dialyzer:
	$(MIX) deps.get
	$(MIX) dialyzer --format short

e2e:
	SYMPHONY_RUN_LIVE_E2E=1 $(MIX) test test/symphony_elixir/live_e2e_test.exs

eval-validate:
	$(MIX) symphony.eval.validate --dataset "$(EVAL_SMOKE_DATASET)" --rubric "$(EVAL_SMOKE_RUBRIC)"

eval-smoke:
	$(MIX) symphony.eval.run --dataset "$(EVAL_SMOKE_DATASET)" --rubric "$(EVAL_SMOKE_RUBRIC)" --output-dir "$(EVAL_SMOKE_OUTPUT)" --eval-id "$(EVAL_SMOKE_ID)" --rel-gate-id "$(EVAL_REL_GATE_ID)" --smoke

ci:
	$(MAKE) setup
	$(MAKE) build
	$(MAKE) fmt-check
	$(MAKE) lint
	$(MAKE) coverage
	$(MAKE) eval-smoke
	$(MAKE) dialyzer

all: ci
