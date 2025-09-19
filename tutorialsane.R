# ===============================
# R TUTORIAL
# ===============================

# ---- 1. INSTALL REQUIRED R LIBRARIES ----

pkgs <- c("birdnetR", "tuneR", "seewave", "dplyr", "progress", "tools", "furrr", "future")

for (pkg in pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
  }
  library(pkg, character.only = TRUE)
}

# ---- 2. DOWNLOAD FILES FROM GITHUB REPO ----
# We will fetch only what we need using "raw.githubusercontent.com"

base_url <- "https://raw.githubusercontent.com/matpagle/sane/main/"

# Local destinations
audio_dir <- "tutorial/audio/directory" #where you will save the example audio files
noisy_file <- "noisy.WAV"
quiet_file <- "quiet.WAV"
checklist_file <- "human_noise_checklist.txt"

# Download files
download.file(paste0(base_url, "assets/noisy.wav"), paste0(audio_dir, noisy_file), mode = "wb")
download.file(paste0(base_url, "assets/quiet.wav"), paste0(audio_dir, quiet_file), mode = "wb")
download.file(paste0(base_url, "human_noise_list.txt"), checklist_file, mode = "wb")

# ---- 4. LOAD CHECKLIST ----
human_noise_checklist <- readLines(checklist_file)


# ---- 4. ANALYZE AUDIO WITH BIRDNET ----
library(birdnetR)
library(parallel)

# detect cores (leave 2 free if possible)
cores <- as.integer(max(1, detectCores() - 2))

# load BirdNET model (no manual download needed)
model <- birdnet_model_tflite(
  version = "v2.4",
  tflite_num_threads = cores
)

# ---- 5. RUN PREDICTIONS ----
# Here we filter directly by species_list
noisy_predictions <- predict_species_from_audio_file(
  model = model,
  audio_file = file.path(audio_dir, noisy_file),
  min_confidence = 0.1,
  batch_size = cores,
  chunk_overlap_s = 2,
  filter_species = human_noise_checklist,
  keep_empty = TRUE
)
noisy_predictions$Filename <- "noisy.WAV"

quiet_predictions <- predict_species_from_audio_file(
  model = model,
  audio_file = file.path(audio_dir, quiet_file),
  min_confidence = 0.1,
  batch_size = cores,
  chunk_overlap_s = 2,
  filter_species = human_noise_checklist,
  keep_empty = TRUE
)
quiet_predictions$Filename <- "quiet.WAV"
outputs <- rbind(noisy_predictions,quiet_predictions)


# ---- 6. COMPUTE SANE SCORE ----

source("https://raw.githubusercontent.com/matpagle/sane/master/sanefunction.R")

sanes <- sane(outputs, threshold = 0.1, class.specific = FALSE, freq.range = c(20, 20000),
              class.col = "common_name", filename.col = "Filename", start.col = "start",
              end.col = "end", confidence.col = "confidence", audio.dir = audio_dir,
              write.fullM = FALSE, write.sane = TRUE, sane_path = "output/sane.csv", parallel = TRUE,
              cores.percentage = 0.5)


# ---- 7. PRINT RESULTS ----
sane_noisy <- subset(sanes, filename == noisy_file)$SANE
sane_quiet <- subset(sanes, filename == quiet_file)$SANE

cat("SANE for noisy audio:", if(length(sane_noisy) == 0) 0 else sane_noisy, "\n")
cat("SANE for quiet audio:", if(length(sane_quiet) == 0) 0 else sane_quiet, "\n")
