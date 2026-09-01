.PHONY: build test app run clean

build:
	swift build

test:
	./Scripts/run_self_tests.sh
	./Scripts/test_signing_identity.sh

app:
	./Scripts/package_app.sh

run:
	swift run SpaceLens

clean:
	swift package clean
	rm -rf dist
