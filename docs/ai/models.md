# On-device models — what to download, from where, with which license

> **Kanoon (laws):** the repo NEVER contains a model binary
> (gitignore: `/assets/models/`, `*.task`, `*.litertlm`, `*.gguf`).
> Models arrive via user import (SAF) or a Play Asset Delivery pack
> you configure. Nothing auto-downloads — the app has no network code
> (ADR-0001/0007).

## 1. Which model file, for which phone

| Tier | File | Size class | RAM floor | Notes |
|---|---|---|---|---|
| Small | FunctionGemma-class 270M (`.task` build) | ≈288 MB | any | Function-calling specialist — chat-agent quality is limited by design; roasts/templates unaffected |
| E2B | `gemma-3n-e2b-it-int4.task` | ≈2 GB | 6 GB+ | **Default target.** Multimodal (vision) — powers the receipt ensemble leg too |
| E4B | `gemma-3n-e4b-it-int4.task` | ≈3 GB | 8 GB+ | Best quality; only suggested on 8 GB+ devices |

The app reads total RAM from its own `udao/platform` channel
(ActivityManager), suggests a tier, and never hard-blocks a bigger
model — your RAM, your call (Settings → AI → Device tier).

## 2. Where to get the files (human steps, no automation)

**Gemma 3n (E2B/E4B, int4, `.task`):**

1. Google AI Edge / Kaggle — the official Gemma 3n `.task`
   artifacts are published under the Gemma model cards (search
   "gemma-3n E2B int4 task" on Kaggle or Google AI Edge Gallery).
2. Hugging Face mirrors (e.g. `google/gemma-3n-*` model cards) ship
   `.litertlm` / safetensors variants; **MediaPipe tasks-genai
   loads `.task`** — prefer the official `.task` builds.
3. Accept the **Gemma Terms of Use** (Google's license — it is NOT
   Apache-2.0; the license text ships with every model card).

**FunctionGemma 270M:**

1. `google/functiongemma-270m-it` on Hugging Face (Gemma-3-based,
   function-calling fine-tune).
2. **License:** check the model card before shipping (spec target:
   Apache-2.0; the card is the source of truth).
3. The HF artifact is a text-model format — a MediaPipe `.task`
   build (LiteRT conversion, e.g. the `litert-community` conversions)
   is needed before the app can load it.
   **TODO-VERIFY(local):** availability of a ready `.task` build;
   until then the E2B file is the practical floor.

## 3. Getting the file onto the phone

**Manual import (works today):**

1. Download the `.task` file on the phone (browser/files app).
2. UDAO → Settings → **AI / Dimaag** → *Import model*.
3. Pick the file. UDAO validates: extension `.task`, size
   50 MB–5 GB, computes **SHA-256**, and re-verifies the hash on
   every load (a corrupted file fails closed with
   `ai-sha-mismatch` — never a crash mid-inference).
4. The file is COPIED into app-documents
   (`models/imported/`) so it survives reboots; the original can be
   deleted.

**Dev sideload (adb) — DEBUG builds only:**

Production reads models from the app-private documents dir
(`/data/user/0/in.udao.app/app_flutter/models/`), which plain `adb
push` cannot write on a non-rooted device. Two honest paths:

* **Any build (release included):** `adb push` the `.task` file to
  `/sdcard/Download/`, then use the in-app *Import model* picker
  (SAF) — identical validation and hashing as a browser download.
* **Debug builds:** `run-as` reaches the private dir directly —

```bash
adb push gemma-3n-e2b-it-int4.task /sdcard/Download/
adb shell run-as in.udao.app mkdir -p app_flutter/models/pad
adb shell run-as in.udao.app cp \
  /sdcard/Download/gemma-3n-e2b-it-int4.task \
  app_flutter/models/pad/gemma-3n-e2b-it-int4.task
```

The `models/pad/` staging path is exactly where the PAD flow (see
[asset-delivery.md](asset-delivery.md)) is expected to deliver the
file — discovery checks it first.

## 4. What the model is used for (and what works without one)

| Path | With model | Without model (template-only) |
|---|---|---|
| Roast | template + model rewrite (Savage voice) | template floor — roasts NEVER die |
| Chat (free-form) | streamed Hinglish answers + tool chips | honest banner: "seedha-jawab mode" |
| Agent tools | model decides which tools to call | tools still work via UI (Phase 07 screens) |
| Unknown-bank parsing | LLM-fallback → pending review + learned-regex proposal | parser stays rules-only (Phase 02 chain) |
| Receipt vision | model leg of the ensemble | rules + human-confirm (unchanged) |

## 5. Memory & battery honesty

- One model resident at a time; **5-minute idle unload** (default).
- "Brain warm rakhna" (preload) toggle keeps it resident — at a
  battery cost, which the settings copy states.
- OS memory pressure unloads the model (unless preload is pinned).
- MediaPipe reports no token usage — every token count in the app is
  labeled **estimated** (chars/4). No fake precision.
