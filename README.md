# apple-podcasts-transcriber

A macOS-first Swift project for finding downloaded Apple Podcasts episodes and
transcribing them with a local model.

The current implementation scans a hard-coded Apple Podcasts library path,
orders episodes newest first, skips transcripts that already exist, and exposes
local and OpenAI-compatible transcription backends.

If multiple downloaded audio files resolve to the same episode title, the app
keeps the newest one for transcription and skips the duplicates to avoid
repeating the same work.

## Requirements

- macOS 13 or newer
- Swift 5.8 or newer
- Xcode or Xcode Command Line Tools

## Build

Install dependencies, download the default local model, build the release
binary, install `whisper-cli` to the app support directory, and install the
command line app to `~/.local/bin`:

```sh
scripts/install.sh
```

Install system-wide instead:

```sh
scripts/install.sh --prefix /usr/local
```

Build the debug executable:

```sh
swift build
```

If running inside a sandboxed environment where SwiftPM cannot write user-level
caches, use workspace-local caches:

```sh
CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift build --cache-path .build/swiftpm-cache --disable-sandbox
```

Build the release executable:

```sh
swift build -c release
```

Use `--verbose` if SwiftPM appears quiet and you want to see compile progress:

```sh
swift build --verbose
```

The release binary is written to:

```text
.build/release/apple-podcasts-transcriber
```

## Test

Run tests normally:

```sh
swift test
```

If running inside a sandboxed environment where SwiftPM cannot write user-level
caches, use workspace-local caches:

```sh
CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --cache-path .build/swiftpm-cache --disable-sandbox
```

## Run

Run through SwiftPM:

```sh
swift run apple-podcasts-transcriber
```

Run the release binary directly after `swift build -c release`:

```sh
.build/release/apple-podcasts-transcriber
```

## Usage Examples

Run the default batch transcription flow:

```sh
swift run apple-podcasts-transcriber
```

List downloaded podcast episodes without transcribing:

```sh
swift run apple-podcasts-transcriber --list
```

Use the OpenAI-compatible API backend:

```sh
OPENAI_API_KEY=... swift run apple-podcasts-transcriber --backend openai
```

Transcribe Chinese podcasts:

```sh
swift run apple-podcasts-transcriber --language zh
```

Language codes are passed to the local `whisper-cli` backend and to the
OpenAI-compatible transcription API. Use ISO-639-style codes such as `en`,
`zh`, `ja`, or `es`.

Process only the newest five episodes:

```sh
swift run apple-podcasts-transcriber --limit 5
```

Use a specific library or output path:

```sh
swift run apple-podcasts-transcriber --library /path/to/podcasts --output /path/to/transcripts
```

Force regeneration of existing transcripts:

```sh
swift run apple-podcasts-transcriber --force
```

Delete all downloaded episode audio files discovered under the configured
podcast library path:

```sh
swift run apple-podcasts-transcriber --delete-downloaded-episodes
```

This deletes cached/downloaded audio files only. It does not delete transcript
files. Use `--library` with this option to target a specific podcast cache path.

By default, transcripts are written to:

```text
~/Documents/Apple Podcast Transcripts/
```

Transcript filenames are determined only by episode name. Existing transcript
files are skipped unless `--force` is used.

## Local Backend

The default local backend uses `whisper.cpp` through a local `whisper-cli`
process. There is no inference server.

Check whether the local backend is ready:

```sh
swift run apple-podcasts-transcriber --check-local-backend
```

Install the `whisper.cpp` CLI with Homebrew:

```sh
brew install whisper-cpp
```

Download the default multilingual model file:

```sh
mkdir -p ~/Library/Application\ Support/apple-podcasts-transcriber/models
curl -L \
  -o ~/Library/Application\ Support/apple-podcasts-transcriber/models/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

By default, the app looks for the model at:

```text
~/Library/Application Support/apple-podcasts-transcriber/models/ggml-base.bin
```

Use a multilingual model such as `base`, `small`, or `medium` for Chinese
podcasts. English-only models with `.en` in the name, such as `base.en`, are not
appropriate for Chinese audio.

The app looks for `whisper-cli` in these locations:

```text
~/Library/Application Support/apple-podcasts-transcriber/whisper.cpp/whisper-cli
/opt/homebrew/bin/whisper-cli
/usr/local/bin/whisper-cli
```

Override either path with environment variables:

```sh
APPLE_PODCASTS_TRANSCRIBER_WHISPER_CLI=/path/to/whisper-cli \
APPLE_PODCASTS_TRANSCRIBER_MODEL=/path/to/ggml-base.bin \
swift run apple-podcasts-transcriber
```

If the binary or model is missing, the CLI prints a clear error for each
episode and `--check-local-backend` reports the missing path.

The install script automates these steps:

```sh
scripts/install.sh
```

Use a different whisper.cpp model:

```sh
scripts/install.sh --model small
```
