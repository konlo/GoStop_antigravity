import os
import shutil

# Paths
SOURCE_DIR = "/Users/najongseong/git_repository/HwaTu_image/origina_svg/png"
DEST_BASE_DIR = "/Users/najongseong/git_repository/GoStop_antigravity/GoStop/Assets.xcassets"

# Mapping: Month Name (Source) -> Month Code (Dest)
MONTH_MAP = {
    "January": "jan",
    "February": "feb",
    "March": "mar",
    "April": "apr",
    "May": "may",
    "June": "jun",
    "July": "jul",
    "August": "aug",
    "September": "sep",
    "October": "oct",
    "November": "nov",
    "December": "dec"
}

# Mapping: Month -> [List of file suffixes or specific filenames in order of index 0, 1, 2, 3]
# Note: Source filenames are like "Hwatu_{Month}_{Type}.png"
# We need to construct the full source filename and map it to index 0, 1, 2, 3

# Helper to generate source filename
def get_source_filename(month_full, suffix):
    return f"Hwatu_{month_full}_{suffix}.png"

# Rules based on Deck.swift and file listing
# Index 0, 1, 2, 3
CARD_MAPPING = {
    "January": ["Hikari", "Tanzaku", "Kasu_1", "Kasu_2"],
    "February": ["Tane", "Tanzaku", "Kasu_1", "Kasu_2"],
    "March": ["Hikari", "Tanzaku", "Kasu_1", "Kasu_2"],
    "April": ["Tane", "Tanzaku", "Kasu_1", "Kasu_2"],
    "May": ["Tane", "Tanzaku", "Kasu_1", "Kasu_2"],
    "June": ["Tane", "Tanzaku", "Kasu_1", "Kasu_2"],
    "July": ["Tane", "Tanzaku", "Kasu_1", "Kasu_2"],
    "August": ["Hikari", "Tane", "Kasu_1", "Kasu_2"],
    "September": ["Tane", "Tanzaku", "Kasu_1", "Kasu_2"],
    "October": ["Tane", "Tanzaku", "Kasu_1", "Kasu_2"],
    "November": ["Hikari", "Kasu_1", "Kasu_2", "Kasu_3"], # Deck.swift: Bright, DoubleJunk, Junk, Junk
    "December": ["Hikari", "Tane", "Tanzaku", "Kasu"]    # Deck.swift: Bright, Animal, Ribbon, DoubleJunk
}

def run_replacement():
    print("Starting replacement...")
    
    success_count = 0
    fail_count = 0
    
    for month_full, suffixes in CARD_MAPPING.items():
        month_code = MONTH_MAP[month_full]
        
        for index, suffix in enumerate(suffixes):
            source_filename = get_source_filename(month_full, suffix)
            source_path = os.path.join(SOURCE_DIR, source_filename)
            
            dest_folder_name = f"Card_{month_code}_{index}.imageset"
            dest_filename = f"Card_{month_code}_{index}.png"
            dest_path = os.path.join(DEST_BASE_DIR, dest_folder_name, dest_filename)
            
            # Check source existence
            if not os.path.exists(source_path):
                print(f"[ERROR] Source not found: {source_path}")
                fail_count += 1
                continue
                
            # Check destination directory existence
            dest_dir = os.path.dirname(dest_path)
            if not os.path.exists(dest_dir):
                print(f"[WARNING] Destination directory does not exist, creating: {dest_dir}")
                os.makedirs(dest_dir)
            
            # Copy
            try:
                shutil.copy2(source_path, dest_path)
                print(f"[OK] Copied {source_filename} -> {dest_filename}")
                success_count += 1
            except Exception as e:
                print(f"[ERROR] Failed to copy {source_filename}: {e}")
                fail_count += 1

    print(f"\nReplacement Complete. Success: {success_count}, Failed: {fail_count}")

if __name__ == "__main__":
    run_replacement()
