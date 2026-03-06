#  sane  score computation function
# ---- SANE (Summed Anthrophony/Nuisance Energy) ----
# sane() computes a per-audio-file anthrophony metric from classifier detections.
# For each detection above `threshold`, it:
#   1) reads the corresponding .wav segment (Start–End seconds),
#   2) optionally downsamples it,
#   3) band-pass filters it to `freq.range`,
#   4) computes an energy/amplitude summary with seewave::M(),
# then sums these values to produce SANE.
#
# Arguments:
# - data: Data frame of detections (one row per acoustic event).
# - threshold: Minimum confidence required to include an event.
# - class.specific: If TRUE, compute SANE separately for each class (SANE_<Class>);
#   if FALSE, compute a single SANE per file.
# - freq.range: Numeric vector length 2 (Hz), band-pass filter range c(low, high).
# - class.col: Name of the column in `data` containing the class/label.
# - filename.col: Name of the column in `data` containing the audio filename or path.
# - start.col: Name of the column in `data` containing event start time (seconds).
# - end.col: Name of the column in `data` containing event end time (seconds).
# - confidence.col: Name of the column in `data` containing confidence values.
# - audio.dir: Directory containing audio files (used only if full.audio.path = FALSE).
# - full.audio.path: If TRUE, `filename.col` already contains full file paths;
#   if FALSE, paths are built with file.path(audio.dir, filename).
# - downsample: If TRUE, downsample each extracted audio segment before analysis.
# - downsample.freq: Target sampling rate (Hz) used when downsample = TRUE.
# - write.fullM: If TRUE, write event-level results (per detection) to `fullM_path`
#   to support resuming long runs.
# - fullM_path: Output path for the event-level CSV (separator is ';').
# - write.sane: If TRUE, write the aggregated per-file SANE table to `sane_path`.
# - sane_path: Output path for the final SANE CSV (separator is ';').
# - resume: If TRUE and `fullM_path` exists, skip events already present in that file.
# - parallel: If TRUE, process events in parallel using future/furrr.
# - cores: Number of worker processes to use when parallel = TRUE.
# - batch_size: Number of events per batch (currently not used in the code).

