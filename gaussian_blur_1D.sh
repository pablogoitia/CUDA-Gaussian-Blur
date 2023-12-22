#!/bin/bash

file="mountain_4096.jpg"
src_image="img/src/$file"
dest_image="img/dest/mountain_4096.jpg"
datetime=$(date +%Y-%m-%d_%H-%M-%S)

report_dir="reports"
report_file="$report_dir/report_1D_$datetime.txt"

profiling_dir="$report_dir"

# Creates directories. Then, the report file if it does not exists, otherwise delete its content.
mkdir -p $report_dir
> "$report_file"

# Compiles the programs.
nvcc codigoCuda1D.cu -L/usr/lib/x86_64-linux-gnu -o gauss_gpu_1D

# Blur all the images at the src directory, and keep a log of the actions and its results.
# Firstly, executes on GPU.
for x in 32 64 128 256 512 1024; do
    echo "[BLURRING ON GPU] $file (block=$x)" # Debug info
    echo "[BLURRING ON GPU] $file (block=$x)" >> "$report_file"
    ./gauss_gpu "$src_image" "$dest_image" "$x" >> "$report_file"
    echo >> "$report_file"
done

# Finally, executes while profiling to collect stats. It will require sudo.
for x in 32 64 128 256 512 1024; do
    echo "[PROFILING] $file" # Debug info
    sudo nvprof -m all ./gauss_gpu "$src_image" "$dest_image" "$x" &> "$profiling_dir/profile_1D_$x.txt"
done
