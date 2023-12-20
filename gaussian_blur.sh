#!/bin/bash

src_dir="img/src"
ref_dir="img/ref"
dest_dir="img/dest"
datetime=$(date +%Y-%m-%d_%H-%M-%S)
report_dir="reports"
report_file="$report_dir/report_$datetime.txt"
report_prof_dir="reports/profile_$datetime"

# Creates directories. Then, the report file if it does not exists, otherwise delete its content.
mkdir -p $report_dir $report_prof_dir
> "$report_file"

# Compiles the programs.
nvcc codigoBase.cu -L/usr/lib/x86_64-linux-gnu -o gauss_cpu
nvcc codigoCuda.cu -L/usr/lib/x86_64-linux-gnu -o gauss_gpu

# Blur all the images at the src directory, and keep a log of the actions and its results.
# Firstly, executes sequentially on CPU.
for file in $src_dir/*; do
    filename=$(basename "$file")
    dest_file="$ref_dir/$filename"
    echo "[BLURRING ON CPU] $file" # Debug info
    echo "[BLURRING ON CPU] $file" >> "$report_file"
    ./gauss_cpu "$file" "$dest_file" >> "$report_file"
    echo >> "$report_file"
done

# Then, executes on GPU.
for file in $src_dir/*; do
    filename=$(basename "$file")
    dest_file="$dest_dir/$filename"
    echo "[BLURRING ON GPU] $file" # Debug info
    echo "[BLURRING ON GPU] $file" >> "$report_file"
    ./gauss_gpu "$file" "$dest_file" >> "$report_file"
    echo >> "$report_file"
done

# Finally, executes while profiling to collect stats. It will require sudo.
for file in $src_dir/*; do
    filename=$(basename "$file")
    dest_file="$dest_dir/$filename"
    echo "[PROFILING] $file" # Debug info
    prof_file="$(basename "$file" .jpg)"
    sudo nvprof -m all ./gauss_gpu "$file" "$dest_file" &> "$report_prof_dir/$prof_file.txt"
done
