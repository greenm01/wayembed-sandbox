// SPDX-License-Identifier: MIT
#include "wayembed.h"
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/gui/iwaylandframe.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivsthostapplication.h"
#include "public.sdk/source/main/pluginfactory.h"

extern "C" {
#include "xdg-shell-client-protocol.h"
}

#include <dlfcn.h>
#include <poll.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

using namespace Steinberg;
using namespace Steinberg::Vst;

static bool sameIid(const TUID a, const TUID b)
{
    return std::memcmp(a, b, sizeof(TUID)) == 0;
}

static void fail(const char *message)
{
    std::fprintf(stderr, "wayembed-vst3-host-smoke: %s\n", message);
    std::exit(1);
}

static void check(bool condition, const char *message)
{
    if (!condition) {
        fail(message);
    }
}

static std::string defaultPluginPath()
{
    const char *env = std::getenv("WAYEMBED_VST3_PLUGIN");
    if (env && env[0]) {
        return env;
    }
    return "/home/niltempus/dev/nilamp/native/bin/nilamp-twd-mkii.vst3";
}

struct HostSurface {
    wl_display *display = nullptr;
    wl_registry *registry = nullptr;
    wl_compositor *compositor = nullptr;
    wl_subcompositor *subcompositor = nullptr;
    wl_shm *shm = nullptr;
    xdg_wm_base *wmBase = nullptr;
    wl_surface *surface = nullptr;
    xdg_surface *xdgSurface = nullptr;
    xdg_toplevel *toplevel = nullptr;
    wl_buffer *buffer = nullptr;
    void *shmData = nullptr;
    size_t shmSize = 0;
    int32_t width = 760;
    int32_t height = 520;
    bool configured = false;
    bool closed = false;
};

static void closeFd(int fd)
{
    (void)::close(fd);
}

static void fillHostPixels(uint32_t *pixels, int32_t width, int32_t height)
{
    for (int32_t y = 0; y < height; y++) {
        for (int32_t x = 0; x < width; x++) {
            const uint32_t color =
                (((x / 32) + (y / 32)) % 2) == 0 ? 0xff253040u : 0xff314050u;
            pixels[(size_t)y * (size_t)width + (size_t)x] = color;
        }
    }
}

static wl_buffer *createBuffer(HostSurface &host)
{
    const int32_t stride = host.width * 4;
    const size_t size = (size_t)stride * (size_t)host.height;
    const int fd = memfd_create("wayembed-vst3-host", MFD_CLOEXEC);
    if (fd < 0) {
        return nullptr;
    }
    if (ftruncate(fd, (off_t)size) != 0) {
        closeFd(fd);
        return nullptr;
    }
    void *data = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        closeFd(fd);
        return nullptr;
    }
    fillHostPixels(static_cast<uint32_t *>(data), host.width, host.height);
    wl_shm_pool *pool = wl_shm_create_pool(host.shm, fd, static_cast<int32_t>(size));
    if (!pool) {
        munmap(data, size);
        closeFd(fd);
        return nullptr;
    }
    wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, host.width, host.height,
                                                  stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    closeFd(fd);
    if (!buffer) {
        munmap(data, size);
        return nullptr;
    }
    host.shmData = data;
    host.shmSize = size;
    return buffer;
}

static void registryGlobal(void *data, wl_registry *registry, uint32_t name,
                           const char *interface, uint32_t version)
{
    HostSurface *host = static_cast<HostSurface *>(data);
    const uint32_t v4 = std::min<uint32_t>(version, 4);
    if (std::strcmp(interface, "wl_compositor") == 0) {
        host->compositor = static_cast<wl_compositor *>(
            wl_registry_bind(registry, name, &wl_compositor_interface, v4));
    } else if (std::strcmp(interface, "wl_subcompositor") == 0) {
        host->subcompositor = static_cast<wl_subcompositor *>(
            wl_registry_bind(registry, name, &wl_subcompositor_interface, 1));
    } else if (std::strcmp(interface, "wl_shm") == 0) {
        host->shm = static_cast<wl_shm *>(
            wl_registry_bind(registry, name, &wl_shm_interface, 1));
    } else if (std::strcmp(interface, "xdg_wm_base") == 0) {
        host->wmBase = static_cast<xdg_wm_base *>(
            wl_registry_bind(registry, name, &xdg_wm_base_interface,
                             std::min<uint32_t>(version, 7)));
    }
}

