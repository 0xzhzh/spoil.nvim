set shell := ["bash", "-c"]

nvim := "nvim"
stylua := "stylua"
luacheck := "luacheck"

mini := "deps/mini.nvim"
mini_url := "https://github.com/nvim-mini/mini.nvim"
mini_ref := "v0.18.0"

# List available recipes
[private]
default:
    @just --list

# Download test-only dependencies at the pinned revision
deps:
    @mkdir -p deps
    @test -d {{mini}} || git clone --filter=blob:none {{mini_url}} {{mini}}
    @git -C {{mini}} rev-parse --verify --quiet {{mini_ref}} >/dev/null || git -C {{mini}} fetch --quiet --tags origin
    @git -C {{mini}} checkout --quiet {{mini_ref}}

# Format Lua sources
fmt:
    {{stylua}} lua tests scripts

# Check Lua formatting
fmt-check:
    {{stylua}} --check lua tests scripts

# Lint Lua sources
lint:
    {{luacheck}} --globals vim --globals MiniTest --no-unused-args lua tests scripts

# Run formatting, lint, and offline tests
check: fmt-check lint test

# Run offline tests (no Spotify credentials or network)
test: deps
    {{nvim}} --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run a single test file
test-file file: deps
    {{nvim}} --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run_file('{{file}}')"

# Run the case(s) covering FILE:LINE
test-at file line: deps
    {{nvim}} --headless --noplugin -u scripts/minimal_init.lua \
        -c "lua MiniTest.run_at_location({ file = '{{file}}', line = {{line}} })"

# Run read-only live tests
test-live: deps
    SPOIL_TEST_LIVE=1 {{nvim}} --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run live mutation tests against the dedicated test account
test-mutations: deps
    SPOIL_TEST_LIVE=1 SPOIL_TEST_MUTATIONS=1 \
        {{nvim}} --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

# Show :checkhealth spoil for the current setup
health:
    {{nvim}} --headless --clean --cmd "set rtp+=." -c "checkhealth spoil" -c "%print" -c "qa"

# Remove downloaded test dependencies
clean:
    rm -rf deps
