#ifndef TVZ_TOUCHVIZ_IMAGE_RETENTION_H
#define TVZ_TOUCHVIZ_IMAGE_RETENTION_H
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

/* NSUUID image files are owned by the importer. Leave other files and directories alone. */
static inline bool TVZTouchVizIsManagedImage(const char *name) {
    if (!name || strlen(name) < 38 || name[36] != '.') return false;
    for (size_t i = 0; i < 36; i++) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (name[i] != '-') return false;
        } else if (!((name[i] >= '0' && name[i] <= '9') ||
                     (name[i] >= 'A' && name[i] <= 'F') ||
                     (name[i] >= 'a' && name[i] <= 'f'))) return false;
    }
    const char *extensions[] = {"png", "gif", "jpg", "jpeg", "heic", "heif", "webp", "tif",
        "tiff", "bmp", "ico", "avif", "dng", "image", "jfif", "apng", "jp2", "j2k"};
    for (size_t i = 0; i < sizeof(extensions) / sizeof(extensions[0]); i++)
        if (!strcasecmp(name + 37, extensions[i])) return true;
    return false;
}

/* Never recurse or follow links. Keep the committed image and any in-progress import. */
static inline int TVZTouchVizPruneImageDirectory(const char *root, const char *keep,
    const char *const *pending, size_t pendingCount, size_t *removed) {
    if (removed) *removed = 0;
    if (!root || !keep || !keep[0] || keep[0] == '.' || strchr(keep, '/') || strchr(keep, '\\') ||
        (pendingCount && !pending)) return EINVAL;
    int directory = open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directory < 0) return errno;
    if (strcmp(keep, "default.png")) {
        struct stat selected;
        if (fstatat(directory, keep, &selected, AT_SYMLINK_NOFOLLOW)) {
            int error = errno; close(directory); return error;
        }
        if (!S_ISREG(selected.st_mode) || selected.st_size <= 0) {
            close(directory); return EINVAL;
        }
    }
    int scan = dup(directory);
    if (scan < 0) { int error = errno; close(directory); return error; }
    DIR *entries = fdopendir(scan);
    if (!entries) { int error = errno; close(scan); close(directory); return error; }
    int error = 0;
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(entries);
        if (!entry) { if (errno && !error) error = errno; break; }
        const char *name = entry->d_name;
        if (!strcmp(name, keep) || !TVZTouchVizIsManagedImage(name)) continue;
        bool isPending = false;
        for (size_t i = 0; i < pendingCount; i++)
            if (pending[i] && !strcmp(name, pending[i])) { isPending = true; break; }
        if (isPending) continue;
        struct stat candidate;
        if (fstatat(directory, name, &candidate, AT_SYMLINK_NOFOLLOW)) {
            if (errno != ENOENT && !error) error = errno;
            continue;
        }
        if (!S_ISREG(candidate.st_mode) || candidate.st_nlink != 1) continue;
        if (unlinkat(directory, name, 0)) {
            if (errno != ENOENT && !error) error = errno;
        } else if (removed) ++*removed;
    }
    closedir(entries);
    close(directory);
    return error;
}
#endif