static void registryGlobalRemove(void *, wl_registry *, uint32_t) {}

static const wl_registry_listener registryListener = {
    registryGlobal,
    registryGlobalRemove,
};

static void wmBasePing(void *, xdg_wm_base *wmBase, uint32_t serial)
{
    xdg_wm_base_pong(wmBase, serial);
}

static const xdg_wm_base_listener wmBaseListener = {
    wmBasePing,
};

static void xdgSurfaceConfigure(void *data, xdg_surface *surface, uint32_t serial)
{
    HostSurface *host = static_cast<HostSurface *>(data);
    xdg_surface_ack_configure(surface, serial);
    if (!host->buffer) {
        host->buffer = createBuffer(*host);
    }
    if (host->buffer) {
        wl_surface_attach(host->surface, host->buffer, 0, 0);
        wl_surface_damage(host->surface, 0, 0, host->width, host->height);
    }
    wl_surface_commit(host->surface);
    host->configured = true;
}

static const xdg_surface_listener xdgSurfaceListener = {
    xdgSurfaceConfigure,
};

static void toplevelConfigure(void *, xdg_toplevel *, int32_t, int32_t, wl_array *) {}

static void toplevelClose(void *data, xdg_toplevel *)
{
    static_cast<HostSurface *>(data)->closed = true;
}

static void toplevelConfigureBounds(void *, xdg_toplevel *, int32_t, int32_t) {}

static void toplevelWmCapabilities(void *, xdg_toplevel *, wl_array *) {}

static const xdg_toplevel_listener toplevelListener = {
    toplevelConfigure,
    toplevelClose,
    toplevelConfigureBounds,
    toplevelWmCapabilities,
};

static void openHostSurface(HostSurface &host)
{
    host.display = wl_display_connect(nullptr);
    check(host.display != nullptr, "failed to connect to Wayland compositor");
    host.registry = wl_display_get_registry(host.display);
    wl_registry_add_listener(host.registry, &registryListener, &host);
    check(wl_display_roundtrip(host.display) >= 0, "Wayland registry roundtrip failed");
    check(host.compositor && host.subcompositor && host.shm && host.wmBase,
          "compositor is missing required Wayland globals");
    xdg_wm_base_add_listener(host.wmBase, &wmBaseListener, &host);
    host.surface = wl_compositor_create_surface(host.compositor);
    host.xdgSurface = xdg_wm_base_get_xdg_surface(host.wmBase, host.surface);
    host.toplevel = xdg_surface_get_toplevel(host.xdgSurface);
    xdg_surface_add_listener(host.xdgSurface, &xdgSurfaceListener, &host);
    xdg_toplevel_add_listener(host.toplevel, &toplevelListener, &host);
    xdg_toplevel_set_title(host.toplevel, "wayembed VST3 host smoke");
    xdg_toplevel_set_app_id(host.toplevel, "wayembed-vst3-host-smoke");
    wl_surface_commit(host.surface);
    wl_display_flush(host.display);
}

static void closeHostSurface(HostSurface &host)
{
    if (host.buffer) {
        wl_buffer_destroy(host.buffer);
    }
    if (host.shmData && host.shmSize > 0) {
        munmap(host.shmData, host.shmSize);
    }
    if (host.toplevel) {
        xdg_toplevel_destroy(host.toplevel);
    }
    if (host.xdgSurface) {
        xdg_surface_destroy(host.xdgSurface);
    }
    if (host.surface) {
        wl_surface_destroy(host.surface);
    }
    if (host.wmBase) {
        xdg_wm_base_destroy(host.wmBase);
    }
    if (host.shm) {
        wl_shm_destroy(host.shm);
    }
    if (host.subcompositor) {
        wl_subcompositor_destroy(host.subcompositor);
    }
    if (host.compositor) {
        wl_compositor_destroy(host.compositor);
    }
    if (host.registry) {
        wl_registry_destroy(host.registry);
    }
    if (host.display) {
        wl_display_disconnect(host.display);
    }
}

