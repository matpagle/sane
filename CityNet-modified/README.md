In our paper we utilized both BirdNET and CityNET. To ensure the SANE computation we needed a CityNet output that was not the percentage of seconds containing anthrophony, as intended
in the original pubblication of Fairbrass _et al._ (2018), to which we encourage the reading for details [DOI: 10.1111/2041-210X.13114](https://doi.org/10.1111/2041-210X.13114). 

Thus, we
we modified the [_multi_predict.py_](https://github.com/mdfirman/CityNet/blob/master/multi_predict.py) fuction provided into the [CityNet repository](https://github.com/mdfirman/CityNet/tree/master).
Specifically:
- our script, by default, does not save the activity plots to reduce disk usage. If do you need plots explicit --save_plots yes command-line option.
- The temporal window size used for classification is now user-configurable through the --window_size argument and must be specified according to the desired temporal resolution.
  Originally, CityNet works with 1 second windows, however, to have a better comparison with BirdNET, we used 3 seconds temporal windows.
- With our script, users can specify a minimum confidence threshold using the --confidence_threshold command-line argument, ensuring that only signals with confidence scores above this value are retained in the output.
- The output format has been extended to produce a BirdNET-style CSV file containing detailed confidence scores for both biotic and anthropogenic sound categories within each time window,
  rather than a simple percentage of seconds containing anthrophony. The csv will be written step-by-step to avoid frustrating situation (We speak from experience).

The code we provided itself it is not sufficient for the CityNet classifier, you need to rely on the original repository (link above).

To run it, in the conda prompt:

```bash 
python multi_predict_updated.py "#audio directory (recursive)" --output_dir "#output directory (traditional CityNet output will also be produced)" --window_size 3 --threshold, default none --plot, default no
```

Be sure to put our script into the citynet folder.