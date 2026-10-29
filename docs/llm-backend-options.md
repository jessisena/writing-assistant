# LLM backend options for the Android app

Research from 2026-10-29. The Android app calls the Anthropic Messages API with the user's own key:
Haiku 4.5 for short English text, Sonnet 5.5 for everything else. This page compares alternatives.

Workload per request: about 2.5k input tokens (the static prompt is ~1.2k words) and about 0.5k
output tokens, returned as a JSON object. Input may be Spanish or Catalan and must come back in
English. Texts are private (emails, Slack messages), so providers that train on prompts are out.

Figures marked *(unverified)* come from third-party sites or search summaries, not the provider's
own docs. Apart from Groq (see the recommendation), nobody has tested Spanish or Catalan → English
quality for any option here yet.

## Recommendation

1. **Stay on Anthropic.** Move short English text from Haiku 4.5 to **Haiku 5.5**, which costs a
   tenth as much. Re-measure its latency over the API first: the Mac kept Haiku 4.5 because 5.5
   was ~2× slower through the CLI. Routing is shared logic, so change `ModelRouting` in both apps.
2. **Best free option: Groq's free tier.** It doesn't retain inference data by default, and its
   limits fit personal use. The Android app offers Groq as a provider in Settings (plan:
   `docs/plans/2026-10-29-groq-provider.md`), with `openai/gpt-oss-20b` as the small model and
   `openai/gpt-oss-120b` as the large one; `llama-3.1-8b-instant` was shut down on the free tier on
   2026-08-16. Live tests passed for English, Spanish and Catalan on 2026-10-29.
3. **Best on-device option: Gemma 4 E2B via LiteRT-LM.** It's free and private, but it's a 2.6 GB
   download and untested on Catalan and JSON. It would be an experiment or offline fallback.
4. **Paid fallback provider: Gemini Flash-Lite with billing enabled.** Never use the free key.

Adding a provider means a new `LlmClient` implementation in `:core` (`Contracts.kt`). It also
means a provider choice in Settings, and checking that the prompts give valid JSON on that model.

## Cost per request

Cost per request assumes 2.5k tokens in and 0.5k out. Prices are in dollars per million tokens
(MTok), input / output.

| Option | $/MTok in / out | ~$ per request | Prompts used for training |
|---|---|---|---|
| Claude Haiku 4.5 (today) | 1 / 5 | 0.0050 | No (API) |
| **Claude Haiku 5.5** | 0.10 / 0.50 | **0.0005** | No (API) |
| Claude Sonnet 5.5 (today) | 2 / 10 | 0.0100 | No (API) |
| Sonnet 5.5 with prompt-cache hit | 0.10 cached read | ~0.0070 | No (API) |
| Gemini 3.1 Flash-Lite, paid | 0.25 / 1.50 | 0.0014 | No on paid tier |
| Gemini 3.5 Flash-Lite, paid | 0.30 / 2.50 | 0.0020 | No on paid tier |
| Gemini Flash / Flash-Lite, free | free | 0 | **Yes** |
| OpenAI GPT-5 nano / mini *(unverified)* | 0.05 / 0.40, 0.25 / 2.00 | 0.0003 / 0.0016 | Not checked |
| DeepSeek V4.1 Flash, off-peak *(unverified)* | 0.15 / 0.60 | 0.0007 | Not checked; China-hosted |
| Cloudflare Workers AI, Llama 3.1 8B | 0.282 / 0.827 | 0.0011 | Not checked |
| OpenRouter (any model) | provider price + 5.5% on credits | ~provider × 1.055 | Off by default |
| AWS Bedrock (Claude) | same as Anthropic, EU can be higher | ~same | Not checked |
| Groq free tier | free | 0 | No retention by default |
| On-device (Gemini Nano, Gemma) | free | 0 | Stays on the phone |

## Anthropic

