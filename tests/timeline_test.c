#include "../TVZPrefs/TVZTouchVizTimeline.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    uint16_t repeats[120] = {0}; double duration = 0;
    const double mixed[] = {0.1,0.2,0.1};
    assert(TVZTouchVizPlanTimeline(mixed,3,repeats,&duration));
    assert(repeats[0]==1 && repeats[1]==2 && repeats[2]==1);
    assert(fabs(duration-0.4)<0.00001);
    const double defaults[] = {0,0.01,0.2};
    assert(TVZTouchVizPlanTimeline(defaults,3,repeats,&duration));
    assert(repeats[0]==1 && repeats[1]==1 && repeats[2]==2);
    const double invalid[] = {NAN};
    assert(!TVZTouchVizPlanTimeline(invalid,1,repeats,&duration));
    const double negative[] = {-1};
    assert(!TVZTouchVizPlanTimeline(negative,1,repeats,&duration));
    double many[121]; for(int i=0;i<121;i++) many[i]=0.1;
    assert(!TVZTouchVizPlanTimeline(many,121,repeats,&duration));
    assert(!TVZTouchVizPlanTimeline(many,0,repeats,&duration));
    for(int i=0;i<120;i++) many[i]=1.01;
    assert(!TVZTouchVizPlanTimeline(many,120,repeats,&duration));
    assert(!TVZTouchVizPlanTimeline(NULL,1,repeats,&duration));
    puts("PASS executable production GIF timeline policy: 9 scenarios");
    return 0;
}
