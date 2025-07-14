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
                 write.fullM = TRUE,
                 fullM_path = "output/full_M.csv",
                 write.sane = TRUE,
                 sane_path = "output/sane.csv",
                 resume = FALSE,
                 parallel = TRUE,
                 cores.percentage = 0.5,
                 batch_size = 100) {
  
  library(tuneR)
  library(seewave)
  library(dplyr)
  library(progress)
  library(tools)
  library(furrr)
  library(future)
  options(future.globals.maxSize = 2 * 1024^3) # currently set 2GB as worker's limits, default, 500Mb, is too low for our audio-files, it could depends on our directory?
  
  start_time <- Sys.time()
  
  # Verifica colonne
  required_cols <- c(class.col, filename.col, confidence.col, start.col, end.col)
  missing <- setdiff(required_cols, names(data))
  if (length(missing) > 0) stop(paste("Missing columns:", paste(missing, collapse = ", ")))
  
  data$Class     <- data[[class.col]]
  data$filename  <- data[[filename.col]]
  data$Confidence <- data[[confidence.col]]
  data$Start     <- data[[start.col]]
  data$End       <- data[[end.col]]
  
  if (!is.null(audio.dir)) {
    data$path <- file.path(audio.dir, data$filename)
  } else if (!"path" %in% names(data)) {
    stop("Column 'path' missing and 'audio.dir' not provided.")
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
  if (resume && file.exists(fullM_path)) {
    existing <- read.csv(fullM_path, sep = ";", stringsAsFactors = FALSE)
    processed_keys <- paste(existing$filename, existing$Class, existing$Confidence, sep = "___")
  }
  
  all_keys <- paste(data$filename, data$Class, data$Confidence, sep = "___")
  to_process_idx <- which(!(all_keys %in% processed_keys))
  total_tasks <- length(to_process_idx)
  
  if (parallel) {
    cores <- floor(parallel::detectCores() * cores.percentage)
    if (cores < 1) cores <- 1
    message(sprintf("Parallel mode ON: using %d of %d cores", cores, parallel::detectCores()))
    plan(multisession, workers = cores)
  } else {
    message(sprintf("Parallel mode OFF: using 1 of %d cores", parallel::detectCores()))
  }
  
  # File lock per evitare conflitti nella scrittura del csv
  lockfile <- paste0(fullM_path, ".lock")
  
  safe_write <- function(df) {
    if (requireNamespace("filelock", quietly = TRUE)) {
      lock <- filelock::lock(lockfile, timeout = 5000)
      on.exit(filelock::unlock(lock), add = TRUE)
    }
    write.table(df, file = fullM_path,
                sep = ";", row.names = FALSE,
                col.names = !file.exists(fullM_path),
                append = file.exists(fullM_path))
  }
  
  # Scrittura riga per riga
  process_row <- function(i) {
    file_path <- data$path[i]
    ext <- tolower(file_ext(file_path))
    if (ext != "wav") return(NULL)
    
    audio <- tryCatch({
      readWave(file_path, from = max(0, data$Start[i]), to = min(300, data$End[i]), unit = "seconds")
    }, error = function(e) return(NULL))
    
    if (is.null(audio)) return(NULL)
    
    fs <- audio@samp.rate
    audio <- bwfilter(audio, channel = 1, n = 4,
                      from = freq.range[1], to = freq.range[2], bandpass = TRUE)
    M_out <- M(audio, f = fs, channel = 1)
    M_sum <- sum(M_out, na.rm = TRUE)
    
    SANE_col <- if (class.specific) paste0("SANE_", gsub("[^[:alnum:]_]", "_", data$Class[i])) else "SANE"
    
    row_df <- data.frame(filename = data$filename[i],
                         Class = data$Class[i],
                         Confidence = data$Confidence[i])
    row_df[[SANE_col]] <- M_sum
    
    # Scrittura sicura da dentro ogni worker
    safe_write(row_df)
    return(NULL)
  }
  
  # Progressbar
  if (parallel) {
    future_map(to_process_idx, process_row, .progress = TRUE)
  } else {
    pb <- txtProgressBar(min = 0, max = total_tasks, style = 3)
    for (j in seq_along(to_process_idx)) {
      i <- to_process_idx[j]
      process_row(i)
      setTxtProgressBar(pb, j)
    }
    close(pb)
  }
  
  # fullM
  completeM <- if (!is.null(existing)) existing else data.frame()
  if (file.exists(fullM_path)) {
    fullM_new <- read.csv(fullM_path, sep = ";", stringsAsFactors = FALSE)
    completeM <- bind_rows(completeM, fullM_new)
  }
  
  # SANE
  if (class.specific) {
    sane_df <- completeM %>%
      group_by(filename, Class) %>%
      summarise(across(starts_with("SANE_"), sum, na.rm = TRUE), .groups = 'drop')
  } else {
    sane_df <- completeM %>%
      group_by(filename) %>%
      summarise(SANE = sum(SANE, na.rm = TRUE), .groups = 'drop')
  }
  
  if (write.sane) {
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


citynet <- read.csv("C:\\Users\\ASUS\\Desktop\\citynetoutput\\Urbis_Recs\\tabular_predictions.csv")
citynetH <- subset(citynet, Class=="anthrop")
library(progressr)
handlers("txtprogressbar") 
library(furrr)
library(future)

plan(multisession, workers = floor(parallel::detectCores() * 0.6))

sane(data = citynetH, 
     threshold = 0.1, 
     class.specific = FALSE,
     freq.range = c(20, 20000), 
     class.col = "Class",
     filename.col = "Filename", 
     start.col = "Start..s.",
     end.col = "End..s.",  
     confidence.col = "Confidence",
     audio.dir = "D:\\Urbis_Recs", 
     write.fullM = TRUE, 
     fullM_path = "C:\\Users\\ASUS\\Desktop\\noisecorrect\\full_M.csv",
     write.sane = TRUE, 
     sane_path = "C:\\Users\\ASUS\\Desktop\\noisecorrect\\sane.csv",
     resume = TRUE,
     parallel = TRUE,
     cores.percentage = 0.6)

