import os
import sys
import yaml
import pickle
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

sys.path.append('lib')
from prediction.tf_classifier import TFClassifier, HOP_LENGTH


def find_wav_files(root_dir):
    """Recursively find all WAV files in the given directory."""
    return [str(p) for p in Path(root_dir).rglob("*.wav")]


def main():
    import argparse
    parser = argparse.ArgumentParser(description="CityNet audio prediction script")
    parser.add_argument("input_dir", help="Directory containing WAV files (can be nested)")
    parser.add_argument("--output_dir", default="output", help="Directory where results will be saved")
    parser.add_argument("--window_size", type=float, default=3.0, help="Window size (in seconds) for aggregating predictions")
    parser.add_argument("--confidence_threshold", type=float, default=None, help="Minimum confidence threshold for predictions")
    parser.add_argument("--save_plots", choices=["yes", "no"], default="no", help="Whether to save prediction plots")
    args = parser.parse_args()

    save_plots = args.save_plots.lower() == "yes"
    input_dir = args.input_dir
    output_dir = args.output_dir
    window_size = args.window_size
    threshold = args.confidence_threshold

    os.makedirs(output_dir, exist_ok=True)
    plots_dir = os.path.join(output_dir, "plots") if save_plots else None
    if plots_dir:
        os.makedirs(plots_dir, exist_ok=True)

    tabular_csv = os.path.join(output_dir, "tabular_predictions.csv")
    summary_csv = os.path.join(output_dir, "prediction_summaries.csv")
    partial_pkl_path = os.path.join(output_dir, 'partial_predictions.pkl')

    # Initialize CSV files if they don't exist
    if not os.path.exists(summary_csv):
        with open(summary_csv, "w") as f:
            f.write("Filename,Average biotic sound,Average anthropogenic sound\n")

    if not os.path.exists(tabular_csv):
        with open(tabular_csv, "w") as f:
            f.write("Filename,Start (s),End (s),Class,Description,Confidence\n")

    # Load partial predictions if available to resume processing
    preds = {}
    if os.path.exists(partial_pkl_path):
        with open(partial_pkl_path, 'rb') as f:
            preds = pickle.load(f)

    wav_files = find_wav_files(input_dir)
    if not wav_files:
        print("No WAV files found in the specified directory.")
        return

    print(f"-> Found {len(wav_files)} WAV files.")

    for classifier_type in ['biotic', 'anthrop']:
        print(f"-> Loading model: {classifier_type}")
        with open(f'tf_models/{classifier_type}/network_opts.yaml') as f:
            options = yaml.full_load(f)
        model_path = f'tf_models/{classifier_type}/weights_99.pkl-1'
        predictor = TFClassifier(options, model_path)

        for count, filepath in enumerate(wav_files):
            filename = os.path.relpath(filepath, input_dir)

            # Skip files that have already been classified by this model
            if filename in preds and classifier_type in preds[filename]:
                continue

            if not os.path.isfile(filepath) or not filepath.lower().endswith('.wav'):
                print(f"Skipping {filepath} (not a valid WAV file)")
                continue

            print(f"[{classifier_type}] Classifying file {count + 1}/{len(wav_files)}: {filename}")

            if filename not in preds:
                preds[filename] = {}

            preds[filename][classifier_type] = predictor.classify(filepath)

            # Save partial predictions after each file
            with open(partial_pkl_path, 'wb') as f:
                pickle.dump(preds, f, -1)

            # Append summary info only if predictions from both classifiers are available
            if 'biotic' in preds[filename] and 'anthrop' in preds[filename]:
                with open(summary_csv, "a") as f:
                    f.write(f"{filename},{preds[filename]['biotic'].mean():.3f},{preds[filename]['anthrop'].mean():.3f}\n")

            # Save detailed predictions to CSV
            sr = predictor.sample_rate
            this_preds = preds[filename]
            total_duration = next(iter(this_preds.values())).shape[0] * HOP_LENGTH / sr
            num_windows = int(np.ceil(total_duration / window_size))

            with open(tabular_csv, "a") as f:
                for i in range(num_windows):
                    start = i * window_size
                    end = min((i + 1) * window_size, total_duration)

                    start_idx = int(np.floor(start * sr / HOP_LENGTH))
                    end_idx = int(np.ceil(end * sr / HOP_LENGTH))

                    for cls in ['biotic', 'anthrop']:
                        class_vals = this_preds.get(cls)
                        if class_vals is None:
                            continue

                        segment = class_vals[start_idx:end_idx]
                        if len(segment) == 0:
                            continue

                        confidence = float(np.mean(segment))
                        if threshold is None or confidence >= threshold:
                            description = "Biotic sound" if cls == "biotic" else "Anthropogenic sound"
                            f.write(f"{filename},{start:.1f},{end:.1f},{cls},{description},{confidence:.4f}\n")

            # Save plots if requested and predictions from both models exist
            if save_plots and 'biotic' in preds[filename] and 'anthrop' in preds[filename]:
                plt.figure(figsize=(15, 5))
                colors = {'anthrop': 'b', 'biotic': 'g'}
                for key, val in preds[filename].items():
                    length_sec = val.shape[0] * HOP_LENGTH / predictor.sample_rate
                    x = np.linspace(0, length_sec, val.shape[0])
                    plt.plot(x, val, colors[key], label=key)

                plt.xlabel('Time (s)')
                plt.ylabel('Activity level')
                plt.ylim(0, 1.2)
                plt.xlim(0, 60)
                plt.legend()
                plt.title(filename)
                save_name = os.path.splitext(os.path.basename(filename))[0]
                plt.savefig(os.path.join(plots_dir, save_name + ".png"))
                plt.close()

    # Save final predictions
    final_pkl_path = os.path.join(output_dir, 'predictions.pkl')
    with open(final_pkl_path, 'wb') as f:
        pickle.dump(preds, f, -1)

    print(f"-> Done! Results saved to: {output_dir}")


if __name__ == "__main__":
    main()
