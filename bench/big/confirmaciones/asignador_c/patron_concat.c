#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1e3+t.tv_nsec/1e6;}
int main(void){
  /* 1) s = s "x": cada paso reserva len+1, copia y libera el anterior (lo que hace una concatenación por valor) */
  double t0=now(); size_t N=128000; char*s=malloc(1); s[0]=0; size_t len=0;
  for(size_t i=0;i<N;i++){char*n=malloc(len+2);memcpy(n,s,len);n[len]='x';n[len+1]=0;free(s);s=n;len++;}
  double t1=now(); size_t keep=len; free(s);
  /* 2) mismo patrón con realloc (crecimiento in situ si se puede) */
  s=malloc(1); len=0; for(size_t i=0;i<N;i++){s=realloc(s,len+2);s[len++]='x';} free(s);
  double t2=now();
  /* 3) muchas asignaciones pequeñas de vida corta (cierres, texto de interpolación) */
  volatile char*p; for(size_t i=0;i<4000000;i++){char*q=malloc(48);q[0]=(char)i;p=q;free(q);}
  double t3=now();
  /* 4) 1 millón de objetos pequeños vivos a la vez y luego liberados */
  char**v=malloc(sizeof(char*)*1000000); for(int i=0;i<1000000;i++){v[i]=malloc(40);v[i][0]=1;} for(int i=0;i<1000000;i++)free(v[i]); free(v);
  double t4=now();
  printf("copiar+liberar (s=s x, %zu)=%.0f ms | realloc=%.0f ms | 4M malloc/free pequenos=%.0f ms | 1M vivos=%.0f ms  [%zu]\n",N,t1-t0,t2-t1,t3-t2,t4-t3,keep);
  return 0;}
