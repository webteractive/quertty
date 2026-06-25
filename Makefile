# quertty Makefile
#
# Mirrors the Supacode build-ghostty-xcframework approach.
# Requires zig 0.15.2 (pinned via .mise.toml / mise).

ZIG ?= $(shell /opt/homebrew/bin/mise exec -- which zig 2>/dev/null || which zig)
GHOSTTY_DIR = vendor/ghostty
XCFRAMEWORK_OUT = $(GHOSTTY_DIR)/macos/GhosttyKit.xcframework

.PHONY: build-ghostty-xcframework clean-ghostty-xcframework

## Build GhosttyKit.xcframework (full libghostty with renderer) from source.
## Output: vendor/ghostty/macos/GhosttyKit.xcframework
build-ghostty-xcframework:
	@echo "Building GhosttyKit.xcframework from $(GHOSTTY_DIR) ..."
	cd $(GHOSTTY_DIR) && \
	    /opt/homebrew/bin/mise exec -- zig build \
	        -Demit-xcframework \
	        -Doptimize=ReleaseFast \
	        --prefix zig-out
	@echo "xcframework output: $(XCFRAMEWORK_OUT)"

## Remove the built xcframework (zig-out and zig-cache stay in vendor/ghostty).
clean-ghostty-xcframework:
	rm -rf $(XCFRAMEWORK_OUT)
