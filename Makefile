.PHONY: project open verify clean reset

project:
	@command -v xcodegen >/dev/null || (echo "Install XcodeGen first: brew install xcodegen" && exit 1)
	xcodegen generate
	@python3 Scripts/patch-xcodeproj.py

open: project
	open Luma.xcodeproj

verify:
	./Scripts/verify.sh

clean:
	rm -rf Luma.xcodeproj DerivedData .build

# Fixes Xcode GUI "Missing package product" errors: the GUI caches the
# SwiftPM package graph in DerivedData, which goes stale when packages
# change (e.g. the remote -> vendored local MartinOMEMO switch). Quit Xcode
# first, run this, then reopen Luma.xcodeproj and let it re-resolve.
reset:
	rm -rf ~/Library/Developer/Xcode/DerivedData/Luma-*
	rm -f Luma.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
	@echo "Xcode package state cleared. Reopen Luma.xcodeproj to re-resolve packages."

