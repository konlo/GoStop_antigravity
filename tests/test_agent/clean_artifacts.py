import os
import shutil

def clean_artifacts():
    artifacts_dir = "artifacts"
    
    if not os.path.exists(artifacts_dir):
        print(f"Directory '{artifacts_dir}' not found. Nothing to clean.")
        return

    # List of subdirectories to empty
    subdirs = ["logs", "crash_dumps", "state_snapshots"]
    
    for subdir in subdirs:
        path = os.path.join(artifacts_dir, subdir)
        if os.path.exists(path):
            print(f"Cleaning {path}...")
            # Delete all files in the subdirectory
            for filename in os.listdir(path):
                file_path = os.path.join(path, filename)
                try:
                    if os.path.isfile(file_path) or os.path.islink(file_path):
                        os.unlink(file_path)
                    elif os.path.isdir(file_path):
                        shutil.rmtree(file_path)
                except Exception as e:
                    print(f'Failed to delete {file_path}. Reason: {e}')
        else:
            print(f"Subdirectory '{path}' not found.")

    # Also clean top-level repro_steps and log files
    for filename in os.listdir(artifacts_dir):
        is_repro = filename.startswith("repro_steps_") and filename.endswith(".json")
        is_error_log = filename == "error_report.log"
        is_general_log = filename.endswith(".log")
        
        if is_repro or is_error_log or is_general_log:
            file_path = os.path.join(artifacts_dir, filename)
            try:
                os.unlink(file_path)
                print(f"Deleted {file_path}")
            except Exception as e:
                print(f'Failed to delete {file_path}. Reason: {e}')

    print("Cleanup complete.")

if __name__ == "__main__":
    clean_artifacts()
