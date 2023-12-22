#include <iostream>
#include <time.h>
#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "lib/stb_image.h"
#include "lib/stb_image_write.h"

#include <stdio.h>

float *createFilter(int width)
{
    const float sigma = 2.f; // Standard deviation of the Gaussian distribution.

    const int half = width / 2;
    float sum = 0.f;

    // Create convolution matrix
    float *res = (float *)malloc(width * width * sizeof(float));

    // Calculate filter sum first
    for (int r = -half; r <= half; ++r)
    {
        for (int c = -half; c <= half; ++c)
        {
            // e (natural logarithm base) to the power x, where x is what's in the brackets
            float weight = expf(-static_cast<float>(c * c + r * r) / (2.f * sigma * sigma));
            int idx = (r + half) * width + c + half;

            res[idx] = weight;
            sum += weight;
        }
    }

    // Normalize weight: sum of weights must equal 1
    float normal = 1.f / sum;

    for (int r = -half; r <= half; ++r)
    {
        for (int c = -half; c <= half; ++c)
        {
            int idx = (r + half) * width + c + half;

            res[idx] *= normal;
        }
    }
    return res;
}

// Copmute gaussian blur per channel on the GPU.
// Call this function for each of red, green, and blue channels
// Returns blurred channel.
__global__ void ComputeConvolution(unsigned char *const blurredChannel, const unsigned char *const inputChannel, int rows, int cols, float *filter, int filterWidth)
{
    // Filter width should be odd as we are calculating average blur for a pixel plus some offset in all directions

    const int half = filterWidth / 2;
    const int width = cols - 1;
    const int height = rows - 1;

    int tid = blockDim.x * blockIdx.x + threadIdx.x;

    // Compute blur(int c = 0; c < cols; ++c)
    float blur = 0.f;

    // Average pixel color summing up adjacent pixels.
    if (tid < rows * cols)
    {
        for (int i = -half; i <= half; ++i)
        {
            for (int j = -half; j <= half; ++j)
            {
                // Clamp filter to the image border
                int h = min(max(r + i, 0), height);
                int w = min(max(c + j, 0), width);

                // Blur is a product of current pixel value and weight of that pixel.
                // Remember that sum of all weights equals to 1, so we are averaging sum of all pixels by their weight.
                int idx = w + cols * h; // current pixel index
                float pixel = static_cast<float>(inputChannel[idx]);

                idx = (i + half) * filterWidth + j + half;
                float weight = filter[idx];

                blur += pixel * weight;
            }
        }

        blurredChannel[c + cols * r] = static_cast<unsigned char>(blur);
    }
}

