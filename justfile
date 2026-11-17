set shell := ["bash", "-c"]

mini := "deps/mini.nvim"

# Download test-only dependencies
deps:
    @mkdir -p deps
    @test -d {{mini}} || git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim {{mini}}

# Run offline tests (no Spotify credentials or network)
test: deps
    nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run a single test file
test-file file: deps
    nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run_file('{{file}}')"

# Run read-only live tests
test-live: deps
    SPOIL_TEST_LIVE=1 nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run live mutation tests against the dedicated test account
test-mutations: deps
    SPOIL_TEST_LIVE=1 SPOIL_TEST_MUTATIONS=1 \
        nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

# Remove downloaded test dependencies
clean:
    rm -rf deps
