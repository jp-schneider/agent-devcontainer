## Local model (LM Studio)
Only applies when the variant includes `compose.lmstudio-host.yml` or `compose.lmstudio-sidecar.yml`.

- `claude-local [claude args]` runs Claude Code against the LM Studio server at `$LMSTUDIO_BASE_URL`
  (model: `$LMSTUDIO_MODEL` or `--model <key>`). Plain `claude` still uses the Anthropic API.
- Models known to the server: `curl -s $LMSTUDIO_BASE_URL/v1/models`.
- Downloading and loading models is done by the user on the host, not from the container.