void GaussianBlur(uchar4 *const modifiedImage, const uchar4 *const rgba, int rows, int cols, float *filter, int filterWidth, dim3 block, dim3 grid)
{
    const int numPixels = rows * cols;
    const int channelSize = numPixels * sizeof(unsigned char);

    // Create channel variables
    unsigned char *red = new unsigned char[numPixels];
    unsigned char *green = new unsigned char[numPixels];
    unsigned char *blue = new unsigned char[numPixels];

    unsigned char *redBlurred = new unsigned char[numPixels];
    unsigned char *greenBlurred = new unsigned char[numPixels];
    unsigned char *blueBlurred = new unsigned char[numPixels];

    // GPU Device Memory
    unsigned char *channelGPU, *blurredChannelGPU;
    float *filterGPU;
    cudaMalloc(&filterGPU, filterWidth * filterWidth * sizeof(float));
    cudaMalloc(&channelGPU, channelSize);
    cudaMalloc(&blurredChannelGPU, channelSize);

    // Separate RGBAimage into red, green, and blue components
    for (int p = 0; p < numPixels; ++p)
    {
        uchar4 pixel = rgba[p];

        red[p] = pixel.x;
        green[p] = pixel.y;
        blue[p] = pixel.z;
    }

    // Compute convolution for each individual channel
    cudaMemcpy((void *)filterGPU, (void *)filter, filterWidth * filterWidth * sizeof(float), cudaMemcpyHostToDevice);

    /* Red channel */
    cudaMemcpy((void *)channelGPU, (void *)red, channelSize, cudaMemcpyHostToDevice);
    ComputeConvolution<<<grid, block>>>(blurredChannelGPU, channelGPU, rows, cols, filterGPU, filterWidth);
    cudaDeviceSynchronize();

    cudaMemcpy((void *)redBlurred, (void *)blurredChannelGPU, channelSize, cudaMemcpyDeviceToHost);

    /* Green channel */
    cudaMemcpy((void *)channelGPU, (void *)green, channelSize, cudaMemcpyHostToDevice);
    ComputeConvolution<<<grid, block>>>(blurredChannelGPU, channelGPU, rows, cols, filterGPU, filterWidth);
    cudaDeviceSynchronize();

    cudaMemcpy((void *)greenBlurred, (void *)blurredChannelGPU, channelSize, cudaMemcpyDeviceToHost);

    /* Blue channel */
    cudaMemcpy((void *)channelGPU, (void *)blue, channelSize, cudaMemcpyHostToDevice);
    ComputeConvolution<<<grid, block>>>(blurredChannelGPU, channelGPU, rows, cols, filterGPU, filterWidth);
    cudaDeviceSynchronize();

    cudaMemcpy((void *)blueBlurred, (void *)blurredChannelGPU, channelSize, cudaMemcpyDeviceToHost);

    // Recombine channels back into an RGBAimage setting alpha to 255, or fully opaque
    for (int p = 0; p < numPixels; ++p)
    {
        unsigned char r = redBlurred[p];
        unsigned char g = greenBlurred[p];
        unsigned char b = blueBlurred[p];

        modifiedImage[p] = make_uchar4(r, g, b, 255);
    }

    cudaFree(filterGPU);
    cudaFree(channelGPU);
    cudaFree(blurredChannelGPU);

    delete[] red;
    delete[] green;
    delete[] blue;
    delete[] redBlurred;
    delete[] greenBlurred;
    delete[] blueBlurred;
}

// Main entry into the application
int main(int argc, char **argv)
{
    char *imagePath;
    char *outputPath;

    int height, width, bpp, channels = 4;
    uchar4 *originalImage, *blurredImage;

    int filterWidth = 9;
    float *filter = createFilter(filterWidth);

    struct timespec start, end;

    // GPU variables
    dim3 block, grid;

    if (argc > 2)
    {
        imagePath = argv[1];
        outputPath = argv[2];
    }
    else
    {
        printf("Please provide input and output image files as arguments to this application.");
        exit(1);
    }

    // Read the image
    uint8_t *rgb_image = stbi_load(imagePath, &width, &height, &bpp, channels);

    if (rgb_image == NULL)
        printf("Could not load image file: %s\n", imagePath);

    // Allocate and copy
    originalImage = (uchar4 *)malloc(width * height * sizeof(uchar4));
    blurredImage = (uchar4 *)malloc(width * height * sizeof(uchar4));
    printf("Width:%d, Height:%d Size(in Bytes):%d\n", width, height, width * height * bpp * channels);
    for (int i = 0; i < width * height * channels; i++)
    {
        int mod = i % channels;
        switch (mod)
        {
        case 0:
            originalImage[i / channels].x = rgb_image[i];
            break;
        case 1:
            originalImage[i / channels].y = rgb_image[i];
            break;
        case 2:
            originalImage[i / channels].z = rgb_image[i];
            break;
        case 3:
            originalImage[i / channels].w = rgb_image[i];
            break;
        }
    }

    // Calculate block and grid dimensions based on the parameters and the image dimensions
    if (argc > 3)
        block.x = atoi(argv[3]);
    else
        block.x = 128;

    grid.x = ceil((double)width * height / block.x);
    printf("block=%d, grid=%d\n", block.x, grid.x);

    // Apply the gaussian blur over the image with the given filter
    clock_gettime(CLOCK_MONOTONIC, &start);
    GaussianBlur(blurredImage, originalImage, height, width, filter, filterWidth, block, grid);
    clock_gettime(CLOCK_MONOTONIC, &end);

    // Write the image back to disk
    stbi_write_jpg(outputPath, width, height, 4, blurredImage, 100);

    // Debug info
    printf("Time: %Lf\n", (long double)((end.tv_sec - start.tv_sec) * 1000000000 + (end.tv_nsec - start.tv_nsec)) / 1000000000);
    printf("Done!\n");
    return 0;
}
