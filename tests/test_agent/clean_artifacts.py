import os
import shutil

def clean_artifacts():
    # Resolve directory relative to this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, "../../"))
    artifacts_dir = os.path.join(repo_root, "test_artifacts")
    
    if not os.path.exists(artifacts_dir):
        print(f"Directory '{artifacts_dir}' not found. Nothing to clean.")
        return

    print(f"Cleaning artifacts in {artifacts_dir}...")

    # 1. Clean subdirectories
    subdirs = ["logs", "crash_dumps", "state_snapshots"]
    for subdir in subdirs:
        path = os.path.join(artifacts_dir, subdir)
        if os.path.exists(path):
            print(f"  Cleaning {path}...")
            for filename in os.listdir(path):
                file_path = os.path.join(path, filename)
                try:
                    if os.path.isfile(file_path) or os.path.islink(file_path):
                        os.unlink(file_path)
                    elif os.path.isdir(file_path):
                        shutil.rmtree(file_path)
                except Exception as e:
                    print(f'  Failed to delete {file_path}. Reason: {e}')

    # 2. Clean top-level files in artifacts_dir
    patterns = [
        "repro_steps_",
        "error_report.log",
        "crash_report_"
    ]
    
    for filename in os.listdir(artifacts_dir):
        file_path = os.path.join(artifacts_dir, filename)
        if not os.path.isfile(file_path):
            continue
            
        should_delete = any(filename.startswith(p) for p in patterns) or filename.endswith(".log")
        
        if should_delete:
            try:
                os.unlink(file_path)
                print(f"  Deleted {file_path}")
            except Exception as e:
                print(f'  Failed to delete {file_path}. Reason: {e}')

    print("Cleanup complete.")

if __name__ == "__main__":
    clean_artifacts()