sane <- function(data,
                 threshold = 0.8,
                 class.specific = FALSE,
                 freq.range = c(20, 20000),
                 class.col = "Common.name",
                 filename.col = "filename",
                 start.col = "Start",
                 end.col = "End",
                 confidence.col = "Confidence",
                 audio.dir = NULL,
                 full.audio.path = TRUE,
                 downsample = TRUE,
                 downsample.freq = 48000,
                 write.fullM = TRUE,
                 fullM_path = "output/full_M.csv",
                 write.sane = TRUE,
                 sane_path = "output/sane.csv",
                 resume = FALSE,
                 parallel = TRUE,
                 cores = 2,
                 batch_size = 100) {
  
  # Load required packages; if not installed, install them
  pkgs_list <- c("tuneR", "seewave", "dplyr", "progress", "tools", "furrr", "future")
  for (pkg in pkgs_list) {
    if (!require(pkg, character.only = TRUE)) {
      install.packages(pkg, dependencies = TRUE)
    }
    library(pkg, character.only = TRUE)
  }
  options(future.globals.maxSize = 2 * 1024^3) # currently set 2GB as worker's limits, default, 500Mb, is too low for our audio-files, it could depends on the dimension of your environment
  
  start_time <- Sys.time()
  
  # Columns check
  required_cols <- c(class.col, filename.col, confidence.col, start.col, end.col)
  missing <- setdiff(required_cols, names(data))
  if (length(missing) > 0) stop(paste("Missing columns:", paste(missing, collapse = ", ")))
  
  data$Class      <- data[[class.col]]
  data$filename   <- data[[filename.col]]
  data$Confidence <- data[[confidence.col]]
  data$Start      <- data[[start.col]]
  data$End        <- data[[end.col]]
  
  # Build the audio path depending on whether filename.col already contains a full path
  if (isTRUE(full.audio.path)) {
    # filename.col already contains the full file path
    data$path <- data$filename
  } else {
    # filename.col contains only the filename; audio.dir must be provided
    if (is.null(audio.dir)) stop("When full.audio.path = FALSE you must provide 'audio.dir'.")
    data$path <- file.path(audio.dir, data$filename)
  }
  
  # Threshold filter
  if (class.specific) {
    data <- data %>% group_by(Class) %>% filter(Confidence >= threshold) %>% ungroup()
  } else {
    data <- data %>% filter(Confidence >= threshold)
  }
  
  if (nrow(data) == 0) stop("No data left after filtering by threshold.")
  
  if (write.fullM) dir.create(dirname(fullM_path), recursive = TRUE, showWarnings = FALSE)
  if (write.sane) dir.create(dirname(sane_path), recursive = TRUE, showWarnings = FALSE)
  
  processed_keys <- character(0)
  existing <- NULL
  if (write.fullM && resume && file.exists(fullM_path)) {
    existing <- read.csv(fullM_path, sep = ";", stringsAsFactors = FALSE)
    processed_keys <- paste(existing$filename, existing$Class, existing$Confidence, sep = "___")
  }
  
  all_keys <- paste(data$filename, data$Class, data$Confidence, sep = "___")
  to_process_idx <- which(!(all_keys %in% processed_keys))
  total_tasks <- length(to_process_idx)
  
  if (parallel) {
    detected_cores <- parallel::detectCores()
    if (cores < 1) cores <- 1
    if (cores > detected_cores) cores <- detected_cores
    message(sprintf("Parallel mode ON: using %d of %d cores", cores, detected_cores))
    plan(multisession, workers = cores)
  } else {
    message(sprintf("Parallel mode OFF: using 1 of %d cores", parallel::detectCores()))
  }
  
  # File lock to avoid conflicts when writing to csv from multiple workers
  lockfile <- if (write.fullM) paste0(fullM_path, ".lock") else NULL
  
  safe_write <- function(df) {
    if (!write.fullM) return(NULL)
    if (requireNamespace("filelock", quietly = TRUE)) {
      lock <- filelock::lock(lockfile, timeout = 5000)
      on.exit(filelock::unlock(lock), add = TRUE)
    }
    write.table(df, file = fullM_path,
                sep = ";", row.names = FALSE,
                col.names = !file.exists(fullM_path),
                append = file.exists(fullM_path))
  }
  
  # Storage for results when write.fullM is FALSE
  results_list <- list()
  
  # Row by row processing
  process_row <- function(i) {
    file_path <- data$path[i]
    ext <- tolower(file_ext(file_path))
    if (ext != "wav") return(NULL)
    
    audio <- tryCatch({
      readWave(file_path, from = max(0, data$Start[i]), to = data$End[i], unit = "seconds")
    }, error = function(e) return(NULL))
    
    if (is.null(audio)) {
      warning(sprintf(
        "Audio is missing (failed to read): path='%s' (row=%d, start=%s, end=%s). Check filename and audio directory",
        file_path, i, as.character(data$Start[i]), as.character(data$End[i])
      ))
      return(NULL)
    }
    
    # Optional downsampling (to speed up computations)
    if (isTRUE(downsample)) {
      if (!is.numeric(downsample.freq) || length(downsample.freq) != 1 || is.na(downsample.freq) || downsample.freq <= 0) {
        stop("'downsample.freq' must be a single positive numeric value (e.g., 48000).")
      }
      if (audio@samp.rate != downsample.freq) {
        audio <- tuneR::downsample(audio, samp.rate = downsample.freq)
      }
    }
    
    fs <- audio@samp.rate
    
    # Bandpass filter (unchanged logic)
    audio <- bwfilter(audio, channel = 1, n = 4,
                      from = freq.range[1], to = freq.range[2], bandpass = TRUE)
    
    M_out <- M(audio, f = fs, channel = 1)
    M_sum <- sum(M_out, na.rm = TRUE)
    
    SANE_col <- if (class.specific) paste0("SANE_", gsub("[^[:alnum:]_]", "_", data$Class[i])) else "SANE"
    
    row_df <- data.frame(filename = data$filename[i],
                         Class = data$Class[i],
                         Confidence = data$Confidence[i])
    row_df[[SANE_col]] <- M_sum
    
    if (write.fullM) {
      # Safe write inside each worker
      safe_write(row_df)
    } else {
      # Store results in memory
      return(row_df)
    }
    return(NULL)
  }
  
  # Progressbar
  if (parallel) {
    results_list <- future_map(to_process_idx, process_row, .progress = TRUE)
  } else {
    pb <- txtProgressBar(min = 0, max = total_tasks, style = 3)
    for (j in seq_along(to_process_idx)) {
      i <- to_process_idx[j]
      results_list[[j]] <- process_row(i)
      setTxtProgressBar(pb, j)
    }
    close(pb)
  }
  
  # full M file, it is necessary for the resume
  completeM <- if (!is.null(existing)) existing else data.frame()
  if (write.fullM && file.exists(fullM_path)) {
    fullM_new <- read.csv(fullM_path, sep = ";", stringsAsFactors = FALSE)
    completeM <- bind_rows(completeM, fullM_new)
  } else if (!write.fullM) {
    # Combine results from memory
    results_list <- Filter(Negate(is.null), results_list)
    if (length(results_list) > 0) {
      completeM <- bind_rows(results_list)
    }
  }
  
  # SANE
  if (nrow(completeM) > 0) {
    if (class.specific) {
      sane_df <- completeM %>%
        group_by(filename, Class) %>%
        summarise(across(starts_with("SANE_"), sum, na.rm = TRUE), .groups = 'drop')
    } else {
      sane_df <- completeM %>%
        group_by(filename) %>%
        summarise(SANE = sum(SANE, na.rm = TRUE), .groups = 'drop')
    }
  } else {
    sane_df <- data.frame()
  }
  
  if (write.sane && nrow(sane_df) > 0) {
    write.table(sane_df, file = sane_path,
                sep = ";", row.names = FALSE, col.names = TRUE)
  }
  
  end_time <- Sys.time()
  duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
  h <- floor(duration / 3600)
  m <- floor((duration %% 3600) / 60)
  s <- round(duration %% 60)
  message(sprintf("Execution completed in %02d:%02d:%02d (hh:mm:ss)", h, m, s))
  
  return(sane_df)
}

