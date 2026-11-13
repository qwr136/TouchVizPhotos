#include "../LNTouchVisualizer/Private/TVZTouchVizImageControlMath.h"
#include <assert.h>
#include <stdio.h>

static void point(TVZTouchVizPoint p, double x, double y) {
    assert(fabs(p.x-x)<1e-8 && fabs(p.y-y)<1e-8);
}
int main(void) {
    assert(TVZTouchVizPlaybackRate(NAN)==1.0);
    assert(TVZTouchVizPlaybackRate(INFINITY)==1.0);
    assert(TVZTouchVizPlaybackRate(-5)==0.5);
    assert(TVZTouchVizPlaybackRate(9)==5.0);
    assert(TVZTouchVizPlaybackRate(2)==2.0);
    assert(fabs(TVZTouchVizPlaybackDuration(0.4,3)-0.4/3)<1e-8);
    assert(fabs(TVZTouchVizPlaybackDuration(0.4,4)-0.1)<1e-8);
    assert(fabs(TVZTouchVizPlaybackDuration(0.4,5)-0.08)<1e-8);
    assert(fabs(TVZTouchVizPlaybackDuration(0.4,9)-0.08)<1e-8);
    assert(TVZTouchVizPlaybackDuration(0.4,0.5)==0.8);
    assert(TVZTouchVizPlaybackDuration(0.4,1)==0.4);
    assert(TVZTouchVizPlaybackDuration(0.4,2)==0.2);
    assert(TVZTouchVizPlaybackDuration(NAN,1)==0);
    assert(TVZTouchVizPlaybackDuration(-2,1)==0);
    assert(TVZTouchVizImageOffset(NAN)==0);
    assert(TVZTouchVizImageOffset(INFINITY)==0);
    assert(TVZTouchVizImageOffset(-999)==-100);
    assert(TVZTouchVizImageOffset(999)==100);
    point(TVZTouchVizDisplayPoint(200,300,true,30,-40,1,0,0,1),230,260);
    point(TVZTouchVizDisplayPoint(200,300,true,30,-40,0,1,-1,0),240,330);
    point(TVZTouchVizDisplayPoint(200,300,true,30,-40,0,-1,1,0),160,270);
    point(TVZTouchVizDisplayPoint(200,300,true,30,-40,-1,0,0,-1),170,340);
    point(TVZTouchVizDisplayPoint(200,300,false,100,100,1,0,0,1),200,300);
    point(TVZTouchVizDisplayPoint(200,300,true,999,-999,1,0,0,1),300,200);
    point(TVZTouchVizDisplayPoint(200,300,true,NAN,INFINITY,1,0,0,1),200,300);
    point(TVZTouchVizDisplayPoint(200,300,true,30,40,NAN,0,0,1),200,300);
    // Repeated positioning is derived from the raw touch, not an accumulated translation.
    for(int i=0;i<1000;i++)
        point(TVZTouchVizDisplayPoint(200,300,true,30,-40,1,0,0,1),230,260);
    puts("PASS production speed and offset math: defaults, limits, invalid values, four axes and no drift");
}
