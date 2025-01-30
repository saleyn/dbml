all: compile

compile: deps
	mix $@

deps:
	mix deps.get