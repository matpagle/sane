# SANE

This repository contains the R function for the _Selective Anthropogenic Noise Exposure_ index (SANE) computation, a novel acoustic index for measuring anthropogenic noise levels in terrestrial ecosystems, along with a brief tutorial. For further details check [our paper]().

The SANE index combines artificial intelligence-based acoustic classifiers and an acoustic index to obtain a measurement of anthropogenic noise in a recording. Specifically, after the classification of an acoustic dataset (step 1), the **Median Amplitude** index is computed for each detected anthropogenic sound event (step 2); SANE is then obtained by summing the Median Amplitude values within each recording (step 3). The `sane()` function in R automatically computes steps 2 and 3 based on the input data obtained in step 1.

![alt text](https://github.com/matpagle/sane/blob/main/assets/saneworkflow2.png)

Main strengths:
- SANE does not rely on traditional frequency-based discrimination between biophony and anthrophony like other indices (e.g., NDSI).
- By leveraging an artificial intelligence classifier, only target sounds are quantified by the SANE index.
- The cumulative nature of SANE allows giving the right importance to both rare disturbance events of high intensity and frequent disturbance events with low intensity.

More details are available from our paper.

---

## How to run BirdNET for Human Noise recognition

BirdNET is a tool that can be run through various supports, such as [R](https://github.com/birdnet-team/birdnetR) or [python](https://github.com/birdnet-team/birdnet). A user-friendly [GUI-version](https://github.com/birdnet-team/BirdNET-Analyzer) is also available.

For Human Noise recognition it is necessary to provide to BirdNET an [_ad-hoc_ species list](https://github.com/matpagle/sane/blob/main/human_noise_list.txt) that includes the anthropophony classes it is currently able to detect. This list can be used on its own or combined with other species lists that include taxa of interest.

We also provided a detailed [tutorial](https://github.com/matpagle/sane/blob/main/tutorialsane.R) with two sample audio-files, showing how to perform BirdNET analysis and calculate SANE values in R.

**NOTE:** Increasing segment overlap has been shown to substantially improve BirdNET's recall for biophony, and our paper shows an increase in recall for anthropogenic sounds as well. Therefore we recommend the following BirdNET-Analyzer set up to maximize initial recall: **minimum precision** = 0.1, **segments overlap** = 2, **sensitivity** = 1.

---

## SANE function

This section describes what you need to run the `sane()` function.

### What the function does (current implementation)

For each detection (row) above `threshold`, `sane()`:
1. reads the corresponding `.wav` segment from `Start` to `End` seconds (`tuneR::readWave()`),
2. optionally downsamples the segment (`tuneR::downsample()`),
3. band-pass filters the signal to `freq.range` (`seewave::bwfilter()`),
4. computes a **Median Amplitude**-based summary via `seewave::M()` and sums the result for that event,
5. aggregates event values to produce a SANE value per recording (and optionally per class).

> Note: the function currently processes only files whose extension is `.wav` (case-insensitive).

### Required libraries

You should have these packages available (the function will attempt to load them and install them if missing):
- `tuneR`
- `seewave`
- `dplyr`
- `progress`
- `tools`
- `furrr`
- `future`

### Input data

`data` must be a data.frame containing detections (one row per acoustic event), including:
- a class/label column
- an audio file identifier (file name or path)
- confidence score
- start time (seconds)
- end time (seconds)

The column names are configurable via function arguments. **Current defaults in the function are:**
- `class.col = "Common.name"`
- `filename.col = "filename"`
- `confidence.col = "Confidence"`
- `start.col = "Start"`
- `end.col = "End"`

Example structure (column names shown here are just an example—use `*_col` arguments to match your data):

| filename                                  | Start (s) | End (s) | Common.name | Confidence |
| ----------------------------------------- | --------- | ------- | ----------- | ---------- |
| /path/to/20240324_170000.WAV              | 0.0       | 3.0     | Engine      | 0.9807     |
| /path/to/20240324_170000.WAV              | 3.0       | 6.0     | Gun         | 0.8176     |
| ...                                       | ...       | ...     | ...         | ...        |

### Audio paths: `full.audio.path` vs `audio.dir`

`sane()` supports two ways of providing audio locations:

- `full.audio.path = TRUE` (default): `filename.col` already contains the full path to the audio file.
- `full.audio.path = FALSE`: `filename.col` contains only file names (or relative paths) and you must provide `audio.dir`. In this case, the function builds paths with `file.path(audio.dir, filename)`.

### Function arguments

- `data`: data.frame of detections (one row per acoustic event).
- `threshold` (default `0.8`): minimum confidence required to include an event.
- `class.specific` (default `FALSE`):  
  - If `FALSE`, compute a single `SANE` per file.  
  - If `TRUE`, compute SANE separately for each class. Output column names are built as `SANE_<Class>` (with non-alphanumeric characters converted to `_`).
- `freq.range` (default `c(20, 20000)`): numeric vector length 2 (Hz), band-pass filter range `c(low, high)`.
- `class.col` (default `"Common.name"`): name of the column in `data` containing the class/label.
- `filename.col` (default `"filename"`): name of the column in `data` containing the audio filename or path.
- `start.col` (default `"Start"`): name of the column containing event start time (seconds).
- `end.col` (default `"End"`): name of the column containing event end time (seconds).
- `confidence.col` (default `"Confidence"`): name of the column containing confidence values.
- `audio.dir` (default `NULL`): directory containing audio files (used only if `full.audio.path = FALSE`).
- `full.audio.path` (default `TRUE`): if `TRUE`, `filename.col` already contains full file paths; if `FALSE`, paths are built using `audio.dir`.
- `downsample` (default `TRUE`): if `TRUE`, downsample each extracted audio segment before analysis.
- `downsample.freq` (default `48000`): target sampling rate (Hz) used when `downsample = TRUE`.
- `write.fullM` (default `TRUE`): if `TRUE`, write event-level results (per detection) to `fullM_path` (CSV separator is `;`). This supports resuming long runs.
- `fullM_path` (default `"output/full_M.csv"`): output path for the event-level CSV (separator is `;`).
- `write.sane` (default `TRUE`): if `TRUE`, write the aggregated per-file SANE table to `sane_path` (CSV separator is `;`).
- `sane_path` (default `"output/sane.csv"`): output path for the final SANE CSV (separator is `;`).
- `resume` (default `FALSE`): if `TRUE` and `fullM_path` exists (and `write.fullM = TRUE`), skip events already present in that file.
- `parallel` (default `TRUE`): if `TRUE`, process events in parallel using `future/furrr`.
- `cores` (default `2`): number of worker processes to use when `parallel = TRUE`.
- `batch_size` (default `100`): currently not used in the code.

### Outputs

The function returns a data.frame:
- If `class.specific = FALSE`: one row per `filename` with a `SANE` column.
- If `class.specific = TRUE`: grouped by `filename` and `Class`, with per-class `SANE_<Class>` columns.

If enabled:
- `fullM_path` stores event-level results (separator `;`).
- `sane_path` stores aggregated SANE results (separator `;`).