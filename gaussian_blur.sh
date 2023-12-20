#!/bin/bash

src_dir="img/src"
dest_dir="img/dest"
report_file="report.txt"

for file in $src_dir/*; do
    filename=$(basename "$file")
    dest_file="$dest_dir/$filename"
    ./gauss "$file" "$dest_file" >> "$report.txt"
done
