#ifndef UNITY_CONFIG_H
#define UNITY_CONFIG_H

#ifdef __cplusplus
extern "C" {
#endif

void unityOutputStart(unsigned long baudrate);
void unityOutputChar(unsigned int c);
void unityOutputFlush(void);
void unityOutputComplete(void);
unsigned long unityClockMs(void);

#ifdef __cplusplus
}
#endif

// ── Output routing ──
#define UNITY_OUTPUT_START()    unityOutputStart((unsigned long)115200)
#define UNITY_OUTPUT_CHAR(c)    unityOutputChar(c)
#define UNITY_OUTPUT_FLUSH()    unityOutputFlush()
#define UNITY_OUTPUT_COMPLETE() unityOutputComplete()

// ── Features ──
#define UNITY_INCLUDE_PRINT_FORMATTED
#define UNITY_INCLUDE_EXEC_TIME
#define UNITY_CLOCK_MS          unityClockMs
#define UNITY_OUTPUT_COLOR

#endif
