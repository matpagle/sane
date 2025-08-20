# SANE
This repository contains the mighty R function for the SANE computation, a novel acoustic index for measuring anthropogenic noise levels in terrestrial ecosystems.

In case you were wondering, SANE is an acronym that stands for _Selective Anthropogenic Noise Exposure_. Now that we have answered the most fearsome question, let’s move on to less serious things.

The SANE index combines artificial intelligence-based acoustic classifiers and acoustic index to obtain a reliable measurament of the anthropogenic noise in a recording. Specifically, after the classification of the acoustical dataset, made with BirdNET, the Median Amplitude index is computed for each human noise signal identified; SANE will be the sum of the Mean Amplitude index values for each recording.

![alt text](https://github.com/matpagle/sane/blob/main/assets/saneworkflow2.png)

As the main strenghts:
- SANE does not rely on traditional frequency-based discrimination between biophony and anthrophony like other indices, like the NDSI.
- By laveraging artificial intelligence classifier only target sounds is effectively quantified by the SANE index.
- The cumulative nature of the SANE allows to give the right importance to both rare disturbance events of high intensity, and frequent disturbance events with low intensity.

More details are available from our paper.

## How to run BirdNET for Human Noise recognition
BirdNET is an amazing tool that can be run through various support, such as [R](https://github.com/birdnet-team/birdnetR) or [python](https://github.com/birdnet-team/birdnet). A user-friendly [GUI-version](https://github.com/birdnet-team/BirdNET-Analyzer) is also available.
For Human Noise recognition it is necessary to provide to BirdNET an [_ad-hoc_ species list](https://github.com/matpagle/sane/blob/main/human_noise_list.txt) that includes the anthropophony classes it is currently able to detect. This list can be used on its own or combined with other species lists that include taxa of interest.
We strongly recommend the following set up: **precision** = 0.1, **overlap** = 2,  **sensitivity** = 1
## SANE function
It follows a description of what do you need to run the SANE function, which computes the Mean Amplitude index for every human noise signal identified and that will sum them in order to obtain a SANE value for each recording.
### Required libraries
Make sure to have installed "tuneR", "seewave", "dplyr", "progress", "tools". It is not necessary to load any of them, it will be done by the sane function itself.
### Function arguments
- _data_ = the dataset containing the information about the location of signals thoughout each recording. It must be structured similarly to the following one.

| Filename                                 | Start (s) | End (s) | Class  | Confidence |
| ---------------------------------------- | --------- | ------- | ------ | ---------- |
| Ada-Borghese-1/AB01/20240324\_170000.WAV | 0.0       | 3.0     | Engine | 0.9807     |
| Ada-Borghese-1/AB01/20240324\_170000.WAV | 3.0       | 6.0     | Gun    | 0.8176     |
| ...                                      | ...       | ...     | ...    | ...        |

- _threshold_ = the minimum confidence score to achieve the desired level of precision. Default is 0.1. 
- _class.specific_ = logical. This argument determines if the SANE computed will be only global, i.e., of the complessive anthrophony, or global and one for each class of disturbance. Default is FALSE. When "TRUE", the final dataset will include one column for each disturbance class whose name will consists in "SANE" + "Class name".
- _freq.range_ = a vector of length 2 to specify the frequency limits of the analysis (in Hz). Default is the audible spectrum for humans (20-20000 Hz). 
- _class.col_ = a character that specifies the name of the column in data that contains class labels. Default is "Class".
- _filename.col_ = a character that specifies the name of the column in data that contains audio file's path and, consequently, its univoque identifier. Default is "Filename".
- _start.col_ = a character that specifies the name of the column in data that contains the temporal information about the start of a specific acoustic signal/event. Default is "Start..s.". The column must be numeric, indicating the number of seconds from the beginning of the recording.
- _end.col_ = a character that specifies the name of the column in data that contains the temporal information about the end of a specific acoustic signal/event. Default is "End..s.". The column must be numeric, indicating the number of seconds from the beginning of the recording.  
- _confidence.col_ = a character that specifies the name of the column in data that contains the confidence score associated with a certain acoustic signal/event. Default is "Confidence". It must be numeric.
- _audio.dir_ = the path of the cartel containing the audio files. If the cartel contains sub-cartel, be sure that your "Filename" column contain rest of each audio path.
- _write.fullM_ = logical, if TRUE (Default) a csv will be written with all the M indices computed associeted with their acoustic signal. The csv will be written step-by-step, then, Windows-Users do not open it to avoid any kind of error. When FALSE no csv will be written.
- _fullM_path_ = the path for the M dataset csv, it must contain the name of the file that will be written.
- _write.sane_ = logical, if TRUE (Default) a csv will be written with all the SANE indices computed associeted with the respective audio recording. When FALSE no csv will be written.
- _sane_path_ = the path for the SANE dataset csv, it must contain the name of the file that will be written.
- _resume_ = Logical. If TRUE, the function resumes from a previous run by reading the existing `fullM_path` file and skipping already processed entries. This is useful when the process is interrupted and needs to be restarted without repeating completed work. If FALSE (default), all entries are processed from the beginning and any existing `fullM_path` file is ignored. Please note that in case of _write.fullM_= FALSE it will not be possible to resume the computation.
-_parallel_ = logical. If TRUE (default), the function runs in parallel using multiple CPU cores, which can significantly speed up the computation on large datasets. If FALSE, the function runs sequentially on a single core.
-_cores.percentage_ = numeric between 0 and 1, specifying the fraction of available CPU cores to use in parallel processing. Default is 0.5 (half of the available cores). If the computed number of cores is less than 1, at least one core will be used.
-_batch_size_ = integer. The number of rows from the dataset to be processed in each block of work. Default is 100. Lower values can reduce memory usage but increase execution time, while higher values may speed up processing but require more memory.
