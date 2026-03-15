target remote :1337

load

set print asm-demangle on
set print pretty on
set style sources on

# Initialize monitoring so iprintln! macro output
# is sent from the itm port to itm.txt
monitor tpiu config internal itm.txt uart off 8000000

# Turn on the itm port
monitor itm port 0 on

# Set a breakpoint at main, aka entry
break main

# Set a breakpoint at DefaultHandler
break DefaultHandler

# Set a breakpoint at HardFault
break HardFault

# Continue running until we hit the main breakpoint
continue

# Step from the trampoline code in entry into main
step
