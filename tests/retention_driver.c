#include "../TVZPrefs/TVZTouchVizImageRetention.h"
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    size_t removed = 0;
    int result = TVZTouchVizPruneImageDirectory(argv[1], argv[2],
        (const char *const *)(argv + 3), (size_t)(argc - 3), &removed);
    printf("%d %zu\n", result, removed);
    return result ? 1 : 0;
}
