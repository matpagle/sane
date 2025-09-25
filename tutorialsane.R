# ===============================
# R TUTORIAL
# ===============================

# ---- 1. INSTALL REQUIRED R LIBRARIES ----

# List of required packages
pkgs <- c("birdnetR", "tuneR", "seewave", "dplyr", "progress", "tools", "furrr", "future", "reticulate")

# Install and load each package if not already installed
for (pkg in pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
  library(pkg, character.only = TRUE)
}

# ---- 2. SETUP TEMPORARY DIRECTORY FOR AUDIO FILES ----

# Create a temporary directory for this session
audio_dir <- file.path(tempdir(), "tutorial_audio")
if (!dir.exists(audio_dir)) {
  dir.create(audio_dir, recursive = TRUE)
}
# All files will be stored here and removed when R session ends

# ---- 3. DOWNLOAD FILES FROM GITHUB REPO ----

base_url <- "https://raw.githubusercontent.com/matpagle/sane/main/"

# File names for local use
noisy_file <- "noisy.WAV"
quiet_file <- "quiet.WAV"
checklist_file <- file.path(tempdir(), "human_noise_checklist.txt") # Save checklist in tempdir

# Download audio files to the temporary directory
download.file(paste0(base_url, "assets/noisy.wav"), file.path(audio_dir, noisy_file), mode = "wb")
download.file(paste0(base_url, "assets/quiet.wav"), file.path(audio_dir, quiet_file), mode = "wb")
download.file(paste0(base_url, "human_noise_list.txt"), checklist_file, mode = "wb")

# ---- 4. LOAD CHECKLIST ----
human_noise_checklist <- readLines(checklist_file)

# ---- 5. ANALYZE AUDIO WITH BIRDNET ----
library(birdnetR)
library(parallel)

# Detect available CPU cores (leave 2 free if possible)
cores <- as.integer(max(1, detectCores() - 2))

# Load BirdNET model (no manual download needed)
model <- birdnet_model_tflite(
  version = "v2.4",
  tflite_num_threads = cores
)

# ---- 6. RUN PREDICTIONS ----
# Filter directly by species_list
noisy_predictions <- predict_species_from_audio_file(
  model = model,
  audio_file = file.path(audio_dir, noisy_file),
  min_confidence = 0.1,
  batch_size = cores,
  chunk_overlap_s = 2,
  filter_species = human_noise_checklist,
  keep_empty = TRUE
)
noisy_predictions$Filename <- noisy_file

quiet_predictions <- predict_species_from_audio_file(
  model = model,
  audio_file = file.path(audio_dir, quiet_file),
  min_confidence = 0.1,
  batch_size = cores,
  chunk_overlap_s = 2,
  filter_species = human_noise_checklist,
  keep_empty = TRUE
)
quiet_predictions$Filename <- quiet_file
outputs <- rbind(noisy_predictions, quiet_predictions)

# ---- 7. COMPUTE SANE SCORES ----

source("https://raw.githubusercontent.com/matpagle/sane/master/sanefunction.R")

# Output file will also be in tempdir (not cluttering user disk)
sane_output_file <- file.path(tempdir(), "sane.csv")

sanes <- sane(
  outputs,
  threshold = 0.1,
  class.specific = FALSE,
  freq.range = c(20, 20000),
  class.col = "common_name",
  filename.col = "Filename",
  start.col = "start",
  end.col = "end",
  confidence.col = "confidence",
  audio.dir = audio_dir,
  write.fullM = FALSE,
  write.sane = TRUE,
  sane_path = sane_output_file,
  parallel = TRUE,
  cores = 2
)

# ---- 8. PRINT RESULTS ----
sane_noisy <- subset(sanes, filename == noisy_file)$SANE
sane_quiet <- subset(sanes, filename == quiet_file)$SANE

cat("SANE for noisy audio:", if(length(sane_noisy) == 0) 0 else sane_noisy, "\n")
cat("SANE for quiet audio:", if(length(sane_quiet) == 0) 0 else sane_quiet, "\n")

# ---- 9. CLEANUP ----
# No explicit cleanup needed: tempdir is auto-removed when R session ends
