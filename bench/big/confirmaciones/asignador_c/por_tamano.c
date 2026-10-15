#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1e3+t.tv_nsec/1e6;}
static char* volatile sink[64];
int main(void){
  /* a) coste por malloc+toque+free según el tamaño (20 000 repeticiones) */
  size_t sizes[]={64,512,4096,16384,65536,98304,131072,262144,1048576};
  for(unsigned k=0;k<sizeof(sizes)/sizeof(*sizes);k++){
    size_t S=sizes[k]; int R=20000; double t0=now();
    for(int i=0;i<R;i++){char*q=malloc(S);q[0]=(char)i;q[S-1]=(char)i;sink[0]=q;free(q);sink[0]=0;}
    double t1=now(); printf("  malloc+free de %7zu bytes: %7.2f us por operación\n",S,(t1-t0)*1000.0/R);
  }
  /* b) 4M asignaciones pequeñas de vida corta, sin que el compilador las elimine */
  double t0=now(); for(size_t i=0;i<4000000;i++){char*q=malloc(48);q[0]=(char)i;char*old=sink[i&63];sink[i&63]=q;free(old);} double t1=now();
  for(int i=0;i<64;i++){free(sink[i]);sink[i]=0;}
  printf("  4M malloc(48) de vida corta (rotando 64 vivos): %.0f ms\n",t1-t0);
  return 0;}
