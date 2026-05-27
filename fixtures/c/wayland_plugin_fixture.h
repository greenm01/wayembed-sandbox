#ifndef WAYEMBED_SANDBOX_WAYLAND_PLUGIN_FIXTURE_H
#define WAYEMBED_SANDBOX_WAYLAND_PLUGIN_FIXTURE_H

#include <stdbool.h>

struct wl_display;
struct wl_surface;
struct wayembed_c_plugin_fixture;

struct wayembed_c_plugin_fixture *
wayembed_c_plugin_fixture_create(struct wl_display *display);

void wayembed_c_plugin_fixture_destroy(struct wayembed_c_plugin_fixture *fixture);

bool wayembed_c_plugin_fixture_globals_ready(
    const struct wayembed_c_plugin_fixture *fixture);

bool wayembed_c_plugin_fixture_commit_surface(
    struct wayembed_c_plugin_fixture *fixture);

#endif
