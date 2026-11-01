
# SPI Drone Strike

One SPI master sends commands to four slaves and together they act out a drone hitting a target. There's a Python HUD on top (inspired by the COD aerial strike view) so you can aim, lock and fire instead of typing hex.

Everything is Verilog except `gui/strike.py`. Part is xc7a100tcsg324-1 (Artix-7), but you don't need a board, it all runs in the Vivado simulator.

## **How it works**

```
HUD (python) -> SPI master -> slave 1  flight ctrl   (drone state, aim servo)
                           -> slave 2  target ctrl   (search, found, lock, impact)
                           -> slave 3  telemetry     (mission + hit count on 7-seg)
                           -> slave 4  fault/game    (buzzer, warning leds)
```

SPI mode 0, 16 bit frames, `{cmd, dat}` msb first. The slave sends its status byte back on MISO in the same frame.

### **Commands**

| Cmd  | Meaning         | What it does |
|------|-----------------|--------------|
| `01` | arm             | slave 1: idle to armed |
| `02` | launch          | slave 1: armed to airborne |
| `03` | start mission   | slave 2: `dat` is the target {x,y}, starts searching |
| `04` | target detect   | slave 2: `dat` is your aim {x,y}, locks only if within 1 cell |
| `05` | execute hit     | slave 1 fires, slave 2 impact (only if LOCKED) |
| `06` | return home     | |
| `07` | abort / fault   | slave 4: `dat` sets the warning leds |
| `08` | reset           | `dat[0]=1` on slave 3 also clears the score |
| `09` | aim             | added by me, `dat` is aim {x,y}, moves the drone servo |

### **Target sequence**

Slave 2 goes SEARCHING, FOUND, LOCKING, LOCKED, IMPACT. When you send `04` it checks your aim against the real target position and only starts locking if you're within one cell. `05` is ignored unless it's LOCKED, so firing early is just a miss.

## **Files**

```
rtl/   spi_m, spi_s, s1_fly, s2_tgt, s3_tel, s4_flt   <- the actual SPI system
       top, u_rx, u_tx, servo, sseg                   <- only needed for the board
sim/   tb.v, tb_x.v, tb_live.v, xlive.tcl, trace_sample.txt
gui/   strike.py
xdc/   nexys_a7.xdc
```

The uart files are only there so a PC can talk to the master on a real board. The SPI part doesn't depend on them.

## **Running it**

Needs `pip install pygame numpy pyserial` and python 3.13 or older (pygame doesn't install on newer ones yet).

| Mode | How | Needs Vivado |
|------|-----|--------------|
| Plain | `python strike.py` | no |
| Check the verilog | run `tb.v` in Vivado | yes |
| Replay | `python strike.py --replay trace.txt` | only to make the trace |
| Live | `python strike.py --vivado` | yes |
| Board | `python strike.py COM5` | to build the bitstream |

### **Plain**
Uses a python copy of the slave logic, nothing else to set up.

### **Check the verilog**
Add everything in `rtl/` as design sources and `sim/tb.v` as a simulation source, run behavioral sim, then `run all`. It prints each state next to what it should be, and writes `trace.txt`.

### **Replay**
Copy `trace.txt` next to `strike.py` and run the replay command. The HUD plays back what the Verilog simulation did.

### **Live**
Set `tb_x` as the simulation top instead (don't `run all`). In the Vivado tcl console `cd` to the sim folder and `source xlive.tcl`, then start `strike.py --vivado`. Sim time is slowed so 1 ms of simulation = 1 second on screen (`--speed` changes it).

### **Board**
Build `top.v` with the xdc, program it, then run with your COM port. I haven't been able to try this part on hardware.

## **Controls**

| Key | Action |
|-----|--------|
| mouse | aim the crosshair |
| `1` | arm |
| `2` | launch + start mission |
| `SPACE` | lock (once the target is found) |
| `F` | fire |
| `R` | return home |
| `X` | abort |
| `N` | new mission |
| `Z` | clear score |
| `M` | mute |

Order for a mission: `1`, `2`, wait for the red box to show up (about 2 s), put the crosshair on it, `SPACE`, wait for LOCKED, `F`.
