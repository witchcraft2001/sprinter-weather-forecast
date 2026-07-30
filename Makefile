.PHONY: all build weather weatherc console debug deps test test-z80 package image debug-image submodule-check clean

all: build

build: weather weatherc

weather:
	tools/build.sh weather

weatherc:
	tools/build.sh weatherc

console: weatherc

debug:
	WEATHER_DEBUG_RAW=1 tools/build.sh

deps:
	tools/check_deps.py

test: build
	tools/test.sh

test-z80:
	tools/run_z80_tests.sh

package: build
	tools/package.sh

image: build
	tools/image.sh

debug-image:
	WEATHER_DEBUG_RAW=1 tools/build.sh
	DIST_NAME=weather-debug WEATHER_DEBUG_CFG=1 tools/image.sh
	tools/build.sh

submodule-check:
	tools/check_deps.py --check-clean

clean:
	rm -rf build distr
