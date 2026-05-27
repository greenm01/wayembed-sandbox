#define _GNU_SOURCE

#include "wayland_plugin_fixture.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

struct wayembed_c_plugin_fixture {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct wl_shm *shm;
    struct wl_surface *surface;
    struct wl_buffer *buffer;
    void *shm_data;
    size_t shm_size;
};

static void registry_global(void *data,
                            struct wl_registry *registry,
                            uint32_t name,
                            const char *interface,
                            uint32_t version)
{
    struct wayembed_c_plugin_fixture *fixture = data;
    uint32_t selected = version;

    if (strcmp(interface, "wl_compositor") == 0) {
        if (selected > 4) {
            selected = 4;
        }
        fixture->compositor = wl_registry_bind(
            registry, name, &wl_compositor_interface, selected);
        return;
    }

    if (strcmp(interface, "wl_shm") == 0) {
        if (selected > 1) {
            selected = 1;
        }
        fixture->shm = wl_registry_bind(registry, name, &wl_shm_interface, selected);
    }
}

static void registry_global_remove(void *data,
                                   struct wl_registry *registry,
                                   uint32_t name)
{
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static void fill_pixels(uint32_t *pixels, int32_t width, int32_t height)
{
    for (int32_t y = 0; y < height; ++y) {
        for (int32_t x = 0; x < width; ++x) {
            const uint32_t base =
                (((x / 12) + (y / 12)) % 2) == 0 ? 0xff285a8eu : 0xff6d9f71u;
            pixels[(size_t)y * (size_t)width + (size_t)x] = base;
        }
    }
}

static struct wl_buffer *create_buffer(struct wayembed_c_plugin_fixture *fixture,
                                       int32_t width,
                                       int32_t height)
{
    const int32_t stride = width * 4;
    const size_t size = (size_t)stride * (size_t)height;
    const int fd = memfd_create("wayembed-c-plugin", MFD_CLOEXEC);
    if (fd < 0) {
        return NULL;
    }

    if (ftruncate(fd, (off_t)size) != 0) {
        close(fd);
        return NULL;
    }

    void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        close(fd);
        return NULL;
    }

    fill_pixels(data, width, height);

    struct wl_shm_pool *pool = wl_shm_create_pool(fixture->shm, fd, (int32_t)size);
    if (pool == NULL) {
        munmap(data, size);
        close(fd);
        return NULL;
    }

    struct wl_buffer *buffer = wl_shm_pool_create_buffer(
        pool, 0, width, height, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);

    if (buffer == NULL) {
        munmap(data, size);
        return NULL;
    }

    fixture->shm_data = data;
    fixture->shm_size = size;
    return buffer;
}

struct wayembed_c_plugin_fixture *
wayembed_c_plugin_fixture_create(struct wl_display *display)
{
    if (display == NULL) {
        return NULL;
    }

    struct wayembed_c_plugin_fixture *fixture = calloc(1, sizeof(*fixture));
    if (fixture == NULL) {
        return NULL;
    }

    fixture->display = display;
    fixture->registry = wl_display_get_registry(display);
    if (fixture->registry == NULL) {
        free(fixture);
        return NULL;
    }

    wl_registry_add_listener(fixture->registry, &registry_listener, fixture);
    wl_display_flush(display);
    return fixture;
}

void wayembed_c_plugin_fixture_destroy(struct wayembed_c_plugin_fixture *fixture)
{
    if (fixture == NULL) {
        return;
    }

    if (fixture->buffer != NULL) {
        wl_buffer_destroy(fixture->buffer);
    }
    if (fixture->surface != NULL) {
        wl_surface_destroy(fixture->surface);
    }
    if (fixture->shm != NULL) {
        wl_shm_destroy(fixture->shm);
    }
    if (fixture->compositor != NULL) {
        wl_compositor_destroy(fixture->compositor);
    }
    if (fixture->registry != NULL) {
        wl_registry_destroy(fixture->registry);
    }
    if (fixture->shm_data != NULL && fixture->shm_size > 0) {
        munmap(fixture->shm_data, fixture->shm_size);
    }

    free(fixture);
}

bool wayembed_c_plugin_fixture_globals_ready(
    const struct wayembed_c_plugin_fixture *fixture)
{
    return fixture != NULL && fixture->compositor != NULL && fixture->shm != NULL;
}

bool wayembed_c_plugin_fixture_commit_surface(
    struct wayembed_c_plugin_fixture *fixture)
{
    if (!wayembed_c_plugin_fixture_globals_ready(fixture)) {
        return false;
    }
    if (fixture->surface != NULL) {
        return false;
    }

    const int32_t width = 168;
    const int32_t height = 92;

    fixture->surface = wl_compositor_create_surface(fixture->compositor);
    if (fixture->surface == NULL) {
        return false;
    }

    fixture->buffer = create_buffer(fixture, width, height);
    if (fixture->buffer == NULL) {
        wl_surface_destroy(fixture->surface);
        fixture->surface = NULL;
        return false;
    }

    wl_surface_attach(fixture->surface, fixture->buffer, 0, 0);
    wl_surface_damage(fixture->surface, 0, 0, width, height);
    wl_surface_commit(fixture->surface);
    wl_display_flush(fixture->display);
    return true;
}