struct Scenario {
    HostSurface *host = nullptr;
    wayembed_server *server = nullptr;
    wayembed_client *client = nullptr;
    wayembed_embed *embed = nullptr;
    wl_surface *child = nullptr;
    uint32_t attachStatus = WAYEMBED_EMBED_STATUS_INVALID_ARGUMENT;
    int connected = 0;
    int closed = 0;
    int surfaceCreated = 0;
    int mapped = 0;
    int resized = 0;
};

static wl_compositor *hostCompositor(void *userdata)
{
    return static_cast<Scenario *>(userdata)->host->compositor;
}

static wl_subcompositor *hostSubcompositor(void *userdata)
{
    return static_cast<Scenario *>(userdata)->host->subcompositor;
}

static wl_shm *hostShm(void *userdata)
{
    return static_cast<Scenario *>(userdata)->host->shm;
}

static xdg_wm_base *hostXdgWmBase(void *userdata)
{
    return static_cast<Scenario *>(userdata)->host->wmBase;
}

static void onClientConnected(void *userdata, wayembed_client *client)
{
    Scenario *scenario = static_cast<Scenario *>(userdata);
    scenario->connected++;
    scenario->client = client;
}

static void onClientClosed(void *userdata, wayembed_client *)
{
    static_cast<Scenario *>(userdata)->closed++;
}

static void onSurfaceCreated(void *userdata, wayembed_client *client,
                             wl_surface *pluginChildSurface)
{
    Scenario *scenario = static_cast<Scenario *>(userdata);
    scenario->surfaceCreated++;
    scenario->child = pluginChildSurface;
    wayembed_embed_attach_info info = {};
    info.size = sizeof(info);
    info.version = WAYEMBED_ABI_VERSION;
    info.client = client;
    info.parent_surface = scenario->host->surface;
    info.child_surface = pluginChildSurface;
    scenario->attachStatus = wayembed_embed_attach(&info, &scenario->embed);
}

static void onEmbedMapped(void *userdata, wayembed_embed *embed)
{
    if (embed && wayembed_embed_id(embed) != 0) {
        static_cast<Scenario *>(userdata)->mapped++;
    }
}

static void onEmbedResized(void *userdata, wayembed_embed *embed, int32_t width,
                           int32_t height)
{
    if (embed && wayembed_embed_id(embed) != 0 && width > 0 && height > 0) {
        static_cast<Scenario *>(userdata)->resized++;
    }
}

