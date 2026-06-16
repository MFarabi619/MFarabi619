#!/usr/bin/env python3
import curses
from time import sleep
import RPi.GPIO as GPIO

AN1, AN2 = 12, 13
DIG1, DIG2 = 26, 24
FREQ = 1000
STEP = 2

def setup():
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    for pin in (AN1, AN2, DIG1, DIG2):
        GPIO.setup(pin, GPIO.OUT)
    p1 = GPIO.PWM(AN1, FREQ)
    p2 = GPIO.PWM(AN2, FREQ)
    p1.start(0)
    p2.start(0)
    return p1, p2


def set_dir(fb_lr):
    if fb_lr == "forward":
        GPIO.output(DIG1, GPIO.HIGH)
        GPIO.output(DIG2, GPIO.LOW)
    elif fb_lr == "backward":
        GPIO.output(DIG1, GPIO.LOW)
        GPIO.output(DIG2, GPIO.HIGH)
    elif fb_lr == "left":
        GPIO.output(DIG1, GPIO.LOW)
        GPIO.output(DIG2, GPIO.LOW)
    elif fb_lr == "right":
        GPIO.output(DIG1, GPIO.HIGH)
        GPIO.output(DIG2, GPIO.HIGH)


def clamp(v, lo=0, hi=100):
    return max(lo, min(hi, v))

def run(stdscr):
    curses.curs_set(0)
    stdscr.nodelay(False)
    stdscr.keypad(True)

    p1, p2 = setup()
    speed = 0
    mode = "stop"
    set_dir("forward")

    def apply_speed(s):
        p1.ChangeDutyCycle(s)
        p2.ChangeDutyCycle(s)

    try:
        while True:
            stdscr.clear()
            stdscr.addstr(0, 0, f"Mode: {mode} | Speed: {speed:3d}%")
            stdscr.addstr(2, 0, "↑/↓: speed ±2%   ←/→: left/right   F: forward   B: backward   SPACE: stop   Q: quit")
            stdscr.refresh()

            ch = stdscr.getch()

            if ch in (ord('q'), ord('Q')):
                break
            elif ch in (ord('f'), ord('F')):
                mode = "forward"
                set_dir("forward")
                apply_speed(speed)
            elif ch in (ord('b'), ord('B')):
                mode = "backward"
                set_dir("backward")
                apply_speed(speed)
            elif ch == curses.KEY_LEFT:
                mode = "left"
                set_dir("left")
                apply_speed(speed)
            elif ch == curses.KEY_RIGHT:
                mode = "right"
                set_dir("right")
                apply_speed(speed)
            elif ch == curses.KEY_UP:
                speed = clamp(speed + STEP)
                apply_speed(speed)
            elif ch == curses.KEY_DOWN:
                speed = clamp(speed - STEP)
                apply_speed(speed)
            elif ch == ord(' '):
                mode = "stop"
                speed = 0
                apply_speed(0)

            sleep(0.01)
    finally:
        p1.ChangeDutyCycle(0)
        p2.ChangeDutyCycle(0)
        p1.stop()
        p2.stop()
        GPIO.cleanup()


if __name__ == "__main__":
    curses.wrapper(run)
