.PHONY: build test benchmark benchmark-full benchmark-trace app run clean

build:
	swift build

test:
	./Scripts/run_self_tests.sh
	./Scripts/test_signing_identity.sh

benchmark:
	./Scripts/run_benchmarks.sh

benchmark-full:
	SPACELENS_BENCHMARK_FIXTURES=full-disk ./Scripts/run_benchmarks.sh

benchmark-trace:
	SPACELENS_BENCHMARK_CAPTURE_TRACE=1 ./Scripts/run_benchmarks.sh

app:
	./Scripts/package_app.sh

run:
	swift run SpaceLens

clean:
	swift package clean
	rm -rf dist