class HostApp final : public IHostApplication,
                      public IWaylandHost,
                      public Linux::IRunLoop {
public:
    explicit HostApp(wayembed_server *serverIn) : server(serverIn) {}

    wl_display *prepareWaylandConnection()
    {
        preparedDisplay = wayembed_server_open_client_display(server);
        return preparedDisplay;
    }

    tresult PLUGIN_API queryInterface(const TUID queryIid, void **obj) SMTG_OVERRIDE
    {
        if (!obj) {
            return kInvalidArgument;
        }
        if (sameIid(queryIid, INLINE_UID_OF(IHostApplication)) ||
            sameIid(queryIid, INLINE_UID_OF(FUnknown))) {
            *obj = static_cast<IHostApplication *>(this);
        } else if (sameIid(queryIid, INLINE_UID_OF(IWaylandHost))) {
            *obj = static_cast<IWaylandHost *>(this);
        } else if (sameIid(queryIid, INLINE_UID_OF(Linux::IRunLoop))) {
            *obj = static_cast<Linux::IRunLoop *>(this);
        } else {
            *obj = nullptr;
            return kNoInterface;
        }
        addRef();
        return kResultOk;
    }

    uint32 PLUGIN_API addRef() SMTG_OVERRIDE { return ++refs; }
    uint32 PLUGIN_API release() SMTG_OVERRIDE { return refs > 1 ? --refs : refs; }

    tresult PLUGIN_API getName(String128 name) SMTG_OVERRIDE
    {
        if (!name) {
            return kInvalidArgument;
        }
        const char *text = "wayembed VST3 smoke";
        for (size_t i = 0; i < 128; i++) {
            name[i] = i < std::strlen(text) ? static_cast<TChar>(text[i]) : 0;
        }
        return kResultOk;
    }

    tresult PLUGIN_API createInstance(TUID cid, TUID iid, void **obj) SMTG_OVERRIDE
    {
        if (!obj) {
            return kInvalidArgument;
        }
        *obj = nullptr;
        if (sameIid(cid, INLINE_UID_OF(IWaylandHost)) &&
            sameIid(iid, INLINE_UID_OF(IWaylandHost))) {
            *obj = static_cast<IWaylandHost *>(this);
            addRef();
            return kResultOk;
        }
        return kNoInterface;
    }

    wl_display *PLUGIN_API openWaylandConnection() SMTG_OVERRIDE
    {
        if (preparedDisplay) {
            activeDisplays.push_back(preparedDisplay);
            wl_display *result = preparedDisplay;
            preparedDisplay = nullptr;
            return result;
        }
        wl_display *display = wayembed_server_open_client_display(server);
        if (display) {
            activeDisplays.push_back(display);
        }
        return display;
    }

    tresult PLUGIN_API closeWaylandConnection(wl_display *display) SMTG_OVERRIDE
    {
        if (!display) {
            return kInvalidArgument;
        }
        activeDisplays.erase(std::remove(activeDisplays.begin(), activeDisplays.end(),
                                         display),
                             activeDisplays.end());
        return wayembed_server_close_client_display(server, display) ? kResultOk :
                                                                       kResultFalse;
    }

    tresult PLUGIN_API registerEventHandler(Linux::IEventHandler *, Linux::FileDescriptor)
        SMTG_OVERRIDE
    {
        return kResultTrue;
    }

    tresult PLUGIN_API unregisterEventHandler(Linux::IEventHandler *) SMTG_OVERRIDE
    {
        return kResultTrue;
    }

    tresult PLUGIN_API registerTimer(Linux::ITimerHandler *, Linux::TimerInterval)
        SMTG_OVERRIDE
    {
        return kResultTrue;
    }

    tresult PLUGIN_API unregisterTimer(Linux::ITimerHandler *) SMTG_OVERRIDE
    {
        return kResultTrue;
    }

private:
    wayembed_server *server = nullptr;
    wl_display *preparedDisplay = nullptr;
    std::vector<wl_display *> activeDisplays;
    uint32 refs = 1;
};

class PlugFrame final : public IPlugFrame, public IWaylandFrame {
public:
    PlugFrame(wl_surface *parentIn, wl_proxy *parentProxyIn)
        : parent(parentIn), parentProxy(parentProxyIn)
    {
    }

    tresult PLUGIN_API queryInterface(const TUID queryIid, void **obj) SMTG_OVERRIDE
    {
        if (!obj) {
            return kInvalidArgument;
        }
        if (sameIid(queryIid, INLINE_UID_OF(IPlugFrame)) ||
            sameIid(queryIid, INLINE_UID_OF(FUnknown))) {
            *obj = static_cast<IPlugFrame *>(this);
        } else if (sameIid(queryIid, INLINE_UID_OF(IWaylandFrame))) {
            *obj = static_cast<IWaylandFrame *>(this);
        } else {
            *obj = nullptr;
            return kNoInterface;
        }
        addRef();
        return kResultOk;
    }

    uint32 PLUGIN_API addRef() SMTG_OVERRIDE { return ++refs; }
    uint32 PLUGIN_API release() SMTG_OVERRIDE { return refs > 1 ? --refs : refs; }

