# sane
This repository contains the mighty R function for the SANE computation, a novel acoustic index for measuring anthropogenic noise levels in terrestrial ecosystems.
In case you were wondering, SANE is an acronym that stand for _Selective Anthropogenic Noise Exposure_. Now that we have answered the most fearsome question, let’s move on to serious things.
The SANE index combines artificial intelligence-based acoustic classifiers and acoustic index to obtain a reliable measurament of the anthropogenic noise in a recording. Specifically, after the classification of the acoustical dataset, the Median Amplitude index is computed for each human noise signal identified; SANE will be the sum of the Mean Amplitude index values for each recording.
![alt text](https://github.com/matpagle/sane/blob/main/saneworkflow2.png)
As the main strenghts:
- SANE does not rely on traditional frequency-based discrimination between biophony and anthrophony like other indices, like the NDSI.
- By laveraging artificial intelligence classifier only target sounds is effectively quantified.
More details are available from our paper.
## sane function
It follows a description of what do you need to run the sane function.
### required library

