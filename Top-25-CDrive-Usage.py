#!/usr/bin/env python3
# Top-25-CDrive-Usage.py
# Scans C drive and reports top 25 largest files/folders
# Usage: python Top-25-CDrive-Usage.py

import os
import csv
from pathlib import Path
from collections import defaultdict
import sys

def main(root='C:\\', top_n=25, output_file=None):
    if output_file is None:
        output_file = r'C:\Users\Public\top-25-c-drive-usage.csv'
    
    print(f'Scanning {root} ...')
    
    # Single pass: collect all files and compute folder sizes
    file_sizes = []
    folder_sizes = defaultdict(int)
    total_files = 0
    
    for dirpath, dirnames, filenames in os.walk(root, onerror=lambda e: None):
        for fname in filenames:
            fpath = os.path.join(dirpath, fname)
            try:
                size = os.path.getsize(fpath)
                file_sizes.append((fpath, size, 'File'))
                total_files += 1
                
                # Accumulate folder sizes (all parent dirs)
                current = dirpath
                while current and current != root.rstrip('\\'):
                    folder_sizes[current] += size
                    parent = os.path.dirname(current)
                    if parent == current:
                        break
                    current = parent
                folder_sizes[root.rstrip('\\')] += size
            except Exception as e:
                pass
    
    print(f'Files scanned: {total_files}')
    print(f'Folders indexed: {len(folder_sizes)}')
    
    # Convert folder dict to list
    folder_list = [(k, v, 'Folder') for k, v in folder_sizes.items()]
    
    # Combine and sort by size descending
    combined = file_sizes + folder_list
    combined.sort(key=lambda x: x[1], reverse=True)
    top = combined[:top_n]
    
    print(f'\nTop {top_n} largest files/folders on {root}\n')
    print(f'{"FullName":<60} {"Type":<8} {"SizeGB":<10}')
    print('-' * 80)
    
    for path, size, ftype in top:
        size_gb = round(size / (1024**3), 2)
        print(f'{path:<60} {ftype:<8} {size_gb:<10.2f}')
    
    # Export CSV
    try:
        with open(output_file, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['FullName', 'Type', 'SizeGB', 'SizeBytes'])
            for path, size, ftype in top:
                size_gb = round(size / (1024**3), 2)
                writer.writerow([path, ftype, size_gb, size])
        print(f'\nExported: {output_file}')
    except Exception as e:
        print(f'\nWarning: Could not export CSV - {e}')

if __name__ == '__main__':
    main()
