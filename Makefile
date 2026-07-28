.PHONY: all build deps test package image submodule-check clean

all: build

build:
	tools/build.sh

deps:
	tools/check_deps.py

test: build
	tools/test.sh

package: build
	tools/package.sh

image: build
	tools/image.sh

submodule-check:
	tools/check_deps.py --check-clean

clean:
	rm -rf build distr