    tresult PLUGIN_API resizeView(IPlugView *view, ViewRect *newSize) SMTG_OVERRIDE
    {
        return view && newSize ? view->onSize(newSize) : kInvalidArgument;
    }

    wl_surface *PLUGIN_API getWaylandSurface(wl_display *) SMTG_OVERRIDE
    {
        return reinterpret_cast<wl_surface *>(parentProxy ? parentProxy : (wl_proxy *)parent);
    }

    xdg_surface *PLUGIN_API getParentSurface(ViewRect &, wl_display *) SMTG_OVERRIDE
    {
        return nullptr;
    }

    xdg_toplevel *PLUGIN_API getParentToplevel(wl_display *) SMTG_OVERRIDE
    {
        return nullptr;
    }

private:
    wl_surface *parent = nullptr;
    wl_proxy *parentProxy = nullptr;
    uint32 refs = 1;
};

static void pump(Scenario &scenario, wl_display *pluginDisplay, int durationMs)
{
    int remaining = durationMs;
    while (remaining > 0 && !scenario.host->closed) {
        if (pluginDisplay) {
            wl_display_flush(pluginDisplay);
        }
        wayembed_server_dispatch(scenario.server);
        wayembed_server_flush(scenario.server);
        wl_display_flush(scenario.host->display);

        pollfd fds[3] = {};
        fds[0].fd = wl_display_get_fd(scenario.host->display);
        fds[0].events = POLLIN;
        fds[1].fd = wayembed_server_get_fd(scenario.server);
        fds[1].events = POLLIN;
        fds[2].fd = pluginDisplay ? wl_display_get_fd(pluginDisplay) : -1;
        fds[2].events = pluginDisplay ? POLLIN : 0;
        const int wait = std::min(remaining, 20);
        const int result = poll(fds, pluginDisplay ? 3 : 2, wait);
        if (result < 0) {
            fail("poll failed");
        }
        if (fds[0].revents & POLLIN) {
            check(wl_display_dispatch(scenario.host->display) >= 0,
                  "host Wayland dispatch failed");
        } else {
            wl_display_dispatch_pending(scenario.host->display);
        }
        if (pluginDisplay && (fds[2].revents & POLLIN)) {
            check(wl_display_dispatch(pluginDisplay) >= 0,
                  "plugin Wayland dispatch failed");
        } else if (pluginDisplay) {
            wl_display_dispatch_pending(pluginDisplay);
        }
        remaining -= wait;
    }
}