- **Haiku 5.5:** $0.10 / $0.50 for prompts up to 100k tokens
  ([pricing](https://platform.claude.com/docs/en/about-claude/pricing)). The newer tokenizer may
  count ~30% more tokens *(unverified)*, which is still far cheaper than Haiku 4.5.
- **Prompt caching** ([docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)):
  - The minimum cacheable prompt is 512 tokens on Sonnet 5.5 and Haiku 5.5, and 4,096 on Haiku
    4.5. Our static prompt (~1.6–2k tokens) only qualifies on the 5.5 models.
  - Cache reads cost 0.05× and a 5-minute write costs 1.25×.
  - It saves ~$0.003 per Sonnet request, only when requests arrive within the cache lifetime. On
    Haiku 5.5 the saving is negligible.
- **Batch API:** 50% off, but asynchronous (most batches finish within an hour), so it doesn't suit
  interactive polishing.
- **Signup credit:** about $5 for new Console accounts, expiring after ~14 days *(unverified)*.
- **Pro/Max subscription:** not allowed. Anthropic doesn't permit third-party apps to use
  Claude.ai login or route requests through Free, Pro or Max credentials
  ([legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)).
- **Claude Android app:** you can probably share text into it from the share sheet *(unverified)*.
  It returns nothing to our app, so Replace and JSON parsing wouldn't work.

## Free cloud options

| Provider | Free limits | Privacy | Notes |
|---|---|---|---|
| **Groq** | ~30 RPM, 1,000 RPD, 8K TPM, 200K TPD ([limits](https://console.groq.com/docs/rate-limits)). ~65 of our requests/day | No retention by default; abuse logs up to 30 days; zero data retention available ([your data](https://console.groq.com/docs/your-data)) | In the app: gpt-oss-20b (small), gpt-oss-120b (large). No-training claim needs confirming in the Services Agreement |
| **Cerebras** | 5 RPM, 1M tokens/day ([limits](https://inference-docs.cerebras.ai/support/rate-limits)). ~330 requests/day | Not checked | gpt-oss-120b, Qwen. Also mentions "$5 free credits" expiring in 30 days, so it may be a trial |
| Gemini free tier | Not published; 500–1,000 RPD *(unverified)* | **Used to improve Google products** ([pricing](https://ai.google.dev/gemini-api/docs/pricing)) | Ruled out for private text |
| OpenRouter `:free` | 20 RPM; 50 RPD, or 1,000 RPD after buying $10 ([limits](https://openrouter.ai/docs/api-reference/limits)) | About half the free models run on hosts that train on prompts *(unverified)*. Filtering them out in settings removes those | Usable only with the training filter on |
| Cloudflare Workers AI | 10,000 neurons/day ([pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)) | Not checked | Requests per neuron not documented |
| Mistral Experiment plan | ~1 req/s *(unverified)* | Free tier may train unless you opt out | The plan may have been withdrawn in Oct 2026. Strong Iberian-language results ([arXiv 2504.03312](https://arxiv.org/html/2504.03312)) |
| Cohere trial | 1,000 calls/month | Not checked | Trial keys are not for production use *(unverified)* |
| NVIDIA build.nvidia.com | ~40 RPM, credits unclear | Free models flagged as training-capable | Trial terms: evaluation only *(unverified)* |
| Hugging Face Inference | $0.10/month credit | — | Too little to matter |
| Together / Fireworks / SambaNova | none, $1 one-off, unclear | — | Not useful |
| GitHub Models | — | — | Retired 2026-07-30 ([docs](https://docs.github.com/en/github-models/prototyping-with-ai-models)) |
| xAI | none found | Free credits required data sharing | Not useful |

## Cheap paid cloud options

- **Gemini API with billing enabled** ([pricing](https://ai.google.dev/gemini-api/docs/pricing)).
  The paid tier doesn't train on prompts, and response-schema JSON is available. Plain HTTPS with
  an API key. Gemini 3.8 Flash is $0.75 / $3.75 until 2026-12-31, then doubles.
- **OpenAI:** GPT-5 nano and mini have structured outputs. Prices are from third-party trackers
  only, and the 2025-08-07 snapshots reportedly retire on 2026-12-11 *(unverified)*.
- **DeepSeek:** cheap off-peak, but China-hosted with an unchecked data policy, and the price
  rose in Aug 2026 *(unverified)*. Not suitable for private emails without checking.
- **OpenRouter:** one key for many providers, Claude included. It adds a hop and a 5.5% fee.
- **AWS Bedrock:** API keys work as `Authorization: Bearer` over plain HTTPS, with no SigV4
  signing ([API keys](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys.html)).
  - Long-term keys belong to an IAM user and AWS recommends them only for exploration.
  - Short-term keys last at most 12 hours.
  - It costs the same as Anthropic but needs more setup.

## On-device

| Option | Status | Fit |
|---|---|---|
| Gemini Nano, Rewriting / Proofreading API ([rewriting](https://developers.google.com/ml-kit/genai/rewriting/android)) | Beta | **No.** Under 256 input tokens, fixed styles only, no custom instructions or translation. Supports Spanish, not Catalan |
| Gemini Nano, Prompt API ([get started](https://developers.google.com/ml-kit/genai/prompt/android/get-started)) | Beta; structured output is alpha | **Weak.** Under 4k input tokens; output cap unclear (255 tokens in one version of the docs). Foreground only, recent flagships only, per-app quota, no language list |
| Gemma 4 in AICore ([blog](https://developer.android.com/blog/posts/announcing-gemma-4-in-the-ai-core-developer-preview)) | Developer preview | Later. Structured output and system prompts are "future updates" |
| **Gemma 4 E2B / E4B via LiteRT-LM** ([overview](https://developers.google.com/edge/litert-lm/overview)) | Kotlin API stable | **Possible.** 2.58 / 3.65 GB download on first run, ~0.7–1.7 GB peak RAM. Measured 47–52 tokens/s decode on an S26 Ultra, so ~5–15 s per polish on a flagship (estimate). No constrained JSON; Catalan quality unknown |
| llama.cpp / MLC | Not researched | Same model limits, more integration work |

## Ruled out

- **Claude Pro/Max subscription:** not permitted for third-party apps (see Anthropic above).
- **Typeform's LLM Gateway (LiteLLM):** internal to the company network. It needs per-service
  virtual keys from #ai-platform-team and cost-attribution tags on every call. It's not meant for
  a personal phone app.
- **Relay to the Mac's `claude` CLI:** rejected when the Android app was planned (Mac must be awake,
  brings back a server).

## Open questions

- Haiku 5.5 latency through the API.
- JSON reliability and Catalan → English quality on Gemini Flash-Lite and Gemma 4 E2B. A
  shared `liveTest`-style run over the same texts would answer this.
- Groq's Services Agreement (training) and paid prices.
- Gemini Nano Prompt API output cap and device list.
- Numeric Gemini free-tier limits, Anthropic signup credit, DeepSeek data policy.
