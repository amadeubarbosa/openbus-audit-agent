#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

int count = 0;

pthread_cond_t barrier;
pthread_cond_t start;

pthread_mutex_t lock_start;
pthread_mutex_t lock_count;

void* run(void* args) {
  pthread_t self = pthread_self();

  printf("Hello World Thread 0x%x\n", (unsigned int) self);
  pthread_mutex_lock(&lock_count);
  printf("Count Lock held 0x%x and Value is %d\n", (unsigned int) self, count);

  if (count == 2) {
    printf("Waiting at barrier...\n");
    pthread_cond_wait(&barrier, &lock_count);
    printf("Thread 0x%x Received Its Signal\n", (unsigned int) self);
  }
  count ++;

  pthread_mutex_unlock(&lock_count);
  
  return NULL;
}

void* bypass(void* args) {
  sleep(10);
  pthread_cond_broadcast(&barrier);
}

int main () {

  int i;
  int pool_max = 5;

  pthread_cond_init(&barrier, NULL);
  pthread_mutex_init(&lock_count, NULL);

	pthread_t* threads = malloc(sizeof(pthread_t)*pool_max);
  for (i = 0; i<pool_max; i++) {
   pthread_create(&threads[i], NULL, run, NULL);
  }
  
  pthread_t shouldpass;
  pthread_create(&shouldpass, NULL, bypass, NULL);

  for (i=0; i<pool_max; i++) {
	  printf("Thread 0x%x Joined (status = %d)\n",(unsigned int) threads[i], pthread_join(threads[i], NULL));
  }

  return 0;
}
