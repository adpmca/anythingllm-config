# anythingllm-config

Docker Compose configuration for self-hosting [AnythingLLM](https://github.com/Mintplex-Labs/anything-llm) — an all-in-one AI document assistant with multi-user support and support for many LLM providers.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/) installed
- An API key for your chosen LLM provider (e.g. OpenAI), or a locally running model (e.g. Ollama)

## Quick Start

1. **Clone this repository**

   ```bash
   git clone https://github.com/adpmca/anythingllm-config.git
   cd anythingllm-config
   ```

2. **Create your environment file**

   ```bash
   cp .env.example .env
   ```

3. **Edit `.env`** and fill in the required values:
   - Set your `LLM_PROVIDER` and corresponding API key (e.g. `OPEN_AI_KEY`)
   - Optionally set `AUTH_TOKEN` and `JWT_SECRET` for password-protected remote access

4. **Start AnythingLLM**

   ```bash
   docker compose up -d
   ```

5. **Open the UI** at [http://localhost:3001](http://localhost:3001)

## Configuration

All settings are controlled through the `.env` file. See `.env.example` for the full list of available options, including:

| Section | Key variables |
|---|---|
| Server | `SERVER_PORT`, `AUTH_TOKEN`, `JWT_SECRET` |
| LLM Provider | `LLM_PROVIDER`, provider-specific keys and model |
| Embedding | `EMBEDDING_ENGINE`, `EMBEDDING_MODEL_PREF` |
| Vector Database | `VECTOR_DB`, connection string / API key |
| Audio / TTS | `WHISPER_PROVIDER`, `TTS_PROVIDER` |
| Agent search | `AGENT_TAVILY_API_KEY`, `AGENT_SERPER_DEV_KEY`, etc. |

## Data Persistence

Container data is stored in the `anythingllm_storage` Docker volume. To back up your data:

```bash
docker run --rm \
  -v anythingllm_anythingllm_storage:/data \
  -v $(pwd):/backup \
  busybox tar czf /backup/anythingllm-backup.tar.gz /data
```

## Updating

```bash
docker compose pull
docker compose up -d
```

## Stopping

```bash
docker compose down
```

## Security Notes

- Set a strong `AUTH_TOKEN` and `JWT_SECRET` before exposing the service to the internet.
- Consider placing the service behind a reverse proxy (e.g. Nginx or Caddy) with HTTPS.
- Set `DISABLE_SWAGGER_DOCS="true"` in production to hide the API documentation endpoint.

## License

This configuration is provided under the [MIT License](https://opensource.org/licenses/MIT).
AnythingLLM itself is licensed under the [MIT License](https://github.com/Mintplex-Labs/anything-llm/blob/master/LICENSE).
