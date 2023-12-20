#!/bin/bash

src_image="img/src/mountain_4096.jpg"
ref_image="img/ref/mountain_4096.jpg"
dest_image="img/dest/mountain_4096.jpg"

datetime=$(date +%Y-%m-%d_%H-%M-%S)
report_dir="reports/blocks_$datetime"
report_file="$report_dir/report.txt"

profiling_dir="$report_dir"

# Creates directories. Then, the report file if it does not exists, otherwise delete its content.
mkdir -p $report_dir
> "$report_file"

# Compiles the GPU program.
nvcc codigoCuda.cu -L/usr/lib/x86_64-linux-gnu -o gauss_gpu

# Blur all the images at the src directory, and keep a log of the actions and its results.
# Firstly, executes on GPU.
for x in {1..32}; do
    power_of_two=$(echo "l($x)/l(2)" | bc -l)
    if [[ $power_of_two == *".000000"* ]]; then
        for y in {1..32}; do
            power_of_two=$(echo "l($y)/l(2)" | bc -l)
            if [[ $power_of_two == *".000000"* ]]; then
                if (( (x * y) % 32 == 0 )); then
                    threads=$((x * y))
                    echo "[BLURRING ON GPU] $file (block.x=$x, block.y=$y; TOTAL: $threads threads)" # Debug info
                    echo "[BLURRING ON GPU] $file (block.x=$x, block.y=$y; TOTAL: $threads threads)" >> "$report_file"
                    ./gauss_gpu "$src_image" "$dest_image" "$x" "$y" >> "$report_file"
                    echo >> "$report_file"
                fi
            fi
        done
    fi
done

# Finally, executes while profiling to collect stats. It will require sudo.
for x in {1..32}; do
    power_of_two=$(echo "l($x)/l(2)" | bc -l)
    if [[ $power_of_two == *".000000"* ]]; then
        for y in {1..32}; do
            power_of_two=$(echo "l($y)/l(2)" | bc -l)
            if [[ $power_of_two == *".000000"* ]]; then
                if (( (x * y) % 32 == 0 )); then
                    threads=$((x * y))
                    echo "[PROFILING] $file (block.x=$x, block.y=$y; TOTAL: $threads threads)" # Debug info
                    sudo nvprof -m all ./gauss_gpu "$src_image" "$dest_image" "$x" "$y" &> "$profiling_dir/profile_$x-$y-$threads.txt"
                fi
            fi
        done
    fi
done
