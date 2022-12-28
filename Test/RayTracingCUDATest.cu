#include <iostream>
#include <limits>
#include "geommath.hpp"
#include "HitableList.hpp"
#include "Image.hpp"
#include "Ray.hpp"
#include "Sphere.hpp"
#include "TestMaterial.hpp"

using hitable = My::Hitable<float>;
using hitable_ptr = hitable *;
using sphere = My::Sphere<float, material *>;
using image = My::Image;

using hitable_list = My::HitableList<float, hitable_ptr, My::SimpleList<hitable_ptr>>;

#define checkCudaErrors(val) check_cuda((val), #val, __FILE__, __LINE__)
void check_cuda(cudaError_t result, char const *const func,
                const char *const file, int const line) {
    if (result) {
        std::cerr << "CUDA error = " << static_cast<unsigned int>(result)
                  << " at " << file << ":" << line << " '" << func << "' \n";
        cudaDeviceReset();
        exit(99);
    }
}

__device__ color ray_color(const ray& r, hitable_list **world) {
    hit_record rec;
    if ((*world)->Intersect(r, rec, 0.0, FLT_MAX)) {
        return 0.5f * color({rec.getNormal()[0] + 1.0f, rec.getNormal()[1] + 1.0f, rec.getNormal()[2] + 1.0f});
    } else {
        vec3 unit_direction = r.getDirection();
        float t = 0.5f * (unit_direction[1] + 1.0f);
        return (1.0f - t) * color({1.0, 1.0, 1.0}) + t * color({0.5, 0.7, 1.0});
    }
}

__global__ void render(vec3 *fb, int max_x, int max_y, vec3 lower_left_corner, vec3 horizontal, vec3 vertical, vec3 origin, hitable_list **world) {
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    int j = threadIdx.y + blockIdx.y * blockDim.y;
    if ((i < max_x) && (j < max_y)) {
        int pixel_index = j * max_x + i;
        float u = float(i) / float(max_x);
        float v = float(j) / float(max_y);
        ray r(origin, lower_left_corner + u * horizontal + v * vertical);
        fb[pixel_index] = ray_color(r, world);
    }
}

__global__ void create_world(hitable_list **d_world) {
    if (threadIdx.x == 0 && blockIdx.x == 0) {
        *d_world        = new hitable_list;
        (*d_world)->add(hitable_ptr(new sphere(0.5f, point3({0, 0, -1}))));
        (*d_world)->add(hitable_ptr(new sphere(100.0f, point3({0, -100.5, -1}))));
    }
}

__global__ void free_world(hitable_list **d_world) {
    delete *d_world; // the destructor will delete hitables 
}

int main() {
    // Render Settings
    const float aspect_ratio = 16.0 / 9.0;
    const int image_width = 1920;
    const int image_height = static_cast<int>(image_width / aspect_ratio);

    int tile_width = 8;
    int tile_height = 8;

    // Canvas
    image img;
    img.Width = image_width;
    img.Height = image_height;
    img.bitcount = 96;
    img.bitdepth = 32;
    img.pixel_format = My::PIXEL_FORMAT::RGB32;
    img.pitch = (img.bitcount >> 3) * img.Width;
    img.compressed = false;
    img.compress_format = My::COMPRESSED_FORMAT::NONE;
    img.data_size = img.Width * img.Height * (img.bitcount >> 3);

    checkCudaErrors(cudaMallocManaged((void **)&img.data, img.data_size));

    // Camera
    auto viewport_height = 2.0f;
    auto viewport_width = aspect_ratio * viewport_height;
    auto focal_length = 1.0f;

    auto origin = point3({0, 0, 0});
    auto horizontal = vec3({viewport_width, 0, 0});
    auto vertical = vec3({0, viewport_height, 0});
    auto lower_left_corner = origin - horizontal / 2.0f - vertical / 2.0f - vec3({0, 0, focal_length});

    // World
    hitable_list **d_world;
    checkCudaErrors(cudaMalloc((void **)&d_world, sizeof(hitable_list *)));
    create_world<<<1, 1>>>(d_world);

    checkCudaErrors(cudaGetLastError());
    checkCudaErrors(cudaDeviceSynchronize());

    // Rendering
    dim3 blocks(image_width / tile_width + 1, image_height / tile_height + 1);
    dim3 threads(tile_width, tile_height);
    render<<<blocks, threads>>>(reinterpret_cast<vec3 *>(img.data), image_width, image_height, lower_left_corner, horizontal, vertical, origin, d_world);

    checkCudaErrors(cudaGetLastError());
    checkCudaErrors(cudaDeviceSynchronize());

    img.SaveTGA("raytracing_cuda.tga");
    
    free_world<<<1, 1>>>(d_world);
    checkCudaErrors(cudaGetLastError());

    checkCudaErrors(cudaFree(d_world));
    checkCudaErrors(cudaFree(img.data));
    img.data = nullptr; // to avoid double free

    return 0;
}