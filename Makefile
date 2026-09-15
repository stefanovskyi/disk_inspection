.PHONY: build test benchmark benchmark-parallelism benchmark-full benchmark-trace benchmark-compare app dmg verify-dmg run clean

build:
	swift build

test:
	./Scripts/run_self_tests.sh
	./Scripts/test_signing_identity.sh
	./Scripts/test_dmg_packaging.sh
	./Scripts/test_benchmark_comparison.sh

benchmark:
	./Scripts/run_benchmarks.sh

benchmark-parallelism:
	./Scripts/run_parallelism_benchmarks.sh

benchmark-full:
	SPACELENS_BENCHMARK_FIXTURES=full-disk ./Scripts/run_benchmarks.sh

benchmark-trace:
	SPACELENS_BENCHMARK_CAPTURE_TRACE=1 ./Scripts/run_benchmarks.sh

benchmark-compare:
	@test -n "$(BASELINE)" -a -n "$(CANDIDATE)" || (echo "Usage: make benchmark-compare BASELINE=baseline.json CANDIDATE=candidate.json" >&2; exit 2)
	./Scripts/compare_benchmarks.sh "$(BASELINE)" "$(CANDIDATE)"

app:
	./Scripts/package_app.sh

dmg: app
	./Scripts/package_dmg.sh

verify-dmg:
	./Scripts/verify_dmg.sh dist/SpaceLens.dmg

run:
	swift run SpaceLens

clean:
	swift package clean
	rm -rf dist
