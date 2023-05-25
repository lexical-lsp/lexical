compile.all: compile.projects compile.umbrella

test.all: test.projects test.umbrella

test.umbrella:
	mix test

project_dirs = lexical lexical_plugin lexical_test

test.projects:
	cd projects
	$(foreach dir, $(project_dirs), cd projects/$(dir) && mix test && cd ../..;)

compile.umbrella: compile.projects
	mix deps.get
	mix compile --skip-umbrella-children

compile.projects:
	cd projects
	$(foreach dir, $(project_dirs), cd projects/$(dir) && mix deps.get && mix compile --warnings-as-errors && cd ../..;)