int main(int argc, char **argv)
{
    const std::string pluginPath = argc > 1 ? argv[1] : defaultPluginPath();
    HostSurface host;
    openHostSurface(host);

    Scenario scenario;
    scenario.host = &host;
    wayembed_host_interface hostInterface = {};
    hostInterface.size = sizeof(hostInterface);
    hostInterface.version = WAYEMBED_ABI_VERSION;
    hostInterface.userdata = &scenario;
    hostInterface.get_compositor = hostCompositor;
    hostInterface.get_subcompositor = hostSubcompositor;
    hostInterface.get_shm = hostShm;
    hostInterface.get_xdg_wm_base = hostXdgWmBase;
    hostInterface.on_client_connected = onClientConnected;
    hostInterface.on_client_closed = onClientClosed;
    hostInterface.on_surface_created = onSurfaceCreated;
    hostInterface.on_embed_mapped = onEmbedMapped;
    hostInterface.on_embed_resized = onEmbedResized;

    scenario.server = wayembed_server_create(&hostInterface, nullptr);
    check(scenario.server != nullptr, "wayembed_server_create failed");
    HostApp hostApp(scenario.server);
    wl_display *pluginDisplay = hostApp.prepareWaylandConnection();
    check(pluginDisplay != nullptr, "open client display failed");
    wayembed_server_dispatch(scenario.server);
    check(scenario.connected == 1, "prepared client did not connect");

    wl_proxy *parentProxy = wayembed_server_create_proxy(
        scenario.server, pluginDisplay, reinterpret_cast<wl_proxy *>(host.surface));
    if (!parentProxy) {
        std::fprintf(stderr,
                     "wayembed-vst3-host-smoke: parent proxy unavailable; using "
                     "controlled nilamp smoke parent\n");
    }
    void *parentForPlugin = parentProxy ? static_cast<void *>(parentProxy) :
                                          static_cast<void *>(host.surface);

    const std::string libraryPath =
        pluginPath + "/Contents/x86_64-linux/nilamp-twd-mkii.so";
    void *module = dlopen(libraryPath.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!module) {
        std::fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 1;
    }
    using ModuleEntryFn = bool (*)(void *);
    using ModuleExitFn = bool (*)(void);
    using GetFactoryFn = IPluginFactory *(*)();
    auto moduleEntry = reinterpret_cast<ModuleEntryFn>(dlsym(module, "ModuleEntry"));
    auto moduleExit = reinterpret_cast<ModuleExitFn>(dlsym(module, "ModuleExit"));
    auto getFactory = reinterpret_cast<GetFactoryFn>(dlsym(module, "GetPluginFactory"));
    check(moduleEntry && moduleExit && getFactory, "missing VST3 entry points");
    check(moduleEntry(module), "ModuleEntry failed");

    IPluginFactory *factory = getFactory();
    check(factory != nullptr, "missing VST3 factory");
    IPluginFactory3 *factory3 = nullptr;
    if (factory->queryInterface(INLINE_UID_OF(IPluginFactory3),
                                reinterpret_cast<void **>(&factory3)) == kResultOk) {
        (void)factory3->setHostContext(
            static_cast<FUnknown *>(static_cast<IHostApplication *>(&hostApp)));
        factory3->release();
    }

    TUID controllerUid = INLINE_UID(0x66e72a3a, 0x9187500d, 0xafa4d86a, 0x88935c65);
    IEditController *controller = nullptr;
    check(factory->createInstance(controllerUid, INLINE_UID_OF(IEditController),
                                  reinterpret_cast<void **>(&controller)) == kResultOk,
          "controller create failed");
    check(controller->initialize(
              static_cast<FUnknown *>(static_cast<IHostApplication *>(&hostApp))) ==
              kResultOk,
          "controller initialize failed");
    IPlugView *view = controller->createView(ViewType::kEditor);
    check(view != nullptr, "editor view create failed");
    check(view->isPlatformTypeSupported(kPlatformTypeWaylandSurfaceID) == kResultTrue,
          "editor does not support WaylandSurfaceID");

    PlugFrame frame(host.surface, parentProxy);
    check(view->setFrame(&frame) == kResultOk, "setFrame failed");
    check(view->attached(parentForPlugin, kPlatformTypeWaylandSurfaceID) == kResultOk,
          "WaylandSurfaceID attach failed");
    pump(scenario, pluginDisplay, 1000);

    check(scenario.surfaceCreated == 1, "plugin child surface was not created");
    check(scenario.attachStatus == WAYEMBED_EMBED_STATUS_OK, "wayembed embed attach failed");
    check(scenario.embed != nullptr, "wayembed embed handle missing");
    check(scenario.mapped >= 1, "embedded surface did not map");
    check(wayembed_embed_resize(scenario.embed, 640, 360) == WAYEMBED_EMBED_STATUS_OK,
          "embed resize failed");
    pump(scenario, pluginDisplay, 200);
    check(scenario.resized >= 1, "embed resize callback did not fire");

    check(view->removed() == kResultOk, "view removed failed");
    view->release();
    controller->terminate();
    controller->release();
    factory->release();
    check(moduleExit(), "ModuleExit failed");
    check(dlclose(module) == 0, "dlclose failed");
    wayembed_server_destroy(scenario.server);
    closeHostSurface(host);

    std::printf("vst3-host-smoke ok plugin=%s connected=%d surface_created=%d mapped=%d resized=%d\n",
                pluginPath.c_str(), scenario.connected, scenario.surfaceCreated,
                scenario.mapped, scenario.resized);
    return 0;
}
