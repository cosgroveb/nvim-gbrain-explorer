.PHONY: check format format-fix install-deps lint test

install-deps:
	cargo install stylua
	@if command -v brew >/dev/null 2>&1; then \
		brew install luacheck; \
	elif command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update && sudo apt-get install -y lua-check; \
	else \
		echo "Install luacheck from your package manager."; \
		exit 1; \
	fi

format:
	stylua lua/ plugin/ test/ --check

format-fix:
	stylua lua/ plugin/ test/

lint:
	luacheck lua/ plugin/ test/ --config .luacheckrc

test:
	nvim --headless --noplugin -u NONE -c "set runtimepath+=." -c "lua dofile('test/run.lua')"

check: format lint test
