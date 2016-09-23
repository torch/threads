#include <stdlib.h>
#include <string.h>

#include "TH.h"
#include "THThread.h"

#if defined(USE_PTHREAD_THREADS)
#include <pthread.h>

#elif defined(USE_WIN32_THREADS)

/* very basic emulation to suit our needs */

#include <process.h>
#include <windows.h>

typedef HANDLE pthread_t;
typedef DWORD pthread_attr_t;
typedef HANDLE pthread_mutex_t;
typedef HANDLE pthread_cond_t;
typedef HANDLE pthread_mutexattr_t;
typedef HANDLE pthread_condattr_t;
typedef unsigned ( __stdcall *THREAD_FUNCTION )( void * );
#define restrict __restrict

static int pthread_create(pthread_t *restrict thread,
                          const pthread_attr_t *restrict attr, void *(*start_routine)(void *),
                          void *restrict arg)
{
  *thread = (HANDLE)_beginthreadex(NULL, 0, (THREAD_FUNCTION)start_routine, arg, 0, NULL);
  return (int)(*thread == NULL);
}

static int pthread_join(pthread_t thread, void **value_ptr)
{
  return ((WaitForSingleObject((thread), INFINITE) != WAIT_OBJECT_0) || !CloseHandle(thread));
}

static int pthread_mutex_init(pthread_mutex_t *restrict mutex,
                              const pthread_mutexattr_t *restrict attr)
{
  *mutex = CreateMutex(NULL, FALSE, NULL);
  return (int)(*mutex == NULL);
}

static int pthread_mutex_lock(pthread_mutex_t *mutex)
{
  return WaitForSingleObject(*mutex, INFINITE) != 0;
}

static int pthread_mutex_unlock(pthread_mutex_t *mutex)
{
  return ReleaseMutex(*mutex) == 0;
}

static int pthread_mutex_destroy(pthread_mutex_t *mutex)
{
  return CloseHandle(*mutex) == 0;
}

static int pthread_cond_init(pthread_cond_t *restrict cond,
                             const pthread_condattr_t *restrict attr)
{
  *cond = CreateEvent(NULL, FALSE, FALSE, NULL);
  return (int)(*cond == NULL);
}

static int pthread_cond_wait(pthread_cond_t *restrict cond,
                             pthread_mutex_t *restrict mutex)
{
  SignalObjectAndWait(*mutex, *cond, INFINITE, FALSE);
  return WaitForSingleObject(*mutex, INFINITE) != 0;
}

static int pthread_cond_destroy(pthread_cond_t *cond)
{
  return CloseHandle(*cond) == 0;
}

int pthread_cond_signal(pthread_cond_t *cond)
{
  return SetEvent(*cond) == 0;
}

#else
#error no thread system available
#endif

struct THThread_ {
  pthread_t id;
  int (*func)(void*);
  THThreadState state;
};

struct THMutex_{
  pthread_mutex_t id;
  int refcount;
};

struct THCondition_ {
  pthread_cond_t id;
  int refcount;
};

THThread* THThread_new(void* (*func)(void*), void *data)
{
  THThread *self = malloc(sizeof(THThread));
  if(!self)
    return NULL;

  self->state.data = data;
  self->state.status = 0;

  if(pthread_create(&self->id, NULL, func, &self->state)) {
    free(self);
    return NULL;
  }
  return self;
}

AddressType THThread_id(THThread *self)
{
  return (AddressType)self;
}

int THThread_free(THThread *self)
{
  int status = 1;
  if(self) {
    if(pthread_join(self->id, NULL))
      return 1;
    status = self->state.status;
    free(self);
  }
  return status;
}

THMutex* THMutex_new(void)
{
  THMutex *self = malloc(sizeof(THMutex));
  if(!self)
    return NULL;
  if(pthread_mutex_init(&self->id, NULL) != 0) {
    free(self);
    return NULL;
  }
  self->refcount = 1;
  return self;
}

THMutex* THMutex_newWithId(AddressType id)
{
  THMutex *self = (THMutex*)id;
  THAtomicIncrementRef(&self->refcount);
  return self;
}

AddressType THMutex_id(THMutex *self)
{
  return (AddressType)self;
}

int THMutex_lock(THMutex *self)
{
  if(pthread_mutex_lock(&self->id) != 0)
    return 1;
  return 0;
}

int THMutex_unlock(THMutex *self)
{
  if(pthread_mutex_unlock(&self->id) != 0)
    return 1;
  return 0;
}

void THMutex_free(THMutex *self)
{
  if(self) {
    if(THAtomicDecrementRef(&self->refcount)) {
      pthread_mutex_destroy(&self->id);
      free(self);
    }
  }
}

THCondition* THCondition_new(void)
{
  THCondition *self = malloc(sizeof(THCondition));
  if(!self)
    return NULL;
  if(pthread_cond_init(&self->id, NULL)) {
    free(self);
    return NULL;
  }
  self->refcount = 1;
  return self;
}

THCondition* THCondition_newWithId(AddressType id)
{
  THCondition *self = (THCondition*)id;
  THAtomicIncrementRef(&self->refcount);
  return self;
}

AddressType THCondition_id(THCondition *self)
{
  return (AddressType)self;
}

int THCondition_signal(THCondition *self)
{
  if(pthread_cond_signal(&self->id))
    return 1;
  return 0;
}

int THCondition_wait(THCondition *self, THMutex *mutex)
{
  if(pthread_cond_wait(&self->id, &mutex->id))
    return 1;
  return 0;
}

void THCondition_free(THCondition *self)
{
  if(self) {
    if(THAtomicDecrementRef(&self->refcount)) {
      pthread_cond_destroy(&self->id);
      free(self);
    }
  }
}
