// Loaded into Hyprland on VMware's virtual GPU (vmwgfx). There an app's buffer
// comes back from the import as a vmwgfx surface handle rather than a GEM one,
// Hyprland releases it with drmCloseBufferHandle, which can only free GEM
// handles, and on that failure Hyprland turns the app's window away. So when
// the close fails on a vmwgfx device, the surface is released the way vmwgfx
// expects instead. On any other device, and whenever the close succeeds, the
// call is passed through untouched.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <xf86drm.h>
#include <vmwgfx_drm.h>

#define SELF_NAME "libmainstream-vmwgfx-close.so"

typedef int (*close_fn)(int fd, uint32_t handle);
static close_fn real_close;

// Looked up once at load, while the process is still single threaded, but
// callers may release buffers from several threads at once, so the pointer is
// shared through atomics.
static close_fn next_close(void)
{
    close_fn fn = __atomic_load_n(&real_close, __ATOMIC_ACQUIRE);
    if (!fn) {
        fn = (close_fn)dlsym(RTLD_NEXT, "drmCloseBufferHandle");
        __atomic_store_n(&real_close, fn, __ATOMIC_RELEASE);
    }
    return fn;
}

static int is_vmwgfx(int fd)
{
    drmVersionPtr version = drmGetVersion(fd);
    int match = version && version->name && version->name_len == 6
        && strncmp(version->name, "vmwgfx", 6) == 0;
    if (version)
        drmFreeVersion(version);
    return match;
}

int drmCloseBufferHandle(int fd, uint32_t handle)
{
    close_fn real = next_close();
    if (!real) {
        errno = ENOSYS;
        return -1;
    }

    int ret = real(fd, handle);
    if (ret == 0)
        return 0;
    int saved = errno;
    if (is_vmwgfx(fd)) {
        struct drm_vmw_surface_arg arg = {
            .sid = (int32_t)handle,
            .handle_type = DRM_VMW_HANDLE_LEGACY,
        };
        if (drmCommandWrite(fd, DRM_VMW_UNREF_SURFACE, &arg, sizeof(arg)) == 0)
            return 0;
    }
    errno = saved;
    return ret;
}

// Only Hyprland needs this. The apps it starts inherit its environment, so it
// takes itself out of LD_PRELOAD there.
static void drop_self_from_preload(void)
{
    const char *preload = getenv("LD_PRELOAD");
    if (!preload)
        return;
    size_t len = strlen(preload);
    char *kept = malloc(len + 1);
    char *copy = strdup(preload);
    if (!kept || !copy) {
        free(kept);
        free(copy);
        return;
    }
    kept[0] = '\0';
    char *save = NULL;
    for (char *entry = strtok_r(copy, ": ", &save); entry; entry = strtok_r(NULL, ": ", &save)) {
        const char *base = strrchr(entry, '/');
        if (strcmp(base ? base + 1 : entry, SELF_NAME) == 0)
            continue;
        if (kept[0])
            strcat(kept, ":");
        strcat(kept, entry);
    }
    if (kept[0])
        setenv("LD_PRELOAD", kept, 1);
    else
        unsetenv("LD_PRELOAD");
    free(kept);
    free(copy);
}

__attribute__((constructor)) static void on_load(void)
{
    next_close();
    char exe[4096];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n <= 0)
        return;
    exe[n] = '\0';
    const char *base = strrchr(exe, '/');
    if (strcmp(base ? base + 1 : exe, "Hyprland") != 0)
        return;
    drop_self_from_preload();
}
