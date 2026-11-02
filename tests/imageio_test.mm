#include "../TVZPrefs/TVZTouchVizImageFrames.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static bool decode(const char *root, const char *name, TVZTouchVizDecodedFrames *out) {
    char path[4096]; snprintf(path,sizeof(path),"%s/%s",root,name);
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8 *)path,strlen(path),false);
    bool ok=TVZTouchVizDecodeFile(url,out); CFRelease(url); return ok;
}

int main(int argc, const char **argv) {
    assert(argc==2);
    TVZTouchVizDecodedFrames out={};
    assert(decode(argv[1],"unequal.gif",&out));
    assert(out.count==3 && out.animated);
    assert(out.repeats[0]==1 && out.repeats[1]==2 && out.repeats[2]==1);
    assert(out.duration>0.399 && out.duration<0.401);
    assert(CGImageGetWidth((CGImageRef)CFArrayGetValueAtIndex(out.frames,0))<=192);
    TVZTouchVizReleaseFrames(&out); assert(!out.frames && !out.count);
    assert(decode(argv[1],"renamed.dat",&out) && out.animated);
    TVZTouchVizReleaseFrames(&out);
    assert(decode(argv[1],"transparent.gif",&out) && out.animated);
    TVZTouchVizReleaseFrames(&out);
    assert(decode(argv[1],"static.png",&out) && !out.animated && out.count==1);
    TVZTouchVizReleaseFrames(&out);
    const char *bad[]={"damaged.gif","truncated.gif","too-many.gif","too-many-pixels.png","missing.gif"};
    for(size_t i=0;i<sizeof(bad)/sizeof(bad[0]);i++) {
        assert(!decode(argv[1],bad[i],&out)); assert(!out.frames && !out.count);
    }
    puts("PASS actual ImageIO decoder: animated/static/renamed/transparent/corrupt/truncated/limits");
}
