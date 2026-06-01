# Apple Podcasts Transcriber Plan

## Goal

Build a macOS command line app that finds downloaded Apple Podcasts episodes,
transcribes them, and writes one transcript text file per episode.

The app has no UI. It should work as a local batch tool that can be run from a
terminal.

## Requirements

1. The app is a command line app for MacBook/macOS.
2. The app assumes downloaded Apple Podcasts files are located somewhere on the
   MacBook at a hard-coded default path.
3. By default, the app uses a downloaded open-source speech-to-text model
   locally on the MacBook.
4. The app also supports an API transcription backend using OpenAI-compatible
   API request/response conventions.
5. The app writes transcript text to a file for each podcast episode.
6. The transcript filename is determined only by the podcast episode name.
7. If the transcript file already exists, the app skips transcription for that
   episode to avoid wasted work.
8. The app sorts episodes in reverse chronological order and starts with the
   most recent episode.

## Default Behavior

Running the app with no arguments should:

1. Scan the hard-coded Apple Podcasts download/cache directory.
2. Find podcast audio files.
3. Read the episode name and episode date for each audio file.
4. Sort episodes in reverse chronological order.
5. Convert the episode name into a safe `.txt` filename.
6. Check whether the transcript file already exists.
7. Skip existing transcripts.
8. Transcribe missing transcripts using the local backend.
9. Write transcript files to the configured transcript output directory.

## Proposed CLI

```sh
apple-podcasts-transcriber
```

Optional flags:

```sh
apple-podcasts-transcriber --backend local
apple-podcasts-transcriber --backend openai
apple-podcasts-transcriber --force
apple-podcasts-transcriber --limit 5
apple-podcasts-transcriber --episode "Episode Name"
```

Initial implementation can keep the CLI smaller:

```sh
apple-podcasts-transcriber
apple-podcasts-transcriber --backend openai
apple-podcasts-transcriber --force
```

## Hard-Coded Defaults

Podcast library root:

```text
~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/
```

Transcript output directory:

```text
~/Documents/Apple Podcast Transcripts/
```

Local model directory:

```text
~/Library/Application Support/apple-podcasts-transcriber/models/
```

These should start as constants in code. They can become config values later.

## Architecture

```text
CLI
 |
 |-- PodcastFinder
 |     scans the hard-coded Apple Podcasts directory
 |     returns candidate audio files
 |
 |-- EpisodeMetadataReader
 |     extracts episode name and episode date from audio metadata
 |     falls back to source filename/date if metadata is unavailable
 |
 |-- EpisodeSorter
 |     sorts episodes newest first
 |
 |-- TranscriptStore
 |     converts episode name to safe transcript filename
 |     checks whether transcript already exists
 |     writes transcript text
 |
 |-- Transcriber
       |
       |-- LocalTranscriber
       |     default backend
       |     uses downloaded local open-source model
       |
       |-- OpenAICompatibleTranscriber
             optional backend
             uses OpenAI-compatible audio transcription API
```

## Key Interfaces

```swift
protocol PodcastFinding {
    func findEpisodes() throws -> [PodcastEpisode]
}

protocol EpisodeMetadataReading {
    func readMetadata(from audioFile: URL) throws -> EpisodeMetadata
}

protocol TranscriptStoring {
    func transcriptURL(for episodeName: String) -> URL
    func transcriptExists(for episodeName: String) -> Bool
    func write(_ text: String, for episodeName: String) throws
}

protocol Transcribing {
    func transcribe(audioFile: URL) throws -> String
}
```

## Episode Ordering

Episodes must be processed in reverse chronological order, starting with the
most recent episode.

Preferred date source:

1. Episode release date from audio metadata, if present.
2. Apple Podcasts metadata database date, if available in a later phase.
3. Audio file creation date.
4. Audio file modification date.

If no usable date is available, the app should put that episode after dated
episodes and sort undated episodes by episode name for deterministic behavior.

