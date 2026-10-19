#!/usr/bin/env bats
# claude-local (shared/bin/claude-local) and the LM Studio overlays (compose.lmstudio-*.yml).
# claude-local runs only in the container, so it runs with the default bash, not BASH_UNDER_TEST.

load helpers

WRAPPER="$SHARED/bin/claude-local"

setup() {
    setup_workdir
    # Stub claude: prints the arguments and the variables claude-local is responsible for
    mkdir -p "$WORK/bin"
    cat > "$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "args=$*"
for v in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL \
    ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL \
    CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_ATTRIBUTION_HEADER CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; do
    echo "$v=${!v-<unset>}"
done
EOF
    chmod +x "$WORK/bin/claude"
}

teardown() {
    teardown_workdir
}

# local_claude [VAR=value ...] -- [args]: run the wrapper with a clean env and the stub on PATH
local_claude() {
    local envs=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
    [ $# -gt 0 ] && shift
    run env -i HOME="$WORK" PATH="$WORK/bin:/usr/bin:/bin" "${envs[@]}" bash "$WRAPPER" "$@"
}

@test "without LMSTUDIO_BASE_URL: exits 2 and names the overlays, does not start claude" {
    local_claude LMSTUDIO_MODEL=m --
    [ "$status" -eq 2 ]
    output_has "compose.lmstudio-host.yml"
    printf "%s\n" "$output" | not_grep -F "args="
}

@test "without a model: exits 2 and tells how to set one" {
    local_claude LMSTUDIO_BASE_URL=http://h:1234 --
    [ "$status" -eq 2 ]
    output_has "LMSTUDIO_MODEL"
    printf "%s\n" "$output" | not_grep -F "args="
}

@test "maps base URL, default token and every model slot; passes args through" {
    local_claude LMSTUDIO_BASE_URL=http://h:1234/ LMSTUDIO_MODEL=qwen/x ANTHROPIC_API_KEY=sk-real -- -p "hi there"
    [ "$status" -eq 0 ]
    output_has "args=-p hi there"
    output_has "ANTHROPIC_BASE_URL=http://h:1234"
    printf "%s\n" "$output" | not_grep -F "ANTHROPIC_BASE_URL=http://h:1234/"
    output_has "ANTHROPIC_AUTH_TOKEN=lmstudio"
    output_has "ANTHROPIC_API_KEY=<unset>"
    for v in ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL \
        ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_SUBAGENT_MODEL; do
        output_has "$v=qwen/x"
    done
    output_has "CLAUDE_CODE_ATTRIBUTION_HEADER=0"
    output_has "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
}

@test "LMSTUDIO_API_TOKEN is used as the auth token" {
    local_claude LMSTUDIO_BASE_URL=http://h:1234 LMSTUDIO_MODEL=m LMSTUDIO_API_TOKEN=tok --
    [ "$status" -eq 0 ]
    output_has "ANTHROPIC_AUTH_TOKEN=tok"
}

@test "--model <key> and --model=<key> override LMSTUDIO_MODEL (and work without it)" {
    local_claude LMSTUDIO_BASE_URL=http://h:1234 LMSTUDIO_MODEL=env-model -- --model cli-model
    [ "$status" -eq 0 ]
    output_has "ANTHROPIC_DEFAULT_HAIKU_MODEL=cli-model"
    output_has "args=--model cli-model"

    local_claude LMSTUDIO_BASE_URL=http://h:1234 -- --model=eq-model -p x
    [ "$status" -eq 0 ]
    output_has "CLAUDE_CODE_SUBAGENT_MODEL=eq-model"
}

@test "negative control: plain claude (stub) sees none of the LM Studio settings" {
    run env -i HOME="$WORK" PATH="$WORK/bin:/usr/bin:/bin" LMSTUDIO_BASE_URL=http://h:1234 claude
    [ "$status" -eq 0 ]
    output_has "ANTHROPIC_BASE_URL=<unset>"
}

@test "the image build ships the wrapper: Dockerfile copies it, .dockerignore lets it through" {
    grep -q '^COPY --chmod=755 shared/bin/claude-local /usr/local/bin/claude-local$' "$SHARED/Dockerfile"
    grep -qx '!shared/bin/' "$REPO_ROOT/.devcontainer/.dockerignore"
}

@test "overlays parse; both set LMSTUDIO_BASE_URL; the sidecar is hardened and publishes no port" {
    local py='import sys, yaml
host = yaml.safe_load(open(sys.argv[1]))["services"]
side = yaml.safe_load(open(sys.argv[2]))["services"]
assert "LMSTUDIO_BASE_URL" in host["claude-code"]["environment"]
assert "host.docker.internal:host-gateway" in host["claude-code"]["extra_hosts"]
assert side["claude-code"]["environment"]["LMSTUDIO_BASE_URL"] == "http://lmstudio:1234"
lms = side["lmstudio"]
assert "ports" not in lms, "sidecar must not publish ports"
assert lms["cap_drop"] == ["ALL"]
assert "no-new-privileges:true" in lms["security_opt"]
assert lms["networks"] == ["dev"]
mount = lms["volumes"][0]
assert mount["bind"]["create_host_path"] is False'
    if python3 -c 'import yaml' 2> /dev/null; then py_cmd=(python3); else py_cmd=(uv run -q --with pyyaml python); fi
    "${py_cmd[@]}" -c "$py" "$SHARED/compose.lmstudio-host.yml" "$SHARED/compose.lmstudio-sidecar.yml"
}
