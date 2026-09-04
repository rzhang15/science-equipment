import os

directory = '../temp/'

try:
    actual_files = set(os.listdir(directory))
    print(f"DEBUG: Found {len(actual_files)} files in '{directory}'")

except FileNotFoundError:
    print(f"Error: The system cannot find the path '{directory}'.")
    exit()

all_missing_files = []

print("Checking ppr files...")
for i in range(1, 5474):
    filename = f"ppr{i}.dta"
    if filename not in actual_files:
        all_missing_files.append(filename)

print("Checking othr_ppr files...")
for i in range(1, 20261):
    filename = f"othr_ppr{i}.dta"
    if filename not in actual_files:
        all_missing_files.append(filename)

output_file = 'missing_files.txt'

if all_missing_files:
    with open(output_file, 'w') as f:
        for missing in all_missing_files:
            f.write(missing + "\n")
    
    print(f"\nSuccess! Found {len(all_missing_files)} missing files.")
    print(f"List saved to: {os.path.abspath(output_file)}")
else:
    print("\nGreat news! No files are missing.")
