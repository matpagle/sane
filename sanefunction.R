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
                 resume = FALSE) {
  
  library(tuneR)
  library(seewave)
  library(dplyr)
  library(progress)
  library(tools)
  
  start_time <- Sys.time()
  
  required_cols <- c(class.col, filename.col, confidence.col, start.col, end.col)
  missing <- setdiff(required_cols, names(data))
  if (length(missing) > 0) {
    stop(paste("Missing required columns in input data:", paste(missing, collapse = ", ")))
  }
  
  data$Class     <- data[[class.col]]
  data$filename  <- data[[filename.col]]
  data$Confidence <- data[[confidence.col]]
  data$Start     <- data[[start.col]]
  data$End       <- data[[end.col]]
  
  if (!is.null(audio.dir)) {
    data$path <- file.path(audio.dir, data$filename)
  } else if (!"path" %in% names(data)) {
    stop("Column 'path' is missing and 'audio.dir' was not provided.")
  }
  
  if (class.specific) {
    data <- data %>%
      group_by(Class) %>%
      filter(Confidence >= threshold) %>%
      ungroup()
  } else {
    data <- data %>%
      filter(Confidence >= threshold)
  }
  
  if (nrow(data) == 0) {
    stop("No data left after filtering by threshold.")
  }
  
  if (write.fullM) dir.create(dirname(fullM_path), recursive = TRUE, showWarnings = FALSE)
  if (write.sane)  dir.create(dirname(sane_path), recursive = TRUE, showWarnings = FALSE)
  
  # --- resume ---
  processed_keys <- character(0)
  if (resume && file.exists(fullM_path)) {
    existing <- read.csv(fullM_path, sep=";", stringsAsFactors = FALSE)
    # Creo chiavi per righe già processate, ad esempio filename + class + confidence
    processed_keys <- paste(existing$filename, existing$Class, existing$Confidence, sep = "___")
  }
  
  completeM <- if(resume && file.exists(fullM_path)) existing else data.frame()
  
  # Creo chiavi per le righe da processare
  all_keys <- paste(data$filename, data$Class, data$Confidence, sep = "___")
  
  to_process <- which(!(all_keys %in% processed_keys))
  
  pb <- txtProgressBar(min = 0, max = length(all_keys), style = 3)

  for (j in seq_along(to_process)) {
    i <- to_process[j]
    
    file_path <- data$path[i]
    ext <- tolower(file_ext(file_path))
    
    if (ext != "wav") {
      stop(paste("Unsupported audio format:", ext, "- only WAV supported."))
    }
    
    audio <- readWave(file_path, from = max(0, data$Start[i]),
                      to = min(300, data$End[i]), unit = "seconds")
    
    fs <- audio@samp.rate
    
    audio <- bwfilter(audio, channel = 1, n = 4,
                      from = freq.range[1], to = freq.range[2], bandpass = TRUE)
    
    M_out <- M(audio, f = fs, channel = 1)
    M_sum <- sum(M_out, na.rm = TRUE)
    
    SANE_col <- if (class.specific) {
      paste0("SANE_", gsub("[^[:alnum:]_]", "_", data$Class[i]))
    } else {
      "SANE"
    }
    
    row_df <- data.frame(filename = data$filename[i],
                         Class = data$Class[i],
                         Confidence = data$Confidence[i])
    row_df[[SANE_col]] <- M_sum
    
    completeM <- bind_rows(completeM, row_df)
    
    if (write.fullM) {
      write.table(row_df, file = fullM_path,
                  sep = ";", row.names = FALSE,
                  col.names = !file.exists(fullM_path) || (j==1 && length(processed_keys)==0),
                  append = TRUE)
    }
    
    setTxtProgressBar(pb, length(processed_keys) + j)
  }
  
  close(pb)
  
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

