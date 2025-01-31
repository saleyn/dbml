all: compile

compile: deps
	mix $@

deps:
	mix deps.get

test:
	mix test

run:
	iex -S mix

.PHONY: test