Sorting should happen before skip checks so the terminal output reflects the
same newest-first order regardless of whether episodes are transcribed or
skipped.

## Local Transcription Backend

Preferred first implementation:

- Use `whisper.cpp` as the local transcription engine.
- Store/download a model file locally.
- Call the local `whisper.cpp` binary from the CLI app.
- Capture transcript output and write it through `TranscriptStore`.

Example local model path:

```text
~/Library/Application Support/apple-podcasts-transcriber/models/ggml-base.en.bin
```

This keeps the first version pragmatic. A native Core ML or Swift-integrated
backend can be added later behind the same `Transcribing` protocol.

## OpenAI-Compatible API Backend

The API backend should:

- Use `OPENAI_API_KEY` for authentication by default.
- Support a configurable base URL later.
- Send audio using an OpenAI-compatible transcription request format.
- Return plain transcript text to the shared `TranscriptStore`.

Long podcast episodes may exceed API upload limits. API chunking should be a
separate implementation step after the basic backend works.

## Transcript Filename Rules

The filename must be determined only by podcast episode name.

Rules:

1. Trim leading/trailing whitespace.
2. Replace `/`, `:`, and other unsafe filename characters.
3. Collapse repeated whitespace.
4. Append `.txt`.

Example:

```text
Episode name: "My Favorite Episode: Part 1"
Transcript:   "My Favorite Episode - Part 1.txt"
```

Collision behavior:

If two different podcast files have the same episode name, they map to the same
transcript path. Because the filename must be determined only by episode name,
the app should skip the second one if the transcript already exists and print a
clear warning.

## Skip Behavior

Before transcribing:

```text
if transcript file exists:
    print "Skipping: <episode name>"
else:
    transcribe episode
    write transcript file
```

`--force` can be added to overwrite existing transcripts when the user
explicitly requests it.

## Implementation Phases

### Phase 1: CLI Skeleton

- Swift package command line app.
- Basic argument parsing.
- Hard-coded default paths.
- Clear terminal logging.

### Phase 2: Podcast Discovery

- Recursively scan the Apple Podcasts directory.
- Identify supported audio files: `.m4a`, `.mp3`, `.mp4`, `.wav`, `.aac`.
- Return candidate audio files for metadata enrichment and sorting.

### Phase 3: Episode Metadata Extraction

- Read episode title from audio metadata.
- Read episode release date from audio metadata when available.
- Fall back to filename without extension.
- Fall back to file creation/modification date when release date is unavailable.
- Add tests for filename sanitization, date fallback, and metadata fallback
  behavior.

### Phase 4: Episode Ordering

- Sort episodes newest first before processing.
- Put undated episodes after dated episodes.
- Sort undated episodes by episode name for deterministic behavior.
- Add tests for reverse chronological sorting.

### Phase 5: Transcript Store

- Implement episode-name-only transcript paths.
- Skip existing transcript files.
- Add collision warning behavior.
- Add tests for skip logic and filename sanitization.

### Phase 6: Local Transcription

- Integrate local `whisper.cpp` binary/model.
- Validate that missing binary/model errors are clear.
- Write transcript text through shared storage.

### Phase 7: OpenAI-Compatible Backend

- Add API backend selection.
- Read API key from environment.
- Send audio transcription request.
- Write returned text through shared storage.

### Phase 8: Large File Handling

- Add chunking for long podcast files.
- Recombine chunk transcripts in order.
- Keep skip behavior at the episode transcript level.

## Open Questions

1. Should the local model and `whisper.cpp` binary be auto-downloaded, or should
   the user install them first?
2. Which local model size should be the default: tiny, base, small, or medium?
3. Should transcript output include timestamps, or plain text only?
4. Should the transcript directory preserve any show-level grouping, or remain a
   flat directory with episode-name-only filenames?
5. Should failed episodes be retried automatically, or only reported?
6. Which date should be authoritative if audio metadata, Apple Podcasts
   database metadata, and file timestamps disagree?
